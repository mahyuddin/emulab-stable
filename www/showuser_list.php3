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
PAGEHEADER("User List");

#
#
# Only known and logged in users allowed.
#
$uid = GETLOGIN();
LOGGEDINORDIE($uid);

#
# Admin users can see all users, while normal users can only see
# users in their projects.
#
$isadmin = ISADMIN($uid);

if (! $isadmin) {
    USERERROR("You do not have permission to view the user list!", 1);
}

echo "<b>Show: <a href='showuser_list.php3?showtype=loggedin'>loggedin</a>,
               <a href='showuser_list.php3?showtype=widearea'>widearea</a>,
               <a href='showuser_list.php3?showtype=homeless'>homeless</a>,
               <a href='showuser_list.php3?showtype=active'>active</a>,
               <a href='showuser_list.php3?showtype=inactive'>inactive</a>,
               <a href='showuser_list.php3?showtype=all'>all</a>.
      </b><br><br>\n";

if (!isset($showtype)) {
    $showtype='loggedin';
}
if (!isset($sortby))
    $sortby = "uid";

if (! strcmp($showtype, "all")) {
    $where   = "";
    $clause  = "";
    $showtag = "";
}
elseif (! strcmp($showtype, "loggedin")) {
    $clause  = "left join login as l on u.uid=l.uid ";
    $where   = "where l.timeout>=unix_timestamp()";
    $showtag = "logged in";
}
elseif (! strcmp($showtype, "widearea")) {
    $clause  = "left join widearea_accounts as w on u.uid=w.uid ";
    $where   = "where w.node_id is not NULL";
    $showtag = "widearea";
}
elseif (! strcmp($showtype, "homeless")) {
    $clause  = "left join group_membership as m on u.uid=m.uid ";
    $clause .= "left join widearea_accounts as w on u.uid=w.uid ";
    $where   = "where (m.uid is null and w.node_id is NULL) ";
    $showtag = "homeless";
}
elseif (! strcmp($showtype, "inactive")) {
    $clause  = "";
    $where   = "where u.status!='active' ";
    $showtag = "inactive";
}
elseif (! strcmp($showtype, "active")) {
    $clause  = "";
    $where   = "where u.status='active' ";
    $showtag = "active";
}
else {
    $clause  = "";
    $where   = "";
    $showtag = "";
}

if (! strcmp($sortby, "name"))
    $order = "u.usr_name";
elseif (! strcmp($sortby, "uid"))
    $order = "u.uid";
elseif (! strcmp($sortby, "widle"))
    $order = "webidle DESC";
elseif (! strcmp($sortby, "uidle"))
    $order = "usersidle DESC";
else {
    $order = "u.uid";
}

$query_result =
    DBQueryFatal("SELECT u.*, ".
		 " IF(ll.time, ".
		 "    TO_DAYS(CURDATE()) - TO_DAYS(ll.time), ".
		 "    TO_DAYS(CURDATE()) - TO_DAYS(u.usr_created)) ".
		 "   as webidle, ".
		 " TO_DAYS(CURDATE()) - TO_DAYS(ull.date) as usersidle ".
		 "FROM users as u ".
		 "$clause ".
		 "left join userslastlogin as ull on u.uid=ull.uid ".
		 "left join lastlogin as ll on u.uid=ll.uid ".
		 "$where ".
		 "order by $order");

if (($count = mysql_num_rows($query_result)) == 0) {
    USERERROR("There are no users!", 1);
}

echo "<center>
       There are $count $showtag users.
      </center><br>\n";

#
# Grab the project lists and create a hash of lists, per user.
# One query instead of hundreds.
#
$projmemb_array  = array();
$projmemb_result =
   DBQueryFatal("select distinct uid,pid from group_membership ".
		"order by uid");

while ($row = mysql_fetch_array($projmemb_result)) {
    $uid   = $row[0];
    $pid   = $row[1];

    $projmemb_array[$uid][] = $pid;
}

echo "<table width=\"100%\" border=2 cellpadding=1 cellspacing=2
       align='center'>\n";

echo "<tr>
          <th>&nbsp</th>
          <th><a href='showuser_list.php3?showactive=$showactive&sortby=uid'>
                 UID</a></th>
          <th><a href='showuser_list.php3?showactive=$showactive&sortby=name'>
                 Name</a></th>
          <th>Projects</th>\n";

if (! strcmp($showtype, "inactive")) {
    echo "<th>Status</th>\n";
}

echo "    <th><a href='showuser_list.php3?showactive=$showactive&sortby=widle'>
                 Web<br>Idle</a></th>
          <th><a href='showuser_list.php3?showactive=$showactive&sortby=uidle'>
                 Users<br>Idle</a></th>\n";

echo "</tr>\n";

while ($row = mysql_fetch_array($query_result)) {
    $thisuid  = $row[uid];
    $name     = $row[usr_name];
    $status   = $row[status];
    $unix_uid = $row[unix_uid];
    $webidle  = $row[webidle];
    $usersidle= $row[usersidle];

    echo "<tr>\n";

    if (strcmp($status, "active") == 0) {
	echo "<td align=center><img alt=\"Y\" src=\"greenball.gif\"></td>\n";
    }
    else {
	echo "<td align=center><img alt=\"N\" src=\"redball.gif\"></td>\n";
    }

    echo "<td><A href='showuser.php3?target_uid=$thisuid'>$thisuid</A></td>
              <td>$name</td>\n";

    # List of projects.
    reset($projmemb_array);
    if (isset($projmemb_array[$thisuid])) {
	echo "<td> ";
	while (list ($idx, $pid) = each($projmemb_array[$thisuid])) {
	    echo "<A href='showproject.php3?pid=$pid'>$pid</A>";
	    if ($idx != (count($projmemb_array[$thisuid]) - 1))
		echo ", ";
	}
	echo "</td>\n";
    }
    else {
	    echo "<td>--</td>\n";
    }
    
    if (! strcmp($showtype, "inactive")) {
	echo "<td>$status</td>\n";
    }

    echo "<td>$webidle</td>\n";

    if (! $usersidle)
	echo "<td>&nbsp</td>\n";
    else {
	echo "<td>$usersidle</td>\n";
    }

    echo "</tr>\n";
}
echo "</table>\n";

#
# Standard Testbed Footer
# 
PAGEFOOTER();
?>
