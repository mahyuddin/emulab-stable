<?php
#
# EMULAB-COPYRIGHT
# Copyright (c) 2000-2002, 2004, 2005 University of Utah and the Flux Group.
# All rights reserved.
#
chdir("..");
include("defs.php3");

#
# Only known and logged in users can watch LEDs
#
$uid = GETLOGIN();
LOGGEDINORDIE($uid);

#
# Verify page arguments. Allow user to optionally specify building/floor.
#
#
# Verify page arguments.
# 
if (!isset($pid) ||
    strcmp($pid, "") == 0) {
    PAGEARGERROR("You must provide a Project ID.");
}

if (!isset($eid) ||
    strcmp($eid, "") == 0) {
    PAGEARGERROR("You must provide an Experiment ID.");
}

if (!preg_match("/^[-\w]+$/", $pid)) {
    PAGEARGERROR("Invalid pid argument.");
}
if (!preg_match("/^[-\w]+$/", $eid)) {
    PAGEARGERROR("Invalid eid argument.");
}

#
# Check to make sure this is a valid PID/EID tuple.
#
if (! TBValidExperiment($pid, $eid)) {
  USERERROR("Experiment $pid/$eid is not a valid experiment.", 1);
}

#
# Verify Permission.
#
if (! TBExptAccessCheck($uid, $pid, $eid, $TB_EXPT_READINFO)) {
    USERERROR("You do not have permission to access experiment $pid/$eid!", 1);
}

# Initial goo.
header("Content-Type: text/plain");
header("Expires: Mon, 26 Jul 1997 05:00:00 GMT");
header("Cache-Control: no-cache, must-revalidate");
header("Pragma: no-cache");
flush();

#
# Clean up when the remote user disconnects
#
function SPEWCLEANUP()
{
    exit(0);
}
register_shutdown_function("SPEWCLEANUP");

# Get the virtual node info
$query_result =
    DBQueryFatal("select vname,fixed from virt_nodes ".
		 "where pid='$pid' and eid='$eid' ".
		 "order by vname");

while ($row = mysql_fetch_array($query_result)) {
    $vname  = $row["vname"];
    $fixed  = $row["fixed"];

    if (!isset($fixed))
	$fixed = "";
							      
    echo "$vname, $fixed\n";
}

?>
