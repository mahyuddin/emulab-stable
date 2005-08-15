<?php
#
# EMULAB-COPYRIGHT
# Copyright (c) 2005 University of Utah and the Flux Group.
# All rights reserved.
#
include("defs.php3");

#
# No Testbed Header; we zap back.
#

#
# Only known and logged in users.
#
$uid = GETLOGIN();
LOGGEDINORDIE($uid);
$isadmin = ISADMIN($uid);

#
# First off, sanity check page args.
#
if (!isset($listname) ||
    strcmp($listname, "") == 0) {
    USERERROR("Must provide a Listname!", 1);
}
if (! TBvalid_mailman_listname($listname)) {
    PAGEARGERROR("Invalid characters in $listname!");
}

#
# Grab the DB state.
#
$query_result = DBQueryFatal("select * from mailman_listnames ".
			     "where listname='$listname'");

if (!mysql_num_rows($query_result)) {
    USERERROR("No such list $listname!", 1);
}
$row = mysql_fetch_array($query_result);
$owner_uid = $row['owner_uid'];

#
# Verify permission.
#
if ($uid != $owner_uid && !$isadmin) {
    USERERROR("You do not have permission to delete list $listname!", 1);
}

#
# We run this twice. The first time we are checking for a confirmation
# by putting up a form. The next time through the confirmation will be
# set. Or, the user can hit the cancel button, in which case we should
# probably redirect the browser back up a level.
#
if ($canceled) {
    PAGEHEADER("Delete a Mailman List");
    
    echo "<center><h2>
          List removal canceled!
          </h2></center>\n";
    
    PAGEFOOTER();
    return;
}

if (!$confirmed) {
    PAGEHEADER("Delete a Mailman List");
    
    echo "<center><h2>
          Are you <b>REALLY</b> sure you want to remove $listname
          </h2>\n";
    
    echo "<form action='delmmlist.php3?listname=$listname' method=post>";
    echo "<b><input type=submit name=confirmed value=Confirm></b>\n";
    echo "<b><input type=submit name=canceled value=Cancel></b>\n";
    echo "</form>\n";
    echo "</center>\n";

    PAGEFOOTER();
    return;
}

#
# Okay, call out to the backend to delete the list. 
#
SUEXEC($uid, $TBADMINGROUP, "webdelmmlist -u $listname", SUEXEC_ACTION_DIE);

#
# Worked, so delete the record from the DB.
#
DBQueryFatal("delete from mailman_listnames ".
	     "where listname='$listname'");


#
# Back to ...
# 
header("Location: showmmlists.php3");
?>
