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
# Only known and logged in users can end experiments.
#
$uid = GETLOGIN();
LOGGEDINORDIE($uid);
$idleswaptimeout = TBGetSiteVar("idle/threshold");

#
# Verify page arguments.
#
if (!isset($pid) ||
    strcmp($pid, "") == 0) {
    USERERROR("You must provide a Project ID.", 1);
}

if (!isset($eid) ||
    strcmp($eid, "") == 0) {
    USERERROR("You must provide an Experiment ID.", 1);
}

#
# Check to make sure this is a valid PID/EID tuple.
#
if (! TBValidExperiment($pid, $eid)) {
    USERERROR("The experiment $eid is not a valid experiment ".
	      "in project $pid.", 1);
}

#
# Verify Permission.
#
if (! TBExptAccessCheck($uid, $pid, $eid, $TB_EXPT_MODIFY)) {
    USERERROR("You do not have permission to modify experiment $pid/$eid!", 1);
}

#
# Spit the form out using the array of data.
#
function SPITFORM($formfields, $errors)
{
    global $eid, $pid, $TBDOCBASE;

    #
    # Standard Testbed Header
    #
    PAGEHEADER("Edit Experiment Metadata");

    echo "<font size=+2>Experiment <b>".
         "<a href='showproject.php3?pid=$pid'>$pid</a>/".
         "<a href='showexp.php3?pid=$pid&eid=$eid'>$eid</a></b>\n".
         "</font>\n";
    echo "<br><br>\n";

    if ($errors) {
	echo "<table class=nogrid
                     align=center border=0 cellpadding=6 cellspacing=0>
              <tr>
                 <th align=center colspan=2>
                   <font size=+1 color=red>
                      &nbsp;Oops, please fix the following errors!&nbsp;
                   </font>
                 </td>
              </tr>\n";

	while (list ($name, $message) = each ($errors)) {
	    echo "<tr>
                     <td align=right>
                       <font color=red>$name:&nbsp;</font></td>
                     <td align=left>
                       <font color=red>$message</font></td>
                  </tr>\n";
	}
	echo "</table><br>\n";
    }

    echo "<table align=center border=1>
          <form action=editexp.php3?pid=$pid&eid=$eid method=post>\n";

    echo "<tr>
             <td>Description:</td>
             <td class=left>
                 <input type=text
                        name=\"formfields[description]\"
                        value=\"" . $formfields[description] . "\"
	                size=30>
             </td>
          </tr>\n";

    #
    # Swapping goo.
    #
    $swaplink = "$TBDOCBASE/docwrapper.php3?docname=swapping.html";

    echo "<tr>
	      <td class='pad4'>
		  <a href='${swaplink}#swapping'>Swapping:
              </td>
	      <td>
	          <table cellpadding=0 cellspacing=0 border=0>\n";
    if (ISADMIN()) {
        #
        # Batch Experiment?
        #
	echo "    <tr>
  	              <td>
                           <input type=checkbox
                                  name='formfields[idle_ignore]'
                                  value=1";

	if (isset($formfields[idle_ignore]) &&
	    strcmp($formfields[idle_ignore], "1") == 0) {
	    echo " checked='1'";
	}

	echo ">
                      </td>
                      <td>
	                   Idle Ignore
                      </td>
                  </tr>\n";

	echo "    <tr>
                       <td>
                          <input type='checkbox'
	                         name='formfields[swappable]'
	                         value='1'";

	if ($formfields[swappable] == "1") {
	    echo " checked='1'";
	}
	echo ">
                      </td>
                      <td>
                          <a href='{$swaplink}#swapping'>
	                     <b>Swappable:</b></a>
                             This experiment can be swapped.
                      </td>
	              </tr>
	              <tr>
                      <td></td>
   	              <td>If not, why not (administrators option)?<br>
                          <textarea rows=2 cols=50
                                    name='formfields[noswap_reason]'>" .
	                    htmlspecialchars($formfields[noswap_reason],
					     ENT_QUOTES) .
	                 "</textarea>
                      </td>
	              </tr><tr>\n";
    }
    echo "            <td>
                      <input type='checkbox'
	                     name='formfields[idleswap]'
	                     value='1'";

    if ($formfields[idleswap] == "1") {
	echo " checked='1'";
    }
    echo ">
                  </td>
                  <td>
                      <a href='{$swaplink}#idleswap'>
	                 <b>Idle-Swap:</b></a>
                         Swap out this experiment after
                         <input type='text'
                                name='formfields[idleswap_timeout]'
		                value='" . $formfields[idleswap_timeout] . "'
                                size='3'>
                         hours idle.
                  </td>
	          </tr>
	          <tr>
                  <td></td>
   	          <td>If not, why not?<br>
                      <textarea rows=2 cols=50
                                name='formfields[noidleswap_reason]'>" .
	                    htmlspecialchars($formfields[noidleswap_reason],
					     ENT_QUOTES) .
	             "</textarea>
                  </td>
	          </tr><tr>
  	          <td>
                      <input type='checkbox'
		             name='formfields[autoswap]'
		             value='1' ";

    if ($formfields[autoswap] == "1") {
	echo " checked='1'";
    }
    echo ">
                  </td>
	          <td>
                      <a href='${swaplink}#autoswap'>
	                 <b>Max. Duration:</b></a>
                      Swap out after
                        <input type='text'
                               name='formfields[autoswap_timeout]'
		               value='" . $formfields[autoswap_timeout] . "'
                               size='3'>
                      hours, even if not idle.
                  </td>
               </tr>
             </table>
            </td>
         </tr>";

    #
    # Resource usage.
    #
    echo "<tr>
              <td class='pad4'>CPU Usage:</td>
              <td class=left>
                  <input type=text
                         name=\"formfields[cpu_usage]\"
                         value=\"" . $formfields[cpu_usage] . "\"
	                 size=2>
                  (PlanetLab Nodes Only: 1 &lt= X &lt= 5)
              </td>
          </tr>\n";

    echo "<tr>
              <td class='pad4'>Mem Usage:</td>
              <td class=left>
                  <input type=text
                         name=\"formfields[mem_usage]\"
                         value=\"" . $formfields[mem_usage] . "\"
	                 size=2>
                  (PlanetLab Nodes Only: 1 &lt= X &lt= 5)
              </td>
          </tr>\n";

    #
    # Batch Experiment?
    #
    echo "<tr>
  	      <td class=left colspan=2>
              <input type=checkbox name='formfields[batchmode]' value='1'";

    if (isset($formfields[batchmode]) &&
	strcmp($formfields[batchmode], "1") == 0) {
	    echo " checked='1'";
    }

    echo ">\n";
    echo "Batch Mode Experiment &nbsp;
          <font size='-1'>(See
          <a href='$TBDOCBASE/tutorial/tutorial.php3#BatchMode'>Tutorial</a>
          for more information)</font>
          </td>
          </tr>\n";

    echo "<tr>
              <td colspan=2 align=center>
                 <b><input type=submit name=submit value=Submit></b>
              </td>
          </tr>\n";

    echo "</form>
          </table>\n";
}

