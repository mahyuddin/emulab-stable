/*
 * Copyright (c) 1998-2000 Luigi Rizzo, Universita` di Pisa
 * Portions Copyright (c) 2000 Akamba Corp.
 * All rights reserved
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 * $FreeBSD$
 */

#define DEB(x)
#define DDB(x)	x

/*
 * This module implements IP dummynet, a bandwidth limiter/delay emulator
 * used in conjunction with the ipfw package.
 *
 * Most important Changes:
 *
 * 000106: large rewrite, use heaps to handle very many pipes.
 * 980513:	initial release
 *
 * include files marked with XXX are probably not needed
 */

#include <sys/param.h>
#include <sys/systm.h>
#include <sys/malloc.h>
#include <sys/mbuf.h>
#include <sys/queue.h>			/* XXX */
#include <sys/kernel.h>
#include <sys/socket.h>
#include <sys/socketvar.h>
#include <sys/time.h>
#include <sys/sysctl.h>
#include <net/if.h>
#include <net/route.h>
#include <netinet/in.h>
#include <netinet/in_systm.h>
#include <netinet/in_var.h>
#include <netinet/ip.h>
#include <netinet/ip_fw.h>
#include <netinet/ip_dummynet.h>
#include <netinet/ip_var.h>

#include "opt_bdg.h"
#ifdef BRIDGE
#include <netinet/if_ether.h> /* for struct arpcom */
#include <net/bridge.h>
#endif

/*
 * we keep a private variable for the simulation time, but probably
 * it would be better to use the already existing one "softticks"
 * (in sys/kern/kern_timer.c)
 */
static dn_key curr_time = 0 ; /* current simulation time */

static int dn_hash_size = 64 ;	/* default hash size */

/* statistics on number of queue searches and search steps */
static int searches, search_steps ;
static int pipe_expire = 0 ;	/* expire queue if empty */
static int dn_max_ratio = 16 ; /* max queues/buckets ratio */

static struct dn_heap ready_heap, extract_heap ;
static int heap_init(struct dn_heap *h, int size) ;
static int heap_insert (struct dn_heap *h, dn_key key1, void *p);
static void heap_extract(struct dn_heap *h);
static void transmit_event(struct dn_pipe *pipe);
static void ready_event(struct dn_flow_queue *q);
static struct dn_flow_queue * find_queue(struct dn_pipe *pipe);
static struct dn_pipe *all_pipes = NULL ;	/* list of all pipes */

#ifdef SYSCTL_NODE
SYSCTL_NODE(_net_inet_ip, OID_AUTO, dummynet,
		CTLFLAG_RW, 0, "Dummynet");
SYSCTL_INT(_net_inet_ip_dummynet, OID_AUTO, hash_size,
	    CTLFLAG_RW, &dn_hash_size, 0, "Default hash table size");
SYSCTL_INT(_net_inet_ip_dummynet, OID_AUTO, curr_time,
	    CTLFLAG_RD, &curr_time, 0, "Current tick");
SYSCTL_INT(_net_inet_ip_dummynet, OID_AUTO, ready_heap,
	    CTLFLAG_RD, &ready_heap.size, 0, "Size of ready heap");
SYSCTL_INT(_net_inet_ip_dummynet, OID_AUTO, extract_heap,
	    CTLFLAG_RD, &extract_heap.size, 0, "Size of extract heap");
SYSCTL_INT(_net_inet_ip_dummynet, OID_AUTO, searches,
	    CTLFLAG_RD, &searches, 0, "Number of queue searches");
SYSCTL_INT(_net_inet_ip_dummynet, OID_AUTO, search_steps,
	    CTLFLAG_RD, &search_steps, 0, "Number of queue search steps");
SYSCTL_INT(_net_inet_ip_dummynet, OID_AUTO, expire,
	    CTLFLAG_RW, &pipe_expire, 0, "Expire queue if empty");
SYSCTL_INT(_net_inet_ip_dummynet, OID_AUTO, max_chain_len,
	    CTLFLAG_RW, &dn_max_ratio, 0, 
	"Max ratio between dynamic queues and buckets");
#endif

static int ip_dn_ctl(struct sockopt *sopt);

static void rt_unref(struct rtentry *);
static void dummynet(void *);
static void dummynet_flush(void);

/*
 * ip_fw_chain is used when deleting a pipe, because ipfw rules can
 * hold references to the pipe.
 */
extern LIST_HEAD (ip_fw_head, ip_fw_chain) ip_fw_chain;

static void
rt_unref(struct rtentry *rt)
{
    if (rt == NULL)
	return ;
    if (rt->rt_refcnt <= 0)
	printf("-- warning, refcnt now %ld, decreasing\n", rt->rt_refcnt);
    RTFREE(rt);
}

/*
 * Heap management functions.
 *
 * In the heap, first node is element 0. Children of i are 2i+1 and 2i+2.
 * Some macros help finding parent/children so we can optimize them.
 *
 * heap_init() is called to expand the heap when needed.
 * Increment size in blocks of 256 entries (which make one 4KB page)
 * XXX failure to allocate a new element is a pretty bad failure
 * as we basically stall a whole queue forever!!
 * Returns 1 on error, 0 on success
 */
#define HEAP_FATHER(x) ( ( (x) - 1 ) / 2 )
#define HEAP_LEFT(x) ( 2*(x) + 1 )
#define HEAP_IS_LEFT(x) ( (x) & 1 )
#define HEAP_RIGHT(x) ( 2*(x) + 1 )
#define	HEAP_SWAP(a, b, buffer) { buffer = a ; a = b ; b = buffer ; }
#define HEAP_INCREMENT	255

