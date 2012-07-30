#!/usr/bin/perl -wT
#
# EMULAB-COPYRIGHT
# Copyright (c) 2000-2010 University of Utah and the Flux Group.
# All rights reserved.
#

#
# CygWin specific routines and constants for the client bootime setup stuff.
#
package liblocsetup;
use Exporter;
@ISA = "Exporter";
@EXPORT =
    qw ( $CP $LN $RM $MV $TOUCH $EGREP $CHOWN $CHMOD $MOUNT $UMOUNT
	 $NTS $NET $HOSTSFILE
	 $TMPASSWD $SFSSD $SFSCD $RPMCMD
	 os_account_cleanup os_accounts_start os_accounts_end os_accounts_sync
	 os_ifconfig_line os_etchosts_line
	 os_setup os_groupadd os_groupgid os_useradd os_userdel os_usermod os_mkdir
	 os_ifconfig_veth os_viface_name
	 os_routing_enable_forward os_routing_enable_gated
	 os_routing_add_manual os_routing_del_manual os_homedirdel
	 os_groupdel os_samba_mount os_islocaldir
	 os_getnfsmounts os_getnfsmountpoints os_noisycmd
	 os_fwconfig_line os_fwrouteconfig_line
       );

sub VERSION()	{ return 1.0; }

# Must come after package declaration!
use English;

# Load up the paths. Its conditionalized to be compatabile with older images.
# Note this file has probably already been loaded by the caller.
BEGIN
{
    if (-e "/etc/emulab/paths.pm") {
	require "/etc/emulab/paths.pm";
	import emulabpaths;
    }
    else {
	my $ETCDIR  = "/etc/rc.d/testbed";
	my $BINDIR  = "/etc/rc.d/testbed";
	my $VARDIR  = "/etc/rc.d/testbed";
	my $BOOTDIR = "/etc/rc.d/testbed";
    }
}

use librc;

#
# Various programs and things specific to CygWin on XP and that we want to export.
# 
$CP		= "/bin/cp";
$LN		= "/bin/ln";
$RM		= "/bin/rm";
$MV		= "/bin/mv";
$TOUCH		= "/bin/touch";
$EGREP		= "/bin/egrep -q";
$CHOWN		= "/bin/chown";
$CHMOD		= "/bin/chmod";
$MOUNT		= "/bin/mount";
$UMOUNT		= "/bin/umount";

# Cygwin.
$MKPASSWD	= "/bin/mkpasswd";
$MKGROUP	= "/bin/mkgroup";
$AWK		= "/bin/gawk";
$BASH		= "/bin/bash";

# Windows under Cygwin.
$NTS		= "/cygdrive/c/WINDOWS/system32";
$NET		= "$NTS/net";
$NETSH		= "$NTS/netsh";
$IPCONFIG	= "$NTS/ipconfig";
$NTE		= "$NTS/drivers/etc";

$HOSTSFILE	= "$NTE/hosts";
#$HOSTSFILE	= "/etc/hosts";

#
# These are not exported
#
my $ADDUSERS	= "$NTS/addusers.exe";
my $DEVCON	= "$NTS/devcon.exe";
my $IFCONFIGBIN = "$NETSH interface ipv4 set address";
my $IFCONFIG	= "$IFCONFIGBIN name=\"%s\" source=static addr=%s mask=%s";
my $IFC_1000MBS = "1000baseTx";
my $IFC_100MBS  = "100baseTx";
my $IFC_10MBS   = "10baseT";
my $IFC_FDUPLEX = "FD";
my $IFC_HDUPLEX = "HD";
my $FSTABFILE   = "/etc/fstab";
my @LOCKFILES   = ("/etc/group.lock", "/etc/gshadow.lock");
my $MKDIR	= "/bin/mkdir";
my $RMDIR	= "/bin/rmdir";
my $GATED	= "/usr/sbin/gated";
my $ROUTE	= "$NTS/route";
my $SHELLS	= "/etc/shells";
my $DEFSHELL	= "/bin/tcsh";
my $winusersfile = "$BOOTDIR/winusers";
my $usershellsfile = "$BOOTDIR/usershells";
my $XIMAP	= "$BOOTDIR/xif_map";

