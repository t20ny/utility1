# Flat log analysis
param (
$s="syncthing.log", # source log file
$d="syncthing.Log.csv" # destination csv
)

$c=Get-Content -Path $s

$rgx="(?<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}).*ERROR (?<message>.*)"


# $c

# apply regex filter, and export to CSV
function showTimestamp{
    $rgx="(?<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})"
    $c | ForEach-Object {
        if ($_ -match $rgx) {
            [PSCustomObject]@{
                Timestamp = $matches['timestamp']
                Message = $_ 
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


$guid1="(?<guid>(([A-Z]|\d){7}-){7}([A-Z]|\d){7})" # Regex for guid
$IP1="(?<IP>\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})" # IP address

# apply regex filter, and export to CSV

$c | Where-Object { $_ -match $guid1} |ForEach-Object {
    $G1 = $matches['guid']
    if ($_ -match $IP1) {
        $IP= $matches['IP']
        [PSCustomObject]@{
            Guid = $G1
            IP= $IP
            TS=$ts
            Message = $_ 
        }
        
    }
     write-host  $_.ToString()
} | Export-Csv -Path $d -NoTypeInformation