#!/usr/bin/perl -wT

#
# EMULAB-COPYRIGHT
# Copyright (c) 2000-2003 University of Utah and the Flux Group.
# All rights reserved.
#
# TODO: Signal handlers for protecting db files.

#
# Common routines and constants for the client bootime setup stuff.
#
package libsetup;
use Exporter;
@ISA = "Exporter";
@EXPORT =
    qw ( libsetup_init libsetup_setvnodeid cleanup_node 
	 doifconfig dohostnames domounts dotunnels check_nickname
	 doaccounts dorpms dotarballs dostartupcmd install_deltas
	 bootsetup nodeupdate startcmdstatus whatsmynickname dosyncserver
	 TBBackGround TBForkCmd vnodejailsetup plabsetup vnodeplabsetup
	 dorouterconfig jailsetup dojailconfig JailedMounts findiface
	 tmccdie tmcctimeout libsetup_getvnodeid dotrafficconfig
	 ixpsetup

	 OPENTMCC CLOSETMCC RUNTMCC MFS REMOTE JAILED PLAB LOCALROOTFS IXP

	 CONFDIR TMCC TMIFC TMDELAY TMRPM TMTARBALLS TMHOSTS TMJAILNAME
	 TMNICKNAME HOSTSFILE TMSTARTUPCMD FINDIF TMTUNNELCONFIG
	 TMTRAFFICCONFIG TMROUTECONFIG TMLINKDELAY TMDELMAP TMMOUNTDB
	 TMPROGAGENTS TMPASSDB TMGROUPDB TMGATEDCONFIG
	 TMCCCMD_REBOOT TMCCCMD_STATUS TMCCCMD_IFC TMCCCMD_ACCT TMCCCMD_DELAY
	 TMCCCMD_HOSTS TMCCCMD_RPM TMCCCMD_TARBALL TMCCCMD_STARTUP
	 TMCCCMD_DELTA TMCCCMD_STARTSTAT TMCCCMD_READY TMCCCMD_TRAFFIC
	 TMCCCMD_BOSSINFO TMCCCMD_VNODELIST TMCCCMD_ISALIVE TMCCCMD_LINKDELAYS
	 TMCCCMD_PROGRAMS TMCCCMD_SUBNODELIST TMCCCMD_SUBCONFIG
	 TMCCCMD_STATE
       );

# Must come after package declaration!
use English;

#
# For virtual (multiplexed nodes). If defined, tack onto tmcc command.
# and use in pathnames. Used in conjunction with jailed virtual nodes.
# I am also using this for subnodes; eventually everything will be subnodes.
#
my $vnodeid;
sub libsetup_setvnodeid($)
{
    ($vnodeid) = @_;
}
sub libsetup_getvnodeid()
{
    return $vnodeid;
}

#
# True if running inside a jail. Set just below. 
# 
my $injail;

#
# True if running in a Plab vserver.
#
my $inplab;

#
# Ditto for IXP, although currently there is no "in" IXP setup; it
# is all done from outside.
#
my $inixp;

# Load up the paths. Its conditionalized to be compatabile with older images.
# Note this file has probably already been loaded by the caller.
BEGIN
{
    if (! -e "/etc/emulab/paths.pm") {
	die("Yikes! Could not require /etc/emulab/paths.pm!\n");
    }
    require "/etc/emulab/paths.pm";
    import emulabpaths;

    #
    # Determine if running inside a jail. This affects the paths below.
    #
    if (-e "$BOOTDIR/jailname") {
	open(VN, "$BOOTDIR/jailname");
	$vnodeid = <VN>;
	close(VN);

	if ($vnodeid =~ /^([-\w]+)$/) {
	    $vnodeid = $1;
	}
	else {
	    die("Bad data in vnodeid: $vnodeid");
	}
	$injail = 1;
    }

    # Determine if running inside a Plab vserver.
    if (-e "$BOOTDIR/plabname") {
	open(VN, "$BOOTDIR/plabname");
	$vnodeid = <VN>;
	close(VN);

	if ($vnodeid =~ /^([-\w]+)$/) {
	    $vnodeid = $1;
	}
	else {
	    die("Bad data in vnodeid: $vnodeid");
	}
	$inplab = 1;
    }

    # Make sure these exist!
    if (! -e "$VARDIR/logs") {
	mkdir("$VARDIR", 0775);
	mkdir("$VARDIR/jails", 0775);
	mkdir("$VARDIR/db", 0755);
	mkdir("$VARDIR/logs", 0775);
	mkdir("$VARDIR/boot", 0775);
	mkdir("$VARDIR/lock", 0775);
    }
}

#
# The init routine. This is deprecated, but left behind in case an old
# liblocsetup is run against a new libsetup. Whenever a new libsetup
# is installed, better install the path module (see above) too!
#
sub libsetup_init($)
{
    my($path) = @_;

    $ETCDIR  = $path;
    $BINDIR  = $path;
    $VARDIR  = $path;
    $BOOTDIR = $path
}

#
# This "local" library provides the OS dependent part. 
#
use liblocsetup;

#
# These are the paths of various files and scripts that are part of the
# setup library.
#
sub TMCC()		{ "$BINDIR/tmcc"; }
sub TMHOSTS()		{ "$ETCDIR/hosts"; }
sub FINDIF()		{ "$BINDIR/findif"; }
sub HOSTSFILE()		{ "/etc/hosts"; }
#
# This path is valid only *outside* the jail when its setup.
# 
sub JAILDIR()		{ "$VARDIR/jails/$vnodeid"; }

#
# Also valid outside the jail, this is where we put local project storage.
#
sub LOCALROOTFS()	{ (REMOTE() ? "/users/local" : "$VARDIR/jails/local");}

#
# Okay, here is the path mess. There are three environments.
# 1. A local node where everything goes in one place ($VARDIR/boot).
# 2. A virtual node inside a jail or a Plab vserver ($VARDIR/boot).
# 3. A virtual (or sub) node, from the outside. 
#
# As for #3, whether setting up a old-style virtual node or a new style
# jailed node, the code that sets it up needs a different per-vnode path.
#
sub CONFDIR() {
    if ($injail || $inplab) {
	return $BOOTDIR;
    }
    if ($vnodeid) {
	return JAILDIR();
    }
    return $BOOTDIR;
}

#
# These go in /var/emulab. Good for all environments!
# 
sub TMMOUNTDB()		{ $VARDIR . "/db/mountdb"; }
sub TMSFSMOUNTDB()	{ $VARDIR . "/db/sfsmountdb"; }
sub TMPASSDB()		{ $VARDIR . "/db/passdb"; }
sub TMGROUPDB()		{ $VARDIR . "/db/groupdb"; }
#
# The rest of these depend on the environment running in (inside/outside jail).
# 
sub TMNICKNAME()	{ CONFDIR() . "/nickname";}
sub TMJAILNAME()	{ CONFDIR() . "/jailname";}
sub TMJAILCONFIG()	{ CONFDIR() . "/jailconfig";}
sub TMPLABCONFIG()	{ CONFDIR() . "/rc.plab";}
sub TMSTARTUPCMD()	{ CONFDIR() . "/startupcmd";}
sub TMPROGAGENTS()	{ CONFDIR() . "/progagents";}
sub TMIFC()		{ CONFDIR() . "/rc.ifc"; }
sub TMRPM()		{ CONFDIR() . "/rc.rpm";}
sub TMTARBALLS()	{ CONFDIR() . "/rc.tarballs";}
sub TMROUTECONFIG()     { CONFDIR() . "/rc.route";}
sub TMGATEDCONFIG()     { CONFDIR() . "/gated.conf";}
sub TMTRAFFICCONFIG()	{ CONFDIR() . "/rc.traffic";}
sub TMTUNNELCONFIG()	{ CONFDIR() . "/rc.tunnel";}
sub TMVTUNDCONFIG()	{ CONFDIR() . "/vtund.conf";}
sub TMDELAY()		{ CONFDIR() . "/rc.delay";}
sub TMLINKDELAY()	{ CONFDIR() . "/rc.linkdelay";}
sub TMDELMAP()		{ CONFDIR() . "/delay_mapping";}
sub TMSYNCSERVER()	{ CONFDIR() . "/syncserver";}
sub TMRCSYNCSERVER()	{ CONFDIR() . "/rc.syncserver";}

#
# Whether or not to use SFS (the self-certifying file system).  If this
# is 0, fall back to NFS.  Note that it doesn't hurt to set this to 1
# even if TMCD is not serving out SFS mounts, or if this node is not
# running SFS.  It'll deal and fall back to NFS.
#
my $USESFS		= 1;

#
# This is the VERSION. We send it through to tmcd so it knows what version
# responses this file is expecting.
#
# BE SURE TO BUMP THIS AS INCOMPATIBILE CHANGES TO TMCD ARE MADE!
#
sub TMCD_VERSION()	{ 11; };

#
# These are the TMCC commands. 
#
sub TMCCCMD_REBOOT()	{ "reboot"; }
sub TMCCCMD_STATUS()	{ "status"; }
sub TMCCCMD_STATE()	{ "state"; }
sub TMCCCMD_IFC()	{ "ifconfig"; }
sub TMCCCMD_ACCT()	{ "accounts"; }
sub TMCCCMD_DELAY()	{ "delay"; }
sub TMCCCMD_HOSTS()	{ "hostnames"; }
sub TMCCCMD_RPM()	{ "rpms"; }
sub TMCCCMD_TARBALL()	{ "tarballs"; }
sub TMCCCMD_STARTUP()	{ "startupcmd"; }
sub TMCCCMD_DELTA()	{ "deltas"; }
sub TMCCCMD_STARTSTAT()	{ "startstatus"; }
sub TMCCCMD_READY()	{ "ready"; }
sub TMCCCMD_MOUNTS()	{ "mounts"; }
sub TMCCCMD_ROUTING()	{ "routing"; }
sub TMCCCMD_TRAFFIC()	{ "trafgens"; }
sub TMCCCMD_BOSSINFO()	{ "bossinfo"; }
sub TMCCCMD_TUNNEL()	{ "tunnels"; }
sub TMCCCMD_NSECONFIGS(){ "nseconfigs"; }
sub TMCCCMD_VNODELIST() { "vnodelist"; }
sub TMCCCMD_SUBNODELIST(){ "subnodelist"; }
sub TMCCCMD_ISALIVE()   { "isalive"; }
sub TMCCCMD_SFSHOSTID()	{ "sfshostid"; }
sub TMCCCMD_SFSMOUNTS() { "sfsmounts"; }
sub TMCCCMD_JAILCONFIG(){ "jailconfig"; }
sub TMCCCMD_PLABCONFIG(){ "plabconfig"; }
sub TMCCCMD_SUBCONFIG() { "subconfig"; }
sub TMCCCMD_LINKDELAYS(){ "linkdelays"; }
sub TMCCCMD_PROGRAMS()  { "programs"; }
sub TMCCCMD_SYNCSERVER(){ "syncserver"; }

