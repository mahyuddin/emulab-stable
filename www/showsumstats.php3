<?php
#
# EMULAB-COPYRIGHT
# Copyright (c) 2000-2003 University of Utah and the Flux Group.
# All rights reserved.
#
include("defs.php3");
include("showstuff.php3");

#
# Standard Testbed Header
#
PAGEHEADER("Testbed Summary Stats");

#
# Only known and logged in users can end experiments.
#
$uid = GETLOGIN();
LOGGEDINORDIE($uid);
$isadmin = ISADMIN($uid);

# Summary data for admins only.
if (!$isadmin) {
    USERERROR("You are not allowed to view this page!", 1);
}

# Page args,
if (! isset($showby)) {
    $showby = "users";
}
if (! isset($sortby)) {
    $sortby = "pdays";
}
if (! isset($range)) {
    $range = "epoch";
}

echo "<b>Show: <a class='static' href='showexpstats.php3'>
                  Experiment Stats</a>,
               <a class='static' href='showstats.php3'>
                  Testbed Stats</a>.
      </b><br>\n";

echo "<b>Show by: ";
# By Users.
if ($showby != "users") {
    echo "<a class='static' href='showsumstats.php3?showby=users'>
             Users</a>, ";
}
else {
    echo "Users, ";
}
# By Projects
if ($showby != "projects") {
    echo "<a class='static' href='showsumstats.php3?showby=projects'>
             Projects</a>, ";
}
else {
    echo "Projects. ";
}
echo "</b><br>\n";

echo "<b>Range: ";
if ($range != "epoch") {
    echo "<a class='static'
            href='showsumstats.php3?showby=$showby&sortby=$sortby&range=epoch'>
            Epoch</a>, ";
}
else {
    echo "Epoch, ";
}
if ($range != "day") {
    echo "<a class='static'
            href='showsumstats.php3?showby=$showby&sortby=$sortby&range=day'>
            Day</a>, ";
}
else {
    echo "Day, ";
}
if ($range != "week") {
    echo "<a class='static'
            href='showsumstats.php3?showby=$showby&sortby=$sortby&range=week'>
            Week</a>, ";
}
else {
    echo "Week, ";
}
if ($range != "month") {
    echo "<a class='static'
            href='showsumstats.php3?showby=$showby&sortby=$sortby&range=month'>
            Month</a>, ";
}
else {
    echo "Month. ";
}
echo "</b><br><br>\n";


#
# This version prints out the simple summary info for the entire table.
# No ranges, just ordered. 
#
function showsummary ($showby, $sortby) {
    switch ($showby) {
        case "projects":
	    $which = "pid";
	    $table = "project_stats";
	    $title = "Project Summary Stats (Epoch)";
	    $link  = "showproject.php3?pid=";
	    break;
        case "users":
	    $which = "uid";
	    $table = "user_stats";
	    $title = "User Summary Stats (Epoch)";
	    $link  = "showuser.php3?target_uid=";
	    break;
        default:
	    USERERROR("Invalid showby argument: $showby!", 1);
    }
    $wclause = "";
    switch ($sortby) {
        case "pid":
	    $order   = "pid";
	    $wclause = "where pid!='$TBOPSPID'";
	    break;
        case "uid":
	    $order = "uid";
	    break;
        case "pnodes":
	    $order = "allexpt_pnodes desc";
	    break;
        case "pdays":
	    $order = "pnode_days desc";
	    break;
        case "edays":
	    $order = "expt_days desc";
	    break;
        default:
	    USERERROR("Invalid sortby argument: $sortby!", 1);
    }

    $query_result =
	DBQueryFatal("select $which, allexpt_pnodes, ".
		     "allexpt_pnode_duration / (24 * 3600) as pnode_days, ".
		     "allexpt_duration / (24 * 3600) as expt_days ".
		     "from $table where allexpt_pnodes!=0 ".
		     "$wclause ".
		     "order by $order");

    if (mysql_num_rows($query_result) == 0) {
	USERERROR("No summary stats of interest!", 1);
    }

    #
    # Gather some totals first.
    #
    $pnode_total  = 0;
    $pdays_total  = 0;
    $edays_total  = 0;
    while ($row = mysql_fetch_assoc($query_result)) {
	$pnodes  = $row["allexpt_pnodes"];
	$pdays   = $row["pnode_days"];
	$edays   = $row["expt_days"];
	
	$pnode_total  += $pnodes;
	$pdays_total  += $pdays;
	$edays_total  += $edays;
    }

    SUBPAGESTART();
    echo "<table>
           <tr><td colspan=2 nowrap align=center>
               <b>Totals</b></td>
           </tr>
           <tr><td nowrap align=right><b>Pnodes</b></td>
               <td align=left>$pnode_total</td>
           </tr>
           <tr><td nowrap align=right><b>Pnode Days</b></td>
               <td align=left>$pdays_total</td>
           </tr>
           <tr><td nowrap align=right><b>Expt Days</b></td>
               <td align=left>$edays_total</td>
           </tr>
          </table>\n";
    SUBMENUEND_2B();
    
    echo "<center><b>$title</b></center><br>\n";
    echo "<table align=center border=1>
          <tr>
             <th><a class='static'
                    href='showsumstats.php3?showby=$showby&sortby=$which'>
                    $which</th>
             <th><a class='static'
                    href='showsumstats.php3?showby=$showby&sortby=pnodes'>
                    Pnodes</th>
             <th><a class='static'
                    href='showsumstats.php3?showby=$showby&sortby=pdays'>
                    Pnode Days</th>
             <th><a class='static'
                    href='showsumstats.php3?showby=$showby&sortby=edays'>
                    Expt Days</th>
          </tr>\n";

    mysql_data_seek($query_result, 0);    
    while ($row = mysql_fetch_assoc($query_result)) {
	$heading = $row[$which];
	$pnodes  = $row["allexpt_pnodes"];
	$phours  = $row["pnode_days"];
	$ehours  = $row["expt_days"];

	echo "<tr>
                <td><A href='$link${heading}'>$heading</A></td>
                <td>$pnodes</td>
                <td>$phours</td>
                <td>$ehours</td>
              </tr>\n";
    }
    echo "</table>\n";
    SUBPAGEEND();
}

