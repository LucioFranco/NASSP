# NASSP build script
# Usage: .\build.ps1 <command> [options]

param(
    [Parameter(Position=0)]
    [string]$Command = "help",

    [Parameter(Position=1)]
    [string]$Preset = "windows-x64-debug",

    [string]$OrbiterDir = ""
)

$ErrorActionPreference = "Stop"

$NasppRoot = $PSScriptRoot
$SourceDir = Join-Path $NasppRoot "Orbitersdk\samples\ProjectApollo"
$OutputDir = Join-Path $NasppRoot "build"
$CmakeBuildDir = Join-Path $SourceDir "out/build/$Preset"

# Use Kitware CMake if available (prefer over MinGW cmake)
$KitwareCMake = "${env:ProgramFiles}\CMake\bin\cmake.exe"
if (Test-Path $KitwareCMake) {
    $script:CMAKE = $KitwareCMake
} else {
    $script:CMAKE = "cmake"
}

# Initialize Visual Studio environment if cl.exe is not available
function Initialize-VsEnvironment {
    # Always reinitialize to ensure MSVC tools take priority over MinGW
    Write-Host "Initializing Visual Studio environment..." -ForegroundColor Yellow

    # Find vswhere
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        Write-Host "Error: Could not find vswhere.exe. Please install Visual Studio." -ForegroundColor Red
        exit 1
    }

    # Find VS installation path
    $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vsPath) {
        Write-Host "Error: Could not find Visual Studio with C++ tools installed." -ForegroundColor Red
        exit 1
    }

    # Determine architecture
    $arch = if ($Preset -match "x86") { "x86" } else { "x64" }

    # Find and run vcvarsall.bat
    $vcvarsall = Join-Path $vsPath "VC\Auxiliary\Build\vcvarsall.bat"
    if (-not (Test-Path $vcvarsall)) {
        Write-Host "Error: Could not find vcvarsall.bat at $vcvarsall" -ForegroundColor Red
        exit 1
    }

    Write-Host "Using Visual Studio at: $vsPath" -ForegroundColor Gray
    Write-Host "Setting up for architecture: $arch" -ForegroundColor Gray

    # Run vcvarsall and capture environment, ensuring MSVC paths come first
    $cmd = "`"$vcvarsall`" $arch && set"
    $output = cmd /c $cmd
    foreach ($line in $output) {
        if ($line -match "^([^=]+)=(.*)$") {
            [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
        }
    }

    if (-not (Get-Command cl -ErrorAction SilentlyContinue)) {
        Write-Host "Error: Failed to initialize Visual Studio environment." -ForegroundColor Red
        exit 1
    }

    Write-Host "Visual Studio environment initialized." -ForegroundColor Green
}

# Resolve Orbiter directory
function Get-OrbiterDir {
    if ($script:OrbiterDir) {
        $dir = $script:OrbiterDir
        if ($dir.StartsWith("~")) {
            $dir = $dir.Replace("~", $env:USERPROFILE)
        }
        return [System.IO.Path]::GetFullPath($dir)
    }
    # Default: check for Orbiter folder one level up from NASSP
    $parentDir = [System.IO.Path]::GetFullPath((Join-Path $NasppRoot ".."))
    $orbiterDir = Join-Path $parentDir "Orbiter"
    if (Test-Path $orbiterDir) {
        return $orbiterDir
    }
    # Not found - fail with helpful message
    Write-Host "Error: Could not find Orbiter directory." -ForegroundColor Red
    Write-Host "Looked for: $orbiterDir" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Please specify the Orbiter directory with -OrbiterDir:" -ForegroundColor Yellow
    Write-Host "  .\build.ps1 release -OrbiterDir C:\path\to\orbiter" -ForegroundColor Cyan
    exit 1
}

function Show-Help {
    Write-Host @"
NASSP Build Script
==================

Usage: .\build.ps1 <command> [preset] [-OrbiterDir <path>]

Commands:
  help            Show this help message
  configure       Configure the build with CMake
  build           Build the project
  all             Configure and build
  rebuild         Clean, configure, and build
  release         Build in release mode (x64)
  debug           Build in debug mode (x64)
  clean           Clean build artifacts for current preset
  clean-all       Clean all build directories
  presets         List available CMake presets
  orbiter         Build Orbiter and copy files to build directory
  orbiter-release Build Orbiter in release mode and copy files
  orbiter-debug   Build Orbiter in debug mode and copy files
  copy-orbiter    Copy Orbiter files to build directory (without building)
  run             Run Orbiter from build directory

Presets:
  windows-x64-debug (default)
  windows-x64-release
  windows-x64-relwithdebinfo

Options:
  -OrbiterDir     Path to Orbiter source/installation directory

Output:
  Build output goes to: $OutputDir

Examples:
  .\build.ps1 orbiter-release                    # Build Orbiter and copy to build dir
  .\build.ps1 all                                # Configure, build NASSP, and copy files
  .\build.ps1 build                              # Build with default preset
  .\build.ps1 rebuild                            # Clean and rebuild
  .\build.ps1 run                                # Run Orbiter from build directory
"@
}

function Get-OrbiterSdkInfo {
    param([string]$OrbiterPath, [string]$BuildType)

    # Map preset to build type for matching
    $buildTypeLower = $BuildType.ToLower()
    if ($buildTypeLower -match "release") {
        $buildTypeLower = "release"
    } elseif ($buildTypeLower -match "relwithdebinfo") {
        $buildTypeLower = "relwithdebinfo"
    } else {
        $buildTypeLower = "debug"
    }

    # Try to find matching build, then fall back to others
    # Prefer release over debug to avoid debug runtime dependencies
    $buildTypePriority = @($buildTypeLower, "release", "relwithdebinfo", "debug") | Select-Object -Unique

    foreach ($bt in $buildTypePriority) {
        $candidateDir = Join-Path $OrbiterPath "out/build/windows-x64-$bt"
        $sdkDir = Join-Path $candidateDir "Orbitersdk"
        $sdkHeader = Join-Path $sdkDir "include/Orbitersdk.h"

        if (Test-Path $sdkHeader) {
            $isSourceTree = $true
            $luaLib = "lua"  # Source tree uses 'lua'
            if ($bt -ne $buildTypeLower) {
                Write-Host "Warning: No matching Orbiter build for '$BuildType', using '$bt'" -ForegroundColor Yellow
            }
            return @{
                SdkDir = $sdkDir
                IsSourceTree = $isSourceTree
                LuaLibrary = $luaLib
                BuildDir = $candidateDir
            }
        }
    }

    # Check for binary distribution
    $sdkDir = Join-Path $OrbiterPath "Orbitersdk"
    $sdkHeader = Join-Path $sdkDir "include/Orbitersdk.h"
    if (Test-Path $sdkHeader) {
        return @{
            SdkDir = $sdkDir
            IsSourceTree = $false
            LuaLibrary = "lua5.1"  # Binary distribution uses 'lua5.1'
            BuildDir = $OrbiterPath
        }
    }

    # Not found
    return $null
}

function Invoke-Configure {
    param([string]$P = $Preset)
    Initialize-VsEnvironment

    $orbiter = Get-OrbiterDir

    # Detect SDK location
    $sdkInfo = Get-OrbiterSdkInfo -OrbiterPath $orbiter -BuildType $P
    if (-not $sdkInfo) {
        Write-Host "Error: Could not find Orbiter SDK in $orbiter" -ForegroundColor Red
        Write-Host "Build Orbiter first or check your Orbiter directory." -ForegroundColor Yellow
        exit 1
    }

    Write-Host "Using Orbiter: $orbiter" -ForegroundColor Cyan
    Write-Host "Using SDK: $($sdkInfo.SdkDir)" -ForegroundColor Cyan
    Write-Host "Lua library: $($sdkInfo.LuaLibrary)" -ForegroundColor Cyan
    Write-Host "Output directory: $OutputDir" -ForegroundColor Cyan
    Write-Host "Configuring with preset: $P" -ForegroundColor Cyan

    $cmakeArgs = @(
        "--preset", $P,
        "-S", $SourceDir,
        "-DORBITER_INSTALL_DIR=$orbiter",
        "-DORBITERSDK_DIR=$($sdkInfo.SdkDir)",
        "-DLUA_LIBRARY_NAME=$($sdkInfo.LuaLibrary)",
        "-DFINAL_INSTALL_DIR=$OutputDir"
    )

    # Pass build dir for source tree builds (needed for additional lib paths)
    if ($sdkInfo.IsSourceTree) {
        $cmakeArgs += "-DORBITER_BUILD_DIR=$($sdkInfo.BuildDir)"
    }

    & $script:CMAKE @cmakeArgs
}

function Invoke-Build {
    param([string]$P = $Preset)
    Initialize-VsEnvironment
    Write-Host "Building with preset: $P" -ForegroundColor Cyan
    Push-Location $SourceDir
    try {
        & $script:CMAKE --build --preset $P
    } finally {
        Pop-Location
    }
}

function Invoke-Clean {
    param([string]$Dir = $CmakeBuildDir)
    Write-Host "Cleaning: $Dir" -ForegroundColor Cyan
    if (Test-Path $Dir) {
        Remove-Item -Recurse -Force $Dir
        Write-Host "Cleaned $Dir" -ForegroundColor Green
    } else {
        Write-Host "Directory does not exist: $Dir" -ForegroundColor Yellow
    }
}

function Invoke-CleanAll {
    Write-Host "Cleaning all build directories" -ForegroundColor Cyan

    # Clean CMake build directory
    $outDir = Join-Path $SourceDir "out"
    if (Test-Path $outDir) {
        Remove-Item -Recurse -Force $outDir
        Write-Host "Cleaned CMake out/" -ForegroundColor Green
    }

    # Clean output build directory
    if (Test-Path $OutputDir) {
        Remove-Item -Recurse -Force $OutputDir
        Write-Host "Cleaned build/" -ForegroundColor Green
    }
}

function Show-Presets {
    Push-Location $SourceDir
    try {
        & $script:CMAKE --list-presets
    } finally {
        Pop-Location
    }
}

function Copy-OrbiterFiles {
    $orbiter = Get-OrbiterDir

    # Determine if we're using Orbiter source or binary distribution
    # Prefer release builds over debug to avoid debug runtime dependencies
    $orbiterBuildDir = ""
    foreach ($buildType in @("release", "relwithdebinfo", "debug")) {
        $candidate = Join-Path $orbiter "out/build/windows-x64-$buildType"
        if (Test-Path (Join-Path $candidate "Orbiter.exe")) {
            $orbiterBuildDir = $candidate
            Write-Host "Found Orbiter build: $orbiterBuildDir" -ForegroundColor Cyan
            break
        }
    }

    if (-not $orbiterBuildDir) {
        # Check if it's a binary distribution
        if (Test-Path (Join-Path $orbiter "Orbiter.exe")) {
            $orbiterBuildDir = $orbiter
            Write-Host "Using Orbiter binary distribution: $orbiter" -ForegroundColor Cyan
        } else {
            Write-Host "Error: Could not find Orbiter.exe in $orbiter" -ForegroundColor Red
            Write-Host "Build Orbiter first or specify a valid Orbiter directory." -ForegroundColor Yellow
            exit 1
        }
    }

    # Create output directory if needed
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    Write-Host "Copying Orbiter files to $OutputDir..." -ForegroundColor Cyan

    # Copy Orbiter executables and DLLs from build output
    $filesToCopy = @(
        "Orbiter.exe",
        "Orbiter_ng.exe",
        "*.dll"
    )

    foreach ($pattern in $filesToCopy) {
        $files = Get-ChildItem -Path $orbiterBuildDir -Filter $pattern -File -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            $dest = Join-Path $OutputDir $file.Name
            if (-not (Test-Path $dest) -or ($file.LastWriteTime -gt (Get-Item $dest).LastWriteTime)) {
                Copy-Item $file.FullName $dest -Force
                Write-Host "  Copied: $($file.Name)" -ForegroundColor Gray
            }
        }
    }

    # Copy DirectX SDK DLLs (required by D3D9Client)
    $dxsdkDir = Join-Path $orbiter "DXSDK/Utilities/bin/x64"
    if (Test-Path $dxsdkDir) {
        $dxDlls = @("D3DCompiler_43.dll", "d3dx9_43.dll")
        foreach ($dll in $dxDlls) {
            $src = Join-Path $dxsdkDir $dll
            $dest = Join-Path $OutputDir $dll
            if ((Test-Path $src) -and (-not (Test-Path $dest) -or ((Get-Item $src).LastWriteTime -gt (Get-Item $dest).LastWriteTime))) {
                Copy-Item $src $dest -Force
                Write-Host "  Copied: $dll (DirectX SDK)" -ForegroundColor Gray
            }
        }
    }

    # Copy directories from Orbiter source
    $orbiterSource = $orbiter
    $dirsToCopy = @(
        "Doc",
        "Html",
        "Script",
        "Flights"
    )

    foreach ($dir in $dirsToCopy) {
        $srcDir = Join-Path $orbiterSource $dir
        $destDir = Join-Path $OutputDir $dir
        if (Test-Path $srcDir) {
            Write-Host "  Copying: $dir/" -ForegroundColor Gray
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            # Use robocopy for efficient copying (only copies changed files)
            $null = robocopy $srcDir $destDir /E /XO /NFL /NDL /NJH /NJS /NC /NS 2>&1
        }
    }

    # Copy directories from Orbiter build output (these contain generated files)
    $buildDirsToCopy = @(
        "Config",
        "Meshes",
        "Modules",
        "Scenarios",
        "Textures"
    )

    foreach ($dir in $buildDirsToCopy) {
        $srcDir = Join-Path $orbiterBuildDir $dir
        $destDir = Join-Path $OutputDir $dir
        if (Test-Path $srcDir) {
            Write-Host "  Copying: $dir/ (from build)" -ForegroundColor Gray
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            $null = robocopy $srcDir $destDir /E /XO /NFL /NDL /NJH /NJS /NC /NS 2>&1
        }
    }

    # Copy NASSP-specific files from NASSP repo
    Write-Host "Copying NASSP files..." -ForegroundColor Cyan
    $nasspDirs = @(
        "Config",
        "Doc",
        "Html",
        "Meshes",
        "Missions",
        "Scenarios",
        "Script",
        "Sound",
        "Textures",
        "XRSound"
    )

    foreach ($dir in $nasspDirs) {
        $srcDir = Join-Path $NasppRoot $dir
        $destDir = Join-Path $OutputDir $dir
        if (Test-Path $srcDir) {
            Write-Host "  Copying NASSP: $dir/" -ForegroundColor Gray
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            $null = robocopy $srcDir $destDir /E /XO /NFL /NDL /NJH /NJS /NC /NS 2>&1
        }
    }

    Write-Host "Orbiter and NASSP files copied successfully." -ForegroundColor Green
}

function Invoke-BuildOrbiter {
    param([string]$OrbiterPreset = "windows-x64-release")

    $orbiter = Get-OrbiterDir
    $orbiterBuildScript = Join-Path $orbiter "build.ps1"

    if (-not (Test-Path $orbiterBuildScript)) {
        Write-Host "Error: Orbiter build.ps1 not found at $orbiterBuildScript" -ForegroundColor Red
        exit 1
    }

    Write-Host "Building Orbiter with preset: $OrbiterPreset" -ForegroundColor Cyan
    Push-Location $orbiter
    try {
        & $orbiterBuildScript all $OrbiterPreset
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Error: Orbiter build failed" -ForegroundColor Red
            exit 1
        }
    } finally {
        Pop-Location
    }

    Write-Host "Orbiter build complete. Copying files..." -ForegroundColor Green
    Copy-OrbiterFiles
}

function Invoke-Run {
    $orbiterExe = Join-Path $OutputDir "Orbiter.exe"
    if (-not (Test-Path $orbiterExe)) {
        Write-Host "Error: Orbiter.exe not found in $OutputDir" -ForegroundColor Red
        Write-Host "Run 'build.ps1 copy-orbiter' first." -ForegroundColor Yellow
        exit 1
    }

    Write-Host "Starting Orbiter from $OutputDir..." -ForegroundColor Cyan
    Push-Location $OutputDir
    try {
        Start-Process $orbiterExe
    } finally {
        Pop-Location
    }
}

# Main command dispatch
switch ($Command.ToLower()) {
    "help" { Show-Help }
    "configure" { Invoke-Configure -P $Preset }
    "build" { Invoke-Build -P $Preset }
    "all" {
        Invoke-Configure -P $Preset
        Invoke-Build -P $Preset
        Copy-OrbiterFiles
    }
    "rebuild" {
        Invoke-Clean -Dir $CmakeBuildDir
        Invoke-Configure -P $Preset
        Invoke-Build -P $Preset
        Copy-OrbiterFiles
    }
    "release" {
        $Preset = "windows-x64-release"
        Invoke-Configure -P $Preset
        Invoke-Build -P $Preset
        Copy-OrbiterFiles
    }
    "debug" {
        $Preset = "windows-x64-debug"
        Invoke-Configure -P $Preset
        Invoke-Build -P $Preset
        Copy-OrbiterFiles
    }
    "clean" { Invoke-Clean -Dir $CmakeBuildDir }
    "clean-all" { Invoke-CleanAll }
    "presets" { Show-Presets }
    "orbiter" { Invoke-BuildOrbiter -OrbiterPreset $Preset }
    "orbiter-release" { Invoke-BuildOrbiter -OrbiterPreset "windows-x64-release" }
    "orbiter-debug" { Invoke-BuildOrbiter -OrbiterPreset "windows-x64-debug" }
    "copy-orbiter" { Copy-OrbiterFiles }
    "run" { Invoke-Run }
    default {
        Write-Host "Unknown command: $Command" -ForegroundColor Red
        Write-Host "Run '.\build.ps1 help' for usage information."
        exit 1
    }
}
