<?php
#
# EMULAB-COPYRIGHT
# Copyright (c) 2004, 2005 University of Utah and the Flux Group.
# All rights reserved.
#
chdir("..");
require("defs.php3");

# Page arguments.
$printable = $_GET['printable'];

# Pedantic page argument checking. Good practice!
if (isset($printable) && !($printable == "1" || $printable == "0")) {
    PAGEARGERROR();
}
if (!isset($printable))
    $printable = 0;

#
# Standard Testbed Header
#
if (!$printable) {
    PAGEHEADER("Emulab Tutorial - Mobile Wireless Networking");
}

if (!$printable) {
    echo "<b><a href=$REQUEST_URI?printable=1>
             Printable version of this document</a></b><br>\n";
}

function NLCH1($value)
{
	echo "<td align=\"right\" valign=\"top\" class=\"stealth\">
                <b>$value</b>
              </td>";
}

function NLCH2($value)
{
	echo "<td align=\"right\" valign=\"top\" class=\"stealth\">
                <font size=\"-1\"><i>$value</i></font>
              </td>";
}

function NLCBODYBEGIN()
{
	echo "<td align=\"left\" valign=\"top\" class=\"stealth\">";
}

function NLCBODYEND()
{
	echo "</td>";
}

function NLCFIGBEGIN()
{
	echo "<td align=\"center\" valign=\"top\" class=\"stealth\">";
}

function NLCFIGEND()
{
	echo "</td>";
}

function NLCFIG($value, $caption)
{
	echo "<td align=\"center\" valign=\"top\" class=\"stealth\">
                $value
                <font size=\"-2\">$caption</font>
              </td>";
}

function NLCLINKFIG($link, $value, $caption)
{
	echo "<td align=\"center\" valign=\"top\" class=\"stealth\">
                <a href=\"$link\" border=\"0\">
                  $value<br>
                  <font size=\"-2\">[$caption]</font></a>
              </td>";
}

function NLCEMPTY()
{
	echo "<td class=\"stealth\"></td>";
}

#
# Drop into html mode
#
?>
<center>
    <h2>Emulab Tutorial - Mobile Wireless Networking</h2>

    <i><font size="-1">

    Note: This part of the testbed is in the prototype stage, so the hardware
    and software may behave in unexpected ways.  
   

    </font></i>
</center>

<br>

<table cellspacing=5 cellpadding=5 border=0 class="stealth" bgcolor="#ffffff">

<tr><td colspan="3" class="stealth"><hr size=1></td></tr>


<tr>

<?php NLCH1("Preface") ?>

<?php NLCBODYBEGIN() ?>

We have deployed and opened to public external use a small version of
what will grow into a large mobile robotic wireless testbed.  The
small version (4 Motes and 4 Stargates on 4 robots, all remotely
controllable) is in an open area within our offices; the big one will
be elsewhere.

<?php NLCBODYEND() ?>

<?php NLCEMPTY() ?>

</tr>

<tr>

<?php NLCH1("Introduction") ?>

<?php NLCBODYBEGIN() ?>
<!-- Center -->

In addition to <a href="docwrapper.php3?docname=wireless.html">fixed wireless
nodes</a> (currently predominantly 802.11), Emulab also features wireless nodes attached
to robots that can move
around a small area.  These robots consist of a small body (shown on the right)
with an <a href="http://www.xbow.com/Products/XScale.htm">Intel Stargate</a>
that hosts a mote with a wireless network interface.  The goal of this "mobile
wireless testbed" is to give users an opportunity to conduct experiments with
wireless nodes that are truly mobile
<!-- in configurable physical locations and while in motion. -->
For
example, mobile nodes could be used to realistically test and evaluate an
ad-hoc routing algorithm in a fairly repeatable manner.  This document is
intended as a tutorial for those interested in making use of this testbed;
there is also a short <a href="<?php echo
$TBBASE?>/doc/docwrapper.php3?docname=mobilewireless.html">reference manual</a>
available that gives a few details about the workings of the system.

<br>
<br>
<?php NLCBODYEND() ?>

<?php NLCLINKFIG("http://www.acroname.com/garcia/garcia.html",
		 "<img src=\"garcia-thumb.jpg\" border=1
                       alt=\"Acroname Garcia\">",
		 "Acroname&nbsp;Garcia") ?>

</tr>

<tr>

<?php NLCH2("Features") ?>

<?php NLCBODYBEGIN() ?>

The current features of the mobile wireless testbed are:

