---
title: "Sandbox Shenanigans pt.1 - The Windows Sandbox Abuse "
date: 2026-07-20
author: Konrad 'unrooted' Klawikowski
tags: [windows-sandbox, wsb, lolbas, defense-evasion, windows, powershell]
---

# Sandbox Shenanigans pt.1 - The Windows Sandbox Abuse 

Windows Sandbox is a disposable, lightweight VM baked into every Pro/Enterprise install -
flip on one optional feature and you get a throwaway Windows box with Defender off by default and
optional folder mappings into the host. Genuinely useful for detonating a suspicious attachment.
Also, structurally, a gift to anyone trying to hide from your EDR: the payload runs somewhere your
host telemetry can't see.

My previous project, [RedSand](https://github.com/redcode-labs/RedSand) utilized the idea heavily, and I've recently updated it.
This re-visit reminded me of why I left Windows as a go-to personal OS, but also gave me some insights into some other use-cases of the Sandbox.
Original blogpost on the update and what it changed can be seen in [here](https://unrooted.github.io/posts/redsand-2.2/).

This post covers **two approaches**, both demoed non-destructively in the associated repo:

1. **The classic `.wsb`-file pattern** - host-folder write-back and sandbox-side persistence.
2. **The `wsb.exe` CLI pattern (Windows 11 24H2+)** - a four-primitive, fileless abuse approach that splits itself across multiple command-line invocations specifically to defeat single-event detection rules.

Everything here is benign by design - marker files and Calculator, not payloads - built to verify
that your Sysmon / EDR / SIEM actually fires on the *shape* of these techniques before it's too late to prepare proper detection mechanics.

A small hint on the next part: I will try my best to provide detection and hunting capabilities for such abuse, but for now, let's focus on what the attackers could do.

Please note, by 'associated repo', I mean [this one](https://github.com/unrooted/sandbox-shenanigans).

## Approach 1: the classic pattern - `.wsb` + `LogonCommand`

A `.wsb` file is just XML. `shenanigans-demo.wsb` in the associated repository maps two host folders and wires a
script into `<LogonCommand>`, which runs automatically once `WDAGUtilityAccount` logs into the
sandbox:

```xml
<MappedFolders>
   <!-- Read-write host folder - the "abuse target". -->
   <!-- I picked User Public as a rather universal path, tweak to your liking -->
   <MappedFolder>
     <HostFolder>C:\Users\Public</HostFolder>
     <ReadOnly>false</ReadOnly>
   </MappedFolder>

   <!-- Read-only mapping that brings the inner script into the sandbox. -->
   <MappedFolder>
     <HostFolder>scripts\</HostFolder>
     <ReadOnly>true</ReadOnly>
   </MappedFolder>
</MappedFolders>
<LogonCommand>
   <Command>powershell.exe -ExecutionPolicy Bypass -File C:\users\WDAGUtilityAccount\Desktop\scripts\shenanigans-inner.ps1</Command>
</LogonCommand>
```

`scripts/shenanigans-inner.ps1` is the script that demonstrates the two techniques attackers actually could use:

**Technique 1 - host-folder write-back.** The read-write mapping means anything the script writes
to `Desktop\Public\` on the sandbox side lands as the same bytes on the host.
A real attacker would drop a payload this way; the demo drops a text file that documents the technique
instead:

```powershell
$marker = 'C:\users\WDAGUtilityAccount\Desktop\Public\shenanigans-marker.txt'
$body = @"
This file was written from INSIDE a Windows Sandbox into a host-mapped folder. 
Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Source: shenanigans-inner.ps1 (RedSand defensive testing example)

If you are reading this on your HOST filesystem, a process running as
WDAGUtilityAccount inside a Windows Sandbox just wrote to your disk.
Real attackers use this exact pattern to stage malware on the host.

Detection guidance: Sysmon EventID 11 (FileCreate) where the parent
process tree includes any WindowsSandbox* binary.
"@
$body | Out-File -FilePath $marker -Encoding UTF8 -Force
```

Obviously there are other ways one can abuse r/w from host being mapped to the sandbox, I can imagine infostealer easily taking an adventage of that.


**"Technique" 2 - sandbox-side scheduled task.** Registers a task that fires 10 seconds later as SYSTEM. Attackers would use this shape for persistence and privilege escalation inside the sandbox;
but, obviously, this is a very loud approach to the problem. 

The spawning process tree hides behind `WindowsSandboxRemoteSession.exe`. 
The demo swaps the payload for `calc.exe` so the audit signature matches without doing anything harmful:

```powershell
$action    = New-ScheduledTaskAction    -Execute 'calc.exe'
$trigger   = New-ScheduledTaskTrigger   -Once -At ((Get-Date).AddSeconds(10))
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName 'WSB-Test-Shenanigans' -Action $action -Trigger $trigger -Principal $principal -Force
```

Both steps log to `Desktop\shenanigans.log` inside the sandbox so you can confirm each stage
actually ran.

Every modern EDR system and the like should be screaming seeing things like this.
However, there's a catch: I wouldn't treat this as "technique" per-se, as it's meant to showcase that (rather most) EDR solution on the host won't see even the most obvious signs of potential compromise within the Sandbox environment. It's not meant to tamper with the host, grab any files present there etc., but rather to showcase a blindspot.

### Running it

Double-click `shenanigans-demo.wsb` from the repo. After ~30 seconds:

- Verify `Files\shenanigans-marker.txt` exists on the host - the file itself documents the
  technique, and its existence is your baseline confirmation that the demo ran. Delete it once done.
- Verify your EDR / Sysmon / SIEM caught **both** the cross-boundary file write and the scheduled
  task creation. If it didn't, that's the gap this demo exists to surface.

### The fileless variant hiding in plain sight: `wsb.exe` inline config

Even without touching CLI primitives (Approach #2), Windows 11 24H2's `wsb.exe` can replicate this entire
`.wsb`-file pattern with **no file ever written to disk** - the whole configuration, `LogonCommand`
included, travels as a single command-line argument:

```
wsb start --config "<Configuration><LogonCommand><Command>cmd.exe /c echo touched > C:\users\WDAGUtilityAccount\Desktop\out.txt</Command></LogonCommand></Configuration>"
```

There's no `.wsb` file to scan here, so detection has to inspect the `wsb.exe` command line itself
- which is the entire subject of Approach #2.

## Part 2: the `wsb.exe` CLI pattern (Windows 11 24H2+)

Windows 11 24H2 ships a new binary once the Windows Sandbox optional feature is enabled and the
Store app auto-upgrades on first launch: `wsb.exe`, at
`C:\Users\<user>\AppData\Local\Microsoft\WindowsApps\wsb.exe`. There's no separate Store catalog
entry to hunt for - it's just there once the upgrade lands. It's a genuinely well-designed CLI for
scripting sandbox lifecycles. It's also a fresh LOLBAS entry, because it hands an attacker **four
composable primitives** that can be split across independent invocations so that no single command
line looks alarming on its own.

### Why the sandbox is a privileged execution environment, structurally

A few properties hold across every primitive below, learned empirically against a 24H2 box running
the upgraded Sandbox app:

- **Defender is off inside the sandbox by default** and can't be re-enabled from within. Anything
  that runs there is invisible to host-side AV.
- **The host can't see inside the sandbox VM at all.** Inside, the process tree looks like a normal
  Windows install (`winlogon`, `services`, `svchost`); host ETW/Sysmon has no visibility into that
  kernel.
- **Cross-boundary writes are misattributed.** A write from inside the sandbox to a mapped host
  folder shows up on host telemetry as `vmwp.exe` (the Hyper-V worker) creating the file - **not**
  `wsb.exe` and not any `WindowsSandbox*` binary. Rules keyed on the writing process miss it.
- **Network egress exits through the Hyper-V virtual NIC**, not the host NIC. Source-IP and
  source-process egress filters on the host don't observe sandbox-originated traffic.
- **Nothing survives shutdown.** No on-disk artifacts inside the VM persist past close - there's
  nothing for a responder to acquire from the sandbox itself afterward.

The host-side process semantics that matter for detection and detection engineering:

| Process | Meaning |
|---|---|
| `WindowsSandboxServer.exe` | Alive whenever a Sandbox VM exists, **regardless of whether anyone connected** |
| `WindowsSandboxRemoteSession.exe` | Alive **only** when an RDP connection into the sandbox is active - appears immediately if a `.wsb` file is double-clicked (auto-connects), but `wsb start --config` alone does **not** spawn it |
| `vmwp.exe` / `vmmemWindowsSandbox` | Hyper-V worker and VM memory process backing the sandbox |
| `WindowsSandbox.exe` / `WindowsSandboxClient.exe` (System32) | Legacy stubs, still on disk on 24H2 but superseded by the Store-app binaries above |

The gap between `WindowsSandboxServer.exe` and `WindowsSandboxRemoteSession.exe` is the single
highest-signal observable in this whole post.

### The four primitives

| Subcommand | What it does |
|---|---|
| `wsb start --config "<inline XML>"` | Launches a sandbox from CLI-supplied config - no `.wsb` file written |
| `wsb exec --id <id> -c <cmd> -r System` | Runs a command inside a running sandbox as SYSTEM, **no user session required** |
| `wsb share --id <id> -f <host> -s <sbx> --allow-write` | Maps a host folder into a *running* sandbox, dynamically, post-boot |
| `wsb connect --id <id>` | Opens an RDP session into the sandbox (triggers user logon) |

Each is documented innocently on [Microsoft Learn](https://learn.microsoft.com/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-cli). Each looks like routine Sandbox usage in isolation. The attacker value shows up when you chain them.
Another one not being a bug, but a feature. 

Going through those primitives to explain a bit more with more examples:

**Primitive 1 - `wsb start --config "...<LogonCommand>..."`.** Looks like the headline abuse: fileless config with an embedded payload. But `<LogonCommand>` only fires on user *logon* - which in a sandbox only happens via an RDP session, i.e. `wsb connect`. That opens a visible window, so this technique isn't as silent as "fileless" suggests. It's fileless from a forensic-artifact standpoint (no `.wsb` on disk, only a command line), but not headless.

**Primitive 2 - `wsb exec --id <guid> -c <payload> -r System`.** The truly headless variant. `-r System` runs as `NT AUTHORITY\SYSTEM` and, unlike `-r ExistingLogin`, needs no active user session - no `wsb connect`, no logon event, no visible window. It requires a sandbox already running, so it's always paired with a prior `wsb start`. That pairing is exactly what makes it a bit harder for detection: a rule written as "alert on `wsb.exe --config` containing `<LogonCommand>`" never fires on either call individually - `start` here carries no `LogonCommand`, and `exec` carries no `<Configuration>` XML at all. The combined effect is arbitrary SYSTEM-context execution; each individual invocation looks more benign than the all-in-one version. It also enables **late-binding payload selection**: boot the sandbox proactively (looks like routine usage), then decide what to run later - after recon, after a C2 check-in - and **iterative execution** against one running sandbox, since state persists across `exec` calls but evaporates when the sandbox finally closes.

**Primitive 3 - `wsb share --id <guid> -f <host> -s <sbx> --allow-write`.** Before this CLI shipped, mapped folders could only be declared in a `.wsb` at boot. `share` lets an attacker who already started a sandbox (with a config that had *no* read-write mappings) dynamically grant write access to an arbitrary host path afterward - post-boot expansion of host-filesystem access that a config-scanning detection rule will never see, because the rw grant happens in a later, separate call. The target host path is also fully runtime-controlled, so it can be chosen based on what a prior `exec` call discovered via recon.

**Primitive 4 - `wsb connect --id <guid>`.** Opens an RDP session - the trigger that makes
`<LogonCommand>` fire, and the way to get hands-on-keyboard interactivity. The visible window is the one place this whole chain becomes user-perceptible; real operators would avoid it unless the payload genuinely needs a logon event for some reason (HKCU access, user-profile paths). Worth noting: the window can be minimized or hidden via UI automation post-spawn, a host-side action outside `wsb.exe`'s own surface - "this opens a window" doesn't fully neutralize the primitive.

### The four-call chain, combined

```powershell
wsb start --config "<Configuration><Networking>Default</Networking></Configuration>"
## ... time gap: attacker does recon, or waits for a C2 check-in ...
wsb share --id <id> -f C:\Users\victim\Documents -s C:\drop --allow-write
wsb exec --id <id> -c "powershell.exe -enc <base64>" -r System
## (optionally) wsb connect --id <id>   -- for follow-on hands-on work
```

Four invocations, each with a distinct, individually-unremarkable command line: the first looks like routine Sandbox usage, the share looks like a folder-mapping operation, the exec looks like a one-off command, and the connect (if used at all) looks like a normal RDP session. No single event carries the whole story.

### Proof-of-concept

`./wsb-poc.ps1` in the associated repository demonstrates the genuinely headless two-call
pattern end to end - benign by design, just a marker file, again, to test *your* solutions against it:

```powershell
# Step 1: start a sandbox with a mapped folder, no LogonCommand at all.
$config = @"
<Configuration>
  <Networking>Default</Networking>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>$HostShare</HostFolder>
      <SandboxFolder>$SandboxShare</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
  </MappedFolders>
</Configuration>
"@
$startOut = wsb start --config $config 2>&1 | Out-String
$sandboxId = [regex]::Match($startOut, '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}').Value

# Step 2: exec the payload as SYSTEM - no wsb connect, no window, no logon event.
$payload = "cmd.exe /c echo wsb.exe LOLBAS PoC reached host filesystem at %TIME% > $SandboxShare\marker.txt"
wsb exec --id $sandboxId -c $payload -r System
```

Run it, wait a few seconds, and check `%USERPROFILE%\Desktop\wsb-target\marker.txt` on the host. Clean up with `wsb stop --id <id>` and delete the target folder. The two command lines above share nothing but a GUID - which is exactly the correlation key defenders need to join on.

## Conclusions
I've had my fun, and even though I do not miss Windows, I will always love its quirky design choices and weirdness here and there, wsb.exe being very good example alongside the WSL subsytem.

In this part I've tried to cover some examples of potential abuse of this feature, but in the next one I will try my best, as foreshadowed before, to do some examples for my fellow threat hunters and detection engineers out there. 

This allowed me to contribute more to the LOLBAS project as well, adding `wsb.exe` as its own entry: [link](https://lolbas-project.github.io/lolbas/OtherMSBinaries/Wsb/), being the first entry created by me. I am honored to have contributed to such significant project.

Some thinking out loud: even though our tools, systems and everything around us changes, there should be one thing we shall not change within ourselves: ability to adapt to those changes.

## References

- [Operation AkaiRyū: MirrorFace invites Europe to Expo 2025 and revives ANEL backdoor](https://www.welivesecurity.com/en/eset-research/operation-akairyu-mirrorface-invites-europe-expo-2025-revives-anel-backdoor/) - great analysis from the Eset team that showcases a real-world scenario which utilized Windows Sandbox during their campaign, even though it's a bit over a year old at the time of me writing this, it, so far, dated quite well
- [secdev02/SandBoxShenanigans](https://github.com/secdev02/SandBoxShenanigans) - the public research Part 1 is modeled after
- [LloydLabs/wsb-detect](https://github.com/LloydLabs/wsb-detect) - host-side detection research for `wsb.exe` abuse
- ["Weaponizing Windows Sandbox" - syscall.party (archived)](https://web.archive.org/web/20250116184008/http://blog.syscall.party/2020/12/02/weaponizing-windows-sandbox.html)
- [Windows Sandbox overview - Microsoft Learn](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-overview)
- [Windows Sandbox configuration reference - Microsoft Learn](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-configure-using-wsb-file)
- [Windows Sandbox CLI - Microsoft Learn](https://learn.microsoft.com/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-cli)
- [LOLBAS entry: wsb.exe](https://lolbas-project.github.io/lolbas/OtherMSBinaries/Wsb/)
- [Sandbox-Shenanigans](https://github.com/unrooted/sandbox-shenanigans) - my own repo containing complementary code for this blogpost
