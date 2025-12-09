<#
.SYNOPSIS
Compress a source directory, extract to a temp destination, verify contents, delete source files, and write a report. V1

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
    [Parameter(Mandatory = $false)]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$SourceDir="D:\bak",

    [Parameter(Mandatory = $false)]
    [string]$TempDest="D:\tmp",

    [Parameter(Mandatory = $false)]
    [string]$ReportPath="D:\bak\Clean.Log"
)

function dump {             # Write-Log
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$time [$Level] $Message" | Tee-Object -FilePath $ReportPath -Append
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

    write-host "[Environment]::Version"
        [Environment]::Version

    write-host "$PSVersionTable.PSVersion"
        $PSVersionTable.PSVersion

    write-host "$Env:PSModulePath"
        $Env:PSModulePath

    write-host "[system interop info]::FrameworkDescription"
[System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription



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


    function Get-RelativeFileList {
        param(
            [string]$BasePath
        )
        dump "Get-RelativeFileList $SourceDir" "DEBUG"
        $files = Get-ChildItem -Path $BasePath -File -Recurse | 
        ForEach-Object{
             [IO.Path]::GetRelativePath($BasePath, $_.FullName)
        }
        <#ForEach($f in $files) {
             dump "Relative $($f.FullName)" "DEBUG"
            [IO.Path]::GetRelativePath($BasePath, $f.FullName)
        }#>
        return $files
    }

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

     # Optionally, remove any empty directories left in source after deleting files
        dump "Removing empty sub directories from source."
        removeDirectory $SourceDir 
        $finalFileCount = (Get-ChildItem -Path $SourceDir -File -Recurse | Measure-Object).Count
    
        dump ("Remaining files in source directory after cleanup: {0}" -f $finalFileCount)

    move-item -path  $zipName -Destination $SourceDir 

 
    dump "Script completed successfully."

} 
catch {
    dump ("Fatal error: $_") "ERROR"
    exit 1
}