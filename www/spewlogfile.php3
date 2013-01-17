<?php
#
# Copyright (c) 2000-2013 University of Utah and the Flux Group.
# 
# {{{EMULAB-LICENSE
# 
# This file is part of the Emulab network testbed software.
# 
# This file is free software: you can redistribute it and/or modify it
# under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or (at
# your option) any later version.
# 
# This file is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Affero General Public
# License for more details.
# 
# You should have received a copy of the GNU Affero General Public License
# along with this file.  If not, see <http://www.gnu.org/licenses/>.
# 
# }}}
#
include("defs.php3");

#
# Get current user, but allow for anon access.
#
$this_user = CheckLogin($check_status);
$uid       = ($this_user ? $this_user->uid() : "nobody");
$anonopt   = ($this_user ? "" : "-a");

#
# Verify page arguments.
#
$reqargs = RequiredPageArguments("logfile", PAGEARG_LOGFILE);

if (! isset($logfile)) {
    PAGEARGERROR("Must provide either a logfile ID");
}

# Check permission in the backend. The user is logged in, so its safe enough
# to pass it through.
$logfileid = $logfile->logid();

#
# A cleanup function to keep the child from becoming a zombie, since
# the script is terminated, but the children are left to roam.
#
$fp = 0;

function SPEWCLEANUP()
{
    global $fp;

    if (!$fp || !connection_aborted()) {
	exit();
    }
    pclose($fp);
    exit();
}
ignore_user_abort(1);
register_shutdown_function("SPEWCLEANUP");

if ($fp =
    popen("$TBSUEXEC_PATH $uid nobody ".
	  "spewlogfile $anonopt -w -i " . escapeshellarg($logfileid), "r")) {
    header("Content-Type: text/plain");
    header("Expires: Mon, 26 Jul 1997 05:00:00 GMT");
    header("Cache-Control: no-cache, must-revalidate");
    header("Pragma: no-cache");
    flush();

    while (!feof($fp)) {
	$string = fgets($fp, 1024);
	echo "$string";
	flush();
    }
    pclose($fp);
    $fp = 0;
}
else {
    USERERROR("Logfile $logfileid is no longer valid!", 1);
}

?>
