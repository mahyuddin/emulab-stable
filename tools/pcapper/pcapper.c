/*
 * EMULAB-COPYRIGHT
 * Copyright (c) 2000-2004 University of Utah and the Flux Group.
 * All rights reserved.
 */

/*
 * pcapper.c - Program to count the number of various types of IP packets
 * traveling accross a node's interfaces.
 *
 * TODO:
 *     Allow counting packets based upon tcpdump-style filter expressions
 *     More fine-grained locking
 */

/*
 * These seem to make things happier when compiling on Linux
 */
#ifdef __linux__
#define __PREFER_BSD
#define __USE_BSD
#define __FAVOR_BSD
#define uh_ulen len
#define th_off doff
#endif

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/ioctl.h>

#ifdef __linux__
#include <linux/sockios.h>
#else
#include <sys/sockio.h>
#endif

#include <netinet/in_systm.h>
#include <net/ethernet.h>
#include <net/if.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <netinet/tcp.h>
#include <netinet/udp.h>
#include <arpa/inet.h>

#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <pcap.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifdef EVENTSYS
#include "event.h"
#include "tbdefs.h"
#include "log.h"
#endif

#define PORT 4242
#define MAX_INTERFACES 16
#define MAX_FILES 16
#define MAX_CLIENTS 8

/*
 * Program run to determine the control interface.
 */
#define CONTROL_IFACE CLIENT_BINDIR "/control_interface"

/*
 * Wire overhead not seen by pcapper:
 *	interframe gap (12) + preamble (8) + CRC (4)
 */
#define INVISIBLE_ETHSIZE	24

/*
 * A struct definitions shamelessly stolen from tcpdump.org
 */

/* Ethernet header */
struct sniff_ethernet {
	u_char ether_dhost[ETHER_ADDR_LEN]; /* Destination host address */
	u_char ether_shost[ETHER_ADDR_LEN]; /* Source host address */
	u_short ether_type; /* IP? ARP? RARP? etc */
};

#ifdef __linux__
#undef VETH
#endif

#ifdef VETH

#ifndef ETHERTYPE_VETH
#define ETHERTYPE_VETH	0x80FF
#endif

/* Encapsulated ethernet header */
struct sniff_veth {
	/* physical info */
	u_char ether_dhost[ETHER_ADDR_LEN]; /* Destination host address */
	u_char ether_shost[ETHER_ADDR_LEN]; /* Source host address */
	u_short ether_type; /* VETH */
	/* virtual info */
	u_short veth_tag;
	u_char veth_dhost[ETHER_ADDR_LEN]; /* Destination host address */
	u_char veth_shost[ETHER_ADDR_LEN]; /* Source host address */
	u_short veth_type; /* IP? ARP? RARP? etc */
};
#endif

/*
 * Arguments to the readpackets function - passed in a struct since
 * pthread-starting functions take a single void* as a parameter.
 */
struct readpackets_args {
	u_char index;
	char *devname;
	char *bpf_filter;
};

/*
 * Arguments to the feedclient function.
 */
struct feedclient_args {
	int cli;
	int fd;
	int interval;
};

/*
 * Counts that we keep per-interface, per-interval.
 */
struct counter {
	unsigned int icmp_bytes;
	unsigned int tcp_bytes;
	unsigned int udp_bytes;
#ifdef VETH
	unsigned int veth_bytes;
#endif
	unsigned int other_bytes;

	unsigned int icmp_packets;
	unsigned int tcp_packets;
	unsigned int udp_packets;
#ifdef VETH
	unsigned int veth_packets;
#endif
	unsigned int other_packets;
};

/*
 * Per-interface, per-interval structure, that keeps track of the next
 * interval as where, and when they begin and end.
 */
struct interface_counter {
	/*
	 * The start and end times for this interval, so that we can tell if
	 * a packet got noticed way too late, or if the client-feeding thread
	 * has missed its deadline, and we need to roll over into the next
	 * interval.
	 */
	struct timeval start_time;
	struct timeval rollover;

	/*
	 * Client-feeding threads report data from this_interval. But, if the
	 * interface-watching thread notices that the rollover time has passed,
	 * it counts the packets toward the next_interval. Rather than zeroing
	 * out this_interval after reporting it, the client-feeding threads
	 * copy in next_interval.
	 */
	struct counter this_interval;
	struct counter next_interval;
};

/*
 * Forward declarations
 */
void *readpackets(void *args);
void *feedclient(void *args);
void *runeventsys(void *args);
void got_packet(u_char *args, const struct pcap_pkthdr *header,
	const u_char *packet);
int getaddr(char *dev, struct in_addr *addr);
#ifdef EVENTSYS
static void
callback(event_handle_t handle,
	event_notification_t notification, void *data);
#endif

/*
 * Number of interfaces we've detected, and their names.
 */
int interfaces = 0;
char interface_names[MAX_INTERFACES][1024];

