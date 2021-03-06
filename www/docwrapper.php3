<?php
#
# Copyright (c) 2000-2007 University of Utah and the Flux Group.
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
require("defs.php3");

#
# Verify page arguments.
#
$reqargs = RequiredPageArguments("docname",    PAGEARG_STRING);
$optargs = OptionalPageArguments("printable",  PAGEARG_BOOLEAN);

#
# Need to sanity check the path! Allow only [word].html files
#
if (!preg_match("/^[-\w]+\.(html|txt)$/", $docname)) {
    USERERROR("Illegal document name: $docname!", 1, HTTP_400_BAD_REQUEST);
}

$to_wiki = array(
  'hardware.html' => 'UtahHardware',
  'hardware-emulab.net.html' => 'UtahHardware',
  'auth.html' => 'Auth',
  'otheremulabs.html' => 'OtherEmulabs',
  'swapping.html' => 'Swapping',
  'software.html' => 'software'
);

#
# Make sure the file exists
#
$fh = @fopen("$docname", "r");
if (!$fh) {
    if (isset ($to_wiki{$docname})) {
      $wikiname = $to_wiki{$docname};
      header("Location: $WIKIDOCURL/$wikiname", TRUE, 301);
      return 0;
    } else {
      USERERROR("Can't read document file: $docname!", 1, HTTP_404_NOT_FOUND);
    }
}

if (!isset($printable))
    $printable = 0;

#
# Standard Testbed Header
#
if (!$printable) {
    PAGEHEADER("Emulab Documentation");
}

if ($printable) {
    #
    # Need to spit out some header stuff.
    #
    echo "<html>
          <head>
  	  <link rel='stylesheet' href='tbstyle-plain.css' type='text/css'>
          </head>
          <body>\n";
}
else {
	echo "<b><a href=$REQUEST_URI&printable=1>
                 Printable version of this document</a></b><br>\n";
}

fpassthru($fh);
fclose($fh);

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

