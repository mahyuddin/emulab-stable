<?php
#
# EMULAB-COPYRIGHT
# Copyright (c) 2000-2004 University of Utah and the Flux Group.
# All rights reserved.
#
include("defs.php3");
include("showstuff.php3");

#
# Standard Testbed Header
#
PAGEHEADER("Node Information");

#
# Only known and logged in users can do this.
#
$uid = GETLOGIN();
LOGGEDINORDIE($uid);
$isadmin = ISADMIN($uid);

#
# Verify form arguments.
# 
if (!isset($node_id) ||
    strcmp($node_id, "") == 0) {
    USERERROR("You must provide a node ID.", 1);
}
if (!TBvalid_node_id($node_id)) {
    PAGEARGERROR("Illegal characters in arguments");
}

#
# Check to make sure that this is a valid nodeid
#
if (! TBValidNodeName($node_id)) {
    USERERROR("$node_id is not a valid node name!", 1);
}

echo "<font size=+2>".
     "Node <b>$node_id</b></font>";

#
# Admin users can look at any node, but normal users can only control
# nodes in their own experiments.
#
if (! $isadmin &&
    ! TBNodeAccessCheck($uid, $node_id, $TB_NODEACCESS_MODIFYINFO)) {
    SHOWNODE($node_id, SHOWNODE_NOPERM);
    PAGEFOOTER();
    return;
}

$query_result =
    DBQueryFatal("select r.vname,r.pid,r.eid from nodes as n ".
		 "left join reserved as r on n.node_id=r.node_id ".
		 "where n.node_id='$node_id'");

if (! mysql_num_rows($query_result) != 0) {
    TBERROR("Node $node id does not have a nodes table entry!", 1);
}

$row = mysql_fetch_array($query_result);
$vname		= $row[vname];
$pid 		= $row[pid];
$eid		= $row[eid];

if (isset($pid) && $vname != "") {
    echo " (<b>".
	 "   $vname.".
	 "   <a href='showexp.php3?pid=$pid&eid=$eid'>$eid</a>.".
	 "   <a href='showproject.php3?pid=$pid'>$pid</a>.".
	 "       $OURDOMAIN".
	 "  </b>)";
}	

echo "</font><br><br>\n";

SUBPAGESTART();
SUBMENUSTART("Node Options");

#
# Tip to node option
#
if (TBHasSerialConsole($node_id)) {
    WRITESUBMENUBUTTON("Connect to Serial Line</a> " . 
	"<a href=\"faq.php3#UTT-TUNNEL\">(howto)",
	"nodetipacl.php3?node_id=$node_id");
}

#
# SSH to option.
# 
if (isset($pid)) {
    WRITESUBMENUBUTTON("SSH to node</a> ".
		       "<a href='docwrapper.php3?docname=ssh-mime.html'>".
		       "(howto)", "nodessh.php3?node_id=$node_id");
}

#
# Edit option
#
WRITESUBMENUBUTTON("Edit Node Info",
		   "nodecontrol_form.php3?node_id=$node_id");

if (TBNodeAccessCheck($uid, $node_id, $TB_NODEACCESS_REBOOT)) {
    if (isset($pid)) {
	WRITESUBMENUBUTTON("Update Node",
			   "updateaccounts.php3?pid=$pid&eid=$eid".
			   "&nodeid=$node_id");
    }
    WRITESUBMENUBUTTON("Reboot Node",
		       "boot.php3?node_id=$node_id");
}

if (TBNodeAccessCheck($uid, $node_id, $TB_NODEACCESS_LOADIMAGE)) {
    WRITESUBMENUBUTTON("Create a Disk Image",
		       "newimageid_ez.php3?formfields[node]=$node_id");
}

if ($isadmin) {
    WRITESUBMENUBUTTON("Show Node Log",
		       "shownodelog.php3?node_id=$node_id");
    WRITESUBMENUBUTTON("Free Node",
		       "freenode.php3?node_id=$node_id");
}
SUBMENUEND();

#
# Dump record.
# 
SHOWNODE($node_id);

SUBPAGEEND();

#
# Standard Testbed Footer
# 
PAGEFOOTER();
?>




