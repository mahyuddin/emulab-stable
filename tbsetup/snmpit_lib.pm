#!/usr/bin/perl -w
#
# EMULAB-LGPL
# Copyright (c) 2000-2004 University of Utah and the Flux Group.
# All rights reserved.
#

#
# Module of subroutines useful to snmpit and its modules
#

package snmpit_lib;

use Exporter;
@ISA = ("Exporter");
@EXPORT = qw( macport portnum Dev vlanmemb vlanid
		getTestSwitches getControlSwitches getSwitchesInStack
		getVlanPorts
		getExperimentVlans getDeviceNames getDeviceType
		getInterfaceSettings mapPortsToDevices getSwitchStack
		getStackType getDeviceOptions getTrunks getTrunksFromSwitches
		getExperimentPorts snmpitGet snmpitGetWarn snmpitGetFatal
		snmpitSet snmpitSetWarn snmpitSetFatal snmpitWarn snmpitFatal
		printVars tbsort );

use English;
use libdb;
use libtestbed;
use strict;
use SNMP;

my $TBOPS = libtestbed::TB_OPSEMAIL;

my $debug = 0;

my $DEFAULT_RETRIES = 10;

my $SNMPIT_GET = 0;
my $SNMPIT_SET = 1;

my %Devices=();
# Devices maps device names to device IPs

my %Interfaces=();
# Interfaces maps pcX:Y<==>MAC

my %Ports=();
# Ports maps pcX:Y<==>switch:port

my %vlanmembers=();
# vlanmembers maps id -> members

my %vlanids=();
# vlanids maps pid:eid <==> id

my $snmpitErrorString;

#
# Initialize the library
#
sub init($) {
    $debug = shift || $debug;
    &ReadTranslationTable;
    return 0;
}

#
# Map between interfaces and mac addresses
#
sub macport {
    my $val = shift || "";
    return $Interfaces{$val};
}

#
# Map between interfaces and port numbers
#
sub portnum {
    my $val = shift || "";
    return $Ports{$val};
}

#
# Map between interfaces and the devices they are attached to
#
sub Dev {
    my $val = shift || "";
    return $Devices{$val};
}

#
# This function fills in %Interfaces and %Ports
# They hold pcX:Y<==>MAC and pcX:Y<==>switch:port respectively
#
sub ReadTranslationTable {
    my $name="";
    my $mac="";
    my $switchport="";

    print "FILLING %Interfaces\n" if $debug;
    my $result = DBQueryFatal("select * from interfaces;");
    while ( @_ = $result->fetchrow_array()) {
	$name = "$_[0]:$_[1]";
	if ($_[2] != 1) {$name .=$_[2]; }
	$mac = "$_[3]";
	if ($name =~ /(sh\d+)(-\d)(:\d)?/ ) { $name = "$1$3"; }
	$Interfaces{$name} = $mac;
	$Interfaces{$mac} = $name;
	print "Interfaces: $mac <==> $name\n" if $debug > 1;
    }

    print "FILLING %Devices\n" if $debug;
    $result = DBQueryFatal("select i.node_id,i.IP,n.type from interfaces as i ".
	    "left join nodes as n on n.node_id=i.node_id ".
	    "left join node_types as nt on n.type=nt.type ".
	    "where n.role!='testnode' and i.iface=nt.control_iface");
    while ( my ($name,$ip,$type) = $result->fetchrow_array()) {
	$Devices{$name} = $ip;
	$Devices{$ip} = $name;
	print "Devices: $name ($type) <==> $ip\n" if $debug > 1;
    }

    print "FILLING %Ports\n" if $debug;
    $result = DBQueryFatal("select node_id1,card1,port1,node_id2,card2,port2 ".
	    "from wires;");
    while ( @_ = $result->fetchrow_array()) {
	$name = "$_[0]:$_[1]";
	print "Name='$name'\t" if $debug > 2;
	print "Dev='$_[3]'\t" if $debug > 2;
	$switchport = join(":",($_[3],$_[4]));
	$switchport .=".$_[5]";
	print "switchport='$switchport'\n" if $debug > 2;
	$Ports{$name} = $switchport;
	$Ports{$switchport} = $name;
	print "Ports: '$name' <==> '$switchport'\n" if $debug > 1;
    }

}

