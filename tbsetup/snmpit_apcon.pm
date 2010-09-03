#!/usr/bin/perl -W

#
# EMULAB-LGPL
# Copyright (c) 2010 University of Utah and the Flux Group.
# All rights reserved.
#

#
# snmpit module for Apcon 2000 series layer 1 switch
#

package snmpit_apcon;
use strict;

$| = 1; # Turn off line buffering on output

use English;
use SNMP; 
use snmpit_lib;

use libtestbed;
use apcon_clilib;
use Expect;


# CLI constants
my $CLI_UNNAMED_PATTERN = "[Uu]nnamed";
my $CLI_UNNAMED_NAME = "unnamed";
my $CLI_NOCONNECTION = "A00";
my $CLI_TIMEOUT = 10000;

# commands to show something
my $CLI_SHOW_CONNECTIONS = "show connections raw\r";
my $CLI_SHOW_PORT_NAMES  = "show port names *\r";

# mappings from port control command to CLI command
my %portCMDs =
(
    "enable" => "00",
    "disable"=> "00",
    "1000mbit"=> "9f",
    "100mbit"=> "9b",
    "10mbit" => "99",
    "auto"   => "00",
    "full"   => "94",
    "half"   => "8c",
    "auto1000mbit" => "9c",
    "full1000mbit" => "94",
    "half1000mbit" => "8c",
    "auto100mbit"  => "9a",
    "full100mbit"  => "92",
    "half100mbit"  => "8a",
    "auto10mbit"   => "99",
    "full10mbit"   => "91",
    "half10mbit"   => "89",
);


#
# All functions are based on snmpit_hp class.
#
# NOTES: This device is a layer 1 switch that has no idea
# about VLAN. We use the port name on switch as VLAN name here. 
# So in this module, vlan_id and vlan_number are the same 
# thing. vlan_id acts as the port name.
#
# Another fact: the port name can't exist without naming
# a port. So we can't find a VLAN if no ports are in it.
#

#
# Creates a new object.
#
# usage: new($classname,$devicename,$debuglevel,$community)
#        returns a new object.
#
# We actually donot use SNMP, the SNMP values here, like
# community, are just for compatibility.
#
sub new($$$;$) {

    # The next two lines are some voodoo taken from perltoot(1)
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my $name = shift;
    my $debugLevel = shift;
    my $community = shift;  # actually the password for ssh

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
    $self->{CONFIRM} = 1;
    $self->{NAME} = $name;

    #
    # Get config options from the database
    #
    my $options = getDeviceOptions($self->{NAME});
    if (!$options) {
	warn "ERROR: Getting switch options for $self->{NAME}\n";
	return undef;
    }

    $self->{MIN_VLAN}         = $options->{'min_vlan'};
    $self->{MAX_VLAN}         = $options->{'max_vlan'};

    #
    # A simple trick here: we store the ssh password in the 
    # 'snmp_community' column.
    #
    if ($community) { # Allow this to over-ride the default
	$self->{COMMUNITY}    = $community;
    } else {
	$self->{COMMUNITY}    = $options->{'snmp_community'};
    }
    $self->{PASSWORD} = $self->{COMMUNITY};

    # other global variables
    $self->{DOALLPORTS} = 0;
    $self->{DOALLPORTS} = 1;
    $self->{SKIPIGMP} = 1;

    if ($self->{DEBUG}) {
	print "snmpit_apcon initializing $self->{NAME}, " .
	    "debug level $self->{DEBUG}\n" ;   
    }

    $self->{SESS} = undef;
    $self->{CLI_PROMPT} = "$self->{NAME}>> ";

    # Make it a class object
    bless($self, $class);

    #
    # Create the Expect object
    #
    # We'd better set a long timeout on Apcon switch
    # to keep the connection alive.
    $self->{SESS} = $self->createExpectObject();
    if (!$self->{SESS}) {
	warn "WARNNING: Unable to connect via SSH to $self->{NAME}\n";
	return undef;
    }

    # TODO: may need this:
    #$self->readifIndex();

    return $self;
}


