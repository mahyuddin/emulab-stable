#!/usr/bin/perl -wT
#
# Copyright (c) 2008-2012 University of Utah and the Flux Group.
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
# OS-independent vnode definitions, helpers, etc.
#
package libgenvnode;
use Exporter;
@ISA    = "Exporter";
@EXPORT = qw( VNODE_STATUS_RUNNING VNODE_STATUS_STOPPED VNODE_STATUS_BOOTING 
              VNODE_STATUS_INIT VNODE_STATUS_STOPPING VNODE_STATUS_UNKNOWN
	      VNODE_STATUS_MOUNTED
              findVirtControlNet
            );

sub VNODE_STATUS_RUNNING() { return "running"; }
sub VNODE_STATUS_STOPPED() { return "stopped"; }
sub VNODE_STATUS_MOUNTED() { return "mounted"; }
sub VNODE_STATUS_BOOTING() { return "booting"; }
sub VNODE_STATUS_INIT()    { return "init"; }
sub VNODE_STATUS_STOPPING(){ return "stopping"; }
sub VNODE_STATUS_UNKNOWN() { return "unknown"; }

#
# Magic control network config parameters.
#
my $VCNET_NET	    = "172.16.0.0";
my $VCNET_MASK      = "255.240.0.0";
my $VCNET_GW	    = "172.16.0.1";

#
# Find virtual control net iface info.  Returns:
# (net,mask,GW)
#
sub findVirtControlNet()
{
    return ($VCNET_NET, $VCNET_MASK, $VCNET_GW);
}