#
# Returns an array of ports (in node:card form) used by the given VLANs
#
sub getVlanPorts (@) {
    my @vlans = @_;
    # Silently exit if they passed us no VLANs
    if (!@vlans) {
	return ();
    }

    my $result = DBQueryFatal("SELECT members FROM vlans WHERE " .
	join(' OR ', map("id='$_'",@vlans))); # Join "id='foo'" with ORs
    my @ports;
    while (my @row = $result->fetchrow()) {
	my $members = $row[0];
	# $members is a space-seprated list
	foreach my $port (split /\s+/,$members) {
	    # Due to the inconsistent nature of our tables (curses!), we
	    # have to do some conversion here
	    $port =~ /^(.+):(.+)/;
	    my ($node,$iface) = ($1,$2);
	    if (!defined($node) || !defined($iface)) {
		warn "WARNING: Bad node in VLAN: $port - skipping\n";
		next;
	    }
	    my $result = DBQueryFatal("SELECT card FROM interfaces " .
	    	"WHERE node_id='$node' AND iface='$iface'");
	    if (!$result->num_rows()) {
		warn "WARNING: Bad node/iface pair in VLAN: $port - skipping\n";
		next;
	    }

	    my $card = ($result->fetchrow())[0];

	    # OK, finally have the info we need
	    push @ports, $node . ":" . $card;
	}
    }
    return @ports;
}

#
# Returns an array of all VLAN id's used by a given experiment.
# Optional list of vlan ids restricts operation to just those vlans,
#
sub getExperimentVlans ($$@) {
    my ($pid, $eid, @optvlans) = @_;

    my $result =
	DBQueryFatal("SELECT id FROM vlans WHERE pid='$pid' AND eid='$eid' ".
		     (@optvlans ?
		      "and (" . join(' OR ', map("id='$_'", @optvlans)) . ")" :
		      ""));
    
    my @vlans = (); 
    while (my @row = $result->fetchrow()) {
	push @vlans, $row[0];
    }

    return @vlans;
}

#
# Returns an array of all ports used by a given experiment
#
sub getExperimentPorts ($$) {
    my ($pid, $eid) = @_;

    return getVlanPorts(getExperimentVlans($pid,$eid));
}

#
# Usage: getDeviceNames(@ports)
#
# Returns an array of the names of all devices used in the given ports
#
sub getDeviceNames(@) {
    my @ports = @_;
    my %devices = ();
    foreach my $port (@ports) {
	#
	# Accept either node:port or switch.port
	#
	my $device;
	if ($port =~ /^([^:]+):(.+)$/) {
	    my ($node,$card) = ($1,$2);
	    if (!defined($node) || !defined($card)) { # Oops, $card can be 0
		die "Bad port given: $port\n";
	    }
	    my $result = DBQueryFatal("SELECT node_id2 FROM wires " .
		"WHERE node_id1='$node' AND card1=$card");
	    if (!$result->num_rows()) {
		warn "No database entry found for port $port - Skipping\n";
		next;
	    }
	    # This is a loop, on the off chance chance that a single port on a
	    # node can be connected to multiple ports on the switch.
	    while (my @row = $result->fetchrow()) {
		$device = $row[0];
	    }
	} elsif ($port =~ /^([^.]+)\.\d+(\/\d+)?$/) {
		$device = $1;
	} else {
	    warn "Invalid format for port $port - Skipping\n";
	    next;
	}

	$devices{$device} = 1;
    }
    return (sort {tbsort($a,$b)} keys %devices);
}

#
# Returns a hash, keyed by device, of all ports in the given list that are
# on that device
#
sub mapPortsToDevices(@) {
    my @ports = @_;
    my %map = ();
    foreach my $port (@ports) {
	my ($device) = getDeviceNames($port);
	if (defined($device)) { # getDeviceNames does the job of warning users
	    push @{$map{$device}},$port;
	}
    }
    return %map;
}

#
# Returns the device type for the given node_id
#
sub getDeviceType ($) {

    my ($node) = @_;

    my $result =
	DBQueryFatal("SELECT type FROM nodes WHERE node_id='$node'");

    my @row = $result->fetchrow();
    # Sanity check - make sure the node exists
    if (!@row) {
	die "No such node: $node\n";
    }

    return $row[0];
}

