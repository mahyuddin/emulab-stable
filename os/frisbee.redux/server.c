/*
 * EMULAB-COPYRIGHT
 * Copyright (c) 2000-2002 University of Utah and the Flux Group.
 * All rights reserved.
 */

/*
 * Frisbee server
 */
#include <sys/types.h>
#include <sys/param.h>
#include <sys/time.h>
#include <sys/fcntl.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <pthread.h>
#include "decls.h"
#include "queue.h"

#include "trace.h"

/* Globals */
int		debug = 0;
int		tracing = 0;
int		dynburst = 0;
int		timeout = SERVER_INACTIVE_SECONDS;
int		readsize = SERVER_READ_SIZE;
volatile int	burstsize = SERVER_BURST_SIZE;
int		gapsize = SERVER_BURST_GAP;
int		portnum;
int		killme;
int		blockslost;
int		sendretries;
struct in_addr	mcastaddr;
struct in_addr	mcastif;
char	       *filename;
struct timeval  IdleTimeStamp;

/* Forward decls */
void		quit(int);
void		reinit(int);
static ssize_t	mypread(int fd, void *buf, size_t nbytes, off_t offset);
static int	calcburst(void);

#ifdef STATS
/*
 * Track duplicates for stats gathering
 */
char		*chunkmap;

/*
 * Stats gathering.
 */
struct {
	unsigned long	msgin;
	unsigned long	joins;
	unsigned long	leaves;
	unsigned long	requests;
	unsigned long	joinrep;
	unsigned long	blockssent;
	unsigned long	filereads;
	unsigned long	filebytes;
	unsigned long	partialreq;
	unsigned long   dupsent;
	unsigned long	qmerges;
	unsigned long	badpackets;
	unsigned long   blockslost;
	unsigned long	goesidle;
	unsigned long	wakeups;
} Stats;
#define DOSTAT(x)	(Stats.x)
#else
#define DOSTAT(x)
#endif

/*
 * This structure defines the file we are spitting back.
 */
struct FileInfo {
	int	fd;		/* Open file descriptor */
	int	blocks;		/* Number of BLOCKSIZE blocks */
	int	chunks;		/* Number of CHUNKSIZE chunks */
};
static struct FileInfo FileInfo;

/*
 * The work queue of regions a client has requested.
 */
typedef struct {
	queue_chain_t	chain;
	int		chunk;		/* Which chunk */
	int		block;		/* Which starting block */
	int		count;		/* How many blocks */
} WQelem_t;
static queue_head_t     WorkQ;
static pthread_mutex_t	WorkQLock;
static pthread_cond_t	WorkQCond;
static int		WorkQDelay = -1;
static int		WorkQSize = 0;
#ifdef STATS
static int		WorkQMax = 0;
#endif

/*
 * Work queue routines. The work queue is a time ordered list of chunk/blocks
 * pieces that a client is missing. When a request comes in, lock the list
 * and scan it for an existing work item that covers the new request. The new
 * request can be dropped if there already exists a Q item, since the client
 * is going to see that piece eventually.
 *
 * We use a spinlock to guard the work queue, which incidentally will protect
 * malloc/free.
 *
 * XXX - Clients make requests for chunk/block pieces they are
 * missing. For now, map that into an entire chunk and add it to the
 * work queue. This is going to result in a lot more data being sent
 * than is needed by the client, but lets wait and see if that
 * matters.
 */
static void
WorkQueueInit(void)
{
	pthread_mutex_init(&WorkQLock, NULL);
	pthread_cond_init(&WorkQCond, NULL);
	queue_init(&WorkQ);

	if (WorkQDelay < 0)
		WorkQDelay = sleeptime(1000, "workQ check delay");

#ifdef DOSTATS
	chunkmap = calloc(Fileinfo.blocks, 1);
#endif
}

