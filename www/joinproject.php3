<?php
#
# EMULAB-COPYRIGHT
# Copyright (c) 2000-2003, 2005 University of Utah and the Flux Group.
# All rights reserved.
#
include("defs.php3");

#
# No PAGEHEADER since we spit out a Location header later. See below.
#

#
# Get current user.
# 
$uid = GETLOGIN();

#
# If a uid came in, then we check to see if the login is valid.
# We require that the user be logged in to start a second project.
#
if ($uid) {
    # Allow unapproved users to join multiple groups ...
    # Must be verified though.
    LOGGEDINORDIE($uid, CHECKLOGIN_UNAPPROVED|
		  CHECKLOGIN_WEBONLY|CHECKLOGIN_WIKIONLY);
    $joining_uid = $uid;
    $returning = 1;
}
else {
    #
    # No uid, so must be new.
    #
    $returning = 0;
}

if (!isset($forwikionly)) {
    $forwikionly = 0;
}

$ACCOUNTWARNING =
    "Before continuing, please make sure your username " .
    "reflects your normal login name. ".
    "Emulab accounts are not to be shared amongst users!";

$EMAILWARNING =
    "Before continuing, please make sure the email address you have ".
    "provided is current and non-pseudonymic. Redirections and anonymous ".
    "email addresses are not allowed.";