#
# Returns (current_speed,duplex) for the given interface (in node:port form)
#
sub getInterfaceSettings ($) {

    my ($interface) = @_;

    $interface =~ /^(.+):(\d+)$/;
    my ($node, $port) = ($1, $2);
    if ((!defined $node) || (!defined $port)) {
	die "getInterfaceSettings: Bad interface ($interface) given\n";
    }

    my $result =
	DBQueryFatal("SELECT current_speed, duplex FROM interfaces " .
		     "WHERE node_id='$node' and card=$port");

    my @row = $result->fetchrow();
    # Sanity check - make sure the interface exists
    if (!@row) {
	die "No such interface: $interface\n";
    }

    return @row;
}

#
# Returns an array with then names of all switches identified as test switches
#
sub getTestSwitches () {
    my $result =
	DBQueryFatal("SELECT node_id FROM nodes WHERE role='testswitch'");
    my @switches = (); 
    while (my @row = $result->fetchrow()) {
	push @switches, $row[0];
    }

    return @switches;
}

#
# Returns an array with the names of all switches identified as control switches
#
sub getControlSwitches () {
    my $result =
	DBQueryFatal("SELECT node_id FROM nodes WHERE role='ctrlswitch'");
    my @switches = (); 
    while (my @row = $result->fetchrow()) {
	push @switches, $row[0];
    }

    return @switches;
}

#
# Returns an array with the names of all switches in the given stack
#
sub getSwitchesInStack ($) {
    my ($stack_id) = @_;
    my $result = DBQueryFatal("SELECT node_id FROM switch_stacks " .
	"WHERE stack_id='$stack_id'");
    my @switches = (); 
    while (my @row = $result->fetchrow()) {
	push @switches, $row[0];
    }

    return @switches;
}

#
# Returns the stack_id that a switch belongs to
#
sub getSwitchStack($) {
    my $switch = shift;
    my $result = DBQueryFatal("SELECT stack_id FROM switch_stacks WHERE " .
    		"node_id='$switch'");
    if (!$result->numrows()) {
	print STDERR "No stack_id found for switch $switch\n";
	return undef;
    } else {
	my ($stack_id) = ($result->fetchrow());
	return $stack_id;
    }
}

#
# Returns the type of the given stack_id. If called in list context, also
# returns whether or not the stack supports private VLANs, whether it
# uses a single VLAN domain, and the SNMP community to use.
#
sub getStackType($) {
    my $stack = shift;
    my $result = DBQueryFatal("SELECT stack_type, supports_private, " .
	"single_domain, snmp_community FROM switch_stack_types " .
	"WHERE stack_id='$stack'");
    if (!$result->numrows()) {
	print STDERR "No stack found called $stack\n";
	return undef;
    } else {
	my ($stack_type,$supports_private,$single_domain,$community)
	    = ($result->fetchrow());
	if (defined wantarray) {
	    return ($stack_type,$supports_private,$single_domain, $community);
	} else {
	    return $stack_type;
	}
    }
}

#
# Get a hash that describes the configuration options for a switch. The idea is
# that the device's object will call this method to get some options.  Right
# now, all this stuff actually comes from the stack, but there could be
# switch-specific configuration in the future. Provides defaults for NULL
# columns
#
# We could probably make this look more like an object, for type checking, but
# that just doesn't seem necessary yet.
#
sub getDeviceOptions($) {
    my $switch = shift;
    my %options;

    my $result = DBQueryFatal("SELECT supports_private, " .
	"single_domain, snmp_community, min_vlan, max_vlan " .
	"FROM switch_stacks AS s left join switch_stack_types AS t " .
	"    ON s.stack_id = t.stack_id ".
	"WHERE s.node_id='$switch'");

    if (!$result->numrows()) {
	print STDERR "No switch $switch found, or it is not in a stack\n";
	return undef;
    }

    my ($supports_private, $single_domain, $snmp_community, $min_vlan,
	$max_vlan) = $result->fetchrow();

    $options{'supports_private'} = $supports_private;
    $options{'single_domain'} = $single_domain;
    $options{'snmp_community'} = $snmp_community || "public";
    $options{'min_vlan'} = $min_vlan || 2;
    $options{'max_vlan'} = $max_vlan || 1000;

    $options{'type'} = getDeviceType($switch);

    if ($debug) {
	print "Options for $switch:\n";
	while (my ($key,$value) = each %options) {
	    print "$key = $value\n"
	}
    }

    return \%options;
}

