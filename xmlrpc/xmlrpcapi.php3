<?php
#
# EMULAB-COPYRIGHT
# Copyright (c) 2004 University of Utah and the Flux Group.
# All rights reserved.
#
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
    PAGEHEADER("XMLRPC Interface to Emulab");
}

if (!$printable) {
    echo "<b><a href=$REQUEST_URI?printable=1>
             Printable version of this document</a></b><br>\n";
}

#
# Drop into html mode
#
?>
<p>
This page describes the <a href="http://www.xmlrpc.com">XMLRPC</a> interface
to Emulab. Currently, the
interface mainly supports experiment creation, modification, swapping,
and termination. We also provide interfaces to several other common
operations on nodes end experiments such as rebooting, reloading, link
delay configuration, etc. This interface is a work in progress; it
will improve and grow over time. If there is something missing you
need, please send us email.
</p>

<p>
The Emulab XMLRPC server uses SSH as its transport. Yes, this is a little
different then other RPC servers, but since all registered Emulab
users already have accounts on Emulab and are required to use SSH to
log in (and thus have provided us with their public keys), we decided
this was any easy way to handle authentication - much
easier on users then giving out SSL certificates that would need
to be kept track of. At some future time we may provide SSL or HTTPS
based servers, but for now rejoice in the fact that you do not need to
keep yet another certificate around!
</p>

<p>
The API is described in detail below. A demonstration client written in
Python is also available that you can use on your desktop to invoke
commands from the shell. For example:

    <code><pre>
    $ sshxmlrpc_client.py startexp batch=false wait=true proj="myproj" exp="myexp" nsfilestr="`cat ~/nsfile.ns`"</code></pre>

which says to create an experiment called "myexp" in the "myproj" project,
swap it in immediately, wait for the exit status (instead of running
asynchronously), passing inline the contents of <tt>nsfile.ns</tt> in your
home directory on your desktop.  By default, the client will contact the RPC
server at <tt><?php echo $BOSSNODE ?></tt>, but you can override that by
using the <tt>-s hostname</tt> option.. If your login ID on the local
machine is different then your login ID on Emulab, you can use the <tt>-l
login</tt> option. For example:

    <code><pre>
    $ sshxmlrpc_client.py -s boss.emulab.net -l rellots startexp ...</code></pre>

which would invoke the RPC server on <tt>boss.emulab.net</tt>, using the
login ID <tt>rellots</tt> (for the purposes of SSH authentication).  You
will be prompted for your SSH passphrase, unless you are running an SSH
agent and the key you have uploaded to Emulab has been added to your local
agent.
</p>

<p>
The <a href="downloads/xmlrpc/"><tt>sshxmlrpc_client</tt></a>
python program is a simple demonstration of how to use Emulab's RPC
server. If you do not provide a method and arguments on the command
line, it will enter a command loop where you can type in commands (method
and arguments) and wait for responses from the server. It converts your
command lines into RPCs to the server, and prints out the results that the
server sends back (exiting with whatever status code the server
returned). You can use this client program as is, or you can write your own
client program in whatever language you like, as long as you speak to the
server over an SSH connection. The API for the server is broken into
several different modules that export a number of methods, each of which is
described below. The python library we use to speak XMLRPC over an SSH
connection takes paths of the form:

    <code><pre>
    ssh://user@hostname/XMLRPC/module</code></pre>

where each <em>module</em> exports some methods. Each method is of the
form (in Python speak):

    <code><pre>
    def startexp(version, arguments):
        return EmulabResponse(RESPONSE_SUCCESS, value=0, output="Congratulations")</code></pre>

The arguments to each method:
<ul>
<li><tt>version</tt>: a numeric argument that the server uses to
determine if the client is really capable of speaking to the server.

<li><tt>arguments</tt>: a <em>hash table</em> of argument/value pairs,
which in Python is a <tt>Dictionary</tt>. In Perl or PHP this would be a
hashed array. Any client that supports such a datatype will be able to use
this interface directly. For example, to swap out an experiment a client
might:

    <code><pre>
    args = {};
    args["proj"] = "myproj"
    args["exp"] = "myexp"
    args["direction"]  = "out"
    response = server.swapexp(CURRENTVERSION, args)</code></pre>
</ul>

The client specifies the <tt>proj</tt> and <tt>exp</tt> of the experiment
he/she wants to swap, as well as the actual swap operation, in this case
<tt>out</tt>. The response from the server is another hashed array (Python
Dictionary) of the form:

<blockquote>
    <ul>
     <li><tt>code</tt>: An integer code as defined in
     <a href="downloads/xmlrpc/"><tt>emulabclient.py</tt></a>.
     <li><tt>value</tt>: A return value. May be any valid data type that
     can be transfered in XML. 
     <li><tt>output</tt>: A string (with embedded newlines) to print out.
     This is useful for debugging and for guiding users through the perils
     of XMLRPC programming. 
    </ul>
</blockquote>