#
# system() with error checking.
#
sub mysystem($)
{
    my ($cmd) = @_;
    if (system($cmd) != 0) {
	warning("Failed: ($cmd), $!\n");
    }
}

#
# OS dependent part of cleanup node state.
# 
sub os_account_cleanup($)
{
    # XXX this stuff should be lifted up into rc.accounts, sigh
    my ($updatemasterpasswdfiles) = @_;
    if (!defined($updatemasterpasswdfiles)) {
	$updatemasterpasswdfiles = 0;
    }

    # Undo what rc.mounts and rc.accounts did.  

    # Get the users list from NT, dumped into /etc/passwd and preened by the
    # os_accounts_sync function.  Root and internal admin accounts should have
    # homedirs under /home, while users are under /users.
    my ($pwd_line, $name);
    if (open(PWDHANDLE, "/etc/passwd")) {
	while ($pwdline = readline(PWDHANDLE)) {
	    if ($pwdline !~ m|:/users/|) {
		next;
	    }
	    $name = substr($pwdline, 0, index($pwdline, ":"));
	    print "Removing user: $name\n";

	    # There is always an NT account.
	    mysystem("$NET user $name /delete >& /dev/null");

	    # There will only be an NT homedir if the user has logged in sometime.
	    my $das = "C:/Users";
	    if ( -d "$das/$name" ) {
		print "Removing directory: $das/$name\n";
		system("$CHMOD -Rf 777 $das/$name >& /dev/null");
		system("$CHOWN -Rf root $das/$name >& /dev/null");
		system("$RM -rf $das/$name "); # Show errors.
	    }
	    # It sometimes also makes user.PCnnn, user.PCnnn.000, etc.
	    if ( `ls -d $das/$name.* 2>/dev/null` ) {
		print "Removing directories: $das/$name.*\n";
		system("$CHMOD -Rf 777 $das/$name.* >& /dev/null");
		system("$CHOWN -Rf root $das/$name.* >& /dev/null");
		system("$RM -rf $das/$name.*"); # Show errors.
	    }

	    # Unmount the homedir so we can get to the mount point and remove it.
	    system("$UMOUNT /users/$name >& /dev/null");
	    system("$RMDIR /users/$name")
		if ( -d "/users/$name" );
	}
	close(PWDHANDLE);
    }

    # Remove groups added by Emulab clientside. 1000 < GID < 2000.
    if(open(GRHANDLE, "/etc/group")) {
	while (my $gline = <GRHANDLE>) {
	    my ($gname, $sid, $gid) = split(/:/,$gline);
	    next if !defined($gname) || !defined($gid);
	    if ($gid > 1000 && $gid < 2000) {
		print "Removing group: $gname\n";
		system("$NET localgroup $gname /delete");
	    }
	}
	close(GRHANDLE);
    }

    # Make the CygWin /etc/passwd and /etc/group files match Windows.
    os_accounts_sync();

    # Clean out the user /sshkeys directories, leaving /sshkeys/root alone.
    if (opendir(DIRHANDLE, "/sshkeys")) {
	while ($name = readdir(DIRHANDLE)) {
	    if ($name =~ m/^\.+/ || $name =~ m/^root$/) {
		next;
	    }

	    # Open up an existing key dir to the root user.  Even though root
	    # is in the Administrators group, it's locked out by permissions.
	    mysystem("$CHMOD 777 /sshkeys/$name");
	    mysystem("$CHOWN -Rf root /sshkeys/$name");
	    mysystem("$RM -rf /sshkeys/$name");
	}
	closedir(DIRHANDLE);
    }

    # Clean out the /proj subdirectories.
    if (opendir(DIRHANDLE, "/proj")) {
	while ($name = readdir(DIRHANDLE)) {
	    if ($name =~ m/^\.+/) {
		next;
	    }
	    print "Removing project: $name\n";

	    # Unmount the project dir so we can get to the mount point.
	    mysystem("$UMOUNT /proj/$name");
	    mysystem("$RMDIR /proj/$name");
	}
    }

    # Just unmount /share, everybody gets one.
    mysystem("$UMOUNT /share");
}