static int
heap_init(struct dn_heap *h, int new_size)
{       
    struct dn_heap_entry *p;

    if (h->size >= new_size ) {
	printf("heap_init, Bogus call, have %d want %d\n",
		h->size, new_size);
	return 0 ;
    }   
    new_size = (new_size + HEAP_INCREMENT ) & ~HEAP_INCREMENT ;
    p = malloc(new_size * sizeof(*p), M_IPFW, M_DONTWAIT );
    if (p == NULL) {
	printf(" heap_init, resize %d failed\n", new_size );
	return 1 ; /* error */
    }
    if (h->size > 0) {
	bcopy(h->p, p, h->size * sizeof(*p) );
	free(h->p, M_IPFW);
    }
    h->p = p ;
    h->size = new_size ;
    return 0 ;
}

/*
 * Insert element in heap. Normally, p != NULL, we insert p in
 * a new position and bubble up. If p == NULL, then the element is
 * already in place, and key is the position where to start the
 * bubble-up.
 * Returns 1 on failure (cannot allocate new heap entry)
 */
static int
heap_insert(struct dn_heap *h, dn_key key1, void *p)
{   
    int son = h->elements ;

    if (p == NULL)	/* data already there, set starting point */
	son = key1 ;
    else {		/* insert new element at the end, possibly resize */
	son = h->elements ;
	if (son == h->size) /* need resize... */
	    if (heap_init(h, h->elements+1) )
		return 1 ; /* failure... */
	h->p[son].object = p ;
	h->p[son].key = key1 ;
	h->elements++ ;
    }
    while (son > 0) {				/* bubble up */
	int father = HEAP_FATHER(son) ;
	struct dn_heap_entry tmp  ;

	if (DN_KEY_LT( h->p[father].key, h->p[son].key ) )
	    break ; /* found right position */ 
	/* son smaller than father, swap and try again */
	HEAP_SWAP(h->p[son], h->p[father], tmp) ;
	son = father ;
    }
    return 0 ;
}

/*
 * remove top element from heap
 */
static void
heap_extract(struct dn_heap *h)
{  
    int child, father, max = h->elements - 1 ;
    if (max < 0)
	return ;

    /* move up smallest child */
    father = 0 ;
    child = HEAP_LEFT(father) ;		/* left child */
    while (child <= max) {		/* valid entry */
	if (child != max && DN_KEY_LT(h->p[child+1].key, h->p[child].key) )
	    child = child+1 ;		/* take right child, otherwise left */
	h->p[father] = h->p[child] ;
	father = child ;
	child = HEAP_LEFT(child) ;   /* left child for next loop */
    }   
    h->elements-- ;
    if (father != max) {
	/*
	 * Fill hole with last entry and bubble up, reusing the insert code
	 */
	h->p[father] = h->p[max] ;
	heap_insert(h, father, NULL); /* this one cannot fail */
    }   
}	   

/*
 * heapify() will reorganize data inside an array to maintain the
 * heap property. It is needed when we delete a bunch of entries.
 */
static void
heapify(struct dn_heap *h)
{
    int father, i ;
    struct dn_heap_entry tmp ;

    for (i = h->elements - 1 ; i > 0 ; i-- ) {
	father = HEAP_FATHER(i) ;
	if ( DN_KEY_LT(h->p[i].key, h->p[father].key) )
	    HEAP_SWAP(h->p[father], h->p[i], tmp) ;
    }
}
/*
 * --- end of heap management functions ---
 */

/*
 * called when dropping a packet
 * to determine when we will want to drop another.
 */
static void
droppkt(struct dn_pipe *p)
{
    /* CONST_RATE was handled when we first received the packet */
    switch (p->lossdist) {
	case DN_DIST_CONST_TIME:
	    p->nextdroptime = curr_time + p->lossmean;
	    break;
	case DN_DIST_TABLE_DETERM:
	    p->losstablepos = ++p->losstablepos % p->lossentries;
	    p->nextdroptime = curr_time + p->losstable[p->losstablepos];
	    break;
	default: /* leave it alone */
    }
    find_queue(p) ->drops++;	/* drops counted in the queue */
}
    
/*
 * Scheduler functions -- transmit_event(), ready_event()
 *
 * transmit_event() is called when the delay-line needs to enter
 * the scheduler, either because of existing pkts getting ready,
 * or new packets entering the queue. The event handled is the delivery
 * time of the packet.
 *
 * ready_event() does something similar with flow queues, and the
 * event handled is the finish time of the head pkt.
 *
 * In both cases, we make sure that the data structures are consistent
 * before passing pkts out, because this might trigger recursive
 * invocations of the procedures.
 */
static void
transmit_event(struct dn_pipe *pipe)
{
    struct dn_pkt *pkt ;

    while ( (pkt = pipe->p.head) && DN_KEY_LEQ(pkt->output_time, curr_time) ) {
	/*
	 * first unlink, then call procedures, since ip_input() can invoke
	 * ip_output() and viceversa, thus causing nested calls
	 */
	pipe->p.head = DN_NEXT(pkt) ;

	/*
	 * The actual mbuf is preceded by a struct dn_pkt, resembling an mbuf
	 * (NOT A REAL one, just a small block of malloc'ed memory) with
	 *     m_type = MT_DUMMYNET
	 *     m_next = actual mbuf to be processed by ip_input/output
	 *     m_data = the matching rule
	 * and some other fields.
	 * The block IS FREED HERE because it contains parameters passed
	 * to the called routine.
	 */
	switch (pkt->dn_dir) {
	case DN_TO_IP_OUT:
	    if (pipe->nextdroptime <= curr_time)	/* drop it? */
		droppkt(pipe);
	    else
		(void)ip_output((struct mbuf *)pkt, NULL, NULL, 0, NULL);
	    rt_unref (pkt->ro.ro_rt) ;
	    break ;

	case DN_TO_IP_IN :
	    if (pipe->nextdroptime <= curr_time)	/* drop it? */
		droppkt(pipe);
	    else
		ip_input((struct mbuf *)pkt) ;
	    break ;
#ifdef BRIDGE
	case DN_TO_BDG_FWD : {
	    struct mbuf *m = (struct mbuf *)pkt ;
	    if (pipe->nextdroptime <= curr_time)	/* drop it? */
		droppkt(pipe);
	    else
		bdg_forward(&m, pkt->ifp);
	    if (m)
		m_freem(m);
	    }
	    break ;
#endif

	default:
	    printf("dummynet: bad switch %d!\n", pkt->dn_dir);
	    m_freem(pkt->dn_m);
	    break ;
	}
	FREE(pkt, M_IPFW);
    }
    /* if there are leftover packets, put into the heap for next event */
    if ( (pkt = pipe->p.head) )
	 heap_insert(&extract_heap, pkt->output_time, pipe ) ;
    /* XXX should check errors on heap_insert, by draining the
     * whole pipe p and hoping in the future we are more successful
     */
}