#
# Create an Expect object that spawns the ssh process 
# to switch.
#
sub createExpectObject($)
{
    my $self = shift;
    
    my $spawn_cmd = "ssh -l admin $self->{NAME}";
    # Create Expect object and initialize it:
    my $exp = new Expect();
    if (!$exp) {
	# upper layer will check this
	return undef;
    }
    $exp->raw_pty(0);
    $exp->log_stdout(0);
    $exp->spawn($spawn_cmd)
	or die "Cannot spawn $spawn_cmd: $!\n";
    $exp->expect($CLI_TIMEOUT,
		 ["admin\@$self->{NAME}'s password:" => sub { my $e = shift;
						       $e->send($self->{PASSWORD}."\n");
						       exp_continue;}],
		 ["Permission denied (password)." => sub { die "Password incorrect!\n";} ],
		 [ timeout => sub { die "Timeout when connect to switch!\n";} ],
		 $self->{CLI_PROMPT} );
    return $exp;
}


#
# parse the connection output
# return two hashes for query from either direction
#
sub parseConnections($$) 
{
    my $self = shift;
    my $raw = shift;

    my @lines = split( /\n/, $raw );
    my %dst = ();
    my %src = ();

    foreach my $line ( @lines ) {
	if ( $line =~ /^([A-I][0-9]{2}):\s+([A-I][0-9]{2})\W*$/ ) {
	    if ( $2 ne $CLI_NOCONNECTION ) {
		$src{$1} = $2;
		if ( ! (exists $dst{$2}) ) {
		    $dst{$2} = {};
		}

		$dst{$2}{$1} = 1;
	    }
	}
    }

    return (\%src, \%dst);
}


#
# parse the port names output
# return the port => name hashtable
#
sub parseNames($$)
{
    my $self = shift;
    my $raw = shift;

    my %names = ();

    foreach ( split ( /\n/, $raw ) ) {
	if ( /^([A-I][0-9]{2}):\s+(\w+)\W*/ ) {
	    if ( $2 !~ /$CLI_UNNAMED_PATTERN/ ) {
		$names{$1} = $2;
	    }
	}
    }

    return \%names;
}


#
# parse the show classes output
# return the classname => 1 hashtable, not a list.
#
sub parseClasses($$)
{
    my $self = shift;
    my $raw = shift;
    
    my %clses = ();

    foreach ( split ( /\n/, $raw ) ) {
	if ( /^Class\s\d{1,2}:\s+(\w+)\s+(\w+)\W*$/ ) {
	    $clses{$2} = 1;
	}
    }

    return \%clses;
}

#
# parse the show zones output
# return the zonename => 1 hashtable, not a list
#
sub parseZones($$)
{
    my $self = shift;
    my $raw = shift;

    my %zones = ();

    foreach ( split ( /\n/, $raw) ) {
	if ( /^\d{1,2}:\s+(\w+)\W*$/ ) {
	    $zones{$1} = 1;
	}
    }

    return \%zones;
}


#
# parse the show class ports output
# return the ports list
#
sub parseClassPorts($$)
{
    my $self = shift;
    my $raw = shift;
    my @ports = ();

    foreach ( split ( /\n/, $raw) ) {
	if ( /^Port\s+\d+:\s+([A-I][0-9]{2})\W*$/ ) {
	    push @ports, $1;
	}
    }

    return \@ports;
}


#
# parse the show zone ports output
# same to parse_class_ports
#
sub parseZonePorts($$)
{
    my ($self, $raw) = @_;
    return $self->parseClassPorts($raw);
}


#
# helper to do CLI command and check the error msg
#
sub doCLICmd($$)
{
    my ($self, $cmd) = @_;
    my $output = "";
    my $exp = $self->{SESS};

    $exp->clear_accum(); # Clean the accumulated output, as a rule.
    $exp->send($cmd);
    $exp->expect($CLI_TIMEOUT,
		 [$self->{CLI_PROMPT} => sub {
		     my $e = shift;
		     $output = $e->before();
		  }]);

    $cmd = quotemeta($cmd);
    if ( $output =~ /^($cmd)\n(ERROR:.+)\r\n[.\n]*$/ ) {
	return (1, $2);
    } else {
	return (0, $output);
    }
}


