<?PHP
#
# EMULAB-COPYRIGHT
# Copyright (c) 2003, 2005 University of Utah and the Flux Group.
# All rights reserved.
#

#
# This is a simple library for use by the new-node pages, with functions that
# need to be called both by the initial checkin page and the adminstrator
# node-adding page.
#

function find_switch_macs(&$mac_list) {

    global $uid, $gid, $TBSUEXEC_PATH, $ELABINELAB;

    #
    # Avoid SIGPROF in child.
    #   
    set_time_limit(0); 
    
    $macs = popen("$TBSUEXEC_PATH $uid $gid switchmac 2>&1","r");

    #
    # XXX - error checking
    #
    $line = fgets($macs);
    while (!feof($macs)) {
        $line = rtrim($line);
	$exploded = explode(",",$line);
	$MAC = $exploded[0];
	$switchport = $exploded[1];
	$vlan = $exploded[2];
	$iface = $exploded[3];
	$class = $exploded[4];
	if (!preg_match("/^([\w-]+)\/(\d+)\.(\d+)$/",$switchport,$matches)) {
	    echo "<h3>Bad line from switchmac: $line\n";
	}
	$switch = $matches[1];
	$card = $matches[2];
	$port = $matches[3];
	if ($mac_list[$MAC] &&
	    (is_null($mac_list[$MAC]["class"]) ||
	     !isset($mac_list[$MAC]["class"]) ||
	     ($mac_list[$MAC]["class"] == $class))) {
	    $mac_list[$MAC]["switch"] = $switch;
	    $mac_list[$MAC]["switch_card"] = $card;
	    $mac_list[$MAC]["switch_port"] = $port;
	    if ($ELABINELAB) {
		# We let switchmac tell us.
		$mac_list[$MAC]["class"] = $class;
	    }
	}
	$line = fgets($macs);
    }

    pclose($macs);

    return 1;

}

function guess_node_type($proc,$disk) {

    #
    # Allow the reported speed to differ from the one in the database
    #
    $fudge_factor = .10;

    #
    # Convert disk size from megabytes to gigabtypes
    #
    $disk /= 1000.0;

    #
    # Go through node types and try to find a single one that matches
    # this node's processor speed. This is a totally bogus way to do this,
    # but it's the best we got for now.
    #
    $node_type = "";
    $query_result = DBQueryFatal("select type, speed, HD from node_types " .
	"where !isvirtnode and !isremotenode");
    while ($row = mysql_fetch_array($query_result)) {
        $speed = $row["speed"];
	$type = $row["type"];
	$HD = $row["HD"];
	echo "Checking $speed vs $proc, $HD vs $disk\n";
	if (($proc > ($speed * (1.0 - $fudge_factor))) &&
	    ($proc < ($speed * (1.0 + $fudge_factor))) &&
	    ($disk > ($HD * (1.0 - $fudge_factor))) &&
	    ($disk < ($HD * (1.0 + $fudge_factor)))) {
	    if ($node_type != "") {
	        # We found two potential matches, choose neither
		echo "Found a second match ($type), bailing\n";
		return "";
	    } else {
		echo "Found a first match ($type)\n";
	        $node_type = $type;
	    }
	}
    }

    echo "Returning $node_type\n";
    return $node_type;
}

#
# Create a new node type
# XXX - Right now, this is really only meant for inserting a node_types entry
# for ops. It misses doing a lot of important things, like setting the class and
# default OSID for types other than ops
#
function make_node_type($type,$proc,$disk) {

    #
    # Just insert a stub entry for this type
    #
    $class = "";
    $defosid = "";
    if (!strcmp($type,"ops")) {
	$class = "misc";
	$defosid = "emulab-ops-OPSNODE-BSD";
    }
    DBQueryFatal("insert into node_types set type='$type', speed='$speed', " .
	"HD='$disk', class='$class', osid='$defosid';");

}

function guess_IP ($prefix, $number) {
    global $CONTROL_NETWORK;

    $hostname = $prefix . $number;

    #
    # First, lets see if they've already added to to DNS - the PHP
    # gethostbyname has a really dumb way to return failure - it just
    # gives you the hostname back.
    #
    $IP = gethostbyname($hostname);
    if (strcmp($IP,$hostname)) {
    	return $IP;
    }

    #
    # We want to be able to handle both numeric and character 'number's - figure
    # out which we have
    #
    if (is_string($number)) {
	$using_char = 1;
	$number = ord($number);
    } else {
	$using_char = 0;
    }

    #
    # Okay, no such luck. We'll go backwards through the host list until
    # we find the previous node with an established IP, then add our offset
    # onto that
    #
    $i = $number - 1;
    $IP = "";
    while ($i > 0) {
        if ($using_char) {
	    $node = $prefix . chr($i);
	} else {
	    $node = $prefix . $i;
	}
        $query_result = DBQueryFatal("select IP from interfaces as i " .
		"left join nodes as n on i.node_id = n.node_id left join " .
		"node_types as nt on n.type = nt.type " .
		"where n.node_id='$node' and i.iface = nt.control_iface");
        if (mysql_num_rows($query_result)) {
	    $row = mysql_fetch_array($query_result);
	    $IP = $row[IP];
	    break;
	}

	# Try new_nodes too
        $query_result = DBQueryFatal("select IP from new_nodes " .
		"where node_id='$node'");
        if (mysql_num_rows($query_result)) {
	    $row = mysql_fetch_array($query_result);
	    $IP = $row[IP];
	    break;
	}

	$i--;
    }

    #
    # Lets start out as the first address on the given control network.
    # 
    if ($i <= 0) {
    	$IP = $CONTROL_NETWORK;
    }

    #
    # Parse the IP we got into the last octet and everything else. Note that we
    # don't really do the IP address calcuation correctly - just an
    # approximation of the right thing.
    #
    list($oct1,$oct2,$oct3,$oct4) = explode(".",$IP);
    $oct4 += $number - $i;

    # We don't yet wrap - it may not be OK to do
    if ($oct4 > 254) {
        return 0;
    }

    return "$oct1.$oct2.$oct3.$oct4";
    
}


?>
