param(
  [Parameter(Mandatory)][string]$Device,
  [Parameter(Mandatory)][string]$HostAddress,
  [ValidateRange(1,65535)][int]$Port = 22
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/env.ps1"
. "$PSScriptRoot/signing.ps1"
$root = Split-Path -Parent $PSScriptRoot
if ($Device -notmatch '^[a-zA-Z0-9._:-]+$' -or $HostAddress -notmatch '^[a-zA-Z0-9._:-]+$') { throw 'Invalid device or host argument.' }
$mappingFile = Join-Path $root 'build/app/outputs/mapping/release/mapping.txt'
$mapping = Get-Content -LiteralPath $mappingFile -Raw
function Release-Class([string]$Name) {
  $match = [regex]::Match($mapping, '(?m)^' + [regex]::Escape($Name) + ' -> ([^:]+):\r?$')
  if (-not $match.Success) { throw "Class missing from release mapping: $Name" }
  $match.Groups[1].Value
}
$work = Join-Path $root '.tools/sftp-release-check'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$source = Get-Content "$PSScriptRoot/fixtures/SftpHandshakeInstrumentation.java" -Raw
$source = $source.Replace('__PROVIDER__', (Release-Class 'app.secretskeeper.secrets.SftpProvider')).Replace('__CHALLENGE__', (Release-Class 'app.secretskeeper.secrets.SshHostKeyException')).Replace('__FAILURE__', (Release-Class 'app.secretskeeper.secrets.SftpConnectionException'))
$source | Set-Content "$work/SftpHandshakeInstrumentation.java"
'<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="app.secretskeeper.sftpcheck"><uses-sdk android:minSdkVersion="26" android:targetSdkVersion="36"/><application android:label="Secrets SFTP release check"/><instrumentation android:name="app.secretskeeper.sftpcheck.SftpHandshakeInstrumentation" android:targetPackage="app.secretskeeper.secrets"/></manifest>' | Set-Content "$work/AndroidManifest.xml"
function Check-Exit([string]$Action) { if ($LASTEXITCODE) { throw "$Action failed ($LASTEXITCODE)." } }
$tools = "$env:ANDROID_HOME/build-tools/36.0.0"
& "$env:JAVA_HOME/bin/javac.exe" -cp "$env:ANDROID_HOME/platforms/android-36/android.jar" -d $work "$work/SftpHandshakeInstrumentation.java"
Check-Exit 'Compile handshake harness'
& "$env:JAVA_HOME/bin/jar.exe" cf "$work/harness.jar" -C $work app/secretskeeper/sftpcheck/SftpHandshakeInstrumentation.class
Check-Exit 'Package handshake harness'
if (Test-Path "$work/code.zip") { Remove-Item -LiteralPath "$work/code.zip" }
& "$tools/d8.bat" --min-api 26 --output "$work/code.zip" "$work/harness.jar"
Check-Exit 'Dex handshake harness'
& "$tools/aapt2.exe" link -o "$work/unsigned.apk" --manifest "$work/AndroidManifest.xml" -I "$env:ANDROID_HOME/platforms/android-36/android.jar"
Check-Exit 'Link handshake harness'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead("$work/code.zip")
try { [IO.Compression.ZipFileExtensions]::ExtractToFile($zip.GetEntry('classes.dex'), "$work/classes.dex", $true) } finally { $zip.Dispose() }
& "$env:JAVA_HOME/bin/jar.exe" uf "$work/unsigned.apk" -C $work classes.dex
Check-Exit 'Add harness code'
& "$tools/zipalign.exe" -f 4 "$work/unsigned.apk" "$work/harness.apk"
Check-Exit 'Align handshake harness'
$previousPassword = $env:SECRETS_SFTP_CHECK_PASSWORD
try {
  $env:SECRETS_SFTP_CHECK_PASSWORD = Read-SigningPassword -Path (Join-Path $env:LOCALAPPDATA 'SecretsSigning/signing-password.dpapi')
  & "$tools/apksigner.bat" sign --ks (Join-Path $env:LOCALAPPDATA 'SecretsSigning/secrets-release.p12') --ks-key-alias secrets --ks-pass env:SECRETS_SFTP_CHECK_PASSWORD "$work/harness.apk"
  Check-Exit 'Sign handshake harness'
} finally { $env:SECRETS_SFTP_CHECK_PASSWORD = $previousPassword }
try {
  adb -s $Device install -r "$work/harness.apk"
  Check-Exit 'Install handshake harness'
  $result = adb -s $Device shell am instrument -w -e host $HostAddress -e port $Port app.secretskeeper.sftpcheck/app.secretskeeper.sftpcheck.SftpHandshakeInstrumentation
  Check-Exit 'Run handshake harness'
  $result
  if (($result -join "`n") -notmatch 'PASS: SFTP_HOST_TRUST_REACHED') { throw 'Release SSH handshake regression check failed.' }
} finally {
  adb -s $Device uninstall app.secretskeeper.sftpcheck | Out-Null
}