/*
 * Number of packets that are discovered in the correct interval, and those
 * that come in "early" (ie. after the rollover time, but before the client-
 * feeding thread has woken up.) For statistical purposes.
 */
int ontime_packets = 0, early_packets = 0;

/*
 * Nonzero if we're supposed to count payload only
 */
int payload_only = 0;

/*
 * Nonzero if we're supposed to add ethernet headers to the packet size
 */
int add_ethernet = 0;

/*
 * Nonzero if we're supposed to add ALL ethernet overhead to the packet size
 */
int add_all_ethernet = 0;

/*
 * Nonzero if we're supposed to _not_ count zero-sized packets in the
 * packet counts (obviously, they're already ignored in the byte counts.
 */
int no_zero = 0;

/*
 * Whether we should include or skip interfaces that have no IP address
 */
int include_ipless_interfaces = 0;

#ifdef EVENTSYS
/*
 * Time to subtract out of each timestamp reported to clients - this allows
 * us to report times relative to event system time start events.
 */
struct timeval start_time;

/*
 * 1 if we're adjusting timestamps by start_time, 0 otherwise
 */
int adjust_time = 0;

/*
 * A barrier, so that the main thread can wait for time to start
 */
pthread_cond_t time_started;
#endif

/*
 * For getopt()
 */
extern char *optarg;
extern int optind;
extern int optopt;
extern int opterr;
extern int optreset;

/*
 * Lock used to make sure that the threads don't clobber the packet counts.
 * We just use one big fat lock for all of them.
 */
pthread_mutex_t lock;

/*
 * Looks like libpcap has some re-entrance problems - let's only call dispatch
 * on one at a time
 */
pthread_mutex_t dispatch_lock;

/*
 * Condition variable for device threads to wait on for activity.
 */
pthread_cond_t cond;

/*
 * Pakcet counts for the three types of packets that we care about. 
 */
struct interface_counter counters[MAX_CLIENTS][MAX_INTERFACES];

/*
 * Keep track of the pcap devices, since we need them for things like
 * getting counts of packets dropped by the kernel.
 */
pcap_t *pcap_devs[MAX_INTERFACES];

/*
 * An array of 'bools', indicating if any client is using that number.
 */
int client_connected[MAX_CLIENTS];

/*
 * Number of active clients.  When count is zero, the device is closed.
 */
volatile int active;

int MAX(int a, int b) { if ((a) > (b)) return (a); else return (b); }

void usage(char *progname) {
    char *short_usage = "Usage: %s [-f filename] [-i interval] [-p] "
#ifdef EVENTSYS
			"[-e eid/pid] "
#endif
			"[interfaces...]\n"
                        "       %s [options] -t interface 'filter' ... ";
    char *long_usage = "-f filename   Log output to a file\n"
    		       "-i interval   When logging to a file, the interval "
			   "(in ms) to report\n"
		       "-p            Count only payload (not header) size\n"
		       "-n            Add in ethernet header size\n"
		       "-N            Add in all ethernet overhead\n"
		       "-z            Don't count zero-length packets\n"
		       "-o            Print output to stdout\n"
		       "-t            tcpdump mode\n"
		       "-b filter     Use the given bpf filter\n"
		       "-I            Include interfaces that have no IP "
			             "address\n"
#ifdef EVENTSYS
		       "-e pid/eid    Wait for a time start for experiment\n"
		       "-s server     Use <server> for event server\n"
#endif
		       "interfaces... A list of interfaces to monitor\n";

    fprintf(stderr,short_usage,progname,progname);
    fprintf(stderr,long_usage);
    exit(-1);
}

/*
 * XXX: Break up into smaller chunks
 */
