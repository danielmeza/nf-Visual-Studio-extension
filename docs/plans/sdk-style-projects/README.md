# nanoFramework SDK-Style Project System Migration — Specification Set

**Draft v2.** A specification set for migrating .NET nanoFramework from the legacy
custom `.nfproj` project system to an SDK-style MSBuild project system. **Managed
project system only** — OTA, native module compilation, and native binaries in
NuGet packages are out of scope (separate, later effort).

Start with **[00-overview.md](00-overview.md)** — it carries the scope boundary, the
**VS debugger blocker**, the corrected premises, naming conventions, and the document
map.

> **POC executed — debugger gate CLEARED on real hardware. ✅** An SDK-style
> nanoFramework app (`samples/Blink`) now **builds, deploys, runs, and debugs with F5 +
> source breakpoints** on a physical ESP32_S3_OCTAL. See
> **[poc-sdk-style/RESULTS.md](../../../poc-sdk-style/RESULTS.md)** for what's proven,
> **[poc-sdk-style/DEBUGGING-LOG.md](../../../poc-sdk-style/DEBUGGING-LOG.md)** for the
> full decision record (every blocker hit + the fix, §1–§6), and
> **[poc-sdk-style/DEVICE-RUN-DROPDOWN.md](../../../poc-sdk-style/DEVICE-RUN-DROPDOWN.md)**
> for the multi-device selection design. VS Code analysis:
> **[vscode-extension-impact.md](vscode-extension-impact.md)**.

## The blocker — RESOLVED ✅

