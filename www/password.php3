<?php
#
# EMULAB-COPYRIGHT
# Copyright (c) 2000-2003 University of Utah and the Flux Group.
# All rights reserved.
#
include("defs.php3");

# Display a simpler version of this page
$simple = 0;
if (isset($_REQUEST['simple'])) {
    $simple = $_REQUEST['simple'];
}

# Form arguments.
$reset = $_POST['reset'];

# Might come from URL
$email = $_REQUEST['email'];
$phone = $_REQUEST['phone'];

#
# Turn off some of the decorations and menus for the simple view
#
if ($simple) {
    $view = array('hide_banner' => 1, 'hide_copyright' => 1,
	'hide_sidebar' => 1);
} else {
    $view = array();
}

# Must use https!
if (!isset($SSL_PROTOCOL)) {
    PAGEHEADER("Forgot Your Username or Password?", $view);
    USERERROR("Must use https:// to access this page!", 1);
}

#
# Must not be logged in.
# 
if (($known_uid = GETUID()) != FALSE) {
    if (CHECKLOGIN($known_uid) & CHECKLOGIN_LOGGEDIN) {
	PAGEHEADER("Forgot Your Username or Password?", $view);

	echo "<h3>
              You are logged in. You must already know your password!
              </h3>\n";

	PAGEFOOTER($view);
	die("");
    }
}

#
# Spit out the form.
# 
function SPITFORM($email, $phone, $failed, $simple, $view)
{
    global	$TBBASE;
    
    PAGEHEADER("Forgot Your Username or Password?", $view);

    if ($failed) {
	echo "<center>
              <font size=+1 color=red>
              The email/phone you provided does not match.
	      Please try again.
              </font>
              </center><br>\n";
    }
    else {
	echo "<center>
              <font size=+1>
              Please provide your email address and phone number.<br><br>
              </font>
              </center>\n";
    }

    echo "<table align=center border=1>
          <form action=${TBBASE}/password.php3 method=post>
          <tr>
              <td>Email Address:</td>
              <td><input type=text
                         value=\"$email\"
                         name=email size=30></td>
          </tr>
          <tr>
              <td>Phone Number:</td>
              <td><input type=text
                         value=\"$phone\"
                         name=phone size=20></td>
          </tr>
          <tr>
             <td align=center colspan=2>
                 <b><input type=submit value=\"Reset Password\"
                           name=reset></b>
                 <b><input type=submit value=\"Mail my Username\"
                           name=tellme></b>
             </td>
          </tr>\n";
    
    if ($simple) {
	echo "<input type=hidden name=simple value=$simple>\n";
    }

    echo "</form>
          </table>\n";

    echo "<br><blockquote>
          Please provide your phone number in standard dashed notation;
          no extensions or room numbers, etc. We will do our best to match it up
          against our user records.
          <br><br>
          If the email address and phone number you give us matches
          our user records, we will email a URL that will allow you to change
          your password.
          </blockquote>\n";
}

#
# If not clicked, then put up a form.
#
if (!isset($reset) && !isset($tellme)) {
    if (!isset($email))
	$email = "";
    if (!isset($phone))
	$phone = "";
    
    SPITFORM($email, $phone, 0, $simple, $view);
    return;
}

#
# Reset clicked. See if we find a user with the given email/phone. If not
# zap back to the form. 
#
if (!isset($phone) || $phone == "" || !TBvalid_phone($phone) ||
    !isset($email) || $email == "" || !TBvalid_email($email)) {
    SPITFORM($email, $phone, 1, $simple, $view);
    return;
}

$query_result =
    DBQueryFatal("select uid,usr_phone from users ".
		 "where LCASE(usr_email)=LCASE('$email')");

if (! mysql_num_rows($query_result)) {
    SPITFORM($email, $phone, 2, $simple, $view);
    return;
}
$row = mysql_fetch_row($query_result);
$uid = $row[0];
$usr_phone = $row[1];

#
# Compare phone by striping out anything but the numbers.
#
if (preg_replace("/[^0-9]/", "", $phone) !=
    preg_replace("/[^0-9]/", "", $usr_phone)) {
    SPITFORM($email, $phone, 3, $simple, $view);
    return;
}

TBUserInfo($uid, $uid_name, $uid_email);

#
# If just telling the user his account uid, send it and be done.
#
if (isset($tellme)) {
    PAGEHEADER("Forgot Your Username?", $view);
    
    TBMAIL("$uid_name <$uid_email>",
	   "Login ID requested by '$uid'",
	   "\n".
	   "Your Emulab login ID is '$uid'. Please use this ID when logging\n".
	   "in at ${TBBASE}.\n".
	   "\n".
	   "The request originated from IP: " . $_SERVER['REMOTE_ADDR'] . "\n".
	   "\n".
	   "Thanks,\n".
	   "Testbed Operations\n",
	   "From: $TBMAIL_OPS\n".
	   "Bcc: $TBMAIL_AUDIT\n".
	   "Errors-To: $TBMAIL_WWW");

    echo "<br>
          An email message has been sent to your account. In it you will find
          your login ID.\n";

    PAGEFOOTER();
    exit(0);
}

#
# Yep. Generate a random key and send the user an email message with a URL
# that will allow them to change their password. 
#
$key  = md5(uniqid(rand(),1));
$keyA = substr($key, 0, 16);
$keyB = substr($key, 16);

# Send half of the key to the browser and half in the email message.
setcookie($TBAUTHCOOKIE, $keyA, 0, "/",
	  $TBAUTHDOMAIN, $TBSECURECOOKIES);

# It is okay to spit this now that we have sent the cookie.
PAGEHEADER("Forgot Your Username or Password?", $view);

DBQueryFatal("update users set ".
	     "       chpasswd_key='$key', ".
	     "       chpasswd_expires=UNIX_TIMESTAMP(now())+(60*30) ".
	     "where uid='$uid'");

TBMAIL("$uid_name <$uid_email>",
       "Password Reset requested by '$uid'",
       "\n".
       "Here is your password reset authorization URL. Click on this link\n".
       "within the next 30 minutes, and you will be allowed to reset your\n".
       "password. If the link expires, you can request a new one from the\n".
       "web interface.\n".
       "\n".
       "    ${TBBASE}/chpasswd.php3?reset_uid=$uid&key=$keyB&simple=$simple\n".
       "\n".
       "The request originated from IP: " . $_SERVER['REMOTE_ADDR'] . "\n".
       "\n".
       "Thanks,\n".
       "Testbed Operations\n",
       "From: $TBMAIL_OPS\n".
       "Bcc: $TBMAIL_AUDIT\n".
       "Errors-To: $TBMAIL_WWW");

echo "<br>
      An email message has been sent to your account. In it you will find a
      URL that will allow you to change your password. The link will <b>expire 
      in 30 minutes</b>. If the link does expire before you have a chance to
      use it, simply come back and request a <a href='password.php3'>new one</a>.
      \n";

#
# Standard Testbed Footer
# 
PAGEFOOTER();
?>