#
# Suck the current info out of the database.
#
$query_result =
    DBQueryFatal("select * from experiments where pid='$pid' and eid='$eid'");

if (($row = mysql_fetch_array($query_result)) == 0) {
    USERERROR("Experiment $eid in project $pid is gone!\n", 1);
}
#
# We might need these later for email.
#
$creator = $row[expt_head_uid];
$swapper = $row[expt_swap_uid];
$doemail = 0;

#
# Construct a defaults array based on current DB info. Used for the initial
# form, and to determine if any changes were made and to send email.
#
$defaults                    = array();
$defaults[description]       = stripslashes($row[expt_name]);
$defaults[idle_ignore]       = $row[idle_ignore];
$defaults[batchmode]         = $row[batchmode];
$defaults[swappable]         = $row[swappable];
$defaults[noswap_reason]     = stripslashes($row[noswap_reason]);
$defaults[idleswap]          = $row[idleswap];
$defaults[idleswap_timeout]  = $row[idleswap_timeout] / 60.0;
$defaults[noidleswap_reason] = stripslashes($row[noidleswap_reason]);
$defaults[autoswap]          = $row[autoswap];
$defaults[autoswap_timeout]  = $row[autoswap_timeout] / 60.0;
$defaults[idle_ignore]       = $row[idle_ignore];
$defaults[mem_usage]         = $row["mem_usage"];
$defaults[cpu_usage]         = $row["cpu_usage"];

#
# A couple of defaults for turning things on.
#
if (!$defaults[autoswap]) {
     $defaults[autoswap_timeout] = 10;
}
if (!$defaults[idleswap]) {
     $defaults[idleswap_timeout] = $idleswaptimeout;
}

#
# On first load, display initial values.
#
if (! isset($submit)) {
    SPITFORM($defaults, 0);
    PAGEFOOTER();
    return;
}

