<#
.SYNOPSIS
Compress a source directory, extract to a temp destination, verify contents, delete source files, and write a report. V1.2

VS CODE AI TOOTKIT:
OpenAI GPT-4.1-mini, remote via GitHub
USER PROMPT:
create a script to compress a source directory and all it's files. Then unzip the results to temporary destination. Then compare the results of source with destination. Verify the destination contains each of the source files, and then delete each source file. Write of report of statistics of the files processed.
SYSTEM PROMPT:
write powershell code, add validation of parameters, add checking of output, add error handling
RESULTS:
< 1 second
Token used: 1676 (6719 characters)
Explanation:
Parameters validated via [ValidateScript()] to ensure source exists.
Temp destination folder is created if missing.
Compress-Archive zips the entire source directory contents (files and subfolders).
Archive is extracted to a subfolder inside TempDest (extracted).
File presence check compares relative paths from source and extracted directories.
If verification fails, script errors out.
If verification passes, deletes all source files found (with error handling), removes empty dirs.
Writes all logs and results to a report file with timestamps and severity levels.
Uses dump function for consistent and append-friendly logging.
Handles errors and exits with non-zero code on fatal failures.


.PARAMETER SourceDir
The source directory path to compress.

.PARAMETER TempDest
The temporary destination directory path to extract the archive.

.PARAMETER ReportPath
The path of the report file to write statistics and results.

.EXAMPLE
pwsh .\CompressClean.ps1 -SourceDir "C:\Data" -TempDest "C:\TempExtract" -ReportPath "C:\Report.txt"
#>

param(
    [Parameter(Mandatory = $True)]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$SourceDir="D:\bak",

    [Parameter(Mandatory = $false)]
    [string]$TempDest="D:\tmp",

    [Parameter(Mandatory = $false)]
    [string]$ReportPath
)

$script:ReportContent=""
$ReportName="archived.log"
if(-not($ReportPath)){
    $ReportPath="$SourceDir\$ReportName"
}


function dump {             # Write-Log
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $msg="$time [$Level] $Message" 
    #$msg | Tee-Object -FilePath $ReportPath -Append
    $script:ReportContent= "$script:ReportContent `r`n$msg"
    
    write-host $msg -ForegroundColor Green
    # Write-Output $msg
}



function Get-RelativePath {
    param (
        [string]$relativeTo,
        [string]$path
    )

    # Ensure the paths are fully qualified and use correct directory separators
    if (-not ($relativeTo -like "*\") -and 
        -not ($relativeTo -like "*/")) {
        $relativeTo += "\"
    }

    $uriRelativeTo = New-Object System.Uri($relativeTo)
    $uriPath = New-Object System.Uri($path)

    $relativeUri = $uriRelativeTo.MakeRelativeUri($uriPath)
  
  #  Add-Type -AssemblyName System.Net.Http
  #  $relativePath = [System.Web.HttpUtility]::UrlDecode($relativeUri.ToString())
    $relative2 = $relativeUri -replace "/", "\"

    # Replace forward slashes (Uri format) with the correct Windows system directory separator
    return $relative2 
}



function Get-RelativeFileList {
    param(
        [string]$BasePath
    )
    #dump "Get-RelativeFileList $SourceDir" "DEBUG"
    $files = Get-ChildItem -Path $BasePath -File -Recurse | 
    ForEach-Object{
           # [IO.Path]::GetRelativePath($BasePath, $_.FullName)
           Get-RelativePath $BasePath $_.FullName
    }
    <#ForEach($f in $files) {
            dump "Relative $($f.FullName)" "DEBUG"
        [IO.Path]::GetRelativePath($BasePath, $f.FullName)
    }#>
    return $files
}


