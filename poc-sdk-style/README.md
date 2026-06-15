# POC: SDK-style nanoFramework projects + engine-binding seam

Proof-of-concept for `poc-sdk-style-debugging-plan.md`. Proves a minimal,
reusable `nanoFramework.Sdk` can build an SDK-style project and emit a correct
`.pe`/`.pdbx` with no Visual Studio, and lands the engine-binding seam (WS3) that
makes a future AD7→Concord swap contained.

## Quickstart

```bash
./build-and-verify.sh
```

Builds the SDK package, builds the 6-line `samples/Blink` app, confirms the
emitted `Blink.pe` is a real nanoFramework PE, byte-compares it against a
legacy-shaped MDP invocation, and checks the `NanoCSharpProject` capability.

Requires: .NET SDK, and (cached on first restore) `nanoFramework.CoreLibrary`
1.17.11 + `nanoFramework.Tools.MetadataProcessor.MsBuildTask` 3.0.100.

## What's here / what it proves / what's open

See **[RESULTS.md](RESULTS.md)** — including the WS4 validation runbook
(headless protocol test with the `nanoclr` virtual device vs. real-VS F5) and
the Azure Pipelines shape.
