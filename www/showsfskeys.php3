<?php
#
# EMULAB-COPYRIGHT
# Copyright (c) 2000-2002 University of Utah and the Flux Group.
# All rights reserved.
#
include("defs.php3");
include("showstuff.php3");

#
# Only known and logged in users can do this.
#
$uid = GETLOGIN();
LOGGEDINORDIE($uid);
$isadmin = ISADMIN($uid);

#
# Verify form arguments.
# 
if (!isset($target_uid) ||
    strcmp($target_uid, "") == 0) {
    $target_uid = $uid;
}

#
# Check to make sure thats this is a valid UID.
#
if (! TBCurrentUser($target_uid)) {
    USERERROR("The user $target_uid is not a valid user", 1);
}

#
# Verify that this uid is a member of one of the projects that the
# target_uid is in. Must have proper permission in that group too. 
#
if (!$isadmin &&
    strcmp($uid, $target_uid)) {

    if (! TBUserInfoAccessCheck($uid, $target_uid, $TB_USERINFO_READINFO)) {
	USERERROR("You do not have permission to view ${user}'s keys!", 1);
    }
}

function SPITFORM($formfields, $errors)
{
    global $isadmin, $usr_keyfile_name, $target_uid, $BOSSNODE;

    #
    # Standard Testbed Header, now that we know what we want to say.
    #
    if (strcmp($uid, $target_uid)) {
	PAGEHEADER("SFS Public Keys for user: $target_uid");
    }
    else {
	PAGEHEADER("My SFS Public Keys");
    }

    #
    # Get the list and show it.
    #
    $query_result =
	DBQueryFatal("select * from user_sfskeys where uid='$target_uid'");

    if (mysql_num_rows($query_result)) {
	echo "<table align=center border=1 cellpadding=2 cellspacing=2>\n";

	echo "<center>
                Current sfs public keys for user $target_uid.
              </center><br>\n";

	echo "<tr>
                 <th>Delete?</th>
                 <th>Key</th>
              </tr>\n";

	while ($row = mysql_fetch_array($query_result)) {
	    $comment = $row[comment];
	    $pubkey  = $row[pubkey];
	    $date    = $row[stamp];
	    $fnote   = "";

	    if (strstr($comment, $OURDOMAIN)) {
		$fnote = "[<b>1</b>]";
	    }
	    $chunky  = chunk_split("$pubkey $comment $fnote", 75, "<br>\n");

	    echo "<tr>
                     <td align=center>
                       <A href='deletesfskey.php3?target_uid=$target_uid" .
	                  "&key=$comment'><img alt=X src=redball.gif></A>
                     </td>
                     <td>$chunky</td>
                  </tr>\n";
	}
	echo "</table>\n";
    }
    else {
	echo "<center>
             There are no sfs keys on file for user $target_uid!
             </center>\n";
    }
    echo "<blockquote><blockquote><blockquote>
          <ol>
            <li> Please do not delete your Emulab generated SFS public key.
          </ol>
          </blockquote></blockquote></blockquote>\n";

    echo "<br><hr size=4>\n";
    echo "<center>
          Enter sfs public keys for user ${target_uid}[<b>1</b>].
          </center><br>\n";

    if ($errors) {
	echo "<table class=stealth
                     align=center border=0 cellpadding=0 cellspacing=2>
              <tr>
                 <td class=stealth align=center colspan=3>
                   <font size=+1 color=red>
                      Oops, please fix the following errors!
                   </font>
                 </td>
              </tr>\n";

	while (list ($name, $message) = each ($errors)) {
	    echo "<tr>
                     <td class=stealth align=right>
                           <font color=red>$name:</font></td>
                     <td class=stealth>&nbsp</td>
                     <td class=stealth align=left>
                           <font color=red>$message</font></td>
                  </tr>\n";
	}
	echo "</table><br>\n";
    }

    echo "<table align=center border=1> 
          <form enctype=multipart/form-data
                action=showsfskeys.php3?target_uid=$target_uid method=post>\n";

    #
    # SFS public key
    # 
    echo "<tr>
              <td>Insert Public Key</td>
              <td><input type=text
                         name=\"formfields[usr_key]\"
                         value=\"$formfields[usr_key]\"
	                 size=70
	                 maxlength=1024>
              </td>
          </tr>\n";

    #
    # Verify with password.
    #
    if (!$isadmin) {
	echo "<tr>
                  <td>Password[<b>3</b>]:</td>
                  <td class=left>
                      <input type=password
                             name=\"formfields[password]\"
                             size=8></td>
              </tr>\n";
    }

    echo "<tr>
              <td colspan=2 align=center>
                 <b><input type=submit name=submit value='Add New Key'></b>
              </td>
          </tr>\n";

    echo "</form>
          </table>\n";

    echo "<blockquote><blockquote><blockquote>
          <ol>
            <li> Please consult our
                 <a href = 'docwrapper.php3?docname=security.html#SSH'>
                 security policies</a> for information
                 regarding ssh/sfs public keys.
            <li> Note to <a href=http://www.opera.com><b>Opera 5</b></a> users:
                 The file upload mechanism is broken in Opera, so you cannot
                 specify a local file for upload. Instead, please paste your
                 key in.
            <li> As a security precaution, you must supply your password
                 when adding new sfs public keys. 
          </ol>
          </blockquote></blockquote></blockquote>\n";

    echo "<font color=red>NOTE:</font> The SFS public key is somewhat
          difficult to find. Unlike SSH (where the public is kept in
          separate file), the SFS public key is contained in the same file
          as the private key. This means you have to go into the file and
          extract it so you can paste it into the form above. Yes, we could
          take the entire key file and extract it for you, but we would
          rather <b>NOT</b> see your private keys. So, if you read the key
          file (typically ~/.sfs/identity) into your favorite editor, you
          will see a number of comma (,) separated fields; we want the last
          two. Basically, we want to see something like this in the
          form when its posted:<br><br>
          <center>
	  0x17efcbd7bb0c2f7ffba6bd705236f6<b>,</b>yourname@yourserver.your.org
          </center>\n";
}

