#!/usr/bin/perl -wT
#
# Copyright (c) 2013 University of Utah and the Flux Group.
# 
# {{{EMULAB-LICENSE
# 
# This file is part of the Emulab network testbed software.
# 
# This file is free software: you can redistribute it and/or modify it
# under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or (at
# your option) any later version.
# 
# This file is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Affero General Public
# License for more details.
# 
# You should have received a copy of the GNU Affero General Public License
# along with this file.  If not, see <http://www.gnu.org/licenses/>.
# 
# }}}
#

#
# FreeBSD specific routines and constants for client storage setup.
#
package liblocstorage;
use Exporter;
@ISA = "Exporter";
@EXPORT =
    qw (
	os_init_storage os_check_storage os_create_storage os_remove_storage
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
	my $ETCDIR  = "/etc/testbed";
	my $BINDIR  = "/etc/testbed";
	my $VARDIR  = "/etc/testbed";
	my $BOOTDIR = "/etc/testbed";
    }
}

my $MKDIR	= "/bin/mkdir";
my $MOUNT	= "/sbin/mount";
my $UMOUNT	= "/sbin/umount";
my $MKFS	= "/sbin/newfs";
my $FSCK	= "/sbin/fsck";
my $ISCSI	= "/sbin/iscontrol";
my $ISCSICNF	= "/etc/iscsi.conf";
my $SMARTCTL	= "/usr/local/sbin/smartctl";
my $GEOM	= "/sbin/geom";
my $GPART	= "/sbin/gpart";
my $GVINUM	= "/sbin/gvinum";
my $ZPOOL	= "/sbin/zpool";
my $ZFS		= "/sbin/zfs";

#
# We orient the FS blocksize toward larger files.
# (64K/8K is the largest that UFS supports).
#
# Note that we also set the zfs zvol blocksize to match.
# We currently only use zvols when the user does NOT specify a mountpoint
# (we use a native zfs otherwise), but in case they do create a filesystem
# on it later, it will be well suited to that use.
#
my $UFSBS	= "65536";
my $ZVOLBS	= "64K";

#
# For gvinum, it is recommended that the stripe size not be a power of two
# to avoid FS metadata (which use power-of-two alignment) all winding up
# on the same disk.
#
my $VINUMSS	= "81920";

#
# To find the block stores exported from a target portal:
#
#   iscontrol -d -t <storage-host>
#
# To use a remote iSCSI target, the info has to be in /etc/iscsi.conf:
#
#   <bsid> {
#     initiatorname = <our hostname>
#     targetname    = <iqn>
#     targetaddress = <storage-host>
#   }
#
# To login to a remote iSCSI target:
# 
#   iscontrol -c /etc/iscsi.conf -n <bsid>
# 
# The session ID for the resulting session can be determined from the
# sysctl net.iscsi_initiator info:
#
#   net.iscsi_initiator.<session>.targetname: <iqn>
#   net.iscsi_initiator.<session>.targeaddress: <storage-host-IP>
#
# To stop a session (logout) you must first determine its pid from
# the net.iscsi_initiator info:
#
#   net.iscsi_initiator.<session>.pid: <pid>
#
# and then send it a HUP:
#
#   kill -HUP <pid>
#
# Once a blockstore is added, it will appear as a /dev/da? device.
# I have not found a straight-forward way to map session to device.
# What we do now is to use the session ID to match up info from
# "camcontrol identify da<N> -v". camcontrol will return output like:
#
#   (pass3:iscsi0:0:0:0): ATAPI_IDENTIFY. ACB: ...
#   ...
#
# where N in "iscsiN" will be the session.
# 

