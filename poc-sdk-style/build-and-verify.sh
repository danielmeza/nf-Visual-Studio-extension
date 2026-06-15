#!/usr/bin/env bash
#
# POC: SDK-style nanoFramework build + MDP PE emission, end to end.
#
# Proves WS1 (targets composition) and the WS1 parity gate on any machine with
# the .NET SDK + a NuGet restore — no Visual Studio, no device. WS2/WS3/WS4 are
# verified as described in RESULTS.md (VS-on-Windows for the F5 breakpoint).
#
# Usage:  ./build-and-verify.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here"

CORELIB_VER="2.0.0-preview.52"
MDP_PKG="$HOME/.nuget/packages/nanoframework.tools.metadataprocessor.msbuildtask/3.0.100/lib/net6.0/nanoFramework.Tools.MetadataProcessor.MsBuildTask.dll"
# v2 preview ships lib/netnano1.0/ (republished); use that reference for the parity check.
CORELIB_DLL="$HOME/.nuget/packages/nanoframework.corelibrary/$CORELIB_VER/lib/netnano1.0/mscorlib.dll"

echo "==> 1. Pack the local nanoFramework.Sdk into the local feed"
dotnet pack nanoFramework.Sdk/nanoFramework.Sdk.csproj -o local-feed -clp:NoSummary | tail -1
# Force the SDK resolver to re-extract the freshly packed version.
rm -rf "$HOME/.nuget/packages/nanoframework.sdk/1.0.0"

echo "==> 2. Build the SDK-style sample (Sdk=\"nanoFramework.Sdk/1.0.0\")"
cd samples/Blink
rm -rf bin obj
dotnet build -clp:NoSummary | grep -E "Blink.pe|Build succeeded|error|warning" || true

echo
echo "==> 3. Outputs"
ls -la bin/Debug/

PE="bin/Debug/Blink.pe"
echo
echo "==> 4. Confirm it is a real nanoFramework PE (NFMRK1 magic)"
magic="$(head -c 6 "$PE")"
[ "$magic" = "NFMRK1" ] && echo "   OK: $PE starts with NFMRK1" || { echo "   FAIL: bad magic"; exit 1; }

echo
echo "==> 5. WS1 parity gate: same IL through a legacy-shaped MDP invocation, byte-compare"
IL="$(pwd)/obj/Debug/Blink.exe"
tmp="$(mktemp -d)"
cat > "$tmp/legacy.proj" <<EOF
<Project>
  <UsingTask TaskName="MetaDataProcessorTask" AssemblyFile="$MDP_PKG" />
  <Target Name="Go">
    <MetaDataProcessorTask Verbose="false" Parse="$IL" VerboseMinimize="false"
        DumpMetadata="false" LoadHints="$CORELIB_DLL"
        Compile="$tmp/Blink.legacy.pe" GenerateStubs="false" />
  </Target>
</Project>
EOF
dotnet msbuild "$tmp/legacy.proj" -t:Go -clp:NoSummary >/dev/null
if cmp -s "$PE" "$tmp/Blink.legacy.pe"; then
  echo "   OK: SDK PE is BYTE-IDENTICAL to the legacy-shaped MDP output"
else
  echo "   FAIL: PE differs from legacy-shaped MDP output"; exit 1
fi

echo
echo "==> 6. ProjectCapability NanoCSharpProject present (WS2 build-side)"
dotnet msbuild Blink.csproj -getItem:ProjectCapability 2>/dev/null | grep -q '"Identity": "NanoCSharpProject"' \
  && echo "   OK: NanoCSharpProject capability is on the SDK-style project" \
  || { echo "   FAIL: capability missing"; exit 1; }

echo
echo "All POC build-side checks passed."
