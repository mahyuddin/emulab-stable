<?php
#
# EMULAB-COPYRIGHT
# Copyright (c) 2000-2004 University of Utah and the Flux Group.
# All rights reserved.
#
include("defs.php3");

#
# This page is used for both admin node control, and for mere user
# information purposes. Be careful about what you do outside of
# $isadmin tests.
# 

#
# Standard Testbed Header
#
PAGEHEADER("Node Control Center");

#
# Only known and logged in users can do this.
#
$uid = GETLOGIN();
LOGGEDINORDIE($uid);
$isadmin = ISADMIN($uid);

#
# Admin users can control nodes.
#
$isadmin = ISADMIN($uid);

echo "<b>Show: <a href='nodecontrol_list.php3?showtype=summary'>summary</a>,
               <a href='nodecontrol_list.php3?showtype=pcs'>pcs</a>,
               <a href='nodecontrol_list.php3?showtype=widearea'>widearea</a>";

if ($isadmin) {
    echo    ", <a href='nodecontrol_list.php3?showtype=virtnodes'>virtual</a>,
               <a href='nodecontrol_list.php3?showtype=physical'>physical</a>,
               <a href='nodecontrol_list.php3?showtype=all'>all</a>";
}
echo ".</b><br>\n";

if (!isset($showtype)) {
    $showtype='summary';
}

$additionalVariables = "";
$additionalLeftJoin  = "";

if (! strcmp($showtype, "summary")) {
    # Separate query below.
    $role   = "";
    $clause = "";
    $view   = "Free Node Summary";
}
elseif (! strcmp($showtype, "all")) {
    $role   = "(role='testnode' or role='virtnode')";
    $clause = "";
    $view   = "All";
}
elseif (! strcmp($showtype, "pcs")) {
    $role   = "(role='testnode')";
    $clause = "and (nt.class='pc')";
    $view   = "PCs";
}
elseif (! strcmp($showtype, "sharks")) {
    $role   = "(role='testnode')";
    $clause = "and (nt.class='shark')";
    $view   = "Sharks";
}
elseif (! strcmp($showtype, "virtnodes")) {
    $role   = "(role='virtnode')";
    $clause = "";
    $view   = "Virtual Nodes";
}
elseif (! strcmp($showtype, "physical")) {
    $role   = "";
    $clause = "(nt.isvirtnode=0)";
    $view   = "Physical Nodes";
}
elseif (! strcmp($showtype, "widearea")) {
    $role   = "(role='testnode')";
    $clause = "and (nt.isremotenode=1)";

    $additionalVariables = ",".
			   "wani.machine_type,".
			   "REPLACE(CONCAT_WS(', ',".
			   "wani.city,wani.state,wani.country,wani.zip), ".
		 	   "'USA, ','')".
			   "AS location, ".
	 		   "wani.connect_type, ".
			   "wani.hostname";
    $additionalLeftJoin = "LEFT JOIN widearea_nodeinfo AS wani ".
			  "ON n.node_id=wani.node_id";

    $view   = "Widearea";
}
else {
    $role   = "(role='testnode')";
    $clause = "and (nt.class='pc')";
    $view   = "PCs";
}
# If admin or widearea, show the vname too. 
$showvnames = 0;
if ($isadmin || !strcmp($showtype, "widearea")) {
    $showvnames = 1;
}