#
# Some things never change.
# 
my $TARINSTALL  = "/usr/local/bin/install-tarfile %s %s %s";
my $VTUND       = "/usr/local/sbin/vtund";

#
# This is a debugging thing for my home network.
#
my $NODE = "";
if (defined($ENV{'TMCCARGS'})) {
    if ($ENV{'TMCCARGS'} =~ /^([-\w\s]*)$/) {
	$NODE .= " $1";
    }
    else {
	die("Tainted TMCCARGS from environment: $ENV{'TMCCARGS'}!\n");
    }
}

# Locals
my $pid		= "";
my $eid		= "";
my $vname	= "";

# Control tmcc error condition and timeout. Dynamic, not lexical!
$tmccdie        = 1; 
$tmcctimeout    = 0;
my $TMCCTIMEO   = 30;	# Default timeout on remote nodes. 

# When on the MFS, we do a much smaller set of stuff.
# Cause of the way the packages are loaded (which I do not understand),
# this is computed on the fly instead of once.
sub MFS()	{ if (-e "$ETCDIR/ismfs") { return 1; } else { return 0; } }

#
# Same for a remote node.
#
sub REMOTE()	{ if (-e "$ETCDIR/isrem") { return 1; } else { return 0; } }

#
# Same for a control node.
#
sub CONTROL()	{ if (-e "$ETCDIR/isctrl") { return 1; } else { return 0; } }

#
# Are we jailed? See above.
#
sub JAILED()	{ if ($injail) { return $vnodeid; } else { return 0; } }

#
# Are we on plab?
#
sub PLAB()	{ if ($inplab) { return $vnodeid; } else { return 0; } }

#
# Are we on an IXP
#
sub IXP()	{ if ($inixp) { return $vnodeid; } else { return 0; } }

#
# Do not try this on the MFS since it has such a wimpy perl installation.
#
if (!MFS()) {
    require Socket;
    import Socket;
}

#
# Open a TMCC connection and return the "stream pointer". Caller is
# responsible for closing the stream and checking return value.
#
# usage: OPENTMCC(char *command, char *args, char *options)
#
sub OPENTMCC($;$$)
{
    my($cmd, $args, $options) = @_;
    my $vn = "";
    local *TM;

    if (!defined($args)) {
	$args = "";
    }
    if (!defined($options)) {
	$options = "";
    }
    if (defined($vnodeid)) {
	$vn = "-n $vnodeid";
    }
    if ($tmcctimeout) {
	$options .= " -t $tmcctimeout";
    }

    my $foo = sprintf("%s -v %d $options $NODE $vn $cmd $args |",
		      TMCC, TMCD_VERSION);

    if (!open(TM, $foo)) {
	print STDERR "Cannot start TMCC: $!\n";
	die("\n") if $tmccdie;
	return undef;
    }
    return (*TM);
}

#
# Close connection. Die on error.
# 
sub CLOSETMCC($) {
    my($TM) = @_;
    
    if (! close($TM)) {
	if ($?) {
	    print STDERR "TMCC exited with status $?!\n";
	}
	else {
	    print STDERR "Error closing TMCC pipe: $!\n";
	}
	die("\n") if $tmccdie;
	return 0;
    }
    return 1;
}

#
# Run a TMCC command with the provided arguments.
#
# usage: RUNTMCC(char *command, char *args, char *options)
#
sub RUNTMCC($;$$)
{
    my($cmd, $args, $options) = @_;
    my($TM);

    if (!defined($args)) {
	$args = "";
    }
    if (!defined($options)) {
	$options = "";
    }
    
    $TM = OPENTMCC($cmd, $args, $options);

    close($TM)
	or die $? ? "TMCC exited with status $?" : "Error closing pipe: $!";
    
    return 0;
}

#
# Reset to a moderately clean state.
#
sub cleanup_node ($) {
    my ($scrub) = @_;
    
    print STDOUT "Cleaning node; removing configuration files ...\n";
    unlink TMIFC, TMRPM, TMSTARTUPCMD, TMTARBALLS;
    unlink TMROUTECONFIG, TMTRAFFICCONFIG, TMTUNNELCONFIG;
    unlink TMDELAY, TMLINKDELAY, TMPROGAGENTS, TMSYNCSERVER, TMRCSYNCSERVER;
    unlink TMMOUNTDB . ".db";
    unlink TMSFSMOUNTDB . ".db";
    unlink "$VARDIR/db/rtabid";

    #
    # If scrubbing, remove the password/group file DBs so that we revert
    # to base set.
    # 
    if ($scrub) {
	unlink TMNICKNAME;
	unlink TMPASSDB . ".db";
	unlink TMGROUPDB . ".db";
    }

    if (! REMOTE()) {
	printf STDOUT "Resetting %s file\n", HOSTSFILE;
	if (system($CP, "-f", TMHOSTS, HOSTSFILE) != 0) {
	    printf "Could not copy default %s into place: $!\n", HOSTSFILE;
	    exit(1);
	}
    }

    return os_cleanup_node($scrub);
}

#
# Check node allocation. If the nickname file has been created, use
# that to avoid load on tmcd.
#
# Returns 0 if node is free. Returns list (pid/eid/vname) if allocated.
#
sub check_status ()
{
    my $TM = OPENTMCC(TMCCCMD_STATUS);
    $_  = <$TM>;
    CLOSETMCC($TM);

    if ($_ =~ /^FREE/) {
	unlink TMNICKNAME;
	return 0;
    }
    
    if ($_ =~ /ALLOCATED=([-\@\w]*)\/([-\@\w]*) NICKNAME=([-\@\w]*)/) {
	$pid   = $1;
	$eid   = $2;
	$vname = $3;
    }
    else {
	warn "*** WARNING: Error getting reservation status\n";
	return 0;
    }
    
    #
    # Stick our nickname in a file in case someone wants it.
    # Do not overwrite; we want to save the original info until later.
    # See bootsetup; indicates project change!
    #
    if (! -e TMNICKNAME()) {
	system("echo '$vname.$eid.$pid' > " . TMNICKNAME());
    }
    
    return ($pid, $eid, $vname);
}

#
# Check cached nickname. Its okay if we have been deallocated and the info
# is stale. The node will notice that later.
# 
sub check_nickname()
{
    if (-e TMNICKNAME) {
	my $nickfile = TMNICKNAME;
	my $nickinfo = `cat $nickfile`;

	if ($nickinfo =~ /([-\@\w]*)\.([-\@\w]*)\.([-\@\w]*)/) {
	    $vname = $1;
	    $eid   = $2;
	    $pid   = $3;

	    return ($pid, $eid, $vname);
	}
    }
    return check_status();
}

#
# Process mount directives from TMCD. We keep track of all the mounts we
# have added in here so that we delete just the mounts we added, when
# project membership changes. Same goes for project directories on shared
# nodes. We use a simple perl DB for that.
#
sub domounts()
{
    my $TM;
    my %MDB;
    my %mounts;
    my %deletes;
    my %sfsmounts;
    my %sfsdeletes;

    #
    # Update our SFS hostid first. If this fails, dosfshostid will
    # unset USESFS.
    # 
    if ($USESFS) {
	if (! MFS()) {
	    #
	    # Setup SFS hostid.
	    #
	    print STDOUT "Setting up for SFS ... \n";
	    dosfshostid();
	}
	else {
	    # No SFS on the MFS.
	    $USESFS = 0;
	}
    }

    $TM = OPENTMCC(TMCCCMD_MOUNTS, "USESFS=$USESFS");

    while (<$TM>) {
	if ($_ =~ /^REMOTE=([-:\@\w\.\/]+) LOCAL=([-\@\w\.\/]+)/) {
	    $mounts{$1} = $2;
	}
	elsif ($_ =~ /^SFS REMOTE=([-:\@\w\.\/]+) LOCAL=([-\@\w\.\/]+)/) {
	    $sfsmounts{$1} = $2;
	}
	else {
	    warn "*** WARNING: Malformed mount information: $_\n";
	}
    }
    CLOSETMCC($TM);
    
    #
    # The MFS version does not support (or need) this DB stuff. Just mount
    # them up.
    #
    if (MFS()) {
	while (($remote, $local) = each %mounts) {
	    if (! -e $local) {
		if (! os_mkdir($local, "0770")) {
		    warn "*** WARNING: Could not make directory $local: $!\n";
		    next;
		}
	    }
	
	    print STDOUT "  Mounting $remote on $local\n";
	    if (system("$NFSMOUNT $remote $local")) {
		warn "*** WARNING: Could not $NFSMOUNT ".
		    "$remote on $local: $!\n";
		next;
	    }
	}
	return 0;
    }

    dbmopen(%MDB, TMMOUNTDB, 0660);
    
    #
    # First mount all the mounts we are told to. For each one that is not
    # currently mounted, and can be mounted, add it to the DB.
    # 
    while (($remote, $local) = each %mounts) {
	if (defined($MDB{$remote})) {
	    next;
	}

	if (! -d $local) {
	    # Leftover SFS link.
	    if (-l $local) {
		unlink($local) or
		    warn "*** WARNING: Could not unlink $local: $!\n";
	    }
	    if (! os_mkdir($local, "0770")) {
		warn "*** WARNING: Could not make directory $local: $!\n";
		next;
	    }
	}
	
	print STDOUT "  Mounting $remote on $local\n";
	if (system("$NFSMOUNT $remote $local")) {
	    warn "*** WARNING: Could not $NFSMOUNT $remote on $local: $!\n";
	    next;
	}

	$MDB{$remote} = $local;
    }

    #
    # Now unmount the ones that we mounted previously, but are now no longer
    # in the mount set (as told to us by the TMCD). Note, we cannot delete 
    # them directly from MDB since that would mess up the foreach loop, so
    # just stick them in temp and postpass it.
    #
    while (($remote, $local) = each %MDB) {
	if (defined($mounts{$remote})) {
	    next;
	}

	print STDOUT "  Unmounting $local\n";
	if (system("$UMOUNT $local")) {
	    warn "*** WARNING: Could not unmount $local\n";
	    next;
	}
	
	#
	# Only delete from set if we can actually unmount it. This way
	# we can retry it later (or next time).
	# 
	$deletes{$remote} = $local;
    }
    while (($remote, $local) = each %deletes) {
	delete($MDB{$remote});
    }

    # Write the DB back out!
    dbmclose(%MDB);

    #
    # Now, do basically the same thing over again, but this time for
    # SFS mounted stuff
    #

    if (scalar(%sfsmounts)) {
	dbmopen(%MDB, TMSFSMOUNTDB, 0660);
	
	#
	# First symlink all the mounts we are told to. For each one
	# that is not currently symlinked, and can be, add it to the
	# DB.
	#
	while (($remote, $local) = each %sfsmounts) {
	    if (-l $local) {
		if (readlink($local) eq ("/sfs/" . $remote)) {
		    $MDB{$remote} = $local;
		    next;
		}
		if (readlink($local) ne ("/sfs/" . $remote)) {
		    print STDOUT "  Unlinking incorrect symlink $local\n";
		    if (! unlink($local)) {
			warn "*** WARNING: Could not unlink $local: $!\n";
			next;
		    }
		}
	    }
	    elsif (-d $local) {
		if (! rmdir($local)) {
		    warn "*** WARNING: Could not rmdir $local: $!\n";
		    next;
		}
	    }
	    
	    $dir = $local;
	    $dir =~ s/(.*)\/[^\/]*$/$1/;
	    if ($dir ne "" && ! -e $dir) {
		print STDOUT "  Making directory $dir\n";
		if (! os_mkdir($dir, "0755")) {
		    warn "*** WARNING: Could not make directory $local: $!\n";
		    next;
		}
	    }
	    print STDOUT "  Symlinking $remote on $local\n";
	    if (! symlink("/sfs/" . $remote, $local)) {
		warn "*** WARNING: Could not make symlink $local: $!\n";
		next;
	    }
	    
	    $MDB{$remote} = $local;
	}

	#
	# Now delete the ones that we symlinked previously, but are
	# now no longer in the mount set (as told to us by the TMCD).
	# Note, we cannot delete them directly from MDB since that
	# would mess up the foreach loop, so just stick them in temp
	# and postpass it.
	#
	while (($remote, $local) = each %MDB) {
	    if (defined($sfsmounts{$remote})) {
		next;
	    }
	    
	    if (! -e $local) {
		$sfsdeletes{$remote} = $local;
		next;
	    }
	    
	    print STDOUT "  Deleting symlink $local\n";
	    if (! unlink($local)) {
		warn "*** WARNING: Could not delete $local: $!\n";
		next;
	    }
	    
	    #
	    # Only delete from set if we can actually unlink it.  This way
	    # we can retry it later (or next time).
	    #
	    $sfsdeletes{$remote} = $local;
	}
	while (($remote, $local) = each %sfsdeletes) {
	    delete($MDB{$remote});
	}

	# Write the DB back out!
	dbmclose(%MDB);	
    }
    else {
	# There were no SFS mounts reported, so disable SFS
	$USESFS = 0;
    }

    return 0;
}