static int
WorkQueueEnqueue(int chunk, int block, int blockcount)
{
	WQelem_t	*wqel;
	int		elt;

	pthread_mutex_lock(&WorkQLock);

	elt = 0;
	queue_iterate(&WorkQ, wqel, WQelem_t *, chain) {
		if (wqel->chunk == chunk) {
			/*
			 * Look for overlaps with existing requests and
			 * extend the already queued request accordingly.
			 */
			if (block < wqel->block + wqel->count &&
			    block + blockcount > wqel->block) {
				EVENT(1, EV_WORKOVERLAP, mcastaddr,
				      wqel->block, wqel->count,
				      block, blockcount);
				if (block < wqel->block)
					wqel->block = block;
				if (block + blockcount >
				    wqel->block + wqel->count)
					wqel->count = block + blockcount
						- wqel->block;
				pthread_mutex_unlock(&WorkQLock);
				EVENT(1, EV_WORKMERGE, mcastaddr,
				      chunk, wqel->block, wqel->count, elt);
				return 0;
			}
		}
		elt++;
	}

	if ((wqel = (WQelem_t *) calloc(1, sizeof(WQelem_t))) == NULL)
		fatal("WorkQueueEnqueue: No more memory");

	wqel->chunk = chunk;
	wqel->block = block;
	wqel->count = blockcount;
	queue_enter(&WorkQ, wqel, WQelem_t *, chain);
	WorkQSize++;
#ifdef STATS
	if (WorkQSize > WorkQMax)
		WorkQMax = WorkQSize;
#endif

	if (WorkQSize == 1)
		pthread_cond_signal(&WorkQCond);
	pthread_mutex_unlock(&WorkQLock);

	EVENT(1, EV_WORKENQ, mcastaddr, chunk, block, blockcount, WorkQSize);
	return 1;
}

static int
WorkQueueDequeue(int *chunk, int *block, int *blockcount)
{
	WQelem_t	*wqel;

	/*
	 * Wait for up to WorkQDelay usec for work
	 */
	pthread_mutex_lock(&WorkQLock);
	if (WorkQSize == 0) {
		struct timeval tv;
		struct timespec ts;

		gettimeofday(&tv, 0);
		ts.tv_nsec = tv.tv_usec * 1000 + WorkQDelay;
		if (ts.tv_nsec >= 1000000000) {
			ts.tv_sec = tv.tv_sec + 1;
			ts.tv_nsec -= 1000000000;
		} else
			ts.tv_sec = tv.tv_sec;

		do {
			if (pthread_cond_timedwait(&WorkQCond,
						   &WorkQLock, &ts) != 0) {
				pthread_mutex_unlock(&WorkQLock);
				return 0;
			}
			if (WorkQSize == 0)
				DOSTAT(wakeups++);
		} while (WorkQSize == 0);
	}
	
	queue_remove_first(&WorkQ, wqel, WQelem_t *, chain);
	*chunk = wqel->chunk;
	*block = wqel->block;
	*blockcount = wqel->count;
	free(wqel);
	WorkQSize--;

	pthread_mutex_unlock(&WorkQLock);

	EVENT(1, EV_WORKDEQ, mcastaddr,
	      *chunk, *block, *blockcount, WorkQSize);
	return 1;
}

/*
 * A client joins. We print out the time at which the client joins, and
 * return a reply packet with the number of chunks in the file so that
 * the client knows how much to ask for. We do not do anything else with
 * this info; clients can crash and go away and it does not matter. If they
 * crash they will start up again later. Inactivity is defined as a period
 * with no data block requests. The client will resend its join message
 * until it gets a reply back; duplicates of either the request or the
 * reply are harmless.
 */
static void
ClientJoin(Packet_t *p)
{
	struct in_addr	ipaddr   = { p->hdr.srcip };
	unsigned int    clientid = p->msg.join.clientid;

	/*
	 * Return fileinfo. Duplicates are harmless.
	 */
	EVENT(1, EV_JOINREQ, ipaddr, clientid, 0, 0, 0);
	p->hdr.type            = PKTTYPE_REPLY;
	p->hdr.datalen         = sizeof(p->msg.join);
	p->msg.join.blockcount = FileInfo.blocks;
	PacketReply(p);
	DOSTAT(joinrep++);
	EVENT(1, EV_JOINREP, ipaddr, FileInfo.blocks, 0, 0, 0);

	/*
	 * Log after we send reply so that we get the packet off as
	 * quickly as possible!
	 */
	log("%s (id %u) joins at %s!",
	    inet_ntoa(ipaddr), clientid, CurrentTimeString());
}

