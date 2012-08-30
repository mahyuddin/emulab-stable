#
# Script for preparing a vanilla Windows 7 installation for Emulab
#

# First, grab script arguments - I really hate that this must come first
# in a powershell script (before any other executable lines).
param([string]$actionfile, [switch]$debug)

#
# Constants
#
$MAXSLEEP = 1800
$LOGFILE="C:\temp\basesetup.log"
$FAIL = "fail"
$SUCCESS = "success"
$REG_TYPES = @("String", "Dword")


#
# Utility functions
#

# Log to $LOGFILE
Function log($msg) {
	$time = Get-Date -format g
	($time + ": " + $msg) | Out-File -encoding "ASCII" -append $LOGFILE
}

Function debug($msg) {
	if ($debug) {
		log("DEBUG: $msg")
	}
}

Function lograw($msg) {
	$msg | Out-File -encoding "ASCII" -append $LOGFILE
}

Function isNumeric ($x) {
    $x2 = 0
    $isNum = [System.Int32]::TryParse($x, [ref]$x2)
    return $isNum
}

#
# Action execution functions
#

Function log_func($cmdarr) {
	foreach ($logline in $cmdarr) {
		log($logline)
	}

	return $SUCCESS
}

# Create or set an existing registry value.  Create entire key path as required.
# XXX: Update to return powershell errors
Function addreg_func($cmdarr) {
	debug("addreg called with: $cmdarr")

	# set / check args
	if (!$cmdarr -or $cmdarr.count -ne 4) {
		log("addreg called with improper argument list")
		return $FAIL
	}
	$path, $vname, $type, $value = $cmdarr
	$regpath = "Registry::$path"
	if ($REG_TYPES -notcontains $type) {
		log("ERROR: Unknown registry value type specified: $type")
		return $FAIL
	}
	if (!(Test-Path -IsValid -Path $regpath)) {
		log("Invalid registry key specified: '$path'")
		return $FAIL
	}
	
	# Set the value, creating the full key path if necessary
	if (!(Test-Path -Path $regpath)) {
		if (!(New-Item -Path $regpath -Force)) {
			log("Couldn't create registry key path: '$path'")
			return $FAIL
		}
	}
	if (!(New-ItemProperty -Path $regpath -Name $vname `
	      -PropertyType $type -Value $value -Force)) {
		    log("ERROR: Could not set registry value: '$vname' to '$value'")
		    return $FAIL
	    }

	return $SUCCESS
}

Function reboot_func($cmdarr) {
	debug("reboot called with: $cmdarr")

	if ($cmdarr) {
		$force = $cmdarr
	}

	# Reboot ...
	if ($force) {
		"force reboot..." | Out-Host
		#Retart-Computer -Force
	} else {
		"reboot..." | Out-Host
		#Restart-Computer
	}

	return $SUCCESS
}

Function sleep_func($cmdarr) {
	debug("sleep called with: $cmdarr")

	if ($cmdarr.count -lt 1) {
		log("ERROR: Must supply a time to sleep!")
		return $FAIL
	}

	$wtime = $cmdarr[0]
	if (!(isNumeric($wtime)) -or `
	    (0 -gt $wtime) -or `
	    ($MAXSLEEP -lt $wtime))
	{
		log("ERROR: Invalid sleep time: $wtime")
		return $FAIL
	}

	# Sleep...
	Start-Sleep -s $wtime
	
	return $SUCCESS
}

Function runcmd_func($cmdarr) {
	debug("runcmd called with: $cmdarr")

	if ($cmdarr.count -lt 1) {
		log("No command given to run.")
		return $FAIL
	}
	$cmd, $expret = $cmdarr

	# XXX:  Do some sanity checks on command... Implement timeout?
	$cmdout = Invoke-Expression $cmd
	if ($debug) {
		debug("Command output:")
		lograw($cmdout)
	}
	# $null is a special varibale in PS - always null!
	if ($expret -ne $null -and $LASTEXITCODE -ne $expret) {
		log("Command returned unexpected code.")
		return $FAIL
	}

	return $SUCCESS
}

Function getfile_func($cmdarr) {
	debug("getfile called with: $cmdarr")
	$retcode = $FAIL

	if ($cmdarr.count -lt 2) {
		log("URL and local file must be provided.")
		return $FAIL
	}

	$url, $filename = $cmdarr
	if (Test-Path -Path $filename) {
		log("WARNING: Overwriting existing file: $filename")
	}
	# XXX: Timeout?
	try {
		$webclient = New-Object System.Net.WebClient
		$webclient.DownloadFile($url,$filename)
		$retcode = $SUCCESS
	} catch {
		log("Error Trying to download file: $filename: $_")
		$retcode = $FAIL
	}

	return $retcode
}

# Main starts here
if ($actionfile -and !(Test-Path -pathtype leaf $actionfile)) {
	log("Specified action sequence file does not exist: $actionfile")
	exit 1;
} else {
	log("Executing action sequence: $actionfile")
}

# Parse and run through the actions in the input sequence
foreach ($cmdline in (Get-Content -Path $actionfile)) {
	if (!$cmdline -or ($cmdline.startswith("#"))) {
		continue
	}
	$cmd, $argtoks = $cmdline.split()
	$cmdarr = @()
	if ($argtoks) {
		$cmdargs = [string]::join(" ", $argtoks)
		$cmdarr = [regex]::split($cmdargs, '\s*;;\s*')
	}
	$result = $FAIL
	# XXX: Maybe refactor all of this with OOP at some point.
	switch($cmd) {
		"log" {
			$result = log_func($cmdarr)
		}
		"addreg" {
			$result = addreg_func($cmdarr)
		}
		"runcmd" {
			$result = runcmd_func($cmdarr)
		}
		"reboot" {
			$result = reboot_func($cmdarr)
		}
		"sleep" {
			$result = sleep_func($cmdarr)
		}
		"getfile" {
			$result = getfile_func($cmdarr)
		}
		default {
			log("WARNING: Skipping unknown action: $cmd")
			$result = $SUCCESS
		}
	}
	if ($result -eq $FAIL) {
		log("ERROR: Action failed: $cmdline")
		log("Exiting!")
		exit 1
	}
}