#
# Otherwise, must validate and redisplay if errors. Build up a DB insert
# string as we go.
#
$errors  = array();
$inserts = array();

#
# Description
#
if (!isset($formfields[description]) ||
    strcmp($formfields[description], "") == 0) {
    $errors["Description"] = "Missing Field";
}
else {
    $inserts[] = "expt_name='" . addslashes($formfields[description]) . "'";
}

#
# Swappable/Idle Ignore
# Any of these which are not "1" become "0".
#
# Idle Ignore
#
if (!isset($formfields[idle_ignore]) ||
    strcmp($formfields[idle_ignore], "1")) {
    $formfields[idle_ignore] = 0;
    $inserts[] = "idle_ignore=0";
}
else {
    $formfields[idle_ignore] = 1;
    $inserts[] = "idle_ignore=1";
}

#
# Swappable
#
if (ISADMIN() && (!isset($formfields[swappable]) ||
    strcmp($formfields[swappable], "1"))) {
    $formfields[swappable] = 0;

    if (!isset($formfields[noswap_reason]) ||
        !strcmp($formfields[noswap_reason], "")) {

        if (!ISADMIN()) {
	    $errors["Swappable"] = "No justification provided";
        }
	else {
	    $formfields[noswap_reason] = "ADMIN";
        }
    }
    if ($defaults[swappable])
	$doemail = 1;
    $inserts[] = "swappable=0";
    $inserts[] = "noswap_reason='" .
	         addslashes($formfields[noswap_reason]) . "'";
}
else {
    $inserts[] = "swappable=1";
    $inserts[] = "noswap_reason='" .
	         addslashes($formfields[noswap_reason]) . "'";
}

#
# IdleSwap
#
if (!isset($formfields[idleswap]) ||
    strcmp($formfields[idleswap], "1")) {
    $formfields[idleswap] = 0;

    if (!isset($formfields[noidleswap_reason]) ||
	!strcmp($formfields[noidleswap_reason], "")) {

	if (! ISADMIN()) {
	    $errors["IdleSwap"] = "No justification provided";
	}
	else {
	    $formfields[noidleswap_reason] = "ADMIN";
	}
    }
    if ($defaults[idleswap])
	$doemail = 1;
    $inserts[] = "idleswap=0";
    $inserts[] = "idleswap_timeout=0";
    $inserts[] = "noidleswap_reason='" .
	         addslashes($formfields[noidleswap_reason]) . "'";
}
elseif (!isset($formfields[idleswap_timeout]) ||
	($formfields[idleswap_timeout] + 0) <= 0 ||
	( (($formfields[idleswap_timeout] + 0) > $idleswaptimeout) &&
	  !ISADMIN()) ) {
    $errors["Idleswap"] = "Invalid time provided (0 < X <= $idleswaptimeout)";
}
else {
    $inserts[] = "idleswap=1";
    $inserts[] = "idleswap_timeout=" . 60 * $formfields[idleswap_timeout];
    $inserts[] = "noidleswap_reason='" .
	         addslashes($formfields[noidleswap_reason]) . "'";
}

#
# AutoSwap
#
if (!isset($formfields[autoswap]) ||
    strcmp($formfields[autoswap], "1")) {
    $formfields[autoswap] = 0;
    $inserts[] = "autoswap=0";
    $inserts[] = "autoswap_timeout=0";
}
elseif (!isset($formfields[autoswap_timeout]) ||
	($formfields[autoswap_timeout] + 0) == 0) {
    $errors["Max Duration"] = "Invalid time provided";
}
else {
    $inserts[] = "autoswap=1";
    $inserts[] = "autoswap_timeout=" . 60 * $formfields[autoswap_timeout];
}

#
# CPU Usage
#
if (isset($formfields[cpu_usage]) &&
    strcmp($formfields[cpu_usage], "")) {

    if (($formfields[cpu_usage] + 0) < 0 ||
	($formfields[cpu_usage] + 0) > 5) {
	$errors["CPU Usage"] = "Invalid (0 <= X <= 5)";
    }
    else {
	$inserts[] = "cpu_usage=$formfields[cpu_usage]";
    }
}
else {
    $inserts[] = "cpu_usage=0";
}

#
# Mem Usage
#
if (isset($formfields[mem_usage]) &&
    strcmp($formfields[mem_usage], "")) {

    if (($formfields[mem_usage] + 0) < 0 ||
	($formfields[mem_usage] + 0) > 5) {
	$errors["Mem Usage"] = "Invalid (0 <= X <= 5)";
    }
    else {
	$inserts[] = "mem_usage=$formfields[mem_usage]";
    }
}
else {
    $inserts[] = "mem_usage=0";
}

