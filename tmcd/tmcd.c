/*
 * EMULAB-COPYRIGHT
 * Copyright (c) 2000-2003 University of Utah and the Flux Group.
 * All rights reserved.
 */

#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <syslog.h>
#include <signal.h>
#include <stdarg.h>
#include <assert.h>
#include <sys/wait.h>
#include <sys/fcntl.h>
#include <sys/syscall.h>
#include <sys/stat.h>
#include <paths.h>
#include <setjmp.h>
#include <pwd.h>
#include <grp.h>
#include <mysql/mysql.h>
#include "decls.h"
#include "config.h"
#include "ssl.h"
#include "log.h"
#include "tbdefs.h"

#ifdef EVENTSYS
#include "event.h"
#endif

/*
 * XXX This needs to be localized!
 */
#define FSPROJDIR	FSNODE ":" FSDIR_PROJ
#define FSGROUPDIR	FSNODE ":" FSDIR_GROUPS
#define FSUSERDIR	FSNODE ":" FSDIR_USERS
#ifdef  FSDIR_SHARE
#define FSSHAREDIR	FSNODE ":" FSDIR_SHARE
#endif
#define PROJDIR		"/proj"
#define GROUPDIR	"/groups"
#define USERDIR		"/users"
#define NETBEDDIR	"/netbed"
#define SHAREDIR	"/share"
#define RELOADPID	"emulab-ops"
#define RELOADEID	"reloading"
#define FSHOSTID	"/usr/testbed/etc/fshostid"
#define DOTSFS		".sfs"

#define TESTMODE
#define DEFAULTNETMASK	"255.255.255.0"
/* This can be tossed once all the changes are in place */
static char *
CHECKMASK(char *arg)
{
	if (arg && arg[0])
		return arg;

	error("No netmask defined!\n");
	return DEFAULTNETMASK;
}
/* #define CHECKMASK(arg)  ((arg) && (arg[0]) ? (arg) : DEFAULTNETMASK) */

#define DISKTYPE	"ad"
#define DISKNUM		0

/* Compiled in slothd parameters
 *
 * 1 - reg_interval  2 - agg_interval  3 - load_thresh  
 * 4 - expt_thresh   5 - ctl_thresh
 */
#define SDPARAMS        "reg=300 agg=5 load=1 expt=5 ctl=1000"

/* Defined in configure and passed in via the makefile */
#define DBNAME_SIZE	64
#define HOSTID_SIZE	(32+64)
#define DEFAULT_DBNAME	TBDBNAME

int		debug = 0;
static int	verbose = 0;
static int	insecure = 0;
static int	byteswritten = 0;
static char     dbname[DBNAME_SIZE];
static struct in_addr myipaddr;
static char	fshostid[HOSTID_SIZE];
static int	nodeidtoexp(char *nodeid, char *pid, char *eid, char *gid);
static int	checkprivkey(struct in_addr, char *);
static void	tcpserver(int sock);
static void	udpserver(int sock);
static int      handle_request(int, struct sockaddr_in *, char *, int);
static int	makesockets(int portnum, int *udpsockp, int *tcpsockp);
int		client_writeback(int sock, void *buf, int len, int tcp);
void		client_writeback_done(int sock, struct sockaddr_in *client);
MYSQL_RES *	mydb_query(char *query, int ncols, ...);
int		mydb_update(char *query, ...);
static int	safesymlink(char *name1, char *name2);

/* thread support */
#define MAXCHILDREN	20
#define MINCHILDREN	5
static int	numchildren;
static int	maxchildren = 10;
static int	mypid;
static volatile int killme;

