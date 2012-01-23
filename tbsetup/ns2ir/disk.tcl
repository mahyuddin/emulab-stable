# -*- tcl -*-
#
# EMULAB-COPYRIGHT
# Copyright (c) 2000-2006 University of Utah and the Flux Group.
# All rights reserved.
#

######################################################################
# disk.tcl
#
# This defines the local disk agent.
#
######################################################################

Class Disk -superclass NSObject

namespace eval GLOBALS {
    set new_classes(Disk) {}
    variable all_programs {}
}

Program instproc init {s} {
    global ::GLOBALS::last_class
    global ::GLOBALS::all_programs

    if {$all_programs == {}} {
	# Create a default event group to hold all program agents.
	set foo [uplevel \#0 "set __all_programs [new EventGroup $s]"]
	set all_programs $foo
    }
    $all_programs add $self

    $self set sim $s
    $self set node {}
    $self set name {}
    $self set type {}
    $self set mountpoint {}
    $self set params {}

    # Link simulator to this new object.
    $s add_program $self

    set ::GLOBALS::last_class $self
}

Program instproc rename {old new} {
    global ::GLOBALS::all_programs
    $self instvar sim

    $sim rename_program $old $new
    $all_programs rename-agent $old $new
}

# updatedb DB
# This adds rows to the virt_trafgens table corresponding to this agent.
Program instproc updatedb {DB} {
    var_import ::GLOBALS::pid
    var_import ::GLOBALS::eid
    var_import ::TBCOMPAT::objtypes
    $self instvar node
    $self instvar name 
    $self instvar type 
    $self instvar mountpoint 
    $self instvar params 
    $self instvar sim

    if {$node == {}} {
	perror "\[updatedb] $self has no node."
	return
    }
    set progvnode $node

    #
    # if the attached node is a simulated one, we attach the
    # program to the physical node on which the simulation runs
    #
    if {$progvnode != "ops"} {
	if { [$node set simulated] == 1 } {
	    set progvnode [$node set nsenode]
	}
    }

    # Update the DB
    spitxml_data "virt_disk" [list "vnode" "vname" "name" "type" "mountpoint" "params"] [list $progvnode $self $name $type $mountpoint $params ]

    $sim spitxml_data "virt_agents" [list "vnode" "vname" "objecttype" ] [list $progvnode $self $objtypes(DISK) ]
}