# 
# Make the CygWin /etc/passwd and /etc/group files match Windows.
# 
sub os_accounts_sync()
{
    unlink @LOCKFILES;
    unlink "/etc/passwd.new";

    # Generate the CygWin password and group files from the registry users.
    # Note that the group membership is not reported into the CygWin files.
    print "Resetting the CygWin passwd and group files.\n";

    my $cmd = "$MKPASSWD -l | $AWK -F: '";
    $cmd   .=   'BEGIN{ OFS=":"; ';
    # Keep Windows admin account homedirs under /home so we know what to clean.
    $cmd   .=   '  admin["root"]= admin["Administrator"]= admin["Guest"]= 1; }';
    # Make root's UID zero.
    $cmd   .=   '{ if ($1=="root") $3="0"; ';
    # Put genuine user homedirs under /users, instead of /home.
    $cmd   .=   '    else if ( ! admin[$1] ) sub("/home/", "/users/"); print }'; 
    $cmd   .= "'";
    # Apply the users' shell preferences.
    $cmd   .= " | sed -f $usershellsfile"
	if (-e $usershellsfile);
    $cmd   .= " > /etc/passwd.new";
    ##print "$cmd\n";
    if (system("$cmd") != 0) {
	warning("Nonzero exit status while generating /etc/password.new file: $?\n");
    }
    if (! -e "/etc/passwd.new") {
	warning("passwd.new file not found! /etc/passwd will be wrong.");
	exit -1;
    }

    # Work around "/etc/passwd: Device or resource busy".
    $cmd    = "$MV /etc/passwd /etc/passwd.prev";
    ##print "$cmd\n";
    if (system("$cmd") != 0) {
	warning("Could not $cmd $!\n");
	return -1;
    }
    $cmd    = "$MV /etc/passwd.new /etc/passwd";
    ##print "$cmd\n";
    if (system("$cmd") != 0) {
	warning("Could not $cmd $!\n");
	return -1;
    }

    $cmd  = "$MKGROUP -l | $AWK '";
    # Make a duplicate group line that is a wheel alias for Administrators.
    $cmd .= '/^Administrators:/{print "wheel" substr($0, index($0,":"))} {print}';
    $cmd .= "' > /etc/group";
    ##print "$cmd\n";
    if (system("$cmd") != 0) {
	warning("Nonzero exit status while generating /etc/group file: $?\n");
    }
    
    return 0;
}

# Import the mapping from non-control interface names, e.g. "Local Area
# Connection #4" to the Device Instance ID's used as devcon arguments, e.g.
# "@PCI\VEN_8086&DEV_1010&SUBSYS_10128086&REV_01\5&2FA58B96&0&210030".
my %dev_map = ();
sub get_dev_map()
{
    if (! $dev_map) {
	if (! open(DEVMAP, $XIMAP)) {
	    warning("Cannot open $XIMAP $!\n");
	}
	else {
	    while (my $dev_line = <DEVMAP>) {
		chomp($dev_line);
		my ($dev_name, $dev_inst) = split(":", $dev_line, 2);
		$dev_map{$dev_name} = $dev_inst;
	    }
	    close(DEVMAP);
	}
    }
}

