# Flat log analysis
param (
$s="syncthing.log", # source log file
$d="syncthing.Log.csv" # destination csv
)

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
        write-host  $_.ToString()
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
        write-host  $_.ToString()
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
     write-host  $_.ToString()
} | Export-Csv -Path $d -NoTypeInformation