/*
 * A client leaves. Not much to it. All we do is print out a log statement
 * about it so that we can see the time. If the packet is lost, no big deal.
 */
static void
ClientLeave(Packet_t *p)
{
	struct in_addr	ipaddr = { p->hdr.srcip };

	EVENT(1, EV_LEAVEMSG, ipaddr,
	      p->msg.leave.clientid, p->msg.leave.elapsed, 0, 0);

	log("%s (id %u): leaves at %s, ran for %d seconds.",
	    inet_ntoa(ipaddr), p->msg.leave.clientid, CurrentTimeString(),
	    p->msg.leave.elapsed);
}

/*
 * A client leaves. Not much to it. All we do is print out a log statement
 * about it so that we can see the time. If the packet is lost, no big deal.
 */
static void
ClientLeave2(Packet_t *p)
{
	struct in_addr	ipaddr = { p->hdr.srcip };

	EVENT(1, EV_LEAVEMSG, ipaddr,
	      p->msg.leave2.clientid, p->msg.leave2.elapsed, 0, 0);

	log("%s (id %u): leaves at %s, ran for %d seconds.",
	    inet_ntoa(ipaddr), p->msg.leave2.clientid, CurrentTimeString(),
	    p->msg.leave2.elapsed);

#ifdef STATS
	ClientStatsDump(p->msg.leave2.clientid, &p->msg.leave2.stats);
#endif
}

/*
 * A client requests a chunk/block. Add to the workqueue, but do not
 * send a reply. The client will make a new request later if the packet
 * got lost.
 */
static void
ClientRequest(Packet_t *p)
{
	struct in_addr	ipaddr = { p->hdr.srcip };
	int		chunk = p->msg.request.chunk;
	int		block = p->msg.request.block;
	int		count = p->msg.request.count;
	int		enqueued;

	EVENT(1, EV_REQMSG, ipaddr, chunk, block, count, 0);
	if (block + count > CHUNKSIZE)
		fatal("Bad request from %s - chunk:%d block:%d size:%d", 
		      inet_ntoa(ipaddr), chunk, block, count);

	if (count != CHUNKSIZE) {
		DOSTAT(partialreq++);
		DOSTAT(blockslost+=count);
		blockslost += count;
	}

	enqueued = WorkQueueEnqueue(chunk, block, count);
	if (!enqueued)
		DOSTAT(qmerges++);
#ifdef DOSTATS
	else if (chunkmap != 0 && count == CHUNKSIZE) {
		if (chunkmap[chunk]) {
			if (debug)
				log("Duplicate chunk request: %d", chunk);
			DOSTAT(dupsent++);
		} else
			chunkmap[chunk] = 1;
	}
#endif

	if (debug > 1) {
		log("Client %s requests chunk:%d block:%d size:%d new:%d",
		    inet_ntoa(ipaddr), chunk, block, count, enqueued);
	}
}

/*
 * The server receive thread. This thread does nothing more than receive
 * request packets from the clients, and add to the work queue.
 */
void *
ServerRecvThread(void *arg)
{
	Packet_t	packet, *p = &packet;

	if (debug > 1)
		log("Server pthread starting up ...");
	
	while (1) {
		pthread_testcancel();
		if (PacketReceive(p) < 0) {
			continue;
		}
		DOSTAT(msgin++);

		if (! PacketValid(p, FileInfo.chunks)) {
			DOSTAT(badpackets++);
			log("received bad packet %d/%d, ignored",
			    p->hdr.type, p->hdr.subtype);
			continue;
		}

		switch (p->hdr.subtype) {
		case PKTSUBTYPE_JOIN:
			DOSTAT(joins++);
			ClientJoin(p);
			break;
		case PKTSUBTYPE_LEAVE:
			DOSTAT(leaves++);
			ClientLeave(p);
			break;
		case PKTSUBTYPE_LEAVE2:
			DOSTAT(leaves++);
			ClientLeave2(p);
			break;
		case PKTSUBTYPE_REQUEST:
			DOSTAT(requests++);
			ClientRequest(p);
			break;
		}
	}
}

/*
 * The main thread spits out blocks. 
 *
 * NOTES: Perhaps use readv into a vector of packet buffers?
 */