#
# Generate and return an ifconfig line that is approriate for putting
# into a shell script (invoked at bootup).
#
sub os_ifconfig_line($$$$$$$;$$%)
{
    my ($iface, $inet, $mask, $speed, $duplex, $aliases, $iface_type,
	$settings, $rtabid, $cookie) = @_;
    my ($uplines, $downlines);

    # Handle interfaces missing from ipconfig.
    get_dev_map();
    if ( ! defined( $dev_map{$iface} ) ) {
	# Try rc.cygwin again to disable/re-enable the interface object.
	system("$BINDIR/rc/rc.cygwin");

	# Reboot if it still fails, in hope that the interface comes back.
	# 
	# We dare not proceed, because using netsh to try to set the IP
	# address on one of the missing addresses will blow away the IP on
	# *another* interface, sometimes the control net interface.  Then
	# we would really be in the soup...
	get_dev_map();
	if ( ! defined( $dev_map{$iface} ) ) {
	    system("$BINDIR/rc/rc.reboot");
	    # Sometimes rc.reboot gets fork: Resource temporarily unavailable.
	    print "rc.reboot returned, trying tsshutddn.";
	    system("tsshutdn 1 /REBOOT /DELAY:1");
	    print "tsshutdn failed, sleep forever.";
	    sleep;
	}
    }

    if ($inet ne "") {
	# Startup.
	$uplines   .= qq{\n    #================================\n    };
	$uplines   .= qq{echo "Enabling $iface on $inet"\n    };
	#
	# Re-enable device if necessary (getmac Transport is "Media disconnected".)
	my $test   =  qq[getmac /v /fo csv | awk -F, '/^"$iface"/{print \$4}'];
	$uplines   .= qq{if [ \`$test\` = '"Media disconnected"' ]; then\n    };
	$uplines   .=   "  $DEVCON enable '$dev_map{$iface}'\n    ";
	$uplines   .= qq{  sleep 5\n    };
	$uplines   .= qq{fi\n    };
	#
	# Configure.
	$uplines   .= sprintf($IFCONFIG, $iface, $inet, $mask) . qq{\n    };
	$uplines   .= 
qq%
    waittime=20
    rtcmd="/cygdrive/c/windows/system32/route print $inet"
    echo -n "Waiting for routing table to update for interface $inet "
    n=1
    while ! { \$rtcmd | grep -q $inet; }
    do
      echo -n "."
      sleep 1
      let n++
      if [ \$n -ge \$waittime ]
      then
        echo; echo "Route never updated during allotted time!"
        exit 1
      fi
    done
    echo ""
%;

	$downlines .= qq{echo "Disabling $iface from $inet"\n    };
	$downlines .=   "$DEVCON disable '$dev_map{$iface}'\n";
    }
    
    return ($uplines, $downlines);
}

#
# Specialized function for configing locally hacked veth devices.
#
sub os_ifconfig_veth($$$$$;$$$$$)
{
    return "";
}

#
# Compute the name of a virtual interface device based on the
# information in ifconfig hash (as returned by getifconfig).
#
sub os_viface_name($)
{
    my ($ifconfig) = @_;
    my $piface = $ifconfig->{"IFACE"};

    #
    # Physical interfaces use their own name
    #
    if (!$ifconfig->{"ISVIRT"}) {
	return $piface;
    }
    warn("CygWin does not support virtual interface type '$itype'\n");
    return undef;
}

#
# Generate and return an string that is approriate for putting
# into /etc/hosts.
#
sub os_etchosts_line($$$)
{
    my ($name, $ip, $aliases) = @_;
    
    # Note: space rather than tab after the host name on Windows.
    return sprintf("%s %s %s", $ip, $name, $aliases);
}

#
# On Windows NT, accumulate an input file for the addusers command.
# See "AddUsers Automates Creation of a Large Number of Users",
# http://support.microsoft.com/default.aspx?scid=kb;en-us;199878
# 
# The file format is comma-delimited, as follows:
# 
# [Users]
# User Name,Full name,Password,Description,HomeDrive,Homepath,Profile,Script
# 
# [Global] or [Local]
# Group Name,Comment,UserName,...
# 
my @groupNames;
my %groupsByGid;
my %groupMembers;
sub os_accounts_start()
{
    # Remember group info to be put out at the end.
    @groupNames = ();
    %groupsByGid = ();
    %groupMembers = ();

    if (! open(WINUSERS, "> $winusersfile")) {
	warning("os_accounts_start: Cannot create $winusersfile .\n");
	return -1;
    }

    # Don't wipe out previous user shell preferences, just add new ones.
    if (! open(USERSHELLS, ">> $usershellsfile")) {
	warning("os_accounts_start: Cannot create or append to $usershellsfile .\n");
	return -1;
    }

    # Users come before groups in the addusers.exe account stream.
    # Notice the <CR><LF>'s!  It's a Windows file.
    print WINUSERS "[Users]\r\n";

    return 0;
}

#
# Remember the mapping from an existing group GID to its name.
#
sub os_groupgid($$)
{
    my($group, $gid) = @_;

    $groupsByGid{$gid} = $group;    # Remember the name associated with the gid.

    return 0;
}

#
# Add a new group
# 
sub os_groupadd($$)
{
    my($group, $gid) = @_;

    push(@groupNames, $group);      # Remember all of the group names.
    os_groupgid($group, $gid);

    return 0;
}

#
# Delete an old group
# 
sub os_groupdel($)
{
    my($group) = @_;

    # Unimplemented.
    warning("os_groupdel unimplemented in Windows 7.");
    return -1;
}

#
# Remove a user account.
# 
sub os_userdel($)
{
    my($login) = @_;

    # Unimplemented.
    warning("os_userdel unimplemented in Windows 7.");
    return -1;
}

#
# Modify user password.
# 
sub os_modpasswd($$)
{
    my($login, $pswd) = @_;
    warning("os_modpasswd unimplemented in Windows 7.");
    return -1;
}

#
# Modify user group membership and password.
# Changing the login shell is unimplemented.
# 
sub os_usermod($$$$$$)
{
    my($login, $gid, $glist, $pswd, $root, $shell) = @_;

    if ($root) {
	$glist .= ",0";
    }
    if ($glist ne "") {
	##print "glist '$glist'\n";
	my $gname;
	foreach my $grp (split(/,/, $glist)) {
	    if ( $grp eq "0" ) {
		$gname = "Administrators";
	    }
	    else {
		$gname = $groupsByGid{$grp};
	    }
	    ##print "login $login, grp $grp, gname '$gname'\n";
	    my $cmd = "$NET localgroup $gname | tr -d '\\r' | grep -q '^$login\$'";
	    ##print "    $cmd\n";
	    if (system($cmd)) {
		# Add members into groups using the "net localgroup /add" command.
		$cmd = "$NET localgroup $gname $login /add";
		##print "    $cmd\n";
		if (system($cmd) != 0) {
		    warning("os_usermod error ($cmd)\n");
		}
	    }
	}
    }

    $cmd = "echo -e '$pswd\\n$pswd' | passwd $login >& /dev/null";
    ##print "    $cmd\n";
    if (system($cmd) != 0) {
	warning("os_usermod error ($cmd)\n");
    }
}

#
# Add a user.
# 
sub os_useradd($$$$$$$$$)
{
    my($login, $uid, $gid, $pswd, $glist, $homedir, $gcos, $root, $shell) = @_;

    # Groups have to be created before we can add members.
    my $gname = $groupsByGid{$gid};
    warning("Missing group name for gid $gid.\n")
	if (!$gname);
    $groupMembers{$gname} .= "$login ";
    $groupMembers{'Administrators'} .= "$login "
	if ($root);
    foreach my $gid (split(/,/, $glist)) {
	$gname = $groupsByGid{$gid};
	if ($gname) {
	    $groupMembers{$gname} .= "$login ";
	}
	else {
	    warning("Missing group name for gid $gid.\n");
	}
    }
		     
    # Map the shell into a full path.
    $shell = MapShell($shell);
    # Change the ones that are different from the default from mkpasswd, /bin/bash.
    print USERSHELLS "/^$login:/s|/bin/bash\$|$shell|\n"
	if ($shell !~ "/bin/bash");

    # Use the leading 8 chars of the Unix MD5 passwd hash as a known random
    # password, both here and in Samba.  Skip over a "$1$" prefix.
    my $pwd = $pswd;
    $pwd =~ s/^(\$1\$)(.{8}).*/$2/;
    
    print WINUSERS "$login,$gcos,$pwd,,,,,\r\n";

    return 0;
}

#
# Finish the input for the addusers command.
#
sub os_accounts_end()
{
    # Dump out the group *creation* lines.
    print WINUSERS "[Local]\r\n";
    foreach my $grp (@groupNames) {
	# Ignore group membership here.  See "net localgroup" below.
	print WINUSERS "$grp,Emulab $grp group,\r\n";
    }
    close WINUSERS;
    close USERSHELLS;
       
    # Create the whole batch of groups and accounts listed in the file.
    # /p options: Users don't have to change passwords, and they never expire.
    print "Creating the Windows users and groups.\n";
    my $winfile = "C:/cygwin$winusersfile";
    $winfile =~ s|/|\\|g;
    my $cmd = "$ADDUSERS /c '$winfile' /p:le";
    ##print "    $cmd\n";
    if (system($cmd) != 0) {
	warning("AddUsers error ($cmd)\n");
	return -1;
    }

    # Add members into groups using the "net localgroup /add" command.
    # (Addusers only creates groups, it can't add a user to an existing group.)
    while (my($grp, $members) = each %groupMembers) {
	foreach my $mbr (split(/ /,$members)) {
	    print "  Adding $mbr to $grp.\n";
	    my $cmd = "$NET localgroup $grp $mbr /add > /dev/null";
	    ##print "    $cmd\n";
	    if (system($cmd) != 0) {
		warning("net localgroup error ($cmd)\n");
	    }
	}
    }

    # Make the CygWin /etc/passwd and /etc/group files match Windows.
    # Note that the group membership is not reported into the CygWin files.
    return os_accounts_sync();
}

#
# Remove a homedir. Might someday archive and ship back.
#
sub os_homedirdel($$)
{
    warning("os_homedirdel unimplemented in Windows 7.");
    return 0;
}

#
# Create a directory including all intermediate directories.
#
sub os_mkdir($$)
{
    my ($dir, $mode) = @_;

    if (system("$MKDIR -p -m $mode $dir")) {
	return 0;
    }
    return 1;
}

#
# OS Dependent configuration. 
# 
sub os_setup()
{
    return 0;
}
    
#
# OS dependent, routing-related commands
#
sub os_routing_enable_forward()
{
    return "";
}

sub os_routing_enable_gated($)
{
    return "";
}

sub os_routing_add_manual($$$$$;$)
{
    my ($routetype, $destip, $destmask, $gate, $cost, $rtabid) = @_;
    my $cmd;

    if ($routetype eq "host") {
	$cmd = "$ROUTE add $destip $gate";
    } elsif ($routetype eq "net") {
	$cmd = "$ROUTE add $destip mask $destmask $gate";
    } elsif ($routetype eq "default") {
	$cmd = "$ROUTE add 0.0.0.0 $gate";
    } else {
	warning("Bad routing entry type: $routetype\n");
	$cmd = "";
    }

    # There appears to be a race with interfaces coming on-line.
    #     The route addition failed: Either the interface index is wrong or
    #     the gateway does not lie on the same network as the interface. Check
    #     the IP Address Table for the machine.
    # Re-doing the command later succeeds.
    # Wrap the route command in a loop to make sure it gets done.
    # Don't loop forever.
    #$cmd = "n=1; while ! ( $ROUTE print | grep -Fq $destip ); do \n
    #            echo $cmd;\n
    #            $cmd\n
    #            let n++; if [[ \$n > 5 ]]; then break; fi
    #            sleep 5\n
    #        done";
    $cmd = "echo $cmd; $cmd";

    return $cmd;
}

sub os_routing_del_manual($$$$$;$)
{
    my ($routetype, $destip, $destmask, $gate, $cost, $rtabid) = @_;
    my $cmd;

    if ($routetype eq "host") {
	$cmd = "$ROUTE delete $destip";
    } elsif ($routetype eq "net") {
	$cmd = "$ROUTE delete $destip";
    } elsif ($routetype eq "default") {
	$cmd = "$ROUTE delete 0.0.0.0";
    } else {
	warning("Bad routing entry type: $routetype\n");
	$cmd = "";
    }

    return $cmd;
}

# Map a shell name to a full path using /etc/shells
sub MapShell($)
{
   my ($shell) = @_;

   if ($shell eq "") {
       return $DEFSHELL;
   }

   my $fullpath = `grep '/${shell}\$' $SHELLS`;

   if ($?) {
       return $DEFSHELL;
   }

   # Sanity Check
   if ($fullpath =~ /^([-\w\/]*)$/) {
       $fullpath = $1;
   }
   else {
       $fullpath = $DEFSHELL;
   }
   return $fullpath;
}

# Return non-zero if given directory is on a "local" filesystem
sub os_islocaldir($)
{
    my ($dir) = @_;

    # XXX
    if ($dir =~ /^\/(proj|groups|users|share)/) {
	return 0;
    }
    return 1;
}

my %mounts = ();
sub os_samba_mount($$$)
{
    my ($local, $host, $verbose) = @_;

    # Build mounts hash from /etc/mount, if we haven't already
    if (!%mounts) {
	if (!open(FSTAB, "<$FSTABFILE")) { 
	    warning("os_samba_mount: Can't open $FSTABFILE");
	} else {
	    while (my $inline = <FSTAB>) {
		chomp $inline;
		next if $inline =~ /^\s*#/;
		next if $inline =~ /^\s*$/;
		my ($mpoint,$mtarget,undef,undef,undef,undef) = 
		    split(/\s+/,$inline);
		$mounts{$mpoint} = $mtarget;
	    }
	    close(FSTAB);
	}
    }

    # Make the CygWin mount from the Samba path to the local mount point directory.
    my $sambapath = $local;
    $sambapath =~ s|^/proj/(.*)|proj-$1|;
    $sambapath =~ s|^/groups/(.*)/(.*)|$1-$2|;
    $sambapath =~ s|.*/(.*)|$1|;
    $sambapath = "//$host/$sambapath";
    if (! -e $local) {
	print "os_samba_mount: Making CygWin '$local' mount point directory.\n"
	    if ($verbose);
	if (! os_mkdir($local, "0755")) {  # Will make whole path if necessary.
	    warning("os_samba_mount: Could not make mount point $local.\n");
	}
    }
    elsif (! -d $local) {
	warning("os_samba_mount: Mount point $local is not a directory.\n");
    }

    if (!exists($mounts{$sambapath})) {
	print "Adding '$sambapath' -> '$local' to $FSTABFILE .\n"
	    if ($verbose);

	if (!open(FSTAB, ">>$FSTABFILE")) {
	    warning("os_samba_mount: Can't open $FSTABFILE for append.");
	} else {
	    print FSTAB "$sambapath $local smbfs binary,user 0 0\n";
	    close(FSTAB);
	}
    }
}

# Extract the local mount point from a remote NFS mount path.
sub os_mountlocal($)
{
    my ($remote) = @_;
    my $local = $remote;
    $local =~ s|^.*:||;			# Remove server prefix.
    $local =~ s|^/q/proj/|/proj/|;	# Remove /q prefix from /proj.
    return $local;
}

# Execute a noisy bash command, throwing away the output unless we ask for it.
sub os_noisycmd($$)
{
    my ($cmd, $verbose) = @_;
    my $bashcmd = "$BASH -c '$cmd'" . ($verbose ? "" : " > /dev/null");
    my $ret = system($bashcmd);
    ##print "os_noisycmd cmd '$cmd', ret $ret\n";
    return $ret
}

sub os_fwconfig_line($@)
{
    my ($fwinfo, @fwrules) = @_;
    my ($upline, $downline);
    my $errstr = "*** WARNING: Windows firewall not implemented\n";

    warn $errstr;
    $upline = "echo $errstr; exit 1";
    $downline = "echo $errstr; exit 1";

    return ($upline, $downline);
}

sub os_fwrouteconfig_line($$$)
{
    my ($orouter, $fwrouter, $routestr) = @_;
    my ($upline, $downline);

    #
    # XXX assume the original default route should be used to reach servers.
    #
    # For setting up the firewall, this means we create explicit routes for
    # each host via the original default route.
    #
    # For tearing down the firewall, we just remove the explicit routes
    # and let them fall back on the now re-established original default route.
    #
    $upline  = "for vir in $routestr; do\n";
    $upline .= "        $ROUTE delete \$vir >/dev/null 2>&1\n";
    $upline .= "        $ROUTE add -host \$vir gw $orouter || {\n";
    $upline .= "            echo \"Could not establish route for \$vir\"\n";
    $upline .= "            exit 1\n";
    $upline .= "        }\n";
    $upline .= "    done";

    $downline  = "for vir in $routestr; do\n";
    $downline .= "        $ROUTE delete \$vir >/dev/null 2>&1\n";
    $downline .= "    done";

    return ($upline, $downline);
}

1;
