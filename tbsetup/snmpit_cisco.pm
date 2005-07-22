#!/usr/bin/perl -w

#
# EMULAB-LGPL
# Copyright (c) 2000-2005 University of Utah and the Flux Group.
# All rights reserved.
#

#
# snmpit module for Cisco Catalyst 6509 switches
#
# TODO: Standardize returning 0 on success/failure
# TODO: Fix uninitialized variable warnings in getStats()
#

package snmpit_cisco;
use strict;

$| = 1; # Turn off line buffering on output

use English;
use SNMP;
use snmpit_lib;
use Socket;

#
# These are the commands that can be passed to the portControl function
# below
#
my %cmdOIDs =
(
    "enable"  => ["ifAdminStatus","up"],
    "disable" => ["ifAdminStatus","down"],
    "1000mbit"=> ["portAdminSpeed","s1000000000"],
    "100mbit" => ["portAdminSpeed","s100000000"],
    "10mbit"  => ["portAdminSpeed","s10000000"],
    "full"    => ["portDuplex","full"],
    "half"    => ["portDuplex","half"],
    "auto"    => ["portAdminSpeed","autoDetect",
		 "portDuplex","auto"]
);

#
# Ports can be passed around in three formats:
# ifindex: positive integer corresponding to the interface index (eg. 42)
# modport: dotted module.port format, following the physical reality of
#	Cisco switches (eg. 5.42)
# nodeport: node:port pair, referring to the node that the switch port is
# 	connected to (eg. "pc42:1")
#
# See the function convertPortFormat below for conversions between these
# formats
#
my $PORT_FORMAT_IFINDEX  = 1;
my $PORT_FORMAT_MODPORT  = 2;
my $PORT_FORMAT_NODEPORT = 3;

#
# Creates a new object.
#
# usage: new($classname,$devicename,$debuglevel,$community)
#        returns a new object, blessed into the snmpit_cisco class.
#
sub new($$$;$) {

    # The next two lines are some voodoo taken from perltoot(1)
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my $name = shift;
    my $debugLevel = shift;
    my $community = shift;

    #
    # Create the actual object
    #
    my $self = {};

    #
    # Set the defaults for this object
    # 
    if (defined($debugLevel)) {
	$self->{DEBUG} = $debugLevel;
    } else {
	$self->{DEBUG} = 0;
    }
    $self->{BLOCK} = 1;
    $self->{BULK} = 1;
    $self->{NAME} = $name;

    #
    # Get config options from the database
    #
    my $options = getDeviceOptions($self->{NAME});
    if (!$options) {
	warn "ERROR: Getting switch options for $self->{NAME}\n";
	return undef;
    }

    $self->{SUPPORTS_PRIVATE} = $options->{'supports_private'};
    $self->{MIN_VLAN}         = $options->{'min_vlan'};
    $self->{MAX_VLAN}         = $options->{'max_vlan'};

    if ($community) { # Allow this to over-ride the default
	$self->{COMMUNITY}    = $community;
    } else {
	$self->{COMMUNITY}    = $options->{'snmp_community'};
    }

    #
    # We have to change our behavior depending on what OS the switch runs
    #
    $options->{'type'} =~ /^(\w+)(-modhack(-?))?(-ios)?$/;
    $self->{SWITCHTYPE} = $1;

    if ($2) {
        $self->{NON_MODULAR_HACK} = 1;
    } else {
        $self->{NON_MODULAR_HACK} = 0;
    }

    if ($4) {
	$self->{OSTYPE} = "IOS";
    } else {
	$self->{OSTYPE} = "CatOS";
    }

    if ($self->{DEBUG}) {
	print "snmpit_cisco module initializing... debug level $self->{DEBUG}\n";
    }

    #
    # Set up SNMP module variables, and connect to the device
    #
    $SNMP::debugging = ($self->{DEBUG} - 2) if $self->{DEBUG} > 2;
    my $mibpath = '/usr/local/share/snmp/mibs';
    &SNMP::addMibDirs($mibpath);
    # We list all MIBs we use, so that we don't depend on a correct .index file
    my @mibs = ("$mibpath/SNMPv2-SMI.txt", "$mibpath/SNMPv2-TC.txt",
	    "$mibpath/SNMPv2-MIB.txt", "$mibpath/IANAifType-MIB.txt",
	    "$mibpath/IF-MIB.txt", "$mibpath/RMON-MIB.txt",
	    "$mibpath/CISCO-SMI.txt", "$mibpath/CISCO-TC.txt",
	    "$mibpath/CISCO-VTP-MIB.txt", "$mibpath/CISCO-PAGP-MIB.txt",
	    "$mibpath/CISCO-PRIVATE-VLAN-MIB.txt");
	    
    if ($self->{OSTYPE} eq "CatOS") {
	push @mibs, "$mibpath/CISCO-STACK-MIB.txt";
    } elsif ($self->{OSTYPE} eq "IOS") {
	push @mibs, "$mibpath/CISCO-VLAN-MEMBERSHIP-MIB.txt";
    } else {
	warn "ERROR: Unsupported switch OS $self->{OSTYPE}\n";
	return undef;
    }

    &SNMP::addMibFiles(@mibs);
    
    $SNMP::save_descriptions = 1; # must be set prior to mib initialization
    SNMP::initMib();		  # parses default list of Mib modules 
    $SNMP::use_enums = 1;	  # use enum values instead of only ints

    warn ("Opening SNMP session to $self->{NAME}...") if ($self->{DEBUG});
    $self->{SESS} =
	    new SNMP::Session(DestHost => $self->{NAME},Version => "2c",
		    Community => $self->{COMMUNITY});
    if (!$self->{SESS}) {
	#
	# Bomb out if the session could not be established
	#
	warn "ERROR: Unable to connect via SNMP to $self->{NAME}\n";
	return undef;
    }

    #
    # The bless needs to occur before readifIndex(), since it's a class 
    # method
    #
    bless($self,$class);

    $self->readifIndex();

    return $self;
}

#
# Set a variable associated with a port. The commands to execute are given
# in the cmdOIs hash above
#
# usage: portControl($self, $command, @ports)
#	 returns 0 on success.
#	 returns number of failed ports on failure.
#	 returns -1 if the operation is unsupported
#
sub portControl ($$@) {
    my $self = shift;

    my $cmd = shift;
    my @ports = @_;

    $self->debug("portControl: $cmd -> (@ports)\n");

    $self->debug("portControl: Checking supported for $cmd on " .
	    "$self->{OSTYPE}\n");

    #
    # Check right up front for unsupported operations
    #
    if ($self->{OSTYPE} eq "IOS" && ($cmd !~ /(en|dis)able/)) {
	#
	# XXX - Do we silently exit, in which case the caller doesn't know
	# we failed, or do we exit with an error, in which case the caller has
	# to know what we support before calling us? We'll go with the latter
	# for now.
	#
	$self->debug("portControl: unsupported\n");
	return -1;
    }

    #
    # Find the command in the %cmdOIDs hash (defined at the top of this file)
    #
    if (defined $cmdOIDs{$cmd}) {
	my @oid = @{$cmdOIDs{$cmd}};
	my $errors = 0;

	#
	# Convert the ports from the format they were given in to the format
	# required by the command
	#
	my $portFormat;
	if ($cmd =~ /(en)|(dis)able/) {
	    $portFormat = $PORT_FORMAT_IFINDEX;
	} else { 
	    $portFormat = $PORT_FORMAT_MODPORT;
	}
	my @portlist = $self->convertPortFormat($portFormat,@ports);

	#
	# Some commands involve multiple SNMP commands, so we need to make
	# sure we get all of them
	#
	while (@oid) {
	    my $myoid = shift @oid;
	    my $myval = shift @oid;
	    $errors += $self->UpdateField($myoid,$myval,@portlist);
	}
	return $errors;

    } else {
	#
	# Command not supported
	#
	print STDERR "Unsupported port control command '$cmd' ignored.\n";
	return -1;
    }
}

