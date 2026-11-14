<#
.SYNOPSIS
    Safely finds and removes junk files (temp files, caches, crash dumps) to free disk space.
.DESCRIPTION
    Default mode is a read-only scan that reports how much space each category uses.
    Use -Clean to actually delete. Only regenerable data is touched: temporary files,
    caches, crash dumps and logs. Documents, downloads, browser profiles, cookies,
    passwords, saved sessions, installed programs and system files are never touched.

    Categories that need elevation are skipped unless the script runs as Administrator.
    Locked or in-use files are skipped silently.
.PARAMETER Clean
    Delete the junk found. Without it the script only reports.
.PARAMETER Yes
    Skip the confirmation prompt (requires -Clean).
.PARAMETER Deep
    Also run Windows component store cleanup (DISM /StartComponentCleanup). Requires
    Administrator and can take several minutes. It never uses /ResetBase.
.PARAMETER IncludeRecycleBin
    Also empty the Recycle Bin. Opt-in because it holds files you deleted yourself.
.PARAMETER CloseApps
    Close running apps (browsers, VS Code, Discord...) that lock cache files without
    asking. Without it the script asks interactively. -Yes never closes apps by itself,
    because that could lose unsaved work.
#>

[CmdletBinding()]
param(
    [switch]$Clean,
    [switch]$Yes,
    [switch]$Deep,
    [switch]$IncludeRecycleBin,
    [switch]$CloseApps
)

. "$PSScriptRoot\lib\common.ps1"
Initialize-ScriptEnvironment -Clear

if ($Yes -and -not $Clean) {
    Write-ErrorMessage "-Yes can only be used together with -Clean."
    exit 2
}

