<?php
#
# EMULAB-COPYRIGHT
# Copyright (c) 2000-2003 University of Utah and the Flux Group.
# All rights reserved.
#
include("defs.php3");

#
# Standard Testbed Header
#
PAGEHEADER("Node Type Information");

#
# Anyone can access this info, its a PUBLIC PAGE!
#

#
# Verify form arguments.
# 
if (!isset($node_type) ||
    strcmp($node_type, "") == 0) {
    USERERROR("You must provide a node type.", 1);
}

#
# Check to make sure that this is a valid nodeid
#
if (! TBValidNodeType($node_type)) {
    USERERROR("$node_type is not a valid node type!", 1);
}

$query_result =
    DBQueryFatal("select * from node_types ".
		 "where type='$node_type'");

if (! mysql_num_rows($query_result) != 0) {
    TBERROR("No entry for node_type $node_type!", 1);
}
$noderow = mysql_fetch_assoc($query_result);

echo "<font size=+2>".
     "Node Type <b>$node_type</b>".
     "</font>\n";

echo "<table border=2 cellpadding=0 cellspacing=2
             align=center>\n";

$class		= $noderow["class"];
$proc		= $noderow["proc"];
$speed		= $noderow["speed"];
$RAM		= $noderow["RAM"];
$HD		= $noderow["HD"];
$max_interfaces = $noderow["max_interfaces"];
$osid		= $noderow["osid"];
$imageid	= $noderow["imageid"];
$imageable	= $noderow["imageable"];
$delay_capacity = $noderow["delay_capacity"];
$virtnode_capacity = $noderow["virtnode_capacity"];
$delay_osid	= $noderow["delay_osid"];
$jail_osid	= $noderow["jail_osid"];
$isvirtnode	= $noderow["isvirtnode"];
$isremotenode	= $noderow["isremotenode"];

TBOSInfo($osid, $osname, $pid);
TBOSInfo($jail_osid, $jail_osname, $pid);
TBOSInfo($delay_osid, $delay_osname, $pid);
TBImageInfo($imageid, $imagename, $pid);

echo "<tr>
      <td>Type:</td>
      <td class=left>$node_type</td>
          </tr>\n";

echo "<tr>
      <td>Class:</td>
      <td class=left>$class</td>
          </tr>\n";

if ($isremotenode) {
    echo "<tr>
          <td>Remote:</td>
          <td class=left>Yes</td>
              </tr>\n";
}

if ($isvirtnode) {
    echo "<tr>
          <td>Virtual:</td>
          <td class=left>Yes</td>
              </tr>\n";
}

echo "<tr>
      <td>Processor:</td>
      <td class=left>$proc</td>
          </tr>\n";

echo "<tr>
      <td>Speed:</td>
      <td class=left>$speed MHZ</td>
          </tr>\n";

echo "<tr>
      <td>RAM:</td>
      <td class=left>$RAM MB</td>
          </tr>\n";

echo "<tr>
      <td>Disk Size:</td>
      <td class=left>$HD GB</td>
          </tr>\n";

echo "<tr>
      <td>Interfaces:</td>
      <td class=left>$max_interfaces</td>
          </tr>\n";

echo "<tr>
      <td>Delay Capacity:</td>
      <td class=left>$delay_capacity</td>
          </tr>\n";

echo "<tr>
      <td>Jail Capacity:</td>
      <td class=left>$virtnode_capacity</td>
          </tr>\n";

echo "<tr>
      <td>Default OSID:</td>
      <td class=left>$osname</td>
          </tr>\n";

echo "<tr>
      <td>Jail OSID:</td>
      <td class=left>$jail_osname</td>
          </tr>\n";

echo "<tr>
      <td>Delay OSID:</td>
      <td class=left>$delay_osname</td>
          </tr>\n";

echo "<tr>
      <td>Default ImageID:</td>
      <td class=left>$imagename</td>
          </tr>\n";

echo "</table>\n";

#
# Standard Testbed Footer
# 
PAGEFOOTER();
?>