<ul>
<li>Four <a href="http://www.acroname.com">Acroname Garcia</a> robots
<li><a href="http://www.xbow.com/Products/XScale.htm">Intel Stargate</a> single
board computers for each robot.
<li><a href="http://www.xbow.com/Products/productsdetails.aspx?sid=72">900MHz Mica2 
motes</a> attached to each Stargate.
<!-- <li>Some non-mobile Mica2 motes nearby. -->
<li>Roaming an area about 8 x 3.5 meters with a sheetrock-covered steel pillar in the middle.
<li>Four overhead cameras for vision-based position tracking of the robots.
<li>Two <a href="<?php echo $TBBASE ?>/webcam.php3">webcams</a> for viewing the
robots in their habitat.
<li>An <a href="<?php echo $TBBASE ?>/robotmap.php3">abstract map</a> of the
current locations of the robots.
<li>Open for public use weekdays 8am-6pm MST, with operations support.
</ul>

<?php NLCBODYEND() ?>

<?php NLCEMPTY() ?>

</tr>

<tr>

<?php NLCH2("Limitations") ?>

<?php NLCBODYBEGIN() ?>

Due to the "brand-new" nature of this part of Emulab, there are some
limitations you should be aware of:

<ul>
<li>Before you can use the mobile testbed, your project must be granted the
appropriate privileges.  You can request access by sending mail to <a
href="mailto:testbed-ops@flux.utah.edu">Testbed Operations</a>.
<li>The mobile testbed is currently open on non-holiday weekdays between
8am and 6pm mountain time, so we have staff available to assist with problems.
<li>There is no space sharing; only one mobile experiment can be swapped-in at
a time.
<li>Batteries must be replaced manually by the operator when levels are low.
</ul>

We expect to overcome these limitations over time; however, we are also eager to
introduce external users to the mobile testbed early on so we can integrate
their feedback.

<?php NLCBODYEND() ?>

<?php NLCEMPTY() ?>

</tr>

<tr><td colspan="3" class="stealth"><hr size=1></td></tr>

<tr>

<?php NLCH1("Mobile Experiments") ?>

<?php NLCBODYBEGIN() ?>

Creating a mobile wireless experiment is very similar to creating a regular
Emulab experiment: you construct an NS file, swap in the experiment, and then
you can log into the nodes to run your programs.  There are, of course, some
extra commands and settings that pertain to the physical manifestations of the
robots.  This tutorial will take you through the process of: creating a mobile
experiment, moving the robots to various destinations, creating random motion
scenarios, and "attaching" transmitter and receiver motes to the robots in your
experiment.

<?php NLCBODYEND() ?>

<?php NLCFIGBEGIN() ?>

<font size="-2">Sample Movie</font>
<img src="robot_anim.gif" border="1" alt="Robot Movie">
<a href="robot_divx.avi"><font size="-2">[DiVX (1.2M)]</font></a><br>
<a href="robot.mpg"><font size="-2">[MPG (5.3M)]</font></a>

<?php NLCFIGEND() ?>

</tr>

<tr>

<?php NLCH2("A First Experiment") ?>

<?php NLCBODYBEGIN() ?>

Lets start with a simple NS script that will allocate a single robot located in
our building:

<blockquote style="border-style:solid; border-color:#bbbbbb; border-width: thin">
<pre>set ns [new Simulator]
source tb_compat.tcl

set topo [new Topography]
$topo load_area MEB-ROBOTS

$ns node-config -topography $topo

set node(0) [$ns node]

$node(0) set X_ 3.01
$node(0) set Y_ 2.49

$ns run</pre>
</blockquote>
<center>
<font size="-2">Figure 1: Example NS file with mobile nodes.</font>
</center>
<br>

Some parts of that example should be familiar to regular experimenters, so we
will focus mainly on the new bits of code.  First, we specified the physical
area where the robots will be roaming by creating a "topography" object and
loading it with the dimensions of that area:

<blockquote>
<pre><i>Line 4:</i>  set topo [new Topography]
<i>Line 5:</i>  $topo load_area MEB-ROBOTS</pre>
</blockquote>

In this case, the "MEB-ROBOTS" area is the name given to part of our office
space in the Merrill Engineering Building.  Next, we change the default node
configuration so any subsequent calls to "<code>[$ns node]</code>" will
automatically attach the node to the topography we just created:

<blockquote>
<pre><i>Line 7:</i>  $ns node-config -topography $topo</pre>
</blockquote>

Finally, after creating the robot, we need to set the initial position in the
area:

<blockquote>
<pre><i>Line 11:</i> $node set X_ 3.01
<i>Line 12:</i> $node set Y_ 2.49</pre>
</blockquote>

