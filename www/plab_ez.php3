<?php
#
# EMULAB-COPYRIGHT
# Copyright (c) 2003, 2004 University of Utah and the Flux Group.
# All rights reserved.
#
include("defs.php3");

#
# The program we use to make the NS file, and the template we use
#
$NSGEN         = "webnsgen";
$PLAB_TEMPLATE = "$TBDIR/etc/nsgen/planetlab.xml";

#
# Figure out which view to present
#
if (isset($advanced) || $advanced || (isset($submit)
	&& ($submit != "Create it"))) {
    $advanced = 1;
}

#
# Only known and logged in users can get this page
#
$uid = GETLOGIN();
LOGGEDINORDIE($uid,0,"$TBBASE/login_plab.php3?refer=1");

#
# The reason for this apparently redundant pair of arrays is so that we can
# keep things in order - I don't beleive PHP's each() guarantees any order
# when using strings for array indices
#
$plab_types = array('pcplab', 'pcplabdsl', 'pcplabinet', 'pcplabintl',
    'pcplabinet2');
$plab_type_descr = array('pcplab' => 'Any PlanetLab node',
			 'pcplabdsl' => 'Nodes on DSL lines',
			 'pcplabinet' => 'Commodity Internet, North America',
		         'pcplabintl' => 'Outside North America',
			 'pcplabinet2' => 'Internet2');

