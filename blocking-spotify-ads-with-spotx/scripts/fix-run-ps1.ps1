# Applies the known fix to a freshly downloaded SpotX run.ps1.
#
# SpotX aborts at run.ps1:5829 with "另一个进程正在使用此文件" because
# `Get-ChildItem | Rename-Item` renames a file while its own directory
# enumeration is still open. -ErrorAction Stop kills the whole script before
# any binary patching happens, leaving the client installed but unpatched.
#
# Idempotent: reports a no-op if already fixed.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path)) { throw "run.ps1 not found: $Path" }

$Path = (Resolve-Path -LiteralPath $Path).Path
$orig = "$Path.orig"

# --- already fixed? -------------------------------------------------------
$text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
if ($text -match '\$v8Snapshots\s*=') {
    Write-Host "Already fixed - no change made: $Path"
    exit 0
}

$nl = if ($text -match "`r`n") { "`r`n" } else { "`n" }
$lines = [IO.File]::ReadAllLines($Path, [Text.Encoding]::UTF8)

# --- locate the two lines to replace --------------------------------------
$targetStmt = "Rename-Item -NewName { 'V' + `$_.Name.Substring(1) } -ErrorAction Stop"
$idx = -1
for ($i = 0; $i -lt $lines.Length; $i++) {
    if ($lines[$i].Trim() -eq $targetStmt.Trim()) { $idx = $i; break }
}

if ($idx -lt 0) {
    throw "Target line not found. Upstream run.ps1 changed - inspect the 'v8_context_snapshot' rename manually and update this script."
}

if ($idx -eq 0) { throw "Unexpected file layout: target line is the first line." }

$prev = $lines[$idx - 1].Trim()
if ($prev -notlike "Get-ChildItem -LiteralPath *v8_context_snapshot*.bin' -File |") {
    throw "Preceding line is not the expected Get-ChildItem pipeline: $prev"
}

# --- back up, then splice ------------------------------------------------
if (-not (Test-Path -LiteralPath $orig)) { Copy-Item -LiteralPath $Path -Destination $orig }
Write-Host "Backup written: $orig"

$indent = ($lines[$idx - 1] -replace '\S.*$', '')
$replacement = @(
    "${indent}`$v8Snapshots = @(Get-ChildItem -LiteralPath `$spotifyDirectory -Filter 'v8_context_snapshot*.bin' -File)"
    "${indent}foreach (`$v8Snapshot in `$v8Snapshots) {"
    "${indent}    Rename-Item -LiteralPath `$v8Snapshot.FullName -NewName ('V' + `$v8Snapshot.Name.Substring(1)) -ErrorAction Stop"
    "${indent}}"
)

$out = New-Object 'System.Collections.Generic.List[string]'
if ($idx -ge 2) { $out.AddRange([string[]]$lines[0..($idx - 2)]) }
$out.AddRange([string[]]$replacement)
if ($idx + 1 -lt $lines.Length) { $out.AddRange([string[]]$lines[($idx + 1)..($lines.Length - 1)]) }

# Preserve original encoding: UTF-8 without BOM, original line endings.
[IO.File]::WriteAllText($Path, ($out -join $nl) + $nl, (New-Object Text.UTF8Encoding($false)))
Write-Host "Patched line $($idx + 1)."

# --- verify the result parses --------------------------------------------
$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errs)
if ($errs.Count -gt 0) {
    Write-Warning "Patched file has $($errs.Count) syntax error(s). Restoring backup."
    Copy-Item -LiteralPath $orig -Destination $Path -Force
    $errs | ForEach-Object { Write-Warning "  line $($_.Extent.StartLineNumber): $($_.Message)" }
    exit 1
}

Write-Host "Syntax OK. Run with:"
Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File `"$Path`" -new_theme -confirm_spoti_recomended_over -block_update_on -podcasts_on -defender_exclusions_off -no_pause"