#
# Convert a set of ports to an alternate format. The input format is detected
# automatically. See the declarations of the constants at the top of this
# file for a description of the different port formats.
#
# usage: convertPortFormat($self, $output format, @ports)
#        returns a list of ports in the specified output format
#        returns undef if the output format is unknown
#
# TODO: Add debugging output, better comments, more sanity checking
#
sub convertPortFormat($$@) {
    my $self = shift;
    my $output = shift;
    my @ports = @_;


    #
    # Avoid warnings by exiting if no ports given
    # 
    if (!@ports) {
	return ();
    }

    #
    # We determine the type by sampling the first port given
    #
    my $sample = $ports[0];
    if (!defined($sample)) {
	warn "convertPortFormat: Given a bad list of ports\n";
	return undef;
    }

    my $input;
    SWITCH: for ($sample) {
	(/^\d+$/) && do { $input = $PORT_FORMAT_IFINDEX; last; };
	(/^\d+\.\d+$/) && do { $input = $PORT_FORMAT_MODPORT; last; };
	(/^$self->{NAME}\.\d+\/\d+$/) && do { $input = $PORT_FORMAT_MODPORT;
		@ports = map {/^$self->{NAME}\.(\d+)\/(\d+)$/; "$1.$2";} @ports; last; };
	$input = $PORT_FORMAT_NODEPORT; last;
    }

    #
    # It's possible the ports are already in the right format
    #
    if ($input == $output) {
	$self->debug("Not converting, input format = output format\n",2);
	return @ports;
    }

    # Shark hack
    @ports = map {if (/(sh\d+)-\d(:\d)/) { "$1$2" } else { $_ }} @ports;
    # End shark hack

    if ($input == $PORT_FORMAT_IFINDEX) {
	if ($output == $PORT_FORMAT_MODPORT) {
	    $self->debug("Converting ifindex to modport\n",2);
	    return map $self->{IFINDEX}{$_}, @ports;
	} elsif ($output == $PORT_FORMAT_NODEPORT) {
	    $self->debug("Converting ifindex to nodeport\n",2);
	    return map portnum($self->{NAME}.":".$self->{IFINDEX}{$_}), @ports;
	}
    } elsif ($input == $PORT_FORMAT_MODPORT) {
	if ($output == $PORT_FORMAT_IFINDEX) {
	    $self->debug("Converting modport to ifindex\n",2);
	    return map $self->{IFINDEX}{$_}, @ports;
	} elsif ($output == $PORT_FORMAT_NODEPORT) {
	    $self->debug("Converting modport to nodeport\n",2);
	    return map portnum($self->{NAME} . ":$_"), @ports;
	}
    } elsif ($input == $PORT_FORMAT_NODEPORT) {
	if ($output == $PORT_FORMAT_IFINDEX) {
	    $self->debug("Converting nodeport to ifindex\n",2);
	    return map $self->{IFINDEX}{(split /:/,portnum($_))[1]}, @ports;
	} elsif ($output == $PORT_FORMAT_MODPORT) {
	    $self->debug("Converting nodeport to modport\n",2);
	    return map { (split /:/,portnum($_))[1] } @ports;
	}
    }

    #
    # Some combination we don't know how to handle
    #
    warn "convertPortFormat: Bad input/output combination ($input/$output)\n";
    return undef;

}

#
# Obtain a lock on the VLAN edit buffer. This must be done before VLANS
# are created or removed. Will retry 5 times before failing
#
# usage: vlanLock($self)
#        returns 1 on success
#        returns 0 on failure
#
sub vlanLock($) {
    my $self = shift;

    my $EditOp = 'vtpVlanEditOperation'; # use index 1
    my $BufferOwner = 'vtpVlanEditBufferOwner'; # use index 1

    #
    # Try max_tries times before we give up, in case some other process just
    # has it locked.
    #
    my $tries = 1;
    my $max_tries = 40;
    while ($tries <= $max_tries) {
    
	#
	# Attempt to grab the edit buffer
	#
	my $grabBuffer = $self->{SESS}->set([$EditOp,1,"copy","INTEGER"]);

	#
	# Check to see if we were sucessful
	#
	$self->debug("Buffer Request Set gave " .
		(defined($grabBuffer)?$grabBuffer:"undef.") . "\n");
	if (! $grabBuffer) {
	    #
	    # Only print this message every five tries
	    #
	    if (!($tries % 5)) {
		print STDERR "$self->{NAME}: VLAN edit buffer request failed - " .
			     "try $tries of $max_tries.\n";
	    }
	} else {
	    last;
	}
	$tries++;

	sleep(3);
    }

    if ($tries > $max_tries) {
	#
	# Admit defeat and exit
	#
	print STDERR "ERROR: Failed to obtain VLAN edit buffer lock\n";
	return 0;
    } else {
	#
	# Set the owner of the buffer to be the machine we're running on
	#
	my $me = `/usr/bin/uname -n`;
	chomp $me;
	$self->{SESS}->set([$BufferOwner,1,$me,"OCTETSTR"]);

	return 1;
    }

}

