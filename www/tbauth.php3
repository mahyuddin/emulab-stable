<?php
#
# EMULAB-COPYRIGHT
# Copyright (c) 2000-2003 University of Utah and the Flux Group.
# All rights reserved.
#
#
# Login support: Beware empty spaces (cookies)!
#

# These global are to prevent repeated calls to the DB. 
#
$CHECKLOGIN_STATUS		= -1;
$CHECKLOGIN_UID			= 0;
$CHECKLOGIN_NOLOGINS		= -1;

#
# New Mapping. 
#
define("CHECKLOGIN_NOSTATUS",		-1);
define("CHECKLOGIN_NOTLOGGEDIN",	0);
define("CHECKLOGIN_LOGGEDIN",		1);
define("CHECKLOGIN_TIMEDOUT",		2);
define("CHECKLOGIN_MAYBEVALID",		4);
define("CHECKLOGIN_STATUSMASK",		0x000ff);
define("CHECKLOGIN_MODMASK",		0xfff00);
#
# These are modifiers of the above status fields. They are stored
# as a bit field in the top part. This is intended to localize as
# many queries related to login as possible. 
#
define("CHECKLOGIN_NEWUSER",		0x00100);
define("CHECKLOGIN_UNVERIFIED",		0x00200);
define("CHECKLOGIN_UNAPPROVED",		0x00400);
define("CHECKLOGIN_ACTIVE",		0x00800);
define("CHECKLOGIN_USERSTATUS",		0x00f00);
define("CHECKLOGIN_PSWDEXPIRED",	0x01000);
define("CHECKLOGIN_FROZEN",		0x02000);
define("CHECKLOGIN_ISADMIN",		0x04000);
define("CHECKLOGIN_TRUSTED",		0x08000);
define("CHECKLOGIN_CVSWEB",		0x10000);
define("CHECKLOGIN_ADMINOFF",		0x20000);
define("CHECKLOGIN_WEBONLY",		0x40000);
define("CHECKLOGIN_PLABUSER",		0x80000);

#
# Constants for tracking possible login attacks.
#
define("DOLOGIN_MAXUSERATTEMPTS",	15);
define("DOLOGIN_MAXIPATTEMPTS",		25);

#
# Generate a hash value suitable for authorization. We use the results of
# microtime, combined with a random number.
# 
function GENHASH() {
    $fp = fopen("/dev/urandom", "r");
    if (! $fp) {
        TBERROR("Error opening /dev/urandom", 1);
    }
    $random_bytes = fread($fp, 128);
    fclose($fp);

    $hash  = mhash (MHASH_MD5, bin2hex($retval) . " " . microtime());
    return bin2hex($hash);
}

#
# Return the value of the currently logged in uid, or null if not
# logged in. Basically, check the browser to see if its sending a UID
# and HASH back, and then check the DB to see if the user is really
# logged in.
# 
function GETLOGIN() {
    if (($uid = GETUID()) == FALSE)
	    return FALSE;

    $check = CHECKLOGIN($uid);

    if ($check & (CHECKLOGIN_LOGGEDIN|CHECKLOGIN_MAYBEVALID))
	    return $uid;

    return FALSE;
}

#
# Return the value of the UID cookie. This does not check to see if
# this person is currently logged in. We just want to know what the
# browser thinks, if anything.
# 
function GETUID() {
    global $TBNAMECOOKIE;
    global $nocookieuid;

    $curname = FALSE;

    # XXX - nocookieuid is sent by netbuild applet in URL.
    if (isset($_GET['nocookieuid'])) {
	$curname = $_GET['nocookieuid'];
    }
    elseif (isset($_COOKIE[$TBNAMECOOKIE])) {
	$curname = $_COOKIE[$TBNAMECOOKIE];
    }
    else
	return FALSE;

    # Verify valid string (no special chars like single/double quotes!).
    # We do not use the standard check function here, since we want to
    # avoid a DB access on each page until its required. Thats okay since
    # since we just need to ensure that we feed to the DB query is safe.
    if (! preg_match("/^[-\w]+$/", $curname)) {
	return FALSE;
    }
    return $curname;
}