static void
PlayFrisbee(void)
{
	int		chunk, block, blockcount, cc, j, idlelastloop = 0;
	int		startblock, lastblock, throttle = 0;
	Packet_t	packet, *p = &packet;
	char		*databuf;
	off_t		offset;

	if ((databuf = malloc(readsize * BLOCKSIZE)) == NULL)
		fatal("could not allocate read buffer");

	while (1) {
		if (killme)
			return;
		
		/*
		 * Look for a WorkQ item to process. When there is nothing
		 * to process, check for being idle too long, and exit if
		 * no one asks for anything for a long time. Note that
		 * WorkQueueDequeue will delay for a while, so this will not
		 * spin.
		 */
		if (! WorkQueueDequeue(&chunk, &startblock, &blockcount)) {
			throttle = 0;

			/* If zero, never exit */
			if (timeout == 0)
				continue;
			
			if (idlelastloop) {
				struct timeval  estamp;

				gettimeofday(&estamp, 0);

				if ((estamp.tv_sec - IdleTimeStamp.tv_sec) >
				    timeout) {
					log("No requests for %d seconds!",
					    timeout);
					break;
				}
			}
			else {
				DOSTAT(goesidle++);
				gettimeofday(&IdleTimeStamp, 0);
				idlelastloop = 1;
			}
			continue;
		}
		idlelastloop = 0;
		
		lastblock = startblock + blockcount;

		/* Offset within the file */
		offset = (((off_t) BLOCKSIZE * chunk * CHUNKSIZE) +
			  ((off_t) BLOCKSIZE * startblock));

		for (block = startblock; block < lastblock; ) {
			int	readcount;
			int	readbytes;
			int	resends;
			
			/*
			 * Read blocks of data from disk.
			 */
			if (lastblock - block > readsize)
				readcount = readsize;
			else
				readcount = lastblock - block;
			readbytes = readcount * BLOCKSIZE;

			if ((cc = mypread(FileInfo.fd, databuf,
					  readbytes, offset)) <= 0) {
				if (cc < 0)
					pfatal("Reading File");
				fatal("EOF on file");
			}
			DOSTAT(filereads++);
			DOSTAT(filebytes += cc);
			EVENT(2, EV_READFILE, mcastaddr,
			      offset, readbytes, cc, 0);
			if (cc != readbytes)
				fatal("Short read: %d!=%d", cc, readbytes);

			for (j = 0; j < readcount; j++) {
				p->hdr.type    = PKTTYPE_REQUEST;
				p->hdr.subtype = PKTSUBTYPE_BLOCK;
				p->hdr.datalen = sizeof(p->msg.block);
				p->msg.block.chunk = chunk;
				p->msg.block.block = block + j;
				memcpy(p->msg.block.buf,
				       &databuf[j * BLOCKSIZE],
				       BLOCKSIZE);

				PacketSend(p, &resends);
				sendretries += resends;
				DOSTAT(blockssent++);
				EVENT(3, EV_BLOCKMSG, mcastaddr,
				      chunk, block+j, 0, 0);

				/*
				 * Completed a burst.  Adjust the busrtsize
				 * if necessary and delay as required.
				 */
				if (++throttle >= burstsize) {
					if (dynburst)
						calcburst();
					if (gapsize > 0)
						fsleep(gapsize);
					throttle = 0;
				}
			}
			offset   += readbytes;
			block    += readcount;
		}
	}
	free(databuf);
}

char *usagestr = 
 "usage: frisbeed [-d] <-p #> <-m mcastaddr> <filename>\n"
 " -d              Turn on debugging. Multiple -d options increase output.\n"
 " -p portnum      Specify a port number to listen on.\n"
 " -m mcastaddr    Specify a multicast address in dotted notation.\n"
 " -i mcastif      Specify a multicast interface in dotted notation.\n"
 " -b              Use broadcast instead of multicast\n"
 "\n";

void
usage()
{
	fprintf(stderr, usagestr);
	exit(1);
}

