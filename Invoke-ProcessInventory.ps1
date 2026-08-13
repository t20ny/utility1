<#
.SYNOPSIS
    Process Inventory Worker - collects a full inventory of running processes.

.DESCRIPTION
    Enumerates every running process on the local server and reports, per process:
        - Process name and PID
        - Executable path
        - Owning Windows service(s), if the process hosts any (the "caller")
        - Account the process is running under
        - Vendor, gathered from local evidence in priority order:
            1. Authenticode signature subject (signed publisher)
            2. Executable VersionInfo CompanyName
            3. Matching registry uninstall entry Publisher
        - Website, from the matching registry uninstall entry (URLInfoAbout /
          HelpLink) when available. Blank entries are enriched later via
          internet research (performed off-server).
        - Install date, gathered from local evidence in priority order:
            1. Matching registry uninstall entry InstallDate
            2. Executable file CreationTime (fallback, flagged as such)

    Outputs (written to the .\logs sub-directory, timestamped):
        - ProcessInventory_<host>_<timestamp>.csv    (data)
        - ProcessInventory_<host>_<timestamp>.html   (readable report)
        - ProcessInventory_<host>_<timestamp>.log    (verbose run log)

    Read-only: makes no changes to the system. No internet access required.

.NOTES
    Project : ProcessInventory
    Author  : Claude ( t20ny )
    Version : 1.0.0  (2026-08-05)  Initial release.
    Policy  : Designed for ExecutionPolicy RemoteSigned (run a local copy).

.EXAMPLE
    .\Invoke-ProcessInventory.ps1
    Runs the inventory and writes CSV/HTML/log into .\logs
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

$stamp    = Get-Date -Format 'yyyyMMdd_HHmmss'
$hostName = $env:COMPUTERNAME
$base     = Join-Path $LogDirectory ("ProcessInventory_{0}_{1}" -f $hostName, $stamp)
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

Write-Log "Process Inventory Worker v$($script:Version) starting on $hostName"
Write-Log "User context : $env:USERDOMAIN\$env:USERNAME"
Write-Log "PowerShell   : $($PSVersionTable.PSVersion)"
Write-Log "Output base  : $base"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Log "Not running elevated - owner/path details for system processes may be incomplete. Re-run in an elevated PowerShell for full coverage." 'WARN'
}

