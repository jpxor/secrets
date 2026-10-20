param([Parameter(Mandatory)][string]$Device)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/env.ps1"
$package = 'app.secretskeeper.secrets'
# Exercise the installed APK, including release shrinking and startup providers.
# Never clear app data: this check must also be safe for an existing vault.
adb -s $Device shell am force-stop $package
if ($LASTEXITCODE) { throw 'Unable to stop app for startup check.' }
adb -s $Device shell am start -W -n "$package/.MainActivity"
if ($LASTEXITCODE) { throw 'Activity launch failed.' }
Start-Sleep -Seconds 5
$appProcess = adb -s $Device shell pidof $package
if ($LASTEXITCODE -or -not $appProcess) {
  throw 'App exited during startup. Inspect package exit-info and AndroidRuntime crash logs.'
}
Write-Output 'PASS: Secrets remains running after a fresh launch of the installed APK.'