#
# Returns a structure representing all trunk links. It's a hash, keyed by
# switch, that contains hash references. Each of the second level hashes
# is keyed by destination, with the value being an array reference that
# contains the card.port pairs to which the trunk is conencted. For exammple,
# ('cisco1' => { 'cisco3' => ['1.1','1.2'] },
#  'cisco3' => { 'cisco1' => ['2.1','2.2'] } )
#
sub getTrunks() {

    my %trunks = ();

    my $result = DBQueryFatal("SELECT node_id1, card1, port1, " .
	"node_id2, card2, port2 FROM wires WHERE type='Trunk'");

    while (my @row = $result->fetchrow()) {
	my ($node_id1, $card1, $port1, $node_id2, $card2, $port2)  = @row;
	push @{ $trunks{$node_id1}{$node_id2} }, "$card1.$port1";
	push @{ $trunks{$node_id2}{$node_id1} }, "$card2.$port2";
    }

    return %trunks;
	
}

#
# Find the best path from one switch to another. Returns an empty list if no
# path exists, otherwise returns a list of switch names. Arguments are:
# A reference to a hash, as returned by the getTrunks() function
# A reference to an array of unvisited switches: Use [keys %trunks]
# Two siwtch names, the source and the destination 
#
sub getTrunkPath($$$$) {
    my ($trunks, $unvisited, $src,$dst) = @_;
    if ($src eq $dst) {
	#
	# The source and destination are the same
	#
	return ($src);
    } elsif ($trunks->{$src}{$dst}) {
	#
	# The source and destination are directly connected
	#
	return ($src,$dst);
    } else {
	# The source and destination aren't directly connected. We'll need to 
	# recurse across other trunks to find solution
	my @minPath = ();

	#
	# We use the @$unvisited list to pick switches to traverse to, so
	# that we don't re-visit switches we've already been to, which would 
	# cause infinite recursion
	#
	foreach my $i (0 .. $#{$unvisited}) {
	    if ($trunks->{$src}{$$unvisited[$i]}) {

		#
		# We need to pull theswitch out of the unvisted list that we
		# pass to it.
		#
		my @list = @$unvisited;
		splice(@list,$i,1);

		#
		# Check to see if the path we get with this switch is the 
		# best one found so far
		#
		my @path = getTrunkPath($trunks,\@list,$$unvisited[$i],$dst);
		if (@path && ((!@minPath) || (@path < @minPath))) {
		    @minPath = @path;
		}
	    }

	}

	#
	# If we found a path, tack ourselves on the front and return. If not,
	# return the empty list of failure.
	#
	if (@minPath) {
	    return ($src,@minPath);
	} else {
	    return ();
	}
    }
}

#
# Returns a list of trunks, in the form [src, dest], from a path (as returned
# by getTrunkPath() ). For example, if the input is:
# (cisco1, cisco3, cisco4), the return value is:
# ([cisco1, cisco3], [cisco3, cisco4])
#
sub getTrunksFromPath(@) {
    my @path = @_;
    my @trunks = ();
    my $lastswitch = "";
    foreach my $switch (@path) {
	if ($lastswitch) {
	    push @trunks, [$lastswitch, $switch];
	}
	$lastswitch = $switch;
    }

    return @trunks;
}

#
# Given a list of lists of trunks (returned by multiple getTrunksFromPath() 
# calls), return a list of the unique trunks found in this list
#
sub getUniqueTrunks(@) {
    my @trunkLists = @_;
    my @unique = ();
    foreach my $trunkref (@trunkLists) {
	my @trunks = @$trunkref;
	TRUNK: foreach my $trunk (@trunks) {
	    # Since source and destination are interchangable, we have to
	    # check both possible orderings
	    foreach my $unique (@unique) {
		if ((($unique->[0] eq $trunk->[0]) &&
		     ($unique->[1] eq $trunk->[1])) ||
		    (($unique->[0] eq $trunk->[1]) &&
		     ($unique->[1] eq $trunk->[0]))) {
			 # Yep, it's already in the list - go to the next one
			 next TRUNK;
		}
	    }

	    # Made it through, we must not have seen this one before
	    push @unique, $trunk;
	}
    }

    return @unique;
}

