<?php
include("defs.php3");

#
# Standard Testbed Header
#
PAGEHEADER("Terminate Experiment");

#
# Only known and logged in users can end experiments.
#
$uid = GETLOGIN();
LOGGEDINORDIE($uid);

#
# Must provide the EID!
# 
if (!isset($exp_pideid) ||
    strcmp($exp_pideid, "") == 0) {
  USERERROR("The experiment ID was not provided!", 1);
}

#
# First get the project (PID) from the form parameter, which came in
# as <pid>$$<eid>.
#
$exp_eid = strstr($exp_pideid, "\$\$");
$exp_eid = substr($exp_eid, 2);
$exp_pid = substr($exp_pideid, 0, strpos($exp_pideid, "\$\$", 0));

#
# Check to make sure thats this is a valid PID/EID tuple.
#
$query_result = mysql_db_query($TBDBNAME,
	"SELECT * FROM experiments WHERE ".
        "eid=\"$exp_eid\" and pid=\"$exp_pid\"");
if (mysql_num_rows($query_result) == 0) {
  USERERROR("The experiment $exp_eid is not a valid experiment ".
            "in project $exp_pid.", 1);
}
$row = mysql_fetch_array($query_result);

#
# If the experiment is still being configured, then do not allow it to
# be stopped. The user has to wait!
#
$ready = $row[expt_ready];
if (! $ready) {
    USERERROR("The experiment `$exp_eid' is still configuring!<br>".
	      "The user that created the experiment will be notified via ".
	      "email<br>".
	      "when it has been fully configured and is ready for use.<br>".
	      "At that time you may terminate the experiment.<br>", 1);
}

#
# If the experiment is already in the process of ending, then abort.
# The wrapper script checks this too, but might as well head it off early.
#
$terminating = $row[expt_terminating];
if ($terminating) {
    USERERROR("A termination request for experiment $exp_eid was issued at ".
	      "$terminating.<br>".
	      "You may not issue multiple termination requests for an ".
	      "experiment!<br><br>".
	      "A notification will be sent via email ".
	      "to the user that initiated the termination request when the ".
	      "experiment has been torn down.", 1);
}

#
# Verify that this uid is a member of the project for the experiment
# being displayed.
#
$query_result = mysql_db_query($TBDBNAME,
	"SELECT pid FROM proj_memb WHERE uid=\"$uid\" and pid=\"$exp_pid\"");
if (mysql_num_rows($query_result) == 0) {
  USERERROR("You are not a member of Project $exp_pid for ".
            "Experiment: $exp_eid.", 1);
}

#
# We run this twice. The first time we are checking for a confirmation
# by putting up a form. The next time through the confirmation will be
# set. Or, the user can hit the cancel button, in which case we should
# probably redirect the browser back up a level.
#
if ($canceled) {
    echo "<center><h2><br>
          Experiment termination canceled!
          </h2></center>\n";
    
    PAGEFOOTER();
    return;
}

if (!$confirmed) {
    echo "<center><h2><br>
          Are you <b>REALLY</b>
          sure you want to terminate Experiment '$exp_eid?'
          </h2>\n";
    
    echo "<form action=\"endexp.php3\" method=\"post\">";
    echo "<input type=hidden name=exp_pideid value=\"$exp_pideid\">\n";
    echo "<b><input type=submit name=confirmed value=Confirm></b>\n";
    echo "<b><input type=submit name=canceled value=Cancel></b>\n";
    echo "</form>\n";
    echo "</center>\n";

    PAGEFOOTER();
    return;
}

#
# We need the unix gid for the project for running the scripts below.
#
$query_result = mysql_db_query($TBDBNAME,
	"SELECT unix_gid from projects where pid=\"$exp_pid\"");
if (($row = mysql_fetch_row($query_result)) == 0) {
    TBERROR("Database Error: Getting GID for project $exp_pid.", 1);
}
$gid = $row[0];

#
# We run a wrapper script that does all the work of terminating the
# experiment. 
#
#   tbstopit <pid> <eid>
#
echo "<center><br>";
echo "<h3>Starting experiment termination. Please wait a moment ...
          </center><br><br>
      </h3>";

flush();

#
# Run the scripts. We use a script wrapper to deal with changing
# to the proper directory and to keep some of these details out
# of this. 
#
$output = array();
$retval = 0;
$result = exec("$TBSUEXEC_PATH $uid $gid webendexp $exp_pid $exp_eid",
 	       $output, $retval);

if ($retval) {
    echo "<br><br><h2>
          Termination Failure($retval): Output as follows:
          </h2>
          <br>
          <XMP>\n";
          for ($i = 0; $i < count($output); $i++) {
              echo "$output[$i]\n";
          }
    echo "</XMP>\n";

    die("");
}

echo "<center><br>";
echo "<h2>Experiment `$exp_eid' in project `$exp_pid' is terminating!<br><br>
          You will be notified via email when the experiment has been torn<br>
	  down, and you can reuse the experiment name.<br>";
echo "</h2>";
echo "</center>\n";

#
# Standard Testbed Footer
# 
PAGEFOOTER();
?>