#
# Release a lock on the VLAN edit buffer. As part of releasing, applies the
# VLAN edit buffer.
#
# usage: vlanUnlock($self)
#
# TODO: Finish commenting, major cleanup, removal of obsolete features
#        
sub vlanUnlock($;$) {
    my $self = shift;
    my $force = shift;

    my $EditOp = 'vtpVlanEditOperation'; # use index 1
    my $ApplyStatus = 'vtpVlanApplyStatus'; # use index 1
    my $ApplyRetVal = $self->{SESS}->set([[$EditOp,1,"apply","INTEGER"]]);
    $self->debug("Apply set: '$ApplyRetVal'\n");

    $ApplyRetVal = snmpitGetWarn($self->{SESS},[$ApplyStatus,1]);
    $self->debug("Apply gave $ApplyRetVal\n");
    while ($ApplyRetVal eq "inProgress") { 
	$ApplyRetVal = snmpitGetWarn($self->{SESS},[$ApplyStatus,1]);
	$self->debug("Apply gave $ApplyRetVal\n");
    }

    if ($ApplyRetVal ne "succeeded") {
	$self->debug("Apply failed: Gave $ApplyRetVal\n");
	warn("ERROR: Failure applying VLAN changes: $ApplyRetVal\n");
	# Only release the buffer if they've asked to force it.
	if (!$force) {
	    my $RetVal = $self->{SESS}->set([[$EditOp,1,"release","INTEGER"]]);
	    $self->debug("Release: '$RetVal'\n");
	    if (! $RetVal ) {
		warn("VLAN Reconfiguration Failed. No changes saved.\n");
		return 0;
	    }
	}
    } else { 
	$self->debug("Apply Succeeded.\n");
	# If I succeed, release buffer
	my $RetVal = $self->{SESS}->set([[$EditOp,1,"release","INTEGER"]]);
	if (! $RetVal ) {
	    warn("VLAN Reconfiguration Failed. No changes saved.\n");
	    return 0;
	}
	$self->debug("Release: '$RetVal'\n");
    }
    
    return $ApplyRetVal;
}

# 
# Check to see if the given (cisco-specific) VLAN number exists on the switch
#
# usage: vlanNumberExists($self, $vlan_number)
#        returns 1 if the VLAN exists, 0 otherwise
#
sub vlanNumberExists($$) {
    my $self = shift;
    my $vlan_number = shift;

    my $VlanName = "vtpVlanName";

    #
    # Just look up the name for this VLAN, and see if we get an answer back
    # or not
    #
    my $rv = $self->{SESS}->get([$VlanName,"1.$vlan_number"]);
    if (!$rv or $rv eq "NOSUCHINSTANCE") {
	return 0;
    } else {
    	return 1;
    }
}

#
# Given VLAN indentifiers from the database, finds the cisco-specific VLAN
# number for them. If not VLAN id is given, returns mappings for the entire
# switch.
# 
# usage: findVlans($self, @vlan_ids)
#        returns a hash mapping VLAN ids to Cisco VLAN numbers
#        any VLANs not found have NULL VLAN numbers
#
sub findVlans($@) { 
    my $self = shift;
    my @vlan_ids = @_;

    my $VlanName = "vtpVlanName"; # index by 1.vlan #

    #
    # Walk the tree to find the VLAN names
    # TODO - we could optimize a bit, since, if we find all VLAN, we can stop
    # looking, potentially saving us a lot of time. But, it would require a
    # more complex walk.
    #
    my %mapping = ();
    @mapping{@vlan_ids} = undef;
    my ($rows) = $self->{SESS}->bulkwalk(0,32,[$VlanName]);
    foreach my $rowref (@$rows) {
	my ($name,$vlan_number,$vlan_name) = @$rowref;
	#
	# We get the VLAN number in the form 1.number - we need to strip
	# off the '1.' to make it useful
	#
	$vlan_number =~ s/^1\.//;

	$self->debug("Got $name $vlan_number $vlan_name\n",2);
	if (!@vlan_ids || exists $mapping{$vlan_name}) {
	    $self->debug("Putting in mapping from $vlan_name to $vlan_number\n",2);
	    $mapping{$vlan_name} = $vlan_number;
	}
    }

    return %mapping;
}

#
# Given a VLAN identifier from the database, find the cisco-specific VLAN
# number that is assigned to that VLAN. Retries several times (to account
# for propagation delays) unless the $no_retry option is given.
#
# usage: findVlan($self, $vlan_id,$no_retry)
#        returns the VLAN number for the given vlan_id if it exists
#        returns undef if the VLAN id is not found
#
sub findVlan($$;$) { 
    my $self = shift;
    my $vlan_id = shift;
    my $no_retry = shift;

    my $max_tries;
    if ($no_retry) {
	$max_tries = 1;
    } else {
	$max_tries = 10;
    }

    #
    # We try this a few time, with 1 second sleeps, since it can take
    # a while for VLAN information to propagate
    #
    foreach my $try (1 .. $max_tries) {

	my %mapping = $self->findVlans($vlan_id);
	if (defined($mapping{$vlan_id})) {
	    return $mapping{$vlan_id};
	}

	#
	# Wait before we try again
	#
	if ($try != $max_tries) {
	    $self->debug("VLAN find failed, trying again\n");
	    sleep 1;
	}
    }
    #
    # Didn't find it
    #
    return undef;
}