# --- Build registry install-info index (once) --------------------------------
Write-Log "Indexing installed-software registry entries..."
$uninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$installIndex = @()
foreach ($root in $uninstallRoots) {
    try {
        $entries = Get-ItemProperty -Path $root -ErrorAction SilentlyContinue
        foreach ($e in $entries) {
            $loc = $null
            if ($e.PSObject.Properties['InstallLocation'] -and $e.InstallLocation) {
                $loc = ($e.InstallLocation).TrimEnd('\')
            }
            $installIndex += [pscustomobject]@{
                DisplayName     = if ($e.PSObject.Properties['DisplayName'])  { $e.DisplayName }  else { $null }
                Publisher       = if ($e.PSObject.Properties['Publisher'])    { $e.Publisher }    else { $null }
                InstallLocation = $loc
                InstallDate     = if ($e.PSObject.Properties['InstallDate'])  { $e.InstallDate }  else { $null }
                URLInfoAbout    = if ($e.PSObject.Properties['URLInfoAbout']) { $e.URLInfoAbout } else { $null }
                HelpLink        = if ($e.PSObject.Properties['HelpLink'])     { $e.HelpLink }     else { $null }
                DisplayIcon     = if ($e.PSObject.Properties['DisplayIcon'])  { $e.DisplayIcon }  else { $null }
            }
        }
    } catch {
        Write-Log "Registry read issue under $root : $($_.Exception.Message)" 'WARN'
    }
}
$installIndexWithLoc = @($installIndex | Where-Object { $_.InstallLocation })
Write-Log ("Indexed {0} uninstall entries ({1} with InstallLocation)." -f $installIndex.Count, $installIndexWithLoc.Count)

function Find-InstallEntry {
    param([string]$ExePath)
    if (-not $ExePath) { return $null }
    # Best match: longest InstallLocation that is a prefix of the exe path.
    $best = $null; $bestLen = 0
    foreach ($entry in $installIndexWithLoc) {
        $loc = $entry.InstallLocation
        if ($loc.Length -gt $bestLen -and $ExePath.StartsWith($loc, [StringComparison]::OrdinalIgnoreCase)) {
            $best = $entry; $bestLen = $loc.Length
        }
    }
    if ($best) { return $best }
    # Fallback: DisplayIcon pointing at the same exe.
    foreach ($entry in $installIndex) {
        if ($entry.DisplayIcon -and ($entry.DisplayIcon -split ',')[0].Trim('"') -ieq $ExePath) { return $entry }
    }
    return $null
}

function Convert-InstallDate {
    param($Raw)
    if (-not $Raw) { return $null }
    $s = "$Raw".Trim()
    if ($s -match '^\d{8}$') {
        try { return [datetime]::ParseExact($s, 'yyyyMMdd', $null).ToString('yyyy-MM-dd') } catch { }
    }
    try { return ([datetime]$s).ToString('yyyy-MM-dd') } catch { return $s }
}

# --- Map services to PIDs (once) ---------------------------------------------
Write-Log "Mapping Windows services to process IDs..."
$serviceMap = @{}
try {
    Get-CimInstance Win32_Service -ErrorAction Stop |
        Where-Object { $_.ProcessId -gt 0 } |
        ForEach-Object {
            if (-not $serviceMap.ContainsKey([uint32]$_.ProcessId)) { $serviceMap[[uint32]$_.ProcessId] = @() }
            $serviceMap[[uint32]$_.ProcessId] += $_.Name
        }
    Write-Log ("Mapped services across {0} distinct PIDs." -f $serviceMap.Count)
} catch {
    Write-Log "Service mapping failed: $($_.Exception.Message)" 'WARN'
}

# --- Signature cache (many processes share the same exe) ----------------------
$sigCache = @{}
function Get-SignerName {
    param([string]$ExePath)
    if (-not $ExePath -or -not (Test-Path -LiteralPath $ExePath)) { return $null }
    if ($sigCache.ContainsKey($ExePath)) { return $sigCache[$ExePath] }
    $signer = $null
    try {
        $sig = Get-AuthenticodeSignature -LiteralPath $ExePath -ErrorAction Stop
        if ($sig.SignerCertificate) {
            $cn = ($sig.SignerCertificate.Subject -split ',') |
                  Where-Object { $_.Trim() -like 'CN=*' } | Select-Object -First 1
            if ($cn) { $signer = $cn.Trim().Substring(3).Trim('"') }
            if ($sig.Status -ne 'Valid') { $signer = "$signer [sig:$($sig.Status)]" }
        }
    } catch { }
    $sigCache[$ExePath] = $signer
    return $signer
}

# --- Collect processes --------------------------------------------------------
Write-Log "Enumerating running processes (Win32_Process)..."
$cimProcs = Get-CimInstance Win32_Process
Write-Log ("Found {0} running processes." -f $cimProcs.Count)

$rows = New-Object System.Collections.Generic.List[object]
$i = 0
foreach ($p in $cimProcs) {
    $i++
    Write-Progress -Activity 'Process inventory' -Status "$($p.Name) (PID $($p.ProcessId))" -PercentComplete ([int](100 * $i / [math]::Max(1,$cimProcs.Count)))

    $exePath = $p.ExecutablePath

    # Account (owner)
    $account = $null
    try {
        $owner = Invoke-CimMethod -InputObject $p -MethodName GetOwner -ErrorAction Stop
        if ($owner.ReturnValue -eq 0 -and $owner.User) { $account = "$($owner.Domain)\$($owner.User)" }
    } catch { }
    if (-not $account) { $account = '(access denied / system)' }

    # Owning service(s) - the "caller"
    $services = $null
    if ($serviceMap.ContainsKey([uint32]$p.ProcessId)) { $services = ($serviceMap[[uint32]$p.ProcessId] -join '; ') }

    # File version info
    $company = $null; $description = $null; $fileVersion = $null
    if ($exePath -and (Test-Path -LiteralPath $exePath)) {
        try {
            $vi = (Get-Item -LiteralPath $exePath -ErrorAction Stop).VersionInfo
            $company     = $vi.CompanyName
            $description = $vi.FileDescription
            $fileVersion = $vi.ProductVersion
        } catch {
            Write-Log "VersionInfo failed for $exePath : $($_.Exception.Message)" 'WARN'
        }
    }

    # Signature
    $signer = Get-SignerName -ExePath $exePath

    # Registry install entry
    $reg = Find-InstallEntry -ExePath $exePath

    # Vendor: signer > CompanyName > registry Publisher
    $vendor = $null; $vendorSource = $null
    if     ($signer)  { $vendor = $signer;        $vendorSource = 'Signature' }
    elseif ($company) { $vendor = $company;       $vendorSource = 'VersionInfo' }
    elseif ($reg -and $reg.Publisher) { $vendor = $reg.Publisher; $vendorSource = 'Registry' }
    else   { $vendorSource = 'Unknown - needs enrichment' }

    # Website: registry only at this stage; blank = enrich later
    $website = $null
    if ($reg) {
        if     ($reg.URLInfoAbout) { $website = $reg.URLInfoAbout }
        elseif ($reg.HelpLink)     { $website = $reg.HelpLink }
    }

    # Install date: registry InstallDate > exe CreationTime
    $installDate = $null; $installDateSource = $null
    if ($reg -and $reg.InstallDate) {
        $installDate = Convert-InstallDate $reg.InstallDate
        $installDateSource = 'Registry'
    } elseif ($exePath -and (Test-Path -LiteralPath $exePath)) {
        try {
            $installDate = (Get-Item -LiteralPath $exePath).CreationTime.ToString('yyyy-MM-dd')
            $installDateSource = 'FileCreated'
        } catch { }
    }

    $rows.Add([pscustomobject]@{
        Name              = $p.Name
        PID               = $p.ProcessId
        Path              = $exePath
        OwningService     = $services
        Account           = $account
        Vendor            = $vendor
        VendorSource      = $vendorSource
        Website           = $website
        InstallDate       = $installDate
        InstallDateSource = $installDateSource
        Product           = if ($reg) { $reg.DisplayName } else { $null }
        Description       = $description
        FileVersion       = $fileVersion
        CommandLine       = $p.CommandLine
    })
}
Write-Progress -Activity 'Process inventory' -Completed

# --- CSV ----------------------------------------------------------------------
$sorted = $rows | Sort-Object Name, PID
$sorted | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
Write-Log "CSV written : $csvFile"

# --- HTML ----------------------------------------------------------------------
$needsEnrich = @($sorted | Where-Object { -not $_.Vendor -or -not $_.Website }).Count
$style = @"
<style>
 body{font-family:Segoe UI,Arial,sans-serif;margin:20px;color:#222}
 h1{font-size:20px} .meta{color:#555;margin-bottom:12px}
 table{border-collapse:collapse;width:100%;font-size:12px}
 th{background:#1a3c6e;color:#fff;text-align:left;padding:6px;position:sticky;top:0}
 td{border-bottom:1px solid #ddd;padding:5px;vertical-align:top}
 tr:nth-child(even){background:#f5f7fa}
 .warn{background:#fff3cd}
</style>
"@
$header = "<h1>Process Inventory - $hostName</h1><div class='meta'>Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Worker v$($script:Version) | $($sorted.Count) processes | $needsEnrich rows pending vendor/website enrichment (highlighted)</div>"
$tableRows = foreach ($r in $sorted) {
    $cls = if (-not $r.Vendor -or -not $r.Website) { " class='warn'" } else { '' }
    $cells = foreach ($col in 'Name','PID','Path','OwningService','Account','Vendor','Website','InstallDate','Product') {
        $v = [System.Net.WebUtility]::HtmlEncode([string]$r.$col)
        "<td>$v</td>"
    }
    "<tr$cls>$($cells -join '')</tr>"
}
$html = @"
<!DOCTYPE html><html><head><meta charset='utf-8'><title>Process Inventory - $hostName</title>$style</head><body>
$header
<table><tr><th>Name</th><th>PID</th><th>Path</th><th>Owning Service</th><th>Account</th><th>Vendor</th><th>Website</th><th>Install Date</th><th>Product</th></tr>
$($tableRows -join "`n")
</table></body></html>
"@
Set-Content -Path $htmlFile -Value $html -Encoding UTF8
Write-Log "HTML written: $htmlFile"

# --- Summary --------------------------------------------------------------------
Write-Log ("Summary: {0} processes | {1} with vendor from signature | {2} from version info | {3} from registry | {4} unknown." -f `
    $sorted.Count,
    @($sorted | Where-Object VendorSource -eq 'Signature').Count,
    @($sorted | Where-Object VendorSource -eq 'VersionInfo').Count,
    @($sorted | Where-Object VendorSource -eq 'Registry').Count,
    @($sorted | Where-Object VendorSource -like 'Unknown*').Count)
Write-Log ("{0} rows need vendor/website enrichment (done off-server after log sync)." -f $needsEnrich)
Write-Log "Process Inventory Worker completed successfully."
exit 0