#
# Spit the form out using the array of data. 
# 
function SPITFORM($formfields, $returning, $errors)
{
    global $TBDB_UIDLEN, $TBDB_PIDLEN, $TBDB_GIDLEN;
    global $ACCOUNTWARNING, $EMAILWARNING;
    global $WIKISUPPORT, $forwikionly, $WIKIHOME;

    if ($forwikionly)
	PAGEHEADER("Wiki Registration");
    else
	PAGEHEADER("Apply for Project Membership");

    if (! $returning) {
	echo "<center>\n";

	if ($forwikionly) {
	    echo "<font size=+2>Register for an Emulab Wiki account</font>
                  <br><br>\n";
	}
        echo "<font size=+1>
               If you already have an Emulab account,
               <a href=login.php3?refer=1>
               <font color=red>please log on first!</font></a>
              </font>\n";
	if ($forwikionly) {
	    echo "<br>(You will already have a wiki account)\n";
	}
	echo "</center><br>\n";	
    }
    elseif ($forwikionly) {
	USERERROR("You already have a Wiki account!", 1);
    }

    if ($errors) {
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
    echo "<SCRIPT LANGUAGE=JavaScript>
              function SetWikiName(theform) 
              {
	          var validchars = 'abcdefghijklmnopqrstuvwxyz0123456789';
                  var usrname    = theform['formfields[usr_name]'].value;
                  var wikiname   = '';
                  var docap      = 1;

		  for (var i = 0; i < usrname.length; i++) {
                      var letter = usrname.charAt(i).toLowerCase();

                      if (validchars.indexOf(letter) == -1) {
                          if (letter == ' ') {
                              docap = 1;
                          }
                          continue;
                      }
                      else {
                          if (docap == 1) {
                              letter = usrname.charAt(i).toUpperCase()
                              docap  = 0;
                          }
                          wikiname = wikiname + letter;
                      }
                  }
                  theform['formfields[wikiname]'].value = wikiname;
              }
          </SCRIPT>\n";

    echo "<table align=center border=1> 
          <tr>
            <td align=center colspan=3>
                Fields marked with * are required.
            </td>
          </tr>\n

          <form name=myform enctype=multipart/form-data
                action=" . ($forwikionly ?
			    "wikiregister.php3" : "joinproject.php3") . " " .
	        "method=post>\n";

    if (! $returning) {
        #
        # UserName:
        #
        echo "<tr>
                  <td colspan=2>*<a
                         href='docwrapper.php3?docname=security.html'
                         target=_blank>Username</a>
                            (alphanumeric, lowercase):</td>
                  <td class=left>
                      <input type=text
                             name=\"formfields[joining_uid]\"
                             value=\"" . $formfields[joining_uid] . "\"
	                     size=$TBDB_UIDLEN
                             onchange=\"alert('$ACCOUNTWARNING')\"
	                     maxlength=$TBDB_UIDLEN>
                  </td>
              </tr>\n";

	#
	# Full Name
	#
        echo "<tr>
                  <td colspan=2>*Full Name:</td>
                  <td class=left>
                      <input type=text
                             name=\"formfields[usr_name]\"
                             onchange=\"SetWikiName(myform);\"
                             value=\"" . $formfields[usr_name] . "\"
	                     size=30>
                  </td>
              </tr>\n";

	#
	# WikiName
	#
	if ($WIKISUPPORT) {
	    echo "<tr>
                      <td colspan=2>*<a
                            href=${WIKIHOME}/bin/view/TWiki/WikiName
                            target=_blank>WikiName</a>:<td class=left>
                          <input type=text
                                 name=\"formfields[wikiname]\"
                                 value=\"" . $formfields[wikiname] . "\"
	                         size=30>
                      </td>
                  </tr>\n";
	}

	if (! $forwikionly) {
            #
            # Title/Position:
	    #
	    echo "<tr>
                      <td colspan=2>*Title/Position:</td>
                      <td class=left>
                          <input type=text
                                 name=\"formfields[usr_title]\"
                                 value=\"" . $formfields[usr_title] . "\"
  	                         size=30>
                      </td>
                  </tr>\n";

            #
            # Affiliation:
            # 
	    echo "<tr>
                      <td colspan=2>*Institutional<br>Affiliation:</td>
                      <td class=left>
                          <input type=text
                                 name=\"formfields[usr_affil]\"
                                 value=\"" . $formfields[usr_affil] . "\"
	                         size=40>
                      </td>
                  </tr>\n";

	    #
	    # User URL
	    #
	        echo "<tr>
                      <td colspan=2>Home Page URL:</td>
                      <td class=left>
                          <input type=text
                                 name=\"formfields[usr_URL]\"
                                 value=\"" . $formfields[usr_URL] . "\"
	                         size=45>
                      </td>
                  </tr>\n";
	}

	#
	# Email:
	#
	echo "<tr>
                  <td colspan=2>*Email Address[<b>1</b>]:</td>
                  <td class=left>
                      <input type=text
                             name=\"formfields[usr_email]\"
                             value=\"" . $formfields[usr_email] . "\"
                             onchange=\"alert('$EMAILWARNING')\"
	                     size=30>
                  </td>
              </tr>\n";

	if (! $forwikionly) {
	    #
	    # Postal Address
	    #
	    echo "<tr><td colspan=3>*Postal Address:<br /><center>
		    <table>
		      <tr><td>Line 1</td><td colspan=3>
                        <input type=text
                               name=\"formfields[usr_addr]\"
                               value=\"" . $formfields[usr_addr] . "\"
	                       size=45></td></tr>
		      <tr><td>Line 2</td><td colspan=3>
                        <input type=text
                               name=\"formfields[usr_addr2]\"
                               value=\"" . $formfields[usr_addr2] . "\"
	                       size=45></td></tr>
		      <tr><td>City</td><td>
                        <input type=text
                               name=\"formfields[usr_city]\"
                               value=\"" . $formfields[usr_city] . "\"
	                       size=25></td>
		          <td>State/Province</td><td>
                        <input type=text
                               name=\"formfields[usr_state]\"
                               value=\"" . $formfields[usr_state] . "\"
	                       size=2></td></tr>
		      <tr><td>ZIP/Postal Code</td><td>
                        <input type=text
                               name=\"formfields[usr_zip]\"
                               value=\"" . $formfields[usr_zip] . "\"
	                       size=10></td>
		          <td>Country</td><td>
                        <input type=text
                               name=\"formfields[usr_country]\"
                               value=\"" . $formfields[usr_country] . "\"
	                       size=15></td></tr>
                   </table></center></td></tr>";

	    #
	    # Phone
	    #
	    echo "<tr>
                      <td colspan=2>*Phone #:</td>
                      <td class=left>
                          <input type=text
                                 name=\"formfields[usr_phone]\"
                                 value=\"" . $formfields[usr_phone] . "\"
	                         size=15>
                      </td>
                  </tr>\n";

	    #
	    # SSH public key
	    #
	    echo "<tr>
                     <td rowspan><center>
                                   Your SSH Pub Key: &nbsp<br>
                                        [<b>2</b>]
                                  </center></td>
    
                      <td rowspan><center>Upload (1K max)[<b>3</b>]<br>
                                      <b>Or</b><br>
                                   Insert Key
                                 </center></td>
    
                      <td rowspan>
                          <input type=hidden name=MAX_FILE_SIZE value=1024>
                          <input type=file
                                 name=usr_keyfile
                                 value=\"" . $_FILES['usr_keyfile']['name'] .
		                       "\"
	                         size=50>
                          <br>
                          <br>
	                  <input type=text
                                 name=\"formfields[usr_key]\"
                                 value=\"$formfields[usr_key]\"
	                         size=50
	                         maxlength=1024>
                      </td>
                  </tr>\n";
	}

	#
	# Password. Note that we do not resend the password. User
	# must retype on error.
	#
	echo "<tr>
                  <td colspan=2>*Password[<b>1</b>]:</td>
                  <td class=left>
                      <input type=password
                             name=\"formfields[password1]\"
                             size=8></td>
              </tr>\n";

        echo "<tr>
                  <td colspan=2>*Retype Password:</td>
                  <td class=left>
                      <input type=password
                             name=\"formfields[password2]\"
                             size=8></td>
             </tr>\n";
    }

    if (! $forwikionly) {
        #
        # Project Name:
        #
	echo "<tr>
                  <td colspan=2>*Project Name:</td>
                  <td class=left>
                      <input type=text
                             name=\"formfields[pid]\"
                             value=\"" . $formfields[pid] . "\"
	                     size=$TBDB_PIDLEN maxlength=$TBDB_PIDLEN>
                  </td>
              </tr>\n";

        #
        # Group Name:
        #
	echo "<tr>
                  <td colspan=2>Group Name:<br>
                  (Leave blank unless you <em>know</em> the group name)</td>
                  <td class=left>
                      <input type=text
                             name=\"formfields[gid]\"
                             value=\"" . $formfields[gid] . "\"
	                     size=$TBDB_GIDLEN maxlength=$TBDB_GIDLEN>
                  </td>
              </tr>\n";
    }

    echo "<tr>
              <td colspan=3 align=center>
                 <b><input type=submit name=submit value=Submit></b>
              </td>
          </tr>\n";

    echo "</form>
          </table>\n";

    echo "<h4><blockquote><blockquote>
          <ol>
            <li> Please consult our
                 <a href = 'docwrapper.php3?docname=security.html' target='_blank'>
                 security policies</a> for information
                 regarding passwords and email addresses.\n";
    if (!$returning && !$forwikionly) {
	echo "<li> If you want us to use your existing ssh public key,
                   then either paste it in or specify the path to your
                   your identity.pub file.  <font color=red>NOTE:</font>
                   We use the <a href=http://www.openssh.org target='_blank'>OpenSSH</a>
                   key format,
                   which has a slightly different protocol 2 public key format
                   than some of the commercial vendors such as
                   <a href=http://www.ssh.com target='_blank'>SSH Communications</a>. If you
                   use one of these commercial vendors, then please
                   upload the public  key file and we will convert it
                   for you. <i>Please do not paste it in.</i>\n

              <li> Note to <a href=http://www.opera.com target='_blank'><b>Opera 5</b></a>
                   users: The file upload mechanism is broken in Opera, so
                   you cannot specify a local file for upload. Instead,
                   please paste your public key in.\n";
    }
    echo "</ol>
          </blockquote></blockquote>
          </h4>\n";
}