int main (int argc, char **argv) {
	pthread_t thread;
	int sock;
	struct protoent *proto;
	struct sockaddr_in address;
	struct in_addr ifaddr;
	struct hostent *host;
	int i;
	struct sigaction action;
	int limit_interfaces;
	struct ifconf ifc;
	void  *ptr;
	char lastname[IFNAMSIZ];
	char *filenames[MAX_FILES];
	int filetime;
	char ch;
	char *event_server;
	char *global_bpf_filter;
	int tcpdump_mode;
	int interface_it;
#ifdef EVENTSYS
	char *exp;
	address_tuple_t tuple;
#endif
#ifdef EMULAB
	FILE *control_interface;
	char control[1024];
#endif
#ifdef DROPROOT
	uid_t uid;
#endif
	/*
	 * Defaults for command-line arugments
	 */
	bzero(filenames,sizeof(filenames));
	filetime = 1000;
#ifdef EMULAB
	event_server = "localhost";
#else
	event_server = NULL;
#endif

#ifdef EVENTSYS
	exp = 0;
#endif

	tcpdump_mode = 0;
	global_bpf_filter = NULL;

	/*
	 * Process command-line arguments
	 */
	while ((ch = getopt(argc, argv, "f:i:e:hpnNzs:otb:I")) != -1)
		switch(ch) {
		case 'f':
			/* Find the first empty slot */
			for (i = 0; filenames[i] != NULL; i++) {}
			filenames[i] = optarg;
			break;
		case 'i':
			filetime = atoi(optarg);
			break;
		case 'p':
			payload_only = 1;
			break;
		case 'n':
			add_ethernet = 1;
			break;
		case 'N':
			add_all_ethernet = 1;
			break;
		case 'z':
			no_zero = 1;
			break;
		case 't':
			tcpdump_mode = 1;
			break;
		case 'b':
			global_bpf_filter = optarg;
			break;
		case 'o':
			/* Find the first empty slot */
			for (i = 0; filenames[i] != NULL; i++) {}
			filenames[i] = "-";
			break;

#ifdef EVENTSYS
		case 'e':
			adjust_time = 1;
			exp = optarg;
			break;
		case 's':
			event_server = optarg;
			break;

#endif
		case 'h':
			usage(argv[0]);
			break;
		case 'I':
			include_ipless_interfaces = 1;
			break;
		default:
			fprintf(stderr,"Bad argument\n");
			usage(argv[0]);
			break;
		}
	argc -= optind;
	argv += optind;

	/*
	 * If they give any more arguments, we take those as interface/hostname
	 * names to match against, and skip all others.
	 */
	if (argc > 0) {
	    	limit_interfaces = 1;
	} else {
	    	limit_interfaces = 0;
	}

	if (tcpdump_mode && (!argc || (argc % 2))) {
	    usage(argv[0]);
	}

	/*
	 * Zero out all packet counts and other arrays.
	 */
	bzero(counters,sizeof(counters));
	bzero(pcap_devs,sizeof(pcap_devs));
	bzero(client_connected,sizeof(client_connected));

	pthread_mutex_init(&lock,NULL);
	pthread_mutex_init(&dispatch_lock,NULL);
	pthread_cond_init(&cond,NULL);

#ifdef EMULAB
	/*
	 * Find out which interface is the control net
	 */
	if ((control_interface = popen(CONTROL_IFACE,"r")) >= 0) {
		if (!fgets(control,1024,control_interface)) {
			fprintf(stderr,"Unable to determine control "
					"interface\n");
			control[0] = '\0';
		}

		pclose(control_interface);

		/*
		 * Chomp off the newline
		 */
		if (control[strlen(control) -1] == '\n') {
			control[strlen(control) -1] = '\0';
		}
		
	} else {
		fprintf(stderr,"Unable to determine control interface\n");
		control[0] = '\0';
	}

#endif

	/*
	 * Open a socket to do our ioctl()s on
	 */

	if ((sock = socket(PF_INET, SOCK_DGRAM, 0)) < 0) {
		perror("socket");
		return (1);
	}

	/*
	 * Use the SIOCGIFCONF ioctl to get a list of all interfaces on
	 * this system.
	 * XXX: The size used is totally arbitrary - this should be done in
	 * a loop with increasing sizes, as in Stevens' book.
	 * NOTE: Linux (oh so helpfully) only gives back interfaces that
	 * are up in response to SIOCGIFCONF
	 */
	ifc.ifc_buf = malloc(MAX_INTERFACES * 100 * sizeof (struct ifreq));
	ifc.ifc_len = MAX_INTERFACES * 100 * sizeof (struct ifreq);
	if (ioctl(sock,SIOCGIFCONF,&ifc) < 0) {
		perror("SIOCGIFCONF");
		exit(1);
	}

	strcpy(lastname,"");

	/*
	 * Go through the list of interfaces, and fork off packet-reading
	 * threads, etc. as appropriate.
	 */
	for (ptr = ifc.ifc_buf; ptr < (void*)(ifc.ifc_buf + ifc.ifc_len); ) {
		char hostname[1024];
		char *name;
		struct ifreq *ifr, flag_ifr;

		/*
		 * Save the current position, and move ptr along
		 */
		ifr = (struct ifreq *)ptr;

		/*
		 * Great, no sa_len in Linux. This will be broken for things
		 * other than IPv4
		 */
#ifdef __linux__
		ptr = ptr + sizeof(ifr->ifr_name) +
			MAX(sizeof(struct sockaddr),sizeof(ifr->ifr_addr));
#else
		ptr = ptr + sizeof(ifr->ifr_name) +
			MAX(sizeof(struct sockaddr),ifr->ifr_addr.sa_len);
#endif

		/*
		 * Only care about INET4 interfaces
		 */
		if (!include_ipless_interfaces) {
		    if (ifr->ifr_addr.sa_family != AF_INET)
			    continue;
		}

		name = ifr->ifr_name;
		if (!strcmp(name,lastname)) {
			/*
			 * If we get duplicates (IP aliases), skip them
			 */
			continue;
		} else {
			strcpy(lastname,name);
		}

		/*
		 * Get interface flags
		 */
		bzero(&flag_ifr,sizeof(flag_ifr));
		strcpy(flag_ifr.ifr_name, name);
		if (ioctl(sock,SIOCGIFFLAGS, (caddr_t)&flag_ifr) < 0) {
			perror("Getting interface flags");
			exit(1);
		}

		printf("Interface %s is ... ",name);

#ifdef EMULAB
		if (control && !strcmp(control,name)) {
			/* Skip control net */
			printf("control\n");
		} else
#endif
		if (flag_ifr.ifr_flags & IFF_LOOPBACK) {
			/* Skip loopback */
			printf("loopback\n");
		} else if (flag_ifr.ifr_flags & IFF_UP) {
			struct readpackets_args *args;
			struct sockaddr_in *sin;
			int matched_filters = 0;

			/*
			 * Get theIP address for the interface.
			 */
#if 1
			sin = (struct sockaddr_in *) &ifr->ifr_addr;
			ifaddr = sin->sin_addr;
#else
			if (getaddr(name,&ifaddr)) {
				/* Has carrier, but no IP */
				if (!include_ipless_interfaces) {
					printf("down (with carrier)\n");
					continue;
				}
			}
#endif

			/*
			 * Grab the 'hostname' for the interface, but fallback
			 * to IP if we can't get it.
			 */
			host = gethostbyaddr((char*)&ifaddr,
					     sizeof(ifaddr),AF_INET);

			if (host) {
				strcpy(hostname,host->h_name);
			} else {
				strcpy(hostname,inet_ntoa(ifaddr));
			}

			/*
			 * If we're in 'tcmdump mode' we may have to do this
			 * more than once
			 */
			interface_it = 0;
			do {
				char *bpf_filter = global_bpf_filter;

				/*
				 * In 'tcpdump mode', we find out if this is
				 * one of the interfaces we're dealing with,
				 * and if so, grab its bpf filter string
				 */
				if (tcpdump_mode) {
					int matched = 0;
					if (!(strcmp(name,argv[interface_it]))) {
						matched = 1;
						bpf_filter = argv[interface_it +1];
						matched_filters++;
					}
					interface_it+= 2;
					if (!matched) {
						continue;
					}
					/*
					 * Copy it into the global interfaces list
					 */
					strcpy(interface_names[interfaces],hostname);
					strcat(interface_names[interfaces]," '");
					strcat(interface_names[interfaces],bpf_filter);
					strcat(interface_names[interfaces],"'");
					strcat(interface_names[interfaces],"\n");
					
					printf("watched ");

				} else { 
					/*
					 * If we're limiting the interfaces we
					 * look at, skip this one unless it
					 * matches one of the arguments given
					 * by the user
					 */
					if (limit_interfaces) {
						int j;
						for (j = 0; j < argc; j++) {
							if (!(strcmp(name,argv[j])) ||
						             (strstr(hostname,argv[j]))) {
								break;
							}
						}
						if (j == argc) {
							printf("skipped\n");
							continue;
						}
					}
					/*
					 * Copy it into the global interfaces list
					 */
					strcpy(interface_names[interfaces],hostname);
					strcat(interface_names[interfaces],"\n");

					printf("up\n");
				}

				if (interfaces >= MAX_INTERFACES) {
					printf("up, ignored (too many interfaces)\n");
					continue;
				}


				/*
				 * Start up a new thread to read packets from this
				 * interface.
				 */
				args = (struct readpackets_args*)
					malloc(sizeof(struct  readpackets_args));
				args->devname = (char*)malloc(strlen(name) + 1);
				args->bpf_filter = bpf_filter;
				strcpy(args->devname,name);
				args->index = interfaces;
				if (pthread_create(&thread,NULL,readpackets,args)) {
					fprintf(stderr,"Unable to start thread!\n");
					exit(1);
				}

				interfaces++;
			} while (tcpdump_mode && (interface_it < argc));

			if (tcpdump_mode) {
				if (matched_filters == 0) {
					printf("skipped");
				}
				printf("\n");
			}

		} else {
			/* Skip interfaces that don't have carrier */
			printf("down\n");
		}
	}
	close(sock);

	if (interfaces <= 0) {
		fprintf(stderr,"No interfaces to monitor!\n");
		exit(-1);
	}

#ifdef DROPROOT
	if (geteuid() == 0) {
	    uid = getuid();
	    seteuid(uid);
	}
#endif

	/*
	 * Wait for time to start
	 */
#ifdef EVENTSYS
	if (adjust_time) {
	    event_handle_t ehandle;
	    char server_string[1024];

	    printf("Waiting for time start in experiment %s\n",exp);
	    tuple = address_tuple_alloc();
	    if (tuple == NULL) {
		fatal("could not allocate an address tuple");
	    }      
	    tuple->host      = ADDRESSTUPLE_ANY;
	    tuple->site      = ADDRESSTUPLE_ANY;
	    tuple->group     = ADDRESSTUPLE_ANY;
	    tuple->expt      = exp ? exp : ADDRESSTUPLE_ANY;
	    tuple->objtype   = TBDB_OBJECTTYPE_TIME;
	    tuple->objname   = ADDRESSTUPLE_ANY;
	    tuple->eventtype = TBDB_EVENTTYPE_START;

	    pthread_cond_init(&time_started,NULL);

	    if (event_server) {
		snprintf(server_string,sizeof(server_string),"elvin://%s",
			event_server);
	    } else {
		server_string[0] = '\0';
	    }

	    ehandle = event_register(server_string,0);
	    if (ehandle == NULL) {
		fatal("could not register with event system");
	    }
	    if (!event_subscribe(ehandle, callback, tuple, NULL)) {
		fatal("could not subscribe to TIME events");
	    }
	    address_tuple_free(tuple);

	    /*
	     * We put the event system main loop into a new thread, since
	     * we can't use the threaded API with linuxthreads
	     */
	    if (pthread_create(&thread,NULL,runeventsys,&ehandle)) {
		fprintf(stderr,"Unable to start thread!\n");
		exit(1);
	    }
	    pthread_cond_wait(&time_started,&lock);
	    pthread_mutex_unlock(&lock);
	}
#endif

	/*
	 * If they gave us filenames to log to, open them up.
	 */
	for (i = 0; filenames[i] != NULL; i++) {
		int fd;
		struct feedclient_args *args;

		/*
		 * Allow use the of '-' for stdout
		 */
		if (!strcmp(filenames[i],"-")) {
		    fd = 1;
		} else {
		    fd = open(filenames[i],O_WRONLY | O_CREAT | O_TRUNC);
		    if (fd < 0) {
			perror("Opening savefile");
			exit(1);
		    }
		}

		/*
		 * Start a new thread to feed the file
		 */
		args = (struct feedclient_args*)
			malloc(sizeof(struct feedclient_args));
		args->fd = fd;
		args->cli = 0;
		args->interval = filetime;
		client_connected[i] = 1;
		active = 1;
		pthread_create(&thread,NULL,feedclient,args);
                pthread_cond_broadcast(&cond);
	}

	/*
	 * Create a socket to listen on, so that we can tell remote
	 * applications about the counts we're getting.
	 */
	proto = getprotobyname("TCP");
	sock = socket(AF_INET,SOCK_STREAM,proto->p_proto);
	if (sock < 0) {
		perror("Creating socket");
		exit(1);
	}

	//i++;
	if (setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &i, sizeof(int)) < 0)
		perror("SO_REUSEADDR");

	address.sin_family = AF_INET;
	address.sin_port = htons(PORT);
	address.sin_addr.s_addr = INADDR_ANY;

	if (bind(sock,(struct sockaddr*)(&address),sizeof(address))) {
		perror("Binding socket");
		exit(1);
	}

	if (listen(sock,-1)) {
		perror("Listening on socket");
		exit(1);
	}

	/*
	 * Ignore SIGPIPE - we'll detect the remote end closing the connection
	 * by a failed write() .
	 */
	action.sa_handler = SIG_IGN;
	sigaction(SIGPIPE,&action,NULL);

	/*
	 * Loop forever, so that we can handle multiple clients connecting
	 */
	while (1) {
		int fd;
		struct feedclient_args *args;
		struct sockaddr client_addr;
		size_t client_addrlen;

		fd = accept(sock,&client_addr,&client_addrlen);

		if (fd < 0) {
			perror("accept");
			continue;
		}
		/*
		 * Pick a client number
		 */
		pthread_mutex_lock(&lock);
		for (i = 0; i < MAX_CLIENTS; i++) {
			if (!client_connected[i]) {
				/* printf("New client is %i\n",i); */
				client_connected[i] = 1;
				if (active >= MAX_CLIENTS) {
					fprintf(stderr, "active count screwed\n");
					exit(1);
				}
				if (++active == 1)
					pthread_cond_broadcast(&cond);
#if 0
				printf("Now have %d clients\n", active);
#endif
				break;
			}
		}
		pthread_mutex_unlock(&lock);
		
		if (i == MAX_CLIENTS) {
			/*
			 * Didn't find a free slot
			 */
			fprintf(stderr,"Too many clients\n");
			close(fd);
		} else {
			args = (struct feedclient_args*)
				malloc(sizeof(struct feedclient_args));
			args->fd = fd;
			args->cli = i;
			args->interval = 0;
			pthread_create(&thread,NULL,feedclient,args);
		}
	}

}