#
# Create a VLAN on this switch, with the given identifier (which comes from
# the database.) If $vlan_number is given, attempts to use it when creating
# the vlan - otherwise, picks its own Cisco-specific VLAN number.
#
# usage: createVlan($self, $vlan_id, $vlan_number, [,$private_type
# 		[,$private_primary, $private_port]])
#        returns the new VLAN number on success
#        returns 0 on failure
#        if $private_type is given, creates a private VLAN - if private_type
#        is 'community' or 'isolated', then the assocated primary VLAN and
#        promiscous port must also be given
#
sub createVlan($$;$$$) {
    my $self = shift;
    my $vlan_id = shift;
    my $vlan_number = shift;

    my ($private_type,$private_primary,$private_port);
    if (@_) {
	$private_type = shift;
	if ($private_type ne "primary") {
	    $private_primary = shift;
	    $private_port = shift;
	}
    } else {
	$private_type = "normal";
    }


    my $okay = 1;

    my $VlanType = 'vtpVlanEditType'; # vlan # is index
    my $VlanName = 'vtpVlanEditName'; # vlan # is index
    my $VlanSAID = 'vtpVlanEditDot10Said'; # vlan # is index
    my $VlanRowStatus = 'vtpVlanEditRowStatus'; # vlan # is index

    #
    # If they gave a VLAN number, make sure it doesn't exist
    #
    if ($vlan_number) {
	if ($self->vlanNumberExists($vlan_number)) {
	    print STDERR "ERROR: VLAN $vlan_number already exists\n";
	    return 0;
	}
    }
    
    #
    # We may have to do this multiple times - a few times, we've had the
    # Cisco give no errors, but fail to actually create the VLAN. So, we'll
    # make sure it gets created, and retry if it did not. Of course, we don't
    # want to try forever, though....
    #
    my $max_tries = 3;
    my $tries_remaining = $max_tries;
    while ($tries_remaining) {
	#
	# Try to wait out transient failures
	#
	if ($tries_remaining != $max_tries) {
	    print STDERR "VLAN creation failed, trying again " .
		"($tries_remaining tries left)\n";
	    sleep 5;
	}
	$tries_remaining--;

	if (!$self->vlanLock()) {
	    next;
	}

	if (!$vlan_number) {
	    #
	    # Find a free VLAN number to use.
	    #
	    $vlan_number = $self->{MIN_VLAN};
	    my $RetVal = snmpitGetWarn($self->{SESS},
		[$VlanRowStatus,"1.$vlan_number"]);
	    if (!defined($RetVal)) {
		#
		# If we can't get the first one, we might as well bail
		#
		warn "WARNING: Failed to VLAN name for VLAN $vlan_number\n";
		next;
	    }
	    $self->debug("Row $vlan_number got '$RetVal'\n",2);
	    while (($RetVal ne 'NOSUCHINSTANCE') &&
		    ($vlan_number <= $self->{MAX_VLAN})) {
		$vlan_number += 1;
		$RetVal = snmpitGetWarn($self->{SESS},
		    [$VlanRowStatus,"1.$vlan_number"]);
		if (!defined($RetVal)) {
		    #
		    # We probably could unlock the edit buffer and die, but
		    # the script using this library could have other unfinished
		    # business
		    #
		    warn "WARNING: Failed to VLAN name for VLAN $vlan_number\n";
		} else {
		    $self->debug("Row $vlan_number got '$RetVal'\n",2);
		}
	    }
	    if ($vlan_number > $self->{MAX_VLAN}) {
		#
		# We must have failed to find one
		#
		print STDERR "ERROR: Failed to find a free VLAN number\n";
		next;
	    }
	}

	$self->debug("Using Row $vlan_number\n");

	#
	# SAID is a funky security identifier that _must_ be set for VLAN
	# creation to suceeed.
	#
	my $SAID = pack("H*",sprintf("%08x",$vlan_number + 100000));

	print "  Creating VLAN $vlan_id as VLAN #$vlan_number on " .
		"$self->{NAME} ... ";

	#
	# Perform the actual creation. Yes, this next line MUST happen all in
	# one set command....
	#
	my $RetVal = $self->{SESS}->set([[$VlanRowStatus,"1.$vlan_number",
			"createAndGo","INTEGER"],
		[$VlanType,"1.$vlan_number","ethernet","INTEGER"],
		[$VlanName,"1.$vlan_number",$vlan_id,"OCTETSTR"],
		[$VlanSAID,"1.$vlan_number",$SAID,"OCTETSTR"]]);
	print "",($RetVal? "Succeeded":"Failed"), ".\n";

	#
	# Check for success
	#
	if (!$RetVal) {
	    print STDERR "VLAN Create '$vlan_id' as VLAN $vlan_number " .
		    "failed.\n";
	    $self->vlanUnlock();
	    next;
	} else {
	    #
	    # Handle private VLANs - Part I: Stuff that has to be done while we
	    # have the edit buffer locked
	    #
	    if ($self->{SUPPORTS_PRIVATE} && $private_type ne "normal") {
		#
		# First, set the private VLAN type
		#
		my $PVlanType = "cpvlanVlanEditPrivateVlanType";
		print "    Setting private VLAN type to $private_type ... ";
		$RetVal = $self->{SESS}->set([$PVlanType,"1.$vlan_number",$private_type,
		    'INTEGER']);
		print "",($RetVal? "Succeeded":"Failed"), ".\n";
		if (!$RetVal) {
		    $okay = 0;
		}
		if ($okay) {
		    #
		    # Now, if this isn't a primary VLAN, associate it with its
		    # primary VLAN
		    #
		    if ($private_type ne "primary") {
			my $PVlanAssoc = "cpvlanVlanEditAssocPrimaryVlan";
			my $primary_number = $self->findVlan($private_primary);
			if (!$primary_number) {
			    print "    **** Error - Primary VLAN " .
			    	"$private_primary could not be found\n";
			    $okay = 0;
			} else {
			    print "    Associating with $private_primary (#$primary_number) ... ";
			    $RetVal = $self->{SESS}->set([[$PVlanAssoc,"1.$vlan_number",
				$primary_number,"INTEGER"]]);
			    print "", ($RetVal? "Succeeded":"Failed"), ".\n";
			    if (!$RetVal) {
				$okay = 0;
			    }
			}
		    }
		}
	    }

	    $RetVal = $self->vlanUnlock();
	    $self->debug("Got $RetVal from vlanUnlock\n");

	    #
	    # Unfortunately, there are some rare circumstances in which it
	    # seems that we can't trust the switch to tell us the truth.
	    # So, let's use findVlan to see if it really got created.
	    #
	    if (!$self->findVlan($vlan_id)) {
		print STDERR "*** Switch reported success, but VLAN did not " .
			     "get created - trying again\n";
		next;	     
	    }
	    if ($self->{SUPPORTS_PRIVATE} && $private_type ne "normal" &&
		$private_type ne "primary") {

		#
		# Handle private VLANs - Part II: Set up the promiscuous port -
		# this has to be done after we release the edit buffer
		#

		my $SecondaryPort = 'cpvlanPromPortSecondaryRemap';

		my ($ifIndex) = $self->convertPortFormat($PORT_FORMAT_IFINDEX,
		    $private_port);

		if (!$ifIndex) {
		    print STDERR "    **** ERROR - unable to find promiscous " .
			"port $private_port!\n";
		    $okay = 0;
		}

		if ($okay) {
		    print "    Setting promiscuous port to $private_port ... ";

		    #
		    # Get the existing bitfield used to maintain the mapping
		    # for the port
		    #
		    my $bitfield = $self->{SESS}->get([$SecondaryPort,$ifIndex]);
		    my $unpacked = unpack("B*",$bitfield);

		    #
		    # Put this into an array of 1s and 0s for easy manipulation
		    # We have to pad this out to 128 bits, because it's given
		    # back as the empty string if no bits are set yet.
		    #
		    my @bits = split //,$unpacked;
		    foreach my $bit (0 .. 127) {
			if (!defined $bits[$bit]) {
			    $bits[$bit] = 0;
			}
		    }

		    $bits[$vlan_number] = 1;

		    # Pack it back up...
		    $unpacked = join('',@bits);

		    $bitfield = pack("B*",$unpacked);

		    # And save it back...
		    $RetVal = $self->{SESS}->set([$SecondaryPort,$ifIndex,$bitfield,
			"OCTETSTR"]);
		    print "", ($RetVal? "Succeeded":"Failed"), ".\n";

		}
	    }
	    if ($okay) {
		return $vlan_number;
	    } else {
		return 0;
	    }
	}
    }

    print STDERR "*** Failed to create VLAN $vlan_id after $max_tries tries " .
		 "- giving up\n";
    return 0;
}