#
# The conclusion of a join request. See below.
# 
if (isset($_GET['finished'])) {
    if ($forwikionly) 
	PAGEHEADER("Wiki Registration");
    else
	PAGEHEADER("Apply for Project Membership");

    #
    # Generate some warm fuzzies.
    #
    if ($forwikionly) {
	echo "An email message has been sent to your account so we may verify
              your email address. Please follow the instructions contained in
              that message, which will verify your account, and grant you
              access to the Wiki.\n";
    }
    elseif (! $returning) {
	echo "<p>
              As a pending user of the Testbed you will receive a key via email.
              When you receive the message, please follow the instructions
              contained in the message, which will verify your identity.
	      <br>
	      <p>
	      When you have done that, the project leader will be
	      notified of your application. ";
    }
    else {
          echo "<p>
	  	The project leader has been notified of your application. ";
    }

    echo "He/She will make a decision and either approve or deny your
          application, and you will be notified via email as soon as
	  that happens.\n";

    PAGEFOOTER();
    return;
}

#
# On first load, display a virgin form and exit.
#
if (! isset($_POST['submit'])) {
    $defaults = array();
    $defaults[usr_URL] = "$HTTPTAG";
    $defaults[usr_country] = "USA";

    #
    # These two allow presetting the pid/gid.
    # 
    if (isset($target_pid) && strcmp($target_pid, "")) {
	$defaults[pid] = $target_pid;
    }
    if (isset($target_gid) && strcmp($target_gid, "")) {
	$defaults[gid] = $target_gid;
    }
    
    SPITFORM($defaults, $returning, 0);
    PAGEFOOTER();
    return;
}
else {
    # Form submitted. Make sure we have a formfields array and a target_uid.
    if (!isset($_POST['formfields']) ||
	!is_array($_POST['formfields'])) {
	PAGEARGERROR("Invalid form arguments.");
    }
    $formfields = $_POST['formfields'];
}