function removeDirectory{
param($srcd)
    dump "Removing childitem of $srcd."
    $dirs = Get-ChildItem -Path $srcd -Directory -Recurse | Sort-Object FullName -Descending
    foreach ($dir in $dirs) {
        try {
            if ((Get-ChildItem -Path $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
                Remove-Item -Path $dir.FullName -Force -Recurse -ErrorAction Stop
                dump "Removed directory: $($dir.FullName)"
            }
        }
        catch {
            dump ("Failed to remove directory '{0}': {1}" -f $dir.FullName, $_) "WARNING"
        }
    }
}


# main
try {
    # Clear or create report file
    if(Test-Path $ReportPath) { Clear-Content $ReportPath -ErrorAction Stop }
    else { New-Item -Path $ReportPath -ItemType File -Force | Out-Null }

    dump "Script started."
    dump "Source directory: $SourceDir"
    dump "Temporary destination: $TempDest"
    dump "Report path: $ReportPath"

    # write-host "DotNet [Environment]::Version  $(([Environment]::Version).Major)"

    write-host "PSVersion $(($PSVersionTable).PSVersion)"
    write-host "Framework $([System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription)"



    # Validate TempDest exists or create
    if (-not (Test-Path $TempDest)) {
        dump "Temporary destination folder does not exist. Creating '$TempDest'."
        New-Item -Path $TempDest -ItemType Directory -Force | Out-Null
    }

    # Compress source directory to a zip file in temp folder
    $zipName = Join-Path $TempDest ("archive_{0:yyyyMMddHHmmss}.zip" -f (Get-Date))
    dump "Compressing source directory to '$zipName'."

    try {
        Compress-Archive -Path (Join-Path $SourceDir '*') -DestinationPath $zipName -Force -ErrorAction Stop
        dump "Compression completed successfully."
    }
    catch {
        dump "Error during compression: $_" "ERROR"
        throw $_
    }

    # ZIPPED  all files in the source directory
    $files = Get-ChildItem -Path $SourceDir -Recurse -File
    # Calculate total size of files added to the zip
    foreach ($file in $files) {
        $totalSize += $file.Length
    }
    $zipSize =(get-item -path $zipName).Length
    $msg = "Total size of source files: {0:N2} MB" -f ([math]::Round($totalSize / 1MB, 2))
    dump $msg
    $msg = "Zip size is: {0:N1} MB compressed by {1:N0}% " -f ([math]::Round($zipSize / 1MB, 1)), ([math]::Round(100* (1- $zipSize / $totalSize), 0))
    dump $msg

    # Extract the archive to TempDest\extracted
    $extractPath = Join-Path $TempDest "extracted"
    if (Test-Path $extractPath) {
        dump "Clearing existing extracted directory '$extractPath'."
        Remove-Item -Path $extractPath -Recurse -Force -ErrorAction Stop
    }

    dump "Extracting archive to '$extractPath'."
    try {
        Expand-Archive -Path $zipName -DestinationPath $extractPath -Force -ErrorAction Stop
        dump "Extraction completed successfully."
    }
    catch {
        dump "Error during extraction: $_" "ERROR"
        throw $_
    }

    # Get list of source files and extracted files (relative paths)
    dump "Gathering file lists for comparison."



    $sourceFiles = Get-RelativeFileList -BasePath $SourceDir 
    $extractedFiles = Get-RelativeFileList -BasePath $extractPath

    dump ("Source files found: {0}" -f $sourceFiles.Count)
    dump ("Extracted files found: {0}" -f $extractedFiles.Count)

    # Verify each source file is present in extracted files
    $missingFiles = @()
    foreach ($file in $sourceFiles) {
        if (-not ($extractedFiles -contains $file)) {
            $missingFiles += $file
        }
    }

    if($missingFiles.Count -eq 0) {
        dump "Verification succeeded: All source files are in extracted directory."
    }
    else {
        dump ("Verification failed: {0} files missing after extraction:" -f $missingFiles.Count) "ERROR"
        foreach ($mf in $missingFiles) {
            dump "MISSING FILE: $mf" "ERROR"
        }
        throw "Verification failure: Not all source files were extracted correctly."
    }

    # Delete each source file after verification
    dump "Deleting source files."
    $deleteFailures = @()
    foreach ($relFile in $sourceFiles) {
        $fullPath = Join-Path $SourceDir $relFile
        try {
            Remove-Item -Path $fullPath -Force -ErrorAction Stop
            dump "Deleted $fullPath"
        }
        catch {
            dump ("Failed to delete '{0}': {1}" -f $fullPath, $_) "ERROR"
            $deleteFailures += $relFile
        }
    }

    dump ("Deleted {0} files from source directory." -f ($sourceFiles.Count - $deleteFailures.Count))

    if($deleteFailures.Count -gt 0) {
        dump ("Failed to delete {0} files from source:" -f $deleteFailures.Count) "ERROR"
        foreach ($fail in $deleteFailures) {
            dump "FAILED DELETE: $fail" "ERROR"
        }
    }



     # Optionally, remove any empty directories left in source after deleting files
        dump "Removing empty sub directories from source."
        removeDirectory $SourceDir 
        $finalFileCount = (Get-ChildItem -Path $SourceDir -File -Recurse | Measure-Object).Count
    
        dump ("Remaining files in source directory after cleanup: {0}" -f $finalFileCount)

    move-item -path  $zipName -Destination $SourceDir 

 
    dump "Script completed successfully."
    New-Item -path $ReportPath -Value $script:ReportContent -ItemType File -Force

} 
catch {
    dump ("Fatal error: $_") "ERROR"
    exit 1
}