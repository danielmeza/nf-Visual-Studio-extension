# Execution plan — land the POC into `nanoFramework.NET.Sdk` + the extension

How the POC's results get contributed upstream now that the official SDK repo exists.
Status of the POC itself: build + deploy + **F5/breakpoints proven on real hardware**
(see [RESULTS.md](RESULTS.md), [DEBUGGING-LOG.md](DEBUGGING-LOG.md)).

## Workspace & repos (all cloned; forks + upstreams wired)

All clones live under `D:\src\nnf\`; each `origin` = a `danielmeza/*` fork, `upstream` =
`nanoframework/*`. The `lib-*` fleet (doc 07) is intentionally **excluded** — later phase.

| Repo | Role in the plan | Clone dir | Branch |
|---|---|---|---|
| **nanoFramework.NET.Sdk** | SDK contribution (A1–A4) | `nanoFramework.Sdk` | **`poc/vs-debugging-enablers`** (off `move-to-sdk`) |
| **nf-Visual-Studio-extension** | extension fixes (B) | `nf-Visual-Studio-extension` | **`poc/sdk-style-debugging`** |
| metadata-processor | MDP build task (A4, only if targeting v2) | `metadata-processor` | `main` |
| CoreLibrary | corlib SDK-migration (special case) + validation | `nanoFramework-CoreLibrary` | `main` — fork keeps the **old** name; ~51 behind `upstream/CoreLibrary`, sync when tackling corlib |
| Samples | end-to-end validation (deploy/debug a real app) | `Samples` | `main` |
| nf-VSCodeExtension | consumer simplification (later phase) | `nf-VSCodeExtension` | `main` |

Baseline: the SDK's `nanoFramework.Tools.BuildTasks` builds clean (0 errors; only an
NU1903 advisory on `Microsoft.Build.Utilities.Core`).

## Organization — follow the POC's layout

Carry the POC's modular, self-documenting layout into the contribution rather than growing
the official monolithic `Sdk.targets`:
- **`Sdk/Rules/`** folder for XAML rules (e.g. `NanoDebugger.xaml`) — as in the POC.
- Keep **debugging / MDP concerns in their own include(s)** (the POC split out
  `nanoFramework.Mdp.targets`) so the additions stay reviewable + separable, with clear
  sectioning and comments.
- A self-contained **`test/`** sample that exercises build → deploy → F5 (mirrors the POC's
  `samples/Blink`).
- Don't restructure the maintainers' existing files beyond what each change needs; offer the
  fuller split as a follow-up only if they want it.

## Naming — align to the official name

The official package is **`nanoFramework.NET.Sdk`** (per `SDK naming.md`, the
`<Org>.NET.Sdk` pattern, mirroring `Tizen.NET.Sdk`). The POC used `nanoFramework.Sdk`;
all contributions use **`nanoFramework.NET.Sdk`**.

## Gap analysis — official `move-to-sdk` vs the POC

**Already in the official SDK** (no work needed): `Microsoft.NET.Sdk` composition;
`netnano1.0` TFM + identity; `AssetTargetFallback=net`/`NoStdLib`/`TargetingClr2Framework`;
`DebuggerFlavor=NanoDebugger` (`Sdk.props`); `NanoCSharpProject` capability (`Sdk.targets`);
the full MDP pipeline (parse→compile, stubs, core-lib path, resource gen, binary output);
bundled build tasks; auto-injected MDP package (`3.0.29`).

**Missing — the POC's debugging enablers** (what makes VS *deploy + debug*, not just build):

| # | Gap | Fix (from the POC) | Where |
|---|---|---|---|
| A1 | **Breakpoints bind at method entry** | emit a **Windows/full PDB** for Debug: set `DebugType=full` **before** the `Microsoft.NET.Sdk` import (so its `==''→portable` default is pre-empted; under VS's .NET-Framework csc this yields a Windows PDB) | `Sdk/Sdk.props` |
| A2 | **F5 can launch a console app** | `<ProjectCapability Remove="LaunchProfiles" />` so the C# project system's launcher doesn't own F5 (the `DebuggerFlavor` alone isn't enough) | `Sdk/Sdk.targets` |
| A3 | **No debugger property page** | ship `Rules/NanoDebugger.xaml` + a `PropertyPageSchema` (`Context=Project`) | SDK `Sdk/Rules/` + targets |
| A4 | **v2 devices reject the PE** (`NFMRK1` vs `NFMRK2`) | bump MDP `3.0.29 → 4.x` (emits `NFMRK2`) **and** fix the MDP task TFM `net6.0 → net8.0` for `MSBuildRuntimeType==Core` (4.x ships `net8.0`+`net472`) — *discuss with maintainers; depends on target firmware line* | `Sdk/Sdk.props` (`NanoFrameworkMDPVersion`) + `Sdk/Sdk.targets` (`_NfMdpTasksTFM`) |

(The breakpoint fix is **entirely SDK-side** — A1. The engine reads the Windows PDB
already; the POC's `[BP-DIAG]` was only diagnostics.)

**Extension-side** (separate PR, already on `poc/sdk-style-debugging`):

| # | Change | File |
|---|---|---|
| B1 | Deploy pre-check relaxed to a **checksum** match (firmware native-version label is cosmetic) | `DeployProvider/DeployProvider.cs` |
| B2 | Deploy follows the **Device Explorer SelectedDevice**; engine binding uses the chosen device's port | `DeployProvider.cs`, `DebugLauncher/Ad7CorDebugEngineBinding.cs` |
| B3 | **Strip the `[BP-DIAG]` diagnostics** before the PR | `CorDebug/{PdbxFile,CorDebugBreakpoint,CorDebugFunction,CorDebugCode}.cs` |
| B4 | *(future)* per-device Run dropdown | see [DEVICE-RUN-DROPDOWN.md](DEVICE-RUN-DROPDOWN.md) |

## Order of execution

1. **A1–A3** in `nanoFramework.NET.Sdk` (`poc/vs-debugging-enablers`) — the debugging
   enablers. Small, additive, proven.
2. **Validate**: pack the SDK; `test/SmokeTest` builds; then the SDK-style **Blink on a
   real ESP32 → deploy + F5 + breakpoint** (the POC's WS4) using the official SDK.
3. **A4** (MDP version) — only if targeting v2 firmware; coordinate with maintainers.
4. **B1–B3** in the extension — clean up + PR.

## Validation gates

- `dotnet build` an SDK-style lib + app against the packed `nanoFramework.NET.Sdk` →
  `.pe` + **Windows** `.pdbx`/`.pdb`.
- Debug build's `.pdb` magic = `Microsoft C/C++ MSF` (not `BSJB`) under VS MSBuild.
- On hardware: F5 deploys, a source breakpoint **binds + hits** (not method-entry).

## PR strategy

- **SDK:** PR `danielmeza:poc/vs-debugging-enablers → nanoframework:move-to-sdk`. Title
  e.g. *"Enable VS debugging for SDK-style projects (full PDB, F5 wiring)"*; link
  `Home#1784`, the POC `RESULTS.md`/`DEBUGGING-LOG.md`, and the demo (https://youtu.be/9qvXsgXCrjM).
- **Extension:** PR `danielmeza:poc/sdk-style-debugging → nanoframework:develop` after
  stripping `[BP-DIAG]`; scope to B1–B2.

## Open questions for maintainers

- MDP version line (A4): is `move-to-sdk` targeting v1 (`NFMRK1`) or v2 (`NFMRK2`) firmware?
- Is the `DebugType=full` (Windows-PDB-under-VS) approach acceptable, or do they want a
  portable→Windows PDB conversion (Pdb2Pdb) for the `dotnet`-CLI path too?
- Package naming already settled: `nanoFramework.NET.Sdk`.