#
# Otherwise, must validate and redisplay if errors
#
$errors = array();

#
# These fields are required!
#
if (! $returning) {
    if (!isset($formfields[joining_uid]) ||
	strcmp($formfields[joining_uid], "") == 0) {
	$errors["Username"] = "Missing Field";
    }
    elseif (!TBvalid_uid($formfields[joining_uid])) {
	$errors["UserName"] = TBFieldErrorString();
    }
    elseif (TBCurrentUser($formfields[joining_uid]) ||
	    posix_getpwnam($formfields[joining_uid])) {
	$errors["UserName"] = "Already in use. Pick another";
    }
    if (!isset($formfields[usr_name]) ||
	strcmp($formfields[usr_name], "") == 0) {
	$errors["Full Name"] = "Missing Field";
    }
    elseif (! TBvalid_usrname($formfields[usr_name])) {
	$errors["Full Name"] = TBFieldErrorString();
    }
    # Make sure user name has at least two tokens!
    $tokens = preg_split("/[\s]+/", $formfields[usr_name],
			 -1, PREG_SPLIT_NO_EMPTY);
    if (count($tokens) < 2) {
	$errors["Full Name"] = "Please provide a first and last name";
    }
    if ($WIKISUPPORT) {
	if (!isset($formfields[wikiname]) ||
	    strcmp($formfields[wikiname], "") == 0) {
	    $errors["WikiName"] = "Missing Field";
	}
	elseif (! TBvalid_wikiname($formfields[wikiname])) {
	    $errors["WikiName"] = TBFieldErrorString();
	}
	elseif (TBCurrentWikiName($formfields[wikiname])) {
	    $errors["WikiName"] = "Already in use. Pick another";
	}
    }
    if (!$forwikionly) {
	if (!isset($formfields[usr_title]) ||
	    strcmp($formfields[usr_title], "") == 0) {
	    $errors["Title/Position"] = "Missing Field";
	}
	elseif (! TBvalid_title($formfields[usr_title])) {
	    $errors["Title/Position"] = TBFieldErrorString();
	}
	if (!isset($formfields[usr_affil]) ||
	    strcmp($formfields[usr_affil], "") == 0) {
	    $errors["Affiliation"] = "Missing Field";
	}
	elseif (! TBvalid_affiliation($formfields[usr_affil])) {
	    $errors["Affiliation"] = TBFieldErrorString();
	}
    }	
    if (!isset($formfields[usr_email]) ||
	strcmp($formfields[usr_email], "") == 0) {
	$errors["Email Address"] = "Missing Field";
    }
    elseif (! TBvalid_email($formfields[usr_email])) {
	$errors["Email Address"] = TBFieldErrorString();
    }
    elseif (TBCurrentEmail($formfields[usr_email])) {
        #
        # Treat this error separate. Not allowed.
        #
	PAGEHEADER("Apply for Project Membership");
	USERERROR("The email address '$formfields[usr_email]' is already in ".
		  "use by another user.<br>Perhaps you have ".
		  "<a href='password.php3?email=$formfields[usr_email]'>".
		  "forgotten your username.</a>", 1);
    }
    if (! $forwikionly) {
	if (isset($formfields[usr_URL]) &&
	    strcmp($formfields[usr_URL], "") &&
	    strcmp($formfields[usr_URL], $HTTPTAG) &&
	    ! CHECKURL($formfields[usr_URL], $urlerror)) {
	    $errors["Home Page URL"] = $urlerror;
	}
	if (!isset($formfields[usr_addr]) ||
	    strcmp($formfields[usr_addr], "") == 0) {
	    $errors["Address 1"] = "Missing Field";
	}
	elseif (! TBvalid_addr($formfields[usr_addr])) {
	    $errors["Address 1"] = TBFieldErrorString();
	}
        # Optional
	if (isset($formfields[usr_addr2]) &&
	    !TBvalid_addr($formfields[usr_addr2])) {
	    $errors["Address 2"] = TBFieldErrorString();
	}
	if (!isset($formfields[usr_city]) ||
	    strcmp($formfields[usr_city], "") == 0) {
	    $errors["City"] = "Missing Field";
	}
	elseif (! TBvalid_city($formfields[usr_city])) {
	    $errors["City"] = TBFieldErrorString();
	}
	if (!isset($formfields[usr_state]) ||
	    strcmp($formfields[usr_state], "") == 0) {
	    $errors["State"] = "Missing Field";
	}
	elseif (! TBvalid_state($formfields[usr_state])) {
	    $errors["State"] = TBFieldErrorString();
	}
	if (!isset($formfields[usr_zip]) ||
	    strcmp($formfields[usr_zip], "") == 0) {
	    $errors["ZIP/Postal Code"] = "Missing Field";
	}
	elseif (! TBvalid_zip($formfields[usr_zip])) {
	    $errors["Zip/Postal Code"] = TBFieldErrorString();
	}
	if (!isset($formfields[usr_country]) ||
	    strcmp($formfields[usr_country], "") == 0) {
	    $errors["Country"] = "Missing Field";
	}
	elseif (! TBvalid_country($formfields[usr_country])) {
	    $errors["Country"] = TBFieldErrorString();
	}
	if (!isset($formfields[usr_phone]) ||
	    strcmp($formfields[usr_phone], "") == 0) {
	    $errors["Phone #"] = "Missing Field";
	}
	elseif (!TBvalid_phone($formfields[usr_phone])) {
	    $errors["Phone #"] = TBFieldErrorString();
	}
    }
    if (!isset($formfields[password1]) ||
	strcmp($formfields[password1], "") == 0) {
	$errors["Password"] = "Missing Field";
    }
    if (!isset($formfields[password2]) ||
	strcmp($formfields[password2], "") == 0) {
	$errors["Confirm Password"] = "Missing Field";
    }
    elseif (strcmp($formfields[password1], $formfields[password2])) {
	$errors["Confirm Password"] = "Does not match Password";
    }
    elseif (! CHECKPASSWORD($formfields[joining_uid],
			    $formfields[password1],
			    $formfields[usr_name],
			    $formfields[usr_email], $checkerror)) {
	$errors["Password"] = "$checkerror";
    }
}
if (!$forwikionly && (!isset($formfields[pid]) ||
		      strcmp($formfields[pid], "") == 0)) {
    $errors["Project Name"] = "Missing Field";
}