/*
 * Feed data back to a client - since this is done through a file
 * descriptor, the client can be a socket, a file, etc.
 */
void *feedclient(void *args) {
	struct feedclient_args *s_args;
	int cli;
	int fd;
	char inbuf[1024];
	char outbuf[1024];
	int interval;
	int i;
	struct timeval next_time, now, interval_tv;
	int dropped;
	int called = 0;

	s_args = (struct feedclient_args*)args;
	cli = s_args->cli;
	fd = s_args->fd;
	interval = s_args->interval;

	free(args);

	dropped = 0;
	
	/*
	 * The first thing we send is the number of interfaces,
	 * followed by the name of each one (1 per line)
	 */
	sprintf(outbuf,"%i\n",interfaces);
	write(fd,outbuf,strlen(outbuf));

	for (i  = 0; i < interfaces; i++) {
		write(fd,interface_names[i],strlen(interface_names[i]));
	}

	/*
	 * Now, we wait for the client to tell us how long, in ms, they
	 * want to wait in between reports. If we were given an interval in
	 * our arguments (presumably because the output fd is write-only),
	 * forgo this step.
	 */
	if (!interval) {
		read(fd,inbuf,1024);
		interval = atoi(inbuf);
	}

	/*
	 * Convert to microseconds.
	 */
	interval *= 1000;

	interval_tv.tv_usec = interval % 1000000;
	interval_tv.tv_sec = interval / 1000000;

	/*
	 * Zero out the packet counts before the first report
	 */
	pthread_mutex_lock(&lock);
	bzero(counters[cli], sizeof(counters[cli]));
	pthread_mutex_unlock(&lock);

	gettimeofday(&now,NULL);
	timeradd(&now,&interval_tv,&next_time);

	while (1) { /* Repeat until client disconnects */
		int used = 0;
		int writerv;
		struct timeval sleepintr;
		struct timeval timestamp;
		struct timespec sleepintr_ts;
		struct pcap_stat ps;

		/*
		 * Zero out the packet counts, and set up the times in the
		 *
		 */
		pthread_mutex_lock(&lock);
		gettimeofday(&now,NULL);
		for (i  = 0; i < interfaces; i++) {
			bcopy(&(counters[cli][i].next_interval),
			      &(counters[cli][i].this_interval),
			      sizeof(counters[cli][i].next_interval));
			bzero(&(counters[cli][i].next_interval),
			      sizeof(counters[cli][i].next_interval));
			bcopy(&(next_time),&(counters[cli][i].start_time),
			      sizeof(now));
			bcopy(&(next_time),&(counters[cli][i].rollover),
			      sizeof(next_time));
		}
		pthread_mutex_unlock(&lock);

		/*
		 * Figure out how long to sleep for
		 */
		gettimeofday(&now,NULL);
		timersub(&next_time,&now,&sleepintr);

		/*
		 * Have to convert to a timespec, since nanosleep takes a
		 * timespec, but all the other functions I want to use deal
		 * in timeval's
		 */
		sleepintr_ts.tv_sec = sleepintr.tv_sec;
		sleepintr_ts.tv_nsec = sleepintr.tv_usec * 1000;

		nanosleep(&sleepintr_ts,NULL);
		gettimeofday(&now,NULL);

		/*
		 * Figure out the next time we'll be waking up
		 */
		timeradd(&next_time,&interval_tv,&next_time);

		timestamp.tv_sec = now.tv_sec;
		timestamp.tv_usec = now.tv_usec;

#ifdef EVENTSYS
		if (adjust_time) {
		    timersub(&now,&start_time,&timestamp);
		}
#endif

		/*
		 * Put a timestamp on the beginning of each line
		 */
		used += sprintf((outbuf +used),"%li.%06li ", timestamp.tv_sec,
				timestamp.tv_usec);

		/*
		 * Gather up the counts for each interface into
		 * a string.
		 */
		pthread_mutex_lock(&lock);
		for (i  = 0; i < interfaces; i++) {
			used += sprintf((outbuf +used),
#ifdef VETH
				"(icmp:%i,%i tcp:%i,%i udp:%i,%i other:%i,%i veth:%i,%i) ",
#else
				"(icmp:%i,%i tcp:%i,%i udp:%i,%i other:%i,%i) ",
#endif
				counters[cli][i].this_interval.icmp_bytes,
				counters[cli][i].this_interval.icmp_packets,
				counters[cli][i].this_interval.tcp_bytes,
				counters[cli][i].this_interval.tcp_packets,
				counters[cli][i].this_interval.udp_bytes,
				counters[cli][i].this_interval.udp_packets,
				counters[cli][i].this_interval.other_bytes,
				counters[cli][i].this_interval.other_packets
#ifdef VETH
				,counters[cli][i].this_interval.veth_bytes
				,counters[cli][i].this_interval.veth_packets
#endif
					);
		}
		pthread_mutex_unlock(&lock);

		/*
		 * Drop information is not kept per-interface, so we just
		 * grab it from one of them.  Note that since we close all
		 * devices when no one is active, it is possible that the
		 * device threads have not yet reopened their devices when
		 * we reach here.
		 */
		if (pcap_devs[0] == 0 || pcap_stats(pcap_devs[0], &ps)) {
			if (!called) {
				fprintf(stderr,
					"WARNING: unable to get drop stats\n");
				called = 1;
			}
		}

		/*
		 * Put the difference between the last and current kernel drop
		 * count on the end of the line.
		 */
		used += sprintf((outbuf + used),"(dropped:%i)",
				ps.ps_drop - dropped);
		dropped = ps.ps_drop;

		/*
		 * Make it more human-readable
		 */
		strcat(outbuf,"\n");

		writerv = write(fd,outbuf,strlen(outbuf));
		if (writerv < 0) {
			if (errno != EPIPE) {
				perror("write");
			}
			/* printf("Client %i disconnected\n",cli);*/
			pthread_mutex_lock(&lock);
			if (client_connected[cli] == 0 || active <= 0) {
				fprintf(stderr, "active count screwed\n");
				exit(1);
			}
			client_connected[cli] = 0;
			active--;
			/* printf("Now have %d clients\n", active); */
			pthread_mutex_unlock(&lock);
			/*
			 * Client disconnected - exit the loop
			 */
			break;
		}
	}

	return NULL;
}