#
# Aux function called from the mkjail code to do mounts outside
# of a jail, and return the list of mounts that were created. Can use
# either NFS or local loopback. Maybe SFS someday. Local only, of course.
# 
sub JailedMounts($$$)
{
    my ($vid, $rootpath, $usenfs) = @_;
    my @mountlist = ();
    my $mountstr;

    #
    # No NFS mounts on remote nodes.
    # 
    if (REMOTE()) {
	return ();
    }

    if ($usenfs) {
	$mountstr = $NFSMOUNT;
    } else {
	$mountstr = $LOOPBACKMOUNT;
    }

    #
    # Mount same set of existing mounts. A hack, but this whole NFS thing
    # is a serious hack inside jails.
    #
    dbmopen(%MDB, TMMOUNTDB, 0444);
    
    while (my ($remote, $path) = each %MDB) {
	$local = "$rootpath$path";
	    
	if (! -e $local) {
	    if (! os_mkdir($local, "0770")) {
		warn "*** WARNING: Could not make directory $local: $!\n";
		next;
	    }
	}
	
	if (! $usenfs) {
	    $remote = $path;
	}

	print STDOUT "  Mounting $remote on $local\n";
	if (system("$mountstr $remote $local")) {
	    warn "*** WARNING: Could not $mountstr $remote on $local: $!\n";
	    next;
	}
	push(@mountlist, $path);
    }
    dbmclose(%MDB);	   
    return @mountlist;
}
#
# Do SFS hostid setup.
# Creates an SFS host key for this node, if it doesn't already exist,
# and sends it to TMCD
#
sub dosfshostid ()
{
    my $TM;
    my $myhostid;

    # Do I already have a host key?
    if (! -e "/etc/sfs/sfs_host_key") {
	warn "*** This node does not have a host key, skipping SFS stuff\n";
	$USESFS = 0;
	return 1;
    }

    # Give hostid to TMCD
    if (-d "/usr/local/lib/sfs-0.6") {
	$myhostid = `sfskey hostid - 2>/dev/null`;
    }
    else {
	$myhostid = `sfskey hostid -s authserv - 2>/dev/null`;
    }
    if (! $?) {
	if ( $myhostid =~ /^([-\.\w_]*:[a-z0-9]*)$/ ) {
	    $myhostid = $1;
	    print STDOUT "  Hostid: $myhostid\n";
	    RUNTMCC(TMCCCMD_SFSHOSTID, "$myhostid");
	}
	elsif ( $myhostid =~ /^(@[-\.\w_]*,[a-z0-9]*)$/ ) {
	    $myhostid = $1;
	    print STDOUT "  Hostid: $myhostid\n";
	    RUNTMCC(TMCCCMD_SFSHOSTID, "$myhostid");
	}
	else {
	    warn "*** WARNING: Invalid hostid\n";
	}
    }
    else {
	warn "*** WARNING: Could not retrieve this node's SFShostid!\n";
	$USESFS = 0;
    }

    return 0;
}

#
# Do interface configuration.    
# Write a file of ifconfig lines, which will get executed.
#
sub doifconfig (;$)
{
    my ($rtabid) = @_;
    my @ifaces   = ();
    my $upcmds   = "";
    my $downcmds = "";
    my @ifacelist= ();

    #
    # Kinda ugly, but there is too much perl goo included by Socket to put it
    # on the MFS. 
    # 
    if (MFS()) {
	return 1;
    }

    my $TM = OPENTMCC(TMCCCMD_IFC);
    while (<$TM>) {
	push(@ifaces, $_);
    }
    CLOSETMCC($TM);

    #
    # Create the interface list file.
    # Control net is always first.
    #
    open(XIFS, ">$BOOTDIR/tmcc.ifs") or
	die "Cannot open file $BOOTDIR/tmcc.ifs: $!";

    print XIFS `control_interface`;

    if (! @ifaces) {
	close(XIFS);
	return 0;
    }

    my $ethpat  = q(IFACETYPE=(\w*) INET=([0-9.]*) MASK=([0-9.]*) MAC=(\w*) );
    $ethpat    .= q(SPEED=(\w*) DUPLEX=(\w*) IPALIASES="(.*)" IFACE=(\w*));

    my $vethpat = q(IFACETYPE=(\w*) INET=([0-9.]*) MASK=([0-9.]*) ID=(\d*) );
    $vethpat   .= q(VMAC=(\w*) PMAC=(\w*));

    foreach my $iface (@ifaces) {
	if ($iface =~ /$ethpat/) {
	    my $inet     = $2;
	    my $mask     = $3;
	    my $mac      = $4;
	    my $speed    = $5; 
	    my $duplex   = $6;
	    my $aliases  = $7;
	    my $iface    = $8;
	    my $routearg = inet_ntoa(inet_aton($inet) & inet_aton($mask));

	    if (($iface ne "") ||
		($iface = findiface($mac))) {
		if (JAILED()) {
		    next;
		}
		print XIFS "$iface\n";

		#
		# Rather than try to wedge the IXP in, I am going with
		# a new approach. Parse the results from tmcd into a
		# simple data structure, and return that for the caller
		# to use. Might want to use a perl module at some point.
		#
		my $ifconfig = {};
		    
		$ifconfig->{"IPADDR"}   = $inet;
		$ifconfig->{"IPMASK"}   = $mask;
		$ifconfig->{"MAC"}      = $mac;
		$ifconfig->{"SPEED"}    = $speed;
		$ifconfig->{"DUPLEX"}   = $duplex;
		$ifconfig->{"ALIASES"}  = $aliases;
		$ifconfig->{"IFACE"}    = $iface;
		push(@ifacelist, $ifconfig);

		if (IXP()) {
		    next;
		}

		my ($upline, $downline) =
		    os_ifconfig_line($iface, $inet, $mask,
				     $speed, $duplex, $aliases,$rtabid);
		    
		$upcmds   .= "$upline\n    "
		    if (defined($upline));
		$upcmds   .= TMROUTECONFIG . " $routearg up\n";
		
		$downcmds .= TMROUTECONFIG . " $routearg down\n    ";
		$downcmds .= "$downline\n    "
		    if (defined($downline));

		# There could be routes for each alias.
		foreach my $alias (split(',', $aliases)) {
		    $routearg = inet_ntoa(inet_aton($alias) &
					  inet_aton($mask));
			
		    $upcmds   .= TMROUTECONFIG . " $routearg up\n";
		    $downcmds .= TMROUTECONFIG . " $routearg down\n";
		}
	    }
	    else {
		warn "*** WARNING: Bad MAC: $mac\n";
	    }
	}
	elsif ($iface =~ /$vethpat/) {
	    my $iface    = undef;
	    my $inet     = $2;
	    my $mask     = $3;
	    my $id       = $4;
	    my $vmac     = $5;
	    my $pmac     = $6; 
	    my $routearg = inet_ntoa(inet_aton($inet) & inet_aton($mask));

	    if (JAILED()) {
		if ($iface = findiface($vmac)) {
		    print XIFS "$iface\n";
		}
		next;
	    }

	    if ($pmac eq "none" ||
		($iface = findiface($pmac))) {
		print XIFS "$iface\n"
		    if (defined($iface));

		my ($upline, $downline) =
		    os_ifconfig_veth($iface, $inet, $mask, $id, $vmac,$rtabid);
		    
		$upcmds   .= "$upline\n    ";
		$upcmds   .= TMROUTECONFIG . " $routearg up\n";
		
		$downcmds .= TMROUTECONFIG . " $routearg down\n    ";
		$downcmds .= "$downline\n    "
		    if (defined($downline));
	    }
	    else {
		warn "*** WARNING: Bad PMAC: $pmac\n";
	    }
	}
	else {
	    warn "*** WARNING: Bad ifconfig line: $_";
	}
    }
    close(XIFS);
    # Done when jailed or an IXP
    return @ifacelist
	if (JAILED() || IXP());

    #
    # Local file into which we write ifconfig commands (as a shell script).
    # 
    open(IFC, ">" . TMIFC)
	or die("Could not open " . TMIFC . ": $!");

    print IFC "#!/bin/sh\n";
    print IFC "# auto-generated by libsetup.pm, DO NOT EDIT\n";
    print IFC "if [ x\$1 = x ]; then action=enable; else action=\$1; fi\n";
    print IFC "case \"\$action\" in\n";
    print IFC "  enable)\n";
    print IFC "    $upcmds\n";
    print IFC "    ;;\n";
    print IFC "  disable)\n";
    print IFC "    $downcmds\n";
    print IFC "    ;;\n";
    print IFC "esac\n";
    close(IFC);
    chmod(0755, TMIFC);

    return 0;
}