$isAdmin = Test-IsAdministrator

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Format-Size {
    param([Parameter(Mandatory)][double]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return ('{0:N0} B' -f $Bytes)
}

function Test-IsReparsePoint {
    param([Parameter(Mandatory)][IO.FileSystemInfo]$Item)
    return [bool]($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

# Total size of a file or directory, never following junctions or symlinks.
function Get-ItemSize {
    param([Parameter(Mandatory)][IO.FileSystemInfo]$Item)

    if (Test-IsReparsePoint $Item) { return [int64]0 }
    if ($Item -is [IO.FileInfo]) { return [int64]$Item.Length }

    $total = [int64]0
    try {
        foreach ($child in $Item.EnumerateFileSystemInfos()) {
            $total += Get-ItemSize $child
        }
    }
    catch { }
    return $total
}

# Expands a path (wildcards allowed) into existing items.
function Resolve-Targets {
    param([Parameter(Mandatory)][string[]]$Paths)

    $found = [System.Collections.Generic.List[IO.FileSystemInfo]]::new()
    foreach ($path in $Paths) {
        if (-not $path) { continue }
        foreach ($item in @(Get-Item -Path $path -Force -ErrorAction SilentlyContinue)) {
            $found.Add($item)
        }
    }
    return @($found)
}

# Refuses anything that could be a drive root, a profile root or other broad location.
function Test-SafeTarget {
    param([Parameter(Mandatory)][IO.FileSystemInfo]$Item)

    $full = $Item.FullName.TrimEnd('\')
    if ($full.Length -lt 12) { return $false }

    $forbidden = @(
        $env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA, $env:SystemRoot,
        $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData,
        (Join-Path $env:USERPROFILE 'Documents'), (Join-Path $env:USERPROFILE 'Desktop'),
        (Join-Path $env:USERPROFILE 'Downloads'), (Join-Path $env:USERPROFILE 'Pictures')
    ) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') }

    foreach ($path in $forbidden) {
        if ($full -ieq $path) { return $false }
    }
    return $true
}

# Items directly inside the targets whose contents are considered junk.
# Directory targets contribute their children; file targets contribute themselves.
function Get-JunkItems {
    param(
        [Parameter(Mandatory)][string[]]$Paths,
        [double]$MinAgeDays = 0
    )

    $cutoff = (Get-Date).AddDays(-$MinAgeDays)
    $items = [System.Collections.Generic.List[IO.FileSystemInfo]]::new()

    foreach ($target in (Resolve-Targets -Paths $Paths)) {
        if (-not (Test-SafeTarget $target)) { continue }

        if ($target -is [IO.FileInfo]) {
            if ($target.LastWriteTime -le $cutoff) { $items.Add($target) }
            continue
        }
        if (Test-IsReparsePoint $target) { continue }

        try {
            foreach ($child in ([IO.DirectoryInfo]$target).EnumerateFileSystemInfos()) {
                if ($MinAgeDays -gt 0 -and $child.LastWriteTime -gt $cutoff) { continue }
                $items.Add($child)
            }
        }
        catch { }
    }
    return @($items)
}

# Counts a failed delete. "Denied" means access was refused (permissions or security
# software); anything else is treated as the file being in use by a running program.
function Add-DeleteFailure {
    param(
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)]$ErrorRecord
    )

    $Result.Skipped++
    $inner = $ErrorRecord.Exception
    if ($inner.InnerException) { $inner = $inner.InnerException }
    if ($inner -is [UnauthorizedAccessException]) { $Result.Denied++ }
}

# Deletes an item best-effort, file by file, so one locked file never blocks the rest.
# Never follows reparse points. Accumulates freed bytes and skipped (locked) files in $Result.
function Remove-JunkItem {
    param(
        [Parameter(Mandatory)][IO.FileSystemInfo]$Item,
        [Parameter(Mandatory)]$Result
    )

    if (Test-IsReparsePoint $Item) {
        # Removes the link itself, never its target.
        try {
            if ($Item -is [IO.DirectoryInfo]) { [IO.Directory]::Delete($Item.FullName) }
            else { [IO.File]::Delete($Item.FullName) }
        }
        catch { Add-DeleteFailure -Result $Result -ErrorRecord $_ }
        return
    }

    if ($Item -is [IO.FileInfo]) {
        $length = [int64]$Item.Length
        try {
            if ($Item.IsReadOnly) { $Item.IsReadOnly = $false }
            [IO.File]::Delete($Item.FullName)
            $Result.Freed += $length
        }
        catch { Add-DeleteFailure -Result $Result -ErrorRecord $_ }
        return
    }

    $children = @()
    try { $children = @(([IO.DirectoryInfo]$Item).EnumerateFileSystemInfos()) } catch { }
    foreach ($child in $children) { Remove-JunkItem -Item $child -Result $Result }

    # Succeeds only when the directory ended up empty.
    try { [IO.Directory]::Delete($Item.FullName) } catch { }
}

# ---------------------------------------------------------------------------
# Category definitions
# ---------------------------------------------------------------------------

$local = $env:LOCALAPPDATA
$roaming = $env:APPDATA

function New-Category {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string[]]$Paths = @(),
        [double]$MinAgeDays = 0,
        [switch]$NeedsAdmin,
        [scriptblock]$Before,
        [scriptblock]$After
    )
    return [PSCustomObject]@{
        Name = $Name; Paths = $Paths; MinAgeDays = $MinAgeDays
        NeedsAdmin = [bool]$NeedsAdmin; Before = $Before; After = $After
    }
}

$chromiumRoots = @(
    "$local\Google\Chrome\User Data",
    "$local\Microsoft\Edge\User Data",
    "$local\BraveSoftware\Brave-Browser\User Data"
)
$chromiumCachePaths = foreach ($root in $chromiumRoots) {
    foreach ($sub in 'Cache', 'Code Cache', 'GPUCache', 'Service Worker\CacheStorage') {
        "$root\*\$sub"
    }
    "$root\ShaderCache"
    "$root\GrShaderCache"
}

$electronApps = 'Code', 'Discord', 'Slack', 'Microsoft\Teams', 'Spotify'
$electronCachePaths = foreach ($app in $electronApps) {
    foreach ($sub in 'Cache', 'Code Cache', 'GPUCache', 'CachedData') {
        "$roaming\$app\$sub"
    }
}

