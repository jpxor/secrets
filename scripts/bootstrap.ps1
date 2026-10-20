# Installs SDKs locally, without Android Studio or changes to global PATH.
param([switch]$AcceptAndroidLicenses)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$tools = Join-Path $root '.tools'
New-Item -ItemType Directory -Force -Path $tools | Out-Null
function Download([string]$Uri, [string]$Path, [string]$Sha256) {
  if (-not (Test-Path -LiteralPath $Path)) {
    curl.exe --fail --location --silent --show-error --retry 3 --output $Path $Uri
    if ($LASTEXITCODE) { throw "Download failed: $Uri" }
  }
  if ($Sha256 -and (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Sha256) { throw "Checksum mismatch: $Path" }
}
if (-not (Test-Path "$tools/flutter/bin/flutter.bat")) {
  Download 'https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.7-stable.zip' "$tools/flutter.zip" 'c2c875da25a1a1448d18ee4e8f398b2f6fce888b4775d8f9130538e16d826cb4'
  tar -xf "$tools/flutter.zip" -C $tools
  if ($LASTEXITCODE) { throw 'Flutter extraction failed' }
}
if (-not (Test-Path "$tools/java/jdk-17.0.20.1+1/bin/java.exe")) {
  Download 'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.20.1%2B1/OpenJDK17U-jdk_x64_windows_hotspot_17.0.20.1_1.zip' "$tools/jdk.zip" 'e53a79c3c3d86865bd7e787903884331068e71321714ffd44f145785affc7cb0'
  New-Item -ItemType Directory -Force -Path "$tools/java" | Out-Null
  tar -xf "$tools/jdk.zip" -C "$tools/java"
  if ($LASTEXITCODE) { throw 'JDK extraction failed' }
}
if (-not (Test-Path "$tools/android-sdk/cmdline-tools/latest/bin/sdkmanager.bat")) {
  Download 'https://dl.google.com/android/repository/commandlinetools-win-15859902_latest.zip' "$tools/android-cli.zip" '90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a'
  New-Item -ItemType Directory -Force -Path "$tools/android-sdk/cmdline-tools" | Out-Null
  tar -xf "$tools/android-cli.zip" -C "$tools/android-sdk/cmdline-tools"
  if ($LASTEXITCODE) { throw 'Android tools extraction failed' }
  Move-Item -LiteralPath "$tools/android-sdk/cmdline-tools/cmdline-tools" -Destination "$tools/android-sdk/cmdline-tools/latest"
}
. "$PSScriptRoot/env.ps1"
flutter config --no-analytics
if ($AcceptAndroidLicenses) {
  1..80 | ForEach-Object { 'y' } | sdkmanager.bat --sdk_root=$env:ANDROID_HOME --licenses
  if ($LASTEXITCODE) { throw 'Android license acceptance failed' }
}
sdkmanager.bat --sdk_root=$env:ANDROID_HOME 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0'
if ($LASTEXITCODE) { throw 'Android package installation failed' }
Push-Location $root
try { flutter pub get; if ($LASTEXITCODE) { throw 'Dependency resolution failed' } }
finally { Pop-Location }