#
# Convert from MAC to iface name (eth0/fxp0/etc) using little helper program.
# 
sub findiface($)
{
    my($mac) = @_;
    my($iface);

    open(FIF, FINDIF . " $mac |")
	or die "Cannot start " . FINDIF . ": $!";

    $iface = <FIF>;
    
    if (! close(FIF)) {
	return 0;
    }
    
    $iface =~ s/\n//g;
    return $iface;
}

#
# Do router configuration stuff. This just writes a file for someone else
# to deal with.
#
sub dorouterconfig (;$)
{
    my ($rtabid) = @_;
    my @stuff    = ();
    my $routing  = 0;
    my %upmap    = ();
    my %downmap  = ();
    my @routes   = ();
    my $TM;

    $TM = OPENTMCC(TMCCCMD_ROUTING);
    while (<$TM>) {
	push(@stuff, $_);
    }
    CLOSETMCC($TM);

    if (! @stuff) {
	return 0;
    }

    #
    # Look for router type. If none, we still write the file since other
    # scripts expect this to exist.
    # 
    foreach my $line (@stuff) {
	if (($line =~ /ROUTERTYPE=(.+)/) && ($1 ne "none")) {
	    $routing = 1;
	    last;
	}
    }
    
    open(RC, ">" . TMROUTECONFIG)
	or die("Could not open " . TMROUTECONFIG . ": $!");

    print RC "#!/bin/sh\n";
    print RC "# auto-generated by libsetup.pm, DO NOT EDIT\n";

    if (! $routing) {
	print RC "true\n";
	close(RC);
	chmod(0755, TMROUTECONFIG);
	return 0;
    }

    #
    # Now convert static route info into OS route commands
    # Also check for use of gated and remember it.
    #
    my $usegated = 0;
    my $pat;

    #
    # ROUTERTYPE=manual
    # ROUTE DEST=192.168.2.3 DESTTYPE=host DESTMASK=255.255.255.0 \
    #	NEXTHOP=192.168.1.3 COST=0
    #
    $pat = q(ROUTE DEST=([0-9\.]*) DESTTYPE=(\w*) DESTMASK=([0-9\.]*) );
    $pat .= q(NEXTHOP=([0-9\.]*) COST=([0-9]*));

    my $usemanual = 0;
    foreach my $line (@stuff) {
	if ($line =~ /ROUTERTYPE=(gated|ospf)/) {
	    $usegated = 1;
	} elsif ($line =~ /ROUTERTYPE=(manual|static)/) {
	    $usemanual = 1;
	} elsif ($usemanual && $line =~ /$pat/) {
	    my $dip   = $1;
	    my $rtype = $2;
	    my $dmask = $3;
	    my $gate  = $4;
	    my $cost  = $5;
	    my $rcline;
	    my $routearg = inet_ntoa(inet_aton($gate) & inet_aton($dmask));

	    #
	    # For IXP.
	    #
	    my $rconfig = {};
		    
	    $rconfig->{"IPADDR"}   = $dip;
	    $rconfig->{"TYPE"}     = $rtype;
	    $rconfig->{"IPMASK"}   = $dmask;
	    $rconfig->{"GATEWAY"}  = $gate;
	    $rconfig->{"COST"}     = $cost;
	    push(@routes, $rconfig);

	    if (! defined($upmap{$routearg})) {
		$upmap{$routearg} = [];
		$downmap{$routearg} = [];
	    }
	    $rcline = os_routing_add_manual($rtype, $dip,
					    $dmask, $gate, $cost, $rtabid);
	    push(@{$upmap{$routearg}}, $rcline);
	    $rcline = os_routing_del_manual($rtype, $dip,
					    $dmask, $gate, $cost, $rtabid);
	    push(@{$downmap{$routearg}}, $rcline);
	} else {
	    warn "*** WARNING: Bad routing line: $line\n";
	}
    }

    print RC "case \"\$1\" in\n";
    foreach my $arg (keys(%upmap)) {
	print RC "  $arg)\n";
	print RC "    case \"\$2\" in\n";
	print RC "      up)\n";
	foreach my $rcline (@{$upmap{$arg}}) {
	    print RC "        $rcline\n";
	}
	print RC "      ;;\n";
	print RC "      down)\n";
	foreach my $rcline (@{$downmap{$arg}}) {
	    print RC "        $rcline\n";
	}
	print RC "      ;;\n";
	print RC "    esac\n";
	print RC "  ;;\n";
    }
    print RC "  enable)\n";

    #
    # Turn on IP forwarding
    #
    print RC "    " . os_routing_enable_forward() . "\n";

    #
    # Finally, enable gated if desired.
    #
    # Note that we allow both manually-specified static routes and gated
    # though more work may be needed on the gated config files to make
    # this work (i.e., to import existing kernel routes).
    #
    # XXX if rtabid is set, we are setting up routing from outside a
    # jail on behalf of a jail.  We don't want to enable gated in this
    # case, it will be run inside the jail.
    #
    if ($usegated && !defined($rtabid)) {
	print RC "    " . gatedsetup() . "\n";
    }
    print RC "  ;;\n";

    #
    # For convenience, allup and alldown.
    #
    print RC "  enable-routes)\n";
    foreach my $arg (keys(%upmap)) {
	foreach my $rcline (@{$upmap{$arg}}) {
	    print RC "    $rcline\n";
	}
    }
    print RC "  ;;\n";
    
    print RC "  disable-routes)\n";
    foreach my $arg (keys(%downmap)) {
	foreach my $rcline (@{$downmap{$arg}}) {
	    print RC "    $rcline\n";
	}
    }
    print RC "  ;;\n";
    print RC "esac\n";
    print RC "exit 0\n";

    close(RC);
    chmod(0755, TMROUTECONFIG);

    return @routes;
}

sub gatedsetup ()
{
    my ($cnet, @xifs) = split('\n', `cat $BOOTDIR/tmcc.ifs`);

    open(IFS, ">" . TMGATEDCONFIG)
	or die("Could not open " . TMGATEDCONFIG . ": $!");

    print IFS "# auto-generated by libsetup.pm, DO NOT EDIT\n\n";
    #
    # XXX hack: in a jail, the control net is an IP alias with a host mask.
    # This blows gated out of the water, so we have to make the control
    # interface appear to have a subnet mask.
    #
    if (JAILED() && -e "$BOOTDIR/myip") {
	my $hostip = `cat $BOOTDIR/myip`;
	chomp($hostip);
	print IFS "interfaces {\n".
	    "\tdefine subnet local $hostip netmask 255.240.0.0;\n};\n";
    }
    print IFS "smux off;\nrip off;\nospf on {\n";
    print IFS "\tbackbone {\n\t\tinterface $cnet { passive; };\n\t};\n";
    print IFS "\tarea 0.0.0.2 {\n\t\tauthtype none;\n";

    foreach my $xif (@xifs) {
	print IFS "\t\tinterface $xif { priority 1; };\n";
    }

    print IFS "\t};\n};\n";
    close(IFS);

    return os_routing_enable_gated(TMGATEDCONFIG);
}

