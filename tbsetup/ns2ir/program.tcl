# -*- tcl -*-
#
# EMULAB-COPYRIGHT
# Copyright (c) 2000-2004 University of Utah and the Flux Group.
# All rights reserved.
#

######################################################################
# program.tcl
#
# This defines the local program agent.
#
######################################################################

Class Program -superclass NSObject

namespace eval GLOBALS {
    set new_classes(Program) {}
}

Program instproc init {s} {
    global ::GLOBALS::last_class

    $self set sim $s
    $self set node {}
    $self set command {}
    $self set dir {}
    $self set timeout 0

    # Link simulator to this new object.
    $s add_program $self

    set ::GLOBALS::last_class $self
}

Program instproc rename {old new} {
    $self instvar sim

    $sim rename_program $old $new
}

# updatedb DB
# This adds rows to the virt_trafgens table corresponding to this agent.
Program instproc updatedb {DB} {
    var_import ::GLOBALS::pid
    var_import ::GLOBALS::eid
    var_import ::TBCOMPAT::objtypes
    $self instvar node
    $self instvar command
    $self instvar dir
    $self instvar timeout
    $self instvar sim

    if {$node == {}} {
	perror "\[updatedb] $self has no node."
	return
    }
    if { [string first \n $command] != -1 } {
	perror "\[updatedb] $self has disallowed newline in command: $command"
	return
    }

    set progvnode $node
    # if the attached node is a simulated one, we attach the
    # program to the physical node on which the simulation runs
    if { [$node set simulated] == 1 } {
	set progvnode [$node set nsenode]
    }

    # Update the DB
    spitxml_data "virt_programs" [list "vnode" "vname" "command"] [list $progvnode $self $command ]

    $sim spitxml_data "virt_agents" [list "vnode" "vname" "objecttype" ] [list $progvnode $self $objtypes(PROGRAM) ]
}

