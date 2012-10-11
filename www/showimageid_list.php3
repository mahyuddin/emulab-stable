<?php
#
# Copyright (c) 2000-2012 University of Utah and the Flux Group.
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
#
# Only known and logged in users allowed.
#
$this_user = CheckLoginOrDie();
$uid       = $this_user->uid();
$isadmin   = ISADMIN();

#
# Admin users can see all ImageIDs, while normal users can only see
# ones in their projects or ones that are globally available.
#
$optargs = OptionalPageArguments("creator",  PAGEARG_USER);
$extraclause = "";

#
# Standard Testbed Header
#
PAGEHEADER("Image List");

#
# Allow for creator restriction
#
if (isset($creator)) {
    $creator_idx = $creator->uid_idx();
    
    if ($isadmin) {
	$extraclause = "where i.creator_idx='$creator_idx' ";
    }
    elseif ($creator->SameUser($this_user)) {
	$extraclause = "and i.creator_idx='$creator_idx' ";
    }
}

#
# Get the list.
#
if ($isadmin) {
    $query_result = DBQueryFatal("SELECT * FROM images as i ".
				 "$extraclause ".
				 "order by i.imagename");
}
else {
    #
    # User is allowed to view the list of all global images, and all images
    # in his project. Include images in the subgroups too, since its okay
    # for the all project members to see the descriptors. They need proper 
    # permission to use/modify the image/descriptor of course, but that is
    # checked in the pages that do that stuff. In other words, ignore the
    # shared flag in the descriptors.
    #
    $uid_idx = $this_user->uid_idx();
    
    $query_result =
	DBQueryFatal("select distinct i.* from images as i ".
		     "left join image_permissions as p1 on ".
		     "     p1.imageid=i.imageid and p1.permission_type='group' ".
		     "left join image_permissions as p2 on ".
		     "     p2.imageid=i.imageid and p2.permission_type='user' ".
		     "left join group_membership as g on ".
		     "     g.pid_idx=i.pid_idx or ".
		     "     g.gid_idx=p1.permission_idx ".
		     "where (g.uid_idx='$uid_idx' or i.global or".
		     "       p2.permission_idx='$uid_idx') ".
		     "$extraclause ".
		     "order by i.imagename");
}

SUBPAGESTART();
SUBMENUSTART("More Options");
WRITESUBMENUBUTTON("Create an Image Descriptor",
		   "newimageid_ez.php3");
if ($isadmin) {
    WRITESUBMENUBUTTON("Create an OS Descriptor",
		       "newosid.php3");
    WRITESUBMENUBUTTON("OS Descriptor list",
		       "showosid_list.php3");
}
SUBMENUEND();

echo "Listed below are the Images that you can load on your nodes with the
      <a href='$WIKIDOCURL/nscommands#OS'>
      <tt>tb-set-node-os</tt></a> directive. If the OS you have selected for
      a node is not loaded on that node when the experiment is swapped in,
      the Testbed system will automatically reload that node's disk with the
      appropriate image. You might notice that it takes a few minutes longer
      to start your experiment when selecting an OS that is not
      already resident. Please be patient.
      <br>
      More information on how to create your own Images is in the
      <a href='$WIKIDOCURL/Tutorial#CustomOS'>Custom OS</a> section of
      the <a href='$WIKIDOCURL/Tutorial'>Emulab Tutorial.</a>
      <br>\n";

SUBPAGEEND();

if (mysql_num_rows($query_result)) {
    echo "<table border=2 cellpadding=0 cellspacing=2 id='showimagelist'
           align='center'>\n";

    echo "<thead class='sort'>
           <tr>
              <th class='sorttable_alpha'>Image</th>
              <th class='sorttable_alpha'>PID</th>
              <th class='sorttable_alpha'>Description</th>
           </tr>
          </thead>\n";

    while ($row = mysql_fetch_array($query_result)) {
	$imageid    = $row["imageid"];
	$descrip    = $row["description"];
	$imagename  = $row["imagename"];
	$pid        = $row["pid"];
	$url        = CreateURL("showimageid", URLARG_IMAGEID, $imageid);

	echo "<tr>
                  <td><A href='$url'>$imagename</A></td>
                  <td>$pid</td>
                  <td>$descrip</td>\n";
        echo "</tr>\n";
    }
    echo "</table>\n";
}
echo "<script type='text/javascript' language='javascript'>
	sorttable.makeSortable(getObjbyName('showimagelist'));
      </script>\n";

#
# Standard Testbed Footer
# 
PAGEFOOTER();
?>