$categories = @(
    (New-Category -Name 'User temp files (older than 1 day)' -MinAgeDays 1 -Paths @($env:TEMP)),
    (New-Category -Name 'Windows temp files (older than 1 day)' -MinAgeDays 1 -NeedsAdmin -Paths @("$env:SystemRoot\Temp")),
    (New-Category -Name 'Windows Update download cache' -NeedsAdmin `
        -Paths @("$env:SystemRoot\SoftwareDistribution\Download") `
        -Before { foreach ($s in 'wuauserv', 'bits') { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue } } `
        -After  { foreach ($s in 'bits', 'wuauserv') { Start-Service -Name $s -ErrorAction SilentlyContinue } }),
    (New-Category -Name 'Delivery Optimization cache' -NeedsAdmin `
        -Paths @("$env:SystemRoot\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache")),
    (New-Category -Name 'Crash dumps and error reports' -Paths @(
        "$local\CrashDumps",
        "$local\Microsoft\Windows\WER\ReportArchive",
        "$local\Microsoft\Windows\WER\ReportQueue",
        "$env:ProgramData\Microsoft\Windows\WER\ReportArchive",
        "$env:ProgramData\Microsoft\Windows\WER\ReportQueue",
        "$env:SystemRoot\Minidump",
        "$env:SystemRoot\MEMORY.DMP")),
    (New-Category -Name 'Thumbnail and icon cache' -Paths @(
        "$local\Microsoft\Windows\Explorer\thumbcache_*.db",
        "$local\Microsoft\Windows\Explorer\iconcache_*.db")),
    (New-Category -Name 'Browser caches (Chrome, Edge, Brave, Firefox)' -Paths (@($chromiumCachePaths) + @(
        "$local\Mozilla\Firefox\Profiles\*\cache2"))),
    (New-Category -Name 'App caches (VS Code, Discord, Slack, Teams, Spotify)' -Paths @($electronCachePaths)),
    (New-Category -Name 'Graphics shader caches' -Paths @(
        "$local\D3DSCache",
        "$local\NVIDIA\DXCache",
        "$local\NVIDIA\GLCache",
        "$local\AMD\DxCache")),
    (New-Category -Name 'Developer package caches (npm, pip, NuGet, Yarn)' -Paths @(
        "$local\npm-cache\_cacache",
        "$local\pip\Cache",
        "$local\NuGet\v3-cache",
        "$local\Yarn\Cache"))
)

# ---------------------------------------------------------------------------
# Scan
# ---------------------------------------------------------------------------

function Get-FreeSpace {
    $drive = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':')) -ErrorAction SilentlyContinue
    if ($drive) { return [int64]$drive.Free }
    return [int64]0
}

Write-Section "=== Windows Junk Cleaner ==="
if ($Clean) {
    Write-Host "Mode: CLEAN (files will be deleted)" -ForegroundColor $script:ColorWarning
}
else {
    Write-Host "Mode: SCAN ONLY (nothing is deleted; use -Clean to remove)" -ForegroundColor $script:ColorMuted
}
if (-not $isAdmin) {
    Write-Host "Not running as Administrator: system categories will be skipped." -ForegroundColor $script:ColorMuted
}
Write-Host ""

$plan = [System.Collections.Generic.List[object]]::new()
$grandTotal = [int64]0

foreach ($category in $categories) {
    if ($category.NeedsAdmin -and -not $isAdmin) {
        Write-Host ("  [skipped] {0} (needs Administrator)" -f $category.Name) -ForegroundColor $script:ColorMuted
        continue
    }

    $items = @(Get-JunkItems -Paths $category.Paths -MinAgeDays $category.MinAgeDays)
    $size = [int64]0
    foreach ($item in $items) { $size += Get-ItemSize $item }

    $plan.Add([PSCustomObject]@{ Category = $category; Items = $items; Size = $size })
    $grandTotal += $size

    $color = if ($size -gt 0) { $script:ColorSuccess } else { $script:ColorMuted }
    Write-Host ("  {0,-58} {1,12}" -f $category.Name, (Format-Size $size)) -ForegroundColor $color
}

$recycleSize = [int64]0
if ($IncludeRecycleBin) {
    try {
        $shell = New-Object -ComObject Shell.Application
        $bin = $shell.Namespace(10)
        foreach ($entry in $bin.Items()) { $recycleSize += [int64]$entry.Size }
    }
    catch { }
    $grandTotal += $recycleSize
    Write-Host ("  {0,-58} {1,12}" -f 'Recycle Bin', (Format-Size $recycleSize)) -ForegroundColor $script:ColorSuccess
}