#
# Verify a login by sucking a UIDs current hash value out of the database.
# If the login has expired, or of the hashkey in the database does not
# match what came back in the cookie, then the UID is no longer logged in.
#
# Returns a combination of the CHECKLOGIN values above.
#
function CHECKLOGIN($uid) {
    global $TBAUTHCOOKIE, $TBLOGINCOOKIE, $HTTP_COOKIE_VARS, $TBAUTHTIMEOUT;
    global $CHECKLOGIN_STATUS, $CHECKLOGIN_UID;
    global $nocookieauth;
    #
    # If we already figured this out, do not duplicate work!
    #
    if ($CHECKLOGIN_STATUS != CHECKLOGIN_NOSTATUS) {
	return $CHECKLOGIN_STATUS;
    }
    $CHECKLOGIN_UID = $uid;

    # for java applet, we can send the key in the $auth variable,
    # rather than passing it is a cookie.
    if (isset($nocookieauth)) {
	$curhash = $nocookieauth;
    } else {
	$curhash = $HTTP_COOKIE_VARS[$TBAUTHCOOKIE];
    }
    
    #
    # Note that we get multiple rows back because of the group_membership
    # join. No big deal.
    # 
    $query_result =
	DBQueryFatal("select NOW()>=u.pswd_expires,l.hashkey,l.timeout, ".
		     "       status,admin,cvsweb,g.trust,adminoff,webonly, " .
		     "       plab_user " .
		     " from users as u ".
		     "left join login as l on l.uid=u.uid ".
		     "left join group_membership as g on g.uid=u.uid ".
		     "where u.uid='$uid'");

    # No such user.
    if (! mysql_num_rows($query_result)) { 
	$CHECKLOGIN_STATUS = CHECKLOGIN_NOTLOGGEDIN;
	return $CHECKLOGIN_STATUS;
    }
    
    #
    # Scan the rows. All the info is duplicate, except for the trust
    # values. 
    #
    $trusted = 0;
    while ($row = mysql_fetch_array($query_result)) {
	$expired = $row[0];
	$hashkey = $row[1];
	$timeout = $row[2];
	$status  = $row[3];
	$admin   = $row[4];
	$cvsweb  = $row[5];

	if (! strcmp($row[6], "project_root") ||
	    ! strcmp($row[6], "group_root")) {
	    $trusted = 1;
	}
	$adminoff = $row[7];
	$webonly  = $row[8];
	$plab     = $row[9];
    }

    #
    # If user exists, but login has no entry, quit now.
    #
    if (!$hashkey) {
	$CHECKLOGIN_STATUS = CHECKLOGIN_NOTLOGGEDIN;
	return $CHECKLOGIN_STATUS;
    }

    #
    # Check for frozen account. Might do something interesting later.
    #
    if (! strcmp($status, TBDB_USERSTATUS_FROZEN)) {
	DBQueryFatal("DELETE FROM login WHERE uid='$uid'");
	$CHECKLOGIN_STATUS = CHECKLOGIN_NOTLOGGEDIN;
	return $CHECKLOGIN_STATUS;
    }

    #
    # Check for expired login. It does not matter if the cookie matches,
    # kill the entry anyway so the user is officially logged out.
    #
    if (time() > $timeout) {
	DBQueryFatal("DELETE FROM login WHERE uid='$uid'");
	$CHECKLOGIN_STATUS = CHECKLOGIN_TIMEDOUT;
	return $CHECKLOGIN_STATUS;
    }

    #
    # We know the login has not expired. The problem is that we might not
    # have received a cookie since that is set to transfer only when using
    # https. However, we do not want the menu to be flipping back and forth
    # each time the user uses http (say, for documentation), and so the lack
    # of a cookie does not provide enough info to determine if the user is
    # logged in or not from the current browser. Also, we want to allow for
    # a user to switch browsers, and not get confused by getting a uid but
    # no valid cookie from the new browser. In that case the user should just
    # be able to login from the new browser; gets a standard not-logged-in
    # front page. In order to accomplish this, we need another cookie that is
    # set on login, cleared on logout.
    #
    if (isset($curhash)) {
	#
	# Got a cookie (https).
	#
	if ($curhash != $hashkey) {
	    #
	    # User is not logged in from this browser. Must be stale.
	    # 
	    $CHECKLOGIN_STATUS = CHECKLOGIN_NOTLOGGEDIN;
	    return $CHECKLOGIN_STATUS;
	}
	else {
            #
	    # User is logged in. Update the time in the database.
	    # Basically, each time the user does something, we bump the
	    # logout further into the future. This avoids timing them
	    # out just when they are doing useful work.
            #
	    $timeout = time() + $TBAUTHTIMEOUT;

	    DBQueryFatal("UPDATE login set timeout='$timeout' ".
			 "WHERE uid='$uid'");

	    $CHECKLOGIN_STATUS = CHECKLOGIN_LOGGEDIN;
	}
    }
    else {
	#
	# No cookie. Might be because its http, so there is no way to tell
	# if user is not logged in from the current browser without more
	# information. We use another cookie for this, which is a crc of
	# of the real hash, and simply tells us what menu to draw, but does
	# not impart any privs!
	#
	$hashhash = $HTTP_COOKIE_VARS[$TBLOGINCOOKIE];
	
	if (isset($hashhash) &&
	    $hashhash == bin2hex(mhash(MHASH_CRC32, $hashkey))) {
            #
            # The login is probably valid, but we have no proof yet. 
            #
	    $CHECKLOGIN_STATUS = CHECKLOGIN_MAYBEVALID;
	}
	else {
	    #
	    # No hash of the hash, so assume no real cookie either. 
	    # 
	    $CHECKLOGIN_STATUS = CHECKLOGIN_NOTLOGGEDIN;
	    return $CHECKLOGIN_STATUS;
	}
    }

    #
    # Now add in the modifiers.
    #
    if ($expired)
	$CHECKLOGIN_STATUS |= CHECKLOGIN_PSWDEXPIRED;
    if ($admin)
	$CHECKLOGIN_STATUS |= CHECKLOGIN_ISADMIN;
    if ($adminoff)
	$CHECKLOGIN_STATUS |= CHECKLOGIN_ADMINOFF;
    if ($webonly)
	$CHECKLOGIN_STATUS |= CHECKLOGIN_WEBONLY;
    if ($trusted)
	$CHECKLOGIN_STATUS |= CHECKLOGIN_TRUSTED;
    if ($cvsweb)
	$CHECKLOGIN_STATUS |= CHECKLOGIN_CVSWEB;
    if ($plab)
	$CHECKLOGIN_STATUS |= CHECKLOGIN_PLABUSER;
    if (strcmp($status, TBDB_USERSTATUS_NEWUSER) == 0)
	$CHECKLOGIN_STATUS |= CHECKLOGIN_NEWUSER;
    if (strcmp($status, TBDB_USERSTATUS_UNAPPROVED) == 0)
	$CHECKLOGIN_STATUS |= CHECKLOGIN_UNAPPROVED;
    if (strcmp($status, TBDB_USERSTATUS_UNVERIFIED) == 0)
	$CHECKLOGIN_STATUS |= CHECKLOGIN_UNVERIFIED;
    if (strcmp($status, TBDB_USERSTATUS_ACTIVE) == 0)
	$CHECKLOGIN_STATUS |= CHECKLOGIN_ACTIVE;

    #
    # Set the magic enviroment variable, if appropriate, for the sake of
    # any processes we might spawn. We prepend an HTTP_ on the front of
    # the variable name, so that it will get through suexec.
    #
    if ($admin && !$adminoff) {
    	putenv("HTTP_WITH_TB_ADMIN_PRIVS=1");
    }

    return $CHECKLOGIN_STATUS;
}

