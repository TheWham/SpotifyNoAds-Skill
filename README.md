# blocking-spotify-ads-with-spotx

A [skill](https://agentskills.io/specification) for AI coding agents (Claude Code and harnesses that read the `SKILL.md` format) that blocks ads in the **Spotify desktop client on Windows** using [SpotX](https://github.com/SpotX-Official/SpotX).

The valuable part isn't the install command — it's the failure mode this skill encodes.

## The failure it exists for

SpotX's installer aborts partway through with:

```
Rename-Item : 另一个进程正在使用此文件，因此该进程无法访问此文件。
所在位置 <temp>\run.ps1:5829
```

The message blames another process. **It isn't one.**

Verified in `%APPDATA%\Spotify`, alternating the two forms three times each against the same file:

| Form | Result |
|---|---|
| `Get-ChildItem … \| Rename-Item …` (streaming) | fails every time — **even with zero Spotify processes running** |
| `@(Get-ChildItem …)` into an array, then loop | succeeds every time |
| `Rename-Item -LiteralPath $literalPath $newName` | succeeds every time |

The same streaming pipeline succeeds in a temp directory holding a same-named 18 MB file, so the trigger is specific to that directory. The precise mechanism is unidentified — but the behaviour is reproducible, which is what matters.

The rename itself is cosmetic. Because the script runs with `-ErrorAction Stop`, it kills the entire install **before any of the ad-blocking binary patches are applied**. You end up in the worst possible state: a freshly upgraded Spotify client that launches normally and is completely unpatched.

This sets two traps. "Another process holds the file" survives reboots and process-hunting, so people chase a phantom. And the script's own exit is not a reliable success signal — the skill therefore verifies from the bytes on disk (each binary's hash against its `.bak`, a case-sensitive check on the renamed snapshot, and the `SpotX` marker inside `xpui.js`) rather than trusting it.

## Install

```bash
git clone https://github.com/TheWham/SpotifyNoAds-Skill.git /tmp/skill
cp -r /tmp/skill/blocking-spotify-ads-with-spotx ~/.claude/skills/
```

The skill sits in a subdirectory so its folder name matches the `name:` field in its frontmatter. Cloning straight into your skills directory also works, but the skill would then register under the repository name instead.

## Contents

| File | Purpose |
|---|---|
| `SKILL.md` | Preconditions, install flags, the known failure and its fix, verification, gotchas |
| `scripts/fix-run-ps1.ps1` | Applies the fix to a freshly downloaded `run.ps1`. Idempotent; re-validates syntax and restores its backup if the patched file fails to parse |
| `scripts/verify-patch.ps1` | Reports `PATCHED` / `UNPATCHED` from the bytes on disk. Exits `0` patched, `1` unpatched, `2` not installed |

Both scripts fail loudly rather than silently doing nothing: if upstream `run.ps1` changes shape, `fix-run-ps1.ps1` throws and tells you to inspect the rename by hand instead of pretending it worked.

## Scope and limits

**Windows desktop only.** SpotX supports Windows, macOS and Linux desktop clients — there is no Android or iOS version, and this skill does not cover them.

**It is not a Spotify crack.** It patches the official desktop client. Nothing changes server-side, so:

- **Audio quality is untouched.** Bitrate is an account entitlement. Free desktop caps around 160 kbps; ~320 kbps and lossless require Premium.
- **No downloads, AI DJ, group sessions, or Jam.**
- **Ads are not blocked over Spotify Connect or AirPlay** — the audio bypasses the desktop client entirely.

Patching the official client also sidesteps Spotify's terms of service. SpotX's author reports no known cases of accounts being banned for using it; the practical risk is largely self-inflicted, by volunteering to Spotify support that you use a mod.

## Credits

[SpotX](https://github.com/SpotX-Official/SpotX) does the actual work. This repository only packages the operating knowledge — including one upstream bug and its workaround — into a form an agent can apply without re-deriving it.