#
# On first load, display a form of current values.
#
if (! isset($submit) || isset($finished)) {
    $defaults = array();
    
    SPITFORM($defaults, 0);
    PAGEFOOTER();
    return;
}

#
# Otherwise, must validate and redisplay if errors
#
$errors  = array();
$matches = array();

if (isset($formfields[usr_key]) &&
    strcmp($formfields[usr_key], "")) {

    #
    # This is passed off to the shell, so taint check it.
    # 
    if (! preg_match("/^[\w\n\,\@\.]*$/", $formfields[usr_key])) {
	$errors["SFSKey"] = "Invalid characters";
    }
    else {
        #
        # Replace any embedded newlines first.
        #
	$formfields[usr_key] = ereg_replace("[\n]", "", $formfields[usr_key]);

	#
	# Must parse it and construct a key for the DB.
	#
	if (! preg_match("/(\w*),([-\w\@\.]*)/",
			 $formfields[usr_key], $matches)) {
	    $errors["SFSKey"] = "Invalid Key Format";
	}
	$pubkey  = $matches[1];
	$comment = $matches[2];
	$tag     = "$target_uid/" . substr(GENHASH(), 0, 8);
	$usr_key = "$tag:$pubkey:$target_uid::";

        #
        # Must verify passwd to add keys.
        #
	if (! $isadmin) {
	    if (!isset($formfields[password]) ||
		strcmp($formfields[password], "") == 0) {
		$errors["Password"] = "Must supply a verification password";
	    }
	    elseif (VERIFYPASSWD($target_uid, $formfields[password]) != 0) {
		$errors["Password"] = "Incorrect password";
	    }
	}
    }
}
else {
    $errors["Missing Args"] = "Please supply an SFS key";
}

# Spit the errors
if (count($errors)) {
    SPITFORM($formfields, $errors);
    PAGEFOOTER();
    return;
}

DBQueryFatal("replace into user_sfskeys ".
	     "values ('$target_uid', '$comment', '$usr_key', now())");

DBQueryFatal("update users set usr_modified=now() ".
	     "where uid='$target_uid'");

#
# Audit
#
TBUserInfo($uid, $uid_name, $uid_email);
TBUserInfo($target_uid, $targuid_name, $targuid_email);
$chunky = chunk_split("$usr_key $comment", 75, "\n");

TBMAIL("$targuid_name <$targuid_email>",
     "SFS Public Key for '$target_uid' Added",
     "\n".
     "SFS Public Key for '$target_uid' added by '$uid'.\n".
     "\n".
     "$chunky\n".
     "\n".
     "Thanks,\n".
     "Testbed Ops\n".
     "Utah Network Testbed\n",
     "From: $uid_name <$uid_email>\n".
     "Cc: $TBMAIL_AUDIT\n".
     "Errors-To: $TBMAIL_WWW");

#
# mkacct arranges for nodes to be updated.
#
#SUEXEC($uid, $TBADMINGROUP, "webmkacct -a $target_uid", 0);

header("Location: showsfskeys.php3?target_uid=$target_uid&finished=1");
?>
