#!/usr/bin/perl -wT

#
# Common routines and constants for the client bootime setup stuff.
#
package libsetup;
use Exporter;
@ISA = "Exporter";
@EXPORT =
    qw ( libsetup_init inform_reboot cleanup_node check_status
	 create_nicknames doifconfig dohostnames
	 doaccounts dorpms dotarballs dostartupcmd install_deltas
	 bootsetup nodeupdate startcmdstatus whatsmynickname

	 OPENTMCC RUNTMCC

	 TMCC TMIFC TMDELAY TMRPM TMTARBALLS TMHOSTS
	 TMNICKNAME HOSTSFILE TMSTARTUPCMD FINDIF

	 TMCCCMD_REBOOT TMCCCMD_STATUS TMCCCMD_IFC TMCCCMD_ACCT TMCCCMD_DELAY
	 TMCCCMD_HOSTS TMCCCMD_RPM TMCCCMD_TARBALL TMCCCMD_STARTUP
	 TMCCCMD_DELTA TMCCCMD_STARTSTAT TMCCCMD_READY

       );

# Must come after package declaration!
use English;

#
# This is the home of the setup library on the client machine. The including
# program has to tell us this by calling the init routine below. For example,
# it is /etc/testbed on FreeBSD and /etc/rc.d/testbed on Linux.
#
my $SETUPDIR;

sub libsetup_init($)
{
    my($path) = @_;

    $SETUPDIR = $path;
}

#
# This "local" library provides the OS dependent part. Must load this after
# defining the above function cause the local library invokes it to set the
# $SETUPDIR
#
use liblocsetup;

#
# These are the paths of various files and scripts that are part of the
# setup library.
#
sub TMCC()		{ "$SETUPDIR/tmcc"; }
sub TMIFC()		{ "$SETUPDIR/rc.ifc"; }
sub TMRPM()		{ "$SETUPDIR/rc.rpm"; }
sub TMTARBALLS()	{ "$SETUPDIR/rc.tarballs"; }
sub TMSTARTUPCMD()	{ "$SETUPDIR/startupcmd"; }
sub TMHOSTS()		{ "$SETUPDIR/hosts"; }
sub TMNICKNAME()	{ "$SETUPDIR/nickname"; }
sub FINDIF()		{ "$SETUPDIR/findif"; }
sub HOSTSFILE()		{ "/etc/hosts"; }
sub TMMOUNTDB()		{ "$SETUPDIR/mountdb"; }

#
# These are the TMCC commands.
#
sub TMCCCMD_REBOOT()	{ "reboot"; }
sub TMCCCMD_STATUS()	{ "status"; }
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

#
# Some things never change.
# 
my $TARINSTALL  = "/usr/local/bin/install-tarfile %s %s";
my $DELTAINSTALL= "/usr/local/bin/install-delta %s";

#
# This is a debugging thing for my home network.
# 
#my $NODE	= "REDIRECT=155.101.132.101";
$NODE		= "";

# Locals
my $pid	     = "";
my $eid      = "";
my $vname    = "";

#
# Open a TMCC connection and return the "stream pointer". Caller is
# responsible for closing the stream and checking return value.
#
# usage: OPENTMCC(char *command, char *args)
#
sub OPENTMCC($;$)
{
    my($cmd, $args) = @_;
    local *TM;

    if (!defined($args)) {
	$args = "";
    }
    my $foo = sprintf("%s %s %s %s |", TMCC, $NODE, $cmd, $args);

    open(TM, $foo)
	or die "Cannot start $TMCC: $!";

    return (*TM);
}

#
# Run a TMCC command with the provided arguments.
#
# usage: RUNTMCC(char *command, char *args)
#
sub RUNTMCC($;$)
{
    my($cmd, $args) = @_;
    my($TM);

    if (!defined($args)) {
	$args = "";
    }
    $TM = OPENTMCC($cmd, $args);

    close($TM)
	or die $? ? "TMCC exited with status $?" : "Error closing pipe: $!";
    
    return 0;
}

#
# Inform the master we have rebooted.
#
sub inform_reboot()
{
    RUNTMCC(TMCCCMD_REBOOT);
    return 0;
}

#
# Reset to a moderately clean state.
#
sub cleanup_node () {
    print STDOUT "Cleaning node; removing configuration files ...\n";
    unlink TMIFC, TMRPM, TMSTARTUPCMD, TMNICKNAME, TMTARBALLS;
    unlink TMMOUNTDB . ".db";

    printf STDOUT "Resetting %s file\n", HOSTSFILE;
    if (system($CP, "-f", TMHOSTS, HOSTSFILE) != 0) {
	printf STDERR "Could not copy default %s into place: $!\n", HOSTSFILE;
	exit(1);
    }

    return os_cleanup_node();
}