int
main(int argc, char **argv)
{
	int		ch, fd;
	pthread_t	child_pid;
	off_t		fsize;
	void		*ignored;

	while ((ch = getopt(argc, argv, "dhp:m:i:tbDT:R:B:G:")) != -1)
		switch(ch) {
		case 'b':
			broadcast++;
			break;
			
		case 'd':
			debug++;
			break;
			
		case 'p':
			portnum = atoi(optarg);
			break;
			
		case 'm':
			inet_aton(optarg, &mcastaddr);
			break;

		case 'i':
			inet_aton(optarg, &mcastif);
			break;
		case 't':
			tracing++;
			break;
		case 'D':
			dynburst = 1;
			break;
		case 'T':
			timeout = atoi(optarg);
			break;
		case 'R':
			readsize = atoi(optarg);
			break;
		case 'B':
			burstsize = atoi(optarg);
			break;
		case 'G':
			gapsize = atoi(optarg);
			break;
		case 'h':
		case '?':
		default:
			usage();
		}
	argc -= optind;
	argv += optind;
	if (argc != 1)
		usage();

	gapsize = sleeptime(gapsize, "inter-burst delay");

	/*
	 * For the dynamic rate throttle, we need to increase the maximum
	 * burstsize to induce loss at the start.  Also need the gapsize
	 * to be the min possible.
	 */
	if (dynburst) {
		int ngap;

		if (burstsize != SERVER_DYNBURST_SIZE) {
			warning("adjusting burstsize for dynamic throttle");
			burstsize = SERVER_DYNBURST_SIZE;
		}
		ngap = sleeptime(1000, 0);
		if (gapsize != ngap) {
			warning("adjusting gapsize for dynamic throttle");
			gapsize = ngap;
		}
	}

	if (!portnum || ! mcastaddr.s_addr)
		usage();

	signal(SIGINT, quit);
	signal(SIGTERM, quit);
	signal(SIGHUP, reinit);

	ServerLogInit();
	
	filename = argv[0];
	if (access(filename, R_OK) < 0)
		pfatal("Cannot read %s", filename);

	/*
	 * Open the file and get its size so that we can tell clients how
	 * much to expect/require.
	 */
	if ((fd = open(filename, O_RDONLY)) < 0)
		pfatal("Cannot open %s", filename);

	if ((fsize = lseek(fd, (off_t)0, SEEK_END)) < 0)
		pfatal("Cannot lseek to end of file");

	FileInfo.fd     = fd;
	FileInfo.blocks = (int) roundup(fsize, BLOCKSIZE) / BLOCKSIZE;
	FileInfo.chunks = FileInfo.blocks / CHUNKSIZE;
	log("Opened %s: %d blocks", filename, FileInfo.blocks);

	WorkQueueInit();

	/*
	 * Everything else done, now init the network.
	 */
	ServerNetInit();

	if (tracing) {
		ServerTraceInit("frisbeed");
		TraceStart(tracing);
	}

	/*
	 * Create the subthread to listen for packets.
	 */
	if (pthread_create(&child_pid, NULL, ServerRecvThread, (void *)0)) {
		fatal("Failed to create pthread!");
	}
	gettimeofday(&IdleTimeStamp, 0);
	
	PlayFrisbee();
	pthread_cancel(child_pid);
	pthread_join(child_pid, &ignored);

	if (tracing) {
		TraceStop();
		TraceDump();
	}

#ifdef  STATS
	{
		extern unsigned long nonetbufs;

		log("Params:");
		log("  chunk/block size  %d/%d", CHUNKSIZE, BLOCKSIZE);
		log("  burst size/gap    %d/%d", burstsize, gapsize);
		log("  file read size    %d", readsize);
		log("  file:size         %s:%qd",
		    filename, (long long)fsize);
		log("Stats:");
		log("  msgs in/out:      %d/%d",
		    Stats.msgin, Stats.joinrep + Stats.blockssent);
		log("  joins/leaves:     %d/%d", Stats.joins, Stats.leaves);
		log("  requests:         %d (%d merged in queue)",
		    Stats.requests, Stats.qmerges);
		log("  partial/dup req:  %d/%d",
		    Stats.partialreq, Stats.dupsent);
		log("  1k blocks sent:   %d (%d repeated)",
		    Stats.blockssent, Stats.blockssent - FileInfo.blocks);
		log("  file reads:       %d (%d bytes, %d repeated)",
		    Stats.filereads, Stats.filebytes,
		    Stats.filebytes - FileInfo.blocks * BLOCKSIZE);
		log("  net idle/blocked: %d/%d", Stats.goesidle, nonetbufs);
		log("  spurious wakeups: %d", Stats.wakeups);
		log("  max workq size:   %d", WorkQMax);
	}
#endif

	/*
	 * Exit from main thread will kill all the children.
	 */
	log("Exiting!");
	exit(0);
}