#
# Given a trunk structure (as returned by getTrunks() ), and a list of switches,
# return a list of all trunks (in the [src, dest] form) that are needed to span
# all the switches (ie. which trunks the VLAN must be allowed on)
#
sub getTrunksFromSwitches($@) {
    my $trunks = shift;
    my @switches = @_;

    #
    # First, find the paths between each set of switches
    #
    my @paths = ();
    foreach my $switch1 (@switches) {
	foreach my $switch2 (@switches) {
	    push @paths, [ getTrunkPath($trunks, [ keys %$trunks ],
					$switch1, $switch2) ];
	}
    }

    #
    # Now, make a list of all the the trunks used by these paths
    #
    my @trunkList = ();
    foreach my $path (@paths) {
	push @trunkList, [ getTrunksFromPath(@$path) ];
    }

    #
    # Last, remove any duplicates from the list of trunks
    #
    my @trunks = getUniqueTrunks(@trunkList);

    return @trunks;

}

#
# Execute and SNMP command, retrying in case there are transient errors.
#
# usage: snmpitDoIt(getOrSet, session, var, [retries])
# args:  getOrSet - either $SNMPIT_GET or $SNMPIT_SET
#        session - SNMP::Session object, already connected to the SNMP
#                  device
#        var     - An SNMP::Varbind or a reference to a two-element array
#                  (similar to a single Varbind)
#        retries - Number of times to retry in case of failure
# returns: the value on sucess, undef on failure
#
sub snmpitDoIt($$$;$) {

    my ($getOrSet,$sess,$var,$retries) = @_;

    if (! defined($retries) ) {
	$retries = $DEFAULT_RETRIES;
    }

    #
    # Make sure we're given valid inputs
    #
    if (!$sess) {
	$snmpitErrorString = "No valid SNMP session given!\n";
	return undef;
    }

    my $array_size;
    if ($getOrSet == $SNMPIT_GET) {
	$array_size = 2;
    } else {
	$array_size = 4;
    }

    if ((ref($var) ne "SNMP::Varbind") &&
	    ((ref($var) ne "ARRAY") || ((@$var != $array_size) && (@$var != 4)))) {
	$snmpitErrorString = "Invalid SNMP variable given ($var)!\n";
	return undef;
    }

    #
    # Retry several times
    #
    foreach my $retry ( 1 .. $retries) {
	my $status;
	if ($getOrSet == $SNMPIT_GET) {
	    $status = $sess->get($var);
	} else {
	    $status = $sess->set($var);
	}

	#
	# Avoid unitialized variable warnings when printing errors
	#
	if (! defined($status)) {
	    $status = "(undefined)";
	}

	#
	# We detect errors by looking at the ErrorNumber variable from the
	# session
	#
	if ($sess->{ErrorNum}) {
	    my $type;
	    if ($getOrSet == $SNMPIT_GET) {
		$type = "get";
	    } else {
		$type = "set";
	    }
	    $snmpitErrorString  = "SNMPIT $type failed - variable was " .
				    printVars($var) . "\n";
	    $snmpitErrorString .= "Returned $status, ErrorNum was " .
		   "$sess->{ErrorNum}\n";
	    if ($sess->{ErrorStr}) {
		$snmpitErrorString .= "Error string is: $sess->{ErrorStr}\n";
	    }
	} else {
	    if ($getOrSet == $SNMPIT_GET) {
		return $var->[2];
	    } else {
	        return 1;
	    }
	}

	#
	# Don't flood requests too fast. Randomize the sleep a little so that
	# we don't end up with all our retries coming in at the same time.
	#
	sleep(2);
	select(undef, undef, undef, rand(2));
    }

    #
    # If we made it out, all of the attempts must have failed
    #
    return undef;
}

#
# usage: snmpitGet(session, var, [retries])
# args:  session - SNMP::Session object, already connected to the SNMP
#                  device
#        var     - An SNMP::Varbind or a reference to a two-element array
#                  (similar to a single Varbind)
#        retries - Number of times to retry in case of failure
# returns: the value on sucess, undef on failure
#
sub snmpitGet($$;$) {
    my ($sess,$var,$retries) = @_;
    my $result;

    $result = snmpitDoIt($SNMPIT_GET,$sess,$var,$retries);

    return $result;
}

#
# Same as snmpitGet, but send mail if any error occur
#
sub snmpitGetWarn($$;$) {
    my ($sess,$var,$retries) = @_;
    my $result;

    $result = snmpitDoIt($SNMPIT_GET,$sess,$var,$retries);

    if (! defined $result) {
	snmpitWarn("SNMP GET failed");
    }
    return $result;
}

