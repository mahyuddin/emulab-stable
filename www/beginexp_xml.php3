<?php
#
# EMULAB-COPYRIGHT
# Copyright (c) 2000-2004 University of Utah and the Flux Group.
# All rights reserved.
#
include("defs.php3");

#
# No PAGEHEADER since we spit back plain XML output.
#
$errors    = array();

$session_interactive  = 0;
$session_errorhandler = 'handle_error';

#
# Capture script errors and report back to user.
#
function handle_error($message, $death)
{
    XMLSTATUS("weberror", $message);
    if ($death)
	exit(1);
}

#
# Form Errors. 
#
function XMLERROR()
{
    XMLSTATUS("xmlerror", "Invalid form arugments");
}

#
# Helper function to send back errors. This needs some work!
#
function XMLSTATUS($status, $message)
{
    global $errors;

    $results = array();
    $results[status]  = $status;
    $results[message] = $message;
    $results[errors]  = $errors;
    $xmlcode = xmlrpc_encode_request("dummy", $results);

    echo "$xmlcode\n";
    exit(1);
}

#
# Only known and logged in users can begin experiments. Must perform this
# check inline so we can report back status instead of simply dying. I
# need to investigate how to make this cleaner, perhaps with a global variable
# that changes how TBERROR and USERERROR operate. Needs more thought.
#
$uid    = GETLOGIN();
$status = CHECKLOGIN($uid);
if (($status & CHECKLOGIN_NOTLOGGEDIN) != CHECKLOGIN_NOTLOGGEDIN) {
    EXPERROR("autherror", "Not logged in");
}

# Need this below;
$idleswaptimeout = TBGetSiteVar("idle/threshold");

#
# We must get XML code.
# 
if (!isset($xmlcode)) {
    PAGEARGERROR();
}

# Convert the xml into PHP datatypes; an array of arguments. We ignore the
# the method for now. 
$foo = xmlrpc_decode_request($xmlcode, $meth);
if (!isset($foo)) {
    TBERROR("Could not decode XML request!\n\n" .
	    urldecode($xmlcode) . "\n", 1);
}

# First argument is the formfields array. 
$formfields = $foo[0];

#
# Validate the arguments.
#
# Some local variables.
$nsfilelocale    = 0;
$thensfile       = 0;
$deletensfile    = 0;
$nonsfile        = 0;

#
# Project:
#
if (!isset($formfields[exp_pid]) || $formfields[exp_pid] == "") {
    $errors["Project"] = "Not Selected";
}
elseif (!TBvalid_pid($formfields[exp_pid])) {
    $errors["Project"] = TBFieldErrorString();
    # Immediate error since we use this below.
    XMLERROR();
}
elseif (!TBValidProject($formfields[exp_pid])) {
    $errors["Project"] = "No such project";
}

#
# Group: If none specified, then use default group (see below).
#
if (isset($formfields[exp_gid]) && $formfields[exp_gid] != "") {
    if (!TBvalid_gid($formfields[exp_gid])) {
	$errors["Group"] = TBFieldErrorString();
    }
    elseif (!TBValidGroup($formfields[exp_pid], $formfields[exp_gid])) {
	$errors["Group"] = "Group '$exp_gid' is not in project '$exp_pid'";
    }
}

#
# EID:
#
if (!isset($formfields[exp_id]) || $formfields[exp_id] == "") {
    $errors["Experiment Name"] = "Missing Field";
}
elseif (!TBvalid_eid($formfields[exp_id])) {
    $errors["Experiment Name"] = TBFieldErrorString();
}
elseif (TBValidExperiment($formfields[exp_pid], $formfields[exp_id])) {
    $errors["Experiment Name"] = "Already in use";
}

#
# Description:
# 
if (!isset($formfields[exp_description]) ||
    $formfields[exp_description] == "") {
    $errors["Description"] = "Missing Field";
}
elseif (!TBvalid_description($formfields[exp_description])) {
    $errors["Description"] = TBFieldErrorString();
}