#
# Host names configuration (/etc/hosts). 
#
sub dohostnames ()
{
    my $TM;
    my $HTEMP = HOSTSFILE . ".new";

    #
    # Note, we no longer start with the 'prototype' file here, because we have
    # to make up a localhost line that's properly qualified.
    #
    $TM = OPENTMCC(TMCCCMD_HOSTS);

    open(HOSTS, ">$HTEMP")
	or die("Could not open $HTEMP: $!");

    my $localaliases = "loghost";

    #
    # Find out our domain name, so that we can qualify the localhost entry
    #
    my $hostname = `hostname`;
    if ($hostname =~ /[^.]+\.(.+)/) {
	$localaliases .= " localhost.$1";
    }
    
    #
    # First, write a localhost line into the hosts file - we have to know the
    # domain to use here
    #
    print HOSTS os_etchosts_line("localhost", "127.0.0.1",
				 $localaliases), "\n";

    #
    # Now convert each hostname into hosts file representation and write
    # it to the hosts file. Note that ALIASES is for backwards compat.
    # Should go away at some point.
    #
    my $pat  = q(NAME=([-\w\.]+) IP=([0-9\.]*) ALIASES=\'([-\w\. ]*)\');
    
    while (<$TM>) {
	if ($_ =~ /$pat/) {
	    my $name    = $1;
	    my $ip      = $2;
	    my $aliases = $3;
	    
	    my $hostline = os_etchosts_line($name, $ip, $aliases);
	    
	    print HOSTS  "$hostline\n";
	}
	else {
	    warn "*** WARNING: Bad hosts line: $_";
	}
    }
    CLOSETMCC($TM);
    close(HOSTS);
    system("mv -f $HTEMP " . HOSTSFILE) == 0 or
	warn("*** Could not mv $HTEMP to ". HOSTSFILE . "!\n");

    return 0;
}

sub doaccounts()
{
    my %newaccounts = ();
    my %newgroups   = ();
    my %pubkeys1    = ();
    my %pubkeys2    = ();
    my @sfskeys     = ();
    my %deletes     = ();
    my %lastmod     = ();
    my %PWDDB;
    my %GRPDB;

    my $TM = OPENTMCC(TMCCCMD_ACCT);

    #
    # The strategy is to keep a record of all the groups and accounts
    # added by the testbed system so that we know what to remove. We
    # use a vanilla perl dbm for that, one for the groups and one for
    # accounts. 
    #
    # First just get the current set of groups/accounts from tmcd.
    #
    while (<$TM>) {
	if ($_ =~ /^ADDGROUP NAME=([-\@\w.]+) GID=([0-9]+)/) {
	    #
	    # Group info goes in the hash table.
	    #
	    my $gname = "$1";
	    
	    if (REMOTE() && !JAILED() && !PLAB()) {
		$gname = "emu-${gname}";
	    }
	    $newgroups{"$gname"} = $2
	}
	elsif ($_ =~ /^ADDUSER LOGIN=([0-9A-Za-z]+)/) {
	    #
	    # Account info goes in the hash table.
	    # 
	    $newaccounts{$1} = $_;
	    next;
	}
	elsif ($_ =~ /^PUBKEY LOGIN=([0-9A-Za-z]+) KEY="(.*)"/) {
	    #
	    # Keys go into hash as a list of keys.
	    #
	    my $login = $1;
	    my $key   = $2;

	    #
	    # P1 or P2 key. Must be treated differently below.
	    #
	    if ($key =~ /^\d+\s+.*$/) {
		if (! defined($pubkeys1{$login})) {
		    $pubkeys1{$login} = [];
		}
		push(@{$pubkeys1{$login}}, $key);
	    }
	    else {
		if (! defined($pubkeys2{$login})) {
		    $pubkeys2{$login} = [];
		}
		push(@{$pubkeys2{$login}}, $key);
	    }
	    next;
	}
	elsif ($_ =~ /^SFSKEY KEY="(.*)"/) {
	    #
	    # SFS key goes into the array.
	    #
	    push(@sfskeys, $1);
	    next;
	}
	else {
	    warn "*** WARNING: Bad accounts line: $_\n";
	}
    }
    CLOSETMCC($TM);

    if (! MFS()) {
	#
	# On the MFS, these will just start out as empty hashes.
	# 
	dbmopen(%PWDDB, TMPASSDB, 0660) or
	    die("Cannot open " . TMPASSDB . ": $!\n");
	
	dbmopen(%GRPDB, TMGROUPDB, 0660) or
	    die("Cannot open " . TMGROUPDB . ": $!\n");
    }

    #
    # Create any groups that do not currently exist. Add each to the
    # DB as we create it.
    #
    while (($group, $gid) = each %newgroups) {
	my ($exists,undef,$curgid) = getgrnam($group);
	
	if ($exists) {
	    if ($gid != $curgid) {
		warn "*** WARNING: $group/$gid mismatch with existing group\n";
	    }
	    next;
	}

	print "Adding group: $group/$gid\n";
	    
	if (os_groupadd($group, $gid)) {
	    warn "*** WARNING: Error adding new group $group/$gid\n";
	    next;
	}
	# Add to DB only if successful. 
	$GRPDB{$group} = $gid;
    }

    #
    # Now remove the ones that we created previously, but are now no longer
    # in the group set (as told to us by the TMCD). Note, we cannot delete 
    # them directly from the hash since that would mess up the foreach loop,
    # so just stick them in temp and postpass it.
    #
    while (($group, $gid) = each %GRPDB) {
	if (defined($newgroups{$group})) {
	    next;
	}

	print "Removing group: $group/$gid\n";
	
	if (os_groupdel($group)) {
	    warn "*** WARNING: Error removing group $group/$gid\n";
	    next;
	}
	# Delete from DB only if successful. 
	$deletes{$group} = $gid;
    }
    while (($group, $gid) = each %deletes) {
	delete($GRPDB{$group});
    }
    %deletes = ();

    # Write the DB back out!
    if (! MFS()) {
	dbmclose(%GRPDB);
    }

    #
    # Repeat the same sequence for accounts, except we remove old accounts
    # first. 
    # 
    while (($login, $info) = each %PWDDB) {
	my $uid = $info;
	
	#
	# Split out the uid from the serial. Note that this was added later
	# so existing DBs might not have a serial yet. We save the serial
	# for later. 
	#
	if ($info =~ /(\d*):(\d*)/) {
	    $uid = $1;
	    $lastmod{$login} = $2;
	}
	
	if (defined($newaccounts{$login})) {
	    next;
	}

	my ($exists,undef,$curuid,undef,
	    undef,undef,undef,$homedir) = getpwnam($login);

	#
	# If the account is gone, someone removed it by hand. Remove it
	# from the DB so we do not keep trying.
	#
	if (! defined($exists)) {
	    warn "*** WARNING: Account for $login was already removed!\n";
	    $deletes{$login} = $login;
	    next;
	}

	#
	# Check for mismatch, just in case. If there is a mismatch remove it
	# from the DB so we do not keep trying.
	#
	if ($uid != $curuid) {
	    warn "*** WARNING: ".
		 "Account uid for $login has changed ($uid/$curuid)!\n";
	    $deletes{$login} = $login;
	    next;
	}
	
	print "Removing user: $login\n";
	
	if (os_userdel($login) != 0) {
	    warn "*** WARNING: Error removing user $login\n";
	    next;
	}

	#
	# Remove the home dir. 
	#
	# Must ask for the current home dir in case it came from pw.conf.
	#
	if (defined($homedir) &&
	    index($homedir, "/${login}")) {
	    if (os_homedirdel($login, $homedir) != 0) {
	        warn "*** WARNING: Could not remove homedir $homedir.\n";
	    }
	}
	
	# Delete from DB only if successful. 
	$deletes{$login} = $login;
    }
    
    while (($login, $foo) = each %deletes) {
	delete($PWDDB{$login});
    }

    my $pat = q(ADDUSER LOGIN=([0-9A-Za-z]+) PSWD=([^:]+) UID=(\d+) GID=(.*) );
    $pat   .= q(ROOT=(\d) NAME="(.*)" HOMEDIR=(.*) GLIST="(.*)" );
    $pat   .= q(SERIAL=(\d+) EMAIL="([-\w\@\.\+]+)" SHELL=([-\w]*));

    while (($login, $info) = each %newaccounts) {
	if ($info =~ /$pat/) {
	    $pswd  = $2;
	    $uid   = $3;
	    $gid   = $4;
	    $root  = $5;
	    $name  = $6;
	    $hdir  = $7;
	    $glist = $8;
	    $serial= $9;
	    $email = $10;
	    $shell = $11;
	    if ( $name =~ /^(([^:]+$|^))$/ ) {
		$name = $1;
	    }

	    #
	    # See if update needed, based on the serial number we get.
	    # If its different, the account info has changed.
	    # 
	    my $doupdate = 0;
	    if (!defined($lastmod{$login}) || $lastmod{$login} != $serial) {
		$doupdate = 1;
	    }
	    
	    my ($exists,undef,$curuid) = getpwnam($login);

	    if ($exists) {
		if (!defined($PWDDB{$login})) {
		    warn "*** WARNING: ".
			 "Skipping since $login existed before EmulabMan!\n";
		    next;
		}
		if ($curuid != $uid) {
		    warn "*** WARNING: ".
			 "$login/$uid uid mismatch with existing login.\n";
		    next;
		}
		if ($doupdate) {
		    print "Updating: ".
			"$login/$uid/$gid/$root/$name/$hdir/$glist\n";
		    
		    os_usermod($login, $gid, "$glist", $pswd, $root, $shell);

		    #
		    # Note that we changed the info for next time.
		    # 
		    $PWDDB{$login} = "$uid:$serial";
		}
	    }
	    else {
		print "Adding: $login/$uid/$gid/$root/$name/$hdir/$glist\n";

		if (os_useradd($login, $uid, $gid, $pswd, 
			       "$glist", $hdir, $name, $root, $shell)) {
		    warn "*** WARNING: Error adding new user $login\n";
		    next;
		}

		if (PLAB() && ! -e $hdir) {
		    if (! os_mkdir($hdir, "0755")) {
			warn "*** WARNING: Error creating user homedir\n";
			next;
		    }
		    chown($uid, $gid, $hdir);
		}
		
		# Add to DB only if successful. 
		$PWDDB{$login} = "$uid:$serial";
	    }

	    #
	    # Remote nodes and local control nodes get this. 
	    # 
	    if ((REMOTE() || CONTROL()) && $doupdate) {
		#
		# Must ask for the current home dir since we rely on pw.conf.
		#
		my (undef,undef,undef,undef,
		    undef,undef,undef,$homedir) = getpwuid($uid);
		my $sshdir  = "$homedir/.ssh";
		my $forward = "$homedir/.forward";

		#
		# Create .ssh dir and populate it with an authkeys file.
		#
		TBNewsshKeyfile($sshdir, $uid, $gid, 1, @{$pubkeys1{$login}});
		TBNewsshKeyfile($sshdir, $uid, $gid, 2, @{$pubkeys2{$login}});

		#
		# Give user a .forward back to emulab.
		#
		if (! -e $forward) {
		    system("echo '$email' > $forward");
		
		    chown($uid, $gid, $forward) 
			or warn("*** Could not chown $forward: $!\n");
		
		    chmod(0644, $forward) 
			or warn("*** Could not chmod $forward: $!\n");
		}
	    }
	}
	else {
	    warn("*** Bad accounts line: $info\n");
	}
    }
    # Write the DB back out!
    if (! MFS()) {
	dbmclose(%PWDDB);
    }

    #
    # Create sfs_users file and populate it with public SFS keys
    #
    if ($USESFS) {
	my $sfsusers = "/etc/sfs/sfs_users";
	
	if (!open(SFSKEYS, "> ${sfsusers}.new")) {
	    warn("*** WARNING: Could not open ${sfsusers}.new: $!\n");
	    goto bad;
	}
	    
	print SFSKEYS "#\n";
	print SFSKEYS "# DO NOT EDIT! This file auto generated by ".
	    "Emulab.Net account software.\n";
	print SFSKEYS "#\n";
	print SFSKEYS "# Please use the web interface to edit your ".
	    "SFS public key list.\n";
	print SFSKEYS "#\n";
	foreach my $key (@sfskeys) {
	    print SFSKEYS "$key\n";
	}
	close(SFSKEYS);

	if (!chown(0, 0, "${sfsusers}.new")) {
	    warn("*** WARNING: Could not chown ${sfsusers}.new: $!\n");
	    goto bad;
	}
	if (!chmod(0600, "${sfsusers}.new")) {
	    warn("*** WARNING: Could not chmod ${sfsusers}.new: $!\n");
	    goto bad;
	}
	    
	#
	# If there is an update script, its the new version of SFS.
	# Run that script to convert the keys over. At some point ops
	# and the DB will be converted too, and this can go away.
	#
	if (-x "/usr/local/lib/sfs/upgradedb.pl") {
	    system("/usr/local/lib/sfs/upgradedb.pl ${sfsusers}.new");
	    system("rm -f ${sfsusers}.new.v1-saved-1");
	}

	# Because sfs_users only contains public keys, sfs_users.pub is
	# exactly the same
	if (system("cp -p -f ${sfsusers}.new ${sfsusers}.pub.new")) {
	    warn("*** WARNING Could not copy ${sfsusers}.new to ".
		 "${sfsusers}.pub.new: $!\n");
	    goto bad;
	}
	    
	if (!chmod(0644, "${sfsusers}.pub.new")) {
	    warn("*** WARNING: Could not chmod ${sfsusers}.pub.new: $!\n");
	    goto bad;
	}

	# Save off old key files and move in new ones
	foreach my $keyfile ("${sfsusers}", "${sfsusers}.pub") {
	    if (-e $keyfile) {
		if (system("cp -p -f $keyfile $keyfile.old")) {
		    warn("*** Could not save off $keyfile: $!\n");
		    next;
		}
		if (!chown(0, 0, "$keyfile.old")) {
		    warn("*** Could not chown $keyfile.old: $!\n");
		}
		if (!chmod(0600, "$keyfile.old")) {
		    warn("*** Could not chmod $keyfile.old: $!\n");
		}
	    }
	    if (system("mv -f $keyfile.new $keyfile")) {
		warn("*** Could not mv $keyfile.new $keyfile.new: ~!\n");
	    }
	}
      bad:
    }
    
    return 0;
}

#
# RPM configuration. 
#
sub dorpms ()
{
    my @rpms = ();
    
    my $TM = OPENTMCC(TMCCCMD_RPM);
    while (<$TM>) {
	push(@rpms, $_);
    }
    CLOSETMCC($TM);

    if (! @rpms) {
	return 0;
    }
    
    open(RPM, ">" . TMRPM)
	or die("Could not open " . TMRPM . ": $!");
    print RPM "#!/bin/sh\n";
    
    foreach my $rpm (@rpms) {
	if ($rpm =~ /RPM=(.+)/) {
	    my $rpmline = os_rpminstall_line($1);
		    
	    print STDOUT "  $rpmline\n";
	    print RPM    "echo \"Installing RPM $1\"\n";
	    print RPM    "$rpmline\n";
	}
	else {
	    warn "*** WARNING: Bad RPMs line: $rpm";
	}
    }
    close(RPM);
    chmod(0755, TMRPM);

    return 0;
}

#
# TARBALL configuration. 
#
sub dotarballs ()
{
    my @tarballs   = ();
    my $jailoption = (JAILED() ? "-j" : "");
    # XXX Plab option?
    
    my $TM = OPENTMCC(TMCCCMD_TARBALL);
    while (<$TM>) {
	push(@tarballs, $_);
    }
    CLOSETMCC($TM);

    if (! @tarballs) {
	return 0;
    }
    
    open(TARBALL, ">" . TMTARBALLS)
	or die("Could not open " . TMTARBALLS . ": $!");
    print TARBALL "#!/bin/sh\n";
    
    foreach my $tarball (@tarballs) {
	if ($tarball =~ /DIR=(.+)\s+TARBALL=(.+)/) {
	    my $tbline = sprintf($TARINSTALL, $jailoption, $1, $2);
		    
	    print STDOUT  "  $tbline\n";
	    print TARBALL "echo \"Installing Tarball $2 in dir $1 \"\n";
	    print TARBALL "$tbline\n";
	}
	else {
	    warn "*** WARNING: Bad Tarballs line: $tarball";
	}
    }
    close(TARBALL);
    chmod(0755, TMTARBALLS);

    return 0;
}

#
# Experiment startup Command.
#
sub dostartupcmd ()
{
    my $startupcmd;
    
    my $TM = OPENTMCC(TMCCCMD_STARTUP);
    $_ = <$TM>;
    if (defined($_)) {
	$startupcmd = $_;
    }
    CLOSETMCC($TM);

    if (! $startupcmd) {
	return 0;
    }
    
    open(RUN, ">" . TMSTARTUPCMD)
	or die("Could not open $TMSTARTUPCMD: $!");
    
    if ($startupcmd =~ /CMD=(\'.+\') UID=([0-9A-Za-z]+)/) {
	print  STDOUT "  Will run $1 as $2\n";
	print  RUN    "$startupcmd";
    }
    else {
	warn "*** WARNING: Bad startupcmd line: $startupcmd";
    }

    close(RUN);
    chmod(0755, TMSTARTUPCMD);

    return 0;
}

#
# Program agents. I would like to implement startup command using
# a program agent at some point ...
#
sub doprogagent ()
{
    my @agents = ();
    
    my $TM = OPENTMCC(TMCCCMD_PROGRAMS);
    while (<$TM>) {
	push(@agents, $_);
    }
    CLOSETMCC($TM);

    if (! @agents) {
	return 0;
    }

    #
    # Write the data to the file. The rc script will interpret it.
    # Note that one of the lines (the first) indicates what user to
    # run the agent as. 
    # 
    open(RUN, ">" . TMPROGAGENTS)
	or die("Could not open " . TMPROGAGENTS . ": $!");

    foreach my $line (@agents) {
	print RUN "$line";
    }
    close(RUN);

    return 0;
}

sub dotrafficconfig()
{
    my $didopen = 0;
    my $pat;
    my $TM;
    my $boss;
    my $startnse = 0;
    my $nseconfig = "";
    
    #
    # Kinda ugly, but there is too much perl goo included by Socket to put it
    # on the MFS. 
    # 
    if (MFS()) {
	return 1;
    }
    
    $TM = OPENTMCC(TMCCCMD_BOSSINFO);
    my $bossinfo = <$TM>;
    ($boss) = split(" ", $bossinfo);

    #
    # XXX hack: workaround for tmcc cmd failure inside TCL
    #     storing the output of a few tmcc commands in
    #     $BOOTDIR files for use by NSE
    #
    if (!REMOTE() && !JAILED()) {
	open(BOSSINFCFG, ">$BOOTDIR/tmcc.bossinfo") or
	    die "Cannot open file $BOOTDIR/tmcc.bossinfo: $!";
	print BOSSINFCFG "$bossinfo";
	close(BOSSINFCFG);
    }

    CLOSETMCC($TM);
    my ($pid, $eid, $vname) = check_nickname();

    my $cmdline = "$BINDIR/trafgen -s ";
    # Inside a jail, we connect to the local elvind and talk to the
    # master via the proxy.
    if (JAILED()) {
	$cmdline .= "localhost"
    }
    else {
	$cmdline .= "$boss"
    }
    if ($pid) {
	$cmdline .= " -E $pid/$eid";
    }

    #
    # XXX hack: workaround for tmcc cmd failure inside TCL
    #     storing the output of a few tmcc commands in
    #     $BOOTDIR files for use by NSE
    #
    # Also nse stuff is mixed up with traffic config right
    # now because of having FullTcp based traffic generation.
    # Needs to move to a different place
    if (!REMOTE() && !JAILED()) {
	my $record_sep;

	$record_sep = $/;
	undef($/);
	$TM = OPENTMCC(TMCCCMD_IFC);
	open(IFCFG, ">$BOOTDIR/tmcc.ifconfig") or
	    die "Cannot open file $BOOTDIR/tmcc.ifconfig: $!";
	print IFCFG <$TM>;
	close(IFCFG);
	CLOSETMCC($TM);
	$/ = $record_sep;
	
	open(TRAFCFG, ">$BOOTDIR/tmcc.trafgens") or
	    die "Cannot open file $BOOTDIR/tmcc.trafgens: $!";    
    }

    $TM = OPENTMCC(TMCCCMD_TRAFFIC);

    $pat  = q(TRAFGEN=([-\w.]+) MYNAME=([-\w.]+) MYPORT=(\d+) );
    $pat .= q(PEERNAME=([-\w.]+) PEERPORT=(\d+) );
    $pat .= q(PROTO=(\w+) ROLE=(\w+) GENERATOR=(\w+));

    while (<$TM>) {

	if (!REMOTE() && !JAILED()) {
	    print TRAFCFG "$_";
	}
	if ($_ =~ /$pat/) {
	    #
	    # The following is specific to the modified TG traffic generator:
	    #
	    #  trafgen [-s serverip] [-p serverport] [-l logfile] \
	    #	     [ -N name ] [-P proto] [-R role] [ -E pid/eid ] \
	    #	     [ -S srcip.srcport ] [ -T targetip.targetport ]
	    #
	    # N.B. serverport is not needed right now
	    #
	    my $name = $1;
	    my $ownaddr = inet_ntoa(my $ipaddr = gethostbyname($2));
	    my $ownport = $3;
	    my $peeraddr = inet_ntoa($ipaddr = gethostbyname($4));
	    my $peerport = $5;
	    my $proto = $6;
	    my $role = $7;
	    my $generator = $8;
	    my $target;
	    my $source;

	    # Skip if not specified as a TG generator. At some point
	    # work in Shashi's NSE work.
	    if ($generator ne "TG") {
		$startnse = 1;
		if (! $didopen) {
		    open(RC, ">" . TMTRAFFICCONFIG)
			or die("Could not open " . TMTRAFFICCONFIG . ": $!");
		    print RC "#!/bin/sh\n";
		    $didopen = 1;
		}
		next;
	    }

	    if ($role eq "sink") {
		$target = "$ownaddr.$ownport";
		$source = "$peeraddr.$peerport";
	    }
	    else {
		$target = "$peeraddr.$peerport";
		$source = "$ownaddr.$ownport";
	    }

	    if (! $didopen) {
		open(RC, ">" . TMTRAFFICCONFIG)
		    or die("Could not open " . TMTRAFFICCONFIG . ": $!");
		print RC "#!/bin/sh\n";
		$didopen = 1;
	    }
	    print RC "$cmdline -N $name -S $source -T $target -P $proto ".
		"-R $role >$LOGDIR/${name}-${pid}-${eid}.debug 2>&1 &\n";
	}
	else {
	    warn "*** WARNING: Bad traffic line: $_";
	}
    }
    if (!REMOTE() && !JAILED()) {
	close(TRAFCFG);
    }

    if( $startnse ) {
	print RC "$BINDIR/startnse &\n";
    }
    CLOSETMCC($TM);

    #
    # XXX hack: workaround for tmcc cmd failure inside TCL
    #     storing the output of a few tmcc commands in
    #     $BOOTDIR files for use by NSE
    #
    if (!REMOTE() && !JAILED()) {
	open(NSECFG, ">$BOOTDIR/tmcc.nseconfigs") or
	    die "Cannot open file $BOOTDIR/tmcc.nseconfigs: $!";
	$TM = OPENTMCC(TMCCCMD_NSECONFIGS);
	$record_sep = $/;
	undef($/);
	$nseconfig = <$TM>;
	$/ = $record_sep;
	print NSECFG $nseconfig;
	CLOSETMCC($TM);
	close(NSECFG);
    }
	    
    # XXX hack: need a separate section for starting up NSE when we
    #           support simulated nodes
    if( ! $startnse ) {
	
	if( $nseconfig ) {

	    # start NSE if 'tmcc nseconfigs' is not empty
	    if ( ! $didopen ) {
		open(RC, ">" . TMTRAFFICCONFIG)
		    or die("Could not open " . TMTRAFFICCONFIG . ": $!");
		print RC "#!/bin/sh\n";
		$didopen = 1;	
	    }
	    print RC "$BINDIR/startnse &\n";
	}
    }
    
    if ($didopen) {
	printf RC "%s %s\n", TMCC(), TMCCCMD_READY();
	close(RC);
	chmod(0755, TMTRAFFICCONFIG);
    }
    return 0;
}

sub dotunnels(;$)
{
    my ($rtabid) = @_;
    my @tunnels;
    my $pat;
    my $TM;
    my $didserver = 0;

    #
    # Kinda ugly, but there is too much perl goo included by Socket to put it
    # on the MFS. 
    # 
    if (MFS()) {
	return 1;
    }
    
    $TM = OPENTMCC(TMCCCMD_TUNNEL);
    while (<$TM>) {
	push(@tunnels, $_);
    }
    CLOSETMCC($TM);

    if (! @tunnels) {
	return 0;
    }
    my ($pid, $eid, $vname) = check_nickname();

    open(RC, ">" . TMTUNNELCONFIG)
	or die("Could not open " . TMTUNNELCONFIG . ": $!");
    print RC "#!/bin/sh\n";
    print RC "kldload if_tap\n";

    open(CONF, ">" . TMVTUNDCONFIG)
	or die("Could not open " . TMVTUNDCONFIG . ": $!");

    print(CONF
	  "options {\n".
	  "  ifconfig    /sbin/ifconfig;\n".
	  "  route       /sbin/route;\n".
	  "}\n".
	  "\n".
	  "default {\n".
	  "  persist     yes;\n".
	  "  stat        yes;\n".
	  "  keepalive   yes;\n".
	  "  type        ether;\n".
	  "}\n".
	  "\n");
    
    $pat  = q(TUNNEL=([-\w.]+) ISSERVER=(\d) PEERIP=([-\w.]+) );
    $pat .= q(PEERPORT=(\d+) PASSWORD=([-\w.]+) );
    $pat .= q(ENCRYPT=(\d) COMPRESS=(\d) INET=([-\w.]+) );
    $pat .= q(MASK=([-\w.]+) PROTO=([-\w.]+));

    foreach my $tunnel (@tunnels) {
	if ($tunnel =~ /$pat/) {
	    #
	    # The following is specific to vtund!
	    #
	    my $name     = $1;
	    my $isserver = $2;
	    my $peeraddr = $3;
	    my $peerport = $4;
	    my $password = $5;
	    my $encrypt  = ($6 ? "yes" : "no");
	    my $compress = ($7 ? "yes" : "no");
	    my $inetip   = $8;
	    my $mask     = $9;
	    my $proto    = $10;
	    my $routearg = inet_ntoa(inet_aton($inetip) & inet_aton($mask));

	    my $cmd = "$VTUND -n -P $peerport -f ". TMVTUNDCONFIG;

	    if ($isserver) {
		if (!$didserver) {
		    print RC
			"$cmd -s >$LOGDIR/vtund-${pid}-${eid}.debug 2>&1 &\n";
		    $didserver = 1;
		}
	    }
	    else {
		print RC "$cmd $name $peeraddr ".
		    " >$LOGDIR/vtun-${pid}-${eid}-${name}.debug 2>&1 &\n";
	    }
	    #
	    # Sheesh, vtund fails if it sees "//" in a path. 
	    #
	    my $config = TMROUTECONFIG;
	    $config =~ s/\/\//\//g;
	    my $rtabopt= "";
	    if (defined($rtabid)) {
		$rtabopt = "    ifconfig \"%% rtabid $rtabid\";\n";
	    }
	    
	    print(CONF
		  "$name {\n".
		  "  password      $password;\n".
		  "  compress      $compress;\n".
		  "  encrypt       $encrypt;\n".
		  "  proto         $proto;\n".
		  "\n".
		  "  up {\n".
		  "    # Connection is Up\n".
		  $rtabopt .
		  "    ifconfig \"%% $inetip netmask $mask\";\n".
		  "    program " . $config . " \"$routearg up\" wait;\n".
		  "  };\n".
		  "  down {\n".
		  "    # Connection is Down\n".
		  "    ifconfig \"%% down\";\n".
		  "    program " . $config . " \"$routearg down\" wait;\n".
		  "  };\n".
		  "}\n\n");
	}
	else {
	    warn "*** WARNING: Bad tunnel line: $tunnel";
	}
    }

    close(CONF);
    close(RC);
    chmod(0755, TMTUNNELCONFIG);
    return 0;
}

#
# All we do is store it away in the file. This makes it avail later.
# 
sub dojailconfig()
{
    my @configstrings;

    $TM = OPENTMCC(TMCCCMD_JAILCONFIG);
    while (<$TM>) {
	push(@configstrings, $_);
    }
    CLOSETMCC($TM);

    if (! @configstrings) {
	return 0;
    }

    open(RC, ">" . TMJAILCONFIG)
	or die("Could not open " . TMJAILCONFIG . ": $!");

    foreach my $str (@configstrings) {
	print RC $str;
    }
    close(RC);
    chmod(0755, TMJAILCONFIG);
    return 0;
}

#
# Get the sync server config. 
# 
sub dosyncserver()
{
    my @configstrings;
    my $syncserver;
    my $startserver;

    $TM = OPENTMCC(TMCCCMD_SYNCSERVER);
    while (<$TM>) {
	push(@configstrings, $_);
    }
    CLOSETMCC($TM);

    if (! @configstrings) {
	return 0;
    }

    #
    # There should be just one string. Ignore anything else.
    #
    if ($configstrings[0] =~
	/SYNCSERVER SERVER=\'([-\w\.]*)\' ISSERVER=(\d)/) {

	$syncserver = $1;
	$startserver = $2
    }
    else {
	warn "*** WARNING: Bad syncserver line: $_";
	return 1;
    }

    #
    # Write a file so the client program knows where the server is.
    #
    if (system("echo '$syncserver' > ". TMSYNCSERVER)) {
	warn "*** WARNING: Could not write " . TMSYNCSERVER . "\n";
	return 1;
    }

    #
    # If we are the sync server, arrange to start it up.
    #
    return 0
	if (! $startserver);

    open(RC, ">" . TMRCSYNCSERVER)
	or die("Could not open " . TMRCSYNCSERVER . ": $!");

    print RC "#!/bin/sh\n";
    print RC "$BINDIR/emulab-syncd -d >$LOGDIR/syncserver.debug 2>&1 &\n";

    close(RC);
    chmod(0755, TMRCSYNCSERVER);
    return 0;
}

#
# Plab configuration.  Currently sets up sshd and the DNS resolver
# 
sub doplabconfig()
{
    my $plabconfig;

    my $TM = OPENTMCC(TMCCCMD_PLABCONFIG);
    $_ = <$TM>;
    if (defined($_)) {
	$plabconfig = $_;
    }
    CLOSETMCC($TM);

    if (! $plabconfig) {
	return 0;
    }

    open(RC, ">" . TMPLABCONFIG)
	or die("Could not open " . TMPLABCONFIG . ": $!");

    if ($plabconfig =~ /SSHDPORT=(\d+)/) {
	my $sshdport = $1;

	print RC "#!/bin/sh\n";

	# Note that it's important to never directly modify the config
	# file unless it's already been recreated due to vserver's
	# immutable-except-delete flag
	print(RC
	      "function setconfigopt()\n".
	      "{\n".
	      "    file=\$1\n".
	      "    opt=\$2\n".
	      "    value=\$3\n".
	      "    if ( ! grep -q \"^\$opt[ \t]*\$value\\\$\" \$file ); then\n".
	      "        sed -e \"s/^\\(\$opt[ \t]*.*\\)/#\\1/\" < \$file".
	      " > \$file.tmp\n".
	      "        mv -f \$file.tmp \$file\n".
	      "        echo \$opt \$value >> \$file;\n".
	      "    fi\n".
	      "}\n\n");

	# Make it look like it's in Emulab domain
	# XXX This shouldn't be hardcoded
	print RC "setconfigopt /etc/resolv.conf domain emulab.net\n";
	print RC "setconfigopt /etc/resolv.conf search emulab.net\n\n";

	# No SSH X11 Forwarding
	print RC "setconfigopt /etc/ssh/sshd_config X11Forwarding no\n";

	# Set SSH port
	print RC "setconfigopt /etc/ssh/sshd_config Port $sshdport\n";

	# Start sshd
	print RC "/etc/init.d/sshd restart\n";
    }
    else {
	warn "*** WARNING: Bad plab line: $_";
    }

    close(RC);
    chmod(0755, TMPLABCONFIG);

    return 0;
}

#
# Boot Startup code. This is invoked from the setup OS dependent script,
# and this fires up all the stuff above.
#
sub bootsetup()
{
    my $oldpid;
    
    print STDOUT "Checking Testbed reservation status ... \n";

    #
    # Watch for a change in project membership. This is not supposed to
    # happen, but it turns out that it does when reloading. Its good to
    # check for this anyway just in case. A little tricky though.
    #
    if (-e TMNICKNAME) {
	($oldpid) = check_nickname();
    }
    
    #
    # Check allocation. Exit now if not allocated.
    #
    if (! check_status()) {
	print STDOUT "  Free!\n";
	cleanup_node(1);
	return 0;
    }
    #
    # Project Change? 
    #
    if (defined($oldpid) && ($oldpid ne $pid)) {
	print STDOUT "  Old Project: $oldpid\n";
	# This removes the nickname file, so do it again.
	cleanup_node(1);
	check_status();
    }
    else {
	#
	# Cleanup node. Flag indicates to gently clean ...
	# 
	cleanup_node(0);
    }
    print STDOUT "  Allocated! $pid/$eid/$vname\n";

    #
    # Mount the project and user directories and symlink SFS "mounted"
    # directories
    #
    print STDOUT "Mounting project and home directories ... \n";
    domounts();

    #
    # Do account stuff.
    # 
    print STDOUT "Checking Testbed group/user configuration ... \n";
    doaccounts();

    if (! MFS()) {
	#
	# Okay, lets find out about interfaces.
	#
	print STDOUT "Checking Testbed interface configuration ... \n";
	doifconfig();

        #
        # Do tunnels
        # 
        print STDOUT "Checking Testbed tunnel configuration ... \n";
        dotunnels();

	#
	# Host names configuration (/etc/hosts). 
	#
	print STDOUT "Checking Testbed hostnames configuration ... \n";
	dohostnames();

	#
	# Init the sync server.
	# 
	print STDOUT "Checking Testbed sync server setup ...\n";
	dosyncserver();
	
	#
	# Router Configuration.
	#
	print STDOUT "Checking Testbed routing configuration ... \n";
	dorouterconfig();

	#
	# Traffic generator Configuration.
	#
	print STDOUT "Checking Testbed traffic generation configuration ...\n";
	dotrafficconfig();

	#
	# RPMS
	# 
	print STDOUT "Checking Testbed RPM configuration ... \n";
	dorpms();

	#
	# Tar Balls
	# 
	print STDOUT "Checking Testbed Tarball configuration ... \n";
	dotarballs();

	#
	# Program agents
	# 
	print STDOUT "Checking Testbed program agent configuration ... \n";
	doprogagent();
    }

    #
    # Experiment startup Command.
    #
    print STDOUT "Checking Testbed Experiment Startup Command ... \n";
    dostartupcmd();

    #
    # OS specific stuff
    #
    os_setup();

    return 0;
}

#
# This happens inside a jail. 
#
sub jailsetup()
{
    #
    # Currently, we rely on the outer environment to set our vnodeid
    # into the environment so we can get it! See mkjail.pl.
    #
    my $vid = $ENV{'TMCCVNODEID'};
    
    if ($vid =~ /^([-\w]+)$/) {
	$vid = $1;
    }
    else {
	die("Bad data in vnodeid: $vid");
    }

    #
    # Set global vnodeid for tmcc commands. Must be before all the rest!
    #
    $vnodeid  = $vid;
    $injail   = 1;

    #
    # Create a file inside so that libsetup inside the jail knows its
    # inside a jail and what its ID is. 
    #
    system("echo '$vnodeid' > " . TMJAILNAME());
    
    #
    # Do account stuff.
    #
    {
	print STDOUT "Checking Testbed reservation status ... \n";
	if (! check_status()) {
	    print STDOUT "  Free!\n";
	    return 0;
	}
	print STDOUT "  Allocated! $pid/$eid/$vname\n";

	#
	# XXX just generates interface list for routing config
	#
	print STDOUT "Checking Testbed interface configuration ... \n";
	doifconfig();

	#
	# Setup SFS hostid.
	#
	if ($USESFS) {
	    print STDOUT "Setting up for SFS ... \n";
	    dosfshostid();
	}

#	print STDOUT "Mounting project and home directories ... \n";
#	domounts();

	print STDOUT "Checking Testbed jail configuration ...\n";
	dojailconfig();
	
	print STDOUT "Checking Testbed hostnames configuration ... \n";
	dohostnames();

	if (REMOTE()) {
	    # Locally, the password/group files initially comes from
	    # outside the jail. 
	    print STDOUT "Checking Testbed group/user configuration ... \n";
	    doaccounts();
	}

	print STDOUT "Checking Testbed sync server setup ...\n";
	dosyncserver();
	
	print STDOUT "Checking Testbed RPM configuration ... \n";
	dorpms();

	print STDOUT "Checking Testbed Tarball configuration ... \n";
	dotarballs();

	print STDOUT "Checking Testbed routing configuration ... \n";
	dorouterconfig();

	print STDOUT "Checking Testbed traffic generation configuration ...\n";
	dotrafficconfig();

	print STDOUT "Checking Testbed program agent configuration ... \n";
	doprogagent();

	print STDOUT "Checking Testbed Experiment Startup Command ... \n";
	dostartupcmd();
    }

    return $vnodeid;
}

#
# Remote Node virtual node jail setup. This happens outside the jailed
# env.
#
sub vnodejailsetup($)
{
    my ($vid) = @_;

    #
    # Set global vnodeid for tmcc commands.
    #
    $vnodeid  = $vid;

    #
    # This is the directory where the rc files go.
    #
    if (! -e JAILDIR()) {
	die("*** $0:\n".
	    "    No such directory: " . JAILDIR() . "\n");
    }

    # Do not bother if somehow got released.
    if (! check_status()) {
	print "Node is free!\n";
	return undef;
    }

    #
    # Create /local directories for users. 
    #
    if (! -e LOCALROOTFS()) {
	os_mkdir(LOCALROOTFS(), "0755");
    }
    if (-e LOCALROOTFS()) {
	my $piddir = LOCALROOTFS() . "/$pid";
	my $eiddir = LOCALROOTFS() . "/$pid/$eid";
	my $viddir = LOCALROOTFS() . "/$pid/$vid";

	if (! -e $piddir) {
	    mkdir($piddir, 0777) or
		die("*** $0:\n".
		    "    mkdir filed - $piddir: $!\n");
	}
	if (! -e $eiddir) {
	    mkdir($eiddir, 0777) or
		die("*** $0:\n".
		    "    mkdir filed - $eiddir: $!\n");
	}
	if (! -e $viddir) {
	    mkdir($viddir, 0775) or
		die("*** $0:\n".
		    "    mkdir filed - $viddir: $!\n");
	}
	chmod(0777, $piddir);
	chmod(0777, $eiddir);
	chmod(0775, $viddir);
    }

    #
    # Get jail config.
    #
    print STDOUT "Checking Testbed jail configuration ...\n";
    dojailconfig();

    return ($pid, $eid, $vname);
}    

#
# This happens inside a Plab vserver.
#
sub plabsetup()
{
    #
    # vnodeid will either be found in BEGIN block or will be passed to
    # vnodeplabsetup, so it doesn't need to be found here
    #

    #
    # Do account stuff.
    #
    {
	print STDOUT "Checking Testbed reservation status ... \n";
	if (! check_status()) {
	    print STDOUT "  Free!\n";
	    return 0;
	}
	print STDOUT "  Allocated! $pid/$eid/$vname\n";

	#
	# Setup SFS hostid.
	#
	if ($USESFS) {
	    print STDOUT "Setting up for SFS ... \n";
	    dosfshostid();
	}

#	print STDOUT "Mounting project and home directories ... \n";
#	domounts();

	print STDOUT "Checking Testbed plab configuration ...\n";
	doplabconfig();

	print STDOUT "Checking Testbed hostnames configuration ... \n";
	dohostnames();

	print STDOUT "Checking Testbed group/user configuration ... \n";
	doaccounts();

	print STDOUT "Checking Testbed RPM configuration ... \n";
	dorpms();

	print STDOUT "Checking Testbed Tarball configuration ... \n";
	dotarballs();

# 	print STDOUT "Checking Testbed routing configuration ... \n";
# 	dorouterconfig();

# 	print STDOUT "Checking Testbed traffic generation configuration ...\n";
# 	dotrafficconfig();

# 	print STDOUT "Checking Testbed program agent configuration ... \n";
# 	doprogagent();

	print STDOUT "Checking Testbed Experiment Startup Command ... \n";
	dostartupcmd();
    }

    return $vnodeid;
}

#
# Remote node virtual node Plab setup.  This happens inside the vserver
# environment (because on Plab you can't escape)
#
sub vnodeplabsetup($)
{
    my ($vid) = @_;

    #
    # Set global vnodeid for tmcc commands.
    #
    $vnodeid  = $vid;
    $inplab   = 1;

    # Do not bother if somehow got released.
    if (! check_status()) {
	print "Node is free!\n";
	return undef;
    }
    
    #
    # Create a file so that libsetup knows it's inside Plab and what
    # its ID is. 
    #
    system("echo '$vnodeid' > $BOOTDIR/plabname");
    
    # XXX Anything else to do?
    
    return ($pid, $eid, $vname);
}

#
# IXP config. This happens on the outside since there is currently no
# inside setup (until there is a reasonable complete environment).
#
sub ixpsetup($)
{
    my ($vid) = @_;

    #
    # Set global vnodeid for tmcc commands.
    #
    $vnodeid  = $vid;

    #
    # Config files go here. 
    #
    if (! -e CONFDIR()) {
	die("*** $0:\n".
	    "    No such directory: " . CONFDIR() . "\n");
    }

    # Do not bother if somehow got released.
    if (! check_status()) {
	print "Node is free!\n";
	return undef;
    }
    $inixp    = 1;

    #
    # Different approach for IXPs. The ixp setup code will call the routines
    # directly. 
    # 

    return ($pid, $eid, $vname);
}

#
# Report startupcmd status back to the TMCC. Called by the runstartup
# script. 
#
sub startcmdstatus($)
{
    my($status) = @_;

    RUNTMCC(TMCCCMD_STARTSTAT, "$status");
    return 0;
}

#
# Install deltas is deprecated.
#
sub install_deltas ()
{
    #
    # No longer supported, but be sure to return 0.
    #
    print "*** WARNING: No longer supporting testbed deltas!\n";
    return 0;
}

#
# Early on in the boot, we want to reset the hostname. This gets the
# nickname and returns it. 
#
# This is going to get invoked very early in the boot process, before the
# normal client initialization. So we have to do a few things to make
# things are consistent. 
#
sub whatsmynickname()
{
    #
    # Check allocation. Exit now if not allocated.
    #
    if (! check_status()) {
	return 0;
    }

    return "$vname.$eid.$pid";
}

#
# Put ourselves into the background, directing output to the log file.
# The caller provides the logfile name, which should have been created
# with mktemp, just to be safe. Returns the usual return of fork. 
#
# usage int TBBackGround(char *filename).
# 
sub TBBackGround($)
{
    my($logname) = @_;
    
    my $mypid = fork();
    if ($mypid) {
	return $mypid;
    }
    select(undef, undef, undef, 0.2);
    
    #
    # We have to disconnect from the caller by redirecting both STDIN and
    # STDOUT away from the pipe. Otherwise the caller (the web server) will
    # continue to wait even though the parent has exited. 
    #
    open(STDIN, "< /dev/null") or
	die("opening /dev/null for STDIN: $!");

    # Note different taint check (allow /).
    if ($logname =~ /^([-\@\w.\/]+)$/) {
	$logname = $1;
    } else {
	die("Bad data in logfile name: $logname\n");
    }

    open(STDERR, ">> $logname") or die("opening $logname for STDERR: $!");
    open(STDOUT, ">> $logname") or die("opening $logname for STDOUT: $!");

    return 0;
}

#
# Fork a process to exec a command. Return the pid to wait on.
# 
sub TBForkCmd($) {
    my ($cmd) = @_;
    my($mypid);

    $mypid = fork();
    if ($mypid) {
	return $mypid;
    }

    system($cmd);
    exit($? >> 8);
}

#
# Generate ssh authorized_keys files. Either protocol 1 or 2.
# Returns 0 on success, -1 on failure.
#
sub TBNewsshKeyfile($$$$$)
{
    my ($sshdir, $uid, $gid, $protocol, @pkeys) = @_;
    my $keyfile = "$sshdir/authorized_keys";
	
    if (! -e $sshdir) {
	if (! mkdir($sshdir, 0700)) {
	    warn("*** WARNING: Could not mkdir $sshdir: $!\n");
	    return -1;
	}
	if (!chown($uid, $gid, $sshdir)) {
	    warn("*** WARNING: Could not chown $sshdir: $!\n");
	    return -1;
	}
    }
    if ($protocol == 2) {
	$keyfile .= "2";
    }

    if (!open(AUTHKEYS, "> ${keyfile}.new")) {
	warn("*** WARNING: Could not open ${keyfile}.new: $!\n");
	return -1;
    }
    print AUTHKEYS "#\n";
    print AUTHKEYS "# DO NOT EDIT! This file auto generated by ".
	"Emulab.Net account software.\n";
    print AUTHKEYS "#\n";
    print AUTHKEYS "# Please use the web interface to edit your ".
	"public key list.\n";
    print AUTHKEYS "#\n";
    
    foreach my $key (@pkeys) {
	print AUTHKEYS "$key\n";
    }
    close(AUTHKEYS);

    if (!chown($uid, $gid, "${keyfile}.new")) {
	warn("*** WARNING: Could not chown ${keyfile}.new: $!\n");
	return -1;
    }
    if (!chmod(0600, "${keyfile}.new")) {
	warn("*** WARNING: Could not chmod ${keyfile}.new: $!\n");
	return -1;
    }
    if (-e "${keyfile}") {
	if (system("cp -p -f ${keyfile} ${keyfile}.old")) {
	    warn("*** Could not save off ${keyfile}: $!\n");
	    return -1;
	}
	if (!chown($uid, $gid, "${keyfile}.old")) {
	    warn("*** Could not chown ${keyfile}.old: $!\n");
	}
	if (!chmod(0600, "${keyfile}.old")) {
	    warn("*** Could not chmod ${keyfile}.old: $!\n");
	}
    }
    if (system("mv -f ${keyfile}.new ${keyfile}")) {
	warn("*** Could not mv ${keyfile} to ${keyfile}.new: $!\n");
    }
    return 0;
}

1;
