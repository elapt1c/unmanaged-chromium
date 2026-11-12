# Build the portable Windows package from an official Chromium snapshot.
#
#   powershell -ExecutionPolicy Bypass -File scripts\build-windows.ps1
#   $env:CHROMIUM_REV = "1742908"; powershell -ExecutionPolicy Bypass -File scripts\build-windows.ps1
#
# Output: dist\unmanaged-chromium-windows-x64\

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$base = 'https://commondatastorage.googleapis.com/chromium-browser-snapshots/Win_x64'
$out = Join-Path $repoRoot 'dist\unmanaged-chromium-windows-x64'

if ($env:CHROMIUM_REV) { $rev = $env:CHROMIUM_REV }
else { $rev = (Invoke-WebRequest -UseBasicParsing "$base/LAST_CHANGE").Content.Trim() }
Write-Host "==> revision $rev"

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("uc-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $zip = Join-Path $work 'chrome-win.zip'
    Write-Host '==> downloading chrome-win.zip'
    Invoke-WebRequest -UseBasicParsing "$base/$rev/chrome-win.zip" -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $work -Force

    if (Test-Path $out) { Remove-Item -Recurse -Force $out }
    New-Item -ItemType Directory -Path $out | Out-Null
    Move-Item (Join-Path $work 'chrome-win') (Join-Path $out 'chromium')

    Copy-Item (Join-Path $repoRoot 'scripts\launch.cmd') (Join-Path $out 'launch.cmd')
    New-Item -ItemType Directory -Force -Path (Join-Path $out 'config') | Out-Null
    Copy-Item (Join-Path $repoRoot 'config\preferences.json') (Join-Path $out 'config\preferences.json')
    Copy-Item (Join-Path $repoRoot 'README.md') (Join-Path $out 'README.md')
    Copy-Item (Join-Path $repoRoot 'docs\CANNOT-DO.md') (Join-Path $out 'CANNOT-DO.md')
    Set-Content -Path (Join-Path $out 'CHROMIUM_REV') -Value $rev

    # Smoke test: the binary must start and print a version.
    Write-Host '==> smoke test'
    $ver = & (Join-Path $out 'chromium\chrome.exe') --version 2>&1 | Select-Object -First 1
    if (-not $ver) { throw 'chrome.exe produced no version output' }
    Write-Host "    $ver"

    Write-Host "==> done: $out"
}
finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
