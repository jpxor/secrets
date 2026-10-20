$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/signing.ps1"
$temporary = [System.IO.Path]::GetTempFileName()
try {
  $fixture = 'public test fixture, not a real signing password'
  Save-SigningPassword -Password $fixture -Path $temporary
  if ((Read-SigningPassword -Path $temporary) -ne $fixture) { throw 'Signing password round-trip failed' }
  if ((Get-Content -LiteralPath $temporary -Raw).Contains($fixture)) { throw 'Signing password was stored in plaintext' }
  Write-Output 'Signing password encryption/newline regression test passed.'
} finally { Remove-Item -LiteralPath $temporary }
