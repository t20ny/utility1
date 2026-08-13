<#
 this script will capture all network activity            v1.0.0
 every 30 seconds and output to log file as a baseline.
 Then after running for 10 minutes it prompt user to insert usb dongle. It then captures another 10 minutes of activity.
 When it stops after 20 minutes, it analyse the log file.
 Finally it will show a summary report of baseline and after. It will highligh any new network connection found.
 If any new connection found it will drill to details of the exectutable.
#>


<#start the logging
$logFile = "network_activity_log.txt"
#>


[CmdletBinding()]
param(
    # Override the output folder. Default: 'logs' beside this script.
    [string]$LogDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Version = '1.0.0'

# --- Paths and log setup -----------------------------------------------------
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $LogDirectory) { $LogDirectory = Join-Path $scriptRoot 'logs' }
if (-not (Test-Path $LogDirectory)) { New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null }


# --- Paths and log setup -----------------------------------------------------
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $LogDirectory) { $LogDirectory = Join-Path $scriptRoot 'logs' }
if (-not (Test-Path $LogDirectory)) { New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null }

$stamp    = Get-Date -Format 'yyyyMMdd_HHmmss'
$hostName = $env:COMPUTERNAME
$base     = Join-Path $LogDirectory ("PortActivity_{0}_{1}" -f $hostName, $stamp)
$logFile  = "$base.log"
$csvFile  = "$base.csv"
$htmlFile = "$base.html"

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Level, $Message
    Add-Content -Path $logFile -Value $line
    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        default { Write-Host $line }
    }
}

function logNetworkActivity {
    param (
        [string]$logFile,
        [int]$durationMinutes = 10,
        [int]$intervalSeconds = 30
    )

    $iterations = ($durationMinutes * 60) / $intervalSeconds
    for ($i=0; $i -lt 20; $i++) {
        # do a netstat
        NETSTAT.EXE -ano >> $logFile
        # get the process name and path of the executable
        Get-NetTCPConnection | ForEach-Object { Get-Process -Id $_.OwningProcess } | Select-Object OwningProcess, Name, Path >> $logFile

        # get the network connection details (local and remote IP, port, protocol)
        Get-NetTCPConnection | Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess >> $logFile

        Start-Sleep -Seconds 30
    }

}

function test1 {
     param ($logFile = "network_activity_log.txt")
    logNetworkActivity -logFile $logFile -durationMinutes 10 -intervalSeconds 30


    # prompt userr to insert usb dongle
    $msg = "Please insert the USB dongle now. Press Enter after inserting the dongle to continue logging."
    Add-Content -Path $logFile -Value $msg
    Write-log $msg
    Read-Host "Press Enter to continue"
}


# continue the logging
function test2 {
    param(
        [string]$logFile="network_activity_log2.txt",
        [int]$durationMinutes = 10,
        [int]$intervalSeconds = 30
    )
    logNetworkActivity -logFile $logFile -durationMinutes 10 -intervalSeconds 30
}



function analyse1 {
     param (
    $logFile = "network_activity_log.txt"
     )

    # analyze the log file
    $logContent = Get-Content -Path $logFile
    # split the log content into baseline and after sections
    $baselineSection = $logContent[0..($logContent.IndexOf($msg) - 1)]
    $afterSection = $logContent[($logContent.IndexOf($msg) + 1)..($logContent.Length - 1)]       

    # extract the network connections from baseline and after sections
    $baselineConnections = $baselineSection | Select-String -Pattern "LocalAddress" | ForEach-Object { $_.Line }
    $afterConnections = $afterSection | Select-String -Pattern "LocalAddress" | ForEach-Object { $_.Line }  

    # find new connections in after section that are not in baseline
    $newConnections = $afterConnections | Where-Object { $_ -notin $baselineConnections }
    # show summary report
    Write-log "Summary Report:"
    Write-log "Baseline Connections:"
    $baselineConnections | ForEach-Object { Write-log $_ }
    Write-log "After Connections:"
    $afterConnections | ForEach-Object { Write-log $_ }
    if ($newConnections.Count -gt 0) {
        Write-log "New Connections Found:"
        $newConnections | ForEach-Object { Write-log $_ }
        # drill down to details of the executable for new connections
        foreach ($connection in $newConnections) {
            $processId = ($connection -split "\s+")[5] # assuming OwningProcess is the 6th column
            $processInfo = Get-Process -Id $processId | Select-Object Name, Path
            Write-log "Details for new connection with Process ID $processId "
            Write-log "Name: $($processInfo.Name)"
            Write-log "Path: $($processInfo.Path)"
        }
    } else {
        Write-log "No new connections found."
    }
}


function analyse2 {
    # this function can be used to compare the two log files and find any new connections in the second log file that are not in the first log file.

    $logContent1 = Get-Content -Path $logFile1
    $logContent2 = Get-Content -Path $logFile2

    $connections1 = $logContent1 | Select-String -Pattern "LocalAddress" | ForEach-Object { $_.Line }
    $connections2 = $logContent2 | Select-String -Pattern "LocalAddress" | ForEach-Object { $_.Line }

    $newConnections = $connections2 | Where-Object { $_ -notin $connections1 }
    if ($newConnections.Count -gt 0) {
        Write-log "New Connections Found in second log file:"
        $newConnections | ForEach-Object { Write-log $_ }
        foreach ($connection in $newConnections) {
            $processId = ($connection -split "\s+")[5] # assuming OwningProcess is the 6th column
            $processInfo = Get-Process -Id $processId | Select-Object Name, Path
            Write-log "Details for new connection with Process ID $processId "
            Write-log "Name: $($processInfo.Name)"
            Write-log "Path: $($processInfo.Path)"
        }
    } else {
        Write-log "No new connections found in second log file."
    }
}




# MAIN SECTION
$dtstamp = Get-Date -Format "yyyyMMdd.HHmm"
$logFile1 = "network_activity_$dtstamp"+"01.txt"
$logFile2 = "network_activity_$dtstamp"+"02.txt"


# driver 1
# test1
# analyse1



# driver 2
test2 $logFile1
analyse2 $logFile1 $logFile2




# end of script

