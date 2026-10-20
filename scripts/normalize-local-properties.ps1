param([switch]$SelfTest)
$ErrorActionPreference = 'Stop'
function ConvertTo-EscapedSdkProperty([string]$Line) {
  if ($Line -match '^(sdk\.dir|flutter\.sdk)=([A-Za-z]):(.*)$') {
    return $Matches[1] + '=' + $Matches[2] + '\:' + $Matches[3]
  }
  return $Line
}
if ($SelfTest) {
  $fixture = 'sdk.dir=C:\\Android\\sdk'
  $expected = 'sdk.dir=C\:\\Android\\sdk'
  if ((ConvertTo-EscapedSdkProperty $fixture) -ne $expected) { throw 'SDK property escaping regression' }
  if ((ConvertTo-EscapedSdkProperty $expected) -ne $expected) { throw 'SDK escaping must be idempotent' }
  if ((ConvertTo-EscapedSdkProperty 'flutter.versionCode=1') -ne 'flutter.versionCode=1') { throw 'Non-path properties changed' }
  Write-Output 'SDK property escaping regression test passed.'
  return
}
$path = Join-Path (Split-Path -Parent $PSScriptRoot) 'android/local.properties'
if (Test-Path -LiteralPath $path) {
  $lines = @(Get-Content -LiteralPath $path | ForEach-Object { ConvertTo-EscapedSdkProperty $_ })
  $lines | Set-Content -LiteralPath $path -Encoding utf8
}
