<?php
#
# EMULAB-COPYRIGHT
# Copyright (c) 2000-2003 University of Utah and the Flux Group.
# All rights reserved.
#
include("defs.php3");
include("showstuff.php3");

#
# Only known and logged in users can end experiments.
#
$uid = GETLOGIN();
LOGGEDINORDIE($uid);

#
# Must provide the EID!
# 
if (!isset($pid) ||
    strcmp($pid, "") == 0) {
    USERERROR("The project ID was not provided!", 1);
}

if (!isset($eid) ||
    strcmp($eid, "") == 0) {
    USERERROR("The experiment ID was not provided!", 1);
}

if (!isset($inout) ||
    (strcmp($inout, "in") && strcmp($inout, "out") &&
     strcmp($inout, "pause") && strcmp($inout, "restart") &&
     strcmp($inout, "instop"))) {
    USERERROR("Improper inout argument!", 1);
}

# Canceled operation redirects back to showexp page. See below.
if ($canceled) {
    header("Location: showexp.php3?pid=$pid&eid=$eid");
    return;
}

#
# Standard Testbed Header, after cancel above.
#
PAGEHEADER("Swap Control");

#
# Only admins can issue a force swapout
# 
if (isset($force) && $force == 1) {
	if (! ISADMIN($uid)) {
		USERERROR("Only testbed administrators can forcibly swap ".
			  "an experiment out!", 1);
	}
	if (!isset($idleswap)) { $idleswap=0; }
	if (!isset($autoswap)) { $autoswap=0; }
	if (!isset($forcetype)){ $forcetype="force"; }
	if ($forcetype=="idleswap") { $idleswap=1; }
	if ($forcetype=="autoswap") { $autoswap=1; }
}
else {
	$force = 0;
	$idleswap=0;
	$autoswap=0;
}

$exp_eid = $eid;
$exp_pid = $pid;

#
# Check to make sure thats this is a valid PID/EID tuple.
#
$query_result =
    DBQueryFatal("SELECT * FROM experiments WHERE ".
		 "eid='$exp_eid' and pid='$exp_pid'");
if (mysql_num_rows($query_result) == 0) {
    USERERROR("The experiment $exp_eid is not a valid experiment ".
	      "in project $exp_pid.", 1);
}
$row           = mysql_fetch_array($query_result);
$exp_gid       = $row[gid];
$isbatch       = $row[batchmode];
$state         = $row[state];
$swappable     = $row[swappable];
$idleswap_bit  = $row[idleswap];
$idleswap_time = $row[idleswap_timeout];
$idlethresh    = min($idleswap_time/60.0,TBGetSiteVar("idle/threshold"));

#
# Verify permissions.
#
if (! TBExptAccessCheck($uid, $exp_pid, $exp_eid, $TB_EXPT_MODIFY)) {
    USERERROR("You do not have permission for $exp_eid!", 1);
}

# Convert inout to informative text.
if (!strcmp($inout, "in")) {
    if ($isbatch) 
	$action = "queue";
    else
	$action = "swapin";
}
elseif (!strcmp($inout, "out")) {
    if ($isbatch) 
	$action = "swapout";
    else {
	if ($state == $TB_EXPTSTATE_ACTIVATING) {
	    $action = "cancel";
	}
	else {
	    $action = "swapout";
	}
    }
}
elseif (!strcmp($inout, "pause")) {
    if (!$isbatch)
	USERERROR("Only batch experiments can be dequeued!", 1);
    $action = "Dequeue";
}
elseif (!strcmp($inout, "restart")) {
    $action = "restart";
}

echo "<font size=+2>Experiment <b>".
     "<a href='showproject.php3?pid=$pid'>$pid</a>/".
     "<a href='showexp.php3?pid=$pid&eid=$eid'>$eid</a></b></font>\n";