#
# get the raw CLI output of a command
#
sub getRawOutput($$)
{
    my ($self, $cmd) = @_;
    my ($rt, $output) = $self->doCLICmd($cmd);
    if ( !$rt ) {    	
    	my $qcmd = quotemeta($cmd);
	if ( $output =~ /^($qcmd)/ ) {
	    return substr($output, length($cmd)+1);
	}		
    }

    return undef;
}


#
# get all name => prorts hash
# return the name => port list hashtable
#
sub getAllNamedPorts($)
{
    my $self = shift;

    my $raw = $self->getRawOutput($CLI_SHOW_PORT_NAMES);
    my $names = $self->parseNames($raw); 

    my %nps = ();
    foreach my $k (keys %{$names}) {
	if ( !(exists $nps{$names->{$k}}) ) {
	    $nps{$names->{$k}} = ();
	}

	push @{$nps{$names->{$k}}}, $k;
    }

    return \%nps;
}


#
# get the name of a port
#
sub getPortName($$)
{
    my ($self, $port) = @_;

    my $raw = $self->getRawOutput("show port info $port\r");
    if ( $raw =~ /$port Name:\s+(\w+)\W*\n/ ) {
	if (  $1 !~ /$CLI_UNNAMED_PATTERN/ ) {
	    return $1;
	}
    }

    return undef;
}

#
# get the ports list by their name.
#
sub getNamedPorts($$)
{
    my ($self, $pname) = @_;
    my @ports = ();

    my $raw = $self->getRawOutput($CLI_SHOW_PORT_NAMES);
    foreach ( split /\n/, $raw ) {
	if ( /^([A-I][0-9]{2}):\s+($pname)\W*/ ) {
	    push @ports, $1;
	}
    }

    return \@ports;
}

#
# get connections of ports with the given name
# return two hashtabls whose format is same to parseConnections
#
sub getNamedConnections($$)
{
    my ($self, $name) = @_;

    my $raw_conns = $self->getRawOutput($CLI_SHOW_CONNECTIONS);
    my ($allsrc, $alldst) = $self->parseConnections($raw_conns);
    my $ports = $self->getNamedPorts($name);

    my %src = ();
    my %dst = ();

    #
    # There may be something special: a named port may connect to
    # a port whose name is not the same. Then this connection
    # should not belong to the 'vlan'. Till now the following codes
    # have not dealt with it yet.
    #
    # TODO: remove those connections containning ports don't belong
    #       to the 'vlan'.
    #
    foreach my $p (@$ports) {
	if ( exists($allsrc->{$p}) ) {
	    $src{$p} = $allsrc->{$p};
	} 

	if ( exists($alldst->{$p}) ) {
	    $dst{$p} = $alldst->{$p};
	}
    }

    return (\%src, \%dst);
}

#
# Add a new class
#
sub addCls($$)
{
    my ($self, $clsname) = @_;
    my $cmd = "add class I $clsname\r";

    return $self->doCLICmd($cmd);
}

#
# Add a new zone
#
sub addZone($$)
{
    my ($self, $zonename) = @_;
    my $cmd = "add zone $zonename\r";

    return $self->doCLICmd($cmd);
}

#
# Add some ports to a class
#
sub addClassPorts($$@)
{
    my ($self, $clsname, @ports) = @_;
    my $cmd = "add class ports $clsname ".join("", @ports)."\r";

    return $self->doCLICmd($cmd);
}

# 
# Connect ports functions:
#

#
# Make a multicast connection $src --> @dsts
#
sub connectMulticast($$@)
{
    my ($self, $src, @dsts) = @_;
    my $cmd = "connect multicast $src".join("", @dsts)."\r";

    return $self->doCLICmd($cmd);
}

#
# Make a duplex connection $src <> $dst
#
sub connectDuplex($$$)
{
    my ($self, $src, $dst) = @_;
    my $cmd = "connect duplex $src"."$dst"."\r";

    return $self->doCLICmd($cmd);
}

#
# Make a simplex connection $src -> $dst
#
sub connectSimplex($$$)
{
    my ($self, $src, $dst) = @_;
    my $cmd = "connect simplex $src"."$dst"."\r";

    return $self->doCLICmd($cmd);
}