The values specified above are measured in meters and based on the map located
<a href="<?php echo $TBBASE ?>/robotmap.php3">here</a>, where the origin is in
the upper left hand corner, with positive X going right and positive Y going
down.  You can also click on the map to get a specific set of coordinates.
Note that any coordinates you specify must not fall inside an obstacle, or they will
be rejected by the system.  A Java applet that updates in real time is linked
from

<p>
With this NS file you can now create your first mobile experiment.  Actually
creating the experiment is the same as any other, except you might want to
check the "Do Not Swapin" checkbox so that the creation does not fail if
someone else is using the mobile testbed at the time.  Once the area is free
for use, you can swap-in your experiment and begin to work.

<?php NLCBODYEND() ?>

<?php NLCEMPTY() ?>

</tr>

<tr>

<?php NLCH2("Adding Motion") ?>

<?php NLCBODYBEGIN() ?>

Now that you have a node allocated, let's make it mobile.  During swap-in,
Emulab will start moving the node to its initial position.  You can watch its
progress by using the "Robot Map" menu item on the experiment page and checking
out the <a href="<?php echo $TBBASE ?>/webcam.php3">webcams</a> or
the <a href="<?php echo $TBBASE ?>/robotrack/robotrack.php3">applet version of the map</a>
that updates in real time.

<p>
<table width="100%" cellpadding=0 cellspacing=0 border=0 class="stealth">
<tr>
<?php NLCLINKFIG("robotmap-ss.gif", 
		 "<img src=\"robotmap-ss-thumb.gif\" border=1
		 alt=\"Robot Map Screenshot\">",
		 "Sample Robot Map Screenshot") ?>
<?php NLCLINKFIG("webcam-ss.gif", 
		 "<img src=\"webcam-ss-thumb.gif\" border=1
		 alt=\"Webcam Screenshot\">",
		 "Sample Webcam Screenshot") ?>
</tr>
</table>

<p>
Take a few moments to familiarize yourself with those pages since we'll be
making use of them during the rest of the tutorial.  One important item to note
is the "Elapsed event time" value, which displays how much time has elapsed
since the robots have reached their initial positions.  The elapsed time is
also connected to when <code>"$ns at"</code> events in the NS file are run.  In
this case, there were no events in the NS file, so we'll be moving the robot by
sending dynamic SETDEST events, much like sending START and STOP events to <a
href="docwrapper.php3?docname=advanced.html">traffic generators</a> and <a
href="docwrapper.php3?docname=advanced.html#ProgramObjects">program
objects</a>.

<!-- XXX We need to give them a clue on which way the webcam is pointing in -->
<!-- relation to the robot map. -->

<p>
Once the robot has reached its initial position, lets move it up a meter.  To
do this, you will need to log in to ops.emulab.net and run:

<blockquote style="border-style:solid; border-color:#bbbbbb; border-width: thin">
<pre>1 ops:~> /usr/testbed/bin/tevc -e <b>proj</b>/<b>exp</b> \
             now node-0 SETDEST X=3.0 Y=1.5</pre>
</blockquote>
<blockquote>
<center>
<font size="-2">Figure 2: Command to send an event that will move the robot to
the coordinates (3.0, 1.5).  Don't forget to change <b>proj</b>/<b>exp</b> to
match your project and experiment IDs.</font>
</center>
</blockquote>

<!-- mention that one setdest will override the previous. --> 

Then, check back with the map and webcams to see the results of your handiwork.
Try moving it around a few more times to get a feel for how things work and
where the robot can go.  Note that the robot should automatically navigate
around obstacles in the area, like the pole in the middle, so you do not have
to plot your own course around them.

<p>
In addition to driving the robot with dynamic events, you can specify a static
set of events in the NS file.  For example, you can issue the same move as
above at T +5 seconds by adding:

<blockquote style="border-style:solid; border-color:#bbbbbb; border-width: thin">
<pre>$ns at 5.0 "$node(0) setdest 3.01 1.5 0.1"</pre>
</blockquote>
<center>
<font size="-2">Figure 3: NS syntax that moves the robot to the same
destination as in Figure 2.</font>
</center>
<br>

Note that "setdest" takes a third argument, the speed, in addition to the X and
Y coordinates.  The robot's speed is currently fixed at 0.1 meters per second.

<?php NLCBODYEND() ?>

<?php NLCEMPTY() ?>

</tr>

<tr>

<?php NLCH2("Random Motion") ?>

<?php NLCBODYBEGIN() ?>

Generating destination points for nodes can become quite a tedious task, so we
provide a modified version of the NS-2 "setdest" tool that will produce a valid
set of destination points for a given area.  The tool, called "tbsetdest", is
installed on ops and takes the following arguments:

