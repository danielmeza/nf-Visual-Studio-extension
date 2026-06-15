<!--
Suggested title:
  [Proposal] Path toward an SDK-style MSBuild project system (debugger-gated)

Suggested labels: enhancement, area-Config-and-Build,
                  area-Infrastructure-and-Organization, non trivial,
                  blocked, FEEDBACK REQUESTED
-->

# Path toward an SDK-style MSBuild project system

## Summary

This issue tracks the overall effort to move .NET **nanoFramework** from the
flavored `.nfproj` project system toward an **SDK-style** MSBuild project system.

It is written with eyes open about the **known blocker** (the Visual Studio
debugger — see below): a full move to SDK-style is **not possible today**. The
intent of this issue is therefore to (a) agree the destination, (b) line up the
groundwork that is *not* blocked and can start now, and (c) track the debugger
dependency that gates the rest.

This is a **tracking/epic issue**. Detailed design docs will be linked in
follow-up comments; this stays at the plan level.

## Known blocker — the VS debugger, decomposed ⛔

Per maintainer feedback in
[#1635](https://github.com/orgs/nanoframework/discussions/1635), the move to
SDK-style is currently attributed to the **VS debugger**: SDK-style isn't viable
right now, with hope that a future VS version makes it possible; the `dotnet` CLI
flow is not an officially supported path today.

A code-level read of `nf-Visual-Studio-extension` (`develop`) **refines this into
a decomposable picture** — a working hypothesis to be validated by a POC:

- The VS project system is **already CPS**, not a legacy MPF flavor
  (`NanoCSharpProject{Unconfigured,Configured}.cs`;
  `<ProjectCapability Include="CPS" />` in `NFProjectSystem.targets`).
- Deploy (`DeployProvider : IDeployProvider`) and debug-launch
  (`NanoDebuggerLaunchProvider : DebugLaunchProviderBase`) are **CPS providers**
  keyed off a `NanoCSharpProject` capability, and the engine is **launched by GUID**
  (`LaunchDebugEngineGuid = CorDebug.EngineGuid`). None of this inspects the
  project-file format.

So the concrete gate appears to be **(1) build-targets composition** (the nano
targets import the legacy MSBuild chain and collide with `Microsoft.NET.Sdk` —
#1635) and **(2) project-type registration / capability injection**. The **AD7
debug engine is likely orthogonal** — launched by GUID, it should attach to an
SDK-style CPS project once that project carries the capability. The **AD7 → Concord**
engine migration is separate modernization (future-proofing against AD7
deprecation), **not** the unlock.

**Proposed first step — an A+C proof-of-concept:** author a minimal
`nanoFramework.Sdk` composing over `Microsoft.NET.Sdk` + inject the
`NanoCSharpProject` capability, keep the AD7 engine, behind an **engine-binding
abstraction** so a Concord engine can be swapped later without touching the
launch/deploy/project-system layers. The POC gate is: an SDK-style sample loads in
VS, deploys via F5, and a breakpoint binds and hits. A read-only diagnosis confirms
the hypothesis first.

What's reachable regardless of the gate:

- **Build / pack / test.** MDP and the test adapter look only at build *outputs*
  and standard MSBuild items. In
  [#1635](https://github.com/orgs/nanoframework/discussions/1635) an SDK-style
  project targeting `netnano1.0` was made to build (`Microsoft.NET.Sdk` plus
  imported NFProjectSystem targets).
- Prior art on the deploy crawler:
  [nf-Visual-Studio-extension#889](https://github.com/nanoframework/nf-Visual-Studio-extension/pull/889).

## Motivation

The legacy project system relies on a project flavor, MSBuild targets shipped via
the VS / VS Code extensions, `packages.config`, hand-written `.nuspec`, AnyCPU-only
builds and an x64 task / `nodeReuse` workaround. That couples builds to the IDE
extensions and diverges from mainstream .NET tooling, which makes the CLI and CI
story harder than it needs to be. SDK-style would give `dotnet build` / `dotnet
pack`, `PackageReference`, and an IDE-agnostic, CI-friendly experience — once the
debugger story allows it.

## Target framework moniker — already recognized

`netnano1.0` **is** a recognized TFM in the .NET SDK / NuGet client (see the
[Microsoft TFM table](https://learn.microsoft.com/en-us/dotnet/standard/frameworks#supported-target-frameworks)).
The remaining gap is that the nanoFramework **NuGet packages aren't published
against `netnano1.0`** yet — consumers currently fall back to `net` to restore —
and projects still use `packages.config`. Closing that gap is unblocked work
(below) and independent of the debugger.

## Goals

**Near-term (not blocked by the debugger):**

- Publish class-library packages so they properly target `netnano1.0`
  (removing the need for `AssetTargetFallback` to `net`).
- Fix the NFProjectSystem targets so they compose in SDK-style / imported
  contexts without the double-import error (see
  [#1635](https://github.com/orgs/nanoframework/discussions/1635),
  [#1067](https://github.com/nanoframework/Home/issues/1067)).
- Stand up an **experimental, opt-in** CLI build/pack/test path for SDK-style
  projects — explicitly *not* a replacement for the VS experience.
- Keep migration tooling ready for when the gate lifts.

**Gated (require the debugger to work on SDK-style):**

- VS debugging / F5 on SDK-style projects.
- SDK-style as the *supported, default* project format.
- Retiring the project flavor and the legacy `.nfproj`.

## Non-goals — out of scope for this effort

- OTA update system.
- Modular / relocatable native firmware packaging (`runtimes/{rid}/native`,
  ABI / module manifests).
- Any firmware- or device-side changes.

## High-level approach

- Destination is a `nanoFramework.Sdk` (a thin SDK composing over
  `Microsoft.NET.Sdk`, with room to evolve toward a workload).
- The **metadata processor is already an MSBuild task**, so re-host it as an
  incremental target rather than wrapping a shell-out.
- Treat the **VS debugger as an explicit dependency/gate**, tracked against VS /
  VS SDK releases; do not block the unblocked groundwork on it.
- Land changes additively and keep legacy `.nfproj` working throughout.

## Phased rollout (overview only)

- **Phase 0 — Proposal & decisions** (this issue).
- **Phase 1 — Unblocked groundwork**: package `netnano1.0` targeting; targets
  import fix; experimental CLI build/pack/test; migration tooling ready.
- **Phase 2 — Debugger enablement: the A+C POC (THE GATE)**: author a minimal
  `nanoFramework.Sdk` over `Microsoft.NET.Sdk` + inject the `NanoCSharpProject`
  capability, keep the AD7 engine behind an engine-binding abstraction (so Concord
  can be swapped later). Gate: an SDK-style sample loads in VS, deploys via F5, and
  a breakpoint hits. Everything below depends on this passing.
- **Phase 3 — SDK-style as a supported option**: VS debug/F5 on SDK-style via the
  proven path; `nanoFramework.Sdk` published. (Optional, parallel: AD7 → Concord
  for future-proofing.)
- **Phase 4 — Library fleet migration** (leaf-first), using the tooling.
- **Phase 5 — Deprecate** the legacy project system.

## Key open decisions

- Where does `nanoFramework.Sdk` live (new repo vs. `nf-Visual-Studio-extension`)
  and how is it versioned/published?
- Republish strategy for packages targeting `netnano1.0`.
- Whether to support an interim `Microsoft.NET.Sdk` + imported-targets shape (as
  in #1635) vs. waiting for the clean `nanoFramework.Sdk`.

## Affected repositories (initial)

- `nf-Visual-Studio-extension` — project system, build tasks, **and the debugger
  / F5 deployer** (the blocked piece).
- `metadata-processor` — the MDP build task.
- `CoreLibrary` — first validation target (special case).
- `Samples` — end-to-end validation.
- `nf-VSCodeExtension` — consumer; simplifies once the SDK exists.
- new `nanoFramework.Sdk` repo — **TBD**.
- the `lib-*` fleet — later phase.

## Tracking checklist

- [ ] Agree direction, the `nanoFramework.Sdk` repo home, and interim-shape policy
- [ ] Packages republished targeting `netnano1.0`
- [ ] NFProjectSystem targets import fixed for SDK-style/imported contexts
- [ ] Experimental CLI build/pack/test validated on `CoreLibrary` + a `Samples` app
- [ ] **Gate:** VS debugger works on SDK-style projects
- [ ] SDK-style supported as an option; preview `nanoFramework.Sdk` published
- [ ] Fleet migration (leaf-first)
- [ ] Legacy project system deprecated

## References

- Discussion: [#1635 — NFProjectSystem.CSharp.targets import failed in SDK Style project](https://github.com/orgs/nanoframework/discussions/1635)
- Related: [Home#1067](https://github.com/nanoframework/Home/issues/1067),
  [nf-Visual-Studio-extension#889](https://github.com/nanoframework/nf-Visual-Studio-extension/pull/889)
- [Microsoft TFM table (lists `netnano1.0`)](https://learn.microsoft.com/en-us/dotnet/standard/frameworks#supported-target-frameworks)
- [Concord debugger extensibility samples (for a future AD7 → Concord engine; see *Iris*)](https://github.com/microsoft/ConcordExtensibilitySamples)

## Notes

- Detailed design docs will be linked in follow-up comments.
- Migration tooling to convert `.nfproj` → SDK-style and bulk-migrate the fleet
  is already prototyped (emits `netnano1.0`); it supports the later migration
  phase but does not address the debugger gate.
- Feedback on direction and on the open decisions is very welcome. 🙂