/*
 * delay_ticks() is invoked for each packet to determine how many ticks
 * it should be delayed.
 */
static int
delay_ticks(struct dn_pipe *p)
{
    int delay = 0;
    switch (p->delaydist) {
	case DN_DIST_CONST_TIME:
	    delay=p->delay;  /* precomputed for this case */
	    break;
	case DN_DIST_UNIFORM:
	    /* we need a number somewhere between 
	     * (mean - 2*variance) aka minimum and
	     * (mean + 2*variance) aka maximum
	     */
	    delay=random() % ( 4 * p->delayvar)
		+ (p->delaymean - 2 * p->delayvar);
	    delay=delay*hz/1000; /* ms -> ticks */
	    break;
	case DN_DIST_POISSON:	/* curr. implemented as random table */
	case DN_DIST_TABLE_RANDOM:
	    delay=p->delaytable[random() % p->delayentries];
	    delay=delay*hz/1000; /* ms -> ticks */
	    break;
	case DN_DIST_TABLE_DETERM:
	    p->delaytablepos = ++p->delaytablepos % p->delayentries;
	    delay = p->delaytable[p->delaytablepos];
	    delay=delay*hz/1000; /* ms -> ticks */
	    break;
	default: /* no delay */
    }
    return delay;
}

/*  
 * update current bandwidth value
 *
 * ip_dummynet.h claims that bw is bytes/tick, but my suspicion is that
 * it is bits/second.
 */     
static void
updatebw(struct dn_pipe *p)
{   
   switch(p->bwdist) {
        case DN_DIST_UNIFORM:
            /* we need a number somewhere between
             * (mean - 2*variance) aka minimum and
             * (mean + 2*variance) aka maximum
             */
            p->bandwidth = random() % ( 4 * p->bwvar)
                           + (p->bwmean - 2 * p->bwvar);
            break;
	case DN_DIST_TABLE_DETERM:
            p->bwtablepos = ++p->bwtablepos % p->bwentries;
	    p->bandwidth = p->bwtable[p->bwtablepos];
            break;
	case DN_DIST_POISSON:   /* curr. implemented as random table */
	case DN_DIST_TABLE_RANDOM:
	    p->bandwidth = p->bwtable[random() % p->bwentries];
        default: /* no action */
    }   
}

/*
 * ready_event() is invoked every time the queue must enter the
 * scheduler, either because the first packet arrives, or because
 * a previously scheduled event fired.
 * On invocation, drain as many pkts as possible (could be 0) and then
 * if there are leftover packets reinsert the pkt in the scheduler.
 */
static void
ready_event(struct dn_flow_queue *q)
{
    struct dn_pkt *pkt;
    struct dn_pipe *p = q->p ;
    int p_was_empty = (p->p.head == NULL) ;

    if (p->bwquantum_expire <= curr_time) {
	do {
	    p->bwquantum_expire += p->bwquantum;
	} while (p->bwquantum_expire <= curr_time);

	updatebw(p);
    }
    while ( (pkt = q->r.head) != NULL ) {
	int len = pkt->dn_m->m_pkthdr.len;
	int len_scaled = p->bandwidth ? len*8*hz : 0 ;
	/*
	 * bandwidth==0 (no limit) means we can drain as many pkts as
	 * needed from the queue. Setting len_scaled = 0 does the job.
	 */
	if (len_scaled > q->numbytes )
	    break ;
	/*
	 * extract pkt from queue, compute output time (could be now)
	 * and put into delay line (p_queue)
	 */
	q->numbytes -= len_scaled ;
	q->r.head = DN_NEXT(pkt) ;
	q->len-- ;
	q->len_bytes -= len ;

	pkt->output_time = curr_time + delay_ticks(p);
	if (p->p.head == NULL)
	    p->p.head = pkt;
	else
	    DN_NEXT(p->p.tail) = pkt;
	p->p.tail = pkt;
	DN_NEXT(p->p.tail) = NULL;
    }
    /*
     * If we have more packets queued, schedule next ready event
     * (can only occur when bandwidth != 0, otherwise we would have
     * flushed the whole queue in the previous loop).
     * To this purpose compute how many ticks to go for the next
     * event, accounting for packet size and residual credit. This means
     * we compute the finish time of the packet.
     */
    if ( (pkt = q->r.head) != NULL ) { /* this implies bandwidth != 0 */
	dn_key t ;
	t = (pkt->dn_m->m_pkthdr.len*8*hz - q->numbytes + p->bandwidth - 1 ) /
		p->bandwidth ;
	/* the bandwidth could change mid-packet. we will have to calculate
	 * the time to send the remainder of the pkt when this happens
	 */
	if (curr_time + t > p->bwquantum_expire)
		t = p->bwquantum_expire - curr_time;

	q->numbytes += t * p->bandwidth ;
	heap_insert(&ready_heap, curr_time + t, (void *)q );
	/* XXX should check errors on heap_insert, and drain the whole
	 * queue on error hoping next time we are luckier.
	 */
    }
    /*
     * If the delay line was empty call transmit_event(p) now.
     * Otherwise, the scheduler will take care of it.
     */
    if (p_was_empty)
	transmit_event(p);
}

