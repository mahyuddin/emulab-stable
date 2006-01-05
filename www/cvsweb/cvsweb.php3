<?php
#
# EMULAB-COPYRIGHT
# Copyright (c) 2000-2002, 2005 University of Utah and the Flux Group.
# All rights reserved.
#

#
# Wrapper script for cvsweb.cgi
#
chdir("../");
require("defs.php3");

#
# We look for anon access, and if so, redirect to ops web server.
# WARNING: See the LOGGEDINORDIE() calls below.
#
$uid = GETLOGIN();
unset($repodir);

# Tell system we do not want any headers drawn on errors.
$noheaders = 1;

# Use cvsweb or viewvc.
$use_viewvc = 0;

#
# Verify form arguments.
#
if (isset($pid) && $pid != "") {
    if (!$CVSSUPPORT) {
	USERERROR("Project CVS support is not enabled!", 1);
    }
    if (!TBvalid_pid($pid)) {
	PAGEARGERROR("Invalid project ID.");
    }
    # Redirect now, to avoid phishing.
    if ($uid) {
	LOGGEDINORDIE($uid);
    }
    else {
	$url = $OPSCVSURL . "?cvsroot=$pid";
	
	header("Location: $url");
	return;
    }
    if (! TBValidProject($pid)) {
	USERERROR("The project '$pid' is not a valid project.", 1);
    }
    if (isset($eid) && $eid != "") {
	#
	# Wants access to the experiment archive, which is really a repo.
	#
	if (!TBvalid_eid($eid)) {
	    PAGEARGERROR("Invalid experiment ID.");
	}
	if (! TBValidExperiment($pid, $eid)) {
	    USERERROR("Experiment '$pid/$eid' is not a valid experiment", 1);
	}
	if (! ISADMIN($uid) &&
	    ! TBExptAccessCheck($uid, $pid, $eid, $TB_EXPT_READINFO)) {
	    USERERROR("Not enough permission to view '$pid/$eid'", 1);
	}
	# Get the repo index for the experiment.
	$query_result =
	    DBQueryFatal("select s.archive_idx from experiments as e ".
			 "left join experiment_stats as s on s.exptidx=e.idx ".
			 "where e.pid='$pid' and e.eid='$eid'");
	
	if (!mysql_num_rows($query_result)) {
	    TBERROR("Error getting repo index for '$pid/$eid'", 1);
	}
	$row = mysql_fetch_array($query_result);
	if (!isset($row[0])) {
	    TBERROR("Error getting repo index for '$pid/$eid'", 1);
	}
	$repoidx = $row[0];
	$repodir = "/usr/testbed/exparchive/$repoidx/repo/";
	$use_viewvc = 1;
    }
    else {
	#
	# Wants access to the project repo.
	#
	if (! ISADMIN($uid) &&
	    ! TBProjAccessCheck($uid, $pid, $gid, $TB_PROJECT_READINFO)) {
            # Then check to see if the project cvs repo is public.
	    $query_result =
		DBQueryFatal("select cvsrepo_public from projects ".
			     "where pid='$pid'");
	    if (!mysql_num_rows($query_result)) {
		TBERROR("Error getting cvsrepo_public bit", 1);
	    }
	    $row = mysql_fetch_array($query_result);
	    if ($row[0] == 0) {
		USERERROR("You are not a member of Project $pid.", 1);
	    }
	}
	$repodir = "$TBCVSREPO_DIR/$pid";
    }
}
elseif (isset($exptidx) && $exptidx != "") {
    if (!$CVSSUPPORT) {
	USERERROR("Project CVS support is not enabled!", 1);
    }
    if (!TBvalid_integer($exptidx)) {
	PAGEARGERROR("Invalid experiment index.");
    }

    # Must be logged in for this!
    if ($uid) {
	LOGGEDINORDIE($uid);
    }
    
    # Need the pid/eid/gid. Access the stats table since we want to provide
    # cvs access to terminated experiments via the archive.
    $query_result =
	DBQueryFatal("select pid,eid,gid,archive_idx from experiment_stats ".
		     "where exptidx='$exptidx'");
    if (!mysql_num_rows($query_result)) {
	USERERROR("Experiment '$exptidx' is not a valid experiment", 1);
    }
    $row = mysql_fetch_array($query_result);
    $pid = $row[0];
    $eid = $row[1];
    $gid = $row[2];
    $repoidx = $row[3];

    # If a current experiment, check usual permissions.
    if (TBValidExperiment($pid, $eid)) {
	if (! ISADMIN($uid) &&
	    ! TBExptAccessCheck($uid, $pid, $eid, $TB_EXPT_READINFO)) {
	    USERERROR("Not enough permission to view '$pid/$eid'", 1);
	}
	$repodir = "/usr/testbed/exparchive/$repoidx/repo/";
    }
    else {
	if (! ISADMIN($uid)) {
	    USERERROR("Must be administrator to view historical archives!", 1);
	}
	$repodir = "$TBDIR/expinfo/${pid}-${eid}.${exptidx}/Archive/repo";
    }
    $use_viewvc = 1;
}
else {
    LOGGEDINORDIE($uid);
    if (! TBCvswebAllowed($uid)) {
        USERERROR("You do not have permission to use cvsweb!", 1);
    }
    unset($pid);
}

$script = "cvsweb.cgi";

#
# Sine PHP helpfully scrubs out environment variables that we _want_, we
# have to pass them to env.....
#
$query = escapeshellcmd($QUERY_STRING);
$path = escapeshellcmd($PATH_INFO);
$name = escapeshellcmd($SCRIPT_NAME);
$agent = escapeshellcmd($HTTP_USER_AGENT);
$encoding = escapeshellcmd($HTTP_ACCEPT_ENCODING);

#
# Helpfully enough, escapeshellcmd does not escape spaces. Sigh.
#
$script = preg_replace("/ /","\\ ",$script);
$query = preg_replace("/ /","\\ ",$query);
$name = preg_replace("/ /","\\ ",$name);
$agent = preg_replace("/ /","\\ ",$agent);
$encoding = preg_replace("/ /","\\ ",$encoding);

#
# A cleanup function to keep the child from becoming a zombie, since
# the script is terminated, but the children are left to roam.
#
$fp = 0;

function SPEWCLEANUP()
{
    global $fp;

    if (!$fp || !connection_aborted()) {
	exit();
    }
    while ($line = fgets($fp)) {
        # Suck it all up.
        ;
    }
    pclose($fp);
    exit();
}
set_time_limit(0);
register_shutdown_function("SPEWCLEANUP");

$shellcmd = "env PATH=./cvsweb/ QUERY_STRING=$query PATH_INFO=$path " .
            "SCRIPT_NAME=$name HTTP_USER_AGENT=$agent " .
            "HTTP_ACCEPT_ENCODING=$encoding ";

if (isset($repodir)) {
    $prog = ($use_viewvc ? webviewvc : webcvsweb);
    
    # I know, I added an argument to a script that is not supposed to
    # take any. So be it; it was easy.
    $shellcmd .= "$TBSUEXEC_PATH $uid $pid $prog -repo $repodir";
}
else {
    $shellcmd .= "$script";
}

$fp = popen($shellcmd, 'r');

#
# Yuck. Since we can't tell php to shut up and not print headers, we have to
# 'merge' headers from cvsweb with PHP's.
#
while ($line = fgets($fp)) {
    # This indicates the end of headers
    if ($line == "\r\n") { break; }
    header(rtrim($line));
}

#
# Just pass through the rest of cvsweb.cgi's output
#
fpassthru($fp);

fclose($fp);

?>
