# Verifies that a SpotX patch actually landed.
#
# SpotX can exit 0-looking or fail late; the only trustworthy signal is the
# bytes on disk. Reports UNPATCHED when the client was installed but the
# binary patches never ran (the run.ps1:5829 abort leaves exactly that state).

[CmdletBinding()]
param(
    [string]$SpotifyDirectory = (Join-Path $env:APPDATA 'Spotify')
)

[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ErrorActionPreference = 'Continue'

function Line($label, $value) { "  {0,-32} {1}" -f $label, $value }

if (-not (Test-Path -LiteralPath $SpotifyDirectory)) {
    Write-Host "Not installed: $SpotifyDirectory" -ForegroundColor Red
    exit 2
}

Write-Host "`nSpotify directory: $SpotifyDirectory`n"

$dll     = Join-Path $SpotifyDirectory 'Spotify.dll'
$dllBak  = Join-Path $SpotifyDirectory 'Spotify.dll.bak'
$exe     = Join-Path $SpotifyDirectory 'Spotify.exe'
$exeBak  = Join-Path $SpotifyDirectory 'Spotify.bak'
$elf     = Join-Path $SpotifyDirectory 'chrome_elf.dll'
$elfBak  = Join-Path $SpotifyDirectory 'chrome_elf.dll.bak'
$xpui    = Join-Path $SpotifyDirectory 'Apps\xpui.spa'

Line 'Installed version' ((Get-Item -LiteralPath $exe).VersionInfo.FileVersion)

# --- 1. the backup that only exists once binary patching begins -----------
$dllBakExists = Test-Path -LiteralPath $dllBak
Line 'Spotify.dll.bak' $(if ($dllBakExists) { 'exists' } else { 'MISSING' })

# --- 2. do the patched binaries differ from their pristine backups? -------
$diffs = @()
foreach ($pair in @(
        @{ name = 'Spotify.dll';    cur = $dll; bak = $dllBak },
        @{ name = 'Spotify.exe';    cur = $exe; bak = $exeBak },
        @{ name = 'chrome_elf.dll'; cur = $elf; bak = $elfBak })) {
    if (-not (Test-Path -LiteralPath $pair.bak)) {
        Line "$($pair.name) vs backup" 'no backup'
        continue
    }
    $same = (Get-FileHash -LiteralPath $pair.cur -Algorithm MD5).Hash -eq
            (Get-FileHash -LiteralPath $pair.bak -Algorithm MD5).Hash
    Line "$($pair.name) vs backup" $(if ($same) { 'IDENTICAL (unpatched)' } else { 'differs (patched)' })
    if (-not $same) { $diffs += $pair.name }
}

# --- 3. the snapshot rename ----------------------------------------------
# Compare the actual name case-SENSITIVELY: Test-Path is case-insensitive on
# Windows, so it matches the lowercase original too and would always pass.
$snap = Get-ChildItem -LiteralPath $SpotifyDirectory -Filter 'v8_context_snapshot*.bin' -File |
    Select-Object -First 1
$renamed = $null -ne $snap -and $snap.Name -ceq 'V8_context_snapshot.bin'
Line 'v8 snapshot' $(if ($renamed) { 'V8_context_snapshot.bin (renamed)' }
                    elseif ($snap) { "$($snap.Name) (still lowercase)" }
                    else { 'no snapshot file found' })

# --- 4. UI patch marker --------------------------------------------------
$marker = $false
if (Test-Path -LiteralPath $xpui) {
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($xpui)
        $entry = $zip.Entries | Where-Object { $_.FullName -eq 'xpui.js' }
        if ($entry) {
            $sr = New-Object IO.StreamReader($entry.Open())
            $content = $sr.ReadToEnd(); $sr.Close()
            $marker = $content -match 'SpotX'
        }
        $zip.Dispose()
    }
    catch { Line 'xpui read error' $_.Exception.Message }
}
Line 'xpui.js SpotX marker' $(if ($marker) { 'present' } else { 'NOT FOUND' })

# --- 5. running? ---------------------------------------------------------
$proc = @(Get-Process -Name 'Spotify' -ErrorAction SilentlyContinue)
Line 'Running processes' $(if ($proc.Count) { "$($proc.Count)" } else { 'none' })

# --- verdict -------------------------------------------------------------
$ok = $dllBakExists -and ($diffs.Count -ge 2) -and $renamed -and $marker
Write-Host ''
if ($ok) {
    Write-Host "PATCHED - ad-blocking binary patches are in place." -ForegroundColor Green
    exit 0
} else {
    Write-Host "UNPATCHED - the client is installed but the binary patches did not run." -ForegroundColor Yellow
    Write-Host "Re-run the patched run.ps1 (see scripts/fix-run-ps1.ps1)." -ForegroundColor Yellow
    exit 1
}