/*
 * this is called once per tick, or HZ times per second. It is used to
 * increment the current tick counter and schedule expired events.
 */
static void
dummynet(void * __unused unused)
{
    void *p ; /* generic parameter to handler */
    struct dn_heap *h ;
    int s ;

    s = splnet(); /* avoid network interrupts... */
    curr_time++ ;
    h = &ready_heap ;
    while (h->elements > 0 && DN_KEY_LEQ(h->p[0].key, curr_time) ) {
	/*
	 * XXX if the event is late, we should probably credit the queue
	 * by q->p->bandwidth * (delta_ticks). On the other hand, i dont
	 * think this can ever occur with this code (i.e. curr_time will
	 * still be incremented by one at each tick. Things might be
	 * different if we were using the counter from the high priority
	 * timer.
	 */
	if (h->p[0].key != curr_time)
	    printf("-- dummynet: warning, event is %d ticks late\n",
		curr_time - h->p[0].key);
	p = h->p[0].object ;
	heap_extract(h); /* need to extract before processing */
	ready_event(p) ;
    }
    h = &extract_heap ;
    while (h->elements > 0 && DN_KEY_LEQ(h->p[0].key, curr_time) ) {
	if (h->p[0].key != curr_time)	/* XXX same as above */
	    printf("-- dummynet: warning, event is %d ticks late\n",
		curr_time - h->p[0].key);
	p = h->p[0].object ;
	heap_extract(&extract_heap);
	transmit_event(p);
    }
    splx(s);
    timeout(dummynet, NULL, 1);
}
 
/*
 * Unconditionally expire empty queues in case of shortage.
 * Returns the number of queues freed.
 */
static int
expire_queues(struct dn_pipe *pipe)
{
    struct dn_flow_queue *q, *prev ;
    int i, initial_elements = pipe->rq_elements ;

    if (pipe->last_expired == time_second)
	return 0 ;
    pipe->last_expired = time_second ;
    for (i = 0 ; i <= pipe->rq_size ; i++) /* last one is overflow */
	for (prev=NULL, q = pipe->rq[i] ; q != NULL ; )
	    if (q->r.head != NULL) {
		prev = q ;
		q = q->next ;
	    } else { /* entry is idle, expire it */
		struct dn_flow_queue *old_q = q ;

		if (prev != NULL)
		    prev->next = q = q->next ;
		else
		    pipe->rq[i] = q = q->next ;
		pipe->rq_elements-- ;
		free(old_q, M_IPFW);
	    }
    return initial_elements - pipe->rq_elements ;
}

/*
 * If room, create a new queue and put at head of slot i;
 * otherwise, create or use the default queue.
 */
static struct dn_flow_queue *
create_queue(struct dn_pipe *pipe, int i)
{
    struct dn_flow_queue *q ;

    if (pipe->rq_elements > pipe->rq_size * dn_max_ratio &&
	    expire_queues(pipe) == 0) {
	/*
	 * No way to get room, use or create overflow queue.
	 */
	i = pipe->rq_size ;
	if ( pipe->rq[i] != NULL )
	    return pipe->rq[i] ;
    }
    q = malloc(sizeof(*q), M_IPFW, M_DONTWAIT) ;
    if (q == NULL) {
	printf("sorry, cannot allocate queue for new flow\n");
	return NULL ;
    }
    bzero(q, sizeof(*q) );	/* needed */
    q->p = pipe ;
    q->hash_slot = i ;
    q->next = pipe->rq[i] ;
    pipe->rq[i] = q ;
    pipe->rq_elements++ ;
    return q ;
}

/*
 * Given a pipe and a pkt in last_pkt, find a matching queue
 * after appropriate masking. The queue is moved to front
 * so that further searches take less time.
 */
static struct dn_flow_queue *
find_queue(struct dn_pipe *pipe)
{
    int i = 0 ; /* we need i and q for new allocations */
    struct dn_flow_queue *q, *prev;

    if ( !(pipe->flags & DN_HAVE_FLOW_MASK) )
	q = pipe->rq[0] ;
    else {
	/* first, do the masking */
	last_pkt.dst_ip &= pipe->flow_mask.dst_ip ;
	last_pkt.src_ip &= pipe->flow_mask.src_ip ;
	last_pkt.dst_port &= pipe->flow_mask.dst_port ;
	last_pkt.src_port &= pipe->flow_mask.src_port ;
	last_pkt.proto &= pipe->flow_mask.proto ;
	last_pkt.flags = 0 ; /* we dont care about this one */
	/* then, hash function */
	i = ( (last_pkt.dst_ip) & 0xffff ) ^
	    ( (last_pkt.dst_ip >> 15) & 0xffff ) ^
	    ( (last_pkt.src_ip << 1) & 0xffff ) ^
	    ( (last_pkt.src_ip >> 16 ) & 0xffff ) ^
	    (last_pkt.dst_port << 1) ^ (last_pkt.src_port) ^
	    (last_pkt.proto );
	i = i % pipe->rq_size ;
	/* finally, scan the current list for a match */
	searches++ ;
	for (prev=NULL, q = pipe->rq[i] ; q ; ) {
	    search_steps++;
	    if (bcmp(&last_pkt, &(q->id), sizeof(q->id) ) == 0)
		break ; /* found */
	    else if (pipe_expire && q->r.head == NULL) {
		/* entry is idle, expire it */
		struct dn_flow_queue *old_q = q ;

		if (prev != NULL)
		    prev->next = q = q->next ;
		else
		    pipe->rq[i] = q = q->next ;
		pipe->rq_elements-- ;
		free(old_q, M_IPFW);
		continue ;
	    }
	    prev = q ;
	    q = q->next ;
	}
	if (q && prev != NULL) { /* found and not in front */
	    prev->next = q->next ;
	    q->next = pipe->rq[i] ;
	    pipe->rq[i] = q ;
	}
    }
    if (q == NULL) { /* no match, need to allocate a new entry */
	q = create_queue(pipe, i);
	if (q != NULL)
	    q->id = last_pkt ;
    }
    return q ;
}