/*
 * Start the pcap_loop for an interface
 */
void *readpackets(void *args) {
	char ebuf[1024];
	pcap_t *dev;
	struct readpackets_args *sargs;
	int size;
	bpf_u_int32 mask, net;
	struct bpf_program filter;
	char *bpf_filter;

	/*
	 * How much of the packet we want to grab.
	 */
#ifdef VETH
	size = sizeof(struct sniff_veth);
#else
	size = sizeof(struct sniff_ethernet);
#endif
	size += sizeof(struct ip) + sizeof(struct tcphdr);
	    
	sargs = (struct readpackets_args*)args;

 again:
	pthread_mutex_lock(&lock);
	while (active == 0)
		pthread_cond_wait(&cond, &lock);
	pthread_mutex_unlock(&lock);

	/*
	 * NOTE: We set the timeout to a full second - if we set it lower, we
	 * don't get to see packets until a certain number have been buffered
	 * up, for some reason.
	 */
	dev = pcap_open_live(sargs->devname, size, 1, 1, ebuf);
	if (!dev) {
		fprintf(stderr, "Failed to open %s: %s\n",
			sargs->devname, ebuf);
		exit(1);
	}

	/*
	 * Record our pcap device into the global array, so that it can be
	 * found by other processes.
	 */
	pcap_devs[sargs->index] = dev;

	bpf_filter = sargs->bpf_filter;

	/*
	 * Put an empty filter on the device, or we get nothing (but only
	 * in Linux) - how frustrating!
	 */
#ifdef __linux__
	if (!bpf_filter) {
	    bpf_filter = "";
	}
#endif

	if (bpf_filter) {
	    pcap_lookupnet(sargs->devname, &net, &mask, ebuf);
	    if (pcap_compile(dev, &filter, bpf_filter, 0, net)) {
		    fprintf(stderr,"Error compiling BPF filter '%s'\n",
				    bpf_filter);
		    exit(1);
	    }
	    pcap_setfilter(dev, &filter);
	    pcap_freecode(&filter);
	}

	/*
	 * We don't bother to lock the access to active.  If it gets cleared
	 * immediately after a test, we make an extra loop.  If it gets set
	 * immediately after, we do an extra open/close of the device.
	 * Neither case is life threatening.
	 */
	while (active > 0) {
		if (pcap_dispatch(dev, -1, got_packet, &sargs->index) < 0) {
			pcap_perror(dev,"pcap_dispatch failed: ");
			exit(1);
		}
	}
	pcap_close(dev);
	goto again;
}