if (count($errors)) {
    SPITFORM($formfields, $returning, $errors);
    PAGEFOOTER();
    return;
}

#
# Certain of these values must be escaped or otherwise sanitized.
#
if (!$returning) {
    $joining_uid       = $formfields[joining_uid];
    $usr_name          = addslashes($formfields[usr_name]);
    $usr_email         = $formfields[usr_email];
    $password1         = $formfields[password1];
    $password2         = $formfields[password2];
    $wikiname          = ($WIKISUPPORT ? $formfields[wikiname] : "");

    if (!$forwikionly) {
	$usr_affil         = addslashes($formfields[usr_affil]);
	$usr_title         = addslashes($formfields[usr_title]);
	$usr_addr          = addslashes($formfields[usr_addr]);
	$usr_city          = addslashes($formfields[usr_city]);
	$usr_state         = addslashes($formfields[usr_state]);
	$usr_zip           = addslashes($formfields[usr_zip]);
	$usr_country       = addslashes($formfields[usr_country]);
	$usr_phone         = $formfields[usr_phone];
    }
    else {
	$usr_affil         = "";
	$usr_title         = "";
	$usr_addr          = "";
	$usr_city          = "";
	$usr_state         = "";
	$usr_zip           = "";
	$usr_country       = "";
	$usr_phone         = "";
    }

    if (! isset($formfields[usr_URL]) ||
	strcmp($formfields[usr_URL], "") == 0 ||
	strcmp($formfields[usr_URL], $HTTPTAG) == 0) {
	$usr_URL = "";
    }
    else {
	$usr_URL = addslashes($formfields[usr_URL]);
    }

    if (! isset($formfields[usr_addr2])) {
	$usr_addr2 = "";
    }
    else {
	$usr_addr2 = addslashes($formfields[usr_addr2]);
    }

    #
    # Pub Key.
    #
    if (isset($formfields[usr_key]) &&
	strcmp($formfields[usr_key], "")) {
        #
        # This is passed off to the shell, so taint check it.
        # 
	if (! preg_match("/^[-\w\s\.\@\+\/\=]*$/", $formfields[usr_key])) {
	    $errors["PubKey"] = "Invalid characters";
	}
	else {
            #
            # Replace any embedded newlines first.
            #
	    $formfields[usr_key] =
		ereg_replace("[\n]", "", $formfields[usr_key]);
	    $usr_key = $formfields[usr_key];
	    $addpubkeyargs = "-k $joining_uid '$usr_key' ";
	}
    }

    #
    # If usr provided a file for the key, it overrides the paste in text.
    #
    if (isset($_FILES['usr_keyfile']) &&
	$_FILES['usr_keyfile']['name'] != "" &&
	$_FILES['usr_keyfile']['name'] != "none") {

	$localfile = $_FILES['usr_keyfile']['tmp_name'];

	if (! stat($localfile)) {
	    $errors["PubKey File"] = "No such file";
	}
        # Taint check shell arguments always! 
	elseif (! preg_match("/^[-\w\.\/]*$/", $localfile)) {
	    $errors["PubKey File"] = "Invalid characters";
	}
	else {
	    $addpubkeyargs = "$joining_uid $usr_keyfile";
	    chmod($usr_keyfile, 0644);	
	}
    }
}
else {
    #
    # Grab info from the DB for the email message below. Kinda silly.
    #
    $query_result =
	DBQueryFatal("select * from users where uid='$joining_uid'");
    
    $row = mysql_fetch_array($query_result);
    
    $usr_title	= $row[usr_title];
    $usr_name	= $row[usr_name];
    $usr_affil	= $row[usr_affil];
    $usr_email	= $row[usr_email];
    $usr_addr	= $row[usr_addr];
    $usr_addr2	= $row[usr_addr2];
    $usr_city	= $row[usr_city];
    $usr_state	= $row[usr_state];
    $usr_zip	= $row[usr_zip];
    $usr_country= $row[usr_country];
    $usr_phone	= $row[usr_phone];
    $usr_URL    = $row[usr_URL];
}
$usr_expires  = date("Y:m:d", time() + (86400 * 120));
$pid          = $formfields[pid];