#
# We run this twice. The first time we are checking for a confirmation
# by putting up a form. The next time through the confirmation will be
# set. Or, the user can hit the cancel button, in which case we 
# redirect the browser back to the experiment page (see above).
#
if (!$confirmed) {
    echo "<center><h2><br>
          Are you sure you want to ";
    if ($force) {
	echo "<font color=red><br>forcibly</br></font> ";
    }
    echo "$action experiment '$exp_eid?'
          </h2>\n";
    
    SHOWEXP($exp_pid, $exp_eid, 1);

    echo "<form action='swapexp.php3?inout=$inout&pid=$exp_pid&eid=$exp_eid'
                method=post>";

    if ($force) {
	if (!$swappable) {
	    echo "<h2>Note: This experiment is <em>NOT</em> swappable!</h2>\n";
	}
	echo "Force Type: <select name=forcetype>\n";
	echo "<option value=force ".($forcetype=="force"?"selected":"").
	    ">Forced Swap</option>\n";
	echo "<option value=idleswap ".($forcetype=="idleswap"?"selected":"").
	    ">Idle-Swap</option>\n";
	echo "<option value=autoswap ".($forcetype=="autoswap"?"selected":"").
	    ">Auto-Swap</option>\n";
	echo "</select><br><br>\n";
	echo "<input type=hidden name=force value=$force>\n";
	echo "<input type=hidden name=idleswap value=$idleswap>\n";
	echo "<input type=hidden name=autoswap value=$autoswap>\n";
    }
    
    echo "<b><input type=submit name=confirmed value=Confirm></b>\n";
    echo "<b><input type=submit name=canceled value=Cancel></b>\n";
    echo "</form>\n";

    if ($inout!="out" && $idleswap_bit) {
	if ($idleswap_time / 60.0 != $idlethresh) {
	    echo "<p>Note: The Idle-Swap time for your experiment will be
		 reset to $idlethresh hours.</p>\n";
	}
    }
    
    if (!strcmp($inout, "restart")) {
	echo "<p>
              <a href='$TBDOCBASE/faq.php3#UTT-Restart'>
                 (Information on experiment restart)</a>\n";
    }
    else {
	echo "<p>
              <a href='$TBDOCBASE/faq.php3#UTT-Swapping'>
                 (Information on experiment swapping)</a>\n";
    }
    echo "</center>\n";

    PAGEFOOTER();
    return;
}

#
# We need the unix gid for the project for running the scripts below.
# Note usage of default group in project.
#
TBGroupUnixInfo($exp_pid, $exp_gid, $unix_gid, $unix_name);

#
# We run a wrapper script that does all the work of terminating the
# experiment. 
#
#   tbstopit <pid> <eid>
#
echo "<center>";
echo "<h2>Starting experiment state change. Please wait a moment ...
      </h2></center>";

flush();

#
# Run the scripts. We use a script wrapper to deal with changing
# to the proper directory and to keep some of these details out
# of this. 
#
# Avoid SIGPROF in child.
# 
set_time_limit(0);

# Args for idleswap It passes them on to swapexp, or if it is just a
# plain force swap, it passes -f for us.
$args = ($idleswap ? "-i" : ($autoswap ? "-a" : ""));

$retval = SUEXEC($uid, $unix_gid,
		 ($force ?
		  "webidleswap $args $exp_pid $exp_eid" :
		  "webswapexp -s $inout $exp_pid $exp_eid"),
		 SUEXEC_ACTION_IGNORE);

#
# Fatal Error. Report to the user, even though there is not much he can
# do with the error. Also reports to tbops.
# 
if ($retval < 0) {
    SUEXECERROR(SUEXEC_ACTION_DIE);
    #
    # Never returns ...
    #
    die("");
}

#
# Exit status 0 means the experiment is swapping, or will be.
#
echo "<br>\n";
if ($retval) {
    echo "<h3>Experiment $action could not proceed</h3>";
    echo "<blockquote><pre>$suexec_output<pre></blockquote>";
}
else {
    if ($isbatch) {
	if (strcmp($inout, "in") == 0) {
	    echo "Batch Mode experiments will be run when enough resources
                  become available. This might happen immediately, or it
                  may take hours or days. You will be notified via email
                  when the experiment has been run. In the meantime, you can
                  check the web page to see how many attempts have been made,
                  and when the last attempt was.\n";
	}
	elseif (strcmp($inout, "out") == 0) {

	    echo "Batch mode experiments take a few moments to stop. Once
                  it does, the experiment will enter the 'paused' state.
                  You can requeue the batch experiment at that time.\n";

	    echo "<br><br>
                  If you do not receive
                  email notification within a reasonable amount of time,
                  please contact $TBMAILADDR.\n";
	}
	elseif (strcmp($inout, "pause") == 0) {
	    echo "Your experiment has been dequeued. You may requeue your
		  experiment at any time.\n";
	}
    }
    else {
	if (strcmp($inout, "out") == 0 &&
	    strcmp($state, $TB_EXPTSTATE_ACTIVATING) == 0) {

	    echo "Your experiment swapin has been marked for cancelation.
                  It typically takes a few minutes for this to be recognized,
                  assuming you made your request early enough. You will
                  be notified via email when the original swapin request has
                  either aborted or finished.\n";
	}
	else {
	    if (strcmp($inout, "in") == 0)
		$howlong = "two to ten";
	    else
		$howlong = "less than two";
    
	    echo "Your experiment has started its $action.
                 You will be notified via email when the operation is complete.
                 This typically takes $howlong minutes, depending on the
                 number of nodes in the experiment.\n";
	}
	echo "<br><br>
              If you do not receive
              email notification within a reasonable amount of time,
              please contact $TBMAILADDR.\n";

	echo "<br><br>
              While you are waiting, you can watch the log in
              <a target=_blank href=spewlogfile.php3?pid=$exp_pid&eid=$exp_eid>
              realtime</a>.\n";
    }
}

#
# Standard Testbed Footer
# 
PAGEFOOTER();
?>