#
# NS File. There is a bunch of stuff here for Netbuild, which uses the
# beginexp form as a backend. Switch to XML interface someday ...
#
if (isset($formfields[guid])) {
    if ($formfields[guid] == "" ||
	!preg_match("/^\d+$/", $formfields[guid])) {
	$errors["NS File GUID"] = "Invalid characters";
    }
}
if (isset($formfields[nsref])) {
    if ($formfields[nsref] == "" ||
	!preg_match("/^\d+$/", $formfields[nsref])) {
	$errors["NS File Reference"] = "Invalid characters";
    }
    $nsfilelocale = "nsref";
}
elseif (isset($formfields[exp_localnsfile]) &&
	$formfields[exp_localnsfile] != "") {
    if (!preg_match("/^([-\@\w\.\/]+)$/", $formfields[exp_localnsfile])) {
	$errors["Server NS File"] = "Pathname includes illegal characters";
    }
    elseif (! ereg("^$TBPROJ_DIR/.*",  $formfields[exp_localnsfile]) &&
	    ! ereg("^$TBUSER_DIR/.*",  $formfields[exp_localnsfile]) &&
	    ! ereg("^$TBGROUP_DIR/.*", $formfields[exp_localnsfile])) {
	$errors["Server NS File"] = "Must reside in either ".
	    "$TBUSER_DIR/, $TBPROJ_DIR/, or $TBGROUP_DIR/";
    }
    $nsfilelocale = "local";
}
elseif (isset($formfields[exp_nsfile_contents]) &&
	$formfields[exp_nsfile_contents] != "") {
    #
    # The NS file is encoded inline. We will write it to a tempfile below
    # once all other checks passed.
    #
    $nsfilelocale = "inline";
}
else {
    #
    # I am going to allow shell experiments to be created (No NS file),
    # but only by admin types.
    #
    if (! ISADMIN($uid)) {
	$errors["NS File"] = "You must provide an NS file";
    }
}

#
# Swappable
# Any of these which are not "1" become "0".
#
if (!isset($formfields[exp_swappable]) ||
    strcmp($formfields[exp_swappable], "1")) {
    $formfields[exp_swappable] = 0;

    if (!isset($formfields[exp_noswap_reason]) ||
        !strcmp($formfields[exp_noswap_reason], "")) {

        if (! ISADMIN($uid)) {
	    $errors["Not Swappable"] = "No justification provided";
        }
	else {
	    $formfields[exp_noswap_reason] = "ADMIN";
        }
    }
    elseif (!TBvalid_description($formfields[exp_noswap_reason])) {
	$errors["Not Swappable"] = TBFieldErrorString();
    }
}
else {
    $formfields[exp_swappable]     = 1;
    $formfields[exp_noswap_reason] = "";
}

if (!isset($formfields[exp_idleswap]) ||
    strcmp($formfields[exp_idleswap], "1")) {
    $formfields[exp_idleswap] = 0;

    if (!isset($formfields[exp_noidleswap_reason]) ||
	!strcmp($formfields[exp_noidleswap_reason], "")) {
	if (! ISADMIN($uid)) {
	    $errors["Not Idle-Swappable"] = "No justification provided";
	}
	else {
	    $formfields[exp_noidleswap_reason] = "ADMIN";
	}
    }
    elseif (!TBvalid_description($formfields[exp_noidleswap_reason])) {
	$errors["Not Idle-Swappable"] = TBFieldErrorString();
    }
}
else {
    $formfields[exp_idleswap]          = 1;
    $formfields[exp_noidleswap_reason] = "";
}

# Proper idleswap timeout must be provided.
if (!isset($formfields[exp_idleswap_timeout]) ||
    !preg_match("/^[\d]+$/", $formfields[exp_idleswap_timeout]) ||
    ($formfields[exp_idleswap_timeout] + 0) <= 0 ||
    ($formfields[exp_idleswap_timeout] + 0) > $idleswaptimeout) {
    $errors["Idleswap"] = "Invalid time provided - ".
	"must be non-zero and less than $idleswaptimeout";
}


if (!isset($formfields[exp_autoswap]) ||
    strcmp($formfields[exp_autoswap], "1")) {
    $formfields[exp_autoswap] = 0;
}
else {
    $formfields[exp_autoswap] = 1;
    
    if (!isset($formfields[exp_autoswap_timeout]) ||
	!preg_match("/[\d]+/", $formfields[exp_idleswap_timeout]) ||
	($formfields[exp_autoswap_timeout] + 0) <= 0) {
	$errors["Max. Duration"] = "No or invalid time provided";
    }
}

#
# If any errors, stop now. pid/eid/gid must be okay before continuing.
#
if (count($errors)) {
    XMLERROR();
}

$exp_desc    = escapeshellarg($formfields[exp_description]);
$exp_pid     = $formfields[exp_pid];
$exp_gid     = ((isset($formfields[exp_gid]) && $formfields[exp_gid] != "") ?
		$formfields[exp_gid] : $exp_pid);
$exp_id      = $formfields[exp_id];

#
# Verify permissions. We do this here since pid/eid/gid could be bogus above.
#
if (! TBProjAccessCheck($uid, $exp_pid, $exp_gid, $TB_PROJECT_CREATEEXPT)) {
    $errors["Project/Group"] = "Not $exp_gid enough permission to create experiment";
    XMLERROR();
}

