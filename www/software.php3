<?php
#
# EMULAB-COPYRIGHT
# Copyright (c) 2000-2003 University of Utah and the Flux Group.
# All rights reserved.
#
require("defs.php3");

#
# Anyone can run this page. No login is needed.
# 
PAGEHEADER("Emulab Software Distributions");

# Insert plain html inside these brackets. Outside the brackets you are
# programming in php!
?>

<ul>
<li> <img src="/new.gif" alt="&lt;NEW&gt;">
     <a href="/downloads/frisbee-snapshot-20031021.tar.gz">
     Updated Frisbee Server and Client Source Snapshot</a>.
     This is a ``snapshot'' of the current development tree.  It includes the
     NTFS framework that was not in the previous release as well as some
     bug fixes and additional features.
     Please take a look at the
     <a href="/downloads/frisbee-README-20031021.txt">README</a>
     file for more information on the changes.
     This
     <a href="/downloads/frisbee-fs-20031021.iso">updated ISO image</a>
     includes binaries built from the current sources.
<li> <a href="/downloads/frisbee-20030618.tar.gz">Frisbee Server and
     Client</a>,
     as described in our paper <cite><a href="pubs.php3">Fast, Scalable Disk
     Imaging with Frisbee</a></cite>, to appear at
     <a href='http://www.usenix.org/events/usenix03/'>USENIX 2003</a>.
     Please take a look at the
     <a href="/downloads/frisbee-README-20030618.txt">README</a>
     file for a better
     idea of how we use Frisbee in the Testbed, and how to setup a
     simple Frisbee demonstration on your network.   Use this
     <a href="/downloads/frisbee-fs-20030618.iso">ISO image</a>
     to create a bootable FreeBSD 4.6 system from which to run the
     image creation and installation tools.
<ul>

<?php


#
# Standard Footer.
# 
PAGEFOOTER();