Write-Host ""
Write-Host ("Reclaimable space: {0}" -f (Format-Size $grandTotal)) -ForegroundColor $script:ColorPrimary
if ($Deep -and -not $isAdmin) {
    Write-WarningMessage "-Deep requires Administrator; component store cleanup will be skipped."
}

if (-not $Clean) {
    Write-Host ""
    Write-Host "Run again with -Clean to delete the items above." -ForegroundColor $script:ColorMuted
    exit 0
}

# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------

if ($grandTotal -le 0 -and -not ($Deep -and $isAdmin)) {
    Write-Success "Nothing to clean."
    exit 0
}

Write-Host ""
if (-not (Confirm-Action -Prompt "Delete the junk listed above?" -Yes:$Yes)) {
    Write-Host "Cancelled. Nothing was deleted." -ForegroundColor $script:ColorWarning
    exit 0
}

# Apps that keep their cache files open while running.
$lockingApps = 'chrome', 'msedge', 'brave', 'firefox', 'Code', 'Discord', 'slack', 'Teams', 'ms-teams', 'Spotify'
$runningProcesses = @(Get-Process -Name $lockingApps -ErrorAction SilentlyContinue)
$closedApps = @()
if ($runningProcesses.Count -gt 0) {
    $runningNames = @($runningProcesses | Select-Object -ExpandProperty ProcessName -Unique | Sort-Object)
    Write-Host ""
    Write-WarningMessage ("These apps are running and lock their cache files: {0}" -f ($runningNames -join ', '))
    Write-Host "Closing them lets their caches be fully deleted. Unsaved work in them could be lost." -ForegroundColor $script:ColorMuted

    $shouldClose = $CloseApps
    if (-not $shouldClose -and -not [Console]::IsInputRedirected) {
        $shouldClose = Confirm-Action -Prompt "Close these apps now?"
    }

    if ($shouldClose) {
        Write-Host "Closing apps..." -ForegroundColor $script:ColorMuted
        foreach ($process in $runningProcesses) {
            try { [void]$process.CloseMainWindow() } catch { }
        }

        # Give them a few seconds to exit cleanly, then force whatever remains.
        $ids = @($runningProcesses | ForEach-Object { $_.Id })
        $deadline = (Get-Date).AddSeconds(8)
        do {
            Start-Sleep -Milliseconds 500
            $remaining = @(Get-Process -Id $ids -ErrorAction SilentlyContinue)
        } while ($remaining.Count -gt 0 -and (Get-Date) -lt $deadline)

        foreach ($process in $remaining) {
            try { Stop-Process -Id $process.Id -Force -ErrorAction Stop } catch { }
        }
        Start-Sleep -Seconds 1

        $stillRunning = @(Get-Process -Id $ids -ErrorAction SilentlyContinue)
        $closedApps = @($runningNames)
        if ($stillRunning.Count -gt 0) {
            Write-WarningMessage ("Could not close: {0}" -f (($stillRunning | Select-Object -ExpandProperty ProcessName -Unique) -join ', '))
        }
    }
}

$freeBefore = Get-FreeSpace
$result = [PSCustomObject]@{ Freed = [int64]0; Skipped = 0; Denied = 0 }
$report = [System.Collections.Generic.List[object]]::new()
Write-Host ""

foreach ($entry in $plan) {
    if ($entry.Items.Count -eq 0) { continue }
    Write-Host ("Cleaning {0}..." -f $entry.Category.Name) -ForegroundColor $script:ColorMuted
    $freedBefore = $result.Freed
    $skippedBefore = $result.Skipped
    $deniedBefore = $result.Denied

    if ($entry.Category.Before) { & $entry.Category.Before }
    try {
        foreach ($item in $entry.Items) { Remove-JunkItem -Item $item -Result $result }
    }
    finally {
        if ($entry.Category.After) { & $entry.Category.After }
    }

    $report.Add([PSCustomObject]@{
        Name = $entry.Category.Name
        Found = $entry.Size
        Freed = $result.Freed - $freedBefore
        Skipped = $result.Skipped - $skippedBefore
        Denied = $result.Denied - $deniedBefore
    })
}
$freed = $result.Freed
$skippedInUse = $result.Skipped

