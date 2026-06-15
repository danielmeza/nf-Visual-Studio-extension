# legacy-blink — standard-tooling deploy control

A **legacy** (non-SDK-style) nanoFramework C# application. Its only job is to
answer one question:

> Does the **real device** deploy and run a Blink app built with the
> **standard, off-the-shelf nanoFramework tooling** (Visual Studio + the
> nanoFramework VS extension + a published `nanoFramework.CoreLibrary` nuget)?

This is the **control case** for the POC. The POC (`../`) re-hosts the Metadata
Processor and stamps a custom `mscorlib` reference into `Blink.pe`, and that
build fails at CLR link time on the device:

```
Link failure: some assembly references cannot be resolved!!
Assembly: Blink (0.0.0.0) needs assembly 'mscorlib' (100.22.0.4)
Error: a3000000
```

If **this** project deploys and runs, the device + standard toolchain are
healthy and the POC failure is isolated to the re-hosted MDP / custom build
path. If this project *also* fails to link, the problem is broader (device
firmware vs. any available published `mscorlib`).

## Target device

| Property                | Value                              |
| ----------------------- | ---------------------------------- |
| Target                  | `ESP32_S3_OCTAL`                   |
| nanoCLR version         | `2.0.0.467`                        |
| Native `mscorlib`       | `100.22.0.4`, checksum `0x2D5CA905`|

## Files

| File                       | Purpose                                                        |
| -------------------------- | -------------------------------------------------------------- |
| `Blink.nfproj`             | Legacy MSBuild project. `ProjectTypeGuids` = nanoFramework `{11A8DD76-328B-46DF-9F39-F559912D0360}` + C# `{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}`; `OutputType=Exe`; `TargetFrameworkVersion=v1.0`; imports `NFProjectSystem.*` from the installed extension. |
| `Program.cs`               | Counting Blink loop with a breakpoint-friendly line.           |
| `Properties/AssemblyInfo.cs` | Standard assembly metadata, version `1.0.0.0`.               |
| `packages.config`          | The legacy nuget reference list (`nanoFramework.CoreLibrary`). |
| `nuget.config`             | Restores CoreLibrary from `nuget.org` only — no local/POC feed.|

## CoreLibrary version choice — and the unavoidable caveat

The device runs native `mscorlib` **`100.22.0.4`** with checksum
**`0x2D5CA905`**. The CLR linker resolves an assembly reference by matching the
referenced `mscorlib` against the one already flashed in the firmware.

Published CoreLibrary nugets and their native `mscorlib` identity:

| Nuget version          | Native `mscorlib` version | Checksum     | Matches device?                |
| ---------------------- | ------------------------- | ------------ | ------------------------------ |
| `2.0.0-preview.49`     | **100.22.0.4**            | `0xE3176D8B` | version YES, checksum NO       |
| `2.0.0-preview.52`     | 100.22.0.5                | `0x2D5CA905` | version NO, checksum YES       |
| `1.16.x` / `1.17.x` (stable) | 1.x                 | n/a          | NO (wrong major native line)   |

**No published nuget has `100.22.0.4` + `0x2D5CA905` simultaneously** — that
exact pair only exists in the firmware flashed on the device.

This project pins **`2.0.0-preview.49`** because:

1. It is on the **v2 preview (native `100.x`) line**, the same major native line
   as the device. The `1.x` stable nugets are native version `1.x` and can never
   resolve against a `100.x` device, so they are not candidates.
2. Its native `mscorlib` version is an **exact match** for the device's
   `100.22.0.4`. The link resolver keys primarily on the assembly *version*, so
   this is the published package most likely to link.

> Caveat: because the published `100.22.0.4` payload differs from the device's
> (checksum `0xE3176D8B` vs `0x2D5CA905`), even standard tooling may hit the
> same `a3000000` link failure if the CLR also validates the checksum. If
> preview.49 fails, retry with **`2.0.0-preview.52`** (matching checksum,
> version 100.22.0.5) by editing the version in `Blink.nfproj`,
> `packages.config`, and the `HintPath`. If *both* fail the same way, the
> conclusion is that this device's firmware is out of band with every published
> CoreLibrary — i.e. the device needs reflashing to a firmware whose bundled
> `mscorlib` matches a published nuget, which would also explain the POC
> blocker.

## Build & deploy from Visual Studio

Prerequisites:

- Visual Studio 2022 with the **.NET nanoFramework** extension installed
  (Extensions → Manage Extensions → search "nanoFramework"). The extension
  provides the `NFProjectSystem.*` MSBuild targets this `.nfproj` imports.
- The ESP32_S3_OCTAL connected over USB and visible in **Device Explorer**
  (View → Other Windows → Device Explorer) showing nanoCLR `2.0.0.467`.

Steps:

1. Open `Blink.nfproj` in Visual Studio (or add it to a solution and open that).
2. Let nuget restore `nanoFramework.CoreLibrary 2.0.0-preview.49` from
   `nuget.org` (right-click solution → Restore NuGet Packages if needed).
3. **Build** (Build → Build Solution). Expect `Build succeeded` and a
   `bin\Debug\Blink.pe` produced by the *installed* extension's MDP (not the POC
   one).
4. In **Device Explorer**, select the ESP32_S3_OCTAL device.
5. Press **F5** (Debug → Start Debugging) to deploy + run, or right-click the
   project → **Deploy** to flash without the debugger.

## What confirms "the device deploys + runs with standard tooling"

Success = ALL of:

- Build succeeds and emits `bin\Debug\Blink.pe`.
- Deployment completes without the link error — specifically you do **NOT** see:
  `Link failure: some assembly references cannot be resolved!!` /
  `needs assembly 'mscorlib' (100.22.0.4)` / `Error: a3000000`.
- The device reboots into the managed app and the **Output / Debug** window
  streams the loop:
  ```
  Blink 0
  Blink 1
  Blink 2
  ...
  ```
  (roughly one line per second).
- (F5) A breakpoint set on the `Debug.WriteLine($"Blink {counter}");` line is
  hit, and `counter` increments each time you continue.

If you get the running counter, the device + standard toolchain deploy and run a
managed app correctly, and the POC `a3000000` failure is confined to the
re-hosted/custom build path — not the device.

Failure = the `a3000000` link error appears even here. In that case retry with
preview.52 (see the caveat above) before concluding the device firmware itself
is the problem.
