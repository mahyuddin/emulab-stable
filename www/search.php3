<?php
#
# EMULAB-COPYRIGHT
# Copyright (c) 2000-2002, 2004, 2005 University of Utah and the Flux Group.
# All rights reserved.
#
require("defs.php3");

#
# Standard Testbed Header
#
PAGEHEADER("Search Emulab Documentation");

#
# We no longer support an advanced search option. We might bring it back
# someday.
#
function SPITSEARCHFORM($query)
{
    echo "<table align=center border=1>
          <form action=search.php3 method=get>\n";

    $query = htmlspecialchars($query);

    #
    # Just the query please.
    #
    echo "<tr>
             <td class=left>
                 <input type=text name=query value=\"$query\"
                        size=25 maxlength=100>
               </td>
           </tr>\n";
    
    echo "<tr>
              <td align=center>
                 <b><input type=submit name=submit value='Submit Query'></b>
              </td>
          </tr>\n";

    echo "</form>
          </table><br>\n";
}

if (!isset($query) || $query == "") {
    SPITSEARCHFORM("");
    PAGEFOOTER();
    return;
}

# Sanitize for the shell. Be fancy later.
if (!preg_match("/^[-\w\ \"]+$/", $query)) {
    SPITSEARCHFORM("");
    PAGEFOOTER();
    return;
}

#
# Run the query. We get back html we can just spit out.
#
#
# A cleanup function to keep the child from becoming a zombie, since
# the script is terminated, but the children are left to roam.
#
$fp = 0;

function CLEANUP()
{
    global $fp;

    if (!$fp || !connection_aborted()) {
	exit();
    }
    pclose($fp);
    exit();
}
ignore_user_abort(1);
register_shutdown_function("CLEANUP");

SPITSEARCHFORM($query);
flush();

#
# First the Knowledge Base
#
$embedded    = 1;
$query_type  = "and";
$query_which = "both";
include("kb-search.php3");

echo "<br>\n";
echo "<font size=+2>Documentation search results</font><br>\n";

if ($fp = popen("$TBSUEXEC_PATH nobody nobody websearch '$query'", "r")) {
    while (!feof($fp)) {
	$string = fgets($fp, 1024);
	echo "$string";
	flush();
    }
    pclose($fp);
    $fp = 0;
}
else {
    TBERROR("Query failed: $query", 0);
}

#
# Standard Testbed Footer
# 
PAGEFOOTER();
?>