#
# Figure out the NS file to give to the script. Eventually we will allow
# it to come inline as an XML argument.
# 
if ($nsfilelocale == "local") {
    #
    # No way to tell from here if this file actually exists, since
    # the web server runs as user nobody. The startexp script checks
    # for the file so the user will get immediate feedback if the filename
    # is bogus.
    #
    $thensfile = $formfields[exp_localnsfile];
}
elseif ($nsfilelocale == "nsref") {
    $nsref = $formfields[nsref];
    
    if (isset($formfields[guid])) {
	$guid      = $formfields[guid];
	$thensfile = "/tmp/$guid-$nsref.nsfile";
    }
    else {
	$thensfile = "/tmp/$uid-$nsref.nsfile";
    }
    $deletensfile = 1;
}
elseif ($nsfilelocale == "inline") {
    #
    # The NS file is encoded in the URL. Must create a temp file
    # to hold it, and pass through to the backend.
    #
    # Generate a hopefully unique filename that is hard to guess.
    # See backend scripts.
    # 
    list($usec, $sec) = explode(' ', microtime());
    srand((float) $sec + ((float) $usec * 100000));
    $foo = rand();
    
    $thensfile    = "/tmp/$uid-$foo.nsfile";
    $deletensfile = 1;

    if (! ($fp = fopen($thensfile, "w"))) {
	TBERROR("Could not create temporary file $nsfile", 1);
    }
    fwrite($fp, urldecode($formfields[exp_nsfile_contents]));
    fclose($fp);
    chmod($thensfile, 0666);
}
else {
    $nonsfile = 1;
}

#
# Convert other arguments to script parameters.
#
$exp_swappable = "";

# Experiments are swappable by default; supply reason if noswap requested.
if ($formfields[exp_swappable] == "0") {
    $exp_swappable .= " -S " . escapeshellarg($formfields[exp_noswap_reason]);
}

if ($formfields[exp_autoswap] == "1") {
    $exp_swappable .= " -a " . (60 * $formfields[exp_autoswap_timeout]);
}

# Experiments are idle swapped by default; supply reason if noidleswap requested.
if ($formfields[exp_idleswap] == "1") {
    $exp_swappable .= " -l " . (60 * $formfields[exp_idleswap_timeout]);
}
else {
    $exp_swappable .= " -L " .escapeshellarg($formfields[exp_noidleswap_reason]);
}

$exp_batched   = 0;
$exp_preload   = 0;
$batcharg      = "-i";

if (isset($formfields[exp_batched]) &&
    strcmp($formfields[exp_batched], "Yep") == 0) {
    $exp_batched   = 1;
    $batcharg      = "";
}
if (isset($formfields[exp_preload]) &&
    strcmp($formfields[exp_preload], "Yep") == 0) {
    $exp_preload   = 1;
    $batcharg     .= " -f";
}

#
# We need the email address for messages below.
#
TBUserInfo($uid, $user_name, $user_email);

#
# Grab the unix GID for running scripts.
#
TBGroupUnixInfo($exp_pid, $exp_gid, $unix_gid, $unix_name);

#
# Run the backend script.
#
# Avoid SIGPROF in child.
#
set_time_limit(0);

$retval = SUEXEC($uid, $unix_gid,
		 "webbatchexp $batcharg -E $exp_desc $exp_swappable ".
		 "-p $exp_pid -g $exp_gid -e $exp_id ".
		 ($nonsfile ? "" : "$thensfile"),
		 SUEXEC_ACTION_IGNORE);

if ($deletensfile) {
    unlink($thensfile);
}

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

# User error. Tell user and exit.
if ($retval) {
    XMLSTATUS("weberror", $suexec_output);
    exit(1);
}

# Send back a useful message. This needs more thought.
$message = "";
if ($nonsfile) {
    $message =
         "Since you did not provide an NS script, no nodes have been
          allocated. You will not be able to modify or swap this experiment,
          nor do most other neat things you can do with a real experiment.";
}
elseif ($exp_preload) {
    $message = 
         "Since you are only pre-loading the experiment, this will typically
          take less than one minute. If you do not receive email notification
          within a reasonable amount of time, please contact $TBMAILADDR.";
}
elseif ($exp_batched) {
    $message = 
         "Batch Mode experiments will be run when enough resources become
          available. This might happen immediately, or it may take hours
	  or days. You will be notified via email when the experiment has
          been run. If you do not receive email notification within a
          reasonable amount of time, please contact $TBMAILADDR.";
}
else {
    $message = 
         "You will be notified via email when the experiment has been fully
	  configured and you are able to proceed. This typically takes less
          than 10 minutes, depending on the number of nodes you have requested.
          If you do not receive email notification within a reasonable amount
          of time, please contact $TBMAILADDR.";
}
XMLSTATUS("success", $message);
?>