#
# Spit any errors before dealing with batchmode, which changes the DB.
#
if (count($errors)) {
    SPITFORM($formfields, $errors);
    PAGEFOOTER();
    return;
}

#
# Converting the batchmode is tricky, but we can let the DB take care
# of it by requiring that the experiment not be locked, and it be in
# the paused state. If the query fails, we know that the experiment
# was in transition.
#
if (!isset($formfields[batchmode])) {
    $formfields[batchmode] = 0;
}
if ($defaults[batchmode] != $formfields[batchmode]) {
    $batchstate = TBDB_BATCHSTATE_PAUSED;
    $success    = 0;

    if (strcmp($formfields[batchmode], "1")) {
	$batchmode = 0;
	$formfields[batchmode] = 0;
    }
    else {
	$batchmode = 1;
	$formfields[batchmode] = 1;
    }

    DBQueryFatal("lock tables experiments write");

    $query_result =
	DBQueryFatal("update experiments set ".
		     "   batchmode=$batchmode ".
		     "where pid='$pid' and eid='$eid' and ".
		     "     expt_locked is NULL and batchstate='$batchstate'");

    $success = DBAffectedRows();

    DBQueryFatal("unlock tables");

    #
    # Lets see if that worked.
    #
    if (! $query_result || !$success) {
	$errors["Batch Mode"] = "Experiment is running or in transition; ".
	    "try again later";

	SPITFORM($formfields, $errors);
	PAGEFOOTER();
	return;
    }
}

#
# Otherwise, do the other inserts.
#
DBQueryFatal("update experiments set ".
	     implode(",", $inserts) . " ".
	     "where pid='$pid' and eid='$eid'");

#
# Do not send this email if the user is an administrator
# (adminmode does not matter), and is changing an expt he created
# or swapped in. Pointless email.
if ($doemail &&
    ! (ISADMINISTRATOR() &&
       (!strcmp($uid, $creator) || !strcmp($uid, $swapper)))) {

    TBUserInfo($uid,     $user_name, $user_email);
    TBUserInfo($creator, $cname, $cemail);
    TBUserInfo($swapper, $sname, $semail);

    $olds = ($defaults[swappable] ? "Yes" : "No");
    $oldsr= $defaults[noswap_reason];
    $oldi = ($defaults[idleswap] ? "Yes" : "No");
    $oldit= $defaults[idleswap_timeout];
    $oldir= $defaults[noidleswap_reason];
    $olda = ($defaults[autoswap] ? "Yes" : "No");
    $oldat= $defaults[autoswap_timeout];

    $s    = ($formfields[swappable] ? "Yes" : "No");
    $sr   = $formfields[noswap_reason];
    $i    = ($formfields[idleswap] ? "Yes" : "No");
    $it   = $formfields[idleswap_timeout];
    $ir   = $formfields[noidleswap_reason];
    $a    = ($formfields[autoswap] ? "Yes" : "No");
    $at   = $formfields[autoswap_timeout];

    TBMAIL($TBMAIL_OPS,"$pid/$eid swap settings changed",
	   "\nThe swap settings for $pid/$eid have changed.\n".
	   "\nThe old settings were:\n".
	   "Swappable:\t$olds\t($oldsr)\n".
	   "Idleswap:\t$oldi\t(after $oldit hrs)\t($oldir)\n".
	   "MaxDuration:\t$olda\t(after $oldat hrs)\n".
	   "\nThe new settings are:\n".
	   "Swappable:\t$s\t($sr)\n".
	   "Idleswap:\t$i\t(after $it hrs)\t($ir)\n".
	   "MaxDuration:\t$a\t(after $at hrs)\n".
	   "\nCreator:\t$creator ($cname <$cemail>)\n".
	   "Swapper:\t$swapper ($sname <$semail>)\n".
	   "\nIf it is necessary to change these settings, ".
	   "please reply to this message \nto notify the user, ".
	   "then change the settings here:\n\n".
	   "$TBBASE/showexp.php3?pid=$pid&eid=$eid\n\n".
	   "Thanks,\nTestbed WWW\n",
	   "From: $user_name <$user_email>\n".
	   "Errors-To: $TBMAIL_WWW");
}

#
# Spit out a redirect so that the history does not include a post
# in it. The back button skips over the post and to the form.
#
header("Location: showexp.php3?pid=$pid&eid=$eid");

?>