#
# Put the given ports in the given VLAN. The VLAN is given as a cisco-specific
# VLAN number
#
# usage: setPortVlan($self, $vlan_number, @ports)
#	 returns 0 on sucess.
#	 returns the number of failed ports on failure.
#
sub setPortVlan($$@) {
    my $self = shift;
    my $vlan_number = shift;
    my @ports = @_;

    my $errors = 0;

    if (!$self->vlanNumberExists($vlan_number)) {
	print STDERR "ERROR: VLAN $vlan_number does not exist\n";
	return 1;
    }

    #
    # If this switch supports private VLANs, check to see if the VLAN we're
    # putting it into is a secondary private VLAN
    #
    my $privateVlan = 0;
    if ($self->{SUPPORTS_PRIVATE}) {
	$self->debug("Checking to see if vlan is private ... ");
	my $PrivateType = "cpvlanVlanPrivateVlanType";
	my $type = snmpitGetFatal($self->{SESS},[$PrivateType,"1.$vlan_number"]);
	$self->debug("type is $type ... ");
	if ($type eq "community" ||  $type eq "isolated") {
	    $self->debug("It is\n");
	    $privateVlan = 1;
	} else {
	    $self->debug("It isn't\n");
	}
    }

    my $PortVlanMemb;
    my $format;
    if ($self->{OSTYPE} eq "CatOS") {
	if (!$privateVlan) {
	    $PortVlanMemb = "vlanPortVlan"; #index is ifIndex
	    $format = $PORT_FORMAT_MODPORT;
	} else {
	    $PortVlanMemb = "cpvlanPrivatePortSecondaryVlan";
	    $format = $PORT_FORMAT_IFINDEX;
	}
    } elsif ($self->{OSTYPE} eq "IOS") {
	$PortVlanMemb = "vmVlan"; #index is ifIndex
	$format = $PORT_FORMAT_IFINDEX;
    }

    #
    # Convert ports from the format the were passed in to the correct format
    #
    my @portlist = $self->convertPortFormat($format,@ports);

    #
    # We'll keep track of which ports suceeded, so that we don't try to
    # enable/disable, etc. ports that failed.
    #
    my @okports = ();
    foreach my $port (@portlist) {

	# 
	# Make sure the port didn't get mangled in conversion
	#
	if (!defined $port) {
	    print STDERR "Port not found, skipping\n";
	    $errors++;
	    next;
	}
	$self->debug("Putting port $port in VLAN $vlan_number\n");

	#
	# Do the acutal SNMP command
	#
	my $snmpvar = [$PortVlanMemb,$port,$vlan_number,'INTEGER'];
	my $retval = snmpitSetWarn($self->{SESS},$snmpvar);
	if (!$retval) {
	    $errors++;
	    next;
	} else {
	    push @okports, $port;
	}
    }

    #
    # Ports going into VLAN 1 are being taken out of circulation, so we
    # disable them. Otherwise, we need to make sure they get enabled.
    #
    if ($vlan_number == 1) {
	$self->debug("Disabling " . join(',',@okports) . "...");
	if ( my $rv = $self->portControl("disable",@okports) ) {
	    print STDERR "Port disable had $rv failures.\n";
	    $errors += $rv;
	}
    } else {
	$self->debug("Enabling "  . join(',',@okports) . "...");
	if ( my $rv = $self->portControl("enable",@okports) ) {
	    print STDERR "Port enable had $rv failures.\n";
	    $errors += $rv;
	}
    }

    return $errors;
}

#
# Remove all ports from the given VLANs, which are given as Cisco-specific
# VLAN numbers
#
# usage: removePortsFromVlan(self,int vlans)
#	 returns 0 on sucess.
#	 returns the number of failed ports on failure.
#
sub removePortsFromVlan($@) {
    my $self = shift;
    my @vlan_numbers = @_;

    #
    # Make sure the VLANs actually exist
    #
    foreach my $vlan_number (@vlan_numbers) {
	if (!$self->vlanNumberExists($vlan_number)) {
	    print STDERR "ERROR: VLAN $vlan_number does not exist\n";
	    return 1;
	}
    }

    #
    # Make a hash of the vlan number for easy lookup later
    #
    my %vlan_numbers = ();
    @vlan_numbers{@vlan_numbers} = @vlan_numbers;

    #
    # Get a list of the ports in the VLAN
    #
    my $VlanPortVlan;
    if ($self->{OSTYPE} eq "CatOS") {
	$VlanPortVlan = "vlanPortVlan"; #index is ifIndex
    } elsif ($self->{OSTYPE} eq "IOS") {
	$VlanPortVlan = "vmVlan"; #index is ifIndex
    }
    my @ports;

    #
    # Walk the tree to find VLAN membership
    #
    my ($rows) = $self->{SESS}->bulkwalk(0,32,$VlanPortVlan);
    foreach my $rowref (@$rows) {
	my ($name,$modport,$port_vlan_number) = @$rowref;
	$self->debug("Got $name $modport $port_vlan_number\n");
	if ($vlan_numbers{$port_vlan_number}) {
	    push @ports, $modport;
	}
    }

    $self->debug("About to remove ports " . join(",",@ports) . "\n");
    if (@ports) {
	return $self->setPortVlan(1,@ports);
    } else {
	return 0;
    }
}

#
# Remove the given VLAN from this switch. This presupposes that all of its
# ports have already been removed with removePortsFromVlan(). The VLAN is
# given as a Cisco-specific VLAN number
#
# usage: removeVlan(self,int vlan)
#	 returns 1 on success
#	 returns 0 on failure
#
#
sub removeVlan($@) {
    my $self = shift;
    my @vlan_numbers = @_;

    #
    # Need to lock the VLAN edit buffer
    #
    if (!$self->vlanLock()) {
    	return 0;
    }

    my $errors = 0;

    foreach my $vlan_number (@vlan_numbers) {
	#
	# Make sure the VLAN actually exists
	#
	if (!$self->vlanNumberExists($vlan_number)) {
	    print STDERR "ERROR: VLAN $vlan_number does not exist\n";
	    return 0;
	}

	#
	# Perform the actual removal
	#
	my $VlanRowStatus = 'vtpVlanEditRowStatus'; # vlan is index

	print "  Removing VLAN #$vlan_number on $self->{NAME} ... ";
	my $RetVal = $self->{SESS}->set([$VlanRowStatus,"1.$vlan_number",
					 "destroy","INTEGER"]);
	if ($RetVal) {
	    print "Succeeded.\n";
	} else {
	    print "Failed.\n";
	    $errors++;
	}
    }

    #
    # Unlock whether successful or not
    #
    $self->vlanUnlock();

    if ($errors) {
	return 0;
    } else {
	return 1;
    }

}

#
# TODO: Cleanup
#
sub UpdateField($$$@) {
    my $self = shift;
    # returns 0 on success, # of failed ports on failure
    $self->debug("UpdateField: '@_'\n");
    my ($OID,$val,@ports)= @_;
    my $Status = 0;
    my $err = 0;
    foreach my $port (@ports) {
	my ($trans) = convertPortFormat($PORT_FORMAT_NODEPORT,$port);
	if (!defined $trans) {
	    $trans = ""; # Guard against some uninitialized value warnings
	}
	$self->debug("Checking port $port ($trans) for $val...");
	$Status = snmpitGetWarn($self->{SESS},[$OID,$port]);
	if (!defined $Status) {
	    warn "Port $port ($trans), change to $val: No answer from device\n";
	    return -1;		# return error
	} else {
	    $self->debug("Okay.\n");
	    $self->debug("Port $port was $Status\n");
	    if ($Status ne $val) {
		$self->debug("Setting $port to $val...");
		# Don't use async
		my $result = $self->{SESS}->set([$OID,$port,$val,"INTEGER"]);
		$self->debug("Set returned '$result'\n") if (defined $result);
		if ($self->{BLOCK}) {
		    my $n = 0;
		    while ($Status ne $val) {
			$Status = snmpitGetWarn($self->{SESS},[$OID,$port]);
			$self->debug("Value for $port was $Status\n");
			select (undef, undef, undef, .25); # wait .25 seconds
			$n++;
			if ($n > 20) {
			    $err++;
			    $self->debug("Timing out...");
			    last;
			}
		    }
		    $self->debug("Okay.\n");
		} else {
		    $self->debug("\n");
		}
	    }
	}
    }
    # returns 0 on success, # of failed ports on failure
    $err;
}