#
# Summary info very different.
# 
if (! strcmp($showtype, "summary")) {
    # Get permissions table so as not to show nodes the user is not allowed
    # to see.
    $perms = array();
    
    if (!$isadmin) {
	$query_result =
	    DBQueryFatal("select type from nodetypeXpid_permissions");

	while ($row = mysql_fetch_array($query_result)) {
	    $perms{$row[0]} = 0;
	}
    
	$query_result =
	    DBQueryFatal("select distinct type from group_membership as g ".
			 "left join nodetypeXpid_permissions as p ".
			 "     on g.pid=p.pid ".
			 "where uid='$uid'");
	
	while ($row = mysql_fetch_array($query_result)) {
	    $perms{$row[0]} = 1;
	}
    }
    
    # Get totals by type.
    $query_result =
	DBQueryFatal("select n.type,count(*) from nodes as n ".
		     "left join node_types as nt on n.type=nt.type ".
		     "where (role='testnode') and ".
		     "      (nt.class!='shark' and nt.class!='pcRemote' ".
		     "      and nt.class!='pcplabphys') ".
		     "group BY n.type");

    $totals    = array();
    $freecount = array();

    while ($row = mysql_fetch_array($query_result)) {
	$type  = $row[0];
	$count = $row[1];

	$totals[$type]    = $count;
	$freecounts[$type] = 0;
    }

    # Get free totals by type.
    $query_result =
	DBQueryFatal("select n.type,count(*) from nodes as n ".
		     "left join node_types as nt on n.type=nt.type ".
		     "left join reserved as r on r.node_id=n.node_id ".
		     "where (role='testnode') and ".
		     "      (nt.class!='shark' and nt.class!='pcRemote' ".
		     "      and nt.class!='pcplabphys') ".
		     "      and r.pid is null ".
		     "group BY n.type");

    while ($row = mysql_fetch_array($query_result)) {
	$type  = $row[0];
	$count = $row[1];

	$freecounts[$type] = $count;
    }

    echo "<center>
          <b>Free Node Summary</b>
          <br>
          <table>
          <tr>
             <th>Type</th>
             <th align=center>Free<br>Nodes</th>
             <th align=center>Total<br>Nodes</th>
          </tr>\n";

    foreach($totals as $key => $value) {
	$freecount = $freecounts[$key];

	# Check perm entry.
	if (isset($perms[$key]) && !$perms[$key])
	    continue;
	
	echo "<tr>\n";
	if ($isadmin)
	    echo "<td><a href=editnodetype.php3?node_type=$key>\n";
	else
	    echo "<td><a href=shownodetype.php3?node_type=$key>\n";
	echo "           $key</a></td>
              <td align=center>$freecount</td>
              <td align=center>$value</td>
              </tr>\n";
    }
    if ($isadmin) {
	# Give admins the option to create a new type
	echo "<th colspan=3><a href=editnodetype.php3?new_type=1>Create a " .
		"new type</a></th>\n";
    }
    echo "</table>\n";
    PAGEFOOTER();
    exit();
}

#
# Suck out info for all the nodes.
# 
$query_result =
    DBQueryFatal("select n.node_id,n.phys_nodeid,n.type,ns.status, ".
		 "   n.def_boot_osid,r.pid,r.eid,nt.class,r.vname ".
		 "$additionalVariables ".
		 "from nodes as n ".
		 "left join node_types as nt on n.type=nt.type ".
		 "left join node_status as ns on n.node_id=ns.node_id ".
		 "left join reserved as r on n.node_id=r.node_id ".
		 "$additionalLeftJoin ".
		 "where $role $clause ".
		 "ORDER BY priority");

if (mysql_num_rows($query_result) == 0) {
    echo "<center>Oops, no nodes to show you!</center>";
    PAGEFOOTER();
}

#
# First count up free nodes as well as status counts.
#
$num_free = 0;
$num_up   = 0;
$num_pd   = 0;
$num_down = 0;
$num_unk  = 0;
$freetypes= array();

while ($row = mysql_fetch_array($query_result)) {
    $pid                = $row[pid];
    $status             = $row[status];
    $type               = $row[type];

    if (! isset($freetypes[$type])) {
	$freetypes[$type] = 0;
    }
    if (!$pid) {
	$num_free++;
	$freetypes[$type]++;
	continue;
    }
    switch ($status) {
    case "up":
	$num_up++;
	break;
    case "possibly down":
    case "unpingable":
	$num_pd++;
	break;
    case "down":
	$num_down++;
	break;
    default:
	$num_unk++;
	break;
    }
}
$num_total = ($num_free + $num_up + $num_down + $num_pd + $num_unk);
mysql_data_seek($query_result, 0);

if (! strcmp($showtype, "widearea")) {
    echo "<a href=tutorial/docwrapper.php3?docname=widearea.html>
             Widearea Usage Notes</a>\n";
}

echo "<br><center><b>
       View: $view\n";

if (! strcmp($showtype, "widearea")) {
    echo "<br>
          <a href=widearea_nodeinfo.php3>(Widearea Link Metrics)</a><br>
          <a href=plabmetrics.php3>(PlanetLab Node Metrics)</a>\n";
}

echo "</b></center><br>\n";

SUBPAGESTART();

echo "<table>
       <tr><td align=right>
           <img src='/autostatus-icons/greenball.gif' alt=up>
           <b>Up</b></td>
           <td align=left>$num_up</td>
       </tr>
       <tr><td align=right nowrap>
           <img src='/autostatus-icons/yellowball.gif' alt='possibly down'>
           <b>Possibly Down</b></td>
           <td align=left>$num_pd</td>
       </tr>
       <tr><td align=right>
           <img src='/autostatus-icons/blueball.gif' alt=unknown>
           <b>Unknown</b></td>
           <td align=left>$num_unk</td>
       </tr>
       <tr><td align=right>
           <img src='/autostatus-icons/redball.gif' alt=down>
           <b>Down</b></td>
           <td align=left>$num_down</td>
       </tr>
       <tr><td align=right>
           <img src='/autostatus-icons/whiteball.gif' alt=free>
           <b>Free</b></td>
           <td align=left>$num_free</td>
       </tr>
       <tr><td align=right><b>Total</b></td>
           <td align=left>$num_total</td>
       </tr>
       <tr><td colspan=2 nowrap align=center>
               <b>Free Subtotals</b></td></tr>\n";

