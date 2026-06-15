# nanoFramework SDK-Style Project System Migration — Specification Set

**Status:** Draft v2
**Scope:** Migration of .NET nanoFramework from the legacy `.nfproj` flavored
project system to a first-class MSBuild SDK — **managed project system only**.
**Audience:** nanoFramework core contributors with CLR-internals and MSBuild
expertise.

---

## 0.1 Why this exists

The legacy project system relies on a project flavor, MSBuild targets shipped via
the VS / VS Code extensions, `packages.config`, hand-written `.nuspec`, AnyCPU-only
builds, and an x64-task / `nodeReuse` workaround. That couples builds to the IDE
extensions and diverges from mainstream .NET tooling, making the CLI and CI story
harder than it should be. This set specifies a move to an MSBuild **SDK**, so that
`dotnet build` / `dotnet pack` / `dotnet test` work on a clean machine with only
the .NET SDK and a NuGet restore.

## 0.2 Scope boundary (read this first)

This is a **managed project-system migration**. The following are **out of scope**
and belong to a separate, later effort — they are deliberately absent from these
specs and must not be reintroduced:

- OTA update system.
- Modular / relocatable native firmware packaging, native compile/link, and any
  native binaries shipped inside NuGet packages (`runtimes/{rid}/native/`,
  pre-linked modules, module/ABI manifests, CoreRuntime firmware packs, toolchain
  packs).
- Any firmware- or device-side changes.

NuGet packages in scope ship **managed** assets only (`.pe` + reference `.dll` +
`.pdbx` + `.xml`).

## 0.3 The blocker — and what the code actually shows ⛔