/*
 * determine whether to drop packet based on loss rate parameters
 */
static int
rate_based_drop(struct dn_pipe *p)
{
    if (p->lossdist & (DN_DIST_TABLE_DETERM|DN_DIST_CONST_TIME))
	return 0; /* time-based, so don't drop yet */

    if (p->lossquantum_expire <= curr_time) {
	do {
	    p->lossquantum_expire += p->lossquantum;
	} while (p->lossquantum_expire <= curr_time);

	switch(p->lossdist) {
            case DN_DIST_POISSON:   /* curr. implemented as random table */
            case DN_DIST_TABLE_RANDOM: 
                p->plr = p->losstable[random() % p->lossentries];
	        break;
	    case DN_DIST_UNIFORM:
		/* we need a number somewhere between
		 * (mean - 2*variance) aka minimum and
		 * (mean + 2*variance) aka maximum
		 */
		p->plr = random() % ( 4 * p->lossvar)
			+ (p->lossmean - 2 * p->lossvar);
		break;
	    default: /* no action */
	}
    }
    return (random() < p->plr); /* remember, 0 <= plr <= 7fffffff */
}


/*
 * dummynet hook for packets.
 */
int
dummynet_io(int pipe_nr, int dir,
	struct mbuf *m, struct ifnet *ifp, struct route *ro,
	struct sockaddr_in *dst,
	struct ip_fw_chain *rule)
{
    struct dn_pkt *pkt;
    struct dn_pipe *p;
    int len = m->m_pkthdr.len ;
    struct dn_flow_queue *q = NULL ;
    int s ;

    s = splimp();
    /* XXX check the spl protection. It might be unnecessary since we
     * run this at splnet() already.
     */

    DEB(printf("-- last_pkt dst 0x%08x/0x%04x src 0x%08x/0x%04x\n",
	last_pkt.dst_ip, last_pkt.dst_port,
	last_pkt.src_ip, last_pkt.src_port);)

    pipe_nr &= 0xffff ;
    /*
     * locate pipe. First time is expensive, next have direct access.
     */
    if ( (p = rule->rule->pipe_ptr) == NULL ) {
	for (p = all_pipes; p && p->pipe_nr != pipe_nr; p = p->next)
	    ;
	if (p == NULL)
	    goto dropit ;	/* this pipe does not exist! */
	rule->rule->pipe_ptr = p ; /* record pipe ptr for the future	*/
    }
    q = find_queue(p);
    /*
     * update statistics, then do various check on reasons to drop pkt
     */
    if ( q == NULL )
	goto dropit ;		/* cannot allocate queue		*/
    q->tot_bytes += len ;
    q->tot_pkts++ ;
    if (rate_based_drop(p))
	goto dropit ;		/* random pkt drop			*/
    if ( p->queue_size && q->len >= p->queue_size)
	goto dropit ;		/* queue count overflow			*/
    if ( p->queue_size_bytes && len + q->len_bytes > p->queue_size_bytes)
	goto dropit ;		/* queue size overflow			*/
    /*
     * can implement RED drops here if needed.
     */

    pkt = (struct dn_pkt *)malloc(sizeof (*pkt), M_IPFW, M_NOWAIT) ;
    if ( pkt == NULL )
	goto dropit ;		/* cannot allocate packet header	*/
    /* ok, i can handle the pkt now... */
    bzero(pkt, sizeof(*pkt) ); /* XXX expensive, see if we can remove it*/
    /* build and enqueue packet + parameters */
    pkt->hdr.mh_type = MT_DUMMYNET ;
    (struct ip_fw_chain *)pkt->hdr.mh_data = rule ;
    DN_NEXT(pkt) = NULL;
    pkt->dn_m = m;
    pkt->dn_dir = dir ;

    pkt->ifp = ifp;
    if (dir == DN_TO_IP_OUT) {
	/*
	 * We need to copy *ro because for ICMP pkts (and maybe others)
	 * the caller passed a pointer into the stack; dst might also be
	 * a pointer into *ro so it needs to be updated.
	 */
	pkt->ro = *ro;
	if (ro->ro_rt)
	    ro->ro_rt->rt_refcnt++ ; /* XXX */
	if (dst == (struct sockaddr_in *)&ro->ro_dst) /* dst points into ro */
	    dst = (struct sockaddr_in *)&(pkt->ro.ro_dst) ;

	pkt->dn_dst = dst;
    }
    if (q->r.head == NULL)
	q->r.head = pkt;
    else
	DN_NEXT(q->r.tail) = pkt;
    q->r.tail = pkt;
    q->len++;
    q->len_bytes += len ;

    /*
     * If queue was empty (this is first pkt) then call ready_event()
     * now to make the pkt go out at the right time. Otherwise we are done,
     * as there must be a ready event already scheduled.
     */
    if (q->r.head == pkt) /* r_queue was empty */
	ready_event( q );
    splx(s);
    return 0;

dropit:
    splx(s);
    if (q)
	q->drops++ ;
    m_freem(m);
    return 0 ; /* XXX should I return an error ? */
}

/*
 * Below, the rt_unref is only needed when (pkt->dn_dir == DN_TO_IP_OUT)
 * Doing this would probably save us the initial bzero of dn_pkt
 */
#define DN_FREE_PKT(pkt)	{		\
	struct dn_pkt *n = pkt ;		\
	rt_unref ( n->ro.ro_rt ) ;		\
	m_freem(n->dn_m);			\
	pkt = DN_NEXT(n) ;			\
	free(n, M_IPFW) ;	}
/*
 * dispose all packets queued on a pipe
 */
