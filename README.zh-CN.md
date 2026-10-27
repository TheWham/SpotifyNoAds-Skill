# blocking-spotify-ads-with-spotx

[English](README.md) | **简体中文**

一个面向 AI 编程 agent（Claude Code 及支持 `SKILL.md` 格式的框架）的 [skill](https://agentskills.io/specification)，用 [SpotX](https://github.com/SpotX-Official/SpotX) 屏蔽 **Windows 版 Spotify 桌面客户端**的广告。

有价值的部分不是那条安装命令——而是这个 skill 固化的**故障模式**。

## 它要解决的故障

SpotX 安装脚本会中途中断：

```
Rename-Item : 另一个进程正在使用此文件，因此该进程无法访问此文件。
所在位置 <temp>\run.ps1:5829
```

报错把责任推给另一个进程。**但根本不是。**

在 `%APPDATA%\Spotify` 下实测，两种写法交替各跑三次、针对同一个文件：

| 写法 | 结果 |
|---|---|
| `Get-ChildItem … \| Rename-Item …`（流式管道） | 每次失败——**即使 Spotify 进程数为 0** |
| `@(Get-ChildItem …)` 先物化成数组再循环 | 每次成功 |
| `Rename-Item -LiteralPath $literalPath $newName` | 每次成功 |

同样这条流式管道，在一个放着同名 18 MB 文件的临时目录里却是成功的，所以触发条件是**那个目录特有的**。精确机制未查明——但行为可复现，这才是关键。

这处改名本身无关紧要。由于脚本带 `-ErrorAction Stop`，它会**在任何去广告的二进制补丁被应用之前**就终止整个安装。你最终落到最糟的状态：一个刚升级完、能正常启动、却完全没打补丁的客户端。

这里有双重陷阱。「另一个进程占用了文件」这个说法扛得住重启和排查进程，于是人会去追一个幻影。而脚本自身的退出状态也不是可靠的成败信号——所以这个 skill 从**磁盘上的字节**来验证（各二进制与其 `.bak` 的哈希比对、对改名后快照的大小写敏感检查、以及 `xpui.js` 里的 `SpotX` 标记），而不是采信退出码。

## 安装

```bash
git clone https://github.com/TheWham/SpotifyNoAds-Skill.git /tmp/skill
cp -r /tmp/skill/blocking-spotify-ads-with-spotx ~/.claude/skills/
```

skill 放在子目录里，是为了让目录名与 frontmatter 中的 `name:` 字段一致。直接克隆进 skills 目录也能用，但那样 skill 会以仓库名注册。

## 内容

| 文件 | 用途 |
|---|---|
| `SKILL.md` | 前置条件、安装参数、已知故障及其修复、验证方法、坑 |
| `scripts/fix-run-ps1.ps1` | 对刚下载的 `run.ps1` 应用修复。幂等；改完重新做语法校验，解析失败会自动还原备份 |
| `scripts/verify-patch.ps1` | 从磁盘字节判定 `PATCHED` / `UNPATCHED`。退出码 `0` 已打补丁、`1` 未打补丁、`2` 未安装 |

两个脚本都选择**大声失败**而不是静默什么都不做：如果上游 `run.ps1` 的结构变了，`fix-run-ps1.ps1` 会抛错并提示你手工检查那处改名，而不是假装成功。

## 适用范围与限制

**仅限 Windows 桌面端。** SpotX 支持 Windows / macOS / Linux 桌面客户端——没有安卓或 iOS 版本，本 skill 不涉及。

**它不是 Spotify 破解工具。** 它改的是官方桌面客户端，服务端什么都不变，因此：

- **音质完全不受影响。** 码率是账号权益。免费桌面端上限约 160 kbps；约 320 kbps 与无损需要 Premium。
- **没有下载、AI DJ、群组会话、Jam。**
- **通过 Spotify Connect 或 AirPlay 投放时广告不会被屏蔽**——音频完全不经过桌面客户端。

改写官方客户端同时也绕开了 Spotify 的服务条款。SpotX 作者表示未发现有因使用 mod 而被封号的案例；实际风险主要来自自己——比如主动向 Spotify 客服承认你在用 mod。

## 致谢

真正干活的是 [SpotX](https://github.com/SpotX-Official/SpotX)。本仓库只是把操作知识——包括一个上游 bug 及其绕过方法——打包成 agent 可以直接套用的形式，不必重新推导一遍。