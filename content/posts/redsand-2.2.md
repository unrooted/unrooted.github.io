---
title: "RedSand - version 2.2"
description: "it's been a while"
date: 2026-06-07
tags:
  - redsand
  - windows
  - project
  - rcl
draft: false
showFullContent: false
---

## What is RedSand?
RedSand started as a single `.wsb` file: double-click it, get a clean Windows Sandbox for poking at malware or untrusted software, as it's built on top of Windows Sandbox, that'd seem rational. That was useful, but most of the actual work — picking the right isolation knobs, pre-staging tools etc. — was left to you. Been a while since I've worked on it, but after recent moving my personal workflows over to macOS, I've decided to revisit this (hard to admit, but I sometimes miss Windows and it's weirdness, so I keep it on my old ThinkPad), see which capabilities of Windows Sandbox have changed and whatnot. RedSand has grown into a small toolkit around that one idea: opinionated profiles for distinct workflows, helper scripts that do the boring parts, and CI that catches drift before users do.

I want to summarize what's actually different now compared to the project's starting point and where it was left dormant for a few years.

## What changed

### Multiple "profiles", not one wsb

The default `RedSand.wsb` is now joined by two siblings tuned for specific threat models (+ me wanting to play more with the Sandbox configurations):

| Profile | Audience | Notable knobs |
|---|---|---|
| **Default** | General-purpose | Networking on, ProtectedClient on, Clipboard off, 4 GB |
| **Analysis** | RE / dynamic & static binary analysis | Networking **off**, vGPU **off**, audio/video/printer **off**, `Input/` read-only, `Output/` read-write |
| **Forensics** | Evidence triage | Same lockdown as Analysis but with vGPU on for image viewers, 8 GB |

The Analysis and Forensics profiles introduce two new host folders: **`Input/`** for the artifact you're examining (mapped read-only inside, so the sample can't tamper with itself), and **`Output/`** for notes and exports. Each profile's `.wsb` has the `Output/` mapping clearly marked for trivial removal when you want zero writable host mappings.


### New helper scripts
- `build-wsb.ps1` - interactive builder of custom .wsb files, allowing you to go through every Windows Sandbox setting, prompting for value, you can point to your local-folder with `MappedFolder` flag as well and save the config file to any location, quite handy if you don't want to stick with pre-made profiles.
- `build-toolkit-installer.ps1` - quite similar as above, however, it is an interactive builder for scoop-based tool-packs, it will ask you if you want to add given repos and given packages and will result in a `.ps1` file, which you can also re-use locally if Windows Sandbox is not your thing (used it already to re-setup a VM after I've accidentally nuked it)

### Quality of life
* CI: GitHub Actions runs `PSScriptAnalyzer` to parse every `.ps1` for syntax and validate every `.wsb` as XML. On top of that, proves upstream installer URLs on a weekly schedule + Dependabot for Action versions. 
* removal of the wiki: I've asked around and a lot of folks told me, that for a smaller project with one strict goal, README is better and cleaner than a Wiki page. Hence, moved all of it's content + added more docs to README. 
* minor script improvements, `setup.ps1` now restarts `explorer.exe` to FULLY apply the dark theme
* `CONTRIBUTING.md`, `CHANGELOG.md`, issue and PR templates 

## NOTE: what RedSand is NOT
Please note, that RedSand is quick, fast and easy, but it's not full-blown VM like Flare-VM or REMnux, so while it's okay for most of the work it has been intended to do, samples that fingerprint sandboxes or rely on Hyper-V tricks may behave unexpectedly. 

This also means, that you can't run WSL within Windows Sandbox, as nested virtualization seems not available within the `.wsb` schema. Let me know if I've missed something.

## Try it

The project is at v2.2 on GitHub: [redcode-labs/RedSand](https://github.com/redcode-labs/RedSand). Quick start:

```powershell
# As Administrator, one-time:
.\Utils\Scripts\AdditionalScripts\OnHost\enableSandboxFeature.ps1

# Pre-stage tools and check the feature:
.\Utils\Scripts\AdditionalScripts\OnHost\prepareForRedSand.ps1

# Launch a profile:
profiles\RedSand.wsb              # or RedSand-Analysis.wsb / RedSand-Forensics.wsb
```