#
# Check node allocation.
#
# Returns 0 if node is free. Returns list (pid/eid/vname) if allocated.
#
sub check_status ()
{
    my $TM;
    
    $TM = OPENTMCC(TMCCCMD_STATUS);
    $_  = <$TM>;
    close($TM);

    if ($_ =~ /^FREE/) {
	return 0;
    }
    
    if ($_ =~ /ALLOCATED=([-\@\w.]*)\/([-\@\w.]*) NICKNAME=([-\@\w.]*)/) {
	$pid   = $1;
	$eid   = $2;
	$vname = $3;
    }
    else {
	warn "*** WARNING: Error getting reservation status\n";
	return 0;
    }
    return ($pid, $eid, $vname);
}

#
# Stick our nickname in a file in case someone wants it.
#
sub create_nicknames()
{
    open(NICK, ">" . TMNICKNAME)
	or die("Could not open nickname file: $!");
    print NICK "$vname.$eid.$pid\n";
    close(NICK);

    return 0;
}

#
# Process mount directives from TMCD. We keep track of all the mounts we
# have added in here so that we delete just the accounts we added, when
# project membership changes. Same goes for project directories on shared
# nodes. We use a simple perl DB for that.
#
sub domounts()
{
    my $TM;
    my %MDB;
    my %mounts;
    my %deletes;
    
    $TM = OPENTMCC(TMCCCMD_MOUNTS);

    while (<$TM>) {
	if ($_ =~ /REMOTE=([-:\@\w\.\/]+) LOCAL=([-\@\w\.\/]+)/) {
	    $mounts{$1} = $2;
	}
    }

    dbmopen(%MDB, TMMOUNTDB, 0660);
    
    #
    # First mount all the mounts we are told to. For each one that is not
    # currently mounted, and can be mounted, add it to the DB.
    # 
    while (($remote, $local) = each %mounts) {
	if (system("$MOUNT | $EGREP ' $local '") == 0) {
	    $MDB{$remote} = $local;
	    next;
	}

	if (! -e $local) {
	    if (! mkdir($local, 0770)) {
		warn "*** WARNING: Could not make directory $local: $!\n";
		next;
	    }
	}
	
	print STDOUT "  Mounting $remote on $local\n";
	if (system("$MOUNT $remote $local")) {
	    warn "*** WARNING: Could not $MOUNT $remote on $local: $!\n";
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

	if (system("$MOUNT | $EGREP ' $local '")) {
	    $deletes{$remote} = $local;
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

    return 0;
}

#
# Do interface configuration.    
# Write a file of ifconfig lines, which will get executed.
#
sub doifconfig ()
{
    my $TM;
    
    $TM = OPENTMCC(TMCCCMD_IFC);

    #
    # Open a connection to the TMCD, and then open a local file into which
    # we write ifconfig commands (as a shell script).
    # 
    open(IFC, ">" . TMIFC)
	or die("Could not open " . TMIFC . ": $!");
    print IFC "#!/bin/sh\n";
    
    while (<$TM>) {
	if ($_ =~ /INTERFACE=(\d*) INET=([0-9.]*) MASK=([0-9.]*) MAC=(\w*)/) {
	    my $iface;

	    if ($iface = findiface($4)) {
		my $ifline = os_ifconfig_line($iface, $2, $3);
		    
		print STDOUT "  $ifline\n";
		print IFC "$ifline\n";
	    }
	    else {
		warn "*** WARNING: Bad MAC: $4\n";
	    }
	}
	else {
	    warn "*** WARNING: Bad ifconfig line: $_";
	}
    }
    close($TM);
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
# Host names configuration (/etc/hosts). 
#
sub dohostnames ()
{
    my $TM;

    #
    # Start with fresh copy, since the hosts files is potentially updated
    # after the node boots via the update command.
    # 
    if (system($CP, "-f", TMHOSTS, HOSTSFILE) != 0) {
	printf STDERR "Could not copy default %s into place: $!\n", HOSTSFILE;
	return 1;
    }
    
    $TM = OPENTMCC(TMCCCMD_HOSTS);

    open(HOSTS, ">>" . HOSTSFILE)
	or die("Could not open $HOSTSFILE: $!");

    #
    # Now convert each hostname into hosts file representation and write
    # it to the hosts file.
    # 
    while (<$TM>) {
	if ($_ =~
	    /NAME=([-\@\w.]+) LINK=([0-9]*) IP=([0-9.]*) ALIAS=([-\@\w.]*)/) {
	    my $hostline = os_etchosts_line($1, $2, $3, $4);
	    
	    print STDOUT "  $hostline\n";
	    print HOSTS  "$hostline\n";
	}
	else {
	    warn "*** WARNING: Bad hosts line: $_";
	}
    }
    close($TM);
    close(HOSTS);

    return 0;
}

sub doaccounts ()
{
    my %oldaccounts = ();
    my %newaccounts = ();

    my $TM = OPENTMCC(TMCCCMD_ACCT);

    #
    # The strategy here is to grab the list of default accounts from our
    # stub password file, and then add to that the list of accounts that
    # are supposed to be on this machine as told to us by the TMCD. Then,
    # go through the existing accounts in the real password file, and add
    # the ones that are not there and remove the ones that should not be
    # there.
    #
    # Removing groups is not neccessary, so just process those as we get
    # from the TMCD.
    # 
    while (<$TM>) {
	if ($_ =~ /^ADDGROUP NAME=([-\@\w.]+) GID=([0-9]+)/) {
	    print STDOUT "  Group: $1/$2\n";

	    $group = $1;
	    $gid   = $2;

	    ($exists) = getgrgid($gid);
	    if ($exists) {
		next;
	    }
	
	    if (os_groupadd($group, $gid)) {
		warn "*** WARNING: Error adding new group $1/$2\n";
	    }
	    next;
	}
	elsif ($_ =~ /^ADDUSER LOGIN=([0-9a-z]+)/) {
	    #
	    # Account info goes in the hash table.
	    # 
	    $newaccounts{$1} = $_;
	    next;
	}
	else {
	    warn "*** WARNING: Bad accounts line: $_";
	}
    }
    close($TM);

    #
    # All we need to know about the stub accounts is which ones should exist
    # once we are done. Add those to the hash table we created above, but
    # only if not in the list we got from the TMCD. This allows us to
    # override the default accounts with new account info from the TMCD.
    #
    open(PASSWD, $TMPASSWD)
	or die "Cannot open $TMPASSWD: $!";

    while (<PASSWD>) {
	if ($_ =~ /^([0-9a-z]+):/) {
	    if (! defined($newaccounts{$1})) {
		$newaccounts{$1} = "OLDUSER LOGIN=$1";
	    }
	}
    }
    close(PASSWD);

    #
    # Pick up the list of current accounts on this machine. Easier if
    # I have both lists in hand as hash tables. Also note that changing
    # the account list while doing a getpwent() loop can lead to unusual
    # things happening. 
    #
    while (my $login = getpwent()) {
	$oldaccounts{$login} = $login;
    }

    #
    # First off, lets delete accounts that are no longer supposed to be here.
    # We unmount the homedirs too (or try to!).
    #
    foreach my $login (keys %oldaccounts) {
	if (!defined($newaccounts{$login})) {

	    print "  Deleting User: $login\n";
	    
	    if (os_userdel($login) != 0) {
		warn "*** WARNING: Error deleting user $login\n";
	    }
	}
    }

    #
    # Now do the new accounts. We go through the entire list of accounts
    # we got. This includes the list from the TMCD, and the list we get
    # locally from the stub password file. We leave the stub accounts alone
    # since they are in the list to prevent deletion. 
    #
    foreach my $login (keys %newaccounts) {
	my $info = $newaccounts{$login};
	
	if ($info =~
	    /^ADDUSER LOGIN=([0-9a-z]+) PSWD=([^:]+) UID=(\d+) GID=(.*) ROOT=(\d) NAME="(.*)" HOMEDIR=(.*) GLIST=(.*)/)
	{
	    $pswd  = $2;
	    $uid   = $3;
	    $gid   = $4;
	    $root  = $5;
	    $name  = $6;
	    $hdir  = $7;
	    $glist = $8;
	    if ( $name =~ /^(([^:]+$|^))$/ ) {
		$name = $1;
	    }
	    print STDOUT "  User: $login/$uid/$gid/$root/$name/$hdir/$glist\n";

	    ($exists) = getpwuid($uid);
	    if ($exists) {
		os_usermod($login, $gid, "$glist", $root);
		next;
	    }

	    if (os_useradd($login, $uid, $gid, $pswd, 
			   "$glist", $hdir, $name, $root)) {
		warn "*** WARNING: Error adding new user $login\n";
		next;
	    }
	    next;
	}
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
    close($TM);

    if (! @rpms) {
	return 0;
    }
    
    open(RPM, ">" . TMRPM)
	or die("Could not open " . TMRPM . ": $!");
    print RPM "#!/bin/sh\n";
    
    foreach my $rpm (@rpms) {
	if ($rpm =~ /RPM=([-\@\w.\/]+)/) {
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
    my @tarballs = ();

    my $TM = OPENTMCC(TMCCCMD_TARBALL);
    while (<$TM>) {
	push(@tarballs, $_);
    }
    close($TM);

    if (! @tarballs) {
	return 0;
    }
    
    open(TARBALL, ">" . TMTARBALLS)
	or die("Could not open " . TMTARBALLS . ": $!");
    print TARBALL "#!/bin/sh\n";
    
    foreach my $tarball (@tarballs) {
	if ($tarball =~ /DIR=([-\@\w.\/]+)\s+TARBALL=([-\@\w.\/]+)/) {
	    my $tbline = sprintf($TARINSTALL, $1, $2);
		    
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
    close($TM);

    if (! $startupcmd) {
	return 0;
    }
    
    open(RUN, ">" . TMSTARTUPCMD)
	or die("Could not open $TMSTARTUPCMD: $!");
    
    if ($startupcmd =~ /CMD=(\'[-\@\w.\/ ]+\') UID=([0-9a-z]+)/) {
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
# Boot Startup code. This is invoked from the setup OS dependent script,
# and this fires up all the stuff above.
#
sub bootsetup()
{
    #
    # First clean up the node.
    #
    cleanup_node();

    #
    # Inform the master that we have rebooted.
    #
    inform_reboot();

    #
    # Check allocation. Exit now if not allocated.
    #
    print STDOUT "Checking Testbed reservation status ... \n";
    if (! check_status()) {
	print STDOUT "  Free!\n";
	return 0;
    }
    print STDOUT "  Allocated! $pid/$eid/$vname\n";

    #
    # Setup a nicknames file. 
    #
    create_nicknames();

    #
    # Mount the project and user directories
    #
    print STDOUT "Mounting project and home directories ... \n";
    domounts();

    #
    # Okay, lets find out about interfaces.
    #
    print STDOUT "Checking Testbed interface configuration ... \n";
    doifconfig();

    #
    # Host names configuration (/etc/hosts). 
    #
    print STDOUT "Checking Testbed hostnames configuration ... \n";
    dohostnames();

    #
    # Do account stuff.
    # 
    print STDOUT "Checking Testbed group/user configuration ... \n";
    doaccounts();

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
# These are additional support routines for other setup scripts.
#
#
# Node update. This gets fired off after reboot to update accounts,
# mounts, etc. Its the start of shared node support. Quite rough at
# the moment. 
#
sub nodeupdate()
{
    #
    # Check allocation. If the node is now free, then do a cleanup
    # to reset the password files. The node should have its disk
    # reloaded to be safe, at the very least a reboot, but thats for
    # the future. We also need to kill processes belonging to people
    # whose accounts have been killed. Need to check the atq also for
    # queued commands.
    #
    if (! check_status()) {
	print "Node is free. Cleaning up password and group files.\n";
	cleanup_node();
	return 0;
    }

    #
    # Mount the project and user directories
    #
    print STDOUT "Mounting project and home directories ... \n";
    domounts();

    #
    # Host names configuration (/etc/hosts). 
    #
    print STDOUT "Checking Testbed hostnames configuration ... \n";
    dohostnames();

    #
    # Do account stuff.
    # 
    print STDOUT "Checking Testbed group/user configuration ... \n";
    doaccounts();

    return 0;
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
# Install deltas. Return 0 if nothing happened. Return -1 if there was
# an error. Return 1 if deltas installed, which tells the caller to reboot.
#
# This is going to get invoked very early in the boot process, possibly
# before the normal client initialization. So we have to do a few things
# to make things are consistent. 
#
sub install_deltas ()
{
    my @deltas = ();
    my $reboot = 0;

    #
    # Inform the master that we have rebooted.
    #
    inform_reboot();

    #
    # Check allocation. Exit now if not allocated.
    #
    if (! check_status()) {
	return 0;
    }

    #
    # Now do the actual delta install.
    # 
    my $TM = OPENTMCC(TMCCCMD_DELTA);
    while (<$TM>) {
	push(@deltas, $_);
    }
    close($TM);

    #
    # No deltas. Just exit and let the boot continue.
    #
    if (! @deltas) {
	return 0;
    }

    #
    # Mount the project directory.
    #
    domounts();

    #
    # Install all the deltas, and hope they all install okay. We reboot
    # if any one does an actual install (they may already be installed).
    # If any fails, then give up.
    # 
    foreach $delta (@deltas) {
	if ($delta =~ /DELTA=([-\@\w.\/]+)/) {
	    print STDOUT  "Installing DELTA $1 ...\n";

	    system(sprintf($DELTAINSTALL, $1));
	    my $status = $? >> 8;
	    if ($status == 0) {
		$reboot = 1;
	    }
	    else {
		if ($status < 0) {
		    print STDOUT "Failed to install DELTA $1. Help!\n";
		    return -1;
		}
	    }
	}
    }
    return $reboot;
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
    # Inform the master that we have rebooted. THIS MUST BE DONE!
    #
    inform_reboot();

    #
    # Check allocation. Exit now if not allocated.
    #
    if (! check_status()) {
	return 0;
    }

    return "$vname.$eid.$pid";
}

1;

