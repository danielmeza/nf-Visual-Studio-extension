# nanoFramework SDK-Style Project System Migration — Specification Set

**Draft v2.** A specification set for migrating .NET nanoFramework from the legacy
custom `.nfproj` project system to an SDK-style MSBuild project system. **Managed
project system only** — OTA, native module compilation, and native binaries in
NuGet packages are out of scope (separate, later effort).

Start with **[00-overview.md](00-overview.md)** — it carries the scope boundary, the
**VS debugger blocker**, the corrected premises, naming conventions, and the document
map.

> **POC executed.** The A+C proof-of-concept below has been built and verified
> (build side) — see **[poc-sdk-style/RESULTS.md](../../../poc-sdk-style/RESULTS.md)**
> for what's proven, the WS4 validation runbook, and the decision gate, and
> **[vscode-extension-impact.md](vscode-extension-impact.md)** for the VS Code
> extension migration analysis.

## The blocker, up front

The maintainer attributes the SDK-style block to the **Visual Studio debugger**
([#1635](https://github.com/orgs/nanoframework/discussions/1635)). A code read of
`nf-Visual-Studio-extension` refines this: the VS project system is already CPS and
the deploy/debug-launch providers key off a capability and launch the engine **by
GUID**, so the concrete gate looks like **build-targets composition + capability
registration**, with the AD7 engine likely **orthogonal**. The plan of record is an
**A+C proof-of-concept** ([poc-sdk-style-debugging-plan.md](poc-sdk-style-debugging-plan.md)):
author a minimal `nanoFramework.Sdk` + inject the capability, keep the AD7 engine
behind an engine-binding abstraction so Concord can be swapped later. Build, pack,
and test via the CLI are not blocked and are the near-term deliverable. See
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
| 06 | [06-ide-integration.md](06-ide-integration.md) | Thin-extension/fat-SDK split; what moves now vs. behind the debugger gate; VS Code path |
| 07 | [07-library-migration.md](07-library-migration.md) | Fleet migration of ~100+ `lib-*` repos; the embedded converter; leaf-first order; what-breaks table; CI rewrite |
| 08 | [08-nuget-pipeline.md](08-nuget-pipeline.md) | Managed package layout (`lib/netnano1.0/`); `Pack` overrides; nuspec→Pack metadata |
| 09 | [09-implementation-strategy.md](09-implementation-strategy.md) | Minimum viable SDK; phases; coexistence; the debugger gate; risk register |
| 10 | [10-tooling-specs.md](10-tooling-specs.md) | Build-list of managed components; task signatures; `dotnet new` templates; consolidated target graph; acceptance criteria |

### POC & analysis (added by the executed proof-of-concept)

| Document | What it covers |
|----------|----------------|
| [poc-sdk-style-debugging-plan.md](poc-sdk-style-debugging-plan.md) | The A+C POC plan: workstreams WS1–WS4, the engine-binding seam, the decision gate |
| [poc-sdk-style/RESULTS.md](../../../poc-sdk-style/RESULTS.md) | **Executed POC results**: what's proven on a plain machine, the gates hit, WS4 (Layer A/B) runbook + Azure pipeline |
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

3. **The VS debugger gates SDK-style as a supported format** — the central
   constraint the plan is built around.
