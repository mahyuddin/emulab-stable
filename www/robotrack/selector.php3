<?php
#
# EMULAB-COPYRIGHT
# Copyright (c) 2000-2005 University of Utah and the Flux Group.
# All rights reserved.
#
chdir("..");
include("defs.php3");

$uid = GETLOGIN();
LOGGEDINORDIE($uid);

PAGEHEADER("Node Selector Applet");

#
# Verify page arguments. Allow user to optionally specify building/floor.
#
if (isset($building) && $building != "") {
    # Sanitize for the shell.
    if (!preg_match("/^[-\w]+$/", $building)) {
	PAGEARGERROR("Invalid building argument.");
    }
    # Optional floor argument. Sanitize for the shell.
    if (isset($floor) && $floor != "") {
	if (!preg_match("/^[-\w]+$/", $floor)) {
	    PAGEARGERROR("Invalid floor argument.");
	}
    }
    else
	unset($floor);
}
else {
    $building = "MEB-ROBOTS";
    $floor    = 4;
}

if (isset($pid) && $pid != "" && isset($eid) && $eid != "") {
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
}
else {
    unset($pid);
    unset($eid);
}

#
# Grab map info. Might be more then a single floor of course. 
#
if (isset($floor)) {
    $query_result =
	DBQueryFatal("select floor,pixels_per_meter from floorimages ".
		     "where building='$building' and scale=1 and ".
		     "floor='$floor'");
}
else {
    $query_result =
	DBQueryFatal("select distinct fl.floor,fl.pixels_per_meter ".
		     "   from location_info as loc ".
		     "left join floorimages as fl on ".
		     "  loc.building=fl.building and loc.floor=fl.floor ".
		     "where fl.building='$building' and fl.scale=1 ".
		     "order by floor");
}

if (! mysql_num_rows($query_result)) {
    USERERROR("No such building/floor", 1);
}

#
# Draw the legend and some explanatory text.
#
echo "<table cellspacing=5 cellpadding=5 border=0 class=\"stealth\">
      <tr>
       <td align=\"left\" valign=\"top\" class=\"stealth\">
         <table>
           <tr><th colspan=2>Legend</th></tr>
           <tr>
             <td><img src='/autostatus-icons/redball.gif' alt=allocated></td>
             <td nowrap=1>Unavailable Node</td>
           </tr>
           <tr>
             <td><img src='/autostatus-icons/greenball.gif'
                     alt=unassigned></td>
             <td nowrap=1>Unassigned Node</td>
           </tr>
           <tr>
             <td><img src='/autostatus-icons/blueball.gif' alt=assigned></td>
             <td nowrap=1>Assigned Node</td>
           </tr>
           <tr>
             <td><img src='/autostatus-icons/yellowball.gif' alt=selected></td>
             <td nowrap=1>Selected Node</td>
           </tr>
         </table>
       </td>
       <td class=stealth>This applet allows you to select physical nodes
                         for your experiment. See below for instructions.
                         
        </td>
      </tr>
      </table><hr>\n";

$auth       = $HTTP_COOKIE_VARS[$TBAUTHCOOKIE];
$floorcount = mysql_num_rows($query_result);
$ppm        = 1;
$index      = 0;

echo "<applet name='selector' code='NodeSelect.class'
              archive='NodeSelect.jar'
              width='1025' height='700'
              alt='You need java to run this applet'>
            <param name='uid' value='$uid'>
            <param name='auth' value='$auth'>
            <param name='building' value='$building'>\n";
echo "      <param name='floorcount' value='$floorcount'>";
while (($row = mysql_fetch_array($query_result))) {
    $floor = $row['floor'];
    $ppm   = $row['pixels_per_meter'];
    
    echo "  <param name='floor_${index}' value='$floor'>\n";
    $index++;
}
echo "      <param name='ppm' value='$ppm'>";
if (isset($pid)) {
    echo "  <param name='pid' value='$pid'>
            <param name='eid' value='$eid'>\n";
}
echo "</applet>\n";


echo "<br>
     <blockquote>
     <center>
     <h3>Using the Node Selector Applet</h3>
     </center>
     <ul>
     <li> Nodes that are currently available for use are in the upper
          list box.
     <li> Nodes that have been selected for use (assigned) are in the
          lower list box.
     <li> Highlight nodes by selecting them in list boxes or clicking on them
          in the maps.
          Shift-Click does the usual thing; adds to an existing selection.
     <li> Right click over a node will bring up a node context menu.
     <li> Right click anyplace else brings up the root context menu.
     <li> Move highlighted nodes between the upper and lower lists by choosing
          the appropriate option in either context menu.
     <li> Once you have your nodes assigned (the lower list box), use the
          'Create NS File' to menu option to popup an NS fragment that you
          can plug into an existing experiment.
     </ul>
     Notes:<br>
     <ul>
       <li> Middle click repositions the map so that the point under
            the mouse moves to the center.
       <li> Left click and drag in the map scrolls the map around.
       <li> Zoom in and out using the options on the Root Context Menu.
       <li> Return the map to the most recent centering position with the
            <em>Recenter</em> option.
       <li> Reset the zoom and center to initial startup conditions with
            the <em>Reset</em> option.
       <li> The 'rulers' are in 1 meter increments and are intended to provide
            scale information; they are not relative to a specific origin. 
     </ul>
     </blockquote>\n";

PAGEFOOTER();
?>