#
# COmparison functions for sort.
#
function intcmp ($a, $b) {
    if ($a == $b) return 0;
    return ($a > $b) ? -1 : 1;
}
function pnodecmp ($a, $b) {
    return intcmp($a["pnodes"], $b["pnodes"]);
}
function pdaycmp ($a, $b) {
    return intcmp($a["pseconds"], $b["pseconds"]);
}
function edaycmp ($a, $b) {
    return intcmp($a["eseconds"], $b["eseconds"]);
}

function showrange ($showby, $sortby, $range) {
    global $TBOPSPID, $TB_EXPTSTATE_ACTIVE;
    $debug = 0;
    
    switch ($range) {
        case "day":
	    $span = 3600 * 24 * 1;
	    break;
        case "week":
	    $span = 3600 * 24 * 7;
	    break;
        case "month":
	    $span = 3600 * 24 * 31;
	    break;
        default:
	    USERERROR("Invalid range argument: $range!", 1);
    }
    $wclause   = "($span)";
    $now       = time();
    $spanstart = $now - $span;

    # Summary info, indexed by pid and uid. Each entry is an array of the
    # summary info.
    $pid_summary = array();
    $uid_summary = array();

    #
    # First get current swapped in experiments. Instead of using reserved
    # table, use the experiment_stats record so we can more easily separate
    # pnodes from vnodes (although ignoring vnodes at the moment).
    #
    $query_result =
	DBQueryFatal("select e.pid,e.eid,e.expt_swap_uid as swapper, ".
		     "  UNIX_TIMESTAMP(now())-UNIX_TIMESTAMP(e.expt_swapped) ".
		     "   as swapseconds, r.pnodes,r.vnodes ".
		     " from experiments as e ".
		     "left join experiment_stats as s on s.exptidx=e.idx ".
		     "left join experiment_resources as r on s.rsrcidx=r.idx ".
		     "where e.state='" . $TB_EXPTSTATE_ACTIVE . "'" .
		     "  and e.pid!='$TBOPSPID' and ".
		     "      not (e.pid='ron' and e.eid='all') ");

    while ($row = mysql_fetch_assoc($query_result)) {
	$pid         = $row["pid"];
	$eid         = $row["eid"];
	$uid         = $row["swapper"];
	$swapseconds = $row["swapseconds"];
	$pnodes      = $row["pnodes"];
	$vnodes      = $row["vnodes"];

	if ($pnodes == 0)
	    continue;

	if ($debug)
	    echo "$pid $eid $uid $swapseconds $pnodes $vnodes<br>\n";

	if ($swapseconds > $span) {
	    $swapseconds = $span;
	    if ($debug)
		echo "Span to $swapseconds<br>\n";
	}

	if (!isset($pid_summary[$pid])) {
	    $pid_summary[$pid] = array('pnodes'   => 0,
				       'pseconds' => 0,
				       'eseconds' => 0,
				       'current'  => 1);
	}
	if (!isset($uid_summary[$uid])) {
	    $uid_summary[$uid] = array('pnodes'   => 0,
				       'pseconds' => 0,
				       'eseconds' => 0,
				       'current'  => 1);
	}
	$pid_summary[$pid]["pnodes"]   += $pnodes;
	$pid_summary[$pid]["pseconds"] += $pnodes * $swapseconds;
	$pid_summary[$pid]["eseconds"] += $swapseconds;
	$uid_summary[$uid]["pnodes"]   += $pnodes;
	$uid_summary[$uid]["pseconds"] += $pnodes * $swapseconds;
	$uid_summary[$uid]["eseconds"] += $swapseconds;
    }

    $query_result =
	DBQueryFatal("select s.pid,s.eid,t.uid,t.action,t.exptidx, ".
		     "  r1.pnodes as pnodes1,r2.pnodes as pnodes2, ".
		     "  UNIX_TIMESTAMP(t.end_time) as ttstamp ".
		     " from testbed_stats as t ".
		     "left join experiment_stats as s on ".
		     "  s.exptidx=t.exptidx ".
		     "left join experiment_resources as r1 on ".
		     "  r1.idx=t.rsrcidx ".
		     "left join experiment_resources as r2 on ".
		     "  r2.idx=r1.lastidx and r1.lastidx is not null ".
		     "where t.exitcode = 0 && ".
		     "    ((UNIX_TIMESTAMP(now())-UNIX_TIMESTAMP(t.end_time))".
		     "     < $wclause) ".
		     "order by t.end_time");

    # Experiment start time, indexed by pid:eid.
    $expt_start = array();

    while ($row = mysql_fetch_assoc($query_result)) {
	$pid     = $row["pid"];
	$eid     = $row["eid"];
	$uid     = $row["uid"];
	$idx	 = $row["exptidx"];
	$tstamp  = $row["ttstamp"];
	$action  = $row["action"];
	$pnodes  = $row["pnodes1"];
	$pnodes2 = $row["pnodes2"];

	if ($pnodes == 0)
	    continue;

	#
	# If a swapmod, and there is no record, one of two things. Either
	# it was swapped in before the interval, or the experiment was
	# was swapped out, and the user did a swapmod on it. We need to
	# know that, since swapmod of a swapped out experiment does not
	# count! 
	# 
	if ($action == "swapmod" &&
	    ! isset($expt_start["$pid:$eid"])) {
	    $swapper_result =
		DBQueryFatal("select action from testbed_stats ".
			     "where exptidx=$idx and ".
			     "      UNIX_TIMESTAMP(end_time)<$tstamp ".
			     "order by end_time desc");

	    while ($srow = mysql_fetch_assoc($swapper_result)) {
		$saction = $srow["action"];

		if ($saction != "swapmod")
		    break;
	    }
	    if (!$srow ||
		($saction == "swapout" || $saction == "preload"))
		continue;
	    
	    if ($debug)
		echo "M $pid $eid $idx $saction<br>\n";
	}

	if (!isset($pid_summary[$pid])) {
	    $pid_summary[$pid] = array('pnodes'   => 0,
				       'pseconds' => 0,
				       'eseconds' => 0,
				       'current'  => 0);
	}
	if (!isset($uid_summary[$uid])) {
	    $uid_summary[$uid] = array('pnodes'   => 0,
				       'pseconds' => 0,
				       'eseconds' => 0,
				       'current'  => 0);
	}

	if ($debug) 
	    echo "$idx $pid $eid $uid $tstamp $action $pnodes $pnodes2<br>\n";

	switch ($action) {
        case "start":
        case "swapin":
	    $expt_start["$pid:$eid"] = array('pnodes' => $pnodes,
					     'uid'    => $uid,
					     'pid'    => $pid,
					     'stamp'  => $tstamp);
	    break;
        case "swapout":
        case "swapmod":
	    if (isset($expt_start["$pid:$eid"])) {
		# Use the original data, especially pnodes since if this
		# was a swapmod, the nodes are for the new config, not
		# the old config. Besides, we want to credit the original
		# swapper (in), not the current swapper/modder. 
		$uid    = $expt_start["$pid:$eid"]["uid"];
		$pnodes = $expt_start["$pid:$eid"]["pnodes"];
		$diff = $tstamp - $expt_start["$pid:$eid"]["stamp"];
	    }
	    else {
		#
                # The start was before the time span being looked at, so
                # no start/swapin event was returned. Add a record for it.
	        #
		$diff = $tstamp - $spanstart;
		if ($action == "swapmod") {
                    # A pain. We need the number of pnodes for the original
		    # version of the experiment, not the new version.
		    $pnodes = $pnodes2;
		}
	    }
	    if ($debug) 
		echo "S $pid $eid $uid $action $diff $pnodes $pnodes2<br>\n";
	    
	    $pid_summary[$pid]["pnodes"]   += $pnodes;
	    $pid_summary[$pid]["pseconds"] += $pnodes * $diff;
	    $pid_summary[$pid]["eseconds"] += $diff;
	    $uid_summary[$uid]["pnodes"]   += $pnodes;
	    $uid_summary[$uid]["pseconds"] += $pnodes * $diff;
	    $uid_summary[$uid]["eseconds"] += $diff;
	    unset($expt_start["$pid:$eid"]);
	    
	    # Basically, start the clock ticking again with the new
	    # number of pnodes.
	    if ($action == "swapmod") {
		# Yuck, we redefined uid/pnodes above, but we want to start the
		# new record for the current swapper/#pnodes.
		$expt_start["$pid:$eid"] = array('pnodes' => $row['pnodes1'],
						 'uid'    => $row['uid'],
						 'pid'    => $pid,
						 'stamp'  => $tstamp);
	    }
	    break;
	case "preload":
	case "destroy":
	    break;
        default:
	    TBERROR("Invalid action: $action!", 1);
	}
    }

    #
    # Anything still in the expt_start array is obviously still running,
    # but we caught those in the first query above, so we ignore them.
    #
    
    switch ($showby) {
        case "projects":
	    $which = "pid";
	    $table = $pid_summary;
	    $title = "Project Summary Stats ($range)";
	    $link  = "showproject.php3?pid=";
	    break;
        case "users":
	    $which = "uid";
	    $table = $uid_summary;
	    $title = "User Summary Stats ($range)";
	    $link  = "showuser.php3?target_uid=";
	    break;
        default:
	    USERERROR("Invalid showby argument: $showby!", 1);
    }
    switch ($sortby) {
        case "pid":
        case "uid":
	    ksort($table);
	    break;
        case "pnodes":
	    uasort($table, "pnodecmp");
	    break;
        case "pdays":
	    uasort($table, "pdaycmp");
	    break;
        case "edays":
	    uasort($table, "edaycmp");
	    break;
        default:
	    USERERROR("Invalid sortby argument: $sortby!", 1);
    }

    #
    # Gather some totals first.
    #
    $pnode_total  = 0;
    $pdays_total  = 0;
    $edays_total  = 0;

    foreach ($table as $key => $value) {
	$pnodes  = $value["pnodes"];
	$pdays   = sprintf("%.2f", $value["pseconds"] / (3600 * 24));
	$edays   = sprintf("%.2f", $value["eseconds"] / (3600 * 24));

	if ($debug)
	    echo "$key $value[pseconds] $value[eseconds]<br>\n";
	
	$pnode_total  += $pnodes;
	$pdays_total  += $pdays;
	$edays_total  += $edays;
    }

    SUBPAGESTART();
    echo "<table>
           <tr><td colspan=2 nowrap align=center>
               <b>Totals</b></td>
           </tr>
           <tr><td nowrap align=right><b>Pnodes</b></td>
               <td align=left>$pnode_total</td>
           </tr>
           <tr><td nowrap align=right><b>Pnode Days</b></td>
               <td align=left>$pdays_total</td>
           </tr>
           <tr><td nowrap align=right><b>Expt Days</b></td>
               <td align=left>$edays_total</td>
           </tr>
          </table>\n";
    SUBMENUEND_2B();
    
    echo "<center>
               <b>$title</b><br>
               (includes current experiments (*))
          </center><br>\n";
    echo "<table align=center border=1>
          <tr>
             <th><a class='static'
                    href='showsumstats.php3?showby=$showby&sortby=$which&range=$range'>
                    $which</th>
             <th><a class='static'
                    href='showsumstats.php3?showby=$showby&sortby=pnodes&range=$range'>
                    Pnodes</th>
             <th><a class='static'
                    href='showsumstats.php3?showby=$showby&sortby=pdays&range=$range'>
                    Pnode Days</th>
             <th><a class='static'
                    href='showsumstats.php3?showby=$showby&sortby=edays&range=$range'>
                    Expt Days</th>
          </tr>\n";

    foreach ($table as $key => $value) {
	$heading = $key;
	$pnodes  = $value["pnodes"];
	$current = $value["current"];
	$pdays   = sprintf("%.2f", $value["pseconds"] / (3600 * 24));
	$edays   = sprintf("%.2f", $value["eseconds"] / (3600 * 24));

	# We caught a swapout, where the swapin was before the interval
	# being looked at.
	if (!$pnodes)
	    continue;

	if ($current)
	    $current = "*";
	else
	    $current = "";

	echo "<tr>
                <td><A href='$link${heading}'>$heading $current</A></td>
                <td>$pnodes</td>
                <td>$pdays</td>
                <td>$edays</td>
              </tr>\n";
    }
    echo "</table>\n";
    SUBPAGEEND();
}

if ($range == "epoch") {
    showsummary($showby, $sortby);
}
else {
    showrange($showby, $sortby, $range);
}

#
# Standard Testbed Footer
# 
PAGEFOOTER();
?>
