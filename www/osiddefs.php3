<?php
#
# EMULAB-COPYRIGHT
# Copyright (c) 2000-2004 University of Utah and the Flux Group.
# All rights reserved.
#
# Stuff for OSIDs. All this stuff should come from the DB instead!
#

# List of allowed OS types for creating OSIDs. The value is a user-okay flag.
$osid_oslist			= array();
$osid_oslist["Linux"]		= 1;
$osid_oslist["FreeBSD"]		= 1;
$osid_oslist["NetBSD"]		= 1;
$osid_oslist["Oskit"]		= 0;
$osid_oslist["Other"]		= 1;

# List of allowed OS features. The value is a user-okay flag.
$osid_featurelist		= array();
$osid_featurelist["ping"]	= 1;
$osid_featurelist["ssh"]	= 1;
$osid_featurelist["ipod"]	= 1;
$osid_featurelist["isup"]	= 1;
$osid_featurelist["veths"]	= 0;
$osid_featurelist["mlinks"]	= 0;

# Default op modes. The value is a user-okay flag.
$osid_opmodes			= array();
$osid_opmodes["NORMALv2"]	= 0;
$osid_opmodes["NORMALv1"]	= 1;
$osid_opmodes["MINIMAL"]	= 1;
$osid_opmodes["NORMAL"]		= 1;

define("TBDB_DEFAULT_OSID_OPMODE",	"NORMALv2");

#
# Helper function to write out a menu.
#
function WRITEOSIDMENU($caption, $value, $osid_result, $previous)
{
    echo "<tr>
            <td>*$caption:</td>";
    echo "  <td><select name=\"$value\">
                <option value=X>Please Select </option>\n";

    mysql_data_seek($osid_result, 0);

    while ($row = mysql_fetch_array($osid_result)) {
	$osid   = $row[osid];
	$osname = $row[osname];
	$pid    = $row[pid];
	$selected = "";

	if (strcmp($previous, "$osid") == 0)
	    $selected = "selected";

	echo "<option $selected value='$osid'>$pid - $osname</option>\n";
    }
    $selected = "";
    if (strcmp($previous, "none") == 0)
	$selected = "selected";
	
    echo "         <option $selected value=none>No OS</option>\n";
    echo "       </select>";
    echo "    </td>
          </tr>\n";
}

function WRITEIMAGEIDMENU($caption, $value, $imageid_result, $previous)
{
    echo "<tr>
            <td>*$caption:</td>";
    echo "  <td><select name=\"$value\">
                <option value=X>Please Select </option>\n";

    mysql_data_seek($imageid_result, 0);

    while ($row = mysql_fetch_array($imageid_result)) {
	$imageid   = $row[imageid];
	$imagename = $row[imagename];
	$pid       = $row[pid];
	$selected  = "";

	if (strcmp($previous, "$imageid") == 0)
	    $selected = "selected";

	echo "<option $selected value='$imageid'>$pid - $imagename</option>\n";
    }
    $selected = "";
    if (strcmp($previous, "none") == 0)
	$selected = "selected";
	
    echo "         <option $selected value=none>No ImageID</option>\n";
    echo "       </select>";
    echo "    </td>
          </tr>\n";
}

