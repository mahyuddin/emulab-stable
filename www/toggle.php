<?php
#
# EMULAB-COPYRIGHT
# Copyright (c) 2000-2003 University of Utah and the Flux Group.
# All rights reserved.
#
include("defs.php3");

#
# No PAGEHEADER since we spit out a Location header later. See below.
# 

#
# Only known and logged in users can do this.
#
# Note different test though, since we want to allow logged in
# users with expired passwords to change them.
#
$uid = GETLOGIN();
LOGGEDINORDIE($uid);

#
# This page is a generic toggle page, like adminmode.php3, but more
# generalized. There are a set of things you can toggle, and each of
# those items has a permission check and a set (pair) of valid values.
#

# Usage: toggle.php?type=swappable&value=1&pid=foo&eid=bar
# (type & value are required, others are optional and vary by type)

# List of valid toggles
$toggles = array("adminoff", "swappable", "idleswap", "autoswap",
		 "idle_ignore");

# list of valid values for each toggle
$values  = array("adminoff"    => array(0,1),
		 "swappable"   => array(0,1),
		 "idleswap"    => array(0,1),
		 "autoswap"    => array(0,1),
		 "idle_ignore" => array(0,1) );

if (! in_array($type, $toggles)) {
    USERERROR("There is no toggle for $type!", 1);
}
if (! in_array($value, $values[$type])) {
    USERERROR("The value '$value' is illegal for the $type toggle!", 1);
}

#
# Permissions checks, and do the toggle...
#
if ($type=="adminoff") {
    # must be admin
    # Do not check if they are admin mode (ISADMIN), check if they
    # have the power to change to admin mode!
    if (! ($CHECKLOGIN_STATUS & CHECKLOGIN_ISADMIN) ) {
	USERERROR("You do not have permission to toggle $type!", 1);
    }
    # Admins can change status for other users.
    if (!isset($target_uid)) { $target_uid = $uid; }

    DBQueryFatal("update users set adminoff=$value where uid='$target_uid'");
}
elseif ($type=="swappable" || $type=="idleswap" || $type=="autoswap") {
    # must be admin OR must have permission to modify the expt...
    if (! ISADMIN() && !TBExptAccessCheck($uid, $pid, $eid, $TB_EXPT_MODIFY)) {
	USERERROR("You do not have permission to toggle $type!", 1);
    }
    
    # require pid/eid
    if (!isset($pid) || !isset($eid) ||
	!TBValidExperiment($pid, $eid)) {
	USERERROR("Experiment '$pid/$eid' is not valid!", 1);
    }
    
    DBQueryFatal("update experiments set $type=$value ".
		 "where pid='$pid' and eid='$eid'");

    # Send mail on these changes...
    if ($type!="autoswap" && $value=="0") {
	$q = DBQueryFatal("select * from experiments ".
			  "where pid='$pid' and eid='$eid'");
	$r = mysql_fetch_array($q);
	$cuid = $r[expt_head_uid];
	$suid = $r[expt_swap_uid];

	#
	# Do not send this email if the user is an administrator
	# (adminmode does not matter), and is changing an experiment
	# he created or swapped in. Pointless email.
	#
	if (! (ISADMINISTRATOR() &&
	       (!strcmp($uid, $cuid) || !strcmp($uid, $suid)))) {
	    $s = ($r[swappable] ? "Yes" : "No");
	    $sr= $r[noswap_reason];
	    $i = ($r[idleswap] ? "Yes" : "No");
	    $it= $r[idleswap_timeout] / 60.0;
	    $ir= $r[noidleswap_reason];
	    $a = ($r[autoswap] ? "Yes" : "No");
	    $at= $r[autoswap_timeout] / 60.0;
	    $olds = ($type=="swappable"? "Yes" : $s);
	    $oldi = ($type=="idleswap" ? "Yes" : $i);
	    $olda = ($type=="autoswap" ? "Yes" : $a);
	    
	    TBUserInfo($uid, $user_name, $user_email);
	    TBUserInfo($cuid, $cname, $cemail);
	    TBUserInfo($suid, $sname, $semail);
	    TBMAIL($TBMAIL_OPS,"$pid/$eid swap settings changed",
		   "\nThe swap settings for $pid/$eid have changed.\n".
		   "\nThe $type bit has been cleared.\n".
		   "\nThe old settings were:\n".
		  #"Swappable:\t$olds\t('$sr')\n".
		   "Idleswap:\t$oldi\t(after $it hrs)\t('$ir')\n".
		   "MaxDuration:\t$olda\t(after $at hrs)\n".
		   "\nThe new settings are:\n".
		  #"Swappable:\t$s\t('$sr')\n".
		   "Idleswap:\t$i\t(after $it hrs)\t('$ir')\n".
		   "MaxDuration:\t$a\t(after $at hrs)\n".
		   "\nCreator:\t$cuid ($cname <$cemail>)\n".
		   "Swapper:\t$suid ($sname <$semail>)\n".
		   "\nIf it is necessary to change these settings, ".
		   "please reply to this message \nto notify the user, ".
		   "then change the settings here:\n\n".
		   "$TBBASE/showexp.php3?pid=$pid&eid=$eid\n\n".
		   "Thanks,\nTestbed WWW\n",
		   "From: $user_name <$user_email>\n".
		   "Errors-To: $TBMAIL_WWW");
	}
    }
}
elseif ($type=="idle_ignore") {
    # must be admin 
    if (! ISADMIN() ) {
	USERERROR("You do not have permission to toggle $type!", 1);
    }
    # require pid/eid
    if (!isset($pid) || !isset($eid) ||
	!TBValidExperiment($pid, $eid)) {
	USERERROR("Experiment '$pid/$eid' is not valid!", 1);
    }
    
    DBQueryFatal("update experiments set idle_ignore=$value ".
		 "where pid='$pid' and eid='$eid'");

#} elseif ($type=="foo") {
# Add more here...
#
} else {
    USERERROR("Nobody has permission to toggle $type!", 1);
}
    
#
# Spit out a redirect 
#
if (isset($HTTP_REFERER) && $HTTP_REFERER != "" &&
    strpos($HTTP_REFERER,$_SERVER[SCRIPT_NAME])===false) {
    # Make sure the referer isn't me!
    header("Location: $HTTP_REFERER");
}
else {
    if (isset($target_uid)) {
	header("Location: $TBBASE/showuser.php3?target_uid=$target_uid");
    } elseif (isset($pid) && isset($eid)) {
	header("Location: $TBBASE/showexp.php3?pid=$pid&eid=$eid");
    } else {
	header("Location: $TBBASE/showuser.php3");
    }
}

?>
