#!/usr/bin/perl -wT
#
# EMULAB-COPYRIGHT
# Copyright (c) 2000-2004 University of Utah and the Flux Group.
# All rights reserved.
#

#
# Linux specific routines and constants for the client bootime setup stuff.
#
package liblocsetup;
use Exporter;
@ISA = "Exporter";
@EXPORT =
    qw ( $CP $EGREP $MOUNT $UMOUNT $TMPASSWD $SFSSD $SFSCD
	 os_cleanup_node os_ifconfig_line os_etchosts_line
	 os_setup os_groupadd os_useradd os_userdel os_usermod os_mkdir
	 os_rpminstall_line os_ifconfig_veth
	 os_routing_enable_forward os_routing_enable_gated
	 os_routing_add_manual os_routing_del_manual os_homedirdel
	 os_groupdel os_commitchanges
       );

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

#
# Various programs and things specific to win32/cygwin and that we want to export.
# 
##$CP		= "/bin/cp";
##$EGREP	= "/bin/egrep -q";
#$MOUNT		= "/bin/mount";
#$UMOUNT		= "/bin/umount";
#$TMPASSWD	= "$ETCDIR/passwd";
#$SFSSD		= "/usr/local/sbin/sfssd";
#$SFSCD		= "/usr/local/sbin/sfscd";

#
# These are not exported
#
#my $TMGROUP	= "$ETCDIR/group";
#my $TMSHADOW    = "$ETCDIR/shadow";
#my $TMGSHADOW   = "$ETCDIR/gshadow";
#my $USERADD     = "/usr/sbin/useradd";
#my $USERDEL     = "/usr/sbin/userdel";
#my $USERMOD     = "/usr/sbin/usermod";
#my $GROUPADD	= "/usr/sbin/groupadd";
#my $GROUPDEL	= "/usr/sbin/groupdel";
#my $IFCONFIG    = "/sbin/ifconfig %s inet %s netmask %s";
#my $IFC_100MBS  = "100baseTx";
#my $IFC_10MBS   = "10baseT";
#my $IFC_FDUPLEX = "FD";
#my $IFC_HDUPLEX = "HD";
my $RPMINSTALL  = "/bin/rpm -i %s";
#my @LOCKFILES   = ("/etc/group.lock", "/etc/gshadow.lock");
my $MKDIR	= "/bin/mkdir";
my $GATED	= "/usr/sbin/gated";
#my $ROUTE	= "/sbin/route";
my $SHELLS	= "/etc/shells";
#my $DEFSHELL	= "/bin/tcsh";

#
# OS dependent part of cleanup node state.
# 
sub os_cleanup_node ($) {
#     my ($scrub) = @_;

#     unlink @LOCKFILES;

#     if (! $scrub) {
# 	return 0;
#     }
    
#     printf STDOUT "Resetting passwd and group files\n";
#     if (system("$CP -f $TMGROUP $TMPASSWD /etc") != 0) {
# 	print STDERR "Could not copy default group file into place: $!\n";
# 	exit(1);
#     }
    
#     if (system("$CP -f $TMSHADOW $TMGSHADOW /etc") != 0) {
# 	print STDERR "Could not copy default passwd file into place: $!\n";
# 	exit(1);
#     }

    #RDC Should probably do stuff here
    return 0;
}

#
# Generate and return an ifconfig line that is approriate for putting
# into a shell script (invoked at bootup).
#
sub os_ifconfig_line($$$$$$;$)
{
      die "os_ifconfig_line not written";
#     my ($iface, $inet, $mask, $speed, $duplex, $aliases, $rtabid) = @_;
#     my ($ifc, $miirest, $miisleep, $miisetspd, $media);

#     #
#     # Need to check units on the speed. Just in case.
#     #
#     if ($speed =~ /(\d*)([A-Za-z]*)/) {
# 	if ($2 eq "Mbps") {
# 	    $speed = $1;
# 	}
# 	elsif ($2 eq "Kbps") {
# 	    $speed = $1 / 1000;
# 	}
# 	else {
# 	    warn("*** Bad speed units in ifconfig!\n");
# 	    $speed = 100;
# 	}
# 	if ($speed == 100) {
# 	    $media = $IFC_100MBS;
# 	}
# 	elsif ($speed == 10) {
# 	    $media = $IFC_10MBS;
# 	}
# 	else {
# 	    warn("*** Bad Speed in ifconfig!\n");
# 	    $media = $IFC_100MBS;
# 	}
#     }
#     if ($duplex eq "full") {
# 	$media = "$media-$IFC_FDUPLEX";
#     }
#     elsif ($duplex eq "half") {
# 	$media = "$media-$IFC_HDUPLEX";
#     }
#     else {
# 	warn("*** Bad duplex in ifconfig!\n");
# 	$media = "$media-$IFC_FDUPLEX";
#     }

#     $ifc = "/sbin/mii-tool --force=$media $iface\n" .
# 	   sprintf($IFCONFIG, $iface, $inet, $mask);
    
#     return "$ifc";
}

#
# Specialized function for configing locally hacked veth devices.
#
sub os_ifconfig_veth($$$$$;$$$)
{
    return "";
}

#
# Generate and return an string that is approriate for putting
# into /etc/hosts.
#
sub os_etchosts_line($$$)
{
#    my ($name, $ip, $aliases) = @_;

#    return sprintf("%s\t%s %s", $ip, $name, $aliases);
}