#
# This one checks for login, but then dies with an appropriate error
# message. The modifier allows you to turn off checks for specified
# conditions. 
#
function LOGGEDINORDIE($uid, $modifier = 0, $login_url = NULL) {
    global $TBBASE, $BASEPATH, $HTTP_COOKIE_VARS, $TBNAMECOOKIE;

    # If our login is not valid, then the uid is already set to "",
    # so refresh it to the cookie value. Then we can pass the right
    # uid to hcecklogin, so we can give the right error message.
    if ($uid=="") { $uid=$HTTP_COOKIE_VARS[$TBNAMECOOKIE]; }

    #
    # Allow the caller to specify a different URL to direct the user
    # to
    #
    if (!$login_url) {
	$login_url = "$TBBASE/login.php3?refer=1";
    }

    $link = "\n<a href=\"$login_url\">Please ".
	"log in again.</a>\n";

    if ($uid == FALSE)
        USERERROR("You do not appear to be logged in! $link", 1);
    
    $status = CHECKLOGIN($uid);

    switch ($status & CHECKLOGIN_STATUSMASK) {
    case CHECKLOGIN_NOTLOGGEDIN:
        USERERROR("You do not appear to be logged in! $link", 1);
        break;
    case CHECKLOGIN_TIMEDOUT:
        USERERROR("Your login has timed out! $link", 1);
        break;
    case CHECKLOGIN_MAYBEVALID:
        USERERROR("Your login cannot be verified. Are cookies turned on? ".
		  "Are you using https? Are you logged in using another ".
		  "browser or another machine? $link", 1);
        break;
    case CHECKLOGIN_LOGGEDIN:
	break;
    default:
	TBERROR("LOGGEDINORDIE failed mysteriously", 1);
    }

    $status = $status & ~$modifier;

    #
    # Check other conditions.
    #
    if ($status & CHECKLOGIN_PSWDEXPIRED)
        USERERROR("Your password has expired. ".
		  "<a href=moduserinfo.php3>Please change it now!</a>", 1);
    if ($status & CHECKLOGIN_FROZEN)
        USERERROR("Your account has been frozen!", 1);
    if ($status & (CHECKLOGIN_UNVERIFIED|CHECKLOGIN_NEWUSER))
        USERERROR("You have not verified your account yet!", 1);
    if ($status & CHECKLOGIN_UNAPPROVED)
        USERERROR("Your account has not been approved yet!", 1);
    if ($status & CHECKLOGIN_WEBONLY)
        USERERROR("Your account does not permit you to access this page!", 1);

    #
    # Lastly, check for nologins here. This heads off a bunch of other
    # problems and checks we would need.
    #
    if (NOLOGINS() && !ISADMIN($uid))
        USERERROR("Sorry. The Web Interface is ".
		  "<a href=nologins.php3>Temporarily Unavailable!</a>", 1);

    return $uid;
}