#
# List all VLANs on the device
#
# usage: listVlans($self)
# see snmpit_cisco_stack.pm for a description of return value format
#
sub listVlans($) {
    my $self = shift;

    $self->debug("Getting VLAN info...\n");
    # We don't need VlanIndex really...
    my $VlanName = ["vtpVlanName"]; # index by 1.vlan #

    my $VlanPortVlan;
    if ($self->{OSTYPE} eq "CatOS") {
	$VlanPortVlan = "vlanPortVlan"; #index is ifIndex
    } elsif ($self->{OSTYPE} eq "IOS") {
	$VlanPortVlan = "vmVlan"; #index is ifIndex
    }

    #
    # Walk the tree to find the VLAN names
    #
    my ($rows) = $self->{SESS}->bulkwalk(0,32,$VlanName);
    my %Names = ();
    my %Members = ();
    foreach my $rowref (@$rows) {
	my ($name,$vlan_number,$vlan_name) = @$rowref;
	#
	# We get the VLAN number in the form 1.number - we need to strip
	# off the '1.' to make it useful
	#
	$vlan_number =~ s/^1\.//;

	$self->debug("Got $name $vlan_number $vlan_name\n");
	if (!$Names{$vlan_number}) {
	    $Names{$vlan_number} = $vlan_name;
	    @{$Members{$vlan_number}} = ();
	}
    }

    #
    # Walk the tree for the VLAN members
    #
    ($rows) = $self->{SESS}->bulkwalk(0,32,$VlanPortVlan);
    foreach my $rowref (@$rows) {
	my ($name,$modport,$vlan_number) = @$rowref;
	$self->debug("Got $name $modport $vlan_number\n",3);
	my ($node) = $self->convertPortFormat($PORT_FORMAT_NODEPORT,$modport);
	if (!$node) {
	    $modport =~ s/\./\//;
	    $node = $self->{NAME} . ".$modport";
	}
	push @{$Members{$vlan_number}}, $node;
	if (!$Names{$vlan_number}) {
	    $self->debug("listVlans: WARNING: port $self->{NAME}.$modport in non-existant " .
		"VLAN $vlan_number\n");
	}
    }

    #
    # Build a list from the name and membership lists
    #
    my @list = ();
    foreach my $vlan_id (sort {$a <=> $b} keys %Names) {
    	if ($vlan_id != 1) {
	    #
    	    # Special case for Cisco - VLAN 1 is special and should not
    	    # be reported
	    #
    	    push @list, [$Names{$vlan_id},$vlan_id,$Members{$vlan_id}];
    	}
    }
    $self->debug(join("\n",(map {join ",", @$_} @list))."\n");

    return @list;
}

#
# Walk a table that's indexed by ifindex. Convert the ifindex to a port, and
# stuff the value into the given hash
#
# usage: walkTableIfIndex($self,$tableID,$hash,$procfun)
#        $tableID is the name of the table to walk
#        $hash is a reference to the hash we will be updating
#        $procfun is a function run on the data for pre-processing
# returns: nothing
# Internal-only function
#
sub walkTableIfIndex($$$;$) {
    my $self = shift;
    my ($table,$hash,$fun) = @_;
    if (!$fun) {
        $fun = sub { $_[0]; }
    }

    #
    # Grab the whole table in one fell swoop
    #
    my @table = $self->{SESS}->bulkwalk(0,32,$table);

    foreach my $table (@table) {
        foreach my $row (@$table) {
            my ($oid,$index,$data) = @$row;

            #
            # Convert the ifindex we got into a port
            # XXX - Should use convertPortFormat(), right? I've preserved the
            # historical code in case it has some special behavior we depend on
            #
            if (! defined $self->{IFINDEX}{$index}) { next; }
            my $port = portnum("$self->{NAME}:$index")
                || portnum("$self->{NAME}:".$self->{IFINDEX}{$index});
            if (! defined $port) { next; } # Skip if we don't know about it
            
            #
            # Apply the user's processing function
            #
            my $pdata = &$fun($data);
            ${$hash}{$port} = $pdata;
        }
    }
}


#
# List all ports on the device
#
# usage: listPorts($self)
# see snmpit_cisco_stack.pm for a description of return value format
#
#
sub listPorts($) {
    my $self = shift;

    my %Able = ();
    my %Link = ();
    my %speed = ();
    my %duplex = ();

    $self->debug("Getting port information...\n");
    $self->walkTableIfIndex('ifAdminStatus',\%Able,
        sub { if ($_[0] =~ /up/) { "yes" } else { "no" } });
    $self->walkTableIfIndex('ifOperStatus',\%Link);
    $self->walkTableIfIndex('portAdminSpeed',\%speed);
    $self->walkTableIfIndex('portDuplex',\%duplex);
    # Insert stuff here to get ifSpeed if necessary... AdminSpeed is the
    # _desired_ speed, and ifSpeed is the _real_ speed it is using

    #
    # Put all of the data gathered in the loop into a list suitable for
    # returning
    #
    my @rv = ();
    foreach my $id ( keys %Able ) {
	my $vlan;
	if (! defined ($speed{$id}) ) { $speed{$id} = " "; }
	if (! defined ($duplex{$id}) ) { $duplex{$id} = " "; }
	$speed{$id} =~ s/s([10]+)000000/${1}Mbps/;
	push @rv, [$id,$Able{$id},$Link{$id},$speed{$id},$duplex{$id}];
    }
    return @rv;
}

# 
# Get statistics for ports on the switch
#
# usage: getPorts($self)
# see snmpit_cisco_stack.pm for a description of return value format
#
# TODO: Clean up undefined variable warnings
#
sub getStats ($) {
    my $self = shift;

    #
    # Walk the tree for the VLAN members
    #
    my $vars = new SNMP::VarList(['ifInOctets'],['ifInUcastPkts'],
    				 ['ifInNUcastPkts'],['ifInDiscards'],
				 ['ifInErrors'],['ifInUnknownProtos'],
				 ['ifOutOctets'],['ifOutUcastPkts'],
				 ['ifOutNUcastPkts'],['ifOutDiscards'],
				 ['ifOutErrors'],['ifOutQLen']);
    my @stats = $self->{SESS}->bulkwalk(0,32,$vars);

    #
    # We need to flip the two-dimentional array we got from bulkwalk on
    # its side, and convert ifindexes into node:port
    #
    my $i = 0;
    my %stats;
    foreach my $array (@stats) {
	while (@$array) {
	    my ($name,$ifindex,$value) = @{shift @$array};
	    my ($port) = $self->convertPortFormat($PORT_FORMAT_NODEPORT,$ifindex);
	    if ($port) {
		${$stats{$port}}[$i] = $value;
	    }
	}
	$i++;
    }

    return map [$_,@{$stats{$_}}], sort {tbsort($a,$b)} keys %stats;

}