#
# Add some ports to a vlan, 
# it actually names those ports to the vlanname. 
#
sub namePorts($$@)
{
    my ($self, $name, @ports) = @_;

    for( my $i = 0; $i < @ports; $i++ ) {    	
	my ($rt, $msg) = $self->doCLICmd(
				     "configure port name $ports[$i] $name\r");

	# undo set name
	if ( $rt ) {
	    for ($i--; $i >= 0; $i-- ) {	    	
		$self->doCLICmd(
			    "configure port name $ports[$i] $CLI_UNNAMED_NAME\r");
	    }
	    return $msg;
	}
    }

    return 0;
}


#
# Unname ports, the name of those ports will be $CLI_UNNAMED_NAME
#
sub unnamePorts($@)
{
    my ($self, @ports) = @_;

    my $emsg = "";
    foreach my $p (@ports) {
	my ($rt, $msg) = $self->doCLICmd(
				     "configure port name $p $CLI_UNNAMED_NAME\r");
	if ( $rt ) {
	    $emsg = $emsg.$msg."\n";
	}
    }

    if ( $emsg eq "" ) {
	return 0;
    }

    return $emsg;
}


#
# Disconnect ports
# $sconns: the dst => src hashtable.
#
sub disconnectPorts($$) 
{
    my ($self, $sconns) = @_;

    my $emsg = "";
    foreach my $dst (keys %$sconns) {
	my ($rt, $msg) = $self->doCLICmd(
				     "disconnect $dst".$sconns->{$dst}."\r");
	if ( $rt ) {
	    $emsg = $emsg.$msg."\n";
	}
    }

    if ( $emsg eq "" ) {
	return 0;
    }

    return $emsg;
}


#
# Remove a 'vlan', unname the ports and disconnect them
#
sub removePortName($$)
{
    my ($self, $name) =  @_;

    # Disconnect ports:
    my ($src, $dst) = $self->getNamedConnections($name);
    my $disrt = $self->disconnectPorts($src);

    # Unname ports:
    my $ports = $self->getNamedPorts($name);
    my $unrt = $self->unnamePorts(@$ports);
    if ( $unrt || $disrt) {
	return $disrt.$unrt;
    }

    return 0;
}


#
# Set port rate, for port control.
# Rates are defined in %portCMDs.
#
sub setPortRate($$$)
{
    my ($self, $port, $rate) = @_;

    if ( !exists($portCMDs{$rate}) ) {
	return "ERROR: port rate unsupported!\n";
    }

    my $cmd = "configure rate $port $portCMDs{$rate}\r";
    my ($rt, $msg) = $self->doCLICmd($cmd);
    if ( $rt ) {
	return $msg;
    }

    return 0;
}

#
# Get port info
#
sub getPortInfo($$)
{
    my ($self, $port) = @_;

    # TODO: parse the output of show port xxxxx
    return [$port,0];
}


#
# Set a variable associated with a port. The commands to execute are given
# in the apcon_clilib::portCMDs hash
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

    my $errors = 0;
    foreach my $port (@ports) { 
	my $rt = $self->setPortRate($port, $cmd);
	if ($rt) {
	    if ($rt =~ /^ERROR: port rate unsupported/) {
		#
                # Command not supported
		#
		$self->debug("Unsupported port control command '$cmd' ignored.\n");
		return 0;
	    }

	    $errors++;
	}
    }

    return $errors;
}


#
# Original purpose: 
# Given VLAN indentifiers from the database, finds the 802.1Q VLAN
# number for them. If not VLAN id is given, returns mappings for the entire
# switch.
#
# On Apcon switch, no VLAN exists. So we use port name as VLAN name. This 
# funtion actually either list all VLAN names or do the existance checking,
# which will set the mapping value to undef for nonexisted VLANs. 
# 
# usage: findVlans($self, @vlan_ids)
#        returns a hash mapping VLAN ids to ... VLAN ids.
#        any VLANs not found have NULL VLAN numbers
#
sub findVlans($@) { 
    my $self = shift;
    my @vlan_ids = @_;
    my %mapping = ();
    my $id = $self->{NAME} . "::findVlans";
    my ($count, $name, $vlan_number, $vlan_name) = (scalar(@vlan_ids));
    $self->debug("$id\n");

    if ($count > 0) { @mapping{@vlan_ids} = undef; }

    # 
    # Get all port names, which are considered to be VLAN names.
    #
    my $vlans = $self->getAllNamedPorts();
    foreach $vlan_name (keys %{$vlans}) {
	if (!@vlan_ids || exists $mapping{$vlan_name}) {
	    $mapping{$vlan_name} = $vlan_name;
	}
    }

    return %mapping;
}