/*
 * Callback for pcap_loop - gets called every time a packet is recieved, and
 * adds its byte count to the total.
 */
void got_packet(u_char *args, const struct pcap_pkthdr *header,
	const u_char *packet) {

	struct sniff_ethernet *ether_pkt;
	struct ip *ip_pkt; 
	int length;
	int type = 0;
	int index;
	int i;
	int hdrsize;

	/*
	 * We only care about IP packets
	 */
	ether_pkt = (struct sniff_ethernet*)packet;
	switch (ntohs(ether_pkt->ether_type)) {
	case ETHERTYPE_IP:
		hdrsize = sizeof(struct sniff_ethernet);
		break;
#ifdef VETH
	case ETHERTYPE_VETH:
		/* XXX one level only */
		if (ntohs(((struct sniff_veth *)packet)->veth_type) !=
		    ETHERTYPE_IP)
			return;
		hdrsize = sizeof(struct sniff_veth);
		type = -1;
		break;
#endif
	default:
		return;
	}

	ip_pkt = (struct ip*)(packet + hdrsize);

	/*
	 * Add this packet length to the appropriate total
	 */
	if (!add_ethernet) {
		length = ntohs(ip_pkt->ip_len);
	} else {
		length = ntohs(ip_pkt->ip_len) + hdrsize;
		if (add_all_ethernet) {
			length += INVISIBLE_ETHSIZE;
		}
	}
	if (type == 0)
		type = ip_pkt->ip_p;

#if 0
	printf("got type %d(0x%x), len=%d(0x%x)\n",
	       type, type, length, length);
#endif

	index = *args;

	pthread_mutex_lock(&lock);
	/*
	 * Since multiple clients may be monitoring this interface, we have
	 * to update counts for all of them.
	 */
	for (i = 0; i < MAX_CLIENTS; i++) {
		if (client_connected[i] &&
				timerisset(&(counters[i][index].rollover))) {
			struct counter *count;

			/*
			 * Figure out if this packet is on time, or early
			 */
			if (timercmp(&(header->ts),
				     &(counters[i][index].rollover), <)) {
				count = &(counters[i][index].this_interval);
				ontime_packets += 1;
			} else if (timercmp(&(header->ts),
				        &(counters[i][index].start_time), <)) {
				fprintf(stderr,"Got a REALLY late packet!\n");
			} else {
				count = &(counters[i][index].next_interval);
				early_packets += 1;
			}

#ifdef NO_TS_CORRECTION
			count = &(counters[i][index].this_interval);
#endif

			/*
			printf("OTP: %f (%i,%i)\n",
				ontime_packets*1.0/
					(ontime_packets + early_packets),
				ontime_packets,early_packets);
				*/

			/*
			 * Now, just  add it into the approprate counts
			 */
			switch (type) {
				case 1: 
				    count->icmp_bytes  += length;
				    count->icmp_packets++;
				    break;
				case 6:
				    if (payload_only) {
					/*
					 * Find the TCP header in the packet
					 */
					struct tcphdr *tcp_hdr =
					    (struct tcphdr*)((char*)ip_pkt +
							     ip_pkt->ip_hl*4);
					int hdr_len = ip_pkt->ip_hl *4 +
					    tcp_hdr->th_off *4;
					count->tcp_bytes  += length - hdr_len;
					length = length - hdr_len;
				    } else {
					count->tcp_bytes  += length;
				    }
				    if (no_zero) {
					if (length > 0) {
					    count->tcp_packets++;
					}
				    } else {
					count->tcp_packets++;
				    }

				    break;

				case 17:
				    if (payload_only) {
					/*
					 * Find the UDP header in the packet
					 */
					struct udphdr *udp_hdr =
					    (struct udphdr*)((char*)ip_pkt +
							     ip_pkt->ip_hl*4);
					int pay_len = htons(udp_hdr->uh_ulen) -
					    sizeof(struct udphdr);
					count->udp_bytes  += pay_len;
					length = pay_len;
				    } else {
					count->udp_bytes  += length;
				    }

				    if (no_zero) {
					if (length > 0) {
					    count->udp_packets++;
					}
				    } else {
					count->udp_packets++;
				    }
				    break;
#ifdef VETH
				case -1:
					count->veth_bytes += length;
					count->veth_packets++;
					break;
#endif
				default: count->other_bytes += length;
					 count->other_packets++;
					 break;
			}
		}
	}
	pthread_mutex_unlock(&lock);
}

