# POC: SDK-style nanoFramework projects + engine-binding seam

Proof-of-concept for `poc-sdk-style-debugging-plan.md`. Proves a minimal,
reusable `nanoFramework.Sdk` can build an SDK-style project and emit a correct
`.pe`/`.pdbx` with no Visual Studio, and lands the engine-binding seam (WS3) that
makes a future AD7→Concord swap contained.

## Quickstart

### Command line (no Visual Studio)

```bash
./build-and-verify.sh      # macOS / Linux / Git Bash
build-and-verify.cmd       :: Windows Command Prompt / VS Developer Prompt
```

Both scripts pack the SDK package, build the 6-line `samples/Blink` app, confirm
the emitted `Blink.pe` is a real nanoFramework PE, byte-compare it against a
legacy-shaped MDP invocation, and check the `NanoCSharpProject` capability.

Requires: .NET SDK, and (cached on first restore) `nanoFramework.CoreLibrary`
2.0.0-preview.52 + `nanoFramework.Tools.MetadataProcessor.MsBuildTask` 3.0.100.

### Visual Studio (for the WS4 F5 + breakpoint gate)

Open **`poc-sdk-style.sln`**. It groups the three projects:

- `nanoFramework.Sdk` — packs the reusable MSBuild SDK package.
- `samples/Blink` — the SDK-style app; set it as the startup project to debug.
- `tools/NanoDebugProtocolTest` — the headless Layer A debug-protocol harness.

> **First-open note:** `Blink.csproj` resolves `Sdk="nanoFramework.Sdk/1.0.0"`
> from the `local-feed/`, which is produced by packing `nanoFramework.Sdk`. Run
> `build-and-verify.cmd` (or build the `nanoFramework.Sdk` project) **once**
> before opening, or reload the solution after the first build, so Visual Studio
> can resolve the SDK and load `Blink`.

## What's here / what it proves / what's open

See **[RESULTS.md](RESULTS.md)** — including the WS4 validation runbook
(headless protocol test with the `nanoclr` virtual device vs. real-VS F5) and
the Azure Pipelines shape.
