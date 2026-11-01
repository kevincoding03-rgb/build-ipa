#  Look4Sat iOS port — one-command Swift build/test on Windows
#  Prereqs (all verified on this machine 2026-11-02):
#    • winget Swift.Toolchain 6.4.2 → C:\Users\halcy\AppData\Local\Programs\Swift
#    • VS 2022 Community + MSVC 14.44 (C:\Program Files\Microsoft Visual Studio\2022\Community)
#    • Windows SDK 10.0.26100.0
#  Usage:  pwsh -File build-windows.ps1   [cmd] [args...]
#    No args            → swift build
#    test               → swift test
#    cli                → swift run look4sat-cli
#    (any other args)   → swift <args>
param([string]$Target = "build", [Parameter(ValueFromRemainingArguments = $true)][string[]]$ExtraArgs)

$ErrorActionPreference = "Stop"
$script = $MyInvocation.MyCommand.Path
$base   = Split-Path -Parent $script   # …\ios_Look4Sat

# ── 1. MSVC environment (link.exe, cl.exe, Windows SDK libs) ────────
$vcvars = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
if (-not (Test-Path $vcvars)) { throw "vcvars64.bat not found: $vcvars" }
$envDump = cmd /c "`"$vcvars`" >nul 2>&1 && set"
foreach ($line in $envDump) {
    if ($line -match "^([^=]+)=(.*)$") {
        [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
    }
}
if (-not (Get-Command link.exe -ErrorAction SilentlyContinue)) {
    throw "link.exe still not on PATH after vcvars import"
}

# ── 2. Swift toolchain + runtime on PATH ────────────────────────────
$swiftRoot = "C:\Users\halcy\AppData\Local\Programs\Swift"
$tcVer = "6.4.2+Asserts"
$rtVer = "6.4.2"
$swiftTC = "$swiftRoot\Toolchains\$tcVer\usr"
$swiftRT = "$swiftRoot\Runtimes\$rtVer\usr"
if (-not (Test-Path "$swiftTC\bin\swiftc.exe")) { throw "swiftc.exe not found under $swiftTC\bin" }
$env:PATH = "$swiftTC\bin;$swiftRT\bin;" + $env:PATH
# Runtime DLLs for the compiled binaries (swiftCore.dll & friends live in the runtime dir)
$env:PATH = "$swiftRT\bin;" + $env:PATH

# ── 3. SDK auto-detection ────────────────────────────────────────────
# The winget layout splits Toolchains/ and Platforms/ as siblings under the
# top-level Swift dir. SwiftPM (swiftc) only auto-finds the SDK when
# Platforms sits next to the toolchain. The KEY is to set the SDKROOT
# environment variable so the SwiftPM manifest compile picks it up.
$env:SDKROOT = "$swiftRoot\Platforms\6.4.2\Windows.platform\Developer\SDKs\Windows.sdk"
if (-not (Test-Path $env:SDKROOT)) { throw "Windows.sdk not found at $env:SDKROOT" }

# ── 4. Run the requested command ────────────────────────────────────
Push-Location $base
try {
    switch ($Target) {
        "cli" {
            & swift run look4sat-cli @ExtraArgs
        }
        default {
            & swift $Target @ExtraArgs
        }
    }
    if ($LASTEXITCODE -ne 0) { throw "swift $Target failed with exit code $LASTEXITCODE" }
} finally {
    Pop-Location
}
Write-Host ""
Write-Host "Done: swift $Target $($ExtraArgs -join ' ')"
