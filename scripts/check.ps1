param([switch]$SkipBuild)
. "$PSScriptRoot/env.ps1"
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
  dart format --output=none --set-exit-if-changed lib test
  if ($LASTEXITCODE) { throw 'Formatting failed' }
  flutter analyze
  if ($LASTEXITCODE) { throw 'Analysis failed' }
  flutter test
  if ($LASTEXITCODE) { throw 'Tests failed' }
  if (-not $SkipBuild) {
    flutter build apk --debug
    if ($LASTEXITCODE) { throw 'Android build failed' }
  }
} finally { Pop-Location }