static void
purge_pipe(struct dn_pipe *pipe)
{
    struct dn_pkt *pkt ;
    struct dn_flow_queue *q, *qn ;
    int i ;

    for (i = 0 ; i <= pipe->rq_size ; i++ ) /* XXX last one is overflow */
	for (q = pipe->rq[i] ; q ; q = qn ) {
	    for (pkt = q->r.head ; pkt ; )
		DN_FREE_PKT(pkt) ;
	    qn = q->next ;
	    free(q, M_IPFW);
	}
    for (pkt = pipe->p.head ; pkt ; )
	DN_FREE_PKT(pkt) ;
}

/*
 * Delete all pipes and heaps returning memory. Must also
 * remove references from all ipfw rules to all pipes.
 */
static void
dummynet_flush()
{
    struct dn_pipe *curr_p, *p ;
    struct ip_fw_chain *chain ;
    int s ;

    s = splnet() ;

    /* remove all references to pipes ...*/
    for (chain= ip_fw_chain.lh_first ; chain; chain = chain->chain.le_next)
	chain->rule->pipe_ptr = NULL ;
    /* prevent future matches... */
    p = all_pipes ;
    all_pipes = NULL ; 
    /* and free heaps so we don't have unwanted events */
    if (ready_heap.size >0 )
	free(ready_heap.p, M_IPFW);
    ready_heap.elements = ready_heap.size = 0 ;
    if (extract_heap.size >0 )
	free(extract_heap.p, M_IPFW);
    extract_heap.elements = extract_heap.size = 0 ;
    splx(s) ;
    /*
     * Now purge all queued pkts and delete all pipes
     */
    for ( ; p ; ) {
	purge_pipe(p);
	curr_p = p ;
	p = p->next ;	
	free(curr_p->rq, M_IPFW);
	free(curr_p, M_IPFW);
    }
}


/*
 * read in table supplied by user
 */
static int
copyin_table(int entries, int *usertable, int **kerntable)
{
    if (entries <= 0) {
	printf("dummynet: %d entries in table", entries);
	return EINVAL;
    }
    *kerntable = malloc(entries * sizeof(int), M_IPFW, M_DONTWAIT) ;
    if (*kerntable == NULL) {
	printf("dummynet: no memory for table\n");
	return ENOSPC ;
    }
    return copyin(usertable,*kerntable, entries * sizeof(int));
}


/*
 * Configure a pipe
 */