#
# Is this user an admin type, and is his admin bit turned on.
# Its actually incorrect to look at the $uid. Its the currently logged
# in user that has to be admin. So ignore the uid and make sure
# there is a login status.
#
function ISADMIN($uid = 1) {
    global $CHECKLOGIN_STATUS;
    
    if ($CHECKLOGIN_STATUS == CHECKLOGIN_NOSTATUS) {
	$uid=GETUID();
	TBERROR("ISADMIN: $uid is not logged in!", 1);
    }

    return (($CHECKLOGIN_STATUS &
	     (CHECKLOGIN_LOGGEDIN|CHECKLOGIN_ISADMIN|CHECKLOGIN_ADMINOFF)) ==
	    (CHECKLOGIN_LOGGEDIN|CHECKLOGIN_ISADMIN));
}

# Is this user a real administrator (ignore onoff bit).
function ISADMINISTRATOR() {
    global $CHECKLOGIN_STATUS;
    
    if ($CHECKLOGIN_STATUS == CHECKLOGIN_NOSTATUS)
	TBERROR("ISADMIN: $uid is not logged in!", 1);

    return (($CHECKLOGIN_STATUS &
	     (CHECKLOGIN_LOGGEDIN|CHECKLOGIN_ISADMIN)) ==
	    (CHECKLOGIN_LOGGEDIN|CHECKLOGIN_ISADMIN));
}

