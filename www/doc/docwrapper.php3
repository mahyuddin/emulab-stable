<?php
#
# EMULAB-COPYRIGHT
# Copyright (c) 2000-2003 University of Utah and the Flux Group.
# All rights reserved.
#
chdir("..");
require("defs.php3");
chdir("doc");

# Page arguments.
$printable = $_GET['printable'];
$docname   = $_GET['docname'];

# Pedantic page arument checking. Good practice!
if (!isset($docname) ||
    (isset($printable) && !($printable == "1" || $printable == "0"))) {
    PAGEARGERROR();
}
if (!isset($printable))
    $printable = 0;

#
# Standard Testbed Header
#
if (!$printable) {
    PAGEHEADER("Emulab Documentation");
}

#
# Need to sanity check the path! For now, just make sure the path
# does not start with a dot or a slash.
#
$first = substr($docname, 0, 1);
if (strcmp($first, ".") == 0 ||
    strcmp($first, "/") == 0) {
    USERERROR("Illegal document name: $docname!", 1);
}
#
# Nothing that looks like a ../ is allowed anywhere in the name
#
if (strstr($docname, "../")) {
    USERERROR("Illegal document name: $docname!", 1);
}

#
# Check extension. If a .txt file, need some extra wrapper stuff to make
# it look readable.
#
$textfile = 0;
if (preg_match("/^.*\.txt$/", $docname)) {
    $textfile = 1;
}

if ($printable) {
    #
    # Need to spit out some header stuff.
    #
    echo "<html>
          <head>
  	  <link rel='stylesheet' href='../tbstyle-plain.css' type='text/css'>
          </head>
          <body>\n";
}
else {
	echo "<b><a href=$REQUEST_URI&printable=1>
                 Printable version of this document</a></b><br>\n";
}

if ($textfile) {
    echo "<XMP>\n";
}

readfile("$docname");

if ($textfile) {
    echo "</XMP>\n";
}

#
# Standard Testbed Footer
# 
if ($printable) {
    echo "</body>
          </html>\n";
}
else {
    PAGEFOOTER();
}
?>