/*
 * We catch the signals, but do not do anything. We exit with 0 status
 * for these, since it indicates a desired shutdown.
 */
void
quit(int sig)
{
	killme = 1;
}

/*
 * We cannot reinit, so exit with non-zero to indicate it was unexpected.
 */
void
reinit(int sig)
{
	log("Caught signal %d. Exiting ...", sig);
	exit(1);
}

#define NFS_READ_DELAY	100000

/*
 * Wrap up pread with a retry mechanism to help protect against
 * transient NFS errors.
 */
static ssize_t
mypread(int fd, void *buf, size_t nbytes, off_t offset)
{
	int		cc, i, count = 0;

	while (nbytes) {
		int	maxretries = 100;

		for (i = 0; i < maxretries; i++) {
			cc = pread(fd, buf, nbytes, offset);
			if (cc == 0)
				fatal("EOF on file");

			if (cc > 0) {
				nbytes -= cc;
				buf    += cc;
				offset += cc;
				count  += cc;
				goto again;
			}

			if (i == 0)
				pwarning("read error: will retry");

			fsleep(NFS_READ_DELAY);
		}
		pfatal("read error: busted for too long");
		return -1;
	again:
	}
	return count;
}

#define LOSS_THRESHOLD	30

/*
 * Should we consider PacketSend retries?   They indicated that we are over
 * driving the socket?  Even though they have a builtin delay between retries,
 * we might be better off detecting the case and avoiding the delays.
 *
 * From Dave:
 *
 * A smoother one that is still fair with TCP is:
 *    W_{next} = W_{cur} - sqrt( W_{cur} ) if loss
 *    W_{next} = W_{cur} + 1 / sqrt( W_{cur} )  if no loss
 */
static int
calcburst(void)
{
	static int		lastblockslost, lastsendretries;
	static struct timeval	laststamp;
	struct timeval		estamp;
	long			msdiff;
	int			lost, tweaked = 0;

	if (! laststamp.tv_sec)
		gettimeofday(&laststamp, 0);
	gettimeofday(&estamp, 0);

	msdiff  = (estamp.tv_sec  - laststamp.tv_sec)  * 1000;
	msdiff += (estamp.tv_usec - laststamp.tv_usec) / 1000;
	lost    = blockslost - lastblockslost;

#if 0
	/* XXX experiment: for send socket overflows as a decrement event */
	if (sendretries - lastsendretries > 2) {
		if (burstsize <= 20)
			burstsize -= 1;
		else {
			burstsize -= (burstsize / 20);
		}
		tweaked = 1;
		if (debug)
			log("Decrement burstsize to %d (%ld), "
			    "sendretries up by %d",
			    burstsize, msdiff, sendretries - lastsendretries);
	} else
#endif
	if (lost) {
		/*
		 * Decrement the burstsize slowly.
		 */
		if (lost > LOSS_THRESHOLD && msdiff > 150 && burstsize > 1) {
			if (burstsize <= 20)
				burstsize -= 1;
			else {
				burstsize -= (burstsize / 20);
			}
			tweaked = 1;
			fsleep(gapsize);
			if (debug)
				log("Decrement burstsize to %d (%ld), "
				    "blockslost up by %d",
				    burstsize, msdiff, lost);
		}
	}
	else if (burstsize < SERVER_DYNBURST_SIZE) {
		/*
		 * Increment the burstsize even more slowly.
		 */
		if (msdiff > 500) {
			burstsize++;
			tweaked = 1;
			if (debug)
				log("Increment burstsize to %d (%ld)",
				    burstsize, msdiff);
		}
	}

	if (tweaked) {
		laststamp = estamp;
		lastblockslost = blockslost;
		lastsendretries = sendretries;
	}
	return 0;
}