# Is this user a planetlab user? Returns 1 if they are, 0 if not.
function ISPLABUSER() {
    global $CHECKLOGIN_STATUS;

    if ($CHECKLOGIN_STATUS == CHECKLOGIN_NOSTATUS) {
	#
	# For users who are not logged in, we need to check the database
	#
	$uid = GETUID();
	if (!$uid) {
	    return 0;
	}
	$query_result =
	    DBQueryFatal("SELECT plab_user FROM users WHERE uid='$uid'");
	if (!mysql_num_rows($query_result)) {
	    return 0;
	}

	$row = mysql_fetch_row($query_result);
	if ($row[0]) {
	    return 1;
	} else {
	    return 0;
	}
    } else {
	#
	# For logged-in users, we recorded it in the the login status
	#
	return (($CHECKLOGIN_STATUS &
		 (CHECKLOGIN_LOGGEDIN|CHECKLOGIN_PLABUSER)) ==
		(CHECKLOGIN_LOGGEDIN|CHECKLOGIN_PLABUSER));
    }
}

#
# Attempt a login.
# 
function DOLOGIN($token, $password, $adminmode = 0) {
    global $TBAUTHCOOKIE, $TBAUTHDOMAIN, $TBAUTHTIMEOUT;
    global $TBNAMECOOKIE, $TBLOGINCOOKIE, $TBSECURECOOKIES;
    global $TBMAIL_OPS, $TBMAIL_AUDIT, $TBMAIL_WWW;
    
    # Caller makes these checks too.
    if ((!TBvalid_uid($token) && !TBvalid_email($token)) ||
	!isset($password) || $password == "") {
	return -1;
    }
    $now = time();

    #
    # Check for a frozen IP address; too many failures.
    #
    unset($iprow);
    unset($IP);
    if (isset($_SERVER['REMOTE_ADDR'])) {
	$IP = $_SERVER['REMOTE_ADDR'];
	
	$ip_result =
	    DBQueryFatal("select * from login_failures ".
			 "where IP='$IP'");

	if ($iprow = mysql_fetch_array($ip_result)) {
	    $ipfrozen = $iprow['frozen'];

	    if ($ipfrozen) {
		DBQueryFatal("update login_failures set ".
			     "       failcount=failcount+1, ".
			     "       failstamp='$now' ".
			     "where IP='$IP'");
		return -1;
	    }
	}
    }

    $user_result =
	DBQueryFatal("select uid,usr_pswd,admin,weblogin_frozen,".
		     "       weblogin_failcount,weblogin_failstamp, ".
		     "       usr_email,usr_name ".
		     "from users where ".
		     (TBvalid_email($token) ?
		      "usr_email='$token'" :
		      "uid='$token'"));

    #
    # Check password in the database against provided. 
    #
    do {
      if ($row = mysql_fetch_array($user_result)) {
	$uid         = $row['uid'];
        $db_encoding = $row['usr_pswd'];
	$isadmin     = $row['admin'];
	$frozen      = $row['weblogin_frozen'];
	$failcount   = $row['weblogin_failcount'];
	$failstamp   = $row['weblogin_failstamp'];
	$usr_email   = $row['usr_email'];
	$usr_name    = $row['usr_name'];

	# Check for frozen accounts. We do not update the IP record when
	# an account is frozen.
	if ($frozen) {
	    DBQueryFatal("update users set ".
			 "       weblogin_failcount=weblogin_failcount+1, ".
			 "       weblogin_failstamp='$now' ".
			 "where uid='$uid'");
	    return -1;
	}
	
        $encoding = crypt("$password", $db_encoding);
        if (strcmp($encoding, $db_encoding)) {
	    #
	    # Bump count and check for too many consecutive failures.
	    #
	    $failcount++;
	    if ($failcount > DOLOGIN_MAXUSERATTEMPTS) {
		$frozen = 1;
	    
		TBMAIL("$usr_name '$uid' <$usr_email>",
		   "Web Login Freeze: '$uid'",
		   "Your login has been frozen because there were too many\n".
		   "login failures from " . $_SERVER['REMOTE_ADDR'] . ".\n\n".
		   "Testbed Operations has been notified.\n",
		   "From: $TBMAIL_OPS\n".
		   "Cc: $TBMAIL_OPS\n".
		   "Bcc: $TBMAIL_AUDIT\n".
		   "Errors-To: $TBMAIL_WWW");
	    }

	    DBQueryFatal("update users set weblogin_frozen='$frozen', ".
			 "       weblogin_failcount='$failcount', ".
			 "       weblogin_failstamp='$now' ".
			 "where uid='$uid'");
            break;
        }
        #
        # Pass! Insert a record in the login table for this uid with
        # the new hash value. If the user is already logged in, thats
        # okay; just update it in place with a new hash and timeout. 
        #
	$timeout = $now + $TBAUTHTIMEOUT;
	$hashkey = GENHASH();
        $query_result =
	    DBQueryFatal("SELECT timeout FROM login WHERE uid='$uid'");
	
	if (mysql_num_rows($query_result)) {
	    DBQueryFatal("UPDATE login set ".
			 "timeout='$timeout', hashkey='$hashkey' ".
			 "WHERE uid='$uid'");
	}
	else {
	    DBQueryFatal("INSERT into login (uid, hashkey, timeout) ".
			 "VALUES ('$uid', '$hashkey', '$timeout')");
	}

	#
	# Usage stats. 
	#
	DBQueryFatal("update user_stats set ".
		     " weblogin_count=weblogin_count+1, ".
		     " weblogin_last=now() ".
		     "where uid='$uid'");

	#
	# Issue the cookie requests so that subsequent pages come back
	# with the hash value and auth usr embedded.

	#
	# For the hashkey, we use a zero timeout so that the cookie is
	# a session cookie; killed when the browser is exited. Hopefully this
	# keeps the key from going to disk on the client machine. The cookie
	# lives as long as the browser is active, but we age the cookie here
	# at the server so it will become invalid at some point.
	#
	setcookie($TBAUTHCOOKIE, $hashkey, 0, "/",
                  $TBAUTHDOMAIN, $TBSECURECOOKIES);

	#
	# Another cookie, to help in menu generation. See above in
	# checklogin. This cookie is a simple hash of the real hash,
	# intended to indicate if the current browser holds a real hash.
	# All this does is change the menu options presented, imparting
	# no actual privs. 
	#
	$crc = bin2hex(mhash(MHASH_CRC32, $hashkey));
	setcookie($TBLOGINCOOKIE, $crc, 0, "/", $TBAUTHDOMAIN, 0);

	#
	# We give this a really long timeout. We want to remember who the
	# the user was each time they load a page, and more importantly,
	# each time they come back to the main page so we can fill in their
	# user name. NOTE: This cookie is integral to authorization, since
	# we do not pass around the UID anymore, but look for it in the
	# cookie.
	# 
	$timeout = $now + (60 * 60 * 24 * 32);
	setcookie($TBNAMECOOKIE, $uid, $timeout, "/", $TBAUTHDOMAIN, 0);

	#
	# Set adminoff on new logins, unless user requested to be
	# logged in as admin (and is an admin of course!). This is
	# primarily to bypass the nologins directive which makes it
	# impossible for an admin to login when the web interface is
	# turned off. 
	#
	$adminoff = 1;
	if ($adminmode && $isadmin) {
	    $adminoff = 0;
	}
	DBQueryFatal("update users set adminoff=$adminoff, ".
		     "       weblogin_failcount=0,weblogin_failstamp=0 ".
		     "where uid='$uid'");

	# Clear IP record since we have a sucessful login from the IP.
	if (isset($IP)) {
	    DBQueryFatal("delete from login_failures where IP='$IP'");
	}
	return 0;
      }
    } while (0);
    #
    # No such user
    #
    if (!isset($IP)) {
	return -1;
    }
	
    $ipfrozen = 0;
    if (isset($iprow)) {
	$ipfailcount = $iprow['failcount'];

        #
        # Bump count.
        #
	$ipfailcount++;
    }
    else {
	#
	# First failure.
	# 
	$ipfailcount = 1;
    }

    #
    # Check for too many consecutive failures.
    #
    if ($ipfailcount > DOLOGIN_MAXIPATTEMPTS) {
	$ipfrozen = 1;
	    
	TBMAIL($TBMAIL_OPS,
	       "Web Login Freeze: '$IP'",
	       "Logins has been frozen because there were too many login\n".
	       "failures from $IP. Last attempted uid was '$token'.\n\n",
	       "From: $TBMAIL_OPS\n".
	       "Bcc: $TBMAIL_AUDIT\n".
	       "Errors-To: $TBMAIL_WWW");
    }
    DBQueryFatal("replace into login_failures set ".
		 "       IP='$IP', ".
		 "       frozen='$ipfrozen', ".
		 "       failcount='$ipfailcount', ".
		 "       failstamp='$now'");
    return -1;
}


