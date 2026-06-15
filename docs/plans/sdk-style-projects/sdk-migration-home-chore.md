<!--
  PASTE-READY body for a nanoFramework/Home "Chore or Task entry" issue
  (.github/ISSUE_TEMPLATE/chore_task.md).

  ⚠️ That template is "[ONLY for Team Members]". Use this variant only if you're on the
  team and want to track this as an epic/task. Otherwise file the Feature request version
  (sdk-migration-home-issue.md).

  Suggested title: [Epic] SDK-style MSBuild project system migration
  Labels: Type: Chores (auto) — consider also: enhancement, area-Config-and-Build,
          area-Infrastructure-and-Organization, FEEDBACK REQUESTED

  Keep the "Details about Problem" headings and the "<!-- todo-tag DO NOT REMOVE -->"
  marker (the chore template requires them). All links are absolute permalinks pinned to
  commit b8c2ede in danielmeza/nf-Visual-Studio-extension.
-->

## Details about Problem

nanoFramework area: **Visual Studio extension** (also MDP / CLI / MSBuild project system)

VS version (if relevant): Visual Studio 2022

VS extension version (if relevant): POC build off `2022.x` (dev `9.99.999.0`)

Target (if relevant): ESP32_S3_OCTAL

Firmware image version (if relevant): nanoCLR `2.0.0.467` (mscorlib native `100.22.0.4`, checksum `0x2D5CA905`)

## Description

<!-- todo-tag DO NOT REMOVE -->

**Epic:** move .NET nanoFramework from the legacy flavored `.nfproj` project system to an
**SDK-style** MSBuild project system (`<Project Sdk="…">`) — unlocking the `dotnet` CLI
(build / restore / pack / test), cross-platform builds, and standard NuGet, and retiring
the custom project flavor.

**Status — the VS-debugger gate is proven solvable.** A proof-of-concept deploys and
debugs (F5 + source breakpoints) an SDK-style project on real hardware with the existing
AD7 engine **unchanged**. The gate was build-targets composition + the `NanoCSharpProject`
capability — not the engine.

### Demo

SDK-style project deploying and **F5 debugging with breakpoints hitting on a real
ESP32_S3_OCTAL**:

<!-- ⬇️ Drag-and-drop the recorded video below this line in the GitHub editor; GitHub
     inserts a https://github.com/user-attachments/assets/… URL that renders inline.
     Then delete this comment and the placeholder. -->

_➡️ video to be attached here_

### What the POC proved (commit [`b8c2ede`](https://github.com/danielmeza/nf-Visual-Studio-extension/commit/b8c2edeb1ff775e3f78ba74af9ed384d1ee5c333))

A minimal [`nanoFramework.Sdk`](https://github.com/danielmeza/nf-Visual-Studio-extension/tree/b8c2edeb1ff775e3f78ba74af9ed384d1ee5c333/poc-sdk-style/nanoFramework.Sdk/Sdk)
composing over `Microsoft.NET.Sdk` + capability injection makes an SDK-style
[`Blink.csproj`](https://github.com/danielmeza/nf-Visual-Studio-extension/blob/b8c2edeb1ff775e3f78ba74af9ed384d1ee5c333/poc-sdk-style/samples/Blink/Blink.csproj)
build, deploy, run, and debug. Concrete fixes (full record:
[DEBUGGING-LOG.md](https://github.com/danielmeza/nf-Visual-Studio-extension/blob/b8c2edeb1ff775e3f78ba74af9ed384d1ee5c333/poc-sdk-style/DEBUGGING-LOG.md)):

- **Breakpoints** — SDK forces `DebugType=full` for Debug (Windows/full PDB; portable made VS bind at the method entry).
- **Deploy version mismatch** — relax the extension's deploy pre-check to a checksum match.
- **F5 launched a console app** — SDK removes the `LaunchProfiles` capability + sets `DebuggerFlavor=NanoDebugger`.
- **Legacy `.nfproj` + SDK `.csproj` load side by side** in the experimental instance.

### Work checklist

- [x] NFProjectSystem targets import fixed for SDK-style/imported contexts — the POC SDK owns the import chain (composes over `Microsoft.NET.Sdk`)
- [x] Experimental CLI build/pack/test validated — POC `Blink` builds `.pe`/`.pdbx`, cross-platform
- [x] **Gate:** VS debugger works on SDK-style projects — **PROVEN on real hardware** (deploy + F5 + source breakpoints)
- [ ] Agree direction, the `nanoFramework.Sdk` repo home, and interim-shape policy
- [ ] Packages republished targeting `netnano1.0`
- [ ] Fold the POC fixes into the shipped extension (and strip the `[BP-DIAG]` diagnostics)
- [ ] SDK-style supported as an option; preview `nanoFramework.Sdk` published
- [ ] Fleet migration (leaf-first) of the `lib-*` repos
- [ ] Legacy project system deprecated (kept supported during transition)

### Design + decision record

- Full specification set: [`docs/plans/sdk-style-projects/`](https://github.com/danielmeza/nf-Visual-Studio-extension/tree/b8c2edeb1ff775e3f78ba74af9ed384d1ee5c333/docs/plans/sdk-style-projects)
- Decision record (every blocker + fix, §1–§6): [`DEBUGGING-LOG.md`](https://github.com/danielmeza/nf-Visual-Studio-extension/blob/b8c2edeb1ff775e3f78ba74af9ed384d1ee5c333/poc-sdk-style/DEBUGGING-LOG.md) · results: [`RESULTS.md`](https://github.com/danielmeza/nf-Visual-Studio-extension/blob/b8c2edeb1ff775e3f78ba74af9ed384d1ee5c333/poc-sdk-style/RESULTS.md)
- Multi-device Run-selection design: [`DEVICE-RUN-DROPDOWN.md`](https://github.com/danielmeza/nf-Visual-Studio-extension/blob/b8c2edeb1ff775e3f78ba74af9ed384d1ee5c333/poc-sdk-style/DEVICE-RUN-DROPDOWN.md)
- POC branch: [`poc/sdk-style-debugging`](https://github.com/danielmeza/nf-Visual-Studio-extension/tree/poc/sdk-style-debugging)
- Related: [#1635](https://github.com/orgs/nanoframework/discussions/1635) · [Home#1067](https://github.com/nanoframework/Home/issues/1067) · [nf-Visual-Studio-extension#889](https://github.com/nanoframework/nf-Visual-Studio-extension/pull/889)