foreach($freetypes as $key => $value) {
    echo "<tr>
           <td align=right><a href=shownodetype.php3?node_type=$key>
                           $key</a></td>
           <td align=left>$value</td>
          </tr>\n";
}
echo "</table>\n";
SUBMENUEND_2B();

echo "<table border=2 cellpadding=2 cellspacing=2>\n";

echo "<tr>
          <th align=center>ID</th>\n";

if ($showvnames) {
    echo "<th align=center>Name</th>\n";
}

echo "    <th align=center>Type (Class)</th>
          <th align=center>Up?</th>\n";

if ($isadmin) {
    echo "<th align=center>PID</th>
          <th align=center>EID</th>
          <th align=center>Default<br>OSID</th>\n";
}
elseif (strcmp($showtype, "widearea")) {
    # Widearea nodes are always "free"
    echo "<th align=center>Free?</th>\n";
}

if (!strcmp($showtype, "widearea")) {
    echo "<th align=center>Processor</th>
	  <th align=center>Connection</th>
	  <th align=center>Location</th>\n";
}
    
echo "</tr>\n";

while ($row = mysql_fetch_array($query_result)) {
    $node_id            = $row[node_id]; 
    $phys_nodeid        = $row[phys_nodeid]; 
    $type               = $row[type];
    $class              = $row["class"];
    $def_boot_osid      = $row[def_boot_osid];
    $pid                = $row[pid];
    $eid                = $row[eid];
    $vname              = $row[vname];
    $hostname           = $row[hostname];
    $status             = $row[status];

    if (!strcmp($showtype, "widearea")) {	
	$machine_type = $row[machine_type];
	$location = $row[location];
	$connect_type = $row[connect_type];
	$vname        = $row[hostname];
    } 

    echo "<tr>";

    # Admins get a link to expand the node.
    if ($isadmin) {
	echo "<td><A href='shownode.php3?node_id=$node_id'>$node_id</a> " .
	    (!strcmp($node_id, $phys_nodeid) ? "" :
	     "(<A href='shownode.php3?node_id=$phys_nodeid'>$phys_nodeid</a>)")
	    . "</td>\n";
    }
    else {
	echo "<td>$node_id " .
  	      (!strcmp($node_id, $phys_nodeid) ? "" : "($phys_nodeid)") .
	      "</td>\n";
    }

    if ($showvnames) {
	if ($vname)
	    echo "<td>$vname</td>\n";
	else
	    echo "<td>--</td>\n";
    }
    
    echo "   <td>$type ($class)</td>\n";

    if (!$pid)
	echo "<td align=center>
                  <img src='/autostatus-icons/whiteball.gif' alt=free></td>\n";
    elseif (!$status)
	echo "<td align=center>
                  <img src='/autostatus-icons/blueball.gif' alt=unk></td>\n";
    elseif ($status == "up")
	echo "<td align=center>
                  <img src='/autostatus-icons/greenball.gif' alt=up></td>\n";
    elseif ($status == "down")
	echo "<td align=center>
                  <img src='/autostatus-icons/redball.gif' alt=down></td>\n";
    else
	echo "<td align=center>
                  <img src='/autostatus-icons/yellowball.gif' alt=unk></td>\n";

    # Admins get pid/eid/vname, but mere users yes/no.
    if ($isadmin) {
	if ($pid) {
	    echo "<td>$pid</td>
                  <td>$eid</td>\n";
	}
	else {
	    echo "<td>--</td>
   	          <td>--</td>\n";
	}
	if ($def_boot_osid && TBOSInfo($def_boot_osid, $osname, $ospid))
	    echo "<td>$osname</td>\n";
	else
	    echo "<td>&nbsp</td>\n";
    }
    elseif (strcmp($showtype, "widearea")) {
	if ($pid)
	    echo "<td>--</td>\n";
	else
	    echo "<td>Yes</td>\n";
    }

    if (!strcmp($showtype, "widearea")) {	
	echo "<td>$machine_type</td>
	      <td>$connect_type</td>
	      <td><font size='-1'>$location</font></td>\n";
    }
    
    echo "</tr>\n";
}

echo "</table>\n";
SUBPAGEEND();

#
# Standard Testbed Footer
# 
PAGEFOOTER();
?>