#
# Spit out the form
#
function SPITFORM($advanced,$formfields, $errors = array()) {
    global $TBBASE;
    global $plab_types, $plab_type_descr;

    #
    # Header/footer view options
    #
    if ($advanced) {
	PAGEHEADER("Create a Slice on PlanetLab - Advanced Form");
    } else {
	PAGEHEADER("Create a Slice on PlanetLab");
    }

    #
    # If the user is not allowed to use planetlab nodes, print out a messages
    # telling them so
    #
    if (!NODETYPE_ALLOWED("pcplab")) {
	global $TBMAILADDR;
	echo "<p><b><font color=\"red\">NOTE:</font> You do not currently " .
	     "have permission to use PlanetLab nodes through Emulab. Please " .
	     "have your project leader contact $TBMAILADDR to request ".
	     "permission for your project to create PlanetLab slices. " .
	     "</b></p>\n";
    }

    $message = TBGetSiteVar("plab/message");
    if (0 != strcmp($message,"")) {
	echo "<p><h3><center><b>$message</b></center></h3></p><br>\n";
    }

### Possible status phrases:
# largely working.

    #
    # Display any errors
    #
    if (count($errors)) {
	echo "<table class=nogrid
                     align=center border=0 cellpadding=6 cellspacing=0>
              <tr>
                 <th align=center colspan=2>
                   <font size=+1 color=red>
                      &nbsp;Oops, please fix the following errors!&nbsp;
                   </font>
                 </td>
              </tr>\n";

	while (list ($name, $message) = each ($errors)) {
	    echo "<tr>
                     <td align=right>
                       <font color=red>$name:&nbsp;</font></td>
                     <td align=left>
                       <font color=red>$message</font></td>
                  </tr>\n";
	}
	echo "</table><br>\n";
    }

    #
    # The actual form
    #
    echo "<form name='form1' action='plab_ez.php3' method='get'>\n";
    echo "<table align=center border=1>\n";

    #
    # Header
    #
    if ($advanced) {
	echo "<tr><th colspan=2>Basic Options</th></tr>\n";
    } else {
	echo "<tr><th colspan=2>Create a Slice on
	      <a href='http://www.planet-lab.org'>PlanetLab</a></th></tr>\n";
    }

    #
    # How many nodes
    #
    if ($formfields[count]) {
	$nnodes = $formfields[count];
    } else {
	$nnodes = 10;
    }

    #
    # Grab a list of how many are available
    #
    $plab_counts = TBPlabAvail();

    #
    # Spit out some JavaScript that can be used to to put the number of nodes
    # into the input box
    #
    echo "<script language='JavaScript'> <!--
	function AllNodes() {
	    document.form1['formfields[resusage]'].value = '1';\n";
    while (list ($type,$counts) = each($plab_counts)) {
	echo "if (document.form1['formfields[type]'].value == '$type') { 
	    document.form1['formfields[count]'].value = '$counts[0]';
	}\n";
    }
    echo "
	}
	function AllSites() {
	    document.form1['formfields[resusage]'].value = '1';\n";
    reset($plab_counts);
    while (list ($type,$counts) = each($plab_counts)) {
	echo "if (document.form1['formfields[type]'].value == '$type') { 
	    document.form1['formfields[count]'].value = '$counts[1]';
	}\n";
    }
    echo "
	}
	//-->
    </script>\n";

    echo "<tr>
	     <td>Number of
	       <a href='plab_ez_footnote8.html'
	          target='emulabfootnote'>nodes</a></td>
	     <td><nobr>
		 <input type='text' name='formfields[count]'
		         value='$nnodes' size=4>\n";
    echo "or
		  <input type=button id=allnodes name='allnodes'
		         value='All available nodes' onclick='AllNodes()'>
		  or
		  <input type=button id=allsites name='allsites'
		         value='One node at each site' onclick='AllSites()'>\n";
    echo "
		   </nobr></td>
	 </tr>\n";

     #
     # These will appear on the advanced form, but we need to default them on
     # the short version
     #
     if (!$advanced) {
	 echo "<input type='hidden' name='formfields[canfail]' value='Yep'>\n";
	 echo "<input type='hidden' name='formfields[type]' value='pcplab'>\n";
	 echo "<input type='hidden' name='formfields[resusage]' value='3'>\n";
     }

    #
    # Advanced options
    #
    if ($advanced) {
	echo "<tr>
		 <th colspan=2>Advanced Options</th>
	      </tr>\n";

	#
	# Type
	#
	echo "<tr>
	         <td>Type of PlanetLab nodes:</td>
		 <td>
		    <select name='formfields[type]'>\n";
	while (list($junk,$type) = each($plab_types)) {
	    $descr = $plab_type_descr[$type];
	    list($acount,$asites) = $plab_counts[$type];
	    if (!$acount) {
		$acount = 0;
	    }
	    if (!$asites) {
		$asites = 0;
	    }
	    if ($formfields[type] && ($formfields[type] == $type)) {
		$selected = "selected";
	    } else {
		$selected = "";
	    }
	    echo "<option value='$type' $selected>$descr " .
	         "($acount available at $asites sites)</option>\n";
	}
	echo "
		    </select>
		 </td>
	      </tr>\n";

	#
	# Resource usage
	# Boy, keeping the previous value in drop down boxes sure is ugly!
	#
	echo "<tr>
	         <td>Estimated
		    <a href='plab_ez_footnote1.html' target='emulabfootnote'>
		    CPU and memory use</a>:</td>
		 <td>
		    <select name='formfields[resusage]'>
		    <option value='5'";
	if ($formfields[resusage] == 5) { echo " selected"; }
	echo ">Very High</option>
		    <option value='4'";
	if ($formfields[resusage] == 4) { echo " selected"; }
	echo ">High</option>
		    <option value='3'";
	if (!$formfields[resusage] || $formfields[resusage] == 3) {
	    echo " selected";
	}
	echo ">Medium</option>
		    <option value='2'";
	if ($formfields[resusage] == 2) { echo " selected"; }
	echo ">Low</option>
		    <option value='1'";
	if ($formfields[resusage] == 1) { echo " selected"; }
	echo ">Very Low</option>
		    </select>
		 </td>
	      </tr>\n";

	#
	# Batch
	#
	if ($formfields[batched]) {
	    $checked = "checked";
	} else {
	    $checked = "";
	}
	echo "<tr>
	         <td><a href='plab_ez_footnote6.html'
		        target='emulabfootnote'>Retry</a> until nodes with
			sufficient resources are available:</td>
	         <td>
		    <input type='checkbox' name='formfields[batched]' $checked>
		 </td>
	      </tr>\n";

	#
	# Canfail
	# XXX - Take previous value
	#
	echo "<tr>
	         <td><a href='plab_ez_footnote5.html'
		     target='emulabfootnote'>Proceed</a> even if some nodes
		     fail to set up:</td>
	         <td>
		    <input type='checkbox' name='formfields[canfail]' checked>
		 </td>
	      </tr>\n";

        #
	# Auto-swap
	#
	if (!$formfields['when']) {
	    $when = "never";
	} else {
	    $when = $formfields['when'];
	}
	echo "<tr>
	         <td><a href='plab_ez_footnote7.html'
		     target='emulabfootnote'>Auto-terminate</a> slice after:
	         <td>
		    <input type='text' size=6 name='formfields[when]'
		           value='$when'>
		    <select name='formfields[units]'>
		    <option value='1' selected>Hours</option>
		    <option value='24'>Days</option>
		    <option value='168'>Weeks</option>
		    </select>
		 </td>
	      </tr>\n";

	#
	# Header
	# 
	echo "<tr>
		 <th colspan=2>Files to Install and Maintain</th>
	      </tr>\n";

	#
	# Tarballs
	#
	echo "<tr>
	         <td><a href='plab_ez_footnote2.html'
		        target='emulabfootnote'>Tarball(s)</a> to install:</td>
		 <td>
		    <input type='text' size=50 name=formfields[tarball]
		           value='$formfields[tarball]'>
		 </td>
	      </tr>\n";

	#
	# RPMs
	#
	echo "<tr>
	         <td><a href='plab_ez_footnote3.html'
		        target='emulabfootnote'>RPM(s)</a> to install:</td>
	         <td>
		    <input type='text' name='formfields[rpm]'
		           value='$formfields[rpm]' size=50>
	         </td>
              </tr>\n";

	#
	# Startup commands
	#
	echo "<tr>
                 <td><a href='plab_ez_footnote4.html'
		        target='emulabfootnote'>Command</a> to run on startup:
		</td>
	         <td>
		    <input type='text' name='formfields[startupcmd]'
		           value='$formfields[startupcmd]' size=50>
		 </td>
               </tr>\n";
    } # if ($advanced)

    #
    # Submit buttons
    #
    echo "<tr>
             <th colspan=2>\n";

    if ($advanced) {
	echo "<center><input type=submit name=submit value='Submit'>&nbsp;\n";
	echo "<input type=reset value='Reset'></center>\n";
    } else {
	echo "<br>\n";
	echo "<center><input type=submit name=submit value='Create it'>&nbsp;\n";
	echo "<input type=submit name=submit value='More options'></center>\n";
    }
    echo "</th>\n";
    echo "</tr>\n";

    #
    # Finish the table off
    #
    echo "</table>\n";
    echo "</form>\n";

    #
    # On the advanced form, give a link to the link information, too
    #
    if ($advanced) {
	echo "<h4>You can also take a look at the " .
	     "<a href=widearea_nodeinfo.php3>widearea node link metrics</a> " .
	     "</h4>\n";
    }

    PAGEFOOTER();
}