#
# See the comments of findVlans above for explanation.
#
# usage: findVlan($self, $vlan_id,$no_retry)
#        returns the VLAN number for the given vlan_id if it exists
#        returns undef if the VLAN id is not found
#
sub findVlan($$;$) { 
    my $self = shift;
    my $vlan_id = shift;

    #
    # Just for compatibility, we don't use retry for CLI.
    #
    my $no_retry = shift;
    my $id = $self->{NAME} . ":findVlan";

    $self->debug("$id ( $vlan_id )\n",2);
    
    my $ports = $self->getNamedPorts($vlan_id);
    if (@$ports) {
	return $vlan_id;
    }

    return undef;
}

#   
# Create a VLAN on this switch, with the given identifier (which comes from
# the database) and given 802.1Q tag number, which is ignored.
#
# usage: createVlan($self, $vlan_id, $vlan_number)
#        returns the new VLAN number on success
#        returns 0 on failure
#
sub createVlan($$$) {
    my $self = shift;
    my $vlan_id = shift;
    my $vlan_number = shift; # we ignore this on Apcon switch
    my $id = $self->{NAME} . ":createVlan";

    #
    # To acts similar to other device modules
    #
    if (!defined($vlan_number)) {
	warn "$id called without supplying vlan_number";
	return 0;
    }
    my $check_number = $self->findVlan($vlan_id,1);
    if (defined($check_number)) {
	warn "$id: recreating vlan id $vlan_id \n";
	return 0;
    }

    #
    # We do nothing here now.
    # We can be sure that the vlan_id won't be used in future for
    # another VLAN creation, but it is better if we can reserve
    # the vlan_id on switch.
    #   
    #
    # TODO: find a method to reserve the vlan_id as port name on 
    # switch. Maybe creating an empty class or zone, but then we
    # can only reserve as many as 48(or 46) names at most.
    #
    
    print "  Creating VLAN $vlan_id as VLAN #$vlan_number on " .
	    "$self->{NAME} ...\n";

    return $vlan_number;
}


#
# TODO: A+ TODO for Apcon switch. The result seems to be 'unsupported'.
# 
# gets the forbidden, untagged, and egress lists for a vlan
# sends back as a 3 element array of lists.  
#
sub getVlanLists($$) {
    my ($self, $vlan) = @_;
    my $ret = [0, 0, 0];
    return $ret;
}

#
# TODO: A+ TODO for Apcon switch. The result seems to be 'unsupported'.
#
# sets the forbidden, untagged, and egress lists for a vlan
# sends back as a 3 element array of lists.
# (Thats the order we saw in a tcpdump of vlan creation.)
# (or in some cases 6 elements for 2 vlans).
#
sub setVlanLists($@) {
    my ($self, @args) = @_;
    return 0;
}

#
# Put the given ports in the given VLAN. The VLAN is given as an 802.1Q 
# tag number.
#
# usage: setPortVlan($self, $vlan_number, @ports)
#	 returns 0 on sucess.
#	 returns the number of failed ports on failure.
#
sub setPortVlan($$@) {
    my $self = shift;
    my $vlan_number = shift;
    my @ports = @_;

    my $id = $self->{NAME} . "::setPortVlan";
    $self->debug("$id: $vlan_number ");
    $self->debug("ports: " . join(",",@ports) . "\n");
    
    $self->lock();

    # Check if ports are free
    foreach my $port (@ports) {
	if ($self->getPortName($port)) {
	    warn "ERROR: Port $port already in use.\n";
	    $self->unlock();
	    return 1;
	}
    }

    #
    # TODO: Shall we check whether Vlan exists or not?
    #
    
    my $errmsg = $self->namePorts($vlan_number, @ports);
    if ($errmsg) {
	warn "$errmsg";
	$self->unlock();
	return 1;
    }

    $self->unlock();

    return 0;
}