if (isset($formfields[gid]) && $formfields[gid] != "") {
    $gid = $formfields[gid];
}
else {
    $gid = $pid;
}

if (!$forwikionly) {
    if (!TBvalid_pid($pid) || !TBValidProject($pid)) {
	$errors["Project Name"] = "Invalid Project Name";
    }
    elseif (!TBvalid_gid($gid) || !TBValidGroup($pid, $gid)) {
	$errors["Group Name"] = "Invalid Group Name";
    }
    elseif (TBGroupMember($joining_uid, $pid, $gid, $approved)) {
	$errors["Membership"] = "You are already a member";
    }
}

#
# Verify key format.
#
if (isset($addpubkeyargs) &&
    ADDPUBKEY($joining_uid, "webaddpubkey -n $addpubkeyargs")) {
    $errors["Pubkey Format"] = "Could not be parsed. Is it a public key?";
}

if (count($errors)) {
    SPITFORM($formfields, $returning, $errors);
    PAGEFOOTER();
    return;
}

#
# For a new user:
# * Create a new account in the database.
# * Add user email to the list of email address.
# * Generate a mail message to the user with the verification key.
#
if (! $returning) {
    $encoding = crypt("$password1");

    #
    # Must be done before user record is inserted!
    # XXX Since user does not exist, must run as nobody. Script checks. 
    # 
    if (isset($addpubkeyargs)) {
	ADDPUBKEY($joining_uid, "webaddpubkey $addpubkeyargs");
    }

    # Initial mailman_password.
    $mailman_password = substr(GENHASH(), 0, 10);

    # Unique Unix UID.
    $unix_uid = TBGetUniqueIndex('next_uid');

    DBQueryFatal("INSERT INTO users ".
	"(uid,usr_created,usr_expires,usr_name,usr_email,usr_addr,".
	" usr_addr2,usr_city,usr_state,usr_zip,usr_country, ".
	" usr_URL,usr_phone,usr_shell,usr_title,usr_affil,usr_pswd,unix_uid,".
	" status,pswd_expires,usr_modified,wikionly,wikiname,".
	" mailman_password) ".
	"VALUES ('$joining_uid', now(), '$usr_expires', '$usr_name', ".
        "'$usr_email', ".
	"'$usr_addr', '$usr_addr2', '$usr_city', '$usr_state', '$usr_zip', ".
	"'$usr_country', ".
	"'$usr_URL', '$usr_phone', 'tcsh', '$usr_title', '$usr_affil', ".
        "'$encoding', $unix_uid, 'newuser', ".
	"date_add(now(), interval 1 year), now(), $forwikionly, '$wikiname', ".
	"'$mailman_password')");

    DBQueryFatal("INSERT INTO user_stats (uid, uid_idx) ".
		 "VALUES ('$joining_uid', $unix_uid)");

    $key = TBGenVerificationKey($joining_uid);

    TBMAIL("$usr_name '$joining_uid' <$usr_email>",
      "Your New User Key",
      "\n".
      "Dear $usr_name ($joining_uid):\n\n".
      "This is your account verification key: $key\n\n".
      "Please use this link to verify your user account:\n".
      "\n".
      "    ${TBBASE}/login.php3?vuid=$joining_uid&key=$key\n".
      "\n".
      ($forwikionly ?
       "Once you have verified your account, you will be able to access\n".
       "the Wiki. You MUST verify your account first!"
       :       
       "Once you have verified your account, the project leader will be\n".
       "able to approve you. You MUST verify your account before the project".
       "\n".
       "leader can approve you. After project approval, you will be\n".
       "marked as an active user, and will be granted full access to your\n".
       "user account.") .
      "\n\n".
      "Thanks,\n".
      "Testbed Operations\n",
      "From: $TBMAIL_APPROVAL\n".
      "Bcc: $TBMAIL_AUDIT\n".
      "Errors-To: $TBMAIL_WWW");
}