static int
dummynet_conf(struct dn_pipe *p)
{
	struct dn_pipe *a, *b;
	int error = 0;
	/*
	 * The config program passes parameters as follows:
	 * bw = bits/second (0 means no limits),
	 * delaydist = integer constant.
	 * delay = ms, must be translated into ticks.
	 * queue_size = slots (0 means no limit)
	 * queue_size_bytes = bytes (0 means no limit)
	 *	  only one can be set, must be bound-checked
	 */
	if (p->delaydist & ~(DN_DIST_CONST_TIME|DN_DIST_UNIFORM|DN_DIST_POISSON
				|DN_DIST_TABLE_RANDOM|DN_DIST_TABLE_DETERM)) {
	    printf("dummynet: invalid delay distribution %x\n", p->delaydist);
	    return EINVAL;
	}

	if (p->lossdist & ~(DN_DIST_CONST_RATE|DN_DIST_CONST_TIME|
			    DN_DIST_TABLE_DETERM|DN_DIST_UNIFORM|
			    DN_DIST_POISSON)) {
	    printf("dummynet: invalid loss distribution %x\n", p->lossdist);
	    return EINVAL;
	}

	if (p->bwdist & ~(DN_DIST_CONST_RATE|DN_DIST_UNIFORM|
			  DN_DIST_TABLE_DETERM|DN_DIST_TABLE_RANDOM|
			  DN_DIST_POISSON)) {
	    printf("dummynet: invalid bw distribution: %x\n",p->bwdist);
	    return EINVAL;
	}

	if (p->delaydist & DN_DIST_CONST_TIME)
	    p->delay = ( p->delay * hz ) / 1000 ;
	if (p->delaydist & DN_DIST_UNIFORM) {
	    if (p->delayvar == p->delaymean) {
		p->delaydist=DN_DIST_CONST_TIME;
		p->delay = ( p->delaymean * hz ) / 1000 ;
	    }
	    else
	    if (p->delayvar > p->delaymean) {
	     	printf("dummynet: min %d mean %d ???\n",
		       p->delayvar, p->delaymean);
		return EINVAL;
	    }
	}
	if (p->delaydist & DN_TABLE_DIST) {
	    p->delaytablepos = 0;
	    error = copyin_table(p->delayentries,p->delaytable,&(p->delaytable));
	    if (error) {
	     	printf("dummynet: delay table could not be copied from userland\n");
		return error;
	    }
	}
	else /* not custom, so no table */
	    p->delaytable=NULL;

	if (p->lossdist & DN_TABLE_DIST) {
	    p->losstablepos = 0;
	    error = copyin_table(p->lossentries,p->losstable,&(p->losstable));
	    if (error) { 
		printf("dummynet: loss table could not be copied from userland\n");
		return error;
	    }
	}
	else /* not custom, so no table */
	    p->losstable=NULL;

	if (p->bwdist & DN_TABLE_DIST) {
	    p->bwtablepos = 0;
	    error = copyin_table(p->bwentries,p->bwtable,&(p->bwtable));
	    if (error) { 
		printf("dummynet: bw table could not be copied from userland\n");
		return error;
	    }
	}
	else /* not custom, so no table */
	    p->bwtable=NULL;

	/* convert quanta from ms to ticks */
	p->lossquantum = p->lossquantum * hz / 1000 ;
	p->bwquantum = p->bwquantum * hz /1000;

	/* init drop or quantum expiration timers.
	 * pretend that 7fffffff==heat_death_of_universe. i would
	 * be surprised if anybody ran experiments long enough to roll it over.
	 */
	if (p->lossdist & (DN_DIST_TABLE_DETERM|DN_DIST_CONST_TIME))
	    p->nextdroptime = curr_time;
	else
	    p->nextdroptime = 0x7fffffff; 

	if (p->lossdist & ~DN_CONST_DIST)
	    p->lossquantum_expire = curr_time;
	else
	    p->lossquantum_expire = 0x7fffffff;

	if (p->bwdist & ~DN_CONST_DIST)
	    p->bwquantum_expire = curr_time;
	else
	    p->bwquantum_expire = 0x7fffffff;

	if (p->queue_size == 0 && p->queue_size_bytes == 0)
	    p->queue_size = 50 ;
	if (p->queue_size != 0 )	/* buffers are prevailing */
	    p->queue_size_bytes = 0 ;
	if (p->queue_size > 100)
	    p->queue_size = 50 ;
	if (p->queue_size_bytes > 1024*1024)
	    p->queue_size_bytes = 1024*1024 ;
	for (a = NULL , b = all_pipes ; b && b->pipe_nr < p->pipe_nr ;
		 a = b , b = b->next) ;
	if (b && b->pipe_nr == p->pipe_nr) {
	    b->flags = p->flags ;

	    b->bandwidth = p->bandwidth ;
	    b->bwdist = p->bwdist;
	    b->bwmean = p->bwmean;
	    b->bwvar = p->bwvar;
	    b->bwquantum = b->bwquantum;
	    b->bwquantum_expire = b->bwquantum_expire;
	    if (b->bwtable)
		free(b->bwtable,M_IPFW);
	    b->bwtable = p->bwtable;
	    b->bwentries = p->bwentries;

	    b->queue_size = p->queue_size ;
	    b->queue_size_bytes = p->queue_size_bytes ;

	    b->delay = p->delay ;
	    b->delaydist = p->delaydist;
	    b->delaymean = p->delaymean;
	    b->delayvar = p->delayvar;
	    if(b->delaytable)
		free(b->delaytable,M_IPFW);
	    b->delaytable = p->delaytable;
	    b->delayentries = p->delayentries;

	    b->plr = p->plr ;
	    b->lossdist = p->lossdist;
	    b->nextdroptime = p->nextdroptime;
	    b->lossmean = p->lossmean;
	    b->lossvar = p->lossvar;
	    b->lossquantum = p->lossquantum;
	    b->lossquantum_expire = p->lossquantum_expire;
	    if (b->losstable)
		free(b->losstable,M_IPFW);
	    b->losstable = p->losstable;
	    b->lossentries = p->lossentries;

	    b->flow_mask = p->flow_mask ;
	} else { /* brand new pipe */
	    int s ;
	    struct dn_pipe *x;
	    x = malloc(sizeof(struct dn_pipe), M_IPFW, M_DONTWAIT) ;
	    if (x == NULL) {
		printf("ip_dummynet.c: no memory for new pipe\n");
		return ENOSPC ;
	    }
	    bcopy(p,x,sizeof(*x));
	    bzero(&(x->p), sizeof(x->p));
	    bzero(&(x->flow_mask), sizeof(x->flow_mask));
	    x->last_expired = 0;
	    if (x->flags & DN_HAVE_FLOW_MASK) {/* allocate some slots */
		int l = p->rq_size ;
		if (l == 0)
		    l = dn_hash_size ;
		if (l < 4)
		    l = 4 ;
		else if (l > 1024)
		    l = 1024 ;
		x->rq_size = l ;
	    } else /* one is enough for null mask */
		x->rq_size = 1 ;
	    x->rq = malloc((1 + x->rq_size) * sizeof(struct dn_flow_queue *),
		    M_IPFW, M_DONTWAIT) ;
	    if (x->rq == NULL ) {
		printf("sorry, cannot allocate queue\n");
		free(x, M_IPFW);
		return ENOSPC ;
	    }
	    bzero(x->rq, (1+x->rq_size) * sizeof(struct dn_flow_queue *) );
	    x->rq_elements = 0 ;

	    s = splnet() ;
	    x->next = b ;
	    if (a == NULL)
		all_pipes = x ;
	    else
		a->next = x ;
	    splx(s);
	}
    return error;
}

extern struct ip_fw_chain *ip_fw_default_rule ;
/*
 * when a firewall rule is deleted, scan all queues and remove the flow-id
 * from packets matching this rule.
 */
void
dn_rule_delete(void *r)
{
    struct dn_pipe *p ;
    struct dn_flow_queue *q ;
    struct dn_pkt *pkt ;
    int i ;

    for ( p = all_pipes ; p ; p = p->next ) {
	for (i = 0 ; i <= p->rq_size ; i++) /* XXX last one is ovflow */
	    for (q = p->rq[i] ; q ; q = q->next )
		for (pkt = q->r.head ; pkt ; pkt = DN_NEXT(pkt) )
		    if (pkt->hdr.mh_data == r)
			pkt->hdr.mh_data = (void *)ip_fw_default_rule ;
	for (pkt = p->p.head ; pkt ; pkt = DN_NEXT(pkt) )
	    if (pkt->hdr.mh_data == r)
		pkt->hdr.mh_data = (void *)ip_fw_default_rule ;
    }
}


/*
 * Handler for the various dummynet socket options (get, flush, config, del)
 */