#
# Remove the given ports from the given VLAN. The VLAN is given as an 802.1Q 
# tag number.
#
# usage: delPortVlan($self, $vlan_number, @ports)
#	 returns 0 on sucess.
#	 returns the number of failed ports on failure.
#
sub delPortVlan($$@) {
    my $self = shift;
    my $vlan_number = shift;
    my @ports = @_;

    $self->debug($self->{NAME} . "::delPortVlan $vlan_number ");
    $self->debug("ports: " . join(",",@ports) . "\n");
    
    $self->lock();

    #
    # Find connections of @ports
    #
    my ($src, $dst) = $self->getNamedConnections($vlan_number);
    my %sconns = ();
    foreach my $p (@ports) {

	if (exists($src->{$p})) {
	    
	    # As destination:
	    $sconns{$p} = $src->{$p};
	} else {
	    if (exists($dst->{$p})) {
	    
	        # As source:
	        foreach my $pdst (keys %{$dst->{$p}}) {
		    $sconns{$pdst} = $p;
	        }
	    }    
	}
    }
    
    # Disconnect conections of @ports
    my $errmsg = $self->disconnectPorts(\%sconns);
    if ($errmsg) {
	warn "$errmsg";
	$self->unlock();
	return 1;
    }
    
    # Unname the ports, looks like 'remove'
    $errmsg = $self->unnamePorts(@ports);
    if ($errmsg) {
	warn "$errmsg";
	$self->unlock();
	return 1;
    }    

    $self->unlock();

    return 0;
}

#
# Disables all ports in the given VLANS. Each VLAN is given as a VLAN
# 802.1Q tag value.
#
# This version will also 'delete' the VLAN because no ports use
# the vlan name any more. Same to removeVlan().
#
# usage: removePortsFromVlan(self,@vlan)
#	 returns 0 on sucess.
#	 returns the number of failed ports on failure.
#
sub removePortsFromVlan($@) {
    my $self = shift;
    my @vlan_numbers = @_;
    my $errors = 0;
    my $id = $self->{NAME} . "::removePortsFromVlan";

    foreach my $vlan_number (@vlan_numbers) {
	if ($self->removePortName($vlan_number)) {
	    $errors++;
	}
    }
    return $errors;
}

#
# Removes and disables some ports in a given VLAN.
# The VLAN is given as a VLAN 802.1Q tag value.
#
# This function is the same to delPortVlan because
# disconnect a connection will disable its two endports
# at the same time.
#
# usage: removeSomePortsFromVlan(self,vlan,@ports)
#	 returns 0 on sucess.
#	 returns the number of failed ports on failure.
#
sub removeSomePortsFromVlan($$@) {
    my ($self, $vlan_number, @ports) = @_;
    return $self->delPortVlan($vlan_number, @ports);
}

#
# Remove the given VLANs from this switch. Removes all ports from the VLAN,
# The VLAN is given as a VLAN identifier from the database.
#
# usage: removeVlan(self,int vlan)
#	 returns 1 on success
#	 returns 0 on failure
#
#
sub removeVlan($@) {
    my $self = shift;
    my @vlan_numbers = @_;
    my $name = $self->{NAME};
    my $errors = 0;

    foreach my $vlan_number (@vlan_numbers) {
	if ($self->removePortName($vlan_number)) {
	    $errors++;
	} else {
	    print "Removed VLAN $vlan_number on switch $name.\n";	
	}	
    }

    return ($errors == 0) ? 1:0;
}



#
# Determine if a VLAN has any members 
# (Used by stack->switchesWithPortsInVlan())
#
sub vlanHasPorts($$) {
    my ($self, $vlan_number) = @_;

    my $portset = $self->getNamedPorts($vlan_number);
    if (@$portset) {
	return 1;
    }
    return 0;
}

#
# List all VLANs on the device
#
# usage: listVlans($self)
# see snmpit_cisco_stack.pm for a description of return value format
#
sub listVlans($) {
    my $self = shift;

    my @list = ();
    my $vlans = $self->getAllNamedPorts();
    foreach my $vlan_id (keys %$vlans) {
	push @list, [$vlan_id, $vlan_id, $vlans->{$vlan_id}];
    }

    #$self->debug($self->{NAME} .":". join("\n",(map {join ",", @$_} @list))."\n");
    return @list;
}