<blockquote>
<ul>
<li><b>-n</b> <i>nodes</i> - The total number of nodes to generate motion for.
The format for the node variables in the generated code is,
"<code>$node(N)</code>", so write your NS file accordingly.
<li><b>-t</b> <i>secs</i> - The simulation time, in seconds.
<li><b>-a</b> <i>area</i> - The name of the area where the robots will be
roaming around.  Currently, MEB-ROBOTS is the only area available.
</ul>
</blockquote>

Now, taking your existing NS file, we'll add another node to make things more
interesting:

<blockquote style="border-style:solid; border-color:#bbbbbb; border-width: thin">
<pre><i>...</i>
$ns node-config -topography $topo

set node(0) [$ns node]
<b>set node(1) [$ns node]</b></pre>
</blockquote>
<center>
<font size="-2">Figure 4: Excerpt of the original NS file with an additional
node.
</font>
</center>
<br>

Then, use "tbsetdest" to produce some random motion for both robots:

<blockquote>
<pre>2 ops:~> /usr/testbed/bin/tbsetdest -n 2 -t 60 -a MEB-ROBOTS</pre>
</blockquote>

Here is some sample output from the tool:

<blockquote style="border-style:solid; border-color:#bbbbbb; border-width: thin">
<pre>$node(0) set X_ 3.01
$node(0) set Y_ 2.49
$node(1) set X_ 1.22
$node(1) set Y_ 3.61
set rtl [$ns event-timeline]
#
# nodes: 2, pause: 0.50, max x: 5.90, max y: 4.00
#
$rtl at 0.50 "$node(0) setdest 0.92 3.28 0.10"
$rtl at 0.50 "$node(1) setdest 0.61 3.02 0.10"
$rtl at 9.50 "$node(1) setdest 0.88 2.09 0.10"
$rtl at 19.64 "$node(1) setdest 2.80 2.07 0.10"
$rtl at 23.37 "$node(0) setdest 5.62 2.79 0.10"
$rtl at 39.43 "$node(1) setdest 4.98 1.65 0.10"
#
# Destination Unreachables: 0
#</pre>
</blockquote>
<center>
<font size="-2">Figure 5: Sample "tbsetdest" output.</font>
</center>
<br>

You can then add the second node and motion events by clicking on the "Modify
Experiment" menu item on the experiment web page and:

<ol>
<li>Copying and pasting the "tbsetdest" output into the NS file before the
"<code>$ns run</code>" command; and
<li>Starting the modify.
</ol>

While the modify is working, lets take a closer look at the output of
"tbsetdest".  You may have noticed the following new syntax:

<blockquote>
<pre><i>Line 5:</i>  set rtl [$ns event-timeline]
<i>Lines 9+:</i> $rtl at ...</pre>
</blockquote>

These commands create a new "timeline" object and then add events to it, much
like adding events using "<code>$ns at</code>".  The difference is that the
events attached to a timeline object can be requeued by sending a START event
to the timeline, in contrast to the "<code>$ns at</code>" events which are only
queued when the event system starts up.  This feature can be useful for testing
your experiment by just (re)queueing subsets of events.

<p>
Once the modify completes, wait for the robots to reach their initial position
and then start the robots on their way by running the following on ops:

<blockquote style="border-style:solid; border-color:#bbbbbb; border-width: thin">
<pre>3 ops:~> /usr/testbed/bin/tevc -e <b>proj</b>/<b>exp</b> now rtl START</pre>
</blockquote>
<blockquote>
<center>
<font size="-2">Figure 6: Command to start the "rtl" timeline.  Again, don't
forget to change <b>proj</b>/<b>exp</b> to match your project and experiment
IDs.</font>
</center>
</blockquote>

<?php NLCBODYEND() ?>

<?php NLCEMPTY() ?>

</tr>


<tr><td colspan="3" class="stealth"><hr size=1></td></tr>


<tr>

<?php NLCH1("Wireless Traffic") ?>

<?php NLCBODYBEGIN() ?>

Now that you are getting the hang of the mobility part of this testbed, we can
move on to working with wireless network traffic.  As stated earlier, each of
the robots carries a Mica2 mote (pictured on the right), which is a popular
device used in wireless sensor networks.  We'll be using the motes on the
mobile nodes you already have allocated and loading them with <a
href="http://www.tinyos.net">TinyOS</a> demo kernels, one that will be sending
traffic and the other receiving.

<?php NLCBODYEND() ?>