#
# Same as snmpitGetWarn, but also exits from the program if there is a 
# failure.
#
sub snmpitGetFatal($$;$) {
    my ($sess,$var,$retries) = @_;
    my $result;

    $result = snmpitDoIt($SNMPIT_GET,$sess,$var,$retries);

    if (! defined $result) {
	snmpitFatal("SNMP GET failed");
    }
    return $result;
}

#
# usage: snmpitSet(session, var, [retries])
# args:  session - SNMP::Session object, already connected to the SNMP
#                  device
#        var     - An SNMP::Varbind or a reference to a two-element array
#                  (similar to a single Varbind)
#        retries - Number of times to retry in case of failure
# returns: true on success, undef on failure
#
sub snmpitSet($$;$) {
    my ($sess,$var,$retries) = @_;
    my $result;

    $result = snmpitDoIt($SNMPIT_SET,$sess,$var,$retries);

    return $result;
}

#
# Same as snmpitSet, but send mail if any error occur
#
sub snmpitSetWarn($$;$) {
    my ($sess,$var,$retries) = @_;
    my $result;

    $result = snmpitDoIt($SNMPIT_SET,$sess,$var,$retries);

    if (! defined $result) {
	snmpitWarn("SNMP SET failed");
    }
    return $result;
}

#
# Same as snmpitSetWarn, but also exits from the program if there is a 
# failure.
#
sub snmpitSetFatal($$;$) {
    my ($sess,$var,$retries) = @_;
    my $result;

    $result = snmpitDoIt($SNMPIT_SET,$sess,$var,$retries);

    if (! defined $result) {
	snmpitFatal("SNMP SET failed");
    }
    return $result;
}

#
# Print out SNMP::VarList and SNMP::Varbind structures. Useful for debugging
#
sub printVars($) {
    my ($vars) = @_;
    if (!defined($vars)) {
	return "[(undefined)]";
    } elsif (ref($vars) eq "SNMP::VarList") {
	return "[" . join(", ",map( {"[".join(",",@$_)."\]";}  @$vars)) . "]";
    } elsif (ref($vars) eq "SNMP::Varbind") {
	return "[" . join(",",@$vars) . "]";
    } elsif (ref($vars) eq "ARRAY") {
	return "[" . join(",",map( {defined($_)? $_ : "(undefined)"} @$vars))
		. "]";
    } else {
	return "[unknown value]";
    }
}

#
# Both print out an error message and mail it to the testbed ops. Prints out
# the snmpitErrorString set by snmpitGet.
#
# usage: snmpitWarn(message)
#
sub snmpitWarn($) {

    my ($message) = @_;

    #
    # Untaint $PRORAM_NAME
    #
    my $progname;
    if ($PROGRAM_NAME =~ /^([-\w.\/]+)$/) {
	$progname = $1;
    } else {
	$progname = "Tainted";
    }

    my $text = "$message - In $progname\n" .
    	       "$snmpitErrorString\n";
	
    print STDERR "*** $text";

    libtestbed::SENDMAIL($TBOPS, "snmpitError - $message", $text);
}

#
# Like snmpitWarn, but die too
#
sub snmpitFatal($) {
    my ($message) = @_;
    snmpitWarn($message);
    die("\n");
}

#
# Used to sort a set of nodes in testbed order (ie. pc2 < pc10)
#
# usage: tbsort($a,$b)
#        returns -1 if $a < $b
#        returns  0 if $a == $b
#        returns  1 if $a > $b
#
sub tbsort { 
    my ($a,$b) = @_;
    $a =~ /^([a-z]*)([0-9]*):?([0-9]*)/;
    my $a_let = ($1 || "");
    my $a_num = ($2 || 0);
    my $a_num2 = ($3 || 0);
    $b =~ /^([a-z]*)([0-9]*):?([0-9]*)/;
    my $b_let = ($1 || "");
    my $b_num = ($2 || 0);
    my $b_num2 = ($3 || 0);
    if ($a_let eq $b_let) {
	if ($a_num == $b_num) {
	    return $a_num2 <=> $b_num2;
	} else {
	    return $a_num <=> $b_num;
	}
    } else {
	return $a_let cmp $b_let;
    }
    return 0;
}
# End with true
1;