#
# Verify a password
# 
function VERIFYPASSWD($uid, $password) {
    if (! isset($password) ||
	strcmp($password, "") == 0) {
	return -1;
    }

    $query_result =
	DBQueryFatal("SELECT usr_pswd FROM users WHERE uid='$uid'");

    #
    # Check password in the database against provided. 
    #
    if ($row = mysql_fetch_row($query_result)) {
        $db_encoding = $row[0];
        $encoding = crypt("$password", $db_encoding);
	
        if (strcmp($encoding, $db_encoding)) {
            return -1;
	}
	return 0;
    }
    return -1;
}

#
# Log out a UID.
#
function DOLOGOUT($uid) {
    global $CHECKLOGIN_STATUS, $TBAUTHCOOKIE, $TBLOGINCOOKIE, $TBAUTHDOMAIN;

    # Pedantic check.
    if (!TBvalid_uid($uid)) {
	return 1;
    }

    $CHECKLOGIN_STATUS = CHECKLOGIN_NOTLOGGEDIN;

    $query_result =
	DBQueryFatal("SELECT hashkey timeout FROM login WHERE uid='$uid'");

    # Not logged in.
    if (($row = mysql_fetch_array($query_result)) == 0) {
	return 1;
    }

    $hashkey = $row[hashkey];
    $timeout = time() - 1000000;

    DBQueryFatal("DELETE FROM login WHERE uid='$uid'");

    #
    # Issue a cookie request to delete the cookies. 
    #
    setcookie($TBAUTHCOOKIE, "", $timeout, "/", $TBAUTHDOMAIN, 0);
    setcookie($TBLOGINCOOKIE, "", $timeout, "/", $TBAUTHDOMAIN, 0);

    return 0;
}