The maintainer attributed the SDK-style block to the **Visual Studio debugger**
([#1635](https://github.com/orgs/nanoframework/discussions/1635)). The code read was
right and the POC confirmed it end to end: the VS project system is already CPS and the
deploy/debug-launch providers key off the **`NanoCSharpProject` capability** and launch
the engine **by GUID**, so the AD7 engine is **orthogonal** — the real gate was
**build-targets composition + capability registration**, not the engine. A minimal
`nanoFramework.Sdk` composing over `Microsoft.NET.Sdk` and injecting the capability
makes deploy **and** F5 + source breakpoints work on real hardware, AD7 unchanged behind
the engine-binding seam.

Four concrete issues surfaced and were fixed during execution (full detail in
[poc-sdk-style/DEBUGGING-LOG.md](../../../poc-sdk-style/DEBUGGING-LOG.md)):

| Symptom | Root cause | Fix | Where |
|---|---|---|---|
| F5 launched a **console app** | SDK `Exe` inherits the `LaunchProfiles` capability → C# launcher owns F5 | SDK removes `LaunchProfiles` + sets `DebuggerFlavor=NanoDebugger` | SDK `Sdk.targets` (§4) |
| Deploy **version mismatch** | firmware mscorlib `100.22.0.4` vs published `.5` — same checksum, no nuget has the exact pair | relax the deploy pre-check to a **checksum** match (revision is cosmetic; runtime links on major.minor) | extension `DeployProvider` (§3) |
| **Breakpoints didn't bind** (hit only method entry) | SDK emitted a **portable** PDB; nano's debug path resolves source→IL only from a **Windows/full** PDB | SDK forces `DebugType=full` for Debug (Windows PDB under VS's csc) | SDK `Sdk.props` (§5) |
| Legacy **`.nfproj` wouldn't load** beside the SDK `.csproj` | non-elevated experimental-instance deploy can't surface the `InstallRoot="MSBuild"` assets to `$(MSBuildExtensionsPath)` | `dev-install-legacy-targets.ps1` (dev only; a normal elevated install is unaffected) | poc folder (§6) |

Build, pack, and CLI flows are cross-platform and were never blocked. The remaining
work is **productizing, not feasibility** — see
[09-implementation-strategy.md](09-implementation-strategy.md) and the read-only
[debugger-blocker-diagnosis-prompt.md](debugger-blocker-diagnosis-prompt.md).

## Documents

| # | Document | What it covers |
|---|----------|----------------|
| 00 | [00-overview.md](00-overview.md) | Scope boundary, debugger blocker, corrected premises, naming, doc map |
| 01 | [01-current-state.md](01-current-state.md) | Three-layer teardown: VS extension / `NFProjectSystem` MSBuild / MDP; PE pipeline; NuGet structure; property + task inventory |
| 02 | [02-sdk-design.md](02-sdk-design.md) | **Central doc.** SDK mechanics, the `netnano1.0` TFM, the SDK↔.NET-SDK relationship (thin-SDK → workload), managed target graph |
| 03 | [03-project-file-migration.md](03-project-file-migration.md) | Before/after project files; minimal app/lib; backward compat; property reference |
| 04 | [04-mdp-native-integration.md](04-mdp-native-integration.md) | Re-hosting MDP as a first-class incremental managed target; optional build-time ABI gate |
| 05 | [05-cli-experience.md](05-cli-experience.md) | Verb table; why `dotnet deploy` can't be a bare verb; the `dotnet-nano` tool + `Deploy` target; `dotnet watch` iteration |
| 06 | [06-ide-integration.md](06-ide-integration.md) | Thin-extension/fat-SDK split; what was unblocked vs. what the POC proved (gate cleared); VS Code path |
| 07 | [07-library-migration.md](07-library-migration.md) | Fleet migration of ~100+ `lib-*` repos; the embedded converter; leaf-first order; what-breaks table; CI rewrite |
| 08 | [08-nuget-pipeline.md](08-nuget-pipeline.md) | Managed package layout (`lib/netnano1.0/`); `Pack` overrides; nuspec→Pack metadata |
| 09 | [09-implementation-strategy.md](09-implementation-strategy.md) | Minimum viable SDK; phases; coexistence; the debugger gate; risk register |
| 10 | [10-tooling-specs.md](10-tooling-specs.md) | Build-list of managed components; task signatures; `dotnet new` templates; consolidated target graph; acceptance criteria |

### POC & analysis (added by the executed proof-of-concept)

| Document | What it covers |
|----------|----------------|
| [poc-sdk-style-debugging-plan.md](poc-sdk-style-debugging-plan.md) | The A+C POC plan: workstreams WS1–WS4, the engine-binding seam, the decision gate |
| [poc-sdk-style/RESULTS.md](../../../poc-sdk-style/RESULTS.md) | **Executed POC results**: what's proven on a plain machine, the gates hit, WS4 (Layer A/B) runbook + Azure pipeline |
| [poc-sdk-style/DEBUGGING-LOG.md](../../../poc-sdk-style/DEBUGGING-LOG.md) | **Decision record** — every blocker hit on the way to F5+breakpoints on hardware and its fix (§1 restore loop · §2 PE format · §3 deploy version · §4 F5 console · §5 breakpoint PDB · §6 legacy `.nfproj` load), plus dead ends not to repeat |
| [poc-sdk-style/DEVICE-RUN-DROPDOWN.md](../../../poc-sdk-style/DEVICE-RUN-DROPDOWN.md) | Multi-device Run selection: the MAUI-style `IVsProjectCfgDebugTargetSelection` mechanism + the mechanism-independent consumer wiring (deploy/debug follow the selected device) |
| [vscode-extension-impact.md](vscode-extension-impact.md) | Impact of the SDK migration on the VS Code extension (grounded in the shipped extension) |
| [debugger-blocker-diagnosis-prompt.md](debugger-blocker-diagnosis-prompt.md) | Read-only local diagnosis that validates the hypothesis first |

## Tooling

- [NanoMigrate/nano-migrate.py](NanoMigrate/nano-migrate.py) — a reference
  `.nfproj` → SDK-style converter (the C# tool in
  [NanoMigrate/](NanoMigrate/) / the companion `nanoframework-sdk-migration` skill
  supersedes it for fleet use). It drops defaults, folds `.nuspec` metadata into
  MSBuild properties,
  resolves `packages.config` versions into `PackageReference`s (aliasing legacy
  `mscorlib`/`System` references onto `nanoFramework.CoreLibrary`), drops a
  hand-written `Properties/AssemblyInfo.cs`, emits `netnano1.0`, and **fails loud**.

  ```
  python3 scripts/nano-migrate.py path/to/Library.nfproj
  ```

## Premises worth flagging up front

Detailed in `00-overview.md`, but they matter:

1. **MDP is already an MSBuild task**, not an external post-build tool
   (`nanoFramework.Tools.MetadataProcessor.MsBuildTask`, with a `.CLI` variant).
   The migration *re-hosts and makes incremental* an existing task.

2. **`netnano1.0` is a real, recognized TFM** — it's in the
   [Microsoft TFM table](https://learn.microsoft.com/en-us/dotnet/standard/frameworks#supported-target-frameworks).
   The real gap is that nanoFramework's packages aren't published against it yet
   (consumers fall back to `net` to restore), which is unblocked work.

3. **The VS debugger was the central constraint the plan is built around — now PROVEN
   solvable.** The POC achieved deploy + F5 + source breakpoints on real hardware with
   an SDK-style project, AD7 engine unchanged. The remaining effort is productizing
   (packaging the SDK, fleet migration), not proving feasibility.
