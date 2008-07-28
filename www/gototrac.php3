<?php
#
# EMULAB-COPYRIGHT
# Copyright (c) 2000-2008 University of Utah and the Flux Group.
# All rights reserved.
#
include("defs.php3");

if (!$TRACSUPPORT) {
    header("Location: index.php3");
    return;
}

# No Pageheader since we spit out a redirection below.
$this_user = CheckLoginOrDie();
$uid       = $this_user->uid();

# The user has to be approved, real account.
if (!HASREALACCOUNT($uid)) {
    USERERROR("You may not login to the Emulab Wiki until your account ".
	      "has been approved and is active.", 1);
}

#
# Verify page arguments. project_title is the project to zap to.
#
$optargs = OptionalPageArguments("wiki",  PAGEARG_STRING,
				 "login", PAGEARG_BOOLEAN,
				 "do",    PAGEARG_STRING);
				 
if (!isset($wiki)) {
    $wiki = "emulab";
}
if (!isset($login)) {
    $login = 0;
}

if ($wiki == "geni" || $wiki == "protogeni") {
    $geniproject = Project::Lookup("geni");
    $approved    = 0;
    if (! ($geniproject &&
	   $geniproject->IsMember($this_user, $approved) && $approved)) {
	USERERROR("You do not have permission to access the Trac wiki!", 1);
    }
    $wiki    = "protogeni";
    $TRACURL    = "https://www.protogeni.net/trac/$wiki";
    $COOKIENAME = "trac_auth_protogeni_priv";
}
elseif ($wiki != "emulab") {
    USERERROR("Unknown Trac wiki $wiki!", 1);
}
else {
    $TRACURL    = "https://${USERNODE}/trac/$wiki";
    $COOKIENAME = "trac_auth_${wiki}";
}

#
# Look for our cookie. If the browser has it, then there is nothing
# more to do; just redirect the user over to the wiki.
#
if (!$login && isset($_COOKIE[$COOKIENAME])) {
    $url = $TRACURL;
    if (isset($do)) {
	$url .= "/" . $do;
    }
    header("Location: $url");
    return;
}

#
# Do the xlogin, which gives us back a hash to stick in the cookie.
#
SUEXEC($uid, "nobody", "tracxlogin -w " . escapeshellarg($wiki) .
       " $uid " . $_SERVER['REMOTE_ADDR'], SUEXEC_ACTION_DIE);

if (!preg_match("/^(\w*)$/", $suexec_output, $matches)) {
    TBERROR($suexec_output, 1);
}
$hash = $matches[1];

setcookie($COOKIENAME, $hash, 0, "/", $TBAUTHDOMAIN, $TBSECURECOOKIES);

header("Location: ${TRACURL}/xlogin?user=$uid&hash=$hash" .
       (isset($do) ? "&goto=${do}" : ""));