The maintainer attributes the SDK-style block to the **VS debugger**
([#1635](https://github.com/orgs/nanoframework/discussions/1635)). A code-level
read of `nf-Visual-Studio-extension` (`develop`) **refines** that into a more
decomposable picture, which is the current working hypothesis (to be confirmed by
the POC below):

- The VS project system is **already CPS**, not a legacy MPF flavor
  (`NanoCSharpProject{Unconfigured,Configured}.cs`;
  `<ProjectCapability Include="CPS" />` in `NFProjectSystem.targets`).
- Deploy (`DeployProvider : IDeployProvider`) and debug-launch
  (`NanoDebuggerLaunchProvider : DebugLaunchProviderBase`) are **CPS providers**
  keyed off the `NanoCSharpProject` capability, and the engine is **launched by
  GUID** (`LaunchDebugEngineGuid = CorDebug.EngineGuid`). None of this inspects the
  project-file format.

So the concrete gate appears to be **(1) build-targets composition** — the nano
targets import the legacy MSBuild chain and collide with `Microsoft.NET.Sdk`
(#1635) — and **(2) project-type registration / capability injection** onto
SDK-style projects. The **AD7 debug engine (`CorDebug`) is orthogonal**: launched
by GUID, it should attach to an SDK-style CPS project once that project carries the
capability. Migrating the engine **AD7 → Concord** is separate modernization
(future-proofing against AD7 deprecation), **not** the unlock.

**Plan of record:** an A+C proof-of-concept (author a minimal `nanoFramework.Sdk`
+ inject the capability, keep the AD7 engine, behind an engine-binding abstraction
so Concord can be swapped later) — see
[poc-sdk-style-debugging-plan.md](poc-sdk-style-debugging-plan.md). A read-only local
diagnosis ([debugger-blocker-diagnosis-prompt.md](debugger-blocker-diagnosis-prompt.md))
validates the hypothesis first. **The POC has been executed** — results, WS4 runbook,
and decision gate are in [poc-sdk-style/RESULTS.md](../../../poc-sdk-style/RESULTS.md).

What this still means in practice:

## 0.3.1 Blocked vs. not blocked

- **Not blocked:** build, pack, and test via the CLI. MDP and the test adapter
  look only at build outputs and standard MSBuild items, so they're project-type
  agnostic.
- **Blocked:** VS debugging on SDK-style projects, and therefore retiring the
  flavor.

The plan (doc 09) delivers all the unblocked value first and treats the debugger
as an explicit gate; it is not solvable by the SDK or the build tooling.

## 0.4 Corrected premises

Two framing assumptions from the original prompt that the codebase / ecosystem
have invalidated:

1. **MDP is already an MSBuild task**, not an external post-build tool. It ships as
   `nanoFramework.Tools.MetadataProcessor.MsBuildTask` wired into
   `NFProjectSystem.MDP.targets` (`GenerateBinaryOutputTask` et al.), with a
   `.CLI` variant for runtime-codegen. The work is **re-hosting** it inside an SDK
   with proper incrementality and ordering (doc 04).
2. **`netnano1.0` is a real, recognized TFM.** It appears in the
   [Microsoft TFM table](https://learn.microsoft.com/en-us/dotnet/standard/frameworks#supported-target-frameworks)
   (".NET nanoFramework → `netnano1.0`"), recognized by the .NET SDK and NuGet
   client. The real gap is narrower: nanoFramework's **packages aren't published
   against `netnano1.0`** yet (consumers fall back to `net` to restore — see
   [#1635](https://github.com/orgs/nanoframework/discussions/1635)), and projects
   still use `packages.config`. Closing that is unblocked work (doc 02 §2.2).

Two further realities the specs build on:

- The current project-system files (`NFProjectSystem.Default.props`,
  `NFProjectSystem.props`, `NFProjectSystem.CSharp.targets`,
  `NFProjectSystem.MDP.targets`) are distributed via the **VS extension**
  (`$(MSBuildExtensionsPath)\nanoFramework\v1.0\`) and the **VS Code extension**
  (`dist/utils/nanoFramework/v1.0/`), located via
  `$(NanoFrameworkProjectSystemPath)`. One of them
  (`NFProjectSystem.CSharp.targets`) re-imports
  `Microsoft.CSharp.CurrentVersion.targets`, which collides in SDK-style/imported
  contexts (#1635, #1067) — the SDK must own the import chain.
- The project flavor GUID `{11A8DD76-328B-46DF-9F39-F559912D0360}` (plus the C#
  GUID `{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}`) is what makes VS load the custom
  project system, and is tied to the debugger gate (doc 06).

## 0.5 Document map

| Doc | Title |
|-----|-------|
| 00 | Overview (this doc) |
| [01](01-current-state.md) | Current State Analysis |
| [02](02-sdk-design.md) | SDK Design: `nanoFramework.Sdk`, the TFM, the target graph |
| [03](03-project-file-migration.md) | Project File Migration |
| [04](04-mdp-native-integration.md) | Metadata Processor (MDP) Integration |
| [05](05-cli-experience.md) | CLI Experience (`dotnet build/deploy/new/watch`) |
| [06](06-ide-integration.md) | Visual Studio & VS Code Integration (debugger-gated) |
| [07](07-library-migration.md) | Library Repository Migration (~100+ repos) |
| [08](08-nuget-pipeline.md) | NuGet Pipeline (managed `pack`) |
| [09](09-implementation-strategy.md) | Implementation Strategy & Phasing |
| [10](10-tooling-specs.md) | Tooling Specifications, Package Layouts, Templates |
| [POC](poc-sdk-style-debugging-plan.md) | A+C debugging proof-of-concept (executed: [results](../../../poc-sdk-style/RESULTS.md)) |
| [VSCode](vscode-extension-impact.md) | VS Code extension migration impact |

## 0.6 Naming conventions used across the set

- **SDK package:** `nanoFramework.Sdk` (the MSBuild project SDK). Referenced as
  `<Project Sdk="nanoFramework.Sdk/<version>">`. The SDK package version is
  independent of the TFM.
- **TFM:** `netnano1.0`, long form `.NETnanoFramework,Version=v1.0`.
- **Deploy tool:** `nanoff` remains the on-device executor; the SDK target
  `Deploy` orchestrates it (doc 05).

## 0.7 What "done" looks like (for the unblocked, managed part)

A minimal nanoFramework app is a single `.csproj`:

```xml
<Project Sdk="nanoFramework.Sdk/1.0.0">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>netnano1.0</TargetFramework>
  </PropertyGroup>
</Project>
```

`dotnet build` produces a `.pe` (+ `.pdbx`); `dotnet pack` emits a package with the
managed assets under `lib/netnano1.0/`; `dotnet test` runs the unit tests. No VS
extension is required to build, pack, or test. VS debugging of SDK-style projects
remains on the legacy path until the debugger gate (doc 06, doc 09) lifts.