#
# Check tarballs (and RPMs) to make sure that they are fetchable, if URLs were
# given. Returns any errors.
#
function CHECKTARS($formfields) {

    #
    # Make a list of files that will ahve to be fetched
    #
    $tofetch = array();

    #
    # Check RPMs
    #
    if ($formfields['rpm']) {
	$rpms = explode(" ",$formfields['rpm']);
	while (list($junk,$rpm) = each($rpms)) {
	    if (preg_match("/^(http|ftp)/",$rpm,$matches)) {
		$tofetch[$rpm] = 1;
	    } else if (!preg_match("/^\//",$rpm,$matches)) {
		$errors[$rpm] = "RPM should be a http or ftp URL, or a path " .
			"on users.emulab.net";
	    }
	}
    }

    #
    # Tarballs are much like RPMs, but they need a path to untar to, too.
    #
    if ($formfields['tarball']) {
	$tarballs = explode(" ",$formfields['tarball']);
	if (count($tarballs) % 2) {
	    $errors['tarballs'] = "Should be a space-separated list of " .
		"&lt;directory&gt; &lt;tarball&gt; pairs";
	} else {
	    while (list($index,$tarball) = each($tarballs)) {
		if (!($index % 2)) {
		    if (!preg_match("/^\//",$tarball,$matches)) {
			$errors[$tarball] = "Should be a path to start the " .
			    "untar from";
		    }
		    continue;
		}
		if (preg_match("/^(http|ftp)/",$tarball,$matches)) {
		    $tofetch[$tarball] = 1;
		} else if (!preg_match("/^\//",$tarball,$matches)) {
		    $errors[$tarball] = "Tarball should be a http or ftp URL, or a path " .
			"on users.emulab.net";
		}
	    }
	}
    }

    #
    # Now take all the URLs, and make sure they're fetch-able. Don't actually
    # fecth them - that will be done later.
    #
    while (list($URL,$localfile) = each($tofetch)) {
	$fhandle = @fopen($URL,"r");
	if (!$fhandle) {
	    $errors[$URL] = "Unable to fetch file\n";
	} else {
	    fclose($fhandle);
	}
    }

    return $errors;

}

