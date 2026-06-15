<#
.SYNOPSIS
  Dev-only: surface the nanoFramework legacy (.nfproj) MSBuild project system to
  $(MSBuildExtensionsPath) so legacy .nfproj projects load/build alongside SDK-style
  .csproj when the extension is run from the EXPERIMENTAL instance.

.WHY
  A .nfproj imports its project system from
  $(MSBuildExtensionsPath)\nanoFramework\v1.0\NFProjectSystem.*.{props,targets}
  (conditionally — if missing, the import silently skips and VS unloads the project).
  A normal, elevated VSIX install copies the extension's InstallRoot="MSBuild" assets
  there automatically. The experimental-instance F5 deploy is NON-elevated, so it leaves
  those assets inside the extension folder's "$MSBuild" subtree and they never surface at
  $(MSBuildExtensionsPath). SDK-style .csproj is unaffected (it gets everything from the
  nanoFramework.Sdk NuGet package), which is why "only SDK projects load" today.

  This script copies the COMPLETE deployed set (5 targets/props + Rules\*.xaml + the
  build-task DLLs) from the experimental-instance extension into the VS MSBuild path.
  Re-run it after rebuilding/redeploying the extension. A real (elevated) install makes
  this unnecessary.

.NOTES
  Requires elevation (writes under Program Files). Self-elevates via UAC.
#>

[CmdletBinding()]
param(
    # Optional explicit source (…\nanoFramework\v1.0 inside the extension's $MSBuild tree).
    [string]$Source,
    # Optional explicit VS MSBuild extensions path (…\MSBuild).
    [string]$MSBuildExtensionsPath
)

$ErrorActionPreference = 'Stop'

# --- self-elevate ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Elevation required (writes under Program Files). Relaunching as admin..." -ForegroundColor Yellow
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"")
    if ($Source) { $argList += @('-Source', "`"$Source`"") }
    if ($MSBuildExtensionsPath) { $argList += @('-MSBuildExtensionsPath', "`"$MSBuildExtensionsPath`"") }
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList
    return
}

# --- discover SOURCE: the deployed legacy targets inside the experimental extension ---
if (-not $Source) {
    Write-Host "Searching for the deployed nanoFramework legacy targets..."
    $hits = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\VisualStudio" -Recurse -Filter 'NFProjectSystem.Default.props' -ErrorAction SilentlyContinue |
            Where-Object { $_.DirectoryName -match 'nanoFramework[\\/]v1\.0$' -and
                           (Test-Path (Join-Path $_.DirectoryName 'nanoFramework.Tools.BuildTasks.dll')) }
    if (-not $hits) { throw "Could not find a deployed extension with NFProjectSystem.Default.props + build tasks. Run the extension once from the experimental instance, or pass -Source." }
    # Prefer the most recently written (the most recent deploy).
    $Source = ($hits | Sort-Object LastWriteTime -Descending | Select-Object -First 1).DirectoryName
}
if (-not (Test-Path $Source)) { throw "Source not found: $Source" }
Write-Host "Source : $Source" -ForegroundColor Cyan

# --- discover DEST: <VSInstallDir>\MSBuild\nanoFramework\v1.0 (= $(MSBuildExtensionsPath)\...) ---
if (-not $MSBuildExtensionsPath) {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) { throw "vswhere not found; pass -MSBuildExtensionsPath explicitly." }
    $vsRoot = & $vswhere -latest -requires Microsoft.Component.MSBuild -property installationPath | Select-Object -First 1
    if (-not $vsRoot) { throw "No VS install with MSBuild found; pass -MSBuildExtensionsPath." }
    $MSBuildExtensionsPath = Join-Path $vsRoot 'MSBuild'
}
$dest = Join-Path $MSBuildExtensionsPath 'nanoFramework\v1.0'
Write-Host "Dest   : $dest" -ForegroundColor Cyan

# --- copy ---
New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item -Path (Join-Path $Source '*') -Destination $dest -Recurse -Force
Write-Host ""
Write-Host "Done. Legacy project system surfaced at `$(MSBuildExtensionsPath)\nanoFramework\v1.0." -ForegroundColor Green
Write-Host "Restart Visual Studio, then right-click NFApp1.nfproj -> Reload Project." -ForegroundColor Green
Get-ChildItem $dest -Name
