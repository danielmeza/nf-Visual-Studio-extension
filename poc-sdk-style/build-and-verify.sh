#!/usr/bin/env bash
#
# POC: SDK-style nanoFramework v2 (NFMRK2) build + MDP PE emission, end to end.
#
# Builds the modified Metadata Processor (v4, NFMRK2, AssemblyNativeVersion
# stamping) from the metadata-processor submodule, packs it and the
# nanoFramework.Sdk into the local feed, builds the 6-line SDK-style Blink app,
# and verifies the emitted .pe. Proves WS1 (targets composition) and the WS1
# parity gate on any machine with the .NET SDK + a NuGet restore — no Visual
# Studio, no device. WS2/WS3/WS4 are verified as described in RESULTS.md.
#
# Usage:  ./build-and-verify.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here"

# Paths embedded in the generated MSBuild project (step 5) are consumed by the
# Windows .NET MSBuild process, which cannot read Git-Bash/Cygwin POSIX paths
# like /c/Users/... . Convert to native form when cygpath is present (Windows);
# elsewhere (macOS/Linux) the path is already native.
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }

CORELIB_VER="2.0.0-preview.52"
CORELIB_DLL="$HOME/.nuget/packages/nanoframework.corelibrary/$CORELIB_VER/lib/netnano1.0/mscorlib.dll"
MDP_PROJ="$here/../metadata-processor/MetadataProcessor.MsBuildTask/MetadataProcessor.MsBuildTask.csproj"

echo "==> 0. Build + pack the modified Metadata Processor (v4 NFMRK2, native-version stamping)"
dotnet pack "$MDP_PROJ" -c Release -o local-feed -clp:NoSummary | tail -1
MDP_VER="$(ls -1 local-feed/nanoFramework.Tools.MetadataProcessor.MsBuildTask.*.nupkg 2>/dev/null \
  | sed -E 's@.*MsBuildTask\.(.+)\.nupkg@\1@' | sort -V | tail -1)"
[ -n "$MDP_VER" ] || { echo "   FAIL: could not determine packed MDP version"; exit 1; }
echo "   MDP version: $MDP_VER"
# Force re-extract of the freshly packed MDP from the local feed.
rm -rf "$HOME/.nuget/packages/nanoframework.tools.metadataprocessor.msbuildtask/$MDP_VER"
MDP_PKG="$HOME/.nuget/packages/nanoframework.tools.metadataprocessor.msbuildtask/$MDP_VER/lib/net8.0/nanoFramework.Tools.MetadataProcessor.MsBuildTask.dll"

echo "==> 1. Pack the local nanoFramework.Sdk into the local feed"
dotnet pack nanoFramework.Sdk/nanoFramework.Sdk.csproj -o local-feed -clp:NoSummary | tail -1
# Force the SDK resolver to re-extract the freshly packed version.
rm -rf "$HOME/.nuget/packages/nanoframework.sdk/1.0.0"

echo "==> 2. Build the SDK-style sample (Sdk=\"nanoFramework.Sdk/1.0.0\")"
cd samples/Blink
rm -rf bin obj
# Pin the MDP version the SDK consumes to the one we just packed (the SDK's own
# default is a hard-coded pin that may drift from the submodule's git height).
dotnet build -clp:NoSummary -p:NanoMdpTaskPackageVersion="$MDP_VER" \
  | grep -E "Blink.pe|Build succeeded|error|warning" || true

echo
echo "==> 3. Outputs"
ls -la bin/Debug/

PE="bin/Debug/Blink.pe"
echo
echo "==> 4. Confirm it is a real nanoFramework v2 PE (NFMRK2 magic)"
magic="$(head -c 6 "$PE")"
[ "$magic" = "NFMRK2" ] && echo "   OK: $PE starts with NFMRK2" || { echo "   FAIL: bad magic ($magic)"; exit 1; }

echo
echo "==> 5. WS1 parity gate: same IL through a direct MDP invocation, byte-compare"
IL="$(pwd)/obj/Debug/Blink.exe"
tmp="$(mktemp -d)"
legacy_pe="$tmp/Blink.direct.pe"
cat > "$tmp/direct.proj" <<EOF
<Project>
  <UsingTask TaskName="MetaDataProcessorTask" AssemblyFile="$(winpath "$MDP_PKG")" />
  <Target Name="Go">
    <MetaDataProcessorTask Verbose="false" Parse="$(winpath "$IL")" VerboseMinimize="false"
        DumpMetadata="false" LoadHints="$(winpath "$CORELIB_DLL")"
        Compile="$(winpath "$legacy_pe")" GenerateStubs="false" />
  </Target>
</Project>
EOF
dotnet msbuild "$tmp/direct.proj" -t:Go -clp:NoSummary >/dev/null
if cmp -s "$PE" "$legacy_pe"; then
  echo "   OK: SDK PE is BYTE-IDENTICAL to the direct MDP output"
else
  echo "   FAIL: PE differs from direct MDP output"; exit 1
fi

echo
echo "==> 6. ProjectCapability NanoCSharpProject present (WS2 build-side)"
dotnet msbuild Blink.csproj -getItem:ProjectCapability 2>/dev/null | grep -q '"Identity": "NanoCSharpProject"' \
  && echo "   OK: NanoCSharpProject capability is on the SDK-style project" \
  || { echo "   FAIL: capability missing"; exit 1; }

echo
echo "==> 7. Restore-loop guard: MDP PackageReference is stable across restores"
# Simulate Visual Studio's POST-restore nomination, where the MDP package's
# GeneratePathProperty ($Pkg...) is already populated. If the MDP PackageReference
# disappears in that state, the restore graph oscillates between nominations and VS
# reports "A NuGet restore loop has been detected" (and Deploy fails with
# "could not locate the Metadata Processor task assembly"). The reference MUST stay
# present regardless of whether the package path is resolved. See nanoFramework.Mdp.targets.
if dotnet msbuild Blink.csproj -getItem:PackageReference \
     -p:PkgnanoFramework_Tools_MetadataProcessor_MsBuildTask=loopguard 2>/dev/null \
     | grep -q '"Identity": "nanoFramework.Tools.MetadataProcessor.MsBuildTask"'; then
  echo "   OK: MDP PackageReference does not oscillate (no VS restore loop)"
else
  echo "   FAIL: MDP PackageReference vanishes once its path resolves -> VS restore loop"; exit 1
fi

echo
echo "All POC build-side checks passed."