/*
 * Get the IP address for an interface. Returns the IP in the addr parameter,
 * and returns non-zero if problems were encountered.
 */
int getaddr(char *dev, struct in_addr *addr) {
	struct ifreq ifr;
	int sock;
	struct sockaddr_in *sin;

	/*
	 * Open a socket to do the ioctl() on
	 */
	if ((sock = socket(PF_INET, SOCK_DGRAM, 0)) < 0) {
		perror("socket");
		return (1);
	}

	bzero(&ifr.ifr_addr,sizeof(ifr.ifr_addr));
	strcpy(ifr.ifr_name,dev);

	/*
	 * Do the ioctl
	 */
	if (ioctl(sock, SIOCGIFADDR, (char *) &ifr) < 0) {
		close(sock);
		/*
		 * Don't print this, because it can occur during 'normal'
		 * operation
		 */
		/* perror("SIOCGIFADDR"); */
		return 1;
	} else {
		sin = (struct sockaddr_in *) & ifr.ifr_addr;
		/* printf("Got one: %s\n", inet_ntoa(sin->sin_addr)); */
		*addr = sin->sin_addr;
		close(sock);
		return 0;
	}
}

#ifdef EVENTSYS
/*
 * Callback used for the event system. Resets the experiment start time,
 * and signals the main thread, which may be waiting on the condition
 * variable before it starts
 */
static void
callback(event_handle_t handle,
	         event_notification_t notification, void *data) {

	char objtype[256], eventtype[256];
	int len = 256;

	printf("Received an event\n");
	event_notification_get_objtype(handle, notification, objtype, len);
	event_notification_get_eventtype(handle, notification, eventtype, len);

	if (!strcmp(objtype,TBDB_OBJECTTYPE_TIME) &&
		!strcmp(eventtype,TBDB_EVENTTYPE_START)) {
	    /* OK, time has started */
	    gettimeofday(&start_time,NULL);
	    pthread_cond_signal(&time_started);
	    printf("Event time started at UNIX time %lu.%lu\n",
		    start_time.tv_sec, start_time.tv_usec);
	}
	return;
}

/*
 * Simple function that starts up the event main loop - suitable for use as
 * an argument to pthread_create .
 */
void *runeventsys(void *args) {
    event_main(*((event_handle_t*)args));
    return NULL;
}
#endif