#
# Enable, or disable,  port on a trunk
#
# usage: setVlansOnTrunk(self, modport, value, vlan_numbers)
#        modport: module.port of the trunk to operate on
#        value: 0 to disallow the VLAN on the trunk, 1 to allow it
#	 vlan_numbers: An array of cisco-native VLAN numbers operate on
#        Returns 1 on success, 0 otherwise
#
sub setVlansOnTrunk($$$$) {
    my $self = shift;
    my ($modport, $value, @vlan_numbers) = @_;

    #
    # Some error checking
    #
    if (($value != 1) && ($value != 0)) {
	die "Invalid value $value passed to setVlanOnTrunk\n";
    }
    if (grep(/^1$/,@vlan_numbers)) {
	die "VLAN 1 passed to setVlanOnTrunk\n"
    }

    my ($ifIndex) = $self->convertPortFormat($PORT_FORMAT_IFINDEX,$modport);

    #
    # If this is part of an EtherChannel, we have to find the ifIndex for the
    # channel.
    # TODO: Perhaps this should be general - ie. $self{IFINDEX} should have
    # the channel ifIndex the the port is in a channel. Not sure that
    # this is _always_ beneficial, though
    #
    my $channel = snmpitGetFatal($self->{SESS},["pagpGroupIfIndex",$ifIndex]);
    if (($channel =~ /^\d+$/) && ($channel != 0)) {
	$ifIndex = $channel;
    }

    #
    # Get the exisisting bitfield for allowed VLANs on the trunk
    #
    my $bitfield = snmpitGetFatal($self->{SESS},
	    ["vlanTrunkPortVlansEnabled",$ifIndex]);
    my $unpacked = unpack("B*",$bitfield);
    
    # Put this into an array of 1s and 0s for easy manipulation
    my @bits = split //,$unpacked;

    # Just set the bit of the ones we want to change
    foreach my $vlan_number (@vlan_numbers) {
	$bits[$vlan_number] = $value;
    }

    # Pack it back up...
    $unpacked = join('',@bits);

    $bitfield = pack("B*",$unpacked);

    # And save it back...
    my $rv = $self->{SESS}->set(["vlanTrunkPortVlansEnabled",$ifIndex,$bitfield,
    	    "OCTETSTR"]);
    if ($rv) {
	return 1;
    } else {
	return 0;
    }

}

#
# Clear the list of allowed VLANs from a trunk
#
# usage: clearAllVlansOnTrunk(self, modport)
#        modport: module.port of the trunk to operate on
#        Returns 1 on success, 0 otherwise
#
sub clearAllVlansOnTrunk($$) {
    my $self = shift;
    my ($modport) = @_;

    my ($ifIndex) = $self->convertPortFormat($PORT_FORMAT_IFINDEX,$modport);

    #
    # If this is part of an EtherChannel, we have to find the ifIndex for the
    # channel.
    # TODO: Perhaps this should be general - ie. $self{IFINDEX} should have
    # the channel ifIndex the the port is in a channel. Not sure that
    # this is _always_ beneficial, though
    #
    my $channel = snmpitGetFatal($self->{SESS},["pagpGroupIfIndex",$ifIndex]);
    if (($channel =~ /^\d+$/) && ($channel != 0)) {
	$ifIndex = $channel;
    }

    #
    # Get the exisisting bitfield for allowed VLANs on the trunk
    #
    my $bitfield = snmpitGetFatal($self->{SESS},
	    ["vlanTrunkPortVlansEnabled",$ifIndex]);
    my $unpacked = unpack("B*",$bitfield);
    
    # Put this into an array of 1s and 0s for easy manipulation
    my @bits = split //,$unpacked;

    # Clear the bit for every VLAN
    foreach my $index (0 .. $#bits) {
	$bits[$index] = 0;
    }

    # Pack it back up...
    $unpacked = join('',@bits);

    $bitfield = pack("B*",$unpacked);

    # And save it back...
    my $rv = $self->{SESS}->set(["vlanTrunkPortVlansEnabled",$ifIndex,$bitfield,
    	    "OCTETSTR"]);
    if ($rv) {
	return 1;
    } else {
	return 0;
    }

}

#
# Enable trunking on a port
#
# usage: enablePortTrunking(self, modport, nativevlan)
#        modport: module.port of the trunk to operate on
#        nativevlan: VLAN number of the native VLAN for this trunk
#        Returns 1 on success, 0 otherwise
#
sub enablePortTrunking($$$) {
    my $self = shift;
    my ($port,$native_vlan) = @_;

    my ($ifIndex) = $self->convertPortFormat($PORT_FORMAT_IFINDEX,$port);

    #
    # Clear out the list of allowed VLANs for this trunk port, so that when it
    # comes up, there is not some race condition
    #
    my $rv = $self->clearAllVlansOnTrunk($port);
    if (!$rv) {
	warn "ERROR: Unable to clear VLANs on trunk\n";
	return 0;
    } 

    #
    # Set the type of the trunk - we only do dot1q for now
    #
    my $trunkType = ["vlanTrunkPortEncapsulationType",$ifIndex,"dot1Q","INTEGER"];
    $rv = snmpitSetWarn($self->{SESS},$trunkType);
    if (!$rv) {
	warn "ERROR: Unable to set encapsulation type\n";
	return 0;
    }

    #
    # Set the native VLAN for this trunk
    #
    my $nativeVlan = ["vlanTrunkPortNativeVlan",$ifIndex,$native_vlan,"INTEGER"];
    $rv = snmpitSetWarn($self->{SESS},$nativeVlan);
    if (!$rv) {
	warn "ERROR: Unable to set native VLAN on trunk\n";
	return 0;
    }

    #
    # Finally, enable trunking!
    #
    my $trunkEnable = ["vlanTrunkPortDynamicState",$ifIndex,"on","INTEGER"];
    $rv = snmpitSetWarn($self->{SESS},$trunkEnable);
    if (!$rv) {
	warn "ERROR: Unable to enable trunking\n";
	return 0;
    }

    #
    # Allow the native VLAN to cross the trunk
    #
    $rv = $self->setVlansOnTrunk($port,1,$native_vlan);
    if (!$rv) {
	warn "ERROR: Unable to enable native VLAN on trunk\n";
	return 0;
    }

    return 1;
    
}

