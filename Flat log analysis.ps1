# Flat log analysis                              v1.0.1
param (
$s="syncthing.log", # source log file
$d="syncthing.Log.csv" # destination csv
,
    # Override the output folder. Default: 'logs' beside this script.
    [string]$LogDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Version = '1.0.1'

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
$base     = Join-Path $LogDirectory ("FlatLogAnalysis_{0}_{1}" -f $hostName, $stamp)
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


$c=Get-Content -Path $s
# $c

# apply regex filters and export to CSV
function showTimestamp{
    $rgx="(?<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}).*ERROR (?<message>.*)"

    $rgx="(?<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})"
    $c | ForEach-Object {
        if ($_ -match $rgx) {
            $ts = $matches['timestamp']
            $msg= $_ -replace $ts,""
            [PSCustomObject]@{
                Timestamp = $ts
                Message = $msg
            }
        write-log  $_.ToString()
        }
    } | Export-Csv -Path $d -NoTypeInformation
}

function simple{
    # simple one word match
    $c | Where-Object { $_ -match "device" } |ForEach-Object {
        if ($_ -match $rgx) {
            [PSCustomObject]@{
                Timestamp = $matches['device']
                Message = $_ 
            }
            
        }
        write-log  $_.ToString()
    } | Export-Csv -Path $d -NoTypeInformation
}

$deviceLookup = [PSCustomObject]@{
            Guid = $G1
            Device=$dv
        }

function getDevice{
    param($guid,$name)
    if ($guid){ # lookup the list and return the name
        
    }
    else { #  build the list first time

    }
}


$time1="(?<timestamp>\d{4}\/\d{2}\/\d{2} \d{2}:\d{2}:\d{2}\.\d{6})" # regex timestamp
$guid1="(?<guid>(([A-Z]|\d){7}-){7}([A-Z]|\d){7})" # Regex for guid
$IP1="(?<IP>\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})" # IP address
# $device='(?<is>(\bis ")(?<Device>\b\S+\b))' # device name
$device='(?<is>( ")(?<Device>\b\S+\b))' # device name
# apply regex filter, and export to CSV

$c | Where-Object { $_ -match $guid1} |ForEach-Object {
    $G1 = $matches['guid']
    if ($_ -match $IP1) {          $IP= $matches['IP']
        if  ($_ -match $time1){    $ts= $matches['timestamp'] }
        if  ($_ -match $device){   $dv= $matches['Device'] } else {$dv=""}
        $msg= $_ -replace $ts,"" -replace $G1,"guid"
        [PSCustomObject]@{
            Guid = $G1
            IP= $IP
            TS=$ts
            Device=$dv
            Message = $msg
        }
        
    }
     write-log  $_.ToString()
} | Export-Csv -Path $d -NoTypeInformation