Unless specifically stated, the return value of most commands is a
simple integer reflecting an exit code from the server, and some
output to help you determine what went wrong. Otherwise, the
return value is documented in each method description. 

<p>
Finally, a quick note about the types accepted and returned by methods.  Most
methods will accept a real XML-RPC type and try to coerce a string into that
type.  For example, in python, passing <code>True</code> is equivalent to
passing the string, "true".  When returning data, the methods will prefer to
return typed values, rather than formatted strings.

<ul>
<li><b>/XMLRPC/emulab</b>
<p>
The <tt>emulab</tt> module provides general information about this Emulab
installation.

  <ul>
  <li><tt><b>news</b></tt>: Get news item headers.  The optional
  arguments are:<br><br>

  <table cellpadding=2>
    <tr>
      <th>Name</th><th>Type</th><th>Default</th><th>Description</th>
    </tr>
    <tr></tr>
    <tr>
      <td><tt>starting</tt></td>
      <td>date</td>
      <td>-Inf.</td>
      <td>The date to start searching for news items (e.g. "2003-07-23
      10:13:00").</td>
    </tr>
    <tr>
      <td><tt>ending</tt></td>
      <td>date</td>
      <td>+Inf.</td>
      <td>The date to stop searching for news items.</td>
    </tr>
  </table>

  <br>The return value is a list of hash tables with the following
  elements:<br><br>

  <table cellpadding=2>
    <tr>
      <th>Name</th><th>Type</th><th>Description</th>
    </tr>
    <tr>
      <td><tt>subject</tt></td>
      <td>string</td>
      <td>The item's subject.</td>
    </tr>
    <tr>
      <td><tt>author</tt></td>
      <td>string</td>
      <td>The item's author.</td>
    </tr>
    <tr>
      <td><tt>date</tt></td>
      <td>date</td>
      <td>The date the item was posted.</td>
    </tr>
    <tr>
      <td><tt>msgid</tt></td>
      <td>integer</td>
      <td>The item's unique identifier.  This value should be used as the
      anchor when redirecting to the web site
      (e.g. http://www.emulab.net/news.php3#32).</td>
    </tr>
  </table>

  </ul>
</ul>

<ul>
<li><b>/XMLRPC/user</b>
<p>
The <tt>user</tt> module provides access to user-specific information.

  <ul>
  <li><tt><b>nodecount</b></tt>: Get the number of nodes you have allocated.
  There are no arguments and the method returns an integer.<br>

  <br>
  <li><tt><b>membership</b></tt>: Get the list of projects and subgroups of
  which you are a member.  The return value is a hash table where each entry is
  the name of a project and a list of subgroups.  The optional arguments
  are:<br><br>

  <table cellpadding=2>
    <tr>
      <th>Name</th><th>Type</th><th>Default</th><th>Description</th>
    </tr>
    <tr>
      <td>permission</td>
      <td>string</td>
      <td>readinfo</td>
      <td>The name of an action that the user would like to take.  The result
      will then be narrowed to those groups where this action is possible.
      Supported values:
      <ul>
      <li>readinfo - Read information about the project/group.
      <li>createexpt - Create an experiment.
      <li>makegroup - Create a sub-group.
      <li>makeosid - Create an OS identifier.
      <li>makeimageid - Create an image identifier.
      </ul>
      </td>
    </tr>
  </table>

  </ul>
</ul>

<ul>
<li><b>/XMLRPC/fs</b>
<p>
The <tt>fs</tt> module lets you examine the parts of the Emulab file system
that can be exported to your experimental nodes.

  <ul>
  <li><tt><b>access</b></tt>: Check the accessibility of a path.  The path
    must lie on an exported file system or the call will fail.  The return
    value is true or false.  The required arguments are:<br><br>
    <table cellpadding=2>
      <tr>
        <th>Name</th><th>Type</th><th>Description</th>
     </tr>
     <tr></tr>
     <tr>
      <td><tt>path</tt></td>
      <td>string</td>
      <td>The path to check</td>
     </tr>
     <tr>
      <td><tt>permission</tt></td>
      <td>string</td>
      <td>The access permission to check.  Value should be one of: "read",
      "write", "execute", "exists".</td>
     </tr>
    </table>

  <br>
  <li><tt><b>listdir</b></tt>: Get a directory list for a given path.  The path
    must lie on an exported file system of the call will fail.  The return
    value is a list of tuples for each entry, described in detail below.  The
    required arguments are:<br><br>
    <table cellpadding=2>
      <tr>
        <th>Name</th><th>Type</th><th>Description</th>
     </tr>
     <tr></tr>
     <tr>
      <td><tt>path</tt></td>
      <td>string</td>
      <td>The path to check</td>
     </tr>
    </table>

    <br>
    The return value is a list of tuples where each entry is organized as
    follows:<br><br>

    <table cellpadding=2>
      <tr>
        <th>Index</th><th>Type</th><th>Description</th>
     </tr>
     <tr></tr>
     <tr>
      <td>0</td>
      <td>string</td>
      <td>The name of the entry.</td>
     </tr>
     <tr>
      <td>1</td>
      <td>character</td>
      <td>The entry type, where:
      <ul>
      <li>'d' - directory
      <li>'c' - character device
      <li>'b' - block device
      <li>'f' - regular file
      <li>'l' - link
      <li>'s' - socket
      <li>'u' - unknown
      </td>
     </tr>
     <tr>
      <td>2</td>
      <td>integer</td>
      <td>Unix permission mask.</td>
     </tr>
     <tr>
      <td>3</td>
      <td>string</td>
      <td>Name of the user owner.</td>
     </tr>
     <tr>
      <td>4</td>
      <td>string</td>
      <td>Name of the group owner.</td>
     </tr>
     <tr>
      <td>5</td>
      <td>integer</td>
      <td>The size of the file.</td>
     </tr>
     <tr>
      <td>6</td>
      <td>integer</td>
      <td>The last access time as the number of seconds since the epoch.</td>
     </tr>
     <tr>
      <td>7</td>
      <td>integer</td>
      <td>The last modified time as the number of seconds since the epoch.</td>
     </tr>
     <tr>
      <td>8</td>
      <td>integer</td>
      <td>The creation time as the number of seconds since the epoch.</td>
     </tr>
    </table>

    <br>
    <li><tt><b>exports</b></tt>: Get the root list of file system exports
    available to you.  This method takes no arguments and returns a list of
    strings that represent the set of paths that are potentially accessible by
    your experimental nodes.<br><br>

    Note 1: The list does <i>not</i> include other user directories even though
    they may be accessible.<br><br>

    Note 2: The list <i>does</i> include all project and group directories that
    you are a member of, even though the nodes will only be able to access the
    project/group directories the experiment was created under.

  </ul>
</ul>

<ul>
<li><b>/XMLRPC/experiment</b>
<p>
The <tt>experiment</tt> module lets you start, control, and terminate
experiments.

  <ul>
  <li><tt><b>constraints</b></tt>: Get the physical/policy constraints for
  experiment parameters.  There are no arguments and the return value is a hash
  table with the following elements:<br><br>

  <table cellpadding=2>
  <tr>
    <th>Name</th><th>Type</th><th>Description</th>
  </tr>
  <tr>
    <td>idle/threshold</td>
    <td>integer</td>
    <td>The maximum number of hours allowed for the idleswap parameter.</td>
  </tr>
  </table>
  

  <br>
  <li><tt><b>startexp</b></tt>: Create an experiment. By default, the experiment
  is started as a <a href="tutorial/tutorial.php3#BatchMode"><em>batch</em></a>
  experiment, but you can use the <tt>batchmode</tt> option described below to
  alter that behavior. You can pass an NS file inline, or you can give the
  path of a file already on the Emulab fileserver.
  <br>
  <br>
  The required arguments are:<br><br>
  <table cellpadding=2>
  <tr>
    <th>Name</th><th>Type</th><th>Description</th>
  </tr>
  <tr></tr>
  <tr>
    <td><tt>proj</tt></td>
    <td>string</td>
    <td>The Emulab project ID in which to create the experiment</td>
  </tr>
  <tr>
    <td><tt>exp</tt></td>
    <td>string</td>
    <td>The unique ID to call the experiment</td>
  </tr>
  <tr>
    <td><tt>nsfilestr</tt></td>
    <td>string</td>
    <td> A string representing the NS file to use, with embedded newlines,
         <b>or</b>,</td>
  </tr>
  <tr>
    <td><tt>nsfilepath</tt></td>
    <td>string</td>
    <td>The pathname of a NS file on the Emulab file
         server, within the project directory<br>
	 (example: /proj/myproj/foo.ns)</td>
  </tr>
  </table>
  <br>
  The optional arguments are:<br><br>
  <table cellpadding=2>
   <tr>
    <th>Name</th><th>Type</th><th>Default</th><th>Description</th>
   </tr>
   <tr></tr>
   <tr>
    <td><tt>group</tt></td>
    <td>string</td>
    <td>proj</td>
    <td>The Emulab subgroup ID in which to create the experiment<br>
        (defaults to project id)</td>
   </tr>
   <tr>
    <td><tt>batch</tt></td>
    <td>boolean</td>
    <td>true</td>
    <td>Create a
         <a href="tutorial/tutorial.php3#BatchMode"><em>batch</em></a>
         experiment. Value is either "true" or "false"</td>
   </tr>
   <tr>
    <td><tt>description</tt></td>
    <td>string</td>
    <td>&nbsp;</td>
    <td>A pithy sentence describing your experiment</td>
   </tr>
   <tr>
    <td><tt>swappable</tt></td>
    <td>boolean</td>
    <td>true</td>
    <td>Experiment may be swapped at any time. If false, you must provide a
        reason in <tt>noswap_reason</tt></td> 
   </tr>
   <tr>
    <td><tt>noswap_reason</tt></td>
    <td>string</td>
    <td>&nbsp;</td>
    <td>A sentence describing why your experiment cannot be swapped</td> 
   </tr>
   <tr>
    <td><tt>idleswap</tt></td>
    <td>integer</td>
    <td>variable</td>
    <td>How long (in minutes) before your idle experiment can be 
         <a href="docwrapper.php3?docname=swapping.html#idleswap">idle
	 swapped</a>. Defaults to a value between two and four hours.  A
	 value of zero means never idleswap (you must provide a reason in
	 <tt>noidleswap_reason</tt>)</td>
   </tr>
   <tr>
    <td><tt>noidleswap_reason</tt></td>
    <td>string</td>
    <td>&nbsp;</td>
    <td>A sentence describing why your experiment cannot be idle swapped</td> 
   </tr>
   <tr>
    <td><tt>max_duration</tt></td>
    <td>integer</td>
    <td>0</td>
    <td>How long (in minutes) before your experiment
     should be <a href="docwrapper.php3?docname=swapping.html#autoswap">
     unconditionally swapped</a>. A value of zero means never
     unconditionally swap this experiment.
   </tr>
   <tr>
    <td><tt>noswapin</tt></td>
    <td>boolean</td>
    <td>false</td>
    <td>If true, do not swap the experiment in immediately; just "preload"
    the NS file. The experiment can be swapped in later with swapexp.</td>
   </tr>
   <tr>
    <td><tt>wait</tt></td>
    <td>boolean</td>
    <td>false</td>
    <td>If true, wait synchronously for the experiment to finish swapping.
    By default, control returns immediately, and you must wait for email
    notification to determine if the operation succeeded</td>
   </tr>
  </table>

  <br>
  <li><tt><b>swapexp</b></tt>: Swap an experiment in or out. The experiment
  must, of course, be in the proper state for requested operation.
  <br>
  <br>
  The required arguments are:<br><br>
  <table cellpadding=2>
  <tr>
    <th>Name</th><th>Type</th><th>Description</th>
  </tr>
  <tr></tr>
  <tr>
    <td><tt>proj</tt></td>
    <td>string</td>
    <td>The Emulab project ID of the experiment</td>
  </tr>
  <tr>
    <td><tt>exp</tt></td>
    <td>string</td>
    <td>The Emulab experiment ID</td>
  </tr>
  <tr>
    <td><tt>direction</tt></td>
    <td>string</td>
    <td>The direction in which to swap; one of "in" or "out"
  </tr>
  </table>
  <br>
  The optional arguments are:<br><br>
  <table cellpadding=2>
   <tr>
    <th>Name</th><th>Type</th><th>Default</th><th>Description</th>
   </tr>
   <tr></tr>
   <tr>
    <td><tt>wait</tt></td>
    <td>boolean</td>
    <td>false</td>
    <td>If true, wait synchronously for the experiment to finish swapping
    in (or preloading if <tt>noswapin</tt> is true). By default, control
    returns immediately, and you must wait for email notification to
    determine if the operation succeeded</td>
   </tr>
  </table>

  <br>
  <li><tt><b>modify</b></tt>: Modify an experiment, either while it is
  swapped in or out. You must provide an NS file to direct the
  modification. 
  <br>
  <br>
  The required arguments are:<br><br>
  <table cellpadding=2>
  <tr>
    <th>Name</th><th>Type</th><th>Description</th>
  </tr>
  <tr></tr>
  <tr>
    <td><tt>proj</tt></td>
    <td>string</td>
    <td>The Emulab project ID of the experiment</td>
  </tr>
  <tr>
    <td><tt>exp</tt></td>
    <td>string</td>
    <td>The Emulab experiment ID</td>
  </tr>
  <tr>
    <td><tt>nsfilestr</tt></td>
    <td>string</td>
    <td> A string representing the NS file to use, with embedded newlines,
         <b>or</b>,</td>
  </tr>
  <tr>
    <td><tt>nsfilepath</tt></td>
    <td>string</td>
    <td>The pathname of a NS file on the Emulab file
         server, within the project directory<br>
	 (example: /proj/myproj/foo.ns)</td>
  </tr>
  </table>
  <br>
  The optional arguments are:<br><br>
  <table cellpadding=2>
   <tr>
    <th>Name</th><th>Type</th><th>Default</th><th>Description</th>
   </tr>
   <tr></tr>
   <tr>
    <td><tt>wait</tt></td>
    <td>boolean</td>
    <td>false</td>
    <td>If true, wait synchronously for the experiment to finish swapping
    in (or preloading if <tt>noswapin</tt> is true). By default, control
    returns immediately, and you must wait for email notification to
    determine if the operation succeeded</td>
   </tr>
   <tr>
    <td><tt>reboot</tt></td>
    <td>boolean</td>
    <td>false</td>
    <td>If true and the experiment is swapped in, reboot all nodes in the
    experiment</td>
   </tr>
   <tr>
    <td><tt>restart_eventsys</tt></td>
    <td>boolean</td>
    <td>false</td>
    <td>If true and the experiment is swapped in, restart the event system
    (all events are rerun from time zero)</td>
   </tr>
  </table>

  <br>
  <li><tt><b>endexp</b></tt>: Terminate an experiment.
  The required arguments are:<br><br>
  <table cellpadding=2>
  <tr>
    <th>Name</th><th>Type</th><th>Description</th>
  </tr>
  <tr></tr>
  <tr>
    <td><tt>proj</tt></td>
    <td>string</td>
    <td>The Emulab project ID in which the experiment was created</td>
  </tr>
  <tr>
    <td><tt>exp</tt></td>
    <td>string</td>
    <td>The Emulab ID of the experiment to terminate</td>
  </tr>
  </table>
  
  <br>
  The optional arguments are:<br><br>
  <table cellpadding=2>
   <tr>
    <th>Name</th><th>Type</th><th>Default</th><th>Description</th>
   </tr>
   <tr></tr>
   <tr>
    <td><tt>wait</tt></td>
    <td>boolean</td>
    <td>false</td>
    <td>If true, wait synchronously for the experiment to finish terminating.
    By default, control returns immediately, and you must wait for email
    notification to determine if the operation succeeded</td>
   </tr>
  </table>
  
  <br>
  <li><tt><b>state</b></tt>: Get the current state of the experiment.
  The return value is a string; one of active, swapped, activating, etc.
  The required arguments are:<br><br>
  <table cellpadding=2>
  <tr>
    <th>Name</th><th>Type</th><th>Description</th>
  </tr>
  <tr></tr>
  <tr>
    <td><tt>proj</tt></td>
    <td>string</td>
    <td>The Emulab project ID in which the experiment was created</td>
  </tr>
  <tr>
    <td><tt>exp</tt></td>
    <td>string</td>
    <td>The Emulab ID of the experiment</td>
  </tr>
  </table>
  
  <br>
  <li><tt><b>statewait</b></tt>: Wait for an experiment to reach a particular
  state. State is one of swapped, active, swapping, activating, etc. If the
  experiment is already in desired state, returns immediately, otherwise
  blocks indefinitely until the experiment reaches the state. Use the timeout
  option below to terminate the wait early. The required arguments are:<br><br>
  <table cellpadding=2>
  <tr>
    <th>Name</th><th>Type</th><th>Description</th>
  </tr>
  <tr></tr>
  <tr>
    <td><tt>proj</tt></td>
    <td>string</td>
    <td>The Emulab project ID in which the experiment was created</td>
  </tr>
  <tr>
    <td><tt>exp</tt></td>
    <td>string</td>
    <td>The Emulab ID of the experiment</td>
  </tr>
  <tr>
    <td><tt>state</tt></td>
    <td>string</td>
    <td>The experiment state to wait for</td>
  </tr>
  </table>
    
  <br>
  The optional arguments are:<br><br>
  <table cellpadding=2>
   <tr>
    <th>Name</th><th>Type</th><th>Default</th><th>Description</th>
   </tr>
   <tr></tr>
   <tr>
    <td><tt>timeout</tt></td>
    <td>integer</td>
    <td>1-999999</td>
    <td>Timeout after this many <b>seconds</b>. The return code is
        is <tt>RESPONSE_SUCCESS</tt> if the state is reached or
	<tt>RESPONSE_TIMEDOUT</tt> if the timer expires.
    </td>
   </tr>
  </table>

  <br>
  <li><tt><b>info</b></tt>: Get information about an experiment. The
  return value is a hash table (Dictionary) of hash tables. For example,
  the <tt>mapping</tt> request will return a hash indexed by node name, where
  each entry is another hash table of name=value pairs, such as type=pc850
  The required arguments are:<br><br>
  <table cellpadding=2>
  <tr>
    <th>Name</th><th>Type</th><th>Description</th>
  </tr>
  <tr></tr>
  <tr>
    <td><tt>proj</tt></td>
    <td>string</td>
    <td>The Emulab project ID in which the experiment was created</td>
  </tr>
  <tr>
    <td><tt>exp</tt></td>
    <td>string</td>
    <td>The Emulab ID of the experiment</td>
  </tr>
  <tr>
    <td><tt>aspect</tt></td>
    <td>string</td>
    <td>Request information about specific aspect of the experiment.</td>
  </tr>
  </table>
  
  <br>
  The <tt>aspect</tt> is one of:
  <table cellpadding=2>
   <tr>
    <th>Name</th><th>Description</th>
   </tr>
   <tr></tr>
   <tr>
    <td><tt>mapping</tt></td>
    <td>Request the mapping of nodes in your NS file, to physical testbed
    nodes. This request is ignored if the experiment is not swapped in</td>
   </tr>
   <tr>
    <td><tt>links</tt></td>
    <td>Request information about all of the links in your experiment,
    including delay characteristics, IP address and mask</td>
   </tr>
  </table>
  
  <br>
  <li><tt><b>nscheck</b></tt>: Check an NS file for obvious parser errors.
  The return code is <tt>RESPONSE_SUCCESS</tt> or <tt>RESPONSE_ERROR</tt>.
  The required arguments are:<br><br>
  <table cellpadding=2>
  <tr>
    <th>Name</th><th>Type</th><th>Description</th>
  </tr>
  <tr></tr>
  <tr>
    <td><tt>nsfilestr</tt></td>
    <td>string</td>
    <td> A string representing the NS file to use, with embedded newlines,
         <b>or</b>,</td>
  </tr>
  <tr>
    <td><tt>nsfilepath</tt></td>
    <td>string</td>
    <td>The pathname of a NS file on the Emulab file
         server, within the project directory<br>
	 (example: /proj/myproj/foo.ns)</td>
  </tr>
  </table>

  <br>
  <li><tt><b>delay_config</b></tt>: Change the link characteristics for a
  delayed link or lan. Note that the link/lan <b>must</b> already be
  delayed; you cannot convert a non-delayed link into a delayed link. When
  operating on a delayed lan, all nodes (links to the nodes) in the lan
  will be changed.
  The required arguments are:<br><br>
  <table cellpadding=2>
  <tr>
    <th>Name</th><th>Type</th><th>Description</th>
  </tr>
  <tr></tr>
  <tr>
    <td><tt>proj</tt></td>
    <td>string</td>
    <td>The Emulab project ID in which the experiment was created</td>
  </tr>
  <tr>
    <td><tt>exp</tt></td>
    <td>string</td>
    <td>The Emulab ID of the experiment</td>
  </tr>
  <tr>
    <td><tt>link</tt></td>
    <td>string</td>
    <td>The name of the link or lan to change; see your NS file</td>
  </tr>
  <tr>
    <td><tt>params</tt></td>
    <td>Dictionary</td>
    <td>A hashed array (Dictionary) of parameters to change; see below</td>
  </tr>
  </table>
  
  <br>
  The optional arguments are:<br><br>
  <table cellpadding=2>
   <tr>
    <th>Name</th><th>Type</th><th>Default</th><th>Description</th>
   </tr>
   <tr></tr>
   <tr>
    <td><tt>persist</tt></td>
    <td>boolean</td>
    <td>false</td>
    <td>If true, the base experiment is changed in the Emulab Database;
    changes will persist across swapin and swapout. By default, just the
    physical experiment is changed, and changes are lost at swapout</td>
   </tr>
   <tr>
    <td><tt>src</tt></td>
    <td>string</td>
    <td>&nbsp;</td>
    <td>If specified, change a duplex link asymmetrically; just the link from
    the node specified will be changed. <em>This option is ignored on lans; the
    entire lan must be changed</em></td>
   </tr>
  </table>

  <br>
  In addition to the required arguments, you must also supply at least
  one parameter to change in the <tt>params</tt> argument. The reader is
  encouraged to read the <tt>ipfw</tt> and <tt>dummynet</tt> man pages on
  <tt>users.emulab.net</tt>. It is important to note that Emulab supports a
  smaller set of tunable parameters then NS does; please read the
  aforementioned manual pages:<br><br>
  <table cellpadding=2>
   <tr>
    <th>Name</th><th>Type</th><th>Range</th><th>Description</th>
   </tr>
   <tr></tr>
   <tr>
    <td><tt>bandwidth</tt></td>
    <td>integer</td>
    <td>10-100000</td>
    <td>Bandwidth in <b>Kbits</b>/second</td>
   </tr>
   <tr>
    <td><tt>plr</tt></td>
    <td>number</td>
    <td>0 &lt;= plr &lt; 1</td>
    <td>Packet Loss Rate as a number between 0 and 1</td>
   </tr>
   <tr>
    <td><tt>delay</tt></td>
    <td>integer</td>
    <td>&gt; 0</td>
    <td>Delay in milliseconds</td>
   </tr>
   <tr>
    <td><tt>limit</tt></td>
    <td>integer</td>
    <td>&nbsp;</td>
    <td>Queue size in bytes or packets. Default is 50 ethernet sized packets</td>
   </tr>
   <tr>
    <td><tt>queue-in-bytes</tt></td>
    <td>integer</td>
    <td>0,1</td>
    <td>Limit is expressed in bytes or packets (slots); default is packets</td>
   </tr>
   <tr></tr>
   <td colspan=4 align=center>These are valid for RED/GRED links only</td>
   <tr></tr>
   <tr>
    <td><tt>maxthresh</tt></td>
    <td>integer</td>
    <td>&nbsp;</td>
    <td>Maximum threshold for the average queue size</td>
   </tr>
   <tr>
    <td><tt>thresh</tt></td>
    <td>integer</td>
    <td>&nbsp;</td>
    <td>Minimum threshold for the average queue size</td>
   </tr>
   <tr>
    <td><tt>linterm</tt></td>
    <td>integer</td>
    <td>&gt; 0</td>
    <td>Packet dropping probability expressed as an integer (1/linterm)</td>
   </tr>
   <tr>
    <td><tt>q_weight</tt></td>
    <td>number</td>
    <td>0 &lt;= plr &lt; 1</td>
    <td>For calculating average queue size</td>
   </tr>
  </table>

  <br>
  <li><tt><b>link_config</b></tt>: Change the link characteristics for a
  wireless lan. Note that the lan must already be a wireless link; you
  cannot convert wired link to a wireless link! 
  The required arguments are:<br><br>
  <table cellpadding=2>
  <tr>
    <th>Name</th><th>Type</th><th>Description</th>
  </tr>
  <tr></tr>
  <tr>
    <td><tt>proj</tt></td>
    <td>string</td>
    <td>The Emulab project ID in which the experiment was created</td>
  </tr>
  <tr>
    <td><tt>exp</tt></td>
    <td>string</td>
    <td>The Emulab ID of the experiment</td>
  </tr>
  <tr>
    <td><tt>link</tt></td>
    <td>string</td>
    <td>The name of the lan to change; see your NS file</td>
  </tr>
  <tr>
    <td><tt>params</tt></td>
    <td>Dictionary</td>
    <td>A hashed array (Dictionary) of parameters to change; see below</td>
  </tr>
  </table>
  
  <br>
  The optional arguments are:<br><br>
  <table cellpadding=2>
   <tr>
    <th>Name</th><th>Type</th><th>Default</th><th>Description</th>
   </tr>
   <tr></tr>
   <tr>
    <td><tt>persist</tt></td>
    <td>boolean</td>
    <td>false</td>
    <td>If true, the base experiment is changed in the Emulab Database;
    changes will persist across swapin and swapout. By default, just the
    physical experiment is changed, and changes are lost at swapout</td>
   </tr>
   <tr>
    <td><tt>src</tt></td>
    <td>string</td>
    <td>&nbsp;</td>
    <td>If specified, change a duplex link asymmetrically; just the link from
    the node specified will be changed. <em>This option is ignored on lans; the
    entire lan must be changed</em></td>
   </tr>
  </table>

  <br>
  In addition to the required arguments, you must also supply at least
  one parameter to change in the <tt>params</tt> argument. The reader is
  encouraged to read the
  <a href=tutorial/docwrapper.php3?docname=wireless.html>wireless
  tutorial</a> to see what parameters can be changed.
  <br>

  <br>
  <li><tt><b>reboot</b></tt>: Reboot all nodes in an experiment.
  The required arguments are:<br><br>
  <table cellpadding=2>
  <tr>
    <th>Name</th><th>Type</th><th>Description</th>
  </tr>
  <tr></tr>
  <tr>
    <td><tt>proj</tt></td>
    <td>string</td>
    <td>The Emulab project ID in which the experiment was created</td>
  </tr>
  <tr>
    <td><tt>exp</tt></td>
    <td>string</td>
    <td>The Emulab ID of the experiment</td>
  </tr>
  </table>
  
  <br>
  The optional arguments are:<br><br>
  <table cellpadding=2>
   <tr>
    <th>Name</th><th>Type</th><th>Default</th><th>Description</th>
   </tr>
   <tr></tr>
   <tr>
    <td><tt>wait</tt></td>
    <td>boolean</td>
    <td>false</td>
    <td>If true, wait synchronously for all nodes to complete their reboot</td>
   </tr>
  </table>
  
  <br>
  <li><tt><b>reload</b></tt>: Reload the disks on all nodes in an
  experiment. You may specify an imageid to use for all nodes, or you can
  allow the system to load the default imageid for each node. 
  The required arguments are:<br><br>
  <table cellpadding=2>
  <tr>
    <th>Name</th><th>Type</th><th>Description</th>
  </tr>
  <tr></tr>
  <tr>
    <td><tt>proj</tt></td>
    <td>string</td>
    <td>The Emulab project ID in which the experiment was created</td>
  </tr>
  <tr>
    <td><tt>exp</tt></td>
    <td>string</td>
    <td>The Emulab ID of the experiment</td>
  </tr>
  </table>
  
  <br>
  The optional arguments are:<br><br>
  <table cellpadding=2>
   <tr>
    <th>Name</th><th>Type</th><th>Default</th><th>Description</th>
   </tr>
   <tr></tr>
   <tr>
    <td><tt>wait</tt></td>
    <td>boolean</td>
    <td>true</td>
    <td>If true, wait synchronously for all nodes to complete their
    reload. The default is to wait; you must turn this off if you want
    the reload to proceed in the background (not a good idea)</td>
   </tr>
   <tr>
    <td><tt>imageid</tt></td>
    <td>string</td>
    <td>&nbsp;</td>
    <td>Specify the imageid to load on all of the nodes</td>
   </tr>
   <tr>
    <td><tt>imageproj</tt></td>
    <td>string</td>
    <td>&nbsp;</td>
    <td>Specify the Emulab project ID of the imageid. By default the
    system will look in the project of the experiment, and then in the
    system project for globally shared images.</td>
   </tr>
  </table>
  </ul>

<br>
<li><b>/XMLRPC/node</b>
<p>
The <tt>node</tt> module lets you control nodes in your experiments.
  <ul>
   <li><tt><b>reboot</b></tt>: Reboot nodes. The caller must have
   permission to reboot all of the nodes in the list, or the entire request
   fails. The required arguments are:<br><br>
    <table cellpadding=2>
     <tr>
      <th>Name</th><th>Type</th><th>Description</th>
     </tr>
     <tr></tr>
     <tr>
      <td><tt>nodes</tt></td>
      <td>string</td>
      <td>A comma separated list of nodes to reboot</td>
     </tr>
    </table>
  
    <br>
    The optional arguments are:<br><br>
    <table cellpadding=2>
     <tr>
      <th>Name</th><th>Type</th><th>Default</th><th>Description</th>
     </tr>
     <tr></tr>
     <tr>
      <td><tt>wait</tt></td>
      <td>boolean</td>
      <td>false</td>
      <td>If true, wait synchronously for all nodes to complete their reboot</td>
     </tr>
    </table>

   <br>
   <li><tt><b>create_image</b></tt>: Create an image from a node using
   a previously created
   <a href="<?php echo $TBBASE ?>/newimageid_ez.php3">imageid</a>. The 
   The required arguments are:<br><br>
    <table cellpadding=2>
     <tr>
      <th>Name</th><th>Type</th><th>Description</th>
     </tr>
     <tr></tr>
     <tr>
      <td><tt>node</tt></td>
      <td>string</td>
      <td>The node to create the image from</td>
     </tr>
     <tr>
      <td><tt>imageid</tt></td>
      <td>string</td>
      <td>The image id (descriptor)</td>
     </tr>
    </table>

    <br>
    The optional arguments are:<br><br>
    <table cellpadding=2>
     <tr>
      <th>Name</th><th>Type</th><th>Default</th><th>Description</th>
     </tr>
     <tr></tr>
     <tr>
      <td><tt>wait</tt></td>
      <td>boolean</td>
      <td>false</td>
      <td>If true, wait synchronously for all nodes to complete their
       reboot</td>
     </tr>
     <tr>
      <td><tt>proj</tt></td>
      <td>string</td>
      <td>emulab-ops</td>
      <td>The project ID in which the imageid was created; defaults to
      the system project</td>
     </tr>
    </table>

    <br>
    <li><tt><b>reload</b></tt>: Reload the disks on all nodes specified.
    You may specify an imageid to use for all nodes, or you can
    allow the system to load the default imageid for each node. 
    The required arguments are:<br><br>
    <table cellpadding=2>
     <tr>
      <th>Name</th><th>Type</th><th>Description</th>
     </tr>
     <tr></tr>
     <tr>
      <td><tt>nodes</tt></td>
      <td>string</td>
      <td>A comma separated list of nodes to reload</td>
     </tr>
    </table>
  
    <br>
    The optional arguments are:<br><br>
    <table cellpadding=2>
     <tr>
      <th>Name</th><th>Type</th><th>Default</th><th>Description</th>
     </tr>
     <tr></tr>
     <tr>
      <td><tt>wait</tt></td>
      <td>boolean</td>
      <td>true</td>
      <td>If true, wait synchronously for all nodes to complete their
      reload. The default is to wait; you must turn this off if you want
      the reload to proceed in the background (not a good idea)</td>
     </tr>
     <tr>
      <td><tt>imageid</tt></td>
      <td>string</td>
      <td>&nbsp;</td>
      <td>Specify the imageid to load on all of the nodes</td>
     </tr>
     <tr>
      <td><tt>imageproj</tt></td>
      <td>string</td>
      <td>&nbsp;</td>
      <td>Specify the Emulab project ID of the imageid. By default the
      system will look in the system project for globally shared images.</td>
     </tr>
    </table>
    
  </ul>
</ul>

<br>
<ul>
<li><b>/XMLRPC/osid</b>
<p>
The <tt>osid</tt> module lets you operate on OS descriptors.

  <ul>
  <li><tt><b>getlist</b></tt>: Get the list of OS identifiers you can access.
  There are no arguments and the return value is a hash table containing the OS
  IDs and their descriptions.

  </ul>
</ul>

<br>
<ul>
<li><b>/XMLRPC/imageid</b>
<p>
The <tt>imageid</tt> module lets you operate on Image descriptors.

  <ul>
  <li><tt><b>getlist</b></tt>: Get the list of Image identifiers you can
  access.  There are no arguments and the return value is a hash table
  containing the Image IDs and their descriptions.

  </ul>
</ul>

<?php
#
# Standard Testbed Footer
# 
if (!$printable) {
    PAGEFOOTER();
}
?>