sub iscsi_to_dev($)
{
    my ($session) = @_;

    #
    # XXX this is a total hack
    #
    my @lines = `ls /dev/da* 2>&1`;
    foreach (@lines) {
	if (m#^/dev/(da\d+)$#) {
	    my $dev = $1;
	    my $out = `camcontrol identify $dev -v 2>&1`;
	    if ($out =~ /^\(pass\d+:iscsi(\d+):/) {
		if ($1 == $session) {
		    return $dev;
		}
	    }
	}
    }

    return undef;
}

sub serial_to_dev($)
{
    my ($sn) = @_;

    #
    # XXX this is a total hack
    #
    if (! -x "$SMARTCTL") {
	return undef;
    }

    my @lines = `ls /dev/da* 2>&1`;
    foreach (@lines) {
	if (m#^/dev/(da\d+)$#) {
	    my $dev = $1;
	    my $out = `$SMARTCTL -i /dev/$dev 2>&1 | grep 'Serial Number'`;
	    if ($out =~ /^Serial Number:\s+$sn/) {
		return $dev;
	    }
	}
    }

    return undef;
}

#
# Returns one if the indicated device is an iSCSI-provided one
# XXX another total hack
#
sub is_iscsi_dev($)
{
    my ($dev) = @_;

    if ($dev !~ /^da\d+$/) {
	return 0;
    }
    if (!open(FD, "$GEOM disk list $dev|")) {
	return 0;
    }
    my $descr = "";
    while (<FD>) {
	if (/^\s+descr:\s+(.*)$/) {
	    $descr = $1;
	    last;
	}
    }
    close(FD);
    if ($descr !~ /^FreeBSD iSCSI Disk/) {
	return 0;
    }

    return 1;
}

sub uuid_to_session($)
{
    my ($uuid) = @_;

    my @lines = `sysctl net.iscsi_initiator 2>&1`;
    foreach (@lines) {
	if (/net\.iscsi_initiator\.(\d+)\.targetname: $uuid/) {
	    return $1;
	}
    }

    return undef;
}

sub uuid_to_daemonpid($)
{
    my ($uuid) = @_;
    my $session;

    my @lines = `sysctl net.iscsi_initiator 2>&1`;
    foreach (@lines) {
	if (/net\.iscsi_initiator\.(\d+)\.targetname: $uuid/) {
	    $session = $1;
	    next;
	}
	if (/net\.iscsi_initiator\.(\d+)\.pid: (\d+)/) {
	    if (defined($session) && $1 == $session) {
		return $2;
	    }
	}
    }

    return undef;
}

#
# Return the name (e.g., "da0") of the boot disk, aka the "system volume".
#
sub get_bootdisk()
{
    my $disk = undef;
    my $line = `$MOUNT | grep ' on / '`;

    if ($line && $line =~ /^\/dev\/(\S+)s1a on \//) {
	$disk = $1;
	#
	# FreeBSD 9+ changed the naming convention.
	# But there will be a symlink to the real device.
	#
	if ($disk =~ /^ad\d+$/) {
	    $line = `ls -l /dev/$disk`;
	    if ($line =~ /${disk} -> (\S+)/) {
		$disk = $1;
	    }
	}
    }
    return $disk;
}

#
# Return a list of the physical drives (partitions) that are part of
# the current gvinum config.
#
sub get_vinum_drives()
{
    my @drives = ();

    if (open(FD, "$GVINUM ld 2>/dev/null|")) {
	while (<FD>) {
	    if (/^D emulab_(\S+)/) {
		push(@drives, $1);
	    }
	}
	close(FD);
    }

    return @drives;
}

#
# In FreeBSD 9+, zpool has a -v command so we could do:
#   zpool list -vH -o name
# but alas, FreeBSD 8 doesn't have it. So we do:
#   zpool iostat -v
# which is the only other way I have found to list the vdevs of a pool.
#
sub get_zpool_vdevs($)
{
    my ($pool) = @_;
    my @vdevs = ();

    if (open(FD, "$ZPOOL iostat -v $pool 2>/dev/null|")) {
	while (<FD>) {
	    if (/^\s+(\w+)/) {
		push(@vdevs, $1);
	    }
	}
	close(FD);
    }

    return @vdevs;
}

#
# Return the name of any datasets in the given pool.
# Returns an empty list if there is not such pool or no datasets.
#
sub get_zpool_datasets($)
{
    my ($pool) = @_;
    my @dsets = ();

    if (open(FD, "$ZFS list -Hr $pool 2>/dev/null|")) {
	while (<FD>) {
	    if (/^($pool\/\S+)\s/) {
		push(@dsets, $1);
	    }
	}
	close(FD);
    }

    return @dsets;
}

#
# Returns 1 if the volume manager has been initialized.
# For ZFS this means that the "emulab" zpool exists.
# For gvinum this means that the emulab_* drives exist.
#
sub is_lvm_initialized($)
{
    my ($usezfs) = @_;

    if ($usezfs) {
	if (mysystem("$ZPOOL list emulab >/dev/null 2>&1") == 0) {
	    return 1;
	}
    } else {
	if (get_vinum_drives() > 0) {
	    return 1;
	}
    }
    return 0;
}

#
#
# Get information about local disks.
#
# Ideally, this comes from the list of ELEMENTs passed in.
#
# But if that is not available, we figure it out outselves by using
# the GEOM subsystem:
# For FreeBSD 8- we have to go fishing using geom commands.
# For FreeBSD 9+ there is a convenient sysctl mib that gives us everything.
#
sub get_diskinfo($)
{
    my ($usezfs) = @_;
    my %geominfo = ();

    my @lines = `sysctl -n kern.geom.conftxt`;
    chomp(@lines);
    if (@lines > 0) {
	# FBSD9 and above.
	foreach (@lines) {
	    next if ($_ eq "");
	    my @vals = split /\s/;

	    # assume 2k sector size means a CD drive
	    if ($vals[0] == 0 && $vals[1] eq "DISK" && $vals[4] == 2048) {
		next;
	    }

	    my $dev = $vals[2];
	    $geominfo{$dev}{'level'} = $vals[0];
	    $geominfo{$dev}{'type'} = $vals[1];
	    # size is in bytes, convert to MiB
	    $geominfo{$dev}{'size'} = int($vals[3] / 1024 / 1024);
	    if ($vals[1] eq "DISK") {
		$geominfo{$dev}{'inuse'} = 0;
	    } else {
		$geominfo{$dev}{'inuse'} = 1;
	    }
	}
    } else {
	# FBSD8: no sysctl, have to parse geom output
	my ($curdev,$curpart,$skipping);

	# first find all the disks
	if (!open(FD, "$GEOM disk list|")) {
	    warn("*** get_diskinfo: could not execute geom command\n");
	    return undef;
	}
	while (<FD>) {
	    if (/^\d+\.\s+Name:\s+(\S+)$/) {
		$curdev = $1;
		$geominfo{$curdev}{'level'} = 0;
		$geominfo{$curdev}{'type'} = "DISK";
		$geominfo{$curdev}{'inuse'} = 0;
		next;
	    }
	    if (/\sMediasize:\s+(\d+)\s/) {
		if ($curdev) {
		    $geominfo{$curdev}{'size'} = int($1 / 1024 / 1024);
		    $curdev = undef;
		}
		next;
	    }
	    $curdev = undef;
	}
	close(FD);

	# now find all the partitions on those disks
	if (!open(FD, "$GEOM part list|")) {
	    warn("*** get_diskinfo: could not execute geom command\n");
	    return undef;
	}
	$skipping = 1;
	$curdev = $curpart = undef;
	while (<FD>) {
	    if (/^Geom name:\s+(\S+)/) {
		$curdev = $1;
		if (exists($geominfo{$curdev})) {
		    $skipping = 2;
		}
		next;
	    }
	    next if ($skipping < 2);

	    if (/^Providers:/) {
		$skipping = 3;
		next;
	    }
	    next if ($skipping < 3);

	    if (/^\d+\.\s+Name:\s+(\S+)$/) {
		$curpart = $1;
		$geominfo{$curpart}{'level'} = $geominfo{$curdev}{'level'} + 1;
		$geominfo{$curpart}{'type'} = "PART";
		$geominfo{$curpart}{'inuse'} = -1;
		next;
	    }
	    if (/\sMediasize:\s+(\d+)\s/) {
		$geominfo{$curpart}{'size'} = int($1 / 1024 / 1024);
		next;
	    }

	    if (/^Consumers:/) {
		$skipping = 1;
		next;
	    }
	}
	close(FD);

	# and finally, vinums
	if (!$usezfs) {
	    if (!open(FD, "$GEOM vinum list|")) {
		warn("*** get_diskinfo: could not execute geom command\n");
		return undef;
	    }
	    $curpart = undef;
	    $skipping = 1;
	    while (<FD>) {
		if (/^Providers:/) {
		    $skipping = 2;
		    next;
		}
		next if ($skipping < 2);

		if (/^\d+\.\s+Name:\s+(\S+)$/) {
		    $curpart = $1;
		    $geominfo{$curpart}{'level'} = 2;
		    $geominfo{$curpart}{'type'} = "VINUM";
		    $geominfo{$curpart}{'inuse'} = -1;
		    next;
		}
		if (/\sMediasize:\s+(\d+)\s/) {
		    $geominfo{$curpart}{'size'} = int($1 / 1024 / 1024);
		    next;
		}

		if (/^Consumers:/) {
		    $skipping = 1;
		    next;
		}
	    }
	    close(FD);
	}
    }

    #
    # Note that disks are "in use" if they are part of a zpool.
    #
    if ($usezfs) {
	my @vdevs = get_zpool_vdevs("emulab");
	foreach my $dev (@vdevs) {
	    if (exists($geominfo{$dev}) && $geominfo{$dev}{'type'} eq "DISK") {
		$geominfo{$dev}{'inuse'} = 1;
	    }
	}
    }

    #
    # Find any ZFS datasets and their characteristics.
    # Again, FreeBSD 9+ zfs get has a handy "-t filesystem" or "-t volume"
    # option that would allow:
    #
    # zfs get -o name,property,value -Hp -t filesystem quota
    # zfs get -o name,property,value -Hp -t volume volsize
    #
    # but FreeBSD 8 does not, so we do:
    #
    # zfs get -o name,property,value -Hp quota,volsize
    #
    # zvols will have a quota of '-', zfses will have a volsize of '-'
    #
    if ($usezfs) {
	if (!open(FD, "$ZFS get -o name,property,value -Hp quota,volsize|")) {
	    warn("*** get_diskinfo: could not execute ZFS command\n");
	    return undef;
	}
	while (<FD>) {
	    my ($zdev,$prop,$size) = split /\s/;
	    next if ($zdev eq "emulab");
	    next if ($size eq "-");
	    $geominfo{$zdev}{'size'} = int($size / 1024 / 1024);
	    $geominfo{$zdev}{'level'} = 2;
	    if ($prop eq "quota") {
		$geominfo{$zdev}{'type'} = "ZFS";
	    } else {
		$geominfo{$zdev}{'type'} = "ZVOL";
	    }
	    $geominfo{$zdev}{'inuse'} = -1;
	}
	close(FD);
    }

    #
    # Make a pass through and mark disks that are in use where "in use"
    # means "has a partition" or is an iSCSI disk.
    #
    foreach my $dev (keys %geominfo) {
	my $type = $geominfo{$dev}{'type'};
	if ($type eq "DISK" && is_iscsi_dev($dev)) {
	    $geominfo{$dev}{'type'} = "iSCSI";
	    $geominfo{$dev}{'inuse'} = -1;
	}
	elsif ($type eq "PART" && $geominfo{$dev}{'level'} == 1 &&
	    $dev =~ /^(.*)s\d+$/) {
	    if (exists($geominfo{$1})) {
		$geominfo{$1}{'inuse'} = 1;
	    }
	}
    }

    return \%geominfo;
}

#
# Handle one-time operations.
# Return a cookie (object) with current state of storage subsystem.
#
sub os_init_storage($)
{
    my ($lref) = @_;
    my $gotlocal = 0;
    my $gotnonlocal = 0;
    my $gotelement = 0;
    my $gotslice = 0;
    my $gotiscsi = 0;
    my $needavol = 0;
    my $needall = 0;

    my %so = ();

    # we rely heavily on GEOM
    if (! -x "$GEOM") {
	warn("*** storage: $GEOM does not exist, cannot continue\n");
	return undef;
    }

    foreach my $href (@{$lref}) {
	if ($href->{'CMD'} eq "ELEMENT") {
	    $gotelement++;
	} elsif ($href->{'CMD'} eq "SLICE") {
	    $gotslice++;
	    if ($href->{'BSID'} eq "SYSVOL" ||
		$href->{'BSID'} eq "NONSYSVOL") {
		$needavol = 1;
	    } elsif ($href->{'BSID'} eq "ANY") {
		$needall = 1;
	    }
	}
	if ($href->{'CLASS'} eq "local") {
	    $gotlocal++;
	} else {
	    $gotnonlocal++;
	    if ($href->{'PROTO'} eq "iSCSI") {
		$gotiscsi++;
	    }
	}
    }

    # check for local storage incompatibility
    if ($needall && $needavol) {
	warn("*** storage: Incompatible local volumes.\n");
	return undef;
    }
	
    # initialize volume manage if needed for local slices
    if ($gotlocal && $gotslice) {

	# we use ZFS only on 64-bit versions of the OS
	my $usezfs = 0;
	if (-x "$ZPOOL") {
	    my $un = `uname -rm`;
	    if ($un =~ /^(\d+)\.\S+\s+(\S+)/) {
		$usezfs = 1 if ($1 >= 8 && $2 eq "amd64");
	    }
	}
	$so{'USEZFS'} = $usezfs;

	#
	# zfs: see if pool already exists, set zfs_enable in /etc/rc.conf.
	#
	if ($usezfs) {
	    #
	    # XXX we create the empty SPACEMAP so we don't try to initialize
	    # it later. ZFS never uses the SPACEMAP once the pool is created.
	    #
	    if (is_lvm_initialized(1)) {
		$so{'ZFS_POOLCREATED'} = 1;
		$so{'SPACEMAP'} = ();
	    }

	    if (mysystem("grep -q 'zfs_enable=\"YES\"' /etc/rc.conf")) {
		if (!open(FD, ">>/etc/rc.conf")) {
		    warn("*** storage: could not enable zfs in /etc/rc.conf\n");
		    return undef;
		}
		print FD "# added by $BINDIR/rc/rc.storage\n";
		print FD "zfs_enable=\"YES\"\n";
		close(FD);

		# and do a one-time start
		if (-x "/etc/rc.d/zfs") {
		    mysystem("/etc/rc.d/zfs start");
		}
	    }
	}

	#
	# gvinum: put module load in /boot/loader.conf so that /etc/fstab
	# mounts will work.
	#
	else {
	    if (is_lvm_initialized(0)) {
		$so{'VINUM_DRIVES'} = 1;
	    }
	    if (mysystem("grep -q 'geom_vinum_load=\"YES\"' /boot/loader.conf")) {
		if (!open(FD, ">>/boot/loader.conf")) {
		    warn("*** storage: could not enable gvinum in /boot/loader.conf\n");
		    return undef;
		}
		print FD "# added by $BINDIR/rc/rc.storage\n";
		print FD "geom_vinum_load=\"YES\"\n";
		close(FD);

		# and do a one-time start
		mysystem("$GVINUM start");
	    }
	}

	#
	# Grab the bootdisk and current GEOM state
	#
	my $bdisk = get_bootdisk();
	my $dinfo = get_diskinfo($usezfs);
	if (!exists($dinfo->{$bdisk}) || $dinfo->{$bdisk}->{'inuse'} == 0) {
	    warn("*** storage: bootdisk '$bdisk' marked as not in use!?\n");
	    return undef;
	}
	$so{'BOOTDISK'} = $bdisk;
	$so{'DISKINFO'} = $dinfo;
	if (0) {
	    print STDERR "BOOTDISK='$bdisk'\nUSEZFS='$usezfs'\nDISKINFO=\n";
	    foreach my $dev (keys %$dinfo) {
		my $type = $dinfo->{$dev}->{'type'};
		my $lev = $dinfo->{$dev}->{'level'};
		my $size = $dinfo->{$dev}->{'size'};
		my $inuse = $dinfo->{$dev}->{'inuse'};
		print STDERR "name=$dev, type=$type, level=$lev, size=$size, inuse=$inuse\n";
	    }
	    return undef;
	}
    }

    if ($gotiscsi) {
	my $redir = ">/dev/null 2>&1";

	if (! -x "$ISCSI") {
	    warn("*** storage: $ISCSI does not exist, cannot continue\n");
	    return undef;
	}

	#
	# XXX load initiator driver
	#
	if (mysystem("kldstat | grep -q iscsi_initiator") &&
	    mysystem("kldload iscsi_initiator.ko $redir")) {
	    warn("*** storage: Could not load iscsi_initiator kernel module\n");
	    return undef;
	}
    }

    $so{'INITIALIZED'} = 1;
    return \%so;
}

#
# os_check_storage(sobject,confighash)
#
#   Determines if the storage unit described by confighash exists and
#   is properly configured. Returns zero if it doesn't exist, 1 if it
#   exists and is correct, -1 otherwise.
#
#   Side-effect: Creates the hash member $href->{'LVDEV'} with the /dev
#   name of the storage unit.
#
sub os_check_storage($$)
{
    my ($so,$href) = @_;

    if (0) {
	my $dinfo = get_diskinfo($so->{'USEZFS'});
	print STDERR "DISKINFO=\n";
	foreach my $dev (keys %$dinfo) {
	    my $type = $dinfo->{$dev}->{'type'};
	    my $lev = $dinfo->{$dev}->{'level'};
	    my $size = $dinfo->{$dev}->{'size'};
	    my $inuse = $dinfo->{$dev}->{'inuse'};
	    print STDERR "name=$dev, type=$type, level=$lev, size=$size, inuse=$inuse\n";
	}
    }

    if ($href->{'CMD'} eq "ELEMENT") {
	return os_check_storage_element($so,$href);
    }
    if ($href->{'CMD'} eq "SLICE") {
	return os_check_storage_slice($so,$href);
    }
    return -1;
}

sub os_check_storage_element($$)
{
    my ($so,$href) = @_;
    my $CANDISCOVER = 0;
    my $redir = ">/dev/null 2>&1";

    #
    # iSCSI:
    #  make sure iscsi_initiator kernel module is loaded
    #  make sure the IQN exists
    #  make sure there is an entry in /etc/iscsi.conf.
    #
    if ($href->{'CLASS'} eq "SAN" && $href->{'PROTO'} eq "iSCSI") {
	my $hostip = $href->{'HOSTIP'};
	my $uuid = $href->{'UUID'};
	my $bsid = $href->{'VOLNAME'};
	my @lines;
	my $cmd;

	#
	# See if the block store exists on the indicated server.
	# If not, something is very wrong, return -1.
	#
	# Note that the server may not support discovery. If not, we don't
	# do it since it is only a sanity check anyway.
	#
	if ($CANDISCOVER) {
	    @lines = `$ISCSI -d -t $hostip 2>&1`;
	    if ($? != 0) {
		warn("*** could not find exported iSCSI block stores\n");
		return -1;
	    }
	    my $taddr = "";
	    for (my $i = 0; $i < scalar(@lines); $i++) {
		# found target, look at next
		if ($lines[$i] =~ /^TargetName=$uuid/ &&
		    $lines[$i+1] =~ /^TargetAddress=($hostip.*)/) {
		    $taddr = $1;
		    last;
		}
	    }
	    if (!$taddr) {
		warn("*** could not find iSCSI block store '$uuid'\n");
		return -1;
	    }
	}

	#
	# See if it is in the config file.
	# If not, we have not done the one-time initialization, return 0.
	#
	if (! -r "$ISCSICNF" || mysystem("grep -q '$uuid' $ISCSICNF")) {
	    return 0;
	}

	#
	# XXX hmm...FreeBSD does not have an /etc/rc.d script for starting
	# up iscontrol instances. So we have to do it everytime right now.
	#
	# First, check and see if there is a session active for this
	# blockstore. If not we must start one.
	#
	my $session = uuid_to_session($uuid);
	if (!defined($session)) {
	    if (mysystem("$ISCSI -c $ISCSICNF -n $bsid $redir")) {
		warn("*** $bsid: could not create iSCSI session\n");
		return -1;
	    }
	    sleep(1);
	    $session = uuid_to_session($uuid);
	}

	#
	# Figure out the device name from the session.
	#
	my $dev = iscsi_to_dev($session);
	if (!defined($dev)) {
	    warn("*** $bsid: found iSCSI session but could not find device\n");
	    return -1;
	}
	$href->{'LVDEV'} = "/dev/$dev";

	#
	# If there is a mount point, see if it is mounted.
	#
	# XXX because mounts in /etc/fstab happen before iSCSI and possibly
	# even the network are setup, we don't put our mounts there as we
	# do for local blockstores. Thus, if the blockstore device is not
	# mounted, we do it here.
	#
	my $mpoint = $href->{'MOUNTPOINT'};
	if ($mpoint) {
	    my $line = `$MOUNT | grep '^/dev/$dev on '`;
	    if (!$line) {
		# the mountpoint should exist
		if (! -d "$mpoint") {
		    warn("*** $bsid: no mount point $mpoint\n");
		    return -1;
		}
		# fsck it in case of an abrupt shutdown
		if (mysystem("$FSCK -p /dev/$dev $redir")) {
		    warn("*** $bsid: fsck of /dev/$dev failed\n");
		    return -1;
		}
		# and mount it
		if (mysystem("$MOUNT -t ufs /dev/$dev $mpoint $redir")) {
		    warn("*** $bsid: could not mount /dev/$dev on $mpoint\n");
		    return -1;
		}
	    }
	    elsif ($line !~ /^\/dev\/$dev on (\S+) / || $1 ne $mpoint) {
		warn("*** $bsid: mounted on $1, should be on $mpoint\n");
		return -1;
	    }
	}

	return 1;
    }

    #
    # local disk:
    #  make sure disk exists
    #
    if ($href->{'CLASS'} eq "local") {
	my $bsid = $href->{'VOLNAME'};
	my $sn = $href->{'UUID'};

	my $dev = serial_to_dev($sn);
	if (defined($dev)) {
	    $href->{'LVDEV'} = "/dev/$dev";
	    return 1;
	}

	# for physical disks, there is no way to "create" it so return error
	warn("*** $bsid: could not find HD with serial '$sn'\n");
	return -1;
    }

    warn("*** $bsid: unsupported class/proto '" .
	 $href->{'CLASS'} . "/" . $href->{'PROTO'} . "'\n");
    return -1;
}

#
# Return 0 if does not exist
# Return 1 if exists and correct
# Return -1 otherwise
#
sub os_check_storage_slice($$)
{
    my ($so,$href) = @_;
    my $bsid = $href->{'BSID'};

    #
    # local storage:
    #  if BSID==SYSVOL:
    #    see if 4th part of boot disk exists (eg: da0s4) and
    #    is of type freebsd
    #  else if BSID==NONSYSVOL:
    #    see if there is a concat volume with appropriate name
    #  else if BSID==ANY:
    #    see if there is a concat volume with appropriate name
    #  if there is a mountpoint, see if it exists in /etc/fstab
    #
    # List all volumes:
    #   gvinum lv
    #
    #
    if ($href->{'CLASS'} eq "local") {
	my $lv = $href->{'VOLNAME'};
	my ($dev, $devtype, $mdev, $slop);

	my $dinfo = $so->{'DISKINFO'};
	my $bdisk = $so->{'BOOTDISK'};

	# figure out the device of interest
	if ($bsid eq "SYSVOL") {
	    $dev = "${bdisk}s4";
	    $mdev = "${dev}a";
	    $devtype = "PART";
	} else {
	    if ($so->{'USEZFS'}) {
		$dev = "emulab/$lv";
		if ($href->{'MOUNTPOINT'}) {
		    # XXX
		    $mdev = $dev;
		    $devtype = "ZFS";
		} else {
		    $mdev = "zvol/emulab/$lv";
		    $devtype = "ZVOL";
		}
		$slop = 0;
	    } else {
		$dev = $mdev = "gvinum/$lv";
		$devtype = "VINUM";
		#
		# XXX due to round-off when allocating space from individual
		# gvinum drives, the actual size could be larger than what
		# was requested by up to 1MiB per disk.
		#
		$slop = scalar(get_vinum_drives());
	    }
	}
	my $devsize = $href->{'VOLSIZE'};

	# if the device does not exist, return 0
	if (!exists($dinfo->{$dev})) {
	    return 0;
	}
	# if it exists but is of the wrong type, we have a problem!
	my $atype = $dinfo->{$dev}->{'type'};
	if ($atype ne $devtype) {
	    warn("*** $lv: actual type ($atype) != expected type ($devtype)\n");
	    return -1;
	}
	# ditto for size, unless this is the SYSVOL where we ignore user size
	# or if the size was not specified.
	my $asize = $dinfo->{$dev}->{'size'};
	if ($bsid ne "SYSVOL" && $devsize &&
	    !($asize >= $devsize && $asize <= $devsize + $slop)) {
	    warn("*** $lv: actual size ($asize) != expected size ($devsize)\n");
	    return -1;
	}

	# if there is a mountpoint, make sure it is mounted
	my $mpoint = $href->{'MOUNTPOINT'};
	if ($mpoint && $devtype ne "ZFS") {
	    my $line = `$MOUNT | grep '^/dev/$mdev on '`;
	    if (!$line) {
		warn("*** $lv: is not mounted, should be on $mpoint\n");
		return -1;
	    }
	    if ($line !~ /^\/dev\/$mdev on (\S+) / || $1 ne $mpoint) {
		warn("*** $lv: mounted on $1, should be on $mpoint\n");
		return -1;
	    }
	}

	if ($devtype ne "ZFS") {
	    $mdev = "/dev/$mdev";
	}
	$href->{'LVDEV'} = "$mdev";
	return 1;
    }

    warn("*** $bsid: unsupported class '" . $href->{'CLASS'} . "'\n");
    return -1;
}

#
# os_create_storage(confighash)
#
#   Create the storage unit described by confighash. Unit must not exist
#   (os_check_storage should be called first to verify). Return one on
#   success, zero otherwise.
#
sub os_create_storage($$)
{
    my ($so,$href) = @_;
    my $rv = 0;

    # record all the output for debugging
    my $log = "/var/emulab/logs/" . $href->{'VOLNAME'} . ".out";
    mysystem("cp /dev/null $log");

    if ($href->{'CMD'} eq "ELEMENT") {
	$rv = os_create_storage_element($so, $href, $log);
    }
    elsif ($href->{'CMD'} eq "SLICE") {
	$rv = os_create_storage_slice($so, $href, $log);
    }
    if ($rv == 0) {
	return 0;
    }

    if (exists($href->{'MOUNTPOINT'}) && !exists($href->{'MOUNTED'})) {
	my $lv = $href->{'VOLNAME'};
	my $mdev = $href->{'LVDEV'};

	# record all the output for debugging
	my $redir = "";
	my $logmsg = "";
	if ($log) {
	    $redir = ">>$log 2>&1";
	    $logmsg = ", see $log";
	}

	#
	# Create the filesystem
	#
	if (mysystem("$MKFS -b $UFSBS $mdev $redir")) {
	    warn("*** $lv: could not create FS$logmsg\n");
	    return 0;
	}

	#
	# Mount the filesystem
	#
	my $mpoint = $href->{'MOUNTPOINT'};
	if (! -d "$mpoint" && mysystem("$MKDIR -p $mpoint $redir")) {
	    warn("*** $lv: could not create mountpoint '$mpoint'$logmsg\n");
	    return 0;
	}

	#
	# XXX because mounts in /etc/fstab happen before iSCSI and possibly
	# even the network are setup, we don't put our mounts there as we
	# do for local blockstores. Instead, the check_storage call will
	# take care of these mounts.
	#
	if (!($href->{'CLASS'} eq "SAN" && $href->{'PROTO'} eq "iSCSI")) {
	    if (!open(FD, ">>/etc/fstab")) {
		warn("*** $lv: could not add mount to /etc/fstab\n");
		return 0;
	    }
	    print FD "$mdev\t$mpoint\tufs\trw\t2\t2\n";
	    close(FD);
	    if (mysystem("$MOUNT $mpoint $redir")) {
		warn("*** $lv: could not mount on $mpoint$logmsg\n");
		return 0;
	    }
	} else {
	    if (mysystem("$MOUNT -t ufs $mdev $mpoint $redir")) {
		warn("*** $lv: could not mount $mdev on $mpoint$logmsg\n");
		return 0;
	    }
	}
    }

    return 1;
}

sub os_create_storage_element($$$)
{
    my ($so,$href,$log) = @_;

    if ($href->{'CLASS'} eq "SAN" && $href->{'PROTO'} eq "iSCSI") {
	my $hostip = $href->{'HOSTIP'};
	my $uuid = $href->{'UUID'};
	my $bsid = $href->{'VOLNAME'};
	my $cmd;

	# record all the output for debugging
	my $redir = "";
	my $logmsg = "";
	if ($log) {
	    $redir = ">>$log 2>&1";
	    $logmsg = ", see $log";
	}

	#
	# Handle one-time setup of /etc/iscsi.conf.
	#
	if (! -r "$ISCSICNF" || mysystem("grep -q '$uuid' $ISCSICNF $redir")) {
	    if (!open(FD, ">>$ISCSICNF")) {
		warn("*** could not update $ISCSICNF\n");
		return 0;
	    }
	    my $hname = `hostname`;
	    chomp($hname);
	    print FD <<EOF;
$bsid {
    initiatorname = $hname
    targetname    = $uuid
    targetaddress = $hostip
}
EOF
	    close(FD);   
	} else {
	    warn("*** $bsid: trying to create but already exists!?\n");
	    return 0;
        }

	#
	# Everything has been setup, start the daemon.
	#
	if (mysystem("$ISCSI -c $ISCSICNF -n $bsid $redir")) {
	    warn("*** $bsid: could not create iSCSI session\n");
	    return 0;
	}
	sleep(1);

	#
	# Find the session ID and device name.
	#
	my $session = uuid_to_session($uuid);
	if (!defined($session)) {
	    warn("*** $bsid: could not find iSCSI session\n");
	    return 0;
	}
	my $dev = iscsi_to_dev($session);
	if (!defined($dev)) {
	    warn("*** $bsid: could not map iSCSI session to device\n");
	    return 0;
	}

	$href->{'LVDEV'} = "/dev/$dev";
	return 1;
    }

    warn("*** Only support SAN/iSCSI now\n");
    return 0;
}

sub os_create_storage_slice($$$)
{
    my ($so,$href,$log) = @_;
    my $bsid = $href->{'BSID'};

    #
    # local storage:
    #  if BSID==SYSVOL:
    #     create the 4th part of boot disk with type freebsd,
    #	  create a native filesystem (that imagezip would understand).
    #  else if BSID==NONSYSVOL:
    #	  make sure partition 1 exists on all disks and each has type
    #	  freebsd, create stripe or concat volume with appropriate name
    #  else if BSID==ANY:
    #	  make sure all partitions exist (4 on sysvol, 1 on all others)
    #     and have type freebsd, create a concat volume with appropriate
    #	  name across all available disks
    #  if there is a mountpoint:
    #     create a filesystem on device, mount it, add to /etc/fstab
    #
    if ($href->{'CLASS'} eq "local") {
	my $lv = $href->{'VOLNAME'};
	my $lvsize = $href->{'VOLSIZE'};
	my $mdev = "";

	my $bdisk = $so->{'BOOTDISK'};
	my $dinfo = $so->{'DISKINFO'};

	# record all the output for debugging
	my $redir = "";
	my $logmsg = "";
	if ($log) {
	    $redir = ">>$log 2>&1";
	    $logmsg = ", see $log";
	}

	#
	# System volume:
	#
	# gpart add -i 4 -t freebsd da0
	# gpart create -s BSD da0s4
	# gpart add -t freebsd-ufs da0s4
	#
	if ($bsid eq "SYSVOL") {
	    my $slice = "$bdisk" . "s4";
	    my $part = "$slice" . "a";

	    if (mysystem("$GPART add -i 4 -t freebsd $bdisk $redir")) {
		warn("*** $lv: could not create $slice$logmsg\n");
		return 0;
	    }
	    if (mysystem("$GPART create -s BSD $slice $redir") ||
		mysystem("$GPART add -t freebsd-ufs $slice $redir")) {
		warn("*** $lv: could not create $part$logmsg\n");
		return 0;
	    }
	    $mdev = $part;
	}

	#
	# Non-system volume or all space.
	#
	else {
	    #
	    # If partitions have not yet been initialized handle that:
	    #
	    # gpart add -i 4 -t freebsd da0	(ANY only)
	    # gpart create -s mbr da1
	    # gpart add -i 1 -t freebsd da1
	    #
	    if (!exists($so->{'SPACEMAP'})) {
		my %spacemap = ();

		if (exists($so->{'VINUM_DRIVES'})) {
		    foreach my $vdev (get_vinum_drives()) {
			if ($vdev =~ /^(.*)s(\d+)$/) {
			    $spacemap{$1}{'pnum'} = $2;
			}
		    }
		}
		else {
		    if ($bsid eq "ANY") {
			$spacemap{$bdisk}{'pnum'} = 4;
		    }
		    foreach my $dev (keys %$dinfo) {
			if ($dinfo->{$dev}->{'type'} eq "DISK" &&
			    $dinfo->{$dev}->{'inuse'} == 0) {
			    $spacemap{$dev}{'pnum'} = 0;
			}
		    }
		    if (keys(%spacemap) == 0) {
			warn("*** $lv: no space found\n");
			return 0;
		    }

		    #
		    # Create partitions on each disk
		    #
		    foreach my $disk (keys %spacemap) {
			my $pnum = $spacemap{$disk}{'pnum'};

			#
			# If pnum==0, we need an MBR first
			#
			if ($pnum == 0) {
			    if (mysystem("$GPART create -s mbr $disk $redir")) {
				warn("*** $lv: could not create MBR on $disk$logmsg\n");
				return 0;
			    }
			    $pnum = $spacemap{$disk}{'pnum'} = 1;
			}
			if (mysystem("$GPART add -i $pnum -t freebsd $disk $redir")) {
			    warn("*** $lv: could not create ${disk}s${pnum}$logmsg\n");
			    return 0;
			}
		    }
		}

		#
		# Refresh GEOM info and see how much space is available on
		# our disk partitions.
		# XXX we allow some time for changes to take effect.
		#
		sleep(1);
		$dinfo = $so->{'DISKINFO'} = get_diskinfo($so->{'USEZFS'});

		my $total_size = 0;
		my ($min_s,$max_s);
		foreach my $disk (keys %spacemap) {
		    my $part = $disk . "s" . $spacemap{$disk}{'pnum'};
		    if (!exists($dinfo->{$part}) ||
			$dinfo->{$part}->{'type'} ne "PART") {
			warn("*** $lv: created partitions are wrong!?\n");
			return 0;
		    }
		    my $dsize = $dinfo->{$part}->{'size'};
		    $spacemap{$disk}{'size'} = $dsize;
		    $total_size += $dsize;
		    $min_s = $dsize if (!defined($min_s) || $dsize < $min_s);
		    $max_s = $dsize if (!defined($max_s) || $dsize > $max_s);
		}

		#
		# See if we can stripe on the available devices.
		# XXX conservative right now, require all to be the same size.
		#
		if (scalar(keys(%spacemap)) > 1 &&
		    defined($min_s) && $min_s == $max_s) {
		    $so->{'STRIPESIZE'} = $min_s;
		}

		if (0) {
		    print STDERR "DISKINFO=\n";
		    foreach my $dev (keys %$dinfo) {
			my $type = $dinfo->{$dev}->{'type'};
			my $lev = $dinfo->{$dev}->{'level'};
			my $size = $dinfo->{$dev}->{'size'};
			my $inuse = $dinfo->{$dev}->{'inuse'};
			print STDERR "  name=$dev, type=$type, level=$lev, size=$size, inuse=$inuse\n";
		    }
		    my $ssize = "-";
		    if (defined($so->{'STRIPESIZE'})) {
			$ssize = $so->{'STRIPESIZE'};
		    }
		    print STDERR "total/stripe/min/max $total_size/$ssize/$min_s/$max_s, SPACEMAP=\n";
		    foreach my $disk (keys %spacemap) {
			my $pnum = $spacemap{$disk}{'pnum'};
			my $size = $spacemap{$disk}{'size'};
			print STDERR "  disk=$disk, pnum=$pnum, size=$size\n";
		    }
		}

		$so->{'SPACEAVAIL'} = $total_size;
		$so->{'SPACEMAP'} = \%spacemap;
	    }
	    my $space = $so->{'SPACEMAP'};
	    my $total_size = $so->{'SPACEAVAIL'};

	    #
	    # ZFS: put all available space into a zpool, create zfs/zvol
	    # from that:
	    #
	    # zpool create -m none emulab /dev/da0s4 /dev/da1s1	(ANY)
	    # zpool create -m none emulab /dev/da1s1		(NONSYSVOL)
	    #
	    # zfs create -o mountpoint=/mnt -o quota=100M emulab/h2d2 (zfs)
	    # zfs create -b 64K -V 100M emulab/h2d2		      (zvol)
	    #
	    if ($so->{'USEZFS'}) {
		if (!exists($so->{'ZFS_POOLCREATED'})) {
		    my @parts = ();
		    foreach my $disk (sort keys %$space) {
			my $pdev = $disk . "s" . $space->{$disk}->{'pnum'};
			push(@parts, $pdev);
		    }
		    if (mysystem("$ZPOOL create -f -m none emulab @parts $redir")) {
			warn("*** $lv: could not create ZFS pool$logmsg\n");
			return 0;
		    }
		    $so->{'ZFS_POOLCREATED'} = 1;
		}

		#
		# If a mountpoint is specified, create a ZFS filesystem
		# and mount it.
		#
		if (exists($href->{'MOUNTPOINT'})) {
		    my $opts = "-o mountpoint=" . $href->{'MOUNTPOINT'};
		    if ($lvsize > 0) {
			$opts .= " -o quota=${lvsize}M";
		    }
		    if (mysystem("$ZFS create $opts emulab/$lv")) {
			warn("*** $lv: could not create ZFS$logmsg\n");
			return 0;
		    }
		    $mdev = "emulab/$lv";
		    $href->{'MOUNTED'} = 1;
		} else {
		    #
		    # No size specified, use the free size of the pool.
		    # XXX Ugh, we have to parse out the available space of
		    # the root zfs and then leave some slop (5%).
		    #
		    if (!$lvsize) {
			my $line = `$ZFS get -Hp -o value avail emulab 2>/dev/null`;
			if ($line =~ /^(\d+)/) {
			    $lvsize = int(($1 * 0.95) / 1024 / 1024);
			}
			if (!$lvsize) {
			    warn("*** $lv: could not find size of pool\n");
			    return 0;
			}
		    }
		    my $opts = "-b $ZVOLBS -V ${lvsize}M";
		    if (mysystem("$ZFS create $opts emulab/$lv")) {
			warn("*** $lv: could not create ZFS$logmsg\n");
			return 0;
		    }
		    $mdev = "emulab/$lv";
		}
	    }

	    #
	    # VINUM: create a gvinum for the volume using the available space:
	    #
	    # cat > /tmp/h2d2.conf
	    # drive emulab_da0s4 device /dev/da0s4 (ANY only)
	    # drive emulab_da1s1 device /dev/da1s1
	    # volume h2d2
	    #   plex org concat
	    #     sd length NNNm drive emulab_da0s4 (ANY only)
	    #     sd length NNNm drive emulab_da1s1
	    #
	    # gvinum create /tmp/h2d2.conf
	    #
	    else {
		#
		# See if we can stripe.
		# Take the same amount from each volume.
		#
		my $style;
		if (defined($so->{'STRIPESIZE'})) {
		    my $maxstripe = $so->{'STRIPESIZE'};
		    my $ndisks = scalar(keys %$space);
		    my $perdisk;
		    if ($lvsize > 0) {
			$perdisk = int(($lvsize / $ndisks) + 0.5);
		    } else {
			$perdisk = $maxstripe;
		    }
		    if ($perdisk <= $maxstripe) {
			foreach my $disk (keys %$space) {
			    $space->{$disk}->{'vsize'} = $perdisk;
			}
			$lvsize = $ndisks * $perdisk;
			$style = "striped $VINUMSS";
		    }
		}

		#
		# Otherwise we must concatonate.
		# Figure out how much space to take from each disk for this
		# volume. We take proportionally from each.
		#
		if (!$style) {
		    foreach my $disk (keys %$space) {
			if ($lvsize > 0) {
			    my $frac = $space->{$disk}->{'size'} / $total_size;
			    $space->{$disk}->{'vsize'} =
				int(($lvsize * $frac) + 0.5);
			} else {
			    $space->{$disk}->{'vsize'} =
				$space->{$disk}->{'size'};
			}
		    }
		    if ($lvsize == 0) {
			$lvsize = $total_size;
		    }
		    $style = "concat";
		}

		#
		# Create the gvinum config file.
		#
		my $cfile = "/tmp/$lv.conf";
		unlink($cfile);
		if (!open(FD, ">$cfile")) {
		    warn("*** $lv: could not create gvinum config\n");
		    return 0;
		}
		if (!exists($so->{'VINUM_DRIVES'})) {
		    foreach my $disk (keys %$space) {
			my $pdev = $disk . "s" . $space->{$disk}->{'pnum'};
			print FD "drive emulab_$pdev device /dev/$pdev\n";
		    }
		}
		print FD "volume $lv\n";
		print FD "  plex org $style\n";
		foreach my $disk (keys %$space) {
		    my $pdev = $disk . "s" . $space->{$disk}->{'pnum'};
		    my $sdsize = $space->{$disk}->{'vsize'};
		    print FD "    sd length ${sdsize}m drive emulab_$pdev\n";
		}
		close(FD);

		# create the vinum
		if (mysystem("$GVINUM create $cfile $redir")) {
		    warn("*** $lv: could not create vinum$logmsg\n");
		    unlink($cfile);
		    return 0;
		}
		#unlink($cfile);

		# vinum drives exist at this point
		$so->{'VINUM_DRIVES'} = 1;

		# XXX need some delay before accessing device?
		sleep(1);

		$mdev = "gvinum/$lv";
	    }
	}

	#
	# Update the geom info to reflect new devices
	#
	$dinfo = $so->{'DISKINFO'} = get_diskinfo($so->{'USEZFS'});
	if (!exists($dinfo->{$mdev})) {
	    warn("*** $lv: blockstore did not get created!?\n");
	    return 0;
	}

	if (!$href->{'MOUNTED'}) {
	    $mdev = "/dev/$mdev";
	}
	$href->{'LVDEV'} = $mdev;
	return 1;
    }

    warn("*** $bsid: unsupported class '" . $href->{'CLASS'} . "'\n");
    return 0;
}

sub os_remove_storage($$$)
{
    my ($so,$href,$teardown) = @_;

    if ($href->{'CMD'} eq "ELEMENT") {
	return os_remove_storage_element($so, $href, $teardown);
    }
    if ($href->{'CMD'} eq "SLICE") {
	return os_remove_storage_slice($so, $href, $teardown);
    }
    return 0;
}

sub os_remove_storage_element($$$)
{
    my ($so,$href,$teardown) = @_;
    #my $redir = "";
    my $redir = ">/dev/null 2>&1";

    if ($href->{'CLASS'} eq "SAN" && $href->{'PROTO'} eq "iSCSI") {
	my $uuid = $href->{'UUID'};
	my $bsid = $href->{'VOLNAME'};

	#
	# Unmount it
	#
	if (exists($href->{'MOUNTPOINT'})) {
	    my $mpoint = $href->{'MOUNTPOINT'};

	    if (mysystem("$UMOUNT $mpoint")) {
		warn("*** $bsid: could not unmount $mpoint\n");
	    }
	}

	#
	# Find the daemon instance and HUP it.
	# XXX continue even if we could not kill it.
	#
	my $pid = uuid_to_daemonpid($uuid);
	if (defined($pid)) {
	    if (mysystem("kill -HUP $pid $redir")) {
		warn("*** $bsid: could not kill $ISCSI daemon\n");
	    }
	}

	#
	# Remove /etc/iscsi.conf entry for block store
	#
	if ($teardown && !mysystem("grep -q '$uuid' $ISCSICNF $redir")) {
	    if (open(OFD, "<$ISCSICNF") && open(NFD, ">$ISCSICNF.new")) {
		# parser!? we don't need no stinkin parser...
		my $inentry = 0;
		while (<OFD>) {
		    if (/^$bsid {/) {
			$inentry = 1;
			next;
		    }
		    if ($inentry && /^}/) {
			$inentry = 0;
			next;
		    }
		    if (!$inentry) {
			print NFD $_;
		    }
		}
		close(OFD);
		close(NFD);
		if (mysystem("mv -f $ISCSICNF.new $ISCSICNF")) {
		    warn("*** $bsid: could not update $ISCSICNF\n");
		    return 0;
		}
	    }
	}
	return 1;
    }

    #
    # Nothing to do (yet) for a local disk
    #
    if ($href->{'CLASS'} eq "local") {
	return 1;
    }

    warn("*** Only support SAN/iSCSI now\n");
    return 0;
}

#
# teardown==0 means we are rebooting: unmount and shutdown gvinum
# teardown==1 means we are reconfiguring and will be destroying everything
#
sub os_remove_storage_slice($$$)
{
    my ($so,$href,$teardown) = @_;

    if ($href->{'CLASS'} eq "local") {
	my $bsid = $href->{'BSID'};
	my $lv = $href->{'VOLNAME'};

	my $dinfo = $so->{'DISKINFO'};
	my $bdisk = $so->{'BOOTDISK'};

	# figure out the device of interest
	my ($dev, $devtype);
	if ($bsid eq "SYSVOL") {
	    $dev = "${bdisk}s4a";
	    $devtype = "PART";
	} else {
	    if ($so->{'USEZFS'}) {
		$dev = "emulab/$lv";
		if ($href->{'MOUNTPOINT'}) {
		    $devtype = "ZFS";
		} else {
		    $devtype = "ZVOL";
		}
	    } else {
		$dev = "gvinum/$lv";
		$devtype = "VINUM";
	    }
	}

	# if the device does not exist, we have a problem!
	if (!exists($dinfo->{$dev})) {
	    warn("*** $lv: device '$dev' does not exist\n");
	    return 0;
	}
	# ditto if it exists but is of the wrong type
	my $atype = $dinfo->{$dev}->{'type'};
	if ($atype ne $devtype) {
	    warn("*** $lv: actual type ($atype) != expected type ($devtype)\n");
	    return 0;
	}

	# record all the output for debugging
	my $log = "/var/emulab/logs/$lv.out";
	my $redir = ">>$log 2>&1";
	my $logmsg = ", see $log";
	mysystem("cp /dev/null $log");

	#
	# Unmount and remove mount info from fstab.
	#
	# On errors, we warn but don't stop. We do everything in our
	# power to take things down.
	#
	if (exists($href->{'MOUNTPOINT'}) && $devtype ne "ZFS") {
	    my $mpoint = $href->{'MOUNTPOINT'};

	    if (mysystem("$UMOUNT $mpoint")) {
		warn("*** $lv: could not unmount $mpoint\n");
	    }

	    if ($teardown) {
		my $tdev = "/dev/$dev";
		$tdev =~ s/\//\\\//g;
		if (mysystem("sed -E -i -e '/^$tdev/d' /etc/fstab")) {
		    warn("*** $lv: could not remove mount from /etc/fstab\n");
		}
	    }
	}

	#
	# Remove LV
	#
	if ($teardown) {
	    #
	    # System volume:
	    #
	    # gpart destroy -F da0s4
	    # gpart delete -i 4 da0
	    #
	    if ($bsid eq "SYSVOL") {
		my $slice = "$bdisk" . "s4";

		if (mysystem("$GPART destroy -F $slice $redir")) {
		    warn("*** $lv: could not destroy ${slice}a$logmsg\n");
		}
		if (mysystem("$GPART delete -i 4 $bdisk $redir")) {
		    warn("*** $lv: could not destroy $slice$logmsg\n");
		}
		return 1;
	    }

	    #
	    # Other, ZFS:
	    #
	    #   zfs destroy emulab/h2d2
	    #
	    if ($so->{'USEZFS'}) {
		if (mysystem("$ZFS destroy emulab/$lv $redir")) {
		    warn("*** $lv: could not destroy$logmsg\n");
		}

		#
		# If no volumes left:
		#
		#   zpool destroy emulab
		#
		#   gpart delete -i 4 da0 (ANY only)
		#   gpart destroy -F da1
		#
		my @vols = get_zpool_datasets("emulab");
		if (@vols > 0) {
		    return 1;
		}

		#
		# find devices that are a part of the pool
		#
		my @slices = get_zpool_vdevs("emulab");
		if (@slices == 0) {
		    warn("*** $lv: could not find components of zpool\n");
		}

		#
		# Destroy the pool
		#
		if (mysystem("$ZPOOL destroy emulab $redir")) {
		    warn("*** $lv: could not destroy$logmsg\n");
		}

		#
		# And de-partition the disks
		#
		foreach my $slice (@slices) {
		    if ($slice eq "${bdisk}s4") {
			if (mysystem("$GPART delete -i 4 $bdisk $redir")) {
			    warn("*** $lv: could not destroy $slice$logmsg\n");
			}
		    } elsif ($slice =~ /^(.*)s1$/) {
			my $disk = $1;
			if ($disk eq $bdisk ||
			    mysystem("$GPART destroy -F $disk $redir")) {
			    warn("*** $lv: could not destroy $slice$logmsg\n");
			}
		    }
		}

		#
		# If we are the one that enabled ZFS, disable it
		#
		if (!mysystem("grep -q '^# added by.*rc.storage' /etc/rc.conf")) {
		    if (mysystem("sed -i -e '/^# added by.*rc.storage/,+1d' /etc/rc.conf")) {
			warn("*** $lv: could not remove zfs_enable from /etc/rc.conf\n");
		    }
		}
	    }
	    #
	    # Other, gvinum volume:
	    #
	    #   gvinum rm -r h2d2
	    #
	    else {
		if (mysystem("$GVINUM rm -r $lv $redir")) {
		    warn("*** $lv: could not destroy$logmsg\n");
		}

		#
		# If no volumes left:
		#
		#   gvinum rm -r emulab_da0s4 (ANY only)
		#   gvinum rm -r emulab_da1s1
		#
		#   gpart delete -i 4 da0 (ANY only)
		#   gpart destroy -F da1
		#
		my $line = `$GVINUM lv | grep 'volumes:'`;
		chomp($line);
		if (!$line || $line !~ /^0 volumes:/) {
		    return 1;
		}

		my @drives = get_vinum_drives();
		foreach my $slice (@drives) {
		    if (mysystem("$GVINUM rm emulab_$slice $redir")) {
			warn("*** $lv: could not destroy drive emulab_$slice$logmsg\n");
		    }
		    if ($slice eq "${bdisk}s4") {
			if (mysystem("$GPART delete -i 4 $bdisk $redir")) {
			    warn("*** $lv: could not destroy $slice$logmsg\n");
			}
		    } elsif ($slice =~ /^(.*)s1$/) {
			my $disk = $1;
			if ($disk eq $bdisk ||
			    mysystem("$GPART destroy -F $disk $redir")) {
			    warn("*** $lv: could not destroy $slice$logmsg\n");
			}
		    }
		}

		if (mysystem("$GVINUM stop $redir")) {
		    warn("*** $lv: could not stop gvinum$logmsg\n");
		}
		if (mysystem("sed -i -e '/^# added by.*rc.storage/,+1d' /boot/loader.conf")) {
		    warn("*** $lv: could not remove vinum load from /boot/loader.conf\n");
		}
	    }
	}

	return 1;
    }

    return 0;
}

sub mysystem($)
{
    my ($cmd) = @_;
    if (0) {
	print STDERR "CMD: $cmd\n";
    }
    return system($cmd);
}

sub mybacktick($)
{
    my ($cmd) = @_;
    if (0) {
	print STDERR "CMD: $cmd\n";
    }
    return `$cmd`;
}

1;