<?php NLCLINKFIG("http://www.tinyos.net/scoop/special/hardware",
		 "<img src=\"mica2-thumb.jpg\" border=1
                       alt=\"Mica2 Mote\">",
		 "Mica2&nbsp;Mote") ?>

</tr>

<tr>

<?php NLCH2("Adding Motes") ?>

<?php NLCBODYBEGIN() ?>

Adding a couple of motes to your existing experiment can be done by doing a
modify and adding the following NS code:

<blockquote style="border-style:solid; border-color:#bbbbbb; border-width: thin">
<pre>## BEGIN mote nodes
$ns node-config -topography ""

set receiver [$ns node]
tb-set-hardware $receiver mica2
tb-set-node-os $receiver TinyOS-RfmLed
tb-fix-node $receiver $node(0)

set transmitter [$ns node]
tb-set-hardware $transmitter mica2
tb-set-node-os $transmitter TinyOS-CntRfm
tb-fix-node $transmitter $node(1)
## END mote nodes</pre>
</blockquote>
<center>
<font size="-2">Figure 7: NS syntax used to "attach" motes to a robot.</font>
</center>
<br>

This code creates two mote nodes and "attaches" each of them to one of the
mobile nodes.  The OSs to be loaded on the mote nodes are the receiver,
TinyOS-RfmLed, and the transmitter, TinyOS-CntRfm.  These are standard
TinyOS kernels supplied by Emulab; uploading your own is covered below.
The receiver kernel will
listen for packets containing a number from the transmitter and display the
number, in binary, on the mote's builtin LEDs.  The transmitter kernel will
then send packets every second containing the value of a counter that goes from
one to eight.  So, if the mote's radios are well within range of each other,
the receiver should pick up the packets and display the number on the LEDs.  Of
course, since you're not physically around to see that, you can click on the
"Show Blinky Lights" menu item on the experiment web page to bring up a webpage
with an applet that provides a near real-time view of the lights.

<p>
After the modify completes, try moving the nodes close to one another and far
away, to see the lights updating, or not.  You should also try running the
nodes through the random motion created earlier and watching for the same
effect on the lights.

<p>
Uploading your own code to run on the motes is easy. Just build your TinyOS app
normally (ie. '<code>make mica2</code>').  Then, upload the binary that gets
placed in <code>build/mica2/main.srec</code> to our
<a href="<?php echo $TBBASE ?>/newimageid_ez.php3?nodetype=mote">mote image
    creation page</a>.  This page will ask you for a 'descriptor'.  This
descriptor can then be used in <code>tb-set-node-os</code> lines in your
NS files, and your app will be automatically loaded on the appropriate mote(s).

<p>
At this time, we don't have a TinyOS installation on the Emulab servers, so
you'll need to have a TinyOS installation to build from on your desktop
machine, or some other machine you control.  We hope to provide a way for you
build TinyOS apps on Emulab in the near future.  Also, at the current time, all
of our motes have radios in the 900MHz band, so see the TinyOS
<a href="http://www.tinyos.net/tinyos-1.x/doc/mica2radio/CC1000.html">CC1000
radio document</a> to make sure you're tuning the radios to the right band.

<p>
When you inevitably make changes to your code, you can simply place the new
kernel in the path that was automatically constructed for you by the image
creation page; the next time you use that OS in an NS file, the new version
will be loaded. If you'd like to load your node code onto your motes without
starting a new experiment, you have two options:
<ul>
  <li> <code>os_load</code> allows you to load an kernel that has already been
     defined as an image, as above. You give it the image descriptor with its
     <code>-i</code> argument, and you can either give the physical names of all
     motes you want to reload, or a <code>-e pid,eid</code> argument to reload
     all nodes in the given experiment.
  <li> <code>tbuisp</code> allows you to load a file directly onto your motes
     without having to register it as an image. This can be a quick way to do
     development/debugging. Just pass it the operation <code>upload</code>, the
     path to the file you wish to load, and the physical names of your motes.
</ul>
Both of these are commands in /usr/testbed/bin on ops.emulab.net.   They are
also available through our
<a href="<?php echo $TBBASE ?>/xmlrpcapi.php3">XML-RPC interface</a>, so you
can run them from your desktop machine to save time - the file given as an
argument to tbuisp is sent with the XML-RPC, so you don't need to copy it onto
our servers.

<?php NLCBODYEND() ?>

<?php NLCEMPTY() ?>

</tr>

<tr><td colspan="3" class="stealth"><hr size=1></td></tr>


</table>

<?php
#
# Standard Testbed Footer
# 
if (!$printable) {
    PAGEFOOTER();
}
?>