#
# Make an NS file with the supplied data
#
function MAKENS($formfields) {
    global $NSGEN, $PLAB_TEMPLATE;
    #
    # Pick out some defaults for the exp. creation page
    #

    $expname = "planetlab" . $formfields['count'];
    $descr   = "A planetlab experiment with " . $formfields['count'] .
	" nodes started by " . GETUID();

    #
    # Build up a URL to send the user to
    #
    $url = "beginexp_html.php3?view_style=plab&formfields[exp_id]=" .
           urlencode($expname) . "&formfields[exp_description]=" .
	   urlencode($descr) . "&formfields[exp_idleswap]=0" .
	   "&formfields[exp_noidleswap_reason]=" .
	   urlencode("PlanetLab experiment");

    #
    # Batched?
    #
    if ($formfields['batched']) {
	$url .= '&formfields[exp_batched]=Yep';
    }

    #
    # Determine the auto-swap time
    #
    if ($formfields['when'] && ($formfields['when'] != 'never')) {
	$swaptime = $formfields['when'] * $formfields['units'];
	$url .= "&formfields[exp_autoswap]=1";
	$url .= "&formfields[exp_autoswap_timeout]=$swaptime";
    }

    #
    # Run nsgen - make up a random nsref for use with it
    # NOTE: Stuff that is being used as command-line arguments was already
    # checked for bad characters by CHECKFORM()
    #
    list($usec, $sec) = explode(' ', microtime());
    srand((float) $sec + ((float) $usec * 100000));
    $nsref = rand();
    $url .= "&nsref=$nsref";
    $outfile = "/tmp/" . GETUID() . "-$nsref.nsfile";
    $nsgen_args = "";
    if ($formfields['count']) {
	$nsgen_args .= "-v Count='$formfields[count]' ";
    }
    if ($formfields['type']) {
	$nsgen_args .= "-v HWType='$formfields[type]' ";
    }
    if ($formfields['resusage']) {
	$nsgen_args .= "-v ResUsage='$formfields[resusage]' ";
    }
    if ($formfields['canfail']) {
	$nsgen_args .= "-v FailOK=1 ";
    }
    if ($formfields['tarball']) {
	$nsgen_args .= "-v Tarballs='$formfields[tarball]' ";
    }
    if ($formfields['rpm']) {
	$nsgen_args .= "-v RPMs='$formfields[rpm]' ";
    }
    if ($formfields['startupcmd']) {
	$nsgen_args .= "-v Startup='$formfields[startupcmd]' ";
    }
    
    #
    # Note: We run this as nobody on purpose - this is really dumb, but later
    # the web interface needs to be able to remove this file, and /tmp
    # usually has the sticky bit set, so only the owner can remove it.
    #
    SUEXEC("nobody","nobody","$NSGEN -o $outfile $nsgen_args $PLAB_TEMPLATE",
	SUEXEC_ACTION_DIE);

    header("Location: $url");
}

#
# Check values the user submitted to make sure that they are valid
#
function CHECKFORM($formfields) {
    $errors = array();
    if (!preg_match("/^\d+$/",$formfields['count'],$matches)) {
	$errors['count'] = "Number of nodes must be a positive integer";
    }
    if ($formfields['when'] && ($formfields['when'] != "never") &&
        (!preg_match("/^\d*(\.\d+)?$/",$formfields['when'],$matches))) {
	$errors['when'] = "Auto-terminate time must be a positive decimal " .
	    "or 'never'";
    }
    if ($formfields['resusage'] &&
	    !preg_match("/^\d+$/",$formfields['resusage'],$matches)) {
	$errors['resusage'] = "Resource usage must be a positive integer";
    }
    if ($formfields['tarball'] &&
	    preg_match("/'/",$formfields['tarball'],$matches)) {
	$errors['tarball'] = "Invalid characters in tarball";
    }
    if ($formfields['rpm'] &&
	    preg_match("/'/",$formfields['rpm'],$matches)) {
	$errors['rpm'] = "Invalid characters in rpm";
    }
    if ($formfields['startupcmd'] &&
	    preg_match("/'/",$formfields['startupcmd'],$matches)) {
	$errors['startupcmd'] = "Invalid characters in startup command";
    }

    return $errors;
}

#
# Actually do it!
#
if (($submit == "Submit") || ($submit == "Create it")) {
    $errors = CHECKFORM($formfields);
    if (!count($errors)) {
	$errors = CHECKTARS($formfields);
    }
    if (!count($errors)) {
	MAKENS($formfields);
    } else {
	SPITFORM($advanced, $formfields, $errors);
    }
} else {
    SPITFORM($advanced, $formfields);
}

#
# Standard Testbed Footer
#
?>