if (Test-CommandAvailable pnpm) {
    Write-Host "Pruning unreferenced pnpm store packages..." -ForegroundColor $script:ColorMuted
    & pnpm store prune 2>&1 | Out-Null
}

if ($IncludeRecycleBin) {
    Write-Host "Emptying Recycle Bin..." -ForegroundColor $script:ColorMuted
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        $freed += $recycleSize
    }
    catch {
        Write-WarningMessage "Could not empty the Recycle Bin: $($_.Exception.Message)"
    }
}

if ($Deep -and $isAdmin) {
    Write-Host "Running Windows component store cleanup (this can take several minutes)..." -ForegroundColor $script:ColorMuted
    & dism.exe /Online /Cleanup-Image /StartComponentCleanup | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-WarningMessage "DISM component cleanup exited with code $LASTEXITCODE."
    }
}

$freeAfter = Get-FreeSpace
Write-Host ""
Write-Section "=== Result ==="
foreach ($line in $report) {
    $left = [Math]::Max([int64]0, $line.Found - $line.Freed)
    if ($line.Skipped -eq 0) {
        Write-Host ("  [OK]      {0,-56} {1,10} deleted" -f $line.Name, (Format-Size $line.Freed)) -ForegroundColor $script:ColorSuccess
    }
    else {
        $reason = if ($line.Denied -gt 0 -and $line.Denied -ge ($line.Skipped / 2)) { "{0} file(s) access denied" -f $line.Denied } else { "{0} file(s) in use" -f $line.Skipped }
        if ($line.Freed -gt 0) {
            Write-Host ("  [PARTIAL] {0,-56} {1,10} deleted, {2} left ({3})" -f $line.Name, (Format-Size $line.Freed), (Format-Size $left), $reason) -ForegroundColor $script:ColorWarning
        }
        else {
            Write-Host ("  [NOT DELETED] {0,-52} {1} left ({2})" -f $line.Name, (Format-Size $left), $reason) -ForegroundColor $script:ColorError
        }
    }
}

Write-Host ""
if ($freed -gt 0) {
    Write-Success ("Deleted {0} of {1} found." -f (Format-Size $freed), (Format-Size $grandTotal))
}
else {
    Write-Host "Nothing could be deleted: all the files found were in use." -ForegroundColor $script:ColorError
}
if ($skippedInUse -gt 0) {
    Write-Host ("{0} file(s) could not be deleted and were left in place." -f $skippedInUse) -ForegroundColor $script:ColorWarning
    if ($result.Denied -gt 0) {
        Write-Host ("{0} of them returned 'access denied' even though you own them. This is usually security software" -f $result.Denied) -ForegroundColor $script:ColorMuted
        Write-Host "(antivirus or similar) protecting those folders, e.g. browser profile data. The script does not bypass it." -ForegroundColor $script:ColorMuted
        Write-Host "Clear those caches from the browser itself (Ctrl+Shift+Del > Cached images and files)," -ForegroundColor $script:ColorMuted
        Write-Host "or exclude/pause the protection in your antivirus yourself and run again." -ForegroundColor $script:ColorMuted
    }
    $stillOpen = @(Get-Process -Name $lockingApps -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ProcessName -Unique | Sort-Object)
    if ($stillOpen.Count -gt 0) {
        Write-Host ("Still running: {0}. Close them and run again, or use -CloseApps." -f ($stillOpen -join ', ')) -ForegroundColor $script:ColorMuted
    }
    else {
        Write-Host "Some files are held by other processes or services; a reboot or running as Administrator may release them." -ForegroundColor $script:ColorMuted
    }
}
if ($closedApps.Count -gt 0) {
    Write-Host ("Apps that were closed: {0}. Reopen them if you need them." -f ($closedApps -join ', ')) -ForegroundColor $script:ColorMuted
}
if ($freeBefore -gt 0) {
    Write-Host ("Free space on {0}: {1} -> {2}" -f $env:SystemDrive, (Format-Size $freeBefore), (Format-Size $freeAfter)) -ForegroundColor $script:ColorPrimary
}