static int
ip_dn_ctl(struct sockopt *sopt)
{
    int error = 0 ;
    struct dn_pipe *p, tmp_pipe ;
    struct dn_pipe *a, *b ;

    /* Disallow sets in really-really secure mode. */
    if (sopt->sopt_dir == SOPT_SET && securelevel >= 3)
	return (EPERM);

    switch (sopt->sopt_name) {
    default :
	panic("ip_dn_ctl -- unknown option");

    case IP_DUMMYNET_GET :
	{
	    char *buf, *bp ; /* bp is the "copy-pointer" */
	    size_t size ;
	    int s ;

	    s = splnet() ; /* to avoid thing change while we work! */
	    for (p = all_pipes, size = 0 ; p ; p = p->next )
		size += sizeof( *p ) +
		    p->rq_elements * sizeof(struct dn_flow_queue);
	    buf = malloc(size, M_TEMP, M_DONTWAIT);
	    if (buf == 0) {
		error = ENOBUFS ;
		splx(s);
		break ;
	    }
	    for (p = all_pipes, bp = buf ; p ; p = p->next ) {
		int i ;
		struct dn_pipe *pipe_bp = (struct dn_pipe *)bp ;
		struct dn_flow_queue *q;
		int copied = 0 ;

		/*
		 * copy pipe descriptor into *bp, convert delay back to ms,
		 * then copy the queue descriptor(s) one at a time.
		 */
		bcopy(p, bp, sizeof( *p ) );
		pipe_bp->delay = (pipe_bp->delay * 1000) / hz ;
		bp += sizeof( *p ) ;
		for (i = 0 ; i <= p->rq_size ; i++)
		    for (q = p->rq[i] ; q ; q = q->next, bp += sizeof(*q) ) {
			if (q->hash_slot != i)
			    printf("++ at %d: wrong slot (have %d, should be %d)\n", copied, q->hash_slot, i);
			copied++ ;
			bcopy(q, bp, sizeof( *q ) );
		    }
		if (copied != p->rq_elements)
		    printf("++ wrong count, have %d should be %d\n",
			copied, p->rq_elements);
	    }
	    splx(s);
	    error = sooptcopyout(sopt, buf, size);
	    FREE(buf, M_TEMP);
	}
	break ;

    case IP_DUMMYNET_FLUSH :
	dummynet_flush() ;
	break ;

    case IP_DUMMYNET_CONFIGURE :
	error = sooptcopyin(sopt, &tmp_pipe, sizeof tmp_pipe, sizeof tmp_pipe);
	if (!error)
	    error = dummynet_conf(&tmp_pipe);
	break ;

    case IP_DUMMYNET_DEL :
	p = &tmp_pipe ;
	error = sooptcopyin(sopt, p, sizeof *p, sizeof *p);
	if (error)
	    break ;

	for (a = NULL , b = all_pipes ; b && b->pipe_nr < p->pipe_nr ;
		 a = b , b = b->next) ;
	if (b && b->pipe_nr == p->pipe_nr) {	/* found pipe */
	    int s ;
	    struct ip_fw_chain *chain ;

	    s = splnet() ;
	    chain = ip_fw_chain.lh_first;

	    if (a == NULL)
		all_pipes = b->next ;
	    else
		a->next = b->next ;
	    /*
	     * remove references to this pipe from the ip_fw rules.
	     */
	    for (; chain; chain = chain->chain.le_next)
		if (chain->rule->pipe_ptr == b)
		    chain->rule->pipe_ptr = NULL ;
	    /* remove all references to b from heaps */
	    if (ready_heap.elements > 0) {
		struct dn_heap *h = &ready_heap ;
		int i = 0, found = 0 ;
		while ( i < h->elements ) {
		    if (((struct dn_flow_queue *)(h->p[i].object))->p == b) {
			/* found one */
			h->elements-- ;
			h->p[i] = h->p[h->elements] ;
			found++ ;
		    } else
			i++ ;
		}
		if (found)
		    heapify(h);
	    }
	    if (extract_heap.elements > 0) {
		struct dn_heap *h = &extract_heap ;
		int i = 0, found = 0 ;
		while ( i < h->elements ) {
		    if (h->p[i].object == b) { /* found one */
			h->elements-- ;
			h->p[i] = h->p[h->elements] ;
			found++ ;
		    } else
			i++ ;
		}
		if (found)
		    heapify(h);
	    }
	    splx(s);
	    purge_pipe(b);	/* remove pkts from here */

	    if (b->delaydist & 
		(DN_DIST_TABLE_RANDOM|DN_DIST_TABLE_DETERM|DN_DIST_POISSON))
		free(b->delaytable, M_IPFW);
	    if (b->lossdist & (DN_DIST_TABLE_DETERM|DN_DIST_TABLE_RANDOM))
		free(b->losstable, M_IPFW);
	    if (b->bwdist & (DN_DIST_TABLE_DETERM|DN_DIST_TABLE_RANDOM))
		free(b->bwtable, M_IPFW);
	    free(b->rq, M_IPFW);
	    free(b, M_IPFW);
	}
	break ;
    }
    return error ;
}

void
ip_dn_init(void)
{
    printf("DUMMYNET initialized (000212)\n");
    all_pipes = NULL ;
    ready_heap.size = ready_heap.elements = 0 ;
    extract_heap.size = extract_heap.elements = 0 ;
    ip_dn_ctl_ptr = ip_dn_ctl;
    timeout(dummynet, NULL, 1);
}

#ifdef DUMMYNET_MODULE

#include <sys/exec.h>
#include <sys/sysent.h>
#include <sys/lkm.h>

MOD_MISC(dummynet);

static ip_dn_ctl_t *old_dn_ctl_ptr ;

static int
dummynet_load(struct lkm_table *lkmtp, int cmd)
{
	int s=splnet();
	old_dn_ctl_ptr = ip_dn_ctl_ptr;
	ip_dn_init();
	splx(s);
	return 0;
}

static int
dummynet_unload(struct lkm_table *lkmtp, int cmd)
{
	int s=splnet();
	ip_dn_ctl_ptr =  old_dn_ctl_ptr;
	splx(s);
	dummynet_flush();
	printf("DUMMYNET unloaded\n");
	return 0;
}

int
dummynet_mod(struct lkm_table *lkmtp, int cmd, int ver)
{
    DISPATCH(lkmtp, cmd, ver, dummynet_load, dummynet_unload, lkm_nullcmd);
}
#endif