#
# Simple "nologins" support.
#
function NOLOGINS() {
    global $CHECKLOGIN_NOLOGINS;

    if ($CHECKLOGIN_NOLOGINS == -1) {
	$CHECKLOGIN_NOLOGINS = TBGetSiteVar("web/nologins");
    }
	
    return $CHECKLOGIN_NOLOGINS;
}

function LASTWEBLOGIN($uid) {
    global $TBDBNAME;

    $query_result =
        DBQueryFatal("SELECT weblogin_last from user_stats where uid='$uid'");
    
    if (mysql_num_rows($query_result)) {
	$lastrow      = mysql_fetch_array($query_result);
	return $lastrow[weblogin_last];
    }
    return 0;
}

function HASREALACCOUNT($uid) {
    $query_result =
	DBQueryFatal("select status,webonly from users where uid='$uid'");

    if (!mysql_num_rows($query_result)) {
	return 0;
    }
    $row = mysql_fetch_array($query_result);
    $status  = $row[0];
    $webonly = $row[1];

    if ($webonly ||
	(strcmp($status, TBDB_USERSTATUS_ACTIVE) &&
	 strcmp($status, TBDB_USERSTATUS_FROZEN))) {
	return 0;
    }
    return 1;
}

#
# Beware empty spaces (cookies)!
# 
?>