#
# Disable trunking on a port
#
# usage: disablePortTrunking(self, modport)
#        modport: module.port of the trunk to operate on
#        Returns 1 on success, 0 otherwise
#
sub disablePortTrunking($$) {
    my $self = shift;
    my ($port) = @_;

    my ($ifIndex) = $self->convertPortFormat($PORT_FORMAT_IFINDEX,$port);


    #
    # Clear out the list of allowed VLANs for this trunk port
    #
    my $rv = $self->clearAllVlansOnTrunk($port);
    if (!$rv) {
	warn "ERROR: Unable to clear VLANs on trunk\n";
	return 0;
    } 

    #
    # Disable trunking!
    #
    my $trunkDisable = ["vlanTrunkPortDynamicState",$ifIndex,"off","INTEGER"];
    $rv = snmpitSetWarn($self->{SESS},$trunkDisable);
    if (!$rv) {
	warn "ERROR: Unable to enable trunking\n";
	return 0;
    }

    return 1;
    
}

#
# Reads the IfIndex table from the switch, for SNMP functions that use 
# IfIndex rather than the module.port style. Fills out the objects IFINDEX
# members,
#
# usage: readifIndex(self)
#        returns nothing
#
sub readifIndex($) {
    my $self = shift;

    #
    # How we fill this table is highly dependant on which OS the switch
    # is running - CatOS provides a convenient table to convert from
    # node/port to ifindex, but under IOS, we have to infer it from the
    # port description
    #

    if ($self->{OSTYPE} eq "CatOS") {
	my ($rows) = $self->{SESS}->bulkwalk(0,32,["portIfIndex"]);

	foreach my $rowref (@$rows) {
	    my ($name,$modport,$ifindex) = @$rowref;

	    $self->{IFINDEX}{$modport} = $ifindex;
	    $self->{IFINDEX}{$ifindex} = $modport;
	}
    } elsif ($self->{OSTYPE} eq "IOS") {
	my ($rows) = $self->{SESS}->bulkwalk(0,32,["ifDescr"]);
   
	foreach my $rowref (@$rows) {
	    my ($name,$iid,$descr) = @$rowref;
	    if ($descr =~ /(\w*)(\d+)\/(\d+)$/) {
                my $type = $1;
                my $module = $2;
                my $port = $3;
                if ($self->{NON_MODULAR_HACK}) {
                    #
                    # Hack for non-modular switches with both 100Mbps and
                    # gigabit ports - consider gigabit ports to be on module 1
                    #
                    if (($module == 0) && ($type =~ /^gi/i)) {
                        $module = 1;
                        $self->debug("NON_MODULAR_HACK: Moving $descr to mod $module\n");
                    }
                }
		my $modport = "$module.$port";
		my $ifindex;
		if (defined($iid) && ($iid ne "")) {
		    $ifindex = $iid;
		} else {
		    $name =~ /(\d+)$/;
		    $ifindex = $1;
		}

		$self->{IFINDEX}{$modport} = $ifindex;
		$self->{IFINDEX}{$ifindex} = $modport;
	    }
	}
    }
}

#
# Read a set of values for all given ports.
#
# usage: getFields(self,ports,oids)
#        ports: Reference to a list of ports, in any allowable port format
#        oids: A list of OIDs to reteive values for
#
# On sucess, returns a two-dimensional list indexed by port,oid
#
sub getFields($$$) {
    my $self = shift;
    my ($ports,$oids) = @_;

    my @ifindicies = $self->convertPortFormat($PORT_FORMAT_IFINDEX,@$ports);
    my @oids = @$oids;

    
    #
    # Put together an SNMP::VarList for all the values we want to get
    #
    my @vars = ();
    foreach my $ifindex (@ifindicies) {
	foreach my $oid (@oids) {
	    push @vars, ["$oid","$ifindex"];
	}
    }

    #
    # If we try to ask for too many things at once, we get back really bogus
    # errors. So, we limit ourselves to an arbitrary number that, by
    # experimentation, works.
    #
    my $maxvars = 16;
    my @results = ();
    while (@vars) {
	my $varList = new SNMP::VarList(splice(@vars,0,$maxvars));
	my $rv = $self->{SESS}->get($varList);
	push @results, @$varList;
    }
	    
    #
    # Build up the two-dimensional list for returning
    #
    my @return = ();
    foreach my $i (0 .. $#ifindicies) {
	foreach my $j (0 .. $#oids) {
	    my $val = shift @results;
	    $return[$i][$j] = $$val[2];
	}
    }

    return @return;
}

#
# Tell the switch to dump its configuration file to the specified file
# on the specified server, via TFTP
#
# Usage: writeConfigTFTP($server, $filename). The server can be either a
#        hostname or an IP address. The destination filename must exist and be
#        world-writable, or TFTP will refuse to write to it
# Returns: 1 on success, 0 otherwise
#
sub writeConfigTFTP($$$) {
    my ($self,$server,$filename) = @_;
    
    #
    # TODO - convert from Fatal() to Warn() calls
    #

    #
    # The MIB this function currently uses is only supported on CatOS. IOS
    # actually has a better one (CISCO-CONFIG-COPY-MIB), so we'll be able to
    # support it in the future
    #
    if ($self->{OSTYPE} ne "CatOS") {
	warn "writeConfigTFTP only supported on CatOS\n";
	return 0;
    }

    #
    # Start off by resolving the server's name into an IP address
    #
    my $ip = inet_aton($server);
    if (!$ip) {
	warn "Unable to lookup hostname $server\n";
	return 0;
    }

    my $ipstr = join(".",unpack('C4',$ip));

    #
    # Set up a few values on the switch to tell it where to stick the config
    # file
    #
    my $setHost = ["tftpHost",0,$ipstr,"STRING"];
    my $setFilename = ["tftpFile",0,$filename,"STRING"];

    snmpitSetFatal($self->{SESS},$setHost);
    snmpitSetFatal($self->{SESS},$setFilename);

    #
    # Okay, go!
    #
    my $tftpGo = ["tftpAction","0","uploadConfig","INTEGER"];
    snmpitSetFatal($self->{SESS},$tftpGo);

    #
    # Poll to see if it suceeded - wait for a while, but not forever!
    #
    my $tftpResult = ["tftpResult",0];
    my $iters = 0;
    my $rv;
    while (($rv = snmpitGetFatal($self->{SESS},$tftpResult))
	eq "inProgress" && ($iters < 30)) {
	$iters++;
	sleep(1);
    }
    if ($iters == 30) {
	warn "TFTP write took longer than 30 seconds!";
	return 0;
    } else {
	if ($rv ne "success") {
	    warn "TFTP write failed with error $rv\n";
	    return 0;
	} else {
	    return 1;
	}
    }
}

#
# Prints out a debugging message, but only if debugging is on. If a level is
# given, the debuglevel must be >= that level for the message to print. If
# the level is omitted, 1 is assumed
#
# Usage: debug($self, $message, $level)
#
sub debug($$:$) {
    my $self = shift;
    my $string = shift;
    my $debuglevel = shift;
   if (!(defined $debuglevel)) {
	$debuglevel = 1;
    }
    if ($self->{DEBUG} >= $debuglevel) {
	print STDERR $string;
    }
}

# End with true
1;