#
# For wikionly registration, we are done.
# 
if ($forwikionly) {
    header("Location: wikiregister.php3?finished=1");
    exit();
}

#
# Add to the group, but with trust=none. The project/group leader will have
# to upgrade the trust level, making the new user real.
#
$query_result =
    DBQueryFatal("insert into group_membership ".
		 "(uid,gid,pid,trust,date_applied) ".
		 "values ('$joining_uid','$gid','$pid','none', now())");

#
# This could be a new user or an old user trying to join a specific group
# in a project. If the user is new to the project too, then must insert
# a group_membership in the default group for the project. 
#
if (! TBGroupMember($joining_uid, $pid, $pid, $approved)) {
    DBQueryFatal("insert into group_membership ".
		 "(uid,gid,pid,trust,date_applied) ".
		 "values ('$joining_uid','$pid','$pid','none', now())");
}

#
# Generate an email message to the proj/group leaders.
#
$query_result =
    DBQueryFatal("select usr_name,usr_email,leader from users as u ".
		 "left join groups as g on u.uid=g.leader ".
		 "where g.pid='$pid' and g.gid='$gid'");
if (($row = mysql_fetch_row($query_result)) == 0) {
    TBERROR("DB Error getting email address for group leader $leader!", 1);
}
$leader_name = $row[0];
$leader_email = $row[1];
$leader_uid = $row[2];