#
# List all ports on the device
#
# usage: listPorts($self)
# see snmpit_cisco_stack.pm for a description of return value format
#
sub listPorts($) {
    my $self = shift;
    my @ports = ();

    # TODO: call getPortInfo one by one for each port
    return @ports;
}

# 
# Get statistics for ports on the switch
#
# Unsupported operation on Apcon 2000-series switch via CLI.
#
# usage: getStats($self)
# see snmpit_cisco_stack.pm for a description of return value format
#
#
sub getStats() {
    my $self = shift;

    warn "Port statistics are unavaialble on our Apcon 2000 switch.";
    return undef;
}


#
# Get the ifindex for an EtherChannel (trunk given as a list of ports)
#
# usage: getChannelIfIndex(self, ports)
#        Returns: undef if more than one port is given, and no channel is found
#           an ifindex if a channel is found and/or only one port is given
#
sub getChannelIfIndex($@) {
    warn "ERROR: Apcon switch doesn't support trunking";
    return undef;
}


#
# Enable, or disable,  port on a trunk
#
# usage: setVlansOnTrunk(self, modport, value, vlan_numbers)
#        modport: module.port of the trunk to operate on
#        value: 0 to disallow the VLAN on the trunk, 1 to allow it
#	 vlan_numbers: An array of 802.1Q VLAN numbers to operate on
#        Returns 1 on success, 0 otherwise
#
sub setVlansOnTrunk($$$$) {
    warn "ERROR: Apcon switch doesn't support trunking";
    return 0;
}

#
# Enable trunking on a port
#
# usage: enablePortTrunking2(self, modport, nativevlan, equaltrunking)
#        modport: module.port of the trunk to operate on
#        nativevlan: VLAN number of the native VLAN for this trunk
#	 equaltrunk: don't do dual mode; tag PVID also.
#        Returns 1 on success, 0 otherwise
#
sub enablePortTrunking2($$$$) {
    warn "ERROR: Apcon switch doesn't support trunking";
    return 0;
}

#
# Disable trunking on a port
#
# usage: disablePortTrunking(self, modport)
#        modport: module.port of the trunk to operate on
#        Returns 1 on success, 0 otherwise
#
sub disablePortTrunking($$;$) {
    warn "ERROR: Apcon switch doesn't support trunking";
    return 0;
}


#
# Prints out a debugging message, but only if debugging is on. If a level is
# given, the debuglevel must be >= that level for the message to print. If
# the level is omitted, 1 is assumed
#
# Usage: debug($self, $message, $level)
#
sub debug($$;$) {
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

my $lock_held = 0;

sub lock($) {
    my $self = shift;
    my $token = "snmpit_" . $self->{NAME};
    if ($lock_held == 0) {
	my $old_umask = umask(0);
	die if (TBScriptLock($token,0,1800) != TBSCRIPTLOCK_OKAY());
	umask($old_umask);
    }
    $lock_held = 1;
}

sub unlock($) {
	if ($lock_held == 1) { TBScriptUnlock();}
	$lock_held = 0;
}


#
# Enable Openflow
#
sub enableOpenflow($$) {
    warn "ERROR: Apcon switch doesn't support Openflow now";
    return 0;
}

#
# Disable Openflow
#
sub disableOpenflow($$) {
    warn "ERROR: Apcon switch doesn't support Openflow now";
    return 0;
}

#
# Set controller
#
sub setOpenflowController($$$) {
    warn "ERROR: Apcon switch doesn't support Openflow now";
    return 0;
}

#
# Set listener
#
sub setOpenflowListener($$$) {
    warn "ERROR: Apcon switch doesn't support Openflow now";
    return 0;
}

#
# Get used listener ports
#
sub getUsedOpenflowListenerPorts($) {
    my %ports = ();

    warn "ERROR: Apcon switch doesn't support Openflow now";
    return %ports;
}


#
# Check if Openflow is supported on this switch
#
sub isOpenflowSupported($) {
    return 0;
}

# End with true
1;