/* Output macro to check for string overflow */
#define OUTPUT(buf, size, format...) \
({ \
	int __count__ = snprintf((buf), (size), ##format); \
        \
        if (__count__ >= ((size) - 1)) { \
		error("Not enough room in output buffer! line %d.\n", __LINE__);\
		return 1; \
	} \
	__count__; \
})

/*
 * This structure is passed to each request function. The intent is to
 * reduce the number of DB queries per request to a minimum.
 */
typedef struct {
	int		allocated;
	int		jailflag;
	int		isvnode;
	int		issubnode;
	int		islocal;
	int		iscontrol;
	int		update_accounts;
	char		nodeid[TBDB_FLEN_NODEID];
	char		vnodeid[TBDB_FLEN_NODEID];
	char		pnodeid[TBDB_FLEN_NODEID]; /* XXX */
	char		pid[TBDB_FLEN_PID];
	char		eid[TBDB_FLEN_EID];
	char		gid[TBDB_FLEN_GID];
	char		nickname[TBDB_FLEN_VNAME];
	char		type[TBDB_FLEN_NODETYPE];
	char		class[TBDB_FLEN_NODECLASS];
        char		ptype[TBDB_FLEN_NODETYPE];	/* Of physnode */
	char		pclass[TBDB_FLEN_NODECLASS];	/* Of physnode */
	char		creator[TBDB_FLEN_UID];
	char		swapper[TBDB_FLEN_UID];
	char		syncserver[TBDB_FLEN_VNAME];	/* The vname */
	char		keyhash[TBDB_FLEN_PRIVKEY];
	char		eventkey[TBDB_FLEN_PRIVKEY];
	char		sfshostid[TBDB_FLEN_SFSHOSTID];
	char		testdb[256];
} tmcdreq_t;
static int	iptonodeid(struct in_addr, tmcdreq_t *);
static int	checkdbredirect(tmcdreq_t *);

#ifdef EVENTSYS
int			myevent_send(address_tuple_t address);
static event_handle_t	event_handle = NULL;
#endif

/*
 * Commands we support.
 */
#define COMMAND_PROTOTYPE(x) \
	static int \
	x(int sock, tmcdreq_t *reqp, char *rdata, int tcp, int vers)

COMMAND_PROTOTYPE(doreboot);
COMMAND_PROTOTYPE(donodeid);
COMMAND_PROTOTYPE(dostatus);
COMMAND_PROTOTYPE(doifconfig);
COMMAND_PROTOTYPE(doaccounts);
COMMAND_PROTOTYPE(dodelay);
COMMAND_PROTOTYPE(dolinkdelay);
COMMAND_PROTOTYPE(dohosts);
COMMAND_PROTOTYPE(dohostsV2);
COMMAND_PROTOTYPE(dorpms);
COMMAND_PROTOTYPE(dodeltas);
COMMAND_PROTOTYPE(dotarballs);
COMMAND_PROTOTYPE(dostartcmd);
COMMAND_PROTOTYPE(dostartstat);
COMMAND_PROTOTYPE(doready);
COMMAND_PROTOTYPE(doreadycount);
COMMAND_PROTOTYPE(dolog);
COMMAND_PROTOTYPE(domounts);
COMMAND_PROTOTYPE(dosfshostid);
COMMAND_PROTOTYPE(doloadinfo);
COMMAND_PROTOTYPE(doreset);
COMMAND_PROTOTYPE(dorouting);
COMMAND_PROTOTYPE(dotrafgens);
COMMAND_PROTOTYPE(donseconfigs);
COMMAND_PROTOTYPE(dostate);
COMMAND_PROTOTYPE(docreator);
COMMAND_PROTOTYPE(dotunnels);
COMMAND_PROTOTYPE(dovnodelist);
COMMAND_PROTOTYPE(dosubnodelist);
COMMAND_PROTOTYPE(doisalive);
COMMAND_PROTOTYPE(doipodinfo);
COMMAND_PROTOTYPE(doatarball);
COMMAND_PROTOTYPE(doanrpm);
COMMAND_PROTOTYPE(dontpinfo);
COMMAND_PROTOTYPE(dontpdrift);
COMMAND_PROTOTYPE(dojailconfig);
COMMAND_PROTOTYPE(doplabconfig);
COMMAND_PROTOTYPE(dosubconfig);
COMMAND_PROTOTYPE(doixpconfig);
COMMAND_PROTOTYPE(doslothdparams);
COMMAND_PROTOTYPE(doprogagents);
COMMAND_PROTOTYPE(dosyncserver);
COMMAND_PROTOTYPE(dokeyhash);
COMMAND_PROTOTYPE(doeventkey);
COMMAND_PROTOTYPE(dofullconfig);

/*
 * The fullconfig slot determines what routines get called when pushing
 * pushing out a full configuration. Physnodes get slightly different
 * then vnodes, and at some point we might want to distinguish different
 * types of vnodes (jailed, plab).
 */
#define FULLCONFIG_NONE		0x0
#define FULLCONFIG_PHYS		0x1
#define FULLCONFIG_VIRT		0x2
#define FULLCONFIG_ALL		FULLCONFIG_PHYS|FULLCONFIG_VIRT

struct command {
	char	*cmdname;
	int	fullconfig;	
	int    (*func)(int, tmcdreq_t *, char *, int, int);
} command_array[] = {
	{ "reboot",	  FULLCONFIG_NONE, doreboot },
	{ "nodeid",	  FULLCONFIG_ALL,  donodeid },
	{ "status",	  FULLCONFIG_NONE, dostatus },
	{ "ifconfig",	  FULLCONFIG_ALL,  doifconfig },
	{ "accounts",	  FULLCONFIG_ALL,  doaccounts },
	{ "delay",	  FULLCONFIG_ALL,  dodelay },
	{ "linkdelay",	  FULLCONFIG_ALL,  dolinkdelay },
	{ "hostnamesV2",  FULLCONFIG_NONE, dohostsV2 },	/* This will go away */
	{ "hostnames",	  FULLCONFIG_ALL,  dohosts },
	{ "rpms",	  FULLCONFIG_ALL,  dorpms },
	{ "deltas",	  FULLCONFIG_NONE, dodeltas },
	{ "tarballs",	  FULLCONFIG_ALL,  dotarballs },
	{ "startupcmd",	  FULLCONFIG_ALL,  dostartcmd },
	{ "startstatus",  FULLCONFIG_NONE, dostartstat }, /* Before startstat*/
	{ "startstat",	  FULLCONFIG_NONE, dostartstat },
	{ "readycount",   FULLCONFIG_NONE, doreadycount },
	{ "ready",	  FULLCONFIG_NONE, doready },
	{ "log",	  FULLCONFIG_NONE, dolog },
	{ "mounts",	  FULLCONFIG_ALL,  domounts },
	{ "sfshostid",	  FULLCONFIG_NONE, dosfshostid },
	{ "loadinfo",	  FULLCONFIG_NONE, doloadinfo},
	{ "reset",	  FULLCONFIG_NONE, doreset},
	{ "routing",	  FULLCONFIG_ALL,  dorouting},
	{ "trafgens",	  FULLCONFIG_ALL,  dotrafgens},
	{ "nseconfigs",	  FULLCONFIG_ALL,  donseconfigs},
	{ "creator",	  FULLCONFIG_ALL,  docreator},
	{ "state",	  FULLCONFIG_NONE, dostate},
	{ "tunnels",	  FULLCONFIG_ALL,  dotunnels},
	{ "vnodelist",	  FULLCONFIG_PHYS, dovnodelist},
	{ "subnodelist",  FULLCONFIG_PHYS, dosubnodelist},
	{ "isalive",	  FULLCONFIG_NONE, doisalive},
	{ "ipodinfo",	  FULLCONFIG_NONE, doipodinfo},
	{ "ntpinfo",	  FULLCONFIG_PHYS, dontpinfo},
	{ "ntpdrift",	  FULLCONFIG_NONE, dontpdrift},
	{ "tarball",	  FULLCONFIG_NONE, doatarball},
	{ "rpm",	  FULLCONFIG_NONE, doanrpm},
	{ "jailconfig",	  FULLCONFIG_VIRT, dojailconfig},
	{ "plabconfig",	  FULLCONFIG_VIRT, doplabconfig},
	{ "subconfig",	  FULLCONFIG_NONE, dosubconfig},
        { "sdparams",     FULLCONFIG_PHYS, doslothdparams},
        { "programs",     FULLCONFIG_ALL,  doprogagents},
        { "syncserver",   FULLCONFIG_ALL,  dosyncserver},
        { "keyhash",      FULLCONFIG_ALL,  dokeyhash},
        { "eventkey",     FULLCONFIG_ALL,  doeventkey},
        { "fullconfig",   FULLCONFIG_NONE, dofullconfig},
};
static int numcommands = sizeof(command_array)/sizeof(struct command);

char *usagestr = 
 "usage: tmcd [-d] [-p #]\n"
 " -d              Turn on debugging. Multiple -d options increase output\n"
 " -p portnum	   Specify a port number to listen on\n"
 " -c num	   Specify number of servers (must be %d <= x <= %d)\n"
 "\n";

void
usage()
{
	fprintf(stderr, usagestr, MINCHILDREN, MAXCHILDREN);
	exit(1);
}

static void
cleanup()
{
	signal(SIGHUP, SIG_IGN);
	killme = 1;
	killpg(0, SIGHUP);
}

static void
setverbose(int sig)
{
	signal(sig, SIG_IGN);
	
	if (sig == SIGUSR1)
		verbose = 1;
	else
		verbose = 0;
	/* Just the parent sends this */
	if (numchildren)
		killpg(0, sig);
	signal(sig, setverbose);
}

int
main(int argc, char **argv)
{
	int			tcpsock, udpsock, i, ch, foo[4];
	int			alttcpsock, altudpsock;
	int			status, pid;
	int			portnum = TBSERVER_PORT;
	FILE			*fp;
	char			buf[BUFSIZ];
	struct hostent		*he;
	extern char		build_info[];

	while ((ch = getopt(argc, argv, "dp:c:Xv")) != -1)
		switch(ch) {
		case 'p':
			portnum = atoi(optarg);
			break;
		case 'd':
			debug++;
			break;
		case 'c':
			maxchildren = atoi(optarg);
			break;
		case 'X':
			insecure = 1;
			break;
		case 'v':
			verbose++;
			break;
		case 'h':
		case '?':
		default:
			usage();
		}
	argc -= optind;
	argv += optind;

	if (argc)
		usage();
	if (maxchildren < MINCHILDREN || maxchildren > MAXCHILDREN)
		usage();

#ifdef  WITHSSL
	if (tmcd_server_sslinit()) {
		error("SSL init failed!\n");
		exit(1);
	}
#endif
	if (debug) 
		loginit(0, 0);
	else {
		/* Become a daemon */
		daemon(0, 0);
		loginit(1, "tmcd");
	}
	info("daemon starting (version %d)\n", CURRENT_VERSION);
	info("%s\n", build_info);

	/*
	 * Get FS's SFS hostid
	 * XXX This approach is somewhat kludgy
	 */
	strcpy(fshostid, "");
	if (access(FSHOSTID,R_OK) == 0) {
		fp = fopen(FSHOSTID, "r");
		if (!fp) {
			error("Failed to get FS's hostid");
		}
		else {
			fgets(fshostid, HOSTID_SIZE, fp);
			if (rindex(fshostid, '\n')) {
				*rindex(fshostid, '\n') = 0;
				if (debug) {
				    info("fshostid: %s\n", fshostid);
				}
			}
			else {
				error("fshostid from %s may be corrupt: %s",
				      FSHOSTID, fshostid);
			}
			fclose(fp);
		}
	}
	
	/*
	 * Grab our IP for security check below.
	 */
#ifdef	LBS
	strcpy(buf, BOSSNODE);
#else
	if (gethostname(buf, sizeof(buf)) < 0)
		pfatal("getting hostname");
#endif
	if ((he = gethostbyname(buf)) == NULL) {
		error("Could not get IP (%s) - %s\n", buf, hstrerror(h_errno));
		exit(1);
	}
	memcpy((char *)&myipaddr, he->h_addr, he->h_length);

	/*
	 * If we were given a port on the command line, don't open the 
	 * alternate ports
	 */
	if (portnum != TBSERVER_PORT) {
	    if (makesockets(portnum, &udpsock, &tcpsock) < 0) {
		error("Could not make sockets!");
		exit(1);
	    }
	} else {
	    if (makesockets(portnum, &udpsock, &tcpsock) < 0 ||
		makesockets(TBSERVER_PORT2, &altudpsock, &alttcpsock) < 0) {
		    error("Could not make sockets!");
		    exit(1);
	    }
	}

	signal(SIGTERM, cleanup);
	signal(SIGINT, cleanup);
	signal(SIGHUP, cleanup);
	signal(SIGUSR1, setverbose);
	signal(SIGUSR2, setverbose);

	/*
	 * Stash the pid away.
	 */
	mypid = getpid();
	sprintf(buf, "%s/tmcd.pid", _PATH_VARRUN);
	fp = fopen(buf, "w");
	if (fp != NULL) {
		fprintf(fp, "%d\n", mypid);
		(void) fclose(fp);
	}

	/*
	 * Now fork a set of children to handle requests. We keep the
	 * pool at a set level. No need to get too fancy at this point,
	 * although this approach *is* rather bogus. 
	 */
	bzero(foo, sizeof(foo));
	while (1) {
		while (!killme && numchildren < maxchildren) {
			int which = 0;
			if (!foo[1])
				which = 1;
			else if (!debug && !foo[2])
				which = 2;
			else if (!debug && !foo[3])
				which = 3;

			if ((pid = fork()) < 0) {
				errorc("forking server");
				goto done;
			}
			if (pid) {
				foo[which] = pid;
				numchildren++;
				continue;
			}
			/* Poor way of knowing parent/child */
			numchildren = 0;
			mypid = getpid();
			
			/* Child does useful work! Never Returns! */
			signal(SIGTERM, SIG_DFL);
			signal(SIGINT, SIG_DFL);
			signal(SIGHUP, SIG_DFL);
			
			switch (which) {
			case 0: tcpserver(tcpsock);
				break;
			case 1: udpserver(udpsock);
				break;
			case 2: udpserver(altudpsock);
				break;
			case 3: tcpserver(alttcpsock);
				break;
			}
			exit(-1);
		}

		/*
		 * Parent waits.
		 */
		pid = waitpid(-1, &status, 0);
		if (pid < 0) {
			errorc("waitpid failed");
			continue;
		} 
		if (WIFSIGNALED(status)) {
			error("server %d exited with signal %d!\n",
			      pid, WTERMSIG(status));
		}
		else if (WIFEXITED(status)) {
			error("server %d exited with status %d!\n",
			      pid, WEXITSTATUS(status));	  
		}
		numchildren--;
		for (i = 0; i < (sizeof(foo)/sizeof(int)); i++) {
			if (foo[i] == pid)
				foo[i] = 0;
		}
		if (killme && !numchildren)
			break;
	}
 done:
	CLOSE(tcpsock);
	close(udpsock);
	info("daemon terminating\n");
	exit(0);
}

/*
 * Create sockets on specified port.
 */
static int
makesockets(int portnum, int *udpsockp, int *tcpsockp)
{
	struct sockaddr_in	name;
	int			length, i, udpsock, tcpsock;

	/*
	 * Setup TCP socket for incoming connections.
	 */

	/* Create socket from which to read. */
	tcpsock = socket(AF_INET, SOCK_STREAM, 0);
	if (tcpsock < 0) {
		pfatal("opening stream socket");
	}

	i = 1;
	if (setsockopt(tcpsock, SOL_SOCKET, SO_REUSEADDR,
		       (char *)&i, sizeof(i)) < 0)
		pwarning("setsockopt(SO_REUSEADDR)");;
	
	/* Create name. */
	name.sin_family = AF_INET;
	name.sin_addr.s_addr = INADDR_ANY;
	name.sin_port = htons((u_short) portnum);
	if (bind(tcpsock, (struct sockaddr *) &name, sizeof(name))) {
		pfatal("binding stream socket");
	}
	/* Find assigned port value and print it out. */
	length = sizeof(name);
	if (getsockname(tcpsock, (struct sockaddr *) &name, &length)) {
		pfatal("getsockname");
	}
	if (listen(tcpsock, 128) < 0) {
		pfatal("listen");
	}
	info("listening on TCP port %d\n", ntohs(name.sin_port));
	
	/*
	 * Setup UDP socket
	 */

	/* Create socket from which to read. */
	udpsock = socket(AF_INET, SOCK_DGRAM, 0);
	if (udpsock < 0) {
		pfatal("opening dgram socket");
	}

	i = 1;
	if (setsockopt(udpsock, SOL_SOCKET, SO_REUSEADDR,
		       (char *)&i, sizeof(i)) < 0)
		pwarning("setsockopt(SO_REUSEADDR)");;
	
	/* Create name. */
	name.sin_family = AF_INET;
	name.sin_addr.s_addr = INADDR_ANY;
	name.sin_port = htons((u_short) portnum);
	if (bind(udpsock, (struct sockaddr *) &name, sizeof(name))) {
		pfatal("binding dgram socket");
	}

	/* Find assigned port value and print it out. */
	length = sizeof(name);
	if (getsockname(udpsock, (struct sockaddr *) &name, &length)) {
		pfatal("getsockname");
	}
	info("listening on UDP port %d\n", ntohs(name.sin_port));

	*tcpsockp = tcpsock;
	*udpsockp = udpsock;
	return 0;
}

/*
 * Listen for UDP requests. This is not a secure channel, and so this should
 * eventually be killed off.
 */
static void
udpserver(int sock)
{
	char			buf[MYBUFSIZE];
	struct sockaddr_in	client;
	int			length, cc;
	
	info("udpserver starting: pid=%d sock=%d\n", mypid, sock);

	/*
	 * Wait for udp connections.
	 */
	while (1) {
		length = sizeof(client);		
		cc = recvfrom(sock, buf, sizeof(buf) - 1,
			      0, (struct sockaddr *)&client, &length);
		if (cc <= 0) {
			if (cc < 0)
				errorc("Reading UDP request");
			error("UDP Connection aborted\n");
			continue;
		}
		buf[cc] = '\0';
		handle_request(sock, &client, buf, 0);
	}
	exit(1);
}

/*
 * Listen for TCP requests.
 */
static void
tcpserver(int sock)
{
	char			buf[MYBUFSIZE];
	struct sockaddr_in	client;
	int			length, cc, newsock;
	
	info("tcpserver starting: pid=%d sock=%d\n", mypid, sock);

	/*
	 * Wait for TCP connections.
	 */
	while (1) {
		length  = sizeof(client);
		newsock = ACCEPT(sock, (struct sockaddr *)&client, &length);
		if (newsock < 0) {
			errorc("accepting TCP connection");
			continue;
		}

		/*
		 * Read in the command request.
		 */
		if ((cc = READ(newsock, buf, sizeof(buf) - 1)) <= 0) {
			if (cc < 0)
				errorc("Reading TCP request");
			error("TCP connection aborted\n");
			CLOSE(newsock);
			continue;
		}
		buf[cc] = '\0';
		handle_request(newsock, &client, buf, 1);
		CLOSE(newsock);
	}
	exit(1);
}

static int
handle_request(int sock, struct sockaddr_in *client, char *rdata, int istcp)
{
	struct sockaddr_in redirect_client;
	int		   redirect = 0, havekey = 0;
	char		   buf[BUFSIZ], *bp, *cp;
	char		   privkey[TBDB_FLEN_PRIVKEY];
	int		   i, err = 0;
	int		   version = DEFAULT_VERSION;
	tmcdreq_t	   tmcdreq, *reqp = &tmcdreq;

	byteswritten = 0;

	/*
	 * Init the req structure.
	 */
	bzero(reqp, sizeof(*reqp));

	/*
	 * Look for special tags. 
	 */
	bp = rdata;
	while ((bp = strsep(&rdata, " ")) != NULL) {
		/*
		 * Look for PRIVKEY. 
		 */
		if (sscanf(bp, "PRIVKEY=%64s", buf)) {
			havekey = 1;
			strncpy(privkey, buf, sizeof(privkey));

			if (debug) {
				info("PRIVKEY %s\n", buf);
			}
			continue;
		}


		/*
		 * Look for VERSION. 
		 */
		if (sscanf(bp, "VERSION=%d", &i) == 1) {
			version = i;
			continue;
		}

		/*
		 * Look for REDIRECT, which is a proxy request for a
		 * client other than the one making the request. Good
		 * for testing. Might become a general tmcd redirect at
		 * some point, so that we can test new tmcds.
		 */
		if (sscanf(bp, "REDIRECT=%30s", buf)) {
			redirect_client = *client;
			redirect        = 1;
			inet_aton(buf, &client->sin_addr);

			info("REDIRECTED from %s to %s\n",
			     inet_ntoa(redirect_client.sin_addr), buf);

			continue;
		}
		
		/*
		 * Look for VNODE. This is used for virtual nodes.
		 * It indicates which of the virtual nodes (on the physical
		 * node) is talking to us. Currently no perm checking.
		 * Very temporary approach; should be done via a per-vnode
		 * cert or a key.
		 */
		if (sscanf(bp, "VNODEID=%30s", buf)) {
			reqp->isvnode = 1;
			strncpy(reqp->vnodeid, buf, sizeof(reqp->vnodeid));

			if (debug) {
				info("VNODEID %s\n", buf);
			}
			continue;
		}

		/*
		 * An empty token (two delimiters next to each other)
		 * is indicated by a null string. If nothing matched,
		 * and its not an empty token, it must be the actual
		 * command and arguments. Break out.
		 *
		 * Note that rdata will point to any text after the command.
		 *
		 */
		if (*bp) {
			break;
		}
	}

	/* Start with default DB */
	strcpy(dbname, DEFAULT_DBNAME);

	/*
	 * Map the ip to a nodeid.
	 */
	if ((err = iptonodeid(client->sin_addr, reqp))) {
		if (err == 2) {
			error("No such node vnode mapping %s on %s\n",
			      reqp->vnodeid, reqp->nodeid);
		}
		else {
			error("No such node: %s\n",
			      inet_ntoa(client->sin_addr));
		}
		goto skipit;
	}

	/*
	 * Redirect is allowed from the local host only!
	 * I use this for testing. See below where I test redirect
	 * if the verification fails. 
	 */
	if (!insecure && redirect &&
	    redirect_client.sin_addr.s_addr != myipaddr.s_addr) {
		char	buf1[32], buf2[32];
		
		strcpy(buf1, inet_ntoa(redirect_client.sin_addr));
		strcpy(buf2, inet_ntoa(client->sin_addr));

		if (verbose)
			info("%s INVALID REDIRECT: %s\n", buf1, buf2);
		goto skipit;
	}

#ifdef  WITHSSL
	/*
	 * If the connection is not SSL, then it must be a local node.
	 */
	if (isssl) {
		if (tmcd_sslverify_client(reqp->nodeid, reqp->pclass,
					  reqp->ptype,  reqp->islocal)) {
			error("%s: SSL verification failure\n", reqp->nodeid);
			if (! redirect)
				goto skipit;
		}
	}
	else if (!reqp->islocal) {
		if (!istcp)
			goto execute;
		
		error("%s: Remote node connected without SSL!\n",reqp->nodeid);
		if (!insecure)
			goto skipit;
	}
	else if (reqp->iscontrol) {
		if (!istcp)
			goto execute;

		error("%s: Control node connection without SSL!\n",
		      reqp->nodeid);
		if (!insecure)
			goto skipit;
	}
#else
	/*
	 * When not compiled for ssl, do not allow remote connections.
	 */
	if (!reqp->islocal) {
		error("%s: Remote node connection not allowed (Define SSL)!\n",
		      reqp->nodeid);
		if (!insecure)
			goto skipit;
	}
	if (reqp->iscontrol) {
		error("%s: Control node connection not allowed "
		      "(Define SSL)!\n", reqp->nodeid);
		if (!insecure)
			goto skipit;
	}
#endif
	/*
	 * Check for a redirect using the default DB. This allows
	 * for a simple redirect to a secondary DB for testing.
	 * Upon return, the dbname has been changed if redirected.
	 */
	if (checkdbredirect(reqp)) {
		/* Something went wrong */
		goto skipit;
	}

	/*
	 * Do private key check. widearea nodes must report a private key
	 * It comes over ssl of course. At present we skip this check for
	 * ron nodes. 
	 */
	if (!reqp->islocal) {
		if (!havekey) {
			error("%s: No privkey sent!\n", reqp->nodeid);
			/*
			 * Skip. Okay, the problem is that the nodes out
			 * there are not reporting the key!
			goto skipit;
			 */
		}
		else if (checkprivkey(client->sin_addr, privkey)) {
			error("%s: privkey mismatch: %s!\n",
			      reqp->nodeid, privkey);
			goto skipit;
		}
	}

	/*
	 * Figure out what command was given.
	 */
 execute:
	for (i = 0; i < numcommands; i++)
		if (strncmp(bp, command_array[i].cmdname,
			    strlen(command_array[i].cmdname)) == 0)
			break;

	if (i == numcommands) {
		info("%s: INVALID REQUEST: %.8s\n", reqp->nodeid, bp);
		goto skipit;
	}

	/*
	 * XXX: We allow remote nodes to use UDP for isalive only!
	 */
	if (!istcp && !reqp->islocal && command_array[i].func != doisalive) {
		error("%s: Invalid request (%s) from remote node using UDP!\n",
		      reqp->nodeid, command_array[i].cmdname);
		goto skipit;
	}

	/*
	 * Execute it.
	 */
#ifdef	WITHSSL
	cp = (isssl ? "SSL" : (istcp ? "TCP" : "UDP"));
#else
	cp = (istcp ? "TCP" : "UDP");
#endif
	/*
	 * XXX hack, don't log "log" contents,
	 * both for privacy and to keep our syslog smaller.
	 */
	if (command_array[i].func == dolog)
		info("%s: vers:%d %s log %d chars\n",
		     reqp->nodeid, version, cp, strlen(rdata));
	else if (command_array[i].func != doisalive || verbose)
		info("%s: vers:%d %s %s\n", reqp->nodeid,
		     version, cp, command_array[i].cmdname);

	err = command_array[i].func(sock, reqp, rdata, istcp, version);

	if (err)
		info("%s: %s: returned %d\n",
		     reqp->nodeid, command_array[i].cmdname, err);

 skipit:
	if (!istcp) 
		client_writeback_done(sock,
				      redirect ? &redirect_client : client);
	if (byteswritten)
		info("%s: %s wrote %d bytes\n",
		     reqp->nodeid, command_array[i].cmdname,
		     byteswritten);

	return 0;
}

/*
 * Accept notification of reboot. 
 */
COMMAND_PROTOTYPE(doreboot)
{
	/*
	 * This is now a no-op. The things this used to do are now
	 * done by stated when we hit RELOAD/RELOADDONE state
	 */
	return 0;
}

/*
 * Return emulab nodeid (not the experimental name).
 */
COMMAND_PROTOTYPE(donodeid)
{
	char		buf[MYBUFSIZE];

	OUTPUT(buf, sizeof(buf), "%s\n", reqp->nodeid);
	client_writeback(sock, buf, strlen(buf), tcp);
	return 0;
}

/*
 * Return status of node. Is it allocated to an experiment, or free.
 */
COMMAND_PROTOTYPE(dostatus)
{
	char		buf[MYBUFSIZE];

	/*
	 * Now check reserved table
	 */
	if (! reqp->allocated) {
		info("STATUS: %s: Node is free\n", reqp->nodeid);
		strcpy(buf, "FREE\n");
		client_writeback(sock, buf, strlen(buf), tcp);
		return 0;
	}

	OUTPUT(buf, sizeof(buf), "ALLOCATED=%s/%s NICKNAME=%s\n",
	       reqp->pid, reqp->eid, reqp->nickname);
	client_writeback(sock, buf, strlen(buf), tcp);

	if (verbose)
		info("STATUS: %s: %s", reqp->nodeid, buf);
	return 0;
}

/*
 * Return ifconfig information to client.
 */
COMMAND_PROTOTYPE(doifconfig)
{
	MYSQL_RES	*res;	
	MYSQL_ROW	row;
	char		buf[MYBUFSIZE], *ebufp = &buf[MYBUFSIZE];
	int		nrows;

	/*
	 * Now check reserved table
	 */
	if (! reqp->allocated) {
		if (verbose)
			info("IFCONFIG: %s: Node is free\n", reqp->nodeid);
		return 1;
	}

	/*
	 * Virtual nodes, do not return interface table info. No point.
	 * Subnode are slightly different. This test might need to be
	 * smarter?
	 */
	if (reqp->isvnode && !reqp->issubnode)
		goto doveths;

	/*
	 * Find all the interfaces.
	 */
	res = mydb_query("select card,IP,IPalias,MAC,current_speed,duplex, "
			 " IPaliases,iface,role,mask "
			 "from interfaces where node_id='%s'",
			 10, reqp->nodeid);
	if (!res) {
		error("IFCONFIG: %s: DB Error getting interfaces!\n",
		      reqp->nodeid);
		return 1;
	}

	if ((nrows = (int)mysql_num_rows(res)) == 0) {
		error("IFCONFIG: %s: No interfaces!\n", reqp->nodeid);
		mysql_free_result(res);
		return 1;
	}
	while (nrows) {
		row = mysql_fetch_row(res);
		if (row[1] && row[1][0]) {
			int  card    = atoi(row[0]);
			char *iface  = row[7];
			char *role   = row[8];
			char *speed  = "100";
			char *unit   = "Mbps";
			char *duplex = "full";
			char *bufp   = buf;
			char *mask;

			/* Never for the control net; sharks are dead */
			if (strcmp(role, TBDB_IFACEROLE_EXPERIMENT))
				goto skipit;

			/* Do this after above test to avoid error in log */
			mask = CHECKMASK(row[9]);

			/*
			 * Speed and duplex if not the default.
			 */
			if (row[4] && row[4][0])
				speed = row[4];
			if (row[5] && row[5][0])
				duplex = row[5];

			/*
			 * We now use the MAC to determine the interface, but
			 * older images still want that tag at the front.
			 */
			if (vers < 10)
				bufp += OUTPUT(bufp, ebufp - bufp,
					       "INTERFACE=%d ", card);
			else
				bufp += OUTPUT(bufp, ebufp - bufp,
					       "IFACETYPE=eth ");

			bufp += OUTPUT(bufp, ebufp - bufp,
				"INET=%s MASK=%s MAC=%s SPEED=%s%s DUPLEX=%s",
				row[1], mask, row[3], speed, unit, duplex);

			/* Tack on IPaliases */
			if (vers >= 8) {
				char *aliases = "";
				
				if (row[6] && row[6][0])
					aliases = row[6];

				bufp += OUTPUT(bufp, ebufp - bufp,
					       " IPALIASES=\"%s\"", aliases);
			}

			/*
			 * Tack on iface for IXPs. This should be a flag on
			 * the interface instead of a match against type.
			 */
			if (vers >= 11) {
				bufp += OUTPUT(bufp, ebufp - bufp,
					       " IFACE=%s",
					       (strcmp(reqp->class, "ixp") ?
						"" : iface));
			}
			OUTPUT(bufp, ebufp - bufp, "\n");
			client_writeback(sock, buf, strlen(buf), tcp);
			if (verbose)
				info("IFCONFIG: %s", buf);
		}
	skipit:
		nrows--;
	}
	mysql_free_result(res);

	/* Veth interfaces are new. */
 doveths:
	if (vers < 10)
		return 0;

	/*
	 * Outside a vnode, return only those veths that have vnode=NULL,
	 * which indicates its an emulated interface on a physical node. When
	 * inside a vnode, only return veths for which vnode=curvnode,
	 * which are the interfaces that correspond to a jail node.
	 */
	if (reqp->isvnode)
		sprintf(buf, "v.vnode_id='%s'", reqp->vnodeid);
	else
		strcpy(buf, "v.vnode_id is NULL");

	/*
	 * Find all the veth interfaces.
	 */
	res = mydb_query("select v.veth_id,v.IP,v.mac,i.mac,v.mask "
			 "  from veth_interfaces as v "
			 "left join interfaces as i on "
			 "  i.node_id=v.node_id and i.iface=v.iface "
			 "where v.node_id='%s' and %s",
			 5, reqp->pnodeid, buf);
	if (!res) {
		error("IFCONFIG: %s: DB Error getting veth interfaces!\n",
		      reqp->nodeid);
		return 1;
	}
	if ((nrows = (int)mysql_num_rows(res)) == 0) {
		mysql_free_result(res);
		return 0;
	}
	while (nrows) {
		row = mysql_fetch_row(res);

		/*
		 * Note that PMAC might be NULL, which happens if there is
		 * no underlying phys interface (say, colocated nodes in a
		 * link).
		 */
		OUTPUT(buf, sizeof(buf),
		       "IFACETYPE=veth "
		       "INET=%s MASK=%s ID=%s VMAC=%s PMAC=%s\n",
		       row[1], CHECKMASK(row[4]), row[0], row[2],
		       row[3] ? row[3] : "none");

		client_writeback(sock, buf, strlen(buf), tcp);
		if (verbose)
			info("IFCONFIG: %s", buf);
		nrows--;
	}
	mysql_free_result(res);

	return 0;
}

/*
 * Return account stuff.
 */
COMMAND_PROTOTYPE(doaccounts)
{
	MYSQL_RES	*res;	
	MYSQL_ROW	row;
	char		buf[MYBUFSIZE];
	int		nrows, gidint;
	int		tbadmin, didwidearea = 0;

	if (! tcp) {
		error("ACCOUNTS: %s: Cannot give account info out over UDP!\n",
		      reqp->nodeid);
		return 1;
	}

	/*
	 * Now check reserved table
	 */
	if ((reqp->islocal || reqp->isvnode) && !reqp->allocated) {
		error("ACCOUNTS: %s: Node is free\n", reqp->nodeid);
		return 1;
	}

        /*
	 * We need the unix GID and unix name for each group in the project.
	 */
	if (reqp->iscontrol) {
		/*
		 * All groups! 
		 */
		res = mydb_query("select unix_name,unix_gid from groups",
				 2, reqp->pid);
	}
	else if (reqp->islocal || reqp->isvnode) {
		res = mydb_query("select unix_name,unix_gid from groups "
				 "where pid='%s'",
				 2, reqp->pid);
	}
	else if (reqp->jailflag) {
		/*
		 * A remote node, doing jails. We still want to return
		 * a group for the admin people who get accounts outside
		 * the jails. Lets use the same query as above for now,
		 * but switch over to emulab-ops. 
		 */
		res = mydb_query("select unix_name,unix_gid from groups "
				 "where pid='%s'",
				 2, RELOADPID);
	}
	else {
		/*
		 * XXX - Old style node, not doing jails.
		 *
		 * Temporary hack until we figure out the right model for
		 * remote nodes. For now, we use the pcremote-ok slot in
		 * in the project table to determine what remote nodes are
		 * okay'ed for the project. If connecting node type is in
		 * that list, then return all of the project groups, for
		 * each project that is allowed to get accounts on the type.
		 */
		res = mydb_query("select g.unix_name,g.unix_gid "
				 "  from projects as p "
				 "left join groups as g on p.pid=g.pid "
				 "where p.approved!=0 and "
				 "      FIND_IN_SET('%s',pcremote_ok)>0",
				 2, reqp->type);
	}
	if (!res) {
		error("ACCOUNTS: %s: DB Error getting gids!\n", reqp->pid);
		return 1;
	}

	if ((nrows = (int)mysql_num_rows(res)) == 0) {
		error("ACCOUNTS: %s: No Project!\n", reqp->pid);
		mysql_free_result(res);
		return 1;
	}

	while (nrows) {
		row = mysql_fetch_row(res);
		if (!row[1] || !row[1][1]) {
			error("ACCOUNTS: %s: No Project GID!\n", reqp->pid);
			mysql_free_result(res);
			return 1;
		}

		gidint = atoi(row[1]);
		OUTPUT(buf, sizeof(buf),
		       "ADDGROUP NAME=%s GID=%d\n", row[0], gidint);
		client_writeback(sock, buf, strlen(buf), tcp);
		if (verbose)
			info("ACCOUNTS: %s", buf);

		nrows--;
	}
	mysql_free_result(res);

	/*
	 * Each time a node picks up accounts, decrement the update
	 * counter. This ensures that if someone kicks off another
	 * update after this point, the node will end up getting to
	 * do it again in case it missed something.
	 */
	if (mydb_update("update nodes set update_accounts=update_accounts-1 "
			"where node_id='%s' and update_accounts!=0",
			reqp->nodeid)) {
		error("ACCOUNTS: %s: DB Error setting exit update_accounts!\n",
		      reqp->nodeid);
	}
			 
	/*
	 * Now onto the users in the project.
	 */
	if (reqp->iscontrol) {
		/*
		 * All users! This is not currently used. The problem
		 * is that returning a list of hundreds of users whenever
		 * any single change is required is bad. Works fine for
		 * experimental nodes where the number of accounts is small,
		 * but is not scalable. 
		 */
		res = mydb_query("select distinct "
				 "  u.uid,u.usr_pswd,u.unix_uid,u.usr_name, "
				 "  p.trust,g.pid,g.gid,g.unix_gid,u.admin, "
				 "  u.emulab_pubkey,u.home_pubkey, "
				 "  UNIX_TIMESTAMP(u.usr_modified), "
				 "  u.usr_email,u.usr_shell "
				 "from group_membership as p "
				 "left join users as u on p.uid=u.uid "
				 "left join groups as g on p.pid=g.pid "
				 "where p.trust!='none' "
				 "      and u.status='active' order by u.uid",
				 14, reqp->pid, reqp->gid);
	}
	else if (reqp->islocal || reqp->isvnode) {
		/*
		 * This crazy join is going to give us multiple lines for
		 * each user that is allowed on the node, where each line
		 * (for each user) differs by the project PID and it unix
		 * GID. The intent is to build up a list of GIDs for each
		 * user to return. Well, a primary group and a list of aux
		 * groups for that user.
		 */
		res = mydb_query("select distinct "
				 "  u.uid,u.usr_pswd,u.unix_uid,u.usr_name, "
				 "  p.trust,g.pid,g.gid,g.unix_gid,u.admin, "
				 "  u.emulab_pubkey,u.home_pubkey, "
				 "  UNIX_TIMESTAMP(u.usr_modified), "
				 "  u.usr_email,u.usr_shell, "
				 "  u.widearearoot,u.wideareajailroot "
				 "from group_membership as p "
				 "left join users as u on p.uid=u.uid "
				 "left join groups as g on "
				 "     p.pid=g.pid and p.gid=g.gid "
				 "where ((p.pid='%s')) and p.trust!='none' "
				 "      and u.status='active' order by u.uid",
				 16, reqp->pid);
	}
	else if (reqp->jailflag) {
		/*
		 * A remote node, doing jails. We still want to return
		 * accounts for the admin people outside the jails.
		 */
		res = mydb_query("select distinct "
			     "  u.uid,'*',u.unix_uid,u.usr_name, "
			     "  p.trust,g.pid,g.gid,g.unix_gid,u.admin, "
			     "  u.emulab_pubkey,u.home_pubkey, "
			     "  UNIX_TIMESTAMP(u.usr_modified), "
			     "  u.usr_email,u.usr_shell, "
			     "  u.widearearoot,u.wideareajailroot "
			     "from group_membership as p "
			     "left join users as u on p.uid=u.uid "
			     "left join groups as g on "
			     "     p.pid=g.pid and p.gid=g.gid "
			     "where (p.pid='%s') and p.trust!='none' "
			     "      and u.status='active' and u.admin=1 "
			     "      order by u.uid",
			     16, RELOADPID);
	}
	else {
		/*
		 * XXX - Old style node, not doing jails.
		 *
		 * Temporary hack until we figure out the right model for
		 * remote nodes. For now, we use the pcremote-ok slot in
		 * in the project table to determine what remote nodes are
		 * okay'ed for the project. If connecting node type is in
		 * that list, then return user info for all of the users
		 * in those projects (crossed with group in the project). 
		 */
		res = mydb_query("select distinct  "
				 "u.uid,'*',u.unix_uid,u.usr_name, "
				 "m.trust,g.pid,g.gid,g.unix_gid,u.admin, "
				 "u.emulab_pubkey,u.home_pubkey, "
				 "UNIX_TIMESTAMP(u.usr_modified), "
				 "u.usr_email,u.usr_shell, "
				 "u.widearearoot,u.wideareajailroot "
				 "from projects as p "
				 "left join group_membership as m "
				 "  on m.pid=p.pid "
				 "left join groups as g on "
				 "  g.pid=m.pid and g.gid=m.gid "
				 "left join users as u on u.uid=m.uid "
				 "where p.approved!=0 "
				 "      and FIND_IN_SET('%s',pcremote_ok)>0 "
				 "      and m.trust!='none' "
				 "      and u.status='active' "
				 "order by u.uid",
				 16, reqp->type);
	}

	if (!res) {
		error("ACCOUNTS: %s: DB Error getting users!\n", reqp->pid);
		return 1;
	}

	if ((nrows = (int)mysql_num_rows(res)) == 0) {
		error("ACCOUNTS: %s: No Users!\n", reqp->pid);
		mysql_free_result(res);
		return 0;
	}

 again:
	row = mysql_fetch_row(res);
	while (nrows) {
		MYSQL_ROW	nextrow = 0;
		MYSQL_RES	*pubkeys_res;
		MYSQL_RES	*sfskeys_res;
		int		pubkeys_nrows, sfskeys_nrows, i, root = 0;
		int		auxgids[128], gcount = 0;
		char		glist[BUFSIZ];
		char		*bufp = buf, *ebufp = &buf[sizeof(buf)];

		gidint     = -1;
		tbadmin    = root = atoi(row[8]);
		gcount     = 0;
		
		while (1) {
			
			/*
			 * The whole point of this mess. Figure out the
			 * main GID and the aux GIDs. Perhaps trying to make
			 * distinction between main and aux is unecessary, as
			 * long as the entire set is represented.
			 */
			if (strcmp(row[5], reqp->pid) == 0 &&
			    strcmp(row[6], reqp->gid) == 0) {
				gidint = atoi(row[7]);

				/*
				 * Only people in the main pid can get root
				 * at this time, so do this test here.
				 */
				if ((strcmp(row[4], "local_root") == 0) ||
				    (strcmp(row[4], "group_root") == 0) ||
				    (strcmp(row[4], "project_root") == 0))
					root = 1;
			}
			else {
				int k, newgid = atoi(row[7]);
				
				/*
				 * Avoid dups, which can happen because of
				 * different trust levels in the join.
				 */
				for (k = 0; k < gcount; k++) {
				    if (auxgids[k] == newgid)
					goto skipit;
				}
				auxgids[gcount++] = newgid;
			skipit:
			}
			nrows--;

			if (!nrows)
				break;

			/*
			 * See if the next row is the same UID. If so,
			 * we go around the inner loop again.
			 */
			nextrow = mysql_fetch_row(res);
			if (strcmp(row[0], nextrow[0]))
				break;
			row = nextrow;
		}
		/*
		 * widearearoot and wideareajailroot override trust values
		 * from the project (above). Of course, tbadmin overrides
		 * everthing!
		 */
		if (!reqp->islocal) {
			if (!reqp->isvnode)
				root = atoi(row[14]);
			else
				root = atoi(row[15]);

			if (tbadmin)
				root = 1;
		}
		 
		/*
		 * Okay, process the UID. If there is no primary gid,
		 * then use one from the list. Then convert the rest of
		 * the list for the GLIST argument below.
		 */
		if (gidint == -1) {
			gidint = auxgids[--gcount];
		}
		glist[0] = '\0';
		for (i = 0; i < gcount; i++) {
			sprintf(&glist[strlen(glist)], "%d", auxgids[i]);

			if (i < gcount-1)
				strcat(glist, ",");
		}

		if (vers < 4) {
			bufp += OUTPUT(buf, sizeof(buf),
				"ADDUSER LOGIN=%s "
				"PSWD=%s UID=%s GID=%d ROOT=%d NAME=\"%s\" "
				"HOMEDIR=%s/%s GLIST=%s\n",
				row[0], row[1], row[2], gidint, root, row[3],
				USERDIR, row[0], glist);
		}
		else if (vers == 4) {
			bufp += OUTPUT(buf, sizeof(buf),
				"ADDUSER LOGIN=%s "
				"PSWD=%s UID=%s GID=%d ROOT=%d NAME=\"%s\" "
				"HOMEDIR=%s/%s GLIST=\"%s\" "
				"EMULABPUBKEY=\"%s\" HOMEPUBKEY=\"%s\"\n",
				row[0], row[1], row[2], gidint, root, row[3],
				USERDIR, row[0], glist,
				row[9] ? row[9] : "",
				row[10] ? row[10] : "");
		}
		else {
			if (!reqp->islocal) {
				if (vers == 5)
					row[1] = "'*'";
				else
					row[1] = "*";
			}
			bufp += OUTPUT(buf, sizeof(buf),
				"ADDUSER LOGIN=%s "
				"PSWD=%s UID=%s GID=%d ROOT=%d NAME=\"%s\" "
				"HOMEDIR=%s/%s GLIST=\"%s\" SERIAL=%s",
				row[0], row[1], row[2], gidint, root, row[3],
				USERDIR, row[0], glist, row[11]);

			if (vers >= 9) {
				bufp += OUTPUT(bufp, ebufp - bufp,
					       " EMAIL=\"%s\"", row[12]);
			}
			if (vers >= 10) {
				bufp += OUTPUT(bufp, ebufp - bufp,
					       " SHELL=%s", row[13]);
			}
			OUTPUT(bufp, ebufp - bufp, "\n");
		}
			
		client_writeback(sock, buf, strlen(buf), tcp);

		if (verbose)
			info("ACCOUNTS: "
			     "ADDUSER LOGIN=%s "
			     "UID=%s GID=%d ROOT=%d GLIST=%s\n",
			     row[0], row[2], gidint, root, glist);

		if (vers < 5)
			goto skipkeys;

		/*
		 * Need a list of keys for this user.
		 */
		pubkeys_res = mydb_query("select idx,pubkey "
					 " from user_pubkeys "
					 "where uid='%s'",
					 2, row[0]);
	
		if (!pubkeys_res) {
			error("ACCOUNTS: %s: DB Error getting keys\n", row[0]);
			goto skipkeys;
		}
		if ((pubkeys_nrows = (int)mysql_num_rows(pubkeys_res))) {
			while (pubkeys_nrows) {
				MYSQL_ROW	pubkey_row;

				pubkey_row = mysql_fetch_row(pubkeys_res);

				OUTPUT(buf, sizeof(buf),
				       "PUBKEY LOGIN=%s KEY=\"%s\"\n",
				       row[0], pubkey_row[1]);
			
				client_writeback(sock, buf, strlen(buf), tcp);
				pubkeys_nrows--;

				if (verbose)
					info("ACCOUNTS: PUBKEY LOGIN=%s "
					     "IDX=%s\n",
					     row[0], pubkey_row[0]);
			}
		}
		mysql_free_result(pubkeys_res);

		if (vers < 6)
			goto skipkeys;

		/*
		 * Need a list of SFS keys for this user.
		 */
		sfskeys_res = mydb_query("select comment,pubkey "
					 " from user_sfskeys "
					 "where uid='%s'",
					 2, row[0]);

		if (!sfskeys_res) {
			error("ACCOUNTS: %s: DB Error getting SFS keys\n", row[0]);
			goto skipkeys;
		}
		if ((sfskeys_nrows = (int)mysql_num_rows(sfskeys_res))) {
			while (sfskeys_nrows) {
				MYSQL_ROW	sfskey_row;

				sfskey_row = mysql_fetch_row(sfskeys_res);

				OUTPUT(buf, sizeof(buf),
				       "SFSKEY KEY=\"%s\"\n", sfskey_row[1]);

				client_writeback(sock, buf, strlen(buf), tcp);
				sfskeys_nrows--;

				if (verbose)
					info("ACCOUNTS: SFSKEY LOGIN=%s "
					     "COMMENT=%s\n",
					     row[0], sfskey_row[0]);
			}
		}
		mysql_free_result(sfskeys_res);
		
	skipkeys:
		row = nextrow;
	}
	mysql_free_result(res);

	if (!(reqp->islocal || reqp->isvnode) && !didwidearea) {
		didwidearea = 1;

		/*
		 * Sleazy. The only real downside though is that
		 * we could get some duplicate entries, which won't
		 * really harm anything on the client.
		 */
		res = mydb_query("select distinct "
				 "u.uid,'*',u.unix_uid,u.usr_name, "
				 "w.trust,'guest','guest',31,u.admin, "
				 "u.emulab_pubkey,u.home_pubkey, "
				 "UNIX_TIMESTAMP(u.usr_modified), "
				 "u.usr_email,u.usr_shell, "
				 "u.widearearoot,u.wideareajailroot "
				 "from widearea_accounts as w "
				 "left join users as u on u.uid=w.uid "
				 "where w.trust!='none' and "
				 "      u.status='active' and node_id='%s' "
				 "order by u.uid",
				 16, reqp->nodeid);

		if (res) {
			if ((nrows = mysql_num_rows(res)))
				goto again;
			else
				mysql_free_result(res);
		}
	}
	return 0;
}

/*
 * Return delay config stuff.
 */
COMMAND_PROTOTYPE(dodelay)
{
	MYSQL_RES	*res;	
	MYSQL_ROW	row;
	char		buf[2*MYBUFSIZE], *ebufp = &buf[sizeof(buf)];
	int		nrows;

	/*
	 * Now check reserved table
	 */
	if (!reqp->allocated)
		return 0;

	/*
	 * Get delay parameters for the machine. The point of this silly
	 * join is to get the type out so that we can pass it back. Of
	 * course, this assumes that the type is the BSD name, not linux.
	 */
	res = mydb_query("select i.MAC,j.MAC, "
		 "pipe0,delay0,bandwidth0,lossrate0,q0_red, "
		 "pipe1,delay1,bandwidth1,lossrate1,q1_red, "
		 "vname, "
		 "q0_limit,q0_maxthresh,q0_minthresh,q0_weight,q0_linterm, " 
		 "q0_qinbytes,q0_bytes,q0_meanpsize,q0_wait,q0_setbit, " 
		 "q0_droptail,q0_gentle, "
		 "q1_limit,q1_maxthresh,q1_minthresh,q1_weight,q1_linterm, "
		 "q1_qinbytes,q1_bytes,q1_meanpsize,q1_wait,q1_setbit, "
		 "q1_droptail,q1_gentle,vnode0,vnode1 "
                 " from delays as d "
		 "left join interfaces as i on "
		 " i.node_id=d.node_id and i.iface=iface0 "
		 "left join interfaces as j on "
		 " j.node_id=d.node_id and j.iface=iface1 "
		 " where d.node_id='%s'",	 
		 39, reqp->nodeid);
	if (!res) {
		error("DELAY: %s: DB Error getting delays!\n", reqp->nodeid);
		return 1;
	}

	if ((nrows = (int)mysql_num_rows(res)) == 0) {
		mysql_free_result(res);
		return 0;
	}
	while (nrows) {
		char	*bufp = buf;
		
		row = mysql_fetch_row(res);

		/*
		 * Yikes, this is ugly! Sanity check though, since I saw
		 * some bogus values in the DB.
		 */
		if (!row[0] || !row[1] || !row[2] || !row[3]) {
			error("DELAY: %s: DB values are bogus!\n",
			      reqp->nodeid);
			mysql_free_result(res);
			return 1;
		}

		bufp += OUTPUT(bufp, ebufp - bufp,
			"DELAY INT0=%s INT1=%s "
			"PIPE0=%s DELAY0=%s BW0=%s PLR0=%s "
			"PIPE1=%s DELAY1=%s BW1=%s PLR1=%s "
			"LINKNAME=%s "
			"RED0=%s RED1=%s "
			"LIMIT0=%s MAXTHRESH0=%s MINTHRESH0=%s WEIGHT0=%s "
			"LINTERM0=%s QINBYTES0=%s BYTES0=%s "
			"MEANPSIZE0=%s WAIT0=%s SETBIT0=%s "
			"DROPTAIL0=%s GENTLE0=%s "
			"LIMIT1=%s MAXTHRESH1=%s MINTHRESH1=%s WEIGHT1=%s "
			"LINTERM1=%s QINBYTES1=%s BYTES1=%s "
			"MEANPSIZE1=%s WAIT1=%s SETBIT1=%s " 
			"DROPTAIL1=%s GENTLE1=%s",
			row[0], row[1],
			row[2], row[3], row[4], row[5],
			row[7], row[8], row[9], row[10],
			row[12],
			row[6], row[11],
			row[13], row[14], row[15], row[16],
			row[17], row[18], row[19],
			row[20], row[21], row[22],
			row[23], row[24],
			row[25], row[26], row[27], row[28],
			row[29], row[30], row[31],
			row[32], row[33], row[34],
			row[35], row[36]);

		if (vers >= 8) {
			/*
			 * Temp. This is so current experiments with delay
			 * entries continues to work okay with the new image.
			 */
			bufp += OUTPUT(bufp, ebufp - bufp,
				       " VNODE0=%s VNODE1=%s",
				       (row[37] ? row[37] : "foo"),
				       (row[38] ? row[38] : "bar"));
		}
		OUTPUT(bufp, ebufp - bufp, "\n");
			
		client_writeback(sock, buf, strlen(buf), tcp);
		nrows--;
		if (verbose)
			info("DELAY: %s", buf);
	}
	mysql_free_result(res);

	return 0;
}

/*
 * Return link delay config stuff.
 */
COMMAND_PROTOTYPE(dolinkdelay)
{
	MYSQL_RES	*res;	
	MYSQL_ROW	row;
	char		buf[2*MYBUFSIZE];
	int		nrows;

	/*
	 * Now check reserved table
	 */
	if (!reqp->allocated)
		return 0;

	/*
	 * Get link delay parameters for the machine. We store veth
	 * interfaces in another dynamic table, so must join with both
	 * interfaces and veth_interfaces to see which iface this link
	 * delay corresponds to. If there is a veth entry use that, else
	 * use the normal interfaces entry. I do not like this much.
	 * Maybe we should use the regular interfaces table, with type veth,
	 * entries added/deleted on the fly. I avoided that cause I view
	 * the interfaces table as static and pertaining to physical
	 * interfaces.
	 *
	 * Outside a vnode, return only those linkdelays for veths that have
	 * vnode=NULL, which indicates its an emulated interface on a
	 * physical node. When inside a vnode, only return veths for which
	 * vnode=curvnode, which are the interfaces that correspond to a
	 * jail node.
	 */
	if (reqp->isvnode)
		sprintf(buf, "and v.vnode_id='%s'", reqp->vnodeid);
	else
		strcpy(buf, "and v.vnode_id is NULL");

	res = mydb_query("select i.MAC,type,vlan,vnode,d.ip,netmask, "
		 "pipe,delay,bandwidth,lossrate, "
		 "rpipe,rdelay,rbandwidth,rlossrate, "
		 "q_red,q_limit,q_maxthresh,q_minthresh,q_weight,q_linterm, " 
		 "q_qinbytes,q_bytes,q_meanpsize,q_wait,q_setbit, " 
		 "q_droptail,q_gentle,v.mac "
                 " from linkdelays as d "
		 "left join interfaces as i on "
		 " i.node_id=d.node_id and i.iface=d.iface "
		 "left join veth_interfaces as v on "
		 " v.node_id=d.node_id and v.IP=d.ip "
		 "where d.node_id='%s' %s",
		 28, reqp->pnodeid, buf);
	if (!res) {
		error("LINKDELAY: %s: DB Error getting link delays!\n",
		      reqp->nodeid);
		return 1;
	}

	if ((nrows = (int)mysql_num_rows(res)) == 0) {
		mysql_free_result(res);
		return 0;
	}
	while (nrows) {
		row = mysql_fetch_row(res);

		OUTPUT(buf, sizeof(buf),
		        "LINKDELAY IFACE=%s TYPE=%s "
			"LINKNAME=%s VNODE=%s INET=%s MASK=%s "
			"PIPE=%s DELAY=%s BW=%s PLR=%s "
			"RPIPE=%s RDELAY=%s RBW=%s RPLR=%s "
			"RED=%s LIMIT=%s MAXTHRESH=%s MINTHRESH=%s WEIGHT=%s "
			"LINTERM=%s QINBYTES=%s BYTES=%s "
			"MEANPSIZE=%s WAIT=%s SETBIT=%s "
			"DROPTAIL=%s GENTLE=%s\n",
			(row[27] ? row[27] : row[0]), row[1],
			row[2],  row[3],  row[4],  CHECKMASK(row[5]),
			row[6],	 row[7],  row[8],  row[9],
			row[10], row[11], row[12], row[14],
			row[14], row[15], row[16], row[17], row[18],
			row[19], row[20], row[21],
			row[22], row[23], row[24],
			row[25], row[26]);
			
		client_writeback(sock, buf, strlen(buf), tcp);
		nrows--;
		if (verbose)
			info("LINKDELAY: %s", buf);
	}
	mysql_free_result(res);

	return 0;
}

/*
 * Return host table information.
 */
COMMAND_PROTOTYPE(dohostsV2)
{
	/*
	 * This will go away. Ignore version and assume latest.
	 */
	return(dohosts(sock, reqp, rdata, tcp, CURRENT_VERSION));
}

COMMAND_PROTOTYPE(dohosts)
{
	MYSQL_RES	*res;	
	MYSQL_ROW	row;
	char		buf[MYBUFSIZE];
	int		hostcount, nrows;
	int		rv = 0;
	int		nroutes, i;

	/*
	 * We build up a canonical host table using this data structure.
	 * There is one item per node/iface. We need a shared structure
	 * though for each node, to allow us to compute the aliases.
	 */
	struct shareditem {
	    	int	hasalias;
		char	*firstvlan;	/* The first vlan to another node */
	};
	struct hostentry {
		char	nodeid[TBDB_FLEN_NODEID];
		char	vname[TBDB_FLEN_VNAME];
		char	vlan[TBDB_FLEN_VNAME];
		int	virtiface;
		struct in_addr	  ipaddr;
		struct shareditem *shared;
		struct hostentry  *next;
	} *hosts = 0, *host;

	/*
	 * We store all routes for this node in this structure 
	 */
	struct routeentry {
		struct in_addr	dst;
		struct in_addr	dst_mask;
		int		dst_type;
	} *routes = 0, *route;

	/*
	 * Now check reserved table
	 */
	if (!reqp->allocated)
		return 0;

	/*
	 * Now use the virt_nodes table to get a list of all of the
	 * nodes and all of the IPs on those nodes. This is the basis
	 * for the canonical host table. Join it with the reserved
	 * table to get the node_id at the same time (saves a step).
	 */
	/*
	  XXX NSE hack: Using the v2pmap table instead of reserved because
	  of multiple simulated to one physical node mapping. Currently,
	  reserved table contains a vname which is generated in the case of
	  nse
	 */
	res = mydb_query("select v.vname,v.ips,v2p.node_id from virt_nodes as v "
			 "left join v2pmap as v2p on "
			 " v.vname=v2p.vname and v.pid=v2p.pid and v.eid=v2p.eid "
			 " where v.pid='%s' and v.eid='%s' order by v2p.node_id",
			 3, reqp->pid, reqp->eid);

	if (!res) {
		error("HOSTNAMES: %s: DB Error getting virt_nodes!\n",
		      reqp->nodeid);
		return 1;
	}
	if (! (nrows = mysql_num_rows(res))) {
		mysql_free_result(res);
		return 0;
	}

	/*
	 * Parse the list, creating an entry for each node/IP pair.
	 */
	while (nrows--) {
		char		  *bp, *ip, *cp;
		struct shareditem *shareditem;
		
		row = mysql_fetch_row(res);
		if (!row[0] || !row[0][0] ||
		    !row[1] || !row[1][0])
			continue;

		if (! (shareditem = (struct shareditem *)
		       calloc(1, sizeof(*shareditem)))) {
			error("HOSTNAMES: Out of memory for shareditem!\n");
			exit(1);
		}

		bp = row[1];
		while (bp) {
			/*
			 * Note that the ips column is a space separated list
			 * of X:IP where X is a logical interface number.
			 */
			cp = strsep(&bp, ":");
			ip = strsep(&bp, " ");

			if (! (host = (struct hostentry *)
			              calloc(1, sizeof(*host)))) {
				error("HOSTNAMES: Out of memory!\n");
				exit(1);
			}

			strcpy(host->vname, row[0]);
			strcpy(host->nodeid, row[2]);
			host->virtiface = atoi(cp);
			host->shared = shareditem;
			inet_aton(ip, &host->ipaddr);
			host->next = hosts;
			hosts = host;
		}
	}
	mysql_free_result(res);

	/*
	 * Now we need to find the virtual lan name for each interface on
	 * each node. This is the user or system generated vlan name, and is
	 * in the virt_lans table. We use the virtiface number we got above
	 * to match on the member slot.
	 */
	res = mydb_query("select vname,member from virt_lans "
			 " where pid='%s' and eid='%s'",
			 2, reqp->pid, reqp->eid);

	if (!res) {
		error("HOSTNAMES: %s: DB Error getting virt_lans!\n",
		      reqp->nodeid);
		rv = 1;
		goto cleanup;
	}
	if (! (nrows = mysql_num_rows(res))) {
		mysql_free_result(res);
		rv = 1;
		goto cleanup;
	}

	while (nrows--) {
		char	*bp, *cp;
		int	virtiface;
		
		row = mysql_fetch_row(res);
		if (!row[0] || !row[0][0] ||
		    !row[1] || !row[1][0])
			continue;

		/*
		 * Note that the members column looks like vname:X
		 * where X is a logical interface number we got above.
		 * Loop through and find the entry and stash the vlan
		 * name.
		 */
		bp = row[1];
		cp = strsep(&bp, ":");
		virtiface = atoi(bp);

		host = hosts;
		while (host) {
			if (host->virtiface == virtiface &&
			    strcmp(cp, host->vname) == 0) {
				strcpy(host->vlan, row[0]);
			}
			host = host->next;
		}
	}
	mysql_free_result(res);

	/*
	 * The last part of the puzzle is to determine who is directly
	 * connected to this node so that we can add an alias for the
	 * first link to each connected node (could be more than one link
	 * to another node). Since we have the vlan names for all the nodes,
	 * its a simple matter of looking in the table for all of the nodes
	 * that are in the same vlan as the node that we are making the
	 * host table for.
	 */
	host = hosts;
	while (host) {
		/*
		 * Only care about this nodes vlans.
		 */
		if (strcmp(host->nodeid, reqp->nodeid) == 0 && host->vlan) {
			struct hostentry *tmphost = hosts;

			while (tmphost) {
				if (strlen(tmphost->vlan) &&
				    strcmp(host->vlan, tmphost->vlan) == 0 &&
				    strcmp(host->nodeid, tmphost->nodeid) &&
				    (!tmphost->shared->firstvlan ||
				     !strcmp(tmphost->vlan,
					     tmphost->shared->firstvlan))) {
					
					/*
					 * Use as flag to ensure only first
					 * link flagged as connected (gets
					 * an alias), but since a vlan could
					 * be a real lan with more than one
					 * other member, must tag all the
					 * members.
					 */
					tmphost->shared->firstvlan =
						tmphost->vlan;
				}
				tmphost = tmphost->next;
			}
		}
		host = host->next;
	}
#if 0
	host = hosts;
	while (host) {
		printf("%s %s %s %d %s %d\n", host->vname, host->nodeid,
		       host->vlan, host->virtiface, inet_ntoa(host->ipaddr),
		       host->connected);
		host = host->next;
	}
#endif

	/*
	 * Get a list of all routes for this host, to be used in creating
	 * aliases for non-directly connected nodes.
	 */
	res = mydb_query("select dst, dst_type, dst_mask from virt_routes "
			 "where pid='%s' and eid='%s' and vname='%s'"
			 "order by dst",
			 3, reqp->pid, reqp->eid, reqp->nickname);
	if (!res) {
	    error("HOSTNAMES: %s: DB Error getting routes!\n",
		    reqp->nodeid);
	    return 1;
	}

	nrows = mysql_num_rows(res);
	if (!(routes = (struct routeentry*)
		(malloc(nrows * sizeof(struct routeentry))))) {
	    error("HOSTNAMES: Out of memory!\n");
	    exit(1);
	}
	nroutes = nrows;
	route = routes;

	while (nrows--) {
	    row = mysql_fetch_row(res);
	    inet_aton(row[0],&(route->dst));
	    if (!strcmp(row[1],"host")) {
		route->dst_type = 0;
	    } else {
		/*
		 * Only bother with the mask if it's a subnet route
		 */
		route->dst_type = 1;
		inet_aton(row[2],&(route->dst_mask));
	    }
	    route++;
	}
	mysql_free_result(res);

	/*
	 * Okay, spit the entries out!
	 */
	hostcount = 0;
	host = hosts;
	while (host) {
		char	*alias = " ";

		if ((host->shared->firstvlan &&
		     !strcmp(host->shared->firstvlan, host->vlan)) ||
		    /* First interface on this node gets an alias */
		    (!strcmp(host->nodeid, reqp->nodeid) && !host->virtiface)){
			alias = host->vname;
		} else if (!host->shared->firstvlan &&
			   !host->shared->hasalias) {
		
		    /*
		     * Check for routes to this node, if it isn't directly
		     * connected, and doesn't already have an alias
		     */
		    for (i = 0; i < nroutes; i++) {
			if (routes[i].dst_type == 0) { /* Host route */
			    if (routes[i].dst.s_addr == host->ipaddr.s_addr) {
				alias = host->vname;
				host->shared->hasalias = 1;
				break;
			    }
			} else { /* Net route */
			    if ((host->ipaddr.s_addr &
					routes[i].dst_mask.s_addr)
				    == routes[i].dst.s_addr) {
				alias = host->vname;
				host->shared->hasalias = 1;
				break;
			    }
			}
		    }
		}

		/* Old format */
		if (vers == 2) {
			OUTPUT(buf, sizeof(buf),
			       "NAME=%s LINK=%i IP=%s ALIAS=%s\n",
			       host->vname, host->virtiface,
			       inet_ntoa(host->ipaddr), alias);
		}
		else {
			OUTPUT(buf, sizeof(buf),
			       "NAME=%s-%s IP=%s ALIASES='%s-%i %s'\n",
			       host->vname, host->vlan,
			       inet_ntoa(host->ipaddr),
			       host->vname, host->virtiface, alias);
		}
		client_writeback(sock, buf, strlen(buf), tcp);
		host = host->next;
		hostcount++;
	}
#if 0
	/*
	 * List of control net addresses for jailed nodes.
	 * Temporary.
	 */
	res = mydb_query("select r.node_id,r.vname,n.jailip "
			 " from reserved as r "
			 "left join nodes as n on n.node_id=r.node_id "
			 "where r.pid='%s' and r.eid='%s' "
			 "      and jailflag=1 and jailip is not null",
			 3, reqp->pid, reqp->eid);
	if (res) {
	    if ((nrows = mysql_num_rows(res))) {
		while (nrows--) {
		    row = mysql_fetch_row(res);

		    OUTPUT(buf, sizeof(buf),
			   "NAME=%s IP=%s ALIASES='%s.%s.%s.%s'\n",
			   row[0], row[2], row[1], reqp->eid, reqp->pid,
			   OURDOMAIN);
		    client_writeback(sock, buf, strlen(buf), tcp);
		    hostcount++;
		}
	    }
	    mysql_free_result(res);
	}
#endif
	info("HOSTNAMES: %d hosts in list\n", hostcount);
 cleanup:
	host = hosts;
	while (host) {
		struct hostentry *tmphost = host->next;
		free(host);
		host = tmphost;
	}
	free(routes);
	return rv;
}

/*
 * Return RPM stuff.
 */
COMMAND_PROTOTYPE(dorpms)
{
	MYSQL_RES	*res;	
	MYSQL_ROW	row;
	char		buf[MYBUFSIZE], *bp, *sp;

	/*
	 * Now check reserved table
	 */
	if (!reqp->allocated)
		return 0;

	/*
	 * Get RPM list for the node.
	 */
	res = mydb_query("select rpms from nodes where node_id='%s' ",
			 1, reqp->nodeid);

	if (!res) {
		error("RPMS: %s: DB Error getting RPMS!\n", reqp->nodeid);
		return 1;
	}

	if ((int)mysql_num_rows(res) == 0) {
		mysql_free_result(res);
		return 0;
	}

	/*
	 * Text string is a colon separated list.
	 */
	row = mysql_fetch_row(res);
	if (! row[0] || !row[0][0]) {
		mysql_free_result(res);
		return 0;
	}
	
	bp  = row[0];
	sp  = bp;
	do {
		bp = strsep(&sp, ":");

		OUTPUT(buf, sizeof(buf), "RPM=%s\n", bp);
		client_writeback(sock, buf, strlen(buf), tcp);
		if (verbose)
			info("RPM: %s", buf);
		
	} while ((bp = sp));
	
	mysql_free_result(res);
	return 0;
}

/*
 * Return Tarball stuff.
 */
COMMAND_PROTOTYPE(dotarballs)
{
	MYSQL_RES	*res;	
	MYSQL_ROW	row;
	char		buf[MYBUFSIZE], *bp, *sp, *tp;

	/*
	 * Now check reserved table
	 */
	if (!reqp->allocated)
		return 0;

	/*
	 * Get Tarball list for the node.
	 */
	res = mydb_query("select tarballs from nodes where node_id='%s' ",
			 1, reqp->nodeid);

	if (!res) {
		error("TARBALLS: %s: DB Error getting tarballs!\n",
		      reqp->nodeid);
		return 1;
	}

	if ((int)mysql_num_rows(res) == 0) {
		mysql_free_result(res);
		return 0;
	}

	/*
	 * Text string is a colon separated list of "dir filename". 
	 */
	row = mysql_fetch_row(res);
	if (! row[0] || !row[0][0]) {
		mysql_free_result(res);
		return 0;
	}
	
	bp  = row[0];
	sp  = bp;
	do {
		bp = strsep(&sp, ":");
		if ((tp = strchr(bp, ' ')) == NULL)
			continue;
		*tp++ = '\0';

		OUTPUT(buf, sizeof(buf), "DIR=%s TARBALL=%s\n", bp, tp);
		client_writeback(sock, buf, strlen(buf), tcp);
		if (verbose)
			info("TARBALLS: %s", buf);
		
	} while ((bp = sp));
	
	mysql_free_result(res);
	return 0;
}

/*
 * Return Deltas stuff.
 */
COMMAND_PROTOTYPE(dodeltas)
{
	MYSQL_RES	*res;	
	MYSQL_ROW	row;
	char		buf[MYBUFSIZE], *bp, *sp;

	/*
	 * Now check reserved table
	 */
	if (!reqp->allocated)
		return 0;

	/*
	 * Get Delta list for the node.
	 */
	res = mydb_query("select deltas from nodes where node_id='%s' ",
			 1, reqp->nodeid);

	if (!res) {
		error("DELTAS: %s: DB Error getting Deltas!\n", reqp->nodeid);
		return 1;
	}

	if ((int)mysql_num_rows(res) == 0) {
		mysql_free_result(res);
		return 0;
	}

	/*
	 * Text string is a colon separated list.
	 */
	row = mysql_fetch_row(res);
	if (! row[0] || !row[0][0]) {
		mysql_free_result(res);
		return 0;
	}
	
	bp  = row[0];
	sp  = bp;
	do {
		bp = strsep(&sp, ":");

		OUTPUT(buf, sizeof(buf), "DELTA=%s\n", bp);
		client_writeback(sock, buf, strlen(buf), tcp);
		if (verbose)
			info("DELTAS: %s", buf);
		
	} while ((bp = sp));
	
	mysql_free_result(res);
	return 0;
}

/*
 * Return node run command. We return the command to run, plus the UID
 * of the experiment creator to run it as!
 */
COMMAND_PROTOTYPE(dostartcmd)
{
	MYSQL_RES	*res;	
	MYSQL_ROW	row;
	char		buf[MYBUFSIZE];

	/*
	 * Now check reserved table
	 */
	if (!reqp->allocated)
		return 0;

	/*
	 * Get run command for the node.
	 */
	res = mydb_query("select startupcmd from nodes where node_id='%s'",
			 1, reqp->nodeid);

	if (!res) {
		error("STARTUPCMD: %s: DB Error getting startup command!\n",
		       reqp->nodeid);
		return 1;
	}

	if ((int)mysql_num_rows(res) == 0) {
		mysql_free_result(res);
		return 0;
	}

	/*
	 * Simple text string.
	 */
	row = mysql_fetch_row(res);
	if (! row[0] || !row[0][0]) {
		mysql_free_result(res);
		return 0;
	}
	OUTPUT(buf, sizeof(buf), "CMD='%s' UID=%s\n", row[0], reqp->swapper);
	mysql_free_result(res);
	client_writeback(sock, buf, strlen(buf), tcp);
	if (verbose)
		info("STARTUPCMD: %s", buf);
	
	return 0;
}

/*
 * Accept notification of start command exit status. 
 */
COMMAND_PROTOTYPE(dostartstat)
{
	int		exitstatus;

	/*
	 * Make sure currently allocated to an experiment!
	 */
	if (!reqp->allocated)
		return 0;

	/*
	 * Dig out the exit status
	 */
	if (! sscanf(rdata, "%d", &exitstatus)) {
		error("STARTSTAT: %s: Invalid status: %s\n",
		      reqp->nodeid, rdata);
		return 1;
	}

	if (verbose)
		info("STARTSTAT: "
		     "%s is reporting startup command exit status: %d\n",
		     reqp->nodeid, exitstatus);

	/*
	 * Update the node table record with the exit status. Setting the
	 * field to a non-null string value is enough to tell whoever is
	 * watching it that the node is done.
	 */
	if (mydb_update("update nodes set startstatus='%d' "
			"where node_id='%s'", exitstatus, reqp->nodeid)) {
		error("STARTSTAT: %s: DB Error setting exit status!\n",
		      reqp->nodeid);
		return 1;
	}
	return 0;
}

/*
 * Accept notification of ready for action
 */
COMMAND_PROTOTYPE(doready)
{
	/*
	 * Make sure currently allocated to an experiment!
	 */
	if (!reqp->allocated)
		return 0;

	/*
	 * Vnodes not allowed!
	 */
	if (reqp->isvnode)
		return 0;

	/*
	 * Update the ready_bits table.
	 */
	if (mydb_update("update nodes set ready=1 "
			"where node_id='%s'", reqp->nodeid)) {
		error("READY: %s: DB Error setting ready bit!\n",
		      reqp->nodeid);
		return 1;
	}

	if (verbose)
		info("READY: %s: Node is reporting ready\n", reqp->nodeid);

	/*
	 * Nothing is written back
	 */
	return 0;
}

/*
 * Return ready bits count (NofM)
 */
COMMAND_PROTOTYPE(doreadycount)
{
	MYSQL_RES	*res;	
	MYSQL_ROW	row;
	char		buf[MYBUFSIZE];
	int		total, ready, i;

	/*
	 * Make sure currently allocated to an experiment!
	 */
	if (!reqp->allocated)
		return 0;

	/*
	 * Vnodes not allowed!
	 */
	if (reqp->isvnode)
		return 0;

	/*
	 * See how many are ready. This is a non sync protocol. Clients
	 * keep asking until N and M are equal. Can only be used once
	 * of course, after experiment creation.
	 */
	res = mydb_query("select ready from reserved "
			 "left join nodes on nodes.node_id=reserved.node_id "
			 "where reserved.eid='%s' and reserved.pid='%s'",
			 1, reqp->eid, reqp->pid);

	if (!res) {
		error("READYCOUNT: %s: DB Error getting ready bits.\n",
		      reqp->nodeid);
		return 1;
	}

	ready = 0;
	total = (int) mysql_num_rows(res);
	if (total) {
		for (i = 0; i < total; i++) {
			row = mysql_fetch_row(res);

			if (atoi(row[0]))
				ready++;
		}
	}
	mysql_free_result(res);

	OUTPUT(buf, sizeof(buf), "READY=%d TOTAL=%d\n", ready, total);
	client_writeback(sock, buf, strlen(buf), tcp);

	if (verbose)
		info("READYCOUNT: %s: %s", reqp->nodeid, buf);

	return 0;
}

static char logfmt[] = "/proj/%s/logs/%s.log";

/*
 * Log some text to a file in the /proj/<pid>/exp/<eid> directory.
 */
COMMAND_PROTOTYPE(dolog)
{
	char		logfile[TBDB_FLEN_PID+TBDB_FLEN_EID+sizeof(logfmt)];
	FILE		*fd;
	time_t		curtime;
	char		*tstr;

	/*
	 * Find the pid/eid of the requesting node
	 */
	if (!reqp->allocated) {
		if (verbose)
			info("LOG: %s: Node is free\n", reqp->nodeid);
		return 1;
	}

	snprintf(logfile, sizeof(logfile)-1, logfmt, reqp->pid, reqp->eid);
	fd = fopen(logfile, "a");
	if (fd == NULL) {
		error("LOG: %s: Could not open %s\n", reqp->nodeid, logfile);
		return 1;
	}

	curtime = time(0);
	tstr = ctime(&curtime);
	tstr[19] = 0;	/* no year */
	tstr += 4;	/* or day of week */

	while (isspace(*rdata))
		rdata++;

	fprintf(fd, "%s: %s\n\n%s\n=======\n", tstr, reqp->nodeid, rdata);
	fclose(fd);

	return 0;
}

/*
 * Return mount stuff.
 */
COMMAND_PROTOTYPE(domounts)
{
	MYSQL_RES	*res;	
	MYSQL_ROW	row;
	char		buf[MYBUFSIZE];
	int		nrows;
	int		usesfs;

	/*
	 * Now check reserved table
	 */
	if (!reqp->allocated) {
		error("MOUNTS: %s: Node is free\n", reqp->nodeid);
		return 1;
	}

	/*
	 * Should SFS mounts be served?
	 */
	usesfs = 0;
	if (vers >= 6 && strlen(fshostid)) {
		if (strlen(reqp->sfshostid))
			usesfs = 1;
		else {
			while (*rdata && isspace(*rdata))
				rdata++;

			if (!strncmp(rdata, "USESFS=1", strlen("USESFS=1")))
				usesfs = 1;
		}

		if (verbose) {
			if (usesfs) {
				info("Using SFS\n");
			}
			else {
				info("Not using SFS\n");
			}
		}
	}

	/*
	 * Remote nodes must use SFS.
	 */
	if (!reqp->islocal && !usesfs)
		return 0;

	/*
	 * Jailed nodes (the phys or virt node) do not get mounts.
	 * Locally, though, the jailflag is not set on nodes (hmm,
	 * maybe fix that) so that the phys node still looks like it
	 * belongs to the experiment (people can log into it). 
	 */
	if (reqp->jailflag)
		return 0;
	
	/*
	 * If SFS is in use, the project mount is done via SFS.
	 */
	if (!usesfs) {
		/*
		 * Return project mount first. 
		 */
		OUTPUT(buf, sizeof(buf), "REMOTE=%s/%s LOCAL=%s/%s\n",
			FSPROJDIR, reqp->pid, PROJDIR, reqp->pid);
		client_writeback(sock, buf, strlen(buf), tcp);
		/* Leave this logging on all the time for now. */
		info("MOUNTS: %s", buf);
		
#ifdef FSSHAREDIR
		/*
		 * Return share mount if its defined.
		 */
		OUTPUT(buf, sizeof(buf),
		       "REMOTE=%s LOCAL=%s\n",FSSHAREDIR, SHAREDIR);
		client_writeback(sock, buf, strlen(buf), tcp);
		/* Leave this logging on all the time for now. */
		info("MOUNTS: %s", buf);
#endif
		/*
		 * If pid!=gid, then this is group experiment, and we return
		 * a mount for the group directory too.
		 */
		if (strcmp(reqp->pid, reqp->gid)) {
			OUTPUT(buf, sizeof(buf),
			       "REMOTE=%s/%s/%s LOCAL=%s/%s/%s\n",
			       FSGROUPDIR, reqp->pid, reqp->gid,
			       GROUPDIR, reqp->pid, reqp->gid);
			client_writeback(sock, buf, strlen(buf), tcp);
			/* Leave this logging on all the time for now. */
			info("MOUNTS: %s", buf);
		}
	}
	else {
		/*
		 * Return SFS-based mounts. Locally, we send back per
		 * project/group mounts (really symlinks) cause thats the
		 * local convention. For remote nodes, no point. Just send
		 * back mounts for the top level directories. 
		 */
		if (reqp->islocal) {
			OUTPUT(buf, sizeof(buf),
			       "SFS REMOTE=%s%s/%s LOCAL=%s/%s\n",
			       fshostid, FSDIR_PROJ, reqp->pid,
			       PROJDIR, reqp->pid);
			client_writeback(sock, buf, strlen(buf), tcp);
			if (verbose)
				info("MOUNTS: %s", buf);

			/*
			 * Return SFS-based group mount.
			 */
			if (strcmp(reqp->pid, reqp->gid)) {
				OUTPUT(buf, sizeof(buf),
				       "SFS REMOTE=%s%s/%s/%s LOCAL=%s/%s/%s\n",
				       fshostid,
				       FSDIR_GROUPS, reqp->pid, reqp->gid,
				       GROUPDIR, reqp->pid, reqp->gid);
				client_writeback(sock, buf, strlen(buf), tcp);
				info("MOUNTS: %s", buf);
			}
#ifdef FSSHAREDIR
			/*
			 * Pointer to /share.
			 */
			OUTPUT(buf, sizeof(buf), "SFS REMOTE=%s%s LOCAL=%s\n",
				fshostid, FSDIR_SHARE, SHAREDIR);
			client_writeback(sock, buf, strlen(buf), tcp);
			if (verbose)
				info("MOUNTS: %s", buf);
#endif
			/*
			 * Return a mount for "certprog dirsearch"
			 * that matches the local convention. This
			 * allows the same paths to work on remote
			 * nodes.
			 */
			OUTPUT(buf, sizeof(buf),
			       "SFS REMOTE=%s%s/%s LOCAL=%s%s\n",
			       fshostid, FSDIR_PROJ, DOTSFS, PROJDIR, DOTSFS);
			client_writeback(sock, buf, strlen(buf), tcp);
		}
		else {
			/*
			 * Remote nodes get slightly different mounts.
			 * in /netbed.
			 *
			 * Pointer to /proj.
			 */
			OUTPUT(buf, sizeof(buf), "SFS REMOTE=%s%s LOCAL=%s/%s\n",
				fshostid, FSDIR_PROJ, NETBEDDIR, PROJDIR);
			client_writeback(sock, buf, strlen(buf), tcp);
			info("MOUNTS: %s", buf);

			/*
			 * Pointer to /groups
			 */
			OUTPUT(buf, sizeof(buf), "SFS REMOTE=%s%s LOCAL=%s%s\n",
				fshostid, FSDIR_GROUPS, NETBEDDIR, GROUPDIR);
			client_writeback(sock, buf, strlen(buf), tcp);
			if (verbose)
				info("MOUNTS: %s", buf);

			/*
			 * Pointer to /users
			 */
			OUTPUT(buf, sizeof(buf), "SFS REMOTE=%s%s LOCAL=%s%s\n",
				fshostid, FSDIR_USERS, NETBEDDIR, USERDIR);
			client_writeback(sock, buf, strlen(buf), tcp);
			if (verbose)
				info("MOUNTS: %s", buf);
#ifdef FSSHAREDIR
			/*
			 * Pointer to /share.
			 */
			OUTPUT(buf, sizeof(buf), "SFS REMOTE=%s%s LOCAL=%s%s\n",
				fshostid, FSDIR_SHARE, NETBEDDIR, SHAREDIR);
			client_writeback(sock, buf, strlen(buf), tcp);
			if (verbose)
				info("MOUNTS: %s", buf);
#endif
		}
	}

	/*
	 * Remote nodes do not get per-user mounts. See above.
	 */
	if (!reqp->islocal)
		return 0;
	
	/*
	 * Now check for aux project access. Return a list of mounts for
	 * those projects.
	 */
	res = mydb_query("select pid from exppid_access "
			 "where exp_pid='%s' and exp_eid='%s'",
			 1, reqp->pid, reqp->eid);
	if (!res) {
		error("MOUNTS: %s: DB Error getting users!\n", reqp->pid);
		return 1;
	}

	if ((nrows = (int)mysql_num_rows(res))) {
		while (nrows) {
			row = mysql_fetch_row(res);
			
			OUTPUT(buf, sizeof(buf), "REMOTE=%s/%s LOCAL=%s/%s\n",
				FSPROJDIR, row[0], PROJDIR, row[0]);
			client_writeback(sock, buf, strlen(buf), tcp);

			nrows--;
		}
	}
	mysql_free_result(res);

	/*
	 * Now a list of user directories. These include the members of the
	 * experiments projects, plus all the members of all of the projects
	 * that have been granted access to share the nodes in that expt.
	 */
#ifdef  NOSHAREDEXPTS
	res = mydb_query("select u.uid from users as u "
			 "left join group_membership as p on p.uid=u.uid "
			 "where p.pid='%s' and p.gid='%s' and "
			 "      u.status='active' and p.trust!='none'",
			 1, reqp->pid, reqp->gid);
#else
	res = mydb_query("select distinct u.uid from users as u "
			 "left join exppid_access as a "
			 " on a.exp_pid='%s' and a.exp_eid='%s' "
			 "left join group_membership as p on p.uid=u.uid "
			 "where ((p.pid='%s' and p.gid='%s') or p.pid=a.pid) "
			 "       and u.status='active' and p.trust!='none'",
			 1, reqp->pid, reqp->eid, reqp->pid, reqp->gid);
#endif
	if (!res) {
		error("MOUNTS: %s: DB Error getting users!\n", reqp->pid);
		return 1;
	}

	if ((nrows = (int)mysql_num_rows(res)) == 0) {
		error("MOUNTS: %s: No Users!\n", reqp->pid);
		mysql_free_result(res);
		return 0;
	}

	while (nrows) {
		row = mysql_fetch_row(res);
				
		OUTPUT(buf, sizeof(buf), "REMOTE=%s/%s LOCAL=%s/%s\n",
			FSUSERDIR, row[0], USERDIR, row[0]);
		client_writeback(sock, buf, strlen(buf), tcp);
		
		nrows--;
		if (verbose)
		    info("MOUNTS: %s", buf);
	}
	mysql_free_result(res);

	return 0;
}

/*
 * Used by dosfshostid to make sure NFS doesn't give us problems.
 * (This code really unnerves me)
 */
int sfshostiddeadfl;
jmp_buf sfshostiddeadline;
static void
dosfshostiddead()
{
	sfshostiddeadfl = 1;
	longjmp(sfshostiddeadline, 1);
}

static int
safesymlink(char *name1, char *name2)
{
	/*
	 * Really, there should be a cleaner way of doing this, but
	 * this works, at least for now.  Perhaps using the DB and a
	 * symlinking deamon alone would be better.
	 */
	if (setjmp(sfshostiddeadline) == 0) {
		sfshostiddeadfl = 0;
		signal(SIGALRM, dosfshostiddead);
		alarm(1);

		unlink(name2);
		if (symlink(name1, name2) < 0) {
			sfshostiddeadfl = 1;
		}
	}
	alarm(0);
	if (sfshostiddeadfl) {
		errorc("symlinking %s to %s", name2, name1);
		return -1;
	}
	return 0;
}

/*
 * Create dirsearch entry for node.
 */
COMMAND_PROTOTYPE(dosfshostid)
{
	char	nodehostid[HOSTID_SIZE], buf[BUFSIZ];
	char	sfspath[BUFSIZ], dspath[BUFSIZ];

	if (!strlen(fshostid)) {
		/* SFS not being used */
		info("dosfshostid: Called while SFS is not in use\n");
		return 0;
	}
	
	/*
	 * Now check reserved table
	 */
	if (!reqp->allocated) {
		error("dosfshostid: %s: Node is free\n", reqp->nodeid);
		return 1;
	}

	/*
	 * Dig out the hostid. Need to be careful about not overflowing
	 * the buffer.
	 */
	sprintf(buf, "%%%ds", sizeof(nodehostid));
	if (! sscanf(rdata, buf, nodehostid)) {
		error("dosfshostid: No hostid reported!\n");
		return 1;
	}

	/*
	 * Create symlink names
	 */
	OUTPUT(sfspath, sizeof(sfspath), "/sfs/%s", nodehostid);
	OUTPUT(dspath, sizeof(dspath), "/proj/%s/%s.%s.%s", DOTSFS,
	       reqp->nickname, reqp->eid, reqp->pid);
	
	if (safesymlink(sfspath, dspath) < 0) {
		return 1;
	}

	/*
	 * Stash into the DB too.
	 */
	if (mydb_update("update nodes set sfshostid='%s' "
			"where node_id='%s'", nodehostid, reqp->nodeid)) {
		error("SFSHOSTID: %s: DB Error setting sfshostid!\n",
		      reqp->nodeid);
		return 1;
	}
	return 0;
}

/*
 * Return routing stuff.
 */
COMMAND_PROTOTYPE(dorouting)
{
	MYSQL_RES	*res;	
	MYSQL_ROW	row;
	char		buf[MYBUFSIZE];
	int		n, nrows;

	/*
	 * Now check reserved table
	 */
	if (!reqp->allocated) {
		error("ROUTES: %s: Node is free\n", reqp->nodeid);
		return 1;
	}

	/*
	 * Get the routing type from the nodes table.
	 */
	res = mydb_query("select routertype from nodes where node_id='%s'",
			 1, reqp->nodeid);

	if (!res) {
		error("ROUTES: %s: DB Error getting router type!\n",
		      reqp->nodeid);
		return 1;
	}

	if ((int)mysql_num_rows(res) == 0) {
		mysql_free_result(res);
		return 0;
	}

	/*
	 * Return type. At some point we might have to return a list of
	 * routes too, if we support static routes specified by the user
	 * in the NS file.
	 */
	row = mysql_fetch_row(res);
	if (! row[0] || !row[0][0]) {
		mysql_free_result(res);
		return 0;
	}
	OUTPUT(buf, sizeof(buf), "ROUTERTYPE=%s\n", row[0]);
	mysql_free_result(res);

	client_writeback(sock, buf, strlen(buf), tcp);
	if (verbose)
		info("ROUTES: %s", buf);

	/*
	 * Get the routing type from the nodes table.
	 */
	res = mydb_query("select dst,dst_type,dst_mask,nexthop,cost,src "
			 "from virt_routes as vi "
			 "where vi.vname='%s' and "
			 " vi.pid='%s' and vi.eid='%s'",
			 6, reqp->nickname, reqp->pid, reqp->eid);
	
	if (!res) {
		error("ROUTES: %s: DB Error getting manual routes!\n",
		      reqp->nodeid);
		return 1;
	}

	if ((nrows = (int)mysql_num_rows(res)) == 0) {
		mysql_free_result(res);
		return 0;
	}
	n = nrows;

	while (n) {
		char dstip[32];
		char *bufp = buf, *ebufp = &buf[sizeof(buf)];

		row = mysql_fetch_row(res);
				
		/*
		 * OMG, the Linux route command is too stupid to accept a
		 * host-on-a-subnet as the subnet address, so we gotta mask
		 * off the bits manually for network routes.
		 *
		 * Eventually we'll perform this operation in the NS parser
		 * so it appears in the DB correctly.
		 */
		if (strcmp(row[1], "net") == 0) {
			struct in_addr tip, tmask;

			inet_aton(row[0], &tip);
			inet_aton(row[2], &tmask);
			tip.s_addr &= tmask.s_addr;
			strncpy(dstip, inet_ntoa(tip), sizeof(dstip));
		} else
			strncpy(dstip, row[0], sizeof(dstip));

		bufp += OUTPUT(bufp, ebufp - bufp,
			       "ROUTE DEST=%s DESTTYPE=%s DESTMASK=%s "
			       "NEXTHOP=%s COST=%s",
			       dstip, row[1], row[2], row[3], row[4]);

		if (vers >= 12) {
			bufp += OUTPUT(bufp, ebufp - bufp, " SRC=%s", row[5]);
		}
		OUTPUT(bufp, ebufp - bufp, "\n");		
		client_writeback(sock, buf, strlen(buf), tcp);
		
		n--;
	}
	mysql_free_result(res);
	if (verbose)
	    info("ROUTES: %d routes in list\n", nrows);

	return 0;
}

/*
 * Return address from which to load an image, along with the partition that
 * it should be written to and the OS type in that partition.
 */
COMMAND_PROTOTYPE(doloadinfo)
{
	MYSQL_RES	*res;	
	MYSQL_ROW	row;
	char		buf[MYBUFSIZE];
	char		*bufp = buf, *ebufp = &buf[sizeof(buf)];
	char		*disktype;
	int		disknum;

	/*
	 * Get the address the node should contact to load its image
	 */
	res = mydb_query("select load_address,loadpart,OS "
			 "  from current_reloads as r "
			 "left join images as i on i.imageid = r.image_id "
			 "left join os_info as o on i.default_osid = o.osid "
			 "where node_id='%s'",
			 3, reqp->nodeid);

	if (!res) {
		error("doloadinfo: %s: DB Error getting loading address!\n",
		       reqp->nodeid);
		return 1;
	}

	if ((int)mysql_num_rows(res) == 0) {
		mysql_free_result(res);
		return 0;
	}

	/*
	 * Simple text string.
	 */
	row = mysql_fetch_row(res);
	if (! row[0] || !row[0][0]) {
		mysql_free_result(res);
		return 0;
	}

	bufp += OUTPUT(bufp, ebufp - bufp,
		       "ADDR=%s PART=%s PARTOS=%s", row[0], row[1], row[2]);
	mysql_free_result(res);

	/*
	 * Get disk type and number
	 */
	disktype = DISKTYPE;
	disknum = DISKNUM;
	res = mydb_query("select disktype from nodes as n "
			 "left join node_types as nt on n.type = nt.type "
			 "where n.node_id='%s'",
			 1, reqp->nodeid);
	if (!res) {
		error("doloadinfo: %s: DB Error getting disktype!\n",
		      reqp->nodeid);
		return 1;
	}

	if ((int)mysql_num_rows(res) > 0) {
		row = mysql_fetch_row(res);
		if (row[0] && row[0][0])
			disktype = row[0];
	}
	OUTPUT(bufp, ebufp - bufp, " DISK=%s%d\n", disktype, disknum);
	mysql_free_result(res);
	
	client_writeback(sock, buf, strlen(buf), tcp);
	if (verbose)
		info("doloadinfo: %s", buf);
	
	return 0;
}

/*
 * Have stated reset any next_pxe_boot_* and next_boot_* fields.
 * Produces no output to the client.
 */
COMMAND_PROTOTYPE(doreset)
{
#ifdef EVENTSYS
	address_tuple_t tuple;
	/*
	 * Send the state out via an event
	 */
	/* XXX: Maybe we don't need to alloc a new tuple every time through */
	tuple = address_tuple_alloc();
	if (tuple == NULL) {
		error("doreset: Unable to allocate address tuple!\n");
		return 1;
	}

	tuple->host      = BOSSNODE;
	tuple->objtype   = TBDB_OBJECTTYPE_TESTBED; /* "TBCONTROL" */
	tuple->objname	 = reqp->nodeid;
	tuple->eventtype = TBDB_EVENTTYPE_RESET;

	if (myevent_send(tuple)) {
		error("doreset: Error sending event\n");
		return 1;
	} else {
	        info("Reset event sent for %s\n", reqp->nodeid);
	} 
	
	address_tuple_free(tuple);
#else
	info("No event system - no reset performed.\n");
#endif
	return 0;
}

/*
 * Return trafgens info
 */
COMMAND_PROTOTYPE(dotrafgens)
{
	MYSQL_RES	*res;	
	MYSQL_ROW	row;
	char		buf[MYBUFSIZE];
	int		nrows;

	/*
	 * Now check reserved table
	 */
	if (!reqp->allocated) {
		error("TRAFGENS: %s: Node is free\n", reqp->nodeid);
		return 1;
	}

	res = mydb_query("select vi.vname,role,proto,"
			 "  vnode,port,ip,target_vnode,target_port,target_ip, "
			 "  generator "
			 " from virt_trafgens as vi "
			 "where vi.vnode='%s' and "
			 " vi.pid='%s' and vi.eid='%s'",
			 10, reqp->nickname, reqp->pid, reqp->eid);

	if (!res) {
		error("TRAFGENS: %s: DB Error getting virt_trafgens\n",
		      reqp->nodeid);
		return 1;
	}
	if ((nrows = (int)mysql_num_rows(res)) == 0) {
		mysql_free_result(res);
		return 0;
	}

	while (nrows) {
		char myname[TBDB_FLEN_VNAME+2];
		char peername[TBDB_FLEN_VNAME+2];
		
		row = mysql_fetch_row(res);

		if (row[5] && row[5][0]) {
			strcpy(myname, row[5]);
			strcpy(peername, row[8]);
		}
		else {
			/* This can go away once the table is purged */
			strcpy(myname, row[3]);
			strcat(myname, "-0");
			strcpy(peername, row[6]);
			strcat(peername, "-0");
		}

		OUTPUT(buf, sizeof(buf),
		        "TRAFGEN=%s MYNAME=%s MYPORT=%s "
			"PEERNAME=%s PEERPORT=%s "
			"PROTO=%s ROLE=%s GENERATOR=%s\n",
			row[0], myname, row[4], peername, row[7],
			row[2], row[1], row[9]);
		       
		client_writeback(sock, buf, strlen(buf), tcp);
		
		nrows--;
		if (verbose)
			info("TRAFGENS: %s", buf);
	}
	mysql_free_result(res);
	return 0;
}

/*
 * Return nseconfigs info
 */
COMMAND_PROTOTYPE(donseconfigs)
{
	MYSQL_RES	*res;	
	MYSQL_ROW	row;
	int		nrows;

	if (!tcp) {
		error("NSECONFIGS: %s: Cannot do UDP mode!\n", reqp->nodeid);
		return 1;
	}

	/*
	 * Now check reserved table
	 */
	if (!reqp->allocated) {
		error("NSECONFIGS: %s: Node is free\n", reqp->nodeid);
		return 1;
	}

	res = mydb_query("select nseconfig from nseconfigs as nse "
			 "where nse.vname='%s' and "
			 " nse.pid='%s' and nse.eid='%s'",
			 1, reqp->nickname, reqp->pid, reqp->eid);

	if (!res) {
		error("NSECONFIGS: %s: DB Error getting nseconfigs\n",
		      reqp->nodeid);
		return 1;
	}
	if ((nrows = (int)mysql_num_rows(res)) == 0) {
		mysql_free_result(res);
		return 0;
	}

	row = mysql_fetch_row(res);

	/*
	 * Just shove the whole thing out.
	 */
	if (row[0] && row[0][0]) {
		client_writeback(sock, row[0], strlen(row[0]), tcp);
	}
	mysql_free_result(res);
	return 0;
}

/*
 * Report that the node has entered a new state
 */
COMMAND_PROTOTYPE(dostate)
{
	char 		newstate[128];	/* More then we will ever need */
#ifdef EVENTSYS
	address_tuple_t tuple;
#endif

#ifdef LBS
	return 0;
#endif

	/*
	 * Dig out state that the node is reporting
	 */
	if (sscanf(rdata, "%128s", newstate) != 1 ||
	    strlen(newstate) == sizeof(newstate)) {
		error("DOSTATE: %s: Bad arguments\n", reqp->nodeid);
		return 1;
	}

#ifdef EVENTSYS
	/*
	 * Send the state out via an event
	 */
	/* XXX: Maybe we don't need to alloc a new tuple every time through */
	tuple = address_tuple_alloc();
	if (tuple == NULL) {
		error("dostate: Unable to allocate address tuple!\n");
		return 1;
	}

	tuple->host      = BOSSNODE;
	tuple->objtype   = "TBNODESTATE";
	tuple->objname	 = reqp->nodeid;
	tuple->eventtype = newstate;

	if (myevent_send(tuple)) {
		error("dostate: Error sending event\n");
		return 1;
	}

	address_tuple_free(tuple);
#endif /* EVENTSYS */
	
	/* Leave this logging on all the time for now. */
	info("STATE: %s\n", newstate);
	return 0;

}

/*
 * Return creator of experiment. Total hack. Must kill this.
 */
COMMAND_PROTOTYPE(docreator)
{
	char		buf[MYBUFSIZE];

	/*
	 * Now check reserved table
	 */
	if (!reqp->allocated)
		return 0;

	OUTPUT(buf, sizeof(buf), "CREATOR=%s\n", reqp->creator);
	client_writeback(sock, buf, strlen(buf), tcp);
	if (verbose)
		info("CREATOR: %s", buf);
	return 0;
}

/*
 * Return tunnels info.
 */
COMMAND_PROTOTYPE(dotunnels)
{
	MYSQL_RES	*res;	
	MYSQL_ROW	row;
	char		buf[MYBUFSIZE];
	int		nrows;

	/*
	 * Now check reserved table
	 */
	if (!reqp->allocated) {
		error("TRAFGENS: %s: Node is free\n", reqp->nodeid);
		return 1;
	}

	res = mydb_query("select vname,isserver,peer_ip,port,password, "
			 " encrypt,compress,assigned_ip,proto,mask "
			 "from tunnels where node_id='%s'",
			 10, reqp->nodeid);

	if (!res) {
		error("TUNNELS: %s: DB Error getting tunnels\n", reqp->nodeid);
		return 1;
	}
	if ((nrows = (int)mysql_num_rows(res)) == 0) {
		mysql_free_result(res);
		return 0;
	}

	while (nrows) {
		row = mysql_fetch_row(res);

		OUTPUT(buf, sizeof(buf),
		        "TUNNEL=%s ISSERVER=%s PEERIP=%s PEERPORT=%s "
			"PASSWORD=%s ENCRYPT=%s COMPRESS=%s "
			"INET=%s MASK=%s PROTO=%s\n",
			row[0], row[1], row[2], row[3], row[4],
			row[5], row[6], row[7], CHECKMASK(row[9]), row[8]);
		       
		client_writeback(sock, buf, strlen(buf), tcp);
		
		nrows--;
		if (verbose)
			info("TUNNELS: %s ISSERVER=%s PEERIP=%s "
			     "PEERPORT=%s INET=%s\n",
			     row[0], row[1], row[2], row[3], row[7]);
	}
	mysql_free_result(res);
	return 0;
}

/*
 * Return vnode list for a widearea node.
 */
COMMAND_PROTOTYPE(dovnodelist)
{
	MYSQL_RES	*res;	
	MYSQL_ROW	row;
	char		buf[MYBUFSIZE];
	int		nrows;

	res = mydb_query("select r.node_id,n.jailflag from reserved as r "
			 "left join nodes as n on r.node_id=n.node_id "
                         "left join node_types as nt on nt.type=n.type "
                         "where nt.isvirtnode=1 and n.phys_nodeid='%s'",
                         2, reqp->nodeid);

	if (!res) {
		error("VNODELIST: %s: DB Error getting vnode list\n",
		      reqp->nodeid);
		return 1;
	}
	if ((nrows = (int)mysql_num_rows(res)) == 0) {
		mysql_free_result(res);
		return 0;
	}

	while (nrows) {
		row = mysql_fetch_row(res);

		if (vers <= 6) {
			OUTPUT(buf, sizeof(buf), "%s\n", row[0]);
		}
		else {
			/* XXX Plab? */
			OUTPUT(buf, sizeof(buf),
			       "VNODEID=%s JAILED=%s\n", row[0], row[1]);
		}
		client_writeback(sock, buf, strlen(buf), tcp);
		
		nrows--;
		if (verbose)
			info("VNODELIST: %s", buf);
	}
	mysql_free_result(res);
	return 0;
}

/*
 * Return subnode list, and their types.
 */
COMMAND_PROTOTYPE(dosubnodelist)
{
	MYSQL_RES	*res;	
	MYSQL_ROW	row;
	char		buf[MYBUFSIZE];
	int		nrows;

	if (!reqp->allocated) {
		error("SUBNODE: %s: Node is free\n", reqp->nodeid);
		return 1;
	}

	res = mydb_query("select r.node_id,nt.class from reserved as r "
			 "left join nodes as n on r.node_id=n.node_id "
                         "left join node_types as nt on nt.type=n.type "
                         "where nt.issubnode=1 and n.phys_nodeid='%s'",
                         2, reqp->nodeid);

	if (!res) {
		error("SUBNODELIST: %s: DB Error getting vnode list\n",
		      reqp->nodeid);
		return 1;
	}
	if ((nrows = (int)mysql_num_rows(res)) == 0) {
		mysql_free_result(res);
		return 0;
	}

	while (nrows) {
		row = mysql_fetch_row(res);

		OUTPUT(buf, sizeof(buf), "NODEID=%s TYPE=%s\n", row[0], row[1]);
		client_writeback(sock, buf, strlen(buf), tcp);
		nrows--;
		if (verbose)
			info("SUBNODELIST: %s", buf);
	}
	mysql_free_result(res);
	return 0;
}

/*
 * DB stuff
 */
static MYSQL	db;
static int	db_connected;
static char     db_dbname[DBNAME_SIZE];
static void	mydb_disconnect();

static int
mydb_connect()
{
	/*
	 * Each time we talk to the DB, we check to see if the name
	 * matches the last connection. If so, nothing more needs to
	 * be done. If we switched DBs (checkdbredirect()), then drop
	 * the current connection and form a new one.
	 */
	if (db_connected) {
		if (strcmp(db_dbname, dbname) == 0)
			return 1;
		mydb_disconnect();
	}
	
	mysql_init(&db);
	if (mysql_real_connect(&db, 0, "tmcd", 0,
			       dbname, 0, 0, CLIENT_INTERACTIVE) == 0) {
		error("%s: connect failed: %s\n", dbname, mysql_error(&db));
		return 1;
	}
	strcpy(db_dbname, dbname);
	db_connected = 1;
	return 1;
}

static void
mydb_disconnect()
{
	mysql_close(&db);
	db_connected = 0;
}

MYSQL_RES *
mydb_query(char *query, int ncols, ...)
{
	MYSQL_RES	*res;
	char		querybuf[2*MYBUFSIZE];
	va_list		ap;
	int		n;

	va_start(ap, ncols);
	n = vsnprintf(querybuf, sizeof(querybuf), query, ap);
	if (n > sizeof(querybuf)) {
		error("query too long for buffer\n");
		return (MYSQL_RES *) 0;
	}

	if (! mydb_connect())
		return (MYSQL_RES *) 0;

	if (mysql_real_query(&db, querybuf, n) != 0) {
		error("%s: query failed: %s\n", dbname, mysql_error(&db));
		mydb_disconnect();
		return (MYSQL_RES *) 0;
	}

	res = mysql_store_result(&db);
	if (res == 0) {
		error("%s: store_result failed: %s\n",
		      dbname, mysql_error(&db));
		mydb_disconnect();
		return (MYSQL_RES *) 0;
	}

	if (ncols && ncols != (int)mysql_num_fields(res)) {
		error("%s: Wrong number of fields returned "
		      "Wanted %d, Got %d\n",
		      dbname, ncols, (int)mysql_num_fields(res));
		mysql_free_result(res);
		return (MYSQL_RES *) 0;
	}
	return res;
}

int
mydb_update(char *query, ...)
{
	char		querybuf[MYBUFSIZE];
	va_list		ap;
	int		n;

	va_start(ap, query);
	n = vsnprintf(querybuf, sizeof(querybuf), query, ap);
	if (n > sizeof(querybuf)) {
		error("query too long for buffer\n");
		return 1;
	}

	if (! mydb_connect())
		return 1;

	if (mysql_real_query(&db, querybuf, n) != 0) {
		error("%s: query failed: %s\n", dbname, mysql_error(&db));
		mydb_disconnect();
		return 1;
	}
	return 0;
}

/*
 * Map IP to node ID (plus other info).
 */
static int
iptonodeid(struct in_addr ipaddr, tmcdreq_t *reqp)
{
	MYSQL_RES	*res;
	MYSQL_ROW	row;

	/*
	 * I love a good query!
	 *
	 * The join on node_types using control_iface is to prevent the
	 * (unlikely) possibility that we get an experimental interface
	 * trying to contact us! I doubt that can happen though. 
	 *
	 * XXX Locally, the jail flag is not set on the phys node, only
	 * on the virtnodes. This is okay since all the routines that
	 * check jailflag also check to see if its a vnode or physnode. 
	 */
	if (reqp->isvnode) {
		res = mydb_query("select vt.class,vt.type,np.node_id,"
				 " nv.jailflag,r.pid,r.eid,r.vname, "
				 " e.gid,e.testdb,nv.update_accounts, "
				 " np.role,e.expt_head_uid,e.expt_swap_uid, "
				 " e.sync_server,pt.class,pt.type, "
				 " pt.isremotenode,vt.issubnode,e.keyhash, "
				 " nv.sfshostid,e.eventkey "
				 "from nodes as nv "
				 "left join interfaces as i on "
				 " i.node_id=nv.phys_nodeid "
				 "left join nodes as np on "
				 " np.node_id=nv.phys_nodeid "
				 "left join reserved as r on "
				 " r.node_id=nv.node_id "
				 "left join experiments as e on "
				 "  e.pid=r.pid and e.eid=r.eid "
				 "left join node_types as pt on "
				 " pt.type=np.type and "
				 " i.iface=pt.control_iface "
				 "left join node_types as vt on "
				 " vt.type=nv.type "
				 "where nv.node_id='%s' and i.IP='%s'",
				 21, reqp->vnodeid, inet_ntoa(ipaddr));
	}
	else {
		res = mydb_query("select t.class,t.type,n.node_id,n.jailflag,"
				 " r.pid,r.eid,r.vname,e.gid,e.testdb, "
				 " n.update_accounts,n.role, "
				 " e.expt_head_uid,e.expt_swap_uid, "
				 " e.sync_server,t.class,t.type, "
				 " t.isremotenode,t.issubnode,e.keyhash, "
				 " n.sfshostid,e.eventkey "
				 "from interfaces as i "
				 "left join nodes as n on n.node_id=i.node_id "
				 "left join reserved as r on "
				 "  r.node_id=i.node_id "
				 "left join experiments as e on "
				 " e.pid=r.pid and e.eid=r.eid "
				 "left join node_types as t on "
				 " t.type=n.type and i.iface=t.control_iface "
				 "where i.IP='%s'",
				 21, inet_ntoa(ipaddr));
	}

	if (!res) {
		error("iptonodeid: %s: DB Error getting interfaces!\n",
		      inet_ntoa(ipaddr));
		return 1;
	}

	if (! (int)mysql_num_rows(res)) {
		mysql_free_result(res);
		return 1;
	}
	row = mysql_fetch_row(res);
	mysql_free_result(res);

	if (!row[0] || !row[1] || !row[2]) {
		error("iptonodeid: %s: Malformed DB response!\n",
		      inet_ntoa(ipaddr)); 
		return 1;
	}
	strncpy(reqp->class,  row[0],  sizeof(reqp->class));
	strncpy(reqp->type,   row[1],  sizeof(reqp->type));
	strncpy(reqp->pclass, row[14], sizeof(reqp->pclass));
	strncpy(reqp->ptype,  row[15], sizeof(reqp->ptype));
	strncpy(reqp->nodeid, row[2],  sizeof(reqp->nodeid));
	reqp->islocal   = (! strcasecmp(row[16], "0") ? 1 : 0);
	reqp->jailflag  = (! strcasecmp(row[3],  "0") ? 0 : 1);
	reqp->issubnode = (! strcasecmp(row[17], "0") ? 0 : 1);
	if (row[8])
		strncpy(reqp->testdb, row[8], sizeof(reqp->testdb));
	if (row[4] && row[5]) {
		strncpy(reqp->pid, row[4], sizeof(reqp->pid));
		strncpy(reqp->eid, row[5], sizeof(reqp->eid));
		reqp->allocated = 1;

		if (row[6])
			strncpy(reqp->nickname, row[6],sizeof(reqp->nickname));
		else
			strcpy(reqp->nickname, reqp->nodeid);

		strcpy(reqp->creator, row[11]);
		if (row[12]) 
			strcpy(reqp->swapper, row[12]);
		else
			strcpy(reqp->swapper, reqp->creator);

		/*
		 * If there is no gid (yes, thats bad and a mistake), then 
		 * copy the pid in. Also warn.
		 */
		if (row[7])
			strncpy(reqp->gid, row[7], sizeof(reqp->gid));
		else {
			strcpy(reqp->gid, reqp->pid);
			error("iptonodeid: %s: No GID for %s/%s (pid/eid)!\n",
			      reqp->nodeid, reqp->pid, reqp->eid);
		}
		/* Sync server for the experiment */
		if (row[13]) 
			strcpy(reqp->syncserver, row[13]);
		/* keyhash for the experiment */
		if (row[18]) 
			strcpy(reqp->keyhash, row[18]);
		/* event key for the experiment */
		if (row[20]) 
			strcpy(reqp->eventkey, row[20]);
	}
	if (row[9])
		reqp->update_accounts = atoi(row[9]);
	else
		reqp->update_accounts = 0;

	/* SFS hostid for the node */
	if (row[19]) 
		strcpy(reqp->sfshostid, row[19]);
	
	reqp->iscontrol = (! strcasecmp(row[10], "ctrlnode") ? 1 : 0);

	/* If a vnode, copy into the nodeid. Eventually split this properly */
	strcpy(reqp->pnodeid, reqp->nodeid);
	if (reqp->isvnode) {
		strcpy(reqp->nodeid,  reqp->vnodeid);
	}
	
	return 0;
}
 
/*
 * Map nodeid to PID/EID pair.
 */
static int
nodeidtoexp(char *nodeid, char *pid, char *eid, char *gid)
{
	MYSQL_RES	*res;
	MYSQL_ROW	row;

	res = mydb_query("select r.pid,r.eid,e.gid from reserved as r "
			 "left join experiments as e on "
			 "     e.pid=r.pid and e.eid=r.eid "
			 "where node_id='%s'",
			 3, nodeid);
	if (!res) {
		error("nodeidtoexp: %s: DB Error getting reserved!\n", nodeid);
		return 1;
	}

	if (! (int)mysql_num_rows(res)) {
		mysql_free_result(res);
		return 1;
	}
	row = mysql_fetch_row(res);
	mysql_free_result(res);
	strncpy(pid, row[0], TBDB_FLEN_PID);
	strncpy(eid, row[1], TBDB_FLEN_EID);

	/*
	 * If there is no gid (yes, thats bad and a mistake), then copy
	 * the pid in. Also warn.
	 */
	if (row[2]) {
		strncpy(gid, row[2], TBDB_FLEN_GID);
	}
	else {
		strcpy(gid, pid);
		error("nodeidtoexp: %s: No GID for %s/%s (pid/eid)!\n",
		      nodeid, pid, eid);
	}

	return 0;
}
 
/*
 * Check for DBname redirection.
 */
static int
checkdbredirect(tmcdreq_t *reqp)
{
	if (! reqp->allocated || !strlen(reqp->testdb))
		return 0;

	/* This changes the DB we talk to. */
	strcpy(dbname, reqp->testdb);

	/*
	 * Okay, lets test to make sure that DB exists. If not, fall back
	 * on the main DB. 
	 */
	if (nodeidtoexp(reqp->nodeid, reqp->pid, reqp->eid, reqp->gid)) {
		error("CHECKDBREDIRECT: %s: %s DB does not exist\n",
		      reqp->nodeid, dbname);
		strcpy(dbname, DEFAULT_DBNAME);
	}
	return 0;
}

/*
 * Check private key. 
 */
static int
checkprivkey(struct in_addr ipaddr, char *privkey)
{
	MYSQL_RES	*res;
	MYSQL_ROW	row;

	res = mydb_query("select privkey from widearea_privkeys "
			 "where IP='%s'",
			 1, inet_ntoa(ipaddr));
	
	if (!res) {
		error("checkprivkey: %s: DB Error getting privkey!\n",
		      inet_ntoa(ipaddr));
		return 1;
	}

	if (! (int)mysql_num_rows(res)) {
		mysql_free_result(res);
		return 1;
	}
	row = mysql_fetch_row(res);
	mysql_free_result(res);
	if (! row[0] || !row[0][0])
		return 1;

	return strcmp(privkey, row[0]);
}
 
#ifdef EVENTSYS
/*
 * Connect to the event system. It's not an error to call this function if
 * already connected. Returns 1 on failure, 0 on sucess.
 */
int
event_connect()
{
	if (!event_handle) {
		event_handle = event_register("elvin://" BOSSNODE,0);
	}

	if (event_handle) {
		return 0;
	} else {
		error("event_connect: "
		      "Unable to register with event system!\n");
		return 1;
	}
}

/*
 * Send an event to the event system. Automatically connects (registers)
 * if not already done. Returns 0 on sucess, 1 on failure.
 */
int myevent_send(address_tuple_t tuple) {
	event_notification_t notification;

	if (event_connect()) {
		return 1;
	}

	notification = event_notification_alloc(event_handle,tuple);
	if (notification == NULL) {
		error("myevent_send: Unable to allocate notification!");
		return 1;
	}

	if (event_notify(event_handle, notification) == NULL) {
		event_notification_free(event_handle, notification);

		error("myevent_send: Unable to send notification!");
		/*
		 * Let's try to disconnect from the event system, so that
		 * we'll reconnect next time around.
		 */
		if (!event_unregister(event_handle)) {
			error("myevent_send: "
			      "Unable to unregister with event system!");
		}
		event_handle = NULL;
		return 1;
	} else {
		event_notification_free(event_handle,notification);
		return 0;
	}
}
#endif /* EVENTSYS */
 
/*
 * Lets hear it for global state...Yeah!
 */
static char udpbuf[8192];
static int udpfd = -1, udpix;

/*
 * Write back to client
 */
int
client_writeback(int sock, void *buf, int len, int tcp)
{
	int	cc;
	char	*bufp = (char *) buf;
	
	if (tcp) {
		while (len) {
			if ((cc = WRITE(sock, bufp, len)) <= 0) {
				if (cc < 0) {
					errorc("writing to TCP client");
					return -1;
				}
				error("write to TCP client aborted");
				return -1;
			}
			byteswritten += cc;
			len  -= cc;
			bufp += cc;
		}
	} else {
		if (udpfd != sock) {
			if (udpfd != -1)
				error("UDP reply in progress!?");
			udpfd = sock;
			udpix = 0;
		}
		if (udpix + len > sizeof(udpbuf)) {
			error("client data write truncated");
			len = sizeof(udpbuf) - udpix;
		}
		memcpy(&udpbuf[udpix], bufp, len);
		udpix += len;
	}
	return 0;
}

void
client_writeback_done(int sock, struct sockaddr_in *client)
{
	int err;

	/*
	 * XXX got an error before we wrote anything,
	 * still need to send a reply.
	 */
	if (udpfd == -1)
		udpfd = sock;

	if (sock != udpfd)
		error("UDP reply out of sync!");
	else if (udpix != 0) {
		err = sendto(udpfd, udpbuf, udpix, 0,
			     (struct sockaddr *)client, sizeof(*client));
		if (err < 0)
			errorc("writing to UDP client");
	}
	byteswritten = udpix;
	udpfd = -1;
	udpix = 0;
}

/*
 * IsAlive(). Mark nodes as being alive. 
 */
COMMAND_PROTOTYPE(doisalive)
{
	int		doaccounts = 0;
	char		buf[MYBUFSIZE];

	/*
	 * See db/node_status script, which uses this info (timestamps)
	 * to determine when nodes are down.
	 */
	mydb_update("replace delayed into node_status "
		    " (node_id, status, status_timestamp) "
		    " values ('%s', 'up', now())",
		    reqp->nodeid);

	/*
	 * Return info about what needs to be updated. 
	 */
	if (reqp->update_accounts)
		doaccounts = 1;
	
	/*
	 * At some point, maybe what we will do is have the client
	 * make a request asking what needs to be updated. Right now,
	 * just return yes/no and let the client assume it knows what
	 * to do (update accounts).
	 */
	OUTPUT(buf, sizeof(buf), "UPDATE=%d\n", doaccounts);
	client_writeback(sock, buf, strlen(buf), tcp);

	return 0;
}
  
/*
 * Return ipod info for a node
 */
COMMAND_PROTOTYPE(doipodinfo)
{
	char		buf[MYBUFSIZE], *bp;
	unsigned char	randdata[16], hashbuf[16*2+1];
	int		fd, cc, i;

	if (!tcp) {
		error("IPODINFO: %s: Cannot do this in UDP mode!\n",
		      reqp->nodeid);
		return 1;
	}

	if ((fd = open("/dev/urandom", O_RDONLY)) < 0) {
		errorc("opening /dev/urandom");
		return 1;
	}
	if ((cc = read(fd, randdata, sizeof(randdata))) < 0) {
		errorc("reading /dev/urandom");
		close(fd);
		return 1;
	}
	if (cc != sizeof(randdata)) {
		error("Short read from /dev/urandom: %d", cc);
		close(fd);
		return 1;
	}
	close(fd);

	bp = hashbuf;
	for (i = 0; i < sizeof(randdata); i++) {
		bp += sprintf(bp, "%02x", randdata[i]);
	}
	*bp = '\0';

	mydb_update("update nodes set ipodhash='%s' "
		    "where node_id='%s'",
		    hashbuf, reqp->nodeid);
	
	/*
	 * XXX host/mask hardwired to us
	 */
	OUTPUT(buf, sizeof(buf), "HOST=%s MASK=255.255.255.255 HASH=%s\n",
		inet_ntoa(myipaddr), hashbuf);
	client_writeback(sock, buf, strlen(buf), tcp);

	return 0;
}
  
/*
 * Return ntp config for a node. 
 */
COMMAND_PROTOTYPE(dontpinfo)
{
	MYSQL_RES	*res;	
	MYSQL_ROW	row;
	char		buf[MYBUFSIZE];
	int		nrows;

	if (!tcp) {
		error("NTPINFO: %s: Cannot do this in UDP mode!\n",
		      reqp->nodeid);
		return 1;
	}

	/*
	 * Node is allowed to be free?
	 */

	/*
	 * First get the servers and peers.
	 */
	res = mydb_query("select type,IP from ntpinfo where node_id='%s'",
			 2, reqp->nodeid);

	if (!res) {
		error("NTPINFO: %s: DB Error getting ntpinfo!\n",
		      reqp->nodeid);
		return 1;
	}
	
	if ((nrows = (int)mysql_num_rows(res))) {
		while (nrows) {
			row = mysql_fetch_row(res);
			if (row[0] && row[0][0] &&
			    row[1] && row[1][0]) {
				if (!strcmp(row[0], "peer")) {
					OUTPUT(buf, sizeof(buf),
					       "PEER=%s\n", row[1]);
				}
				else {
					OUTPUT(buf, sizeof(buf),
					       "SERVER=%s\n", row[1]);
				}
				client_writeback(sock, buf, strlen(buf), tcp);
				if (verbose)
					info("NTPINFO: %s", buf);
			}
			nrows--;
		}
	}
	mysql_free_result(res);

	/*
	 * Now get the drift.
	 */
	res = mydb_query("select ntpdrift from nodes "
			 "where node_id='%s' and ntpdrift is not null",
			 1, reqp->nodeid);

	if (!res) {
		error("NTPINFO: %s: DB Error getting ntpdrift!\n",
		      reqp->nodeid);
		return 1;
	}

	if ((int)mysql_num_rows(res)) {
		row = mysql_fetch_row(res);
		if (row[0] && row[0][0]) {
			OUTPUT(buf, sizeof(buf), "DRIFT=%s\n", row[0]);
			client_writeback(sock, buf, strlen(buf), tcp);
			if (verbose)
				info("NTPINFO: %s", buf);
		}
	}
	mysql_free_result(res);

	return 0;
}

/*
 * Upload the current ntp drift for a node.
 */
COMMAND_PROTOTYPE(dontpdrift)
{
	float		drift;

	if (!tcp) {
		error("NTPDRIFT: %s: Cannot do this in UDP mode!\n",
		      reqp->nodeid);
		return 1;
	}
	if (!reqp->islocal) {
		error("NTPDRIFT: %s: remote nodes not allowed!\n",
		      reqp->nodeid);
		return 1;
	}

	/*
	 * Node can be free?
	 */

	if (sscanf(rdata, "%f", &drift) != 1) {
		error("NTPDRIFT: %s: Bad argument\n", reqp->nodeid);
		return 1;
	}
	mydb_update("update nodes set ntpdrift='%f' where node_id='%s'",
		    drift, reqp->nodeid);

	if (verbose)
		info("NTPDRIFT: %f", drift);
	return 0;
}

static int sendafile(int sock, tmcdreq_t *reqp, int tcp, char *filename,
		     char *filetype, char *cmdname);

/*
 * Return a tarball.
 * The tarball being requested has to be in the tarballs list for the
 * node of course. Has to be a tcp connection of course, and all remote
 * tcp connections are required to be ssl'ized.
 */
COMMAND_PROTOTYPE(doatarball)
{
	MYSQL_RES	*res;	
	MYSQL_ROW	row;
	char		tarname[1024+1];
	int		okay = 0;
	char		*bp, *sp, *tp;

	/*
	 * Check reserved table
	 */
	if (!reqp->allocated) {
		error("GETTAR: %s: Node is free\n", reqp->nodeid);
		return 1;
	}

	/*
	 * Pick up the name from the argument. Limit to usual MAXPATHLEN.
	 */
	if (sscanf(rdata, "%1024s", tarname) != 1) {
		error("GETTAR: %s: Bad arguments\n", reqp->nodeid);
		return 1;
	}

	/*
	 * Get the tarball list from the DB. The requested path must be
	 * on the list of tarballs for this node.
	 */
	res = mydb_query("select tarballs from nodes where node_id='%s' ",
			 1, reqp->nodeid);

	if (!res) {
		error("GETTAR: %s: DB Error getting tarballs!\n",
		      reqp->nodeid);
		return 1;
	}

	if ((int)mysql_num_rows(res) == 0) {
		mysql_free_result(res);
		error("GETTAR: %s: Invalid Tarball: %s!\n",
		      reqp->nodeid, tarname);
		return 1;
	}

	/*
	 * Text string is a colon separated list of "dir filename". 
	 */
	row = mysql_fetch_row(res);
	if (! row[0] || !row[0][0]) {
		mysql_free_result(res);
		error("GETTAR: %s: Invalid Tarball: %s!\n",
		      reqp->nodeid, tarname);
		return 1;
	}
	
	bp  = row[0];
	sp  = bp;
	do {
		bp = strsep(&sp, ":");
		if ((tp = strchr(bp, ' ')) == NULL)
			continue;
		*tp++ = '\0';

		if (strcmp(tp, tarname) == 0) {
			okay = 1;
			break;
		}
	} while ((bp = sp));
	mysql_free_result(res);

	if (!okay) {
		error("GETTAR: %s: Invalid Tarball: %s!\n",
		      reqp->nodeid, tarname);
		return 1;
	}

	return sendafile(sock, reqp, tcp, tarname, "tarfile", "GETTAR");
}

/*
 * Return an RPM file.
 * The rpm being requested has to be in the rpms list for the
 * node of course. Has to be a tcp connection of course, and all remote
 * tcp connections are required to be ssl'ized.
 */
COMMAND_PROTOTYPE(doanrpm)
{
	MYSQL_RES	*res;	
	MYSQL_ROW	row;
	char		rpmname[1024+1];
	int		okay = 0;
	char		*bp, *sp;

	/*
	 * Check reserved table
	 */
	if (!reqp->allocated) {
		error("GETRPM: %s: Node is free\n", reqp->nodeid);
		return 1;
	}

	/*
	 * Pick up the name from the argument. Limit to usual MAXPATHLEN.
	 */
	if (sscanf(rdata, "%1024s", rpmname) != 1) {
		error("GETRPM: %s: Bad arguments\n", reqp->nodeid);
		return 1;
	}

	/*
	 * Get the rpm list from the DB. The requested path must be
	 * on the list of rpms for this node.
	 */
	res = mydb_query("select rpms from nodes where node_id='%s' ",
			 1, reqp->nodeid);

	if (!res) {
		error("GETRPM: %s: DB Error getting rpms!\n",
		      reqp->nodeid);
		return 1;
	}

	if ((int)mysql_num_rows(res) == 0) {
		mysql_free_result(res);
		error("GETRPM: %s: Invalid RPM: %s!\n",
		      reqp->nodeid, rpmname);
		return 1;
	}

	/*
	 * Text string is a colon separated list of filenames.
	 */
	row = mysql_fetch_row(res);
	if (! row[0] || !row[0][0]) {
		mysql_free_result(res);
		error("GETRPM: %s: Invalid RPM: %s!\n",
		      reqp->nodeid, rpmname);
		return 1;
	}
	
	bp  = row[0];
	sp  = bp;
	do {
		bp = strsep(&sp, ":");
		if (strcmp(bp, rpmname) == 0) {
			okay = 1;
			break;
		}
	} while ((bp = sp));
	mysql_free_result(res);

	if (!okay) {
		error("GETRPM: %s: Invalid RPM: %s!\n",
		      reqp->nodeid, rpmname);
		return 1;
	}

	return sendafile(sock, reqp, tcp, rpmname, "rpm", "GETRPM");
}

static int	safesyscall(int sysnum, ...);

/*
 * Return a tar or RPM file.  Verifies that the user has access to the file
 * in question.  If so, the file is sent back on the connection, prefixed by
 * the file's size.  It is up to the caller to ensure it is a registered tar
 * or RPM file.
 */
static int
sendafile(int sock, tmcdreq_t *reqp, int tcp, char *filename,
	  char *filetype, char *cmdname)
{
	char		buf[1024 * 32];
	int		cc, fd;
	char		*bp;
	struct stat	statbuf;
	struct group	*grp;
	struct passwd   *pwd;

	/*
	 * Ensure that we do not get tricked into returning a file outside
	 * of /proj, /users, or /groups. We could put a check in the frontend
	 * where tarfiles/rpms is set, but this is much safer given the
	 * potential for disaster.
	 *
	 * XXX I know, realpath is not really a syscall. 
	 */
	if (safesyscall(696969, filename, buf) == NULL) {
		errorc("%s: %s: realpath failure %s!",
		       cmdname, reqp->nodeid, filename);
		return 1;
	}
	if ((bp = strchr(&buf[1], '/')) == NULL) {
		errorc("%s: %s: could not parse %s!",
		       cmdname, reqp->nodeid, buf);
		return 1;
	}
	*bp = NULL;
	if (strcmp(buf, PROJDIR) &&
	    strcmp(buf, GROUPDIR) &&
	    strcmp(buf, USERDIR)) {
		*bp = '/';
		error("%s: %s: illegal path: %s --> %s!\n",
		      cmdname, reqp->nodeid, filename, buf);
		return 1;
	}
	*bp = '/';
	
	/*
	 * Better be readable!
	 */
	if ((fd = safesyscall(SYS_open, filename, O_RDONLY)) < 0) {
		errorc("%s: %s: Could not open %s!",
		       cmdname, reqp->nodeid, filename);
		return 1;
	}

	/*
	 * Stat the file so we get its size to send over first.
	 */
	if (safesyscall(SYS_fstat, fd, &statbuf) < 0) {
		errorc("%s: %s: Could not fstat %s!",
		       cmdname, reqp->nodeid, filename);
		goto bad;
	}

	/*
	 * As long as we did the stat, check the uid/gid to make doubly
	 * sure that we should hand this file out. Either the file has
	 * to be in the gid of the experiment, or it has to be owned
	 * by the experiment creator.
	 */
	if ((grp = getgrnam(reqp->gid)) == NULL) {
		error("%s: %s: Could map gid %s!",
		      cmdname, reqp->nodeid, reqp->gid);
		goto bad;
	}
	if (grp->gr_gid != statbuf.st_gid) {
		if ((pwd = getpwnam(reqp->creator)) == NULL) {
			error("%s: %s: Could map uid %s!",
			      cmdname, reqp->nodeid, reqp->creator);
			goto bad;
		}
		if (pwd->pw_uid != statbuf.st_uid) {
			error("%s: %s: %s %s has bad uid/gid (%d/%d)\n",
			      cmdname, reqp->nodeid, filetype, filename,
			      statbuf.st_uid, statbuf.st_gid);
			goto bad;
		}
	}
	
	cc = statbuf.st_size;
	client_writeback(sock, &cc, sizeof(cc), tcp);

	/* Leave this logging on all the time for now. */
	info("%s: %s: Sending %s (%d): %s\n",
	     cmdname, reqp->nodeid, filetype, cc, buf);

	/*
	 * Now dump the file. 
	 */
	while (1) {
	    if ((cc = safesyscall(SYS_read, fd, buf, sizeof(buf))) < 0) {
		errorc("Error reading %s: %s", filetype, filename);
		goto bad;
	    }
	    if (cc == 0)
		break;
	    
	    if (client_writeback(sock, buf, cc, tcp) < 0) {
		errorc("Error writing %s data: %s", filetype, filename);
		goto bad;
	    }
	}
	safesyscall(SYS_close, fd);
	return 0;
 bad:
	safesyscall(SYS_close, fd);
	return 1;
}

int nfsdeadfl;
jmp_buf nfsdeadbuf;
static void
nfswentdead()
{
	nfsdeadfl = 1;
	longjmp(nfsdeadbuf, 1);
}

static int
safesyscall(int sysnum, ...)
{
	volatile int	retval = 0;
	va_list		ap;

	if (setjmp(nfsdeadbuf) == 0) {
		va_start(ap, sysnum);

		retval    = 0;
		nfsdeadfl = 0;
		signal(SIGALRM, nfswentdead);
		alarm(2);

		switch (sysnum) {
		case SYS_open:
			{
				char   *path = va_arg(ap, char *);
				int	flags  = va_arg(ap, int);

				retval = open(path, flags);
			}
			break;

		case SYS_read:
			{
				int	fd     = va_arg(ap, int);
				void   *buf    = va_arg(ap, void *);
				size_t  nbytes = va_arg(ap, size_t);

				retval = read(fd, buf, nbytes);
			}
			break;

		case SYS_fstat:
			{
				int	     fd = va_arg(ap, int);
				struct stat *sb = va_arg(ap, struct stat *);

				retval = fstat(fd, sb);
			}
			break;

		case SYS_close:
			{
				int	fd = va_arg(ap, int);

				retval = close(fd);
			}
			break;

		case 696969:
			{
				char	*pathname = va_arg(ap, char *);
				char	*resolved = va_arg(ap, char *);

				retval = (int) realpath(pathname, resolved);
			}
			break;

		default:
			break;
		}
	}
	alarm(0);
	if (nfsdeadfl) {
		error("NFS wend dead");
		return -1;
	}
	return retval;
}

/*
 * Return the config for a virtual (jailed) node.
 */
COMMAND_PROTOTYPE(dojailconfig)
{
	MYSQL_RES	*res;	
	MYSQL_ROW	row;
	char		buf[MYBUFSIZE];
	char		*bufp = buf, *ebufp = &buf[sizeof(buf)];
	int		low, high;

	/*
	 * Only vnodes get a jailconfig of course, and only allocated ones.
	 */
	if (!reqp->isvnode) {
		/* Silent error is fine */
		return 0;
	}
	if (!reqp->allocated) {
		error("JAILCONFIG: %s: Node is free\n", reqp->nodeid);
		return 1;
	}
	if (!reqp->jailflag)
		return 0;

	/*
	 * Get the portrange for the experiment. Cons up the other params I
	 * can think of right now. 
	 */
	res = mydb_query("select low,high from ipport_ranges "
			 "where pid='%s' and eid='%s'",
			 2, reqp->pid, reqp->eid);
	
	if (!res) {
		error("JAILCONFIG: %s: DB Error getting config!\n",
		      reqp->nodeid);
		return 1;
	}

	if ((int)mysql_num_rows(res) == 0) {
		mysql_free_result(res);
		return 0;
	}
	row  = mysql_fetch_row(res);
	low  = atoi(row[0]);
	high = atoi(row[1]);
	mysql_free_result(res);

	/*
	 * Now need the sshdport and jailip for this node.
	 */
	res = mydb_query("select sshdport,jailip from nodes "
			 "where node_id='%s'",
			 2, reqp->nodeid);
	
	if (!res) {
		error("JAILCONFIG: %s: DB Error getting config!\n",
		      reqp->nodeid);
		return 1;
	}

	if ((int)mysql_num_rows(res) == 0) {
		mysql_free_result(res);
		return 0;
	}
	row   = mysql_fetch_row(res);

	bzero(buf, sizeof(buf));
	if (row[1]) {
		bufp += OUTPUT(bufp, ebufp - bufp,
			       "JAILIP=\"%s,%s\"\n", row[1], JAILIPMASK);
	}
	bufp += OUTPUT(bufp, ebufp - bufp,
		       "PORTRANGE=\"%d,%d\"\n"
		       "SSHDPORT=%d\n"
		       "SYSVIPC=1\n"
		       "INETRAW=1\n"
		       "BPFRO=1\n"
		       "INADDRANY=1\n"
		       "ROUTING=%d\n"
		       "DEVMEM=%d\n",
		       low, high, atoi(row[0]), reqp->islocal, reqp->islocal);

	client_writeback(sock, buf, strlen(buf), tcp);
	mysql_free_result(res);

	/*
	 * Now return the IP interface list that this jail has access to.
	 * These are tunnels or ip aliases on the real interfaces, but
	 * its easier just to consult the virt_nodes table. That table has
	 * a funky format, but thats okay.
	 */
	bufp  = buf;
	bufp += OUTPUT(bufp, ebufp - bufp, "IPADDRS=\"");

	res = mydb_query("select ips from virt_nodes "
			 "where vname='%s' and pid='%s' and eid='%s'",
			 1, reqp->nickname, reqp->pid, reqp->eid);

	if (!res) {
		error("JAILCONFIG: %s: DB Error getting virt_nodes table\n",
		      reqp->nodeid);
		return 1;
	}
	if (mysql_num_rows(res)) {
		char *bp, *cp, *ip;
			
		row = mysql_fetch_row(res);

		if (row[0] && row[0][0]) {
			bp = row[0];
			while (bp) {
				/*
				 * Note that the ips column is a space
				 * separated list of X:IP where X is a
				 * logical interface number.
				 */
				cp = strsep(&bp, ":");
				ip = strsep(&bp, " ");

				bufp += OUTPUT(bufp, ebufp - bufp, "%s", ip);
				if (bp)
					bufp += OUTPUT(bufp, ebufp - bufp, ",");
			}
		}
	}
	mysql_free_result(res);

	OUTPUT(bufp, ebufp - bufp, "\"\n");
	client_writeback(sock, buf, strlen(buf), tcp);
	return 0;
}

/*
 * Return the config for a virtual Plab node.
 */
COMMAND_PROTOTYPE(doplabconfig)
{
	MYSQL_RES	*res;	
	MYSQL_ROW	row;
	char		buf[MYBUFSIZE];

	if (!reqp->isvnode) {
		/* Silent error is fine */
		return 0;
	}
	if (!reqp->allocated) {
		error("PLABCONFIG: %s: Node is free\n", reqp->nodeid);
		return 1;
	}
	/* XXX Check for Plab-ness */

	/*
	 * Now need the sshdport for this node.
	 */
	res = mydb_query("select sshdport from nodes "
			 "where node_id='%s'",
			 1, reqp->nodeid);
	
	if (!res) {
		error("PLABCONFIG: %s: DB Error getting config!\n",
		      reqp->nodeid);
		return 1;
	}

	if ((int)mysql_num_rows(res) == 0) {
		mysql_free_result(res);
		return 0;
	}
	row   = mysql_fetch_row(res);

	OUTPUT(buf, sizeof(buf), "SSHDPORT=%d\n", atoi(row[0]));
	client_writeback(sock, buf, strlen(buf), tcp);
	mysql_free_result(res);

	/* XXX Anything else? */
	
	return 0;
}

/*
 * Return the config for a subnode (this is returned to the physnode).
 */
COMMAND_PROTOTYPE(dosubconfig)
{
	if (!reqp->issubnode) {
		error("SUBCONFIG: %s: Not a subnode\n", reqp->nodeid);
		return 1;
	}
	if (!reqp->allocated) {
		error("SUBCONFIG: %s: Node is free\n", reqp->nodeid);
		return 1;
	}

	if (! strcmp(reqp->type, "ixp-bv")) 
		return(doixpconfig(sock, reqp, rdata, tcp, vers));
	
	error("SUBCONFIG: %s: Invalid subnode class %s\n",
	      reqp->nodeid, reqp->class);
	return 1;
}

COMMAND_PROTOTYPE(doixpconfig)
{
	MYSQL_RES	*res;	
	MYSQL_ROW	row;
	char		buf[MYBUFSIZE];
	struct in_addr  mask_addr, bcast_addr;
	char		bcast_ip[16];

	/*
	 * Get the "control" net address for the IXP from the interfaces
	 * table. This is really a virtual pci/eth interface.
	 */
	res = mydb_query("select i1.IP,i1.iface,i2.iface,i2.mask,i2.IP "
			 " from nodes as n "
			 "left join node_types as nt on n.type=nt.type "
			 "left join interfaces as i1 on i1.node_id=n.node_id "
			 "     and i1.iface=nt.control_iface "
			 "left join interfaces as i2 on i2.node_id='%s' "
			 "     and i2.card=i1.card "
			 "where n.node_id='%s'",
			 5, reqp->pnodeid, reqp->nodeid);
	
	if (!res) {
		error("IXPCONFIG: %s: DB Error getting config!\n",
		      reqp->nodeid);
		return 1;
	}
	if ((int)mysql_num_rows(res) == 0) {
		mysql_free_result(res);
		return 0;
	}
	row   = mysql_fetch_row(res);
	if (!row[1]) {
		error("IXPCONFIG: %s: No IXP interface!\n", reqp->nodeid);
		return 1;
	}
	if (!row[2]) {
		error("IXPCONFIG: %s: No host interface!\n", reqp->nodeid);
		return 1;
	}
	if (!row[3]) {
		error("IXPCONFIG: %s: No mask!\n", reqp->nodeid);
		return 1;
	}
	inet_aton(CHECKMASK(row[3]), &mask_addr);	
	inet_aton(row[0], &bcast_addr);

	bcast_addr.s_addr = (bcast_addr.s_addr & mask_addr.s_addr) |
		(~mask_addr.s_addr);
	strcpy(bcast_ip, inet_ntoa(bcast_addr));

	OUTPUT(buf, sizeof(buf),
	       "IXP_IP=\"%s\"\n"
	       "IXP_IFACE=\"%s\"\n"
	       "IXP_BCAST=\"%s\"\n"
	       "IXP_HOSTNAME=\"%s\"\n"
	       "HOST_IP=\"%s\"\n"
	       "HOST_IFACE=\"%s\"\n"
	       "NETMASK=\"%s\"\n",
	       row[0], row[1], bcast_ip, reqp->nickname,
	       row[4], row[2], row[3]);
		
	client_writeback(sock, buf, strlen(buf), tcp);
	mysql_free_result(res);
	return 0;
}

/*
 * return slothd params - just compiled in for now.
 */
COMMAND_PROTOTYPE(doslothdparams) 
{
	char buf[MYBUFSIZE];
	
	OUTPUT(buf, sizeof(buf), "%s\n", SDPARAMS);
	client_writeback(sock, buf, strlen(buf), tcp);
	return 0;
}

/*
 * Return program agent info.
 */
COMMAND_PROTOTYPE(doprogagents)
{
	MYSQL_RES	*res;	
	MYSQL_ROW	row;
	char		buf[MYBUFSIZE];
	int		nrows;

	/*
	 * Now check reserved table
	 */
	if (!reqp->allocated) {
		error("PROGAGENTS: %s: Node is free\n", reqp->nodeid);
		return 1;
	}

	res = mydb_query("select vname,command from virt_programs "
			 "where vnode='%s' and pid='%s' and eid='%s'",
			 2, reqp->nickname, reqp->pid, reqp->eid);

	if (!res) {
		error("PROGRAM: %s: DB Error getting virt_agents\n",
		      reqp->nodeid);
		return 1;
	}
	if ((nrows = (int)mysql_num_rows(res)) == 0) {
		mysql_free_result(res);
		return 0;
	}
	/*
	 * First spit out the UID, then the agents one to a line.
	 */
	OUTPUT(buf, sizeof(buf), "UID=%s\n", reqp->swapper);
	client_writeback(sock, buf, strlen(buf), tcp);
	if (verbose)
		info("PROGAGENTS: %s", buf);
	
	while (nrows) {
		char	*bufp = buf, *ebufp = &buf[sizeof(buf)];
		
		row = mysql_fetch_row(res);

		bufp += OUTPUT(bufp, ebufp - bufp, "AGENT=%s", row[0]);
		if (vers >= 13)
			bufp += OUTPUT(bufp, ebufp - bufp,
				       " COMMAND='%s'", row[1]);
		OUTPUT(bufp, ebufp - bufp, "\n");
		client_writeback(sock, buf, strlen(buf), tcp);
		
		nrows--;
		if (verbose)
			info("PROGAGENTS: %s", buf);
	}
	mysql_free_result(res);
	return 0;
}

/*
 * Return sync server info.
 */
COMMAND_PROTOTYPE(dosyncserver)
{
	char		buf[MYBUFSIZE];

	/*
	 * Now check reserved table
	 */
	if (!reqp->allocated) {
		error("SYNCSERVER: %s: Node is free\n", reqp->nodeid);
		return 1;
	}
	if (!strlen(reqp->syncserver))
		return 0;

	OUTPUT(buf, sizeof(buf),
	       "SYNCSERVER SERVER='%s.%s.%s.%s' ISSERVER=%d\n",
	       reqp->syncserver,
	       reqp->eid, reqp->pid, OURDOMAIN,
	       (strcmp(reqp->syncserver, reqp->nickname) ? 0 : 1));
	client_writeback(sock, buf, strlen(buf), tcp);

	if (verbose)
		info("%s", buf);
	
	return 0;
}

/*
 * Return keyhash info
 */
COMMAND_PROTOTYPE(dokeyhash)
{
	char		buf[MYBUFSIZE];

	/*
	 * Now check reserved table
	 */
	if (!reqp->allocated) {
		error("KEYHASH: %s: Node is free\n", reqp->nodeid);
		return 1;
	}
	if (!strlen(reqp->keyhash))
		return 0;

	OUTPUT(buf, sizeof(buf), "KEYHASH HASH='%s'\n", reqp->keyhash);
	client_writeback(sock, buf, strlen(buf), tcp);

	if (verbose)
		info("%s", buf);
	
	return 0;
}

/*
 * Return eventkey info
 */
COMMAND_PROTOTYPE(doeventkey)
{
	char		buf[MYBUFSIZE];

	/*
	 * Now check reserved table
	 */
	if (!reqp->allocated) {
		error("EVENTKEY: %s: Node is free\n", reqp->nodeid);
		return 1;
	}
	if (!strlen(reqp->eventkey))
		return 0;

	OUTPUT(buf, sizeof(buf), "EVENTKEY KEY='%s'\n", reqp->eventkey);
	client_writeback(sock, buf, strlen(buf), tcp);

	if (verbose)
		info("%s", buf);
	
	return 0;
}

/*
 * Return entire config.
 */
COMMAND_PROTOTYPE(dofullconfig)
{
	char		buf[MYBUFSIZE];
	int		i;
	int		mask;

	/*
	 * Now check reserved table. If free, give it a minimal status
	 * section so that stuff works as normal. 
	 */
	if (!reqp->allocated) {
		error("FULLCONFIG: %s: Node is free\n", reqp->nodeid);
		return 1;
	}

	if (reqp->isvnode)
		mask = FULLCONFIG_VIRT;
	else
		mask = FULLCONFIG_PHYS;

	for (i = 0; i < numcommands; i++) {
		if (command_array[i].fullconfig & mask) {
			OUTPUT(buf, sizeof(buf),
			       "*** %s\n", command_array[i].cmdname);
			client_writeback(sock, buf, strlen(buf), tcp);
			command_array[i].func(sock, reqp, rdata, tcp, vers);
			client_writeback(sock, buf, strlen(buf), tcp);
		}
	}
	return 0;
}