$allleaders = TBLeaderMailList($pid,$gid);

#
# The mail message to the leader. We send this for returning users
# who are are also verified, since they could not use this page
# if they were not verified.
#
if ($returning) {
    TBMAIL("$leader_name '$leader_uid' <$leader_email>",
	   "$joining_uid $pid Project Join Request",
	   "$usr_name is trying to join your group $gid in project $pid.\n".
	   "\n".
	   "Contact Info:\n".
	   "Name:            $usr_name\n".
	   "Emulab ID:       $joining_uid\n".
	   "Email:           $usr_email\n".
	   "User URL:        $usr_URL\n".
	   "Title:           $usr_title\n".
	   "Affiliation:     $usr_affil\n".
	   "Address 1:       $usr_addr\n".
	   "Address 2:       $usr_addr2\n".
	   "City:            $usr_city\n".
	   "State:           $usr_state\n".
	   "ZIP/Postal Code: $usr_zip\n".
	   "Country:         $usr_country\n".
	   "Phone:           $usr_phone\n".
	   "\n".
	   "Please return to $TBWWW,\n".
	   "log in, and select the 'New User Approval' page to enter your\n".
	   "decision regarding $usr_name's membership in your project.\n\n".
	   "Thanks,\n".
	   "Testbed Operations\n",
	   "From: $TBMAIL_APPROVAL\n".
	   "Cc: $allleaders\n".
	   "Bcc: $TBMAIL_AUDIT\n".
	   "Errors-To: $TBMAIL_WWW");
}

#
# Spit out a redirect so that the history does not include a post
# in it. The back button skips over the post and to the form.
# See above for conclusion.
# 
header("Location: joinproject.php3?finished=1");