my(%daGroups) = (
'Administrators' => 'Administrators,Administrators have complete and unrestricted access to the computer/domain',
'Users' => 'Users,Users are prevented from making accidental or intentional system-wide changes.  Thus, Users can run certified applications, but not most legacy applications',
'Remote Desktop Users' => 'Remote Desktop Users,Members in this group are granted the right to logon remotely'
);

#
# Add a new group
# 
sub os_groupadd($$)
{
    my($group, $gid) = @_;
    
    $daGroups{$gid} = "$group,group description";
    return 0;
}

#
# Delete an old group
# 
sub os_groupdel($)
{
#RDC Right now we are doing nothing, The Addusers.exe program that I am currently using to add users
#    does not support removing groups.
#    my($group) = @_;

#    return system("$GROUPDEL $group");
}

#
# Remove a user account.
# 
sub os_userdel($)
{
#RDC Right now we are doing nothing, The Addusers.exe program that I am currently using to add users
#    does not support removing users.
#    my($login) = @_;

#    return system("$USERDEL $login");
}

#
# Modify user group membership.
# 
sub os_usermod($$$$$$)
{
#RDC MAJOR ERROR!!! Right now this function just silently fails.  It should at least report a error that the 
#                   code is not implemented under win32
#     my($login, $gid, $glist, $pswd, $root, $shell) = @_;

#     if ($root) {
# 	$glist = join(',', split(/,/, $glist), "root");
#     }
#     if ($glist ne "") {
# 	$glist = "-G $glist";
#     }
#     # Map the shell into a full path.
#     $shell = MapShell($shell);

#     return system("$USERMOD -s $shell -g $gid $glist -p '$pswd' $login");
}

my %daUsers = ();
#
# Add a user.
# 
sub os_useradd($$$$$$$$$)
{
    my($login, $uid, $gid, $pswd, $glist, $homedir, $gcos, $root, $shell) = @_;
    my $plainTextPasswd = 'hackMe!';
    $daUsers{$login} = "$login,$login,$plainTextPasswd,,,,";
    print STDERR "message";
    foreach (split(",",$glist), $gid) {
      if($daGroups{$_}) {
        $daGroups{$_} = $daGroups{$_} . ",$login";
      } else {
	print STDERR "gid->group name mapping for gid $_ not found";
      }
    }
    if ($root) {
        $daGroups{Administrators} = $daGroups{Administrators} . ",$login";
    } else {
        $daGroups{Users} = $daGroups{Users} . ",$login";
	$daGroups{'Remote Desktop Users'} = $daGroups{'Remote Desktop Users'} . ",$login";
    }
    return 0;
}

sub os_commitchanges()
{
#This is a nop under Unix and does the work in Windows

#open a file handle to /etc/testbed/accounts_to_create.txt
    open(FOO, ">/etc/testbed/accounts_to_create.txt") or die "accounts_to_create could not open to write";
    print FOO "[Users]\n";
    foreach (values(%daUsers)) {
        print FOO $_ . "\n";
      }
    print FOO "\n[Global]\n"; #Meaning Global groups, this will be
                              #blank becuase we don't have a Domain
                              #Controller
    print FOO "\n[Local]\n"; #Meaning local groups
    #Format is as follows:
    #<groupname>,<group discription>,<group member#1>,<group member#2>,...
      foreach (values(%daGroups)) {
	print FOO $_ . "\n";
      }
    close(FOO);
    #addusers.exe will only accept a DOS text file
    system('unix2dos /etc/testbed/accounts_to_create.txt');
    #Now do the actual commit
    print "Running addusers.exe...\n";
    system('addusers.exe /c c:\\\\cygwin\\\\etc\\\\testbed\\\\accounts_to_create.txt');
    print "addusers.exe done\n";
}
#
# Remove a homedir. Might someday archive and ship back.
#
sub os_homedirdel($$)
{
    return 0;
}

#
# Generate and return an RPM install line that is approriate for putting
# into a shell script (invoked at bootup).
#
sub os_rpminstall_line($)
{
    my ($rpm) = @_;
    
    return sprintf($RPMINSTALL, $rpm);
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
    my $cmd;

    $cmd = "sysctl -w net.ipv4.conf.all.forwarding=1";
    return $cmd;
}

sub os_routing_enable_gated()
{
    my $cmd;

    # XXX hack to avoid gated dying mysteriously with TCP/611 already in use
    $cmd = "sleep 3\n    ";
    $cmd .= "(ps alxww ; netstat -na) > /tmp/gated.state\n    ";
    $cmd .= "$GATED -f $BINDIR/gated_`$BINDIR/control_interface`.conf";
    return $cmd;
}

sub os_routing_add_manual($$$$$;$)
{
    my ($routetype, $destip, $destmask, $gate, $cost, $rtabid) = @_;
    my $cmd;

    if ($routetype eq "host") {
	$cmd = "$ROUTE add -host $destip gw $gate";
    } elsif ($routetype eq "net") {
	$cmd = "$ROUTE add -net $destip netmask $destmask gw $gate";
    } else {
	warn "*** WARNING: bad routing entry type: $routetype\n";
	$cmd = "";
    }

    return $cmd;
}

sub os_routing_del_manual($$$$$;$)
{
    my ($routetype, $destip, $destmask, $gate, $cost, $rtabid) = @_;
    my $cmd;

    if ($routetype eq "host") {
	$cmd = "$ROUTE delete -host $destip";
    } elsif ($routetype eq "net") {
	$cmd = "$ROUTE delete -net $destip netmask $destmask gw $gate";
    } else {
	warn "*** WARNING: bad routing entry type: $routetype\n";
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

1;
