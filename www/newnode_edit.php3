<?PHP
#
# EMULAB-COPYRIGHT
# Copyright (c) 2003 University of Utah and the Flux Group.
# All rights reserved.
#
require("defs.php3");

#
# List the nodes that have checked in and are awaint being added the the real
# testbed
#

#
# Standard Testbed Header
#
PAGEHEADER("New Testbed Node");

#
# Only admins can see this page
#
$uid = GETLOGIN();
LOGGEDINORDIE($uid);
$isadmin = ISADMIN($uid);
if (! $isadmin) {
    USERERROR("You do not have admin privileges!", 1);
}


if (!$id) {
    USERERROR("Must specify a node ID!",1);
}

#
# If we had any update information passed to us, do the update now
#
if ($node_id) {
    DBQueryFatal("UPDATE new_nodes SET node_id='$node_id', type='$type', " .
    	"IP='$IP' WHERE new_node_id='$id'");
}

#
# Same for interface update information
#
foreach ($HTTP_GET_VARS as $key => $value) {
    if (preg_match("/iface(\d+)_mac/",$key,$matches)) {
    	$card        = $matches[1];
    	$mac         = $HTTP_GET_VARS["iface${card}_mac"];
    	$type        = $HTTP_GET_VARS["iface${card}_type"];
    	$switch_id   = $HTTP_GET_VARS["iface${card}_switch_id"];
    	$switch_card = $HTTP_GET_VARS["iface${card}_switch_card"];
    	$switch_port = $HTTP_GET_VARS["iface${card}_switch_port"];
    	DBQueryFatal("UPDATE new_interfaces SET mac='$mac', " .
	    "interface_type='$type', switch_id='$switch_id', " .
	    "switch_card='$switch_card', switch_port='$switch_port' " .
	    "WHERE new_node_id=$id AND card='$card'");
    }
}

#
# Get the information about the node they asked for
#
$query_result = DBQueryFatal("SELECT new_node_id, node_id, type, IP, " .
	"DATE_FORMAT(created,'%M %e %H:%i:%s') as created, dmesg " .
	"FROM new_nodes WHERE new_node_id='$id'");

if (mysql_num_rows($query_result) != 1) {
    USERERROR("Error getting information for node ID $id",1);
}

$row = mysql_fetch_array($query_result)

?>

<h4><a href="newnodes_list.php3">Back to the new node list</a></h4>

<form action="newnode_edit.php3" method="get">

<input type="hidden" name="id" value="<?=$id?>">

<h3 align="center">Node</h3>

<table align="center">
<tr>
    <th>ID</th>
    <td><?= $row['new_node_id'] ?></td>
</tr>
<tr>
    <th>Node ID</th>
    <td>
    <input type="text" width=10 name="node_id" value="<?=$row['node_id']?>">
    </td>
</tr>
<tr>
    <th>Type</th>
    <td>
    <input type="text" width=10 name="type" value="<?=$row['type']?>">
    </td>
</tr>
<tr>
    <th>IP</th>
    <td>
    <input type="text" width=10 name="IP" value="<?=$row['IP']?>">
    </td>
</tr>
<tr>
    <th>Created</th>
    <td><?= $row['created'] ?></td>
</tr>
<tr>
    <th>dmesg Output</th>
    <td><?= $row['dmesg'] ?></td>
</tr>
</table>

<h3 align="center">Interfaces</h3>

<table align="center">
<tr>
    <th>Interface</th>
    <th>MAC</th>
    <th>Type</th>
    <th>Switch</th>
    <th>Card</th>
    <th>Port</th>
</tr>

<?

$query_result = DBQueryFatal("SELECT card, mac, interface_type, switch_id, " .
	"switch_card, switch_port FROM new_interfaces where new_node_id=$id");
while ($row = mysql_fetch_array($query_result)) {
    $card        = $row['card'];
    $mac         = $row['mac'];
    $type        = $row['interface_type'];
    $switch_id   = $row['switch_id'];
    $switch_card = $row['switch_card'];
    $switch_port = $row['switch_port'];
    echo "<tr>\n";
    echo "<td>$card</td>\n";
    echo "<td><input type='text' name='iface${card}_mac' size=12 " .
	"value='$mac'></td>\n";
    echo "<td><input type='text' name='iface${card}_type' size=5 " .
	"value='$type'></td>\n";
    echo "<td><input type='text' name='iface${card}_switch_id' size=10 " .
	"value='$switch_id'></td>\n";
    echo "<td><input type='text' name='iface${card}_switch_card' size=3 " .
	"value='$switch_card'></td>\n";
    echo "<td><input type='text' name='iface${card}_switch_port' size=3 " .
	"value='$switch_port'></td>\n";
    echo "</tr>\n";
}

?>

</table>

<br>

<center>
<input type="submit" name="submit" value="Update node">
</center>

<?

#
# Standard Testbed Footer
# 
PAGEFOOTER();

?>
