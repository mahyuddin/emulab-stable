/*
 * DB interface.
 */

#include <sys/types.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <syslog.h>
#include <assert.h>
#include "tbdb.h"
#include "log.h"
#include "config.h"

/*
 * DB stuff
 */
static MYSQL	db;
static char    *dbname = TBDBNAME;

int
dbinit(void)
{
	mysql_init(&db);
	if (mysql_real_connect(&db, 0, 0, 0,
			       dbname, 0, 0, CLIENT_INTERACTIVE) == 0) {
		error("%s: connect failed: %s", dbname, mysql_error(&db));
		return 0;
	}
	return 1;
}

MYSQL_RES *
mydb_query(char *query, int ncols, ...)
{
	MYSQL_RES	*res;
	char		querybuf[2*BUFSIZ];
	va_list		ap;
	int		n;

	va_start(ap, ncols);
	n = vsnprintf(querybuf, sizeof(querybuf), query, ap);
	if (n > sizeof(querybuf)) {
		error("query too long for buffer");
		return (MYSQL_RES *) 0;
	}

	if (mysql_real_query(&db, querybuf, n) != 0) {
		error("%s: query failed: %s", dbname, mysql_error(&db));
		return (MYSQL_RES *) 0;
	}

	res = mysql_store_result(&db);
	if (res == 0) {
		error("%s: store_result failed: %s", dbname, mysql_error(&db));
		return (MYSQL_RES *) 0;
	}

	if (ncols && ncols != (int)mysql_num_fields(res)) {
		error("%s: Wrong number of fields returned "
		      "Wanted %d, Got %d",
		      dbname, ncols, (int)mysql_num_fields(res));
		mysql_free_result(res);
		return (MYSQL_RES *) 0;
	}
	return res;
}

int
mydb_update(char *query, ...)
{
	char		querybuf[2*BUFSIZ];
	va_list		ap;
	int		n;

	va_start(ap, query);
	n = vsnprintf(querybuf, sizeof(querybuf), query, ap);
	if (n > sizeof(querybuf)) {
		error("query too long for buffer");
		return 0;
	}
	if (mysql_real_query(&db, querybuf, n) != 0) {
		error("%s: query failed: %s", dbname, mysql_error(&db));
		return 0;
	}
	return 1;
}

/*
 * Map IP to node ID. 
 */
int
mydb_iptonodeid(char *ipaddr, char *bufp)
{
	MYSQL_RES	*res;
	MYSQL_ROW	row;

	res = mydb_query("select node_id from interfaces where IP='%s'",
			 1, ipaddr);
	if (!res) {
		error("iptonodeid: DB Error: %s", ipaddr);
		return 0;
	}

	if (! (int)mysql_num_rows(res)) {
		error("iptonodeid: No such nodeid: %s", ipaddr);
		mysql_free_result(res);
		return 0;
	}
	row = mysql_fetch_row(res);
	mysql_free_result(res);
	strcpy(bufp, row[0]);

	return 1;
}
 
/*
 * Set the node event status.
 */
int
mydb_setnodeeventstate(char *nodeid, char *eventtype)
{
	if (! mydb_update("update nodes set eventstatus='%s' "
			  "where node_id='%s'",
			  eventtype, nodeid)) {
		error("setnodestatus: DB Error: %s/%s!", nodeid, eventtype);
		return 0;
	}
	return 1;
}

/*
 * See if all nodes in an experiment are at the specified event state.
 * Return number of nodes not in the proper state.
 */
int
mydb_checkexptnodeeventstate(char *pid, char *eid,
			     char *eventtype, int *count)
{
	MYSQL_RES	*res;
	MYSQL_ROW	row;
	int		nrows;

	res = mydb_query("select eventstatus from nodes "
			 "left join reserved on "
			 " nodes.node_id=reserved.node_id "
			 "where reserved.pid='%s' and reserved.eid='%s' ",
			 1, pid, eid);
	
	if (!res) {
		error("checkexptnodeeventstate: DB Error: %s/%s/%s",
		      pid, eid, eventtype);
		return 0;
	}

	if (! (nrows = mysql_num_rows(res))) {
		error("checkexptnodeeventstate: No such experiment: %s/%s",
		      pid, eid);
		mysql_free_result(res);
		return 0;
	}

	*count = 0;
	while (nrows) {
		row = mysql_fetch_row(res);

		if (!row[0] || !row[0][0] || strcmp(row[0], eventtype))
			*count += 1;
		nrows--;
	}
	mysql_free_result(res);
	return 1;
}

/*
 * Set (or clear) event scheduler process ID. A zero is treated as
 * a request to clear it.
 */
int
mydb_seteventschedulerpid(char *pid, char *eid, int processid)
{
	if (! mydb_update("update experiments set event_sched_pid=%d "
			  "where pid='%s' and eid='%s'",
			  processid, pid, eid)) {
		error("seteventschedulerpid: DB Error: %s/%s!", pid, eid);
		return 0;
	}
	return 1;
}
