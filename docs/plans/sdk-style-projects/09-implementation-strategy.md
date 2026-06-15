# 09 — Implementation Strategy & Phasing

A phased plan, the coexistence story, the minimum viable SDK, and the debugger
gate that governs everything debugger-dependent.

**Scope note.** Managed project system only. Native module compilation, native
binaries in NuGet packages, and OTA are out of scope (separate, later effort) and
are not part of any phase below.

---

## 9.1 Guiding constraints

1. **Never flag-day the fleet.** Old `.nfproj` and the new SDK must build side by
   side for the whole transition.
2. **The VS debugger is the gate.** A move to SDK-style as a *supported* format is
   blocked on the Visual Studio debugger (the project flavor's debug/F5 path is
   tied to the old project system — see §9.5 and
   [#1635](https://github.com/orgs/nanoframework/discussions/1635)). Build, pack,
   and test via the CLI are *not* blocked by this and can proceed.
3. **The TFM already exists.** `netnano1.0` is a recognized TFM (doc 02 §2.2). The
   only gap is that packages aren't published against it yet — unblocked work.

## 9.2 The minimum viable SDK (MVS)

The smallest useful thing to ship first — a **managed-only SDK** that reproduces
today's build via the CLI with none of the pain:

**In scope for MVS:**
- `nanoFramework.Sdk` composing over `Microsoft.NET.Sdk` (doc 02 §2.3).
- `netnano1.0` resolves and restores; packages republished to target it.
- `NanoEmitPe` re-hosting MDP with incrementality + checksum-as-property (doc 04).
- Default globs, `PackageReference`, `dotnet build`/`restore`/`pack`/`test`.
- `dotnet pack` → `lib/netnano1.0/` with `.pe`/`.pdbx`/`.dll`/`.xml`.
- `dotnet new nanoapp`/`nanolib` templates.

**Explicitly out of MVS:**
- Anything native or OTA (out of scope entirely).
- **VS debugging on SDK-style projects** — blocked by the debugger gate (§9.5).
  MVS targets the CLI and VS Code build; F5 debugging stays on legacy `.nfproj`.

MVS value: a `lib-*` repo can convert to a ~6-line `.csproj`, drop
`packages.config`/`.nuspec`/the project-system path hack, and `dotnet
build`/`pack`/`test` on a clean machine. That justifies shipping it even while VS
debugging remains on the legacy path.

## 9.3 Phases

### Phase 0 — Foundations (weeks)
- Read the real `NFProjectSystem.*` targets; map `GenerateBinaryOutputTask` I/O
  onto `NanoEmitPe` (doc 02 §2.6, doc 04 §4.1).
- Stand up the SDK package skeleton + `Sdk.props`/`Sdk.targets` composing over
  `Microsoft.NET.Sdk`; the SDK owns the import chain so the
  `Microsoft.CSharp.CurrentVersion.targets` double-import (#1635/#1067) can't recur.
- **Exit:** a hand-written ~6-line `.csproj` builds a `.pe` byte-identical to the
  legacy `.nfproj` for a sample library.

### Phase 1 — Unblocked groundwork ships (managed, CLI)
- Incremental `NanoEmitPe`, checksum property, `FileWrites`/clean.
- **Republish packages targeting `netnano1.0`** so restore stops falling back to
  `net` (doc 02 §2.2, doc 08 §8.1).
- `dotnet pack` managed layout (doc 08 §8.2).
- Templates (`nanoapp`/`nanolib`); the migration tool for the managed long tail.
- VS Code extension switched to `dotnet build` (doc 06).
- **Coexistence:** legacy `.nfproj` untouched; SDK opt-in; VS debugging stays legacy.
- **Exit:** a pilot set of ~5 pure-managed `lib-*` repos build/pack/test from the CLI.

### Phase 2 — Debugger enablement: the A+C POC (THE GATE) ⛔
- Run the read-only local diagnosis ([debugger-blocker-diagnosis-prompt.md](debugger-blocker-diagnosis-prompt.md)) to
  confirm the hypothesis (§9.5).
- Execute the **A+C POC** ([poc-sdk-style-debugging-plan.md](poc-sdk-style-debugging-plan.md)): minimal
  `nanoFramework.Sdk` composing over `Microsoft.NET.Sdk` (WS1) + `NanoCSharpProject`
  capability injection onto SDK-style projects (WS2), behind an engine-binding
  abstraction (WS3) that keeps the AD7 engine now and allows a Concord swap later.
- **Gate (WS4):** an SDK-style sample loads in VS, deploys via F5, and a breakpoint
  binds and hits with the AD7 engine.
- If the gate fails at engine attach, the abstraction makes the Concord engine
  (model on the Concord **Iris** sample) a contained next workstream — WS1/WS2 stand.

### Phase 3 — SDK-style as a supported option (post-gate)
- VS debug / F5 on SDK-style projects via the path proven in Phase 2; the deploy
  crawler works against SDK-style (related: nf-Visual-Studio-extension#889).
- CPS capability injection generalized; SDK-style projects load in VS.
- (Optional, parallel) AD7 → Concord engine migration for future-proofing.
- **Exit:** full IDE parity for managed projects without the legacy project type.

### Phase 4 — Fleet migration + deprecation
- Bulk-convert the remaining `lib-*` via the migration tool + shared CI template.
- Default `dotnet new` to `.csproj`.
- Deprecate (not delete) the legacy flavored `.nfproj`.

## 9.4 Coexistence mechanics during transition

| Concern | Mechanism |
|--------|-----------|
| Both project types build | SDK ships alongside `NFProjectSystem.*`; neither imports the other |
| VS debugging | Stays on legacy `.nfproj` until the gate (Phase 2) lifts |
| Cross-references | `ProjectReference` both ways; `PackageReference` both ways within the TFM (doc 03) |
| Feed compatibility | Packages target `netnano1.0`; managed assets only |
| CI runs both | Legacy repos keep MSBuild steps; migrated repos use `dotnet` steps |

## 9.5 The debugger gate (why Phase 2 exists)

The maintainer attributes the SDK-style block to the **VS debugger**
([#1635](https://github.com/orgs/nanoframework/discussions/1635)): moving to
SDK-style isn't viable as a supported format right now, with hope that a future VS
version improves it; the `dotnet` CLI flow is not yet officially supported.

**A code-level read of `nf-Visual-Studio-extension` refines this** (working
hypothesis, validated by the POC):
- The VS project system is **already CPS** (`<ProjectCapability Include="CPS" />`;
  `NanoCSharpProject{Unconfigured,Configured}.cs`).
- Deploy (`IDeployProvider`) and debug-launch (`DebugLaunchProviderBase`) are CPS
  providers keyed off the `NanoCSharpProject` capability; the engine is **launched
  by GUID** (`CorDebug.EngineGuid`) and doesn't inspect the project format.

So the concrete gate decomposes into **(1) build-targets composition** (the nano
targets import the legacy MSBuild chain and collide with `Microsoft.NET.Sdk`,
#1635) and **(2) project-type registration / capability injection**. The **AD7
engine is orthogonal** and should attach to an SDK-style CPS project once it
carries the capability. Migrating **AD7 → Concord** is separate modernization
(future-proofing against AD7 deprecation), not the unlock.

What is and isn't blocked:
- **Not blocked:** build, pack, and test. MDP and the test adapter look only at
  build *outputs* and standard MSBuild items, so they're project-type agnostic.
- **The gate (under test):** SDK-style projects loading + debugging in VS — gated
  on (1)+(2), **not** on rewriting the engine, if the hypothesis holds.

**Plan of record:** the A+C proof-of-concept ([poc-sdk-style-debugging-plan.md](poc-sdk-style-debugging-plan.md))
authors a minimal `nanoFramework.Sdk` + injects the capability, keeps the AD7
engine, and puts an engine-binding abstraction in place so Concord can be swapped
later. A read-only local diagnosis ([debugger-blocker-diagnosis-prompt.md](debugger-blocker-diagnosis-prompt.md))
confirms the hypothesis first. If the POC's F5-breakpoint gate fails at engine
attach, the abstraction makes the Concord engine a contained next workstream
rather than a cross-cutting rewrite.

## 9.6 Out of scope: native and OTA

Native module compilation, relocatable native linking, shipping native binaries
in NuGet packages, CoreRuntime firmware packaging, toolchain packs, and the OTA
update system are a **separate effort** and are not part of this plan. Keeping the
managed project-system migration narrow is what makes it safe to pursue
independently of those much larger pieces.

## 9.7 Risk register

| Risk | Likelihood | Mitigation |
|------|-----------|-----------|
| VS debugger gate doesn't lift (no VS support; rewrite too costly) | High | Ship all unblocked value in Phase 1 (CLI build/pack/test); keep VS debugging on legacy `.nfproj` indefinitely if needed |
| `GenerateBinaryOutputTask` semantics subtly differ when re-hosted | Medium | Phase 0 byte-identical `.pe` exit gate |
| `NFProjectSystem.CSharp.targets` double-import recurs | Medium | SDK owns the import chain (#1635/#1067) |
| x64 task / nodeReuse regressions | Low–Med | Ship multi-arch task; SDK controls node reuse |
| Packages not republished against `netnano1.0` | Medium | Mechanical republish; until then consumers use `AssetTargetFallback` |
| Fleet migration stalls (volunteer time) | High | Migration tool + shared CI template reduce per-repo cost to ~minutes; leaf-first ordering |
