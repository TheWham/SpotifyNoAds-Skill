---
name: blocking-spotify-ads-with-spotx
description: Use when asked to block, remove, or disable ads in the Spotify desktop client on Windows, to install or re-run SpotX, when a SpotX run aborts with "另一个进程正在使用此文件" or a Rename-Item IOException at run.ps1:5829, or when Spotify auto-updated and wiped a previous patch.
---

# Blocking Spotify Ads with SpotX

## Overview

SpotX patches the official Spotify desktop client to block banner, video, and audio ads. Everything it does is **client-side**; nothing changes server-side.

Core principle: **SpotX's installer aborts on a cosmetic file rename before it ever applies the ad-blocking binary patches.** A run that "failed" has typically installed the new client and left it *completely unpatched*. Never report success from exit code alone — verify the binary diffs (below).

## Preconditions

Standalone Spotify install at `%APPDATA%\Spotify` (**not** the Microsoft Store build), PowerShell 5.1+, Spotify **not running**.

```bash
ls -d "$APPDATA/Spotify" && ls -d "$LOCALAPPDATA/Packages/SpotifyAB.SpotifyMusic_zpdnekdrzrea0" 2>/dev/null || echo "store version: none"
tasklist //FI "IMAGENAME eq Spotify.exe"
```

## Install

Run in an **interactive** PowerShell when possible — the default flow asks y/n questions. From a non-interactive shell, resolve every prompt with flags or it hangs:

```powershell
iex "& { $(iwr -useb 'https://raw.githubusercontent.com/SpotX-Official/SpotX/refs/heads/main/run.ps1') } -new_theme -confirm_spoti_recomended_over -block_update_on -podcasts_on -defender_exclusions_off -no_pause"
```

| Flag | Why |
|---|---|
| `-confirm_spoti_recomended_over` | Overwrite-install the recommended build instead of prompting |
| `-block_update_on` | Stop Spotify's auto-update from wiping the patch |
| `-podcasts_on` / `-podcasts_off` | Answer the podcast prompt either way |
| `-defender_exclusions_off` | Skip the Defender exclusion prompt (needs admin) |
| `-no_pause` | Don't block at the end |

If the installed Spotify is older than the script's recommended build, SpotX upgrades it first. **That upgrade is the user's call — ask before proceeding.**

Because the official `run.ps1` is fetched fresh each time, patch a local copy and run that instead. Bundled script paths are relative to this skill's directory:

```bash
curl -sSL -o "$TEMP/spotx_run.ps1" https://raw.githubusercontent.com/SpotX-Official/SpotX/refs/heads/main/run.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/fix-run-ps1.ps1 -Path "$TEMP/spotx_run.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "$TEMP/spotx_run.ps1" -new_theme -confirm_spoti_recomended_over -block_update_on -podcasts_on -defender_exclusions_off -no_pause
```

## Known failure: aborts at run.ps1:5829

```
Rename-Item : 另一个进程正在使用此文件，因此该进程无法访问此文件。
所在位置 <temp>\run.ps1:5829
```

The message blames another process. **It is not one.** Verified in `%APPDATA%\Spotify`: a streaming `Get-ChildItem … | <renaming cmdlet>` pipeline fails with this message **every** time — even with zero Spotify processes running — while the same rename via `Rename-Item -LiteralPath` succeeds every time, back-to-back against the same file. That trap survives reboots and process-hunting. The same pipeline succeeds in a temp directory holding a same-named 18 MB file, so the trigger is specific to that directory; the precise mechanism is unidentified. `-ErrorAction Stop` then kills the whole script, including the 100+ lines of binary patching that follow.

Alternate the forms three times each, on the same file, before concluding anything:

| Form | Result |
|---|---|
| `Get-ChildItem … \| Rename-Item …` (streaming) | fails every time |
| `Get-ChildItem … \| ForEach-Object { Rename-Item -LiteralPath … }` (still streaming) | fails every time |
| `@(Get-ChildItem …)` into an array, then loop | succeeds every time |
| `Rename-Item -LiteralPath $literalPath $newName` | succeeds every time |

The fix — materialise the enumeration before renaming:

```powershell
$v8Snapshots = @(Get-ChildItem -LiteralPath $spotifyDirectory -Filter 'v8_context_snapshot*.bin' -File)
foreach ($v8Snapshot in $v8Snapshots) {
    Rename-Item -LiteralPath $v8Snapshot.FullName -NewName ('V' + $v8Snapshot.Name.Substring(1)) -ErrorAction Stop
}
```

`scripts/fix-run-ps1.ps1` applies exactly this, idempotently, and re-validates syntax.

## Verify — evidence, not exit codes

Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify-patch.ps1` — it exits 0 for patched, 1 for unpatched, 2 for not installed — or check by hand:

| Signal | Patched | Unpatched |
|---|---|---|
| `Spotify.dll.bak` | exists | absent |
| `Spotify.dll` vs `Spotify.dll.bak` (MD5) | differs | identical |
| `v8_context_snapshot.bin` | renamed to `V8_…` | still lowercase |
| `Apps/xpui.js` | contains `SpotX` marker | no marker |
| Launch | window opens, stays up | — |

An unpatched run shows the new version number, the lowercase snapshot, and no `Spotify.dll.bak` — the script died before patching. Re-run it.

## Traps that cost real time

- **Console output is GBK.** Decode before reading it: `iconv -f GBK -t UTF-8 < log`. Mojibake misread as different words leads to wrong conclusions about which code path ran.
- **`.sig` files remaining is normal.** `Remove-Signature-FromFiles` zeroes only the *embedded* signature; the `.sig` sidecars stay. Their presence is not evidence the signature step was skipped.
- **Re-running after a failure is safe.** When the installed version matches the recommended one, SpotX skips the download and version prompts.
- **Backups are for rollback.** `Spotify.bak`, `Spotify.dll.bak`, `chrome_elf.dll.bak`, `Apps\xpui.bak`, plus SpotX's own `Uninstall.bat`.

## What SpotX does NOT do

Say this plainly rather than letting the user assume otherwise:

- **No audio-quality change.** Bitrate is an account entitlement, decided server-side. Free desktop caps at ~160 kbps; ~320 kbps and lossless need Premium. SpotX's own FAQ lists "exceptionally high sound quality" among the features it cannot provide.
- **No downloads, AI DJ, group sessions, or Jam.**
- **Ads are not blocked over Spotify Connect / AirPlay** — the audio bypasses the desktop client entirely.

Patching the official client also sidesteps Spotify's terms and can put the account at risk. One sentence up front, then proceed if the user asks for it.