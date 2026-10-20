param([switch]$SkipBuild)
. "$PSScriptRoot/env.ps1"
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
  & "$PSScriptRoot/test-signing.ps1"
  & "$PSScriptRoot/normalize-local-properties.ps1" -SelfTest
  dart format --output=none --set-exit-if-changed lib test
  if ($LASTEXITCODE) { throw 'Formatting failed' }
  flutter analyze
  if ($LASTEXITCODE) { throw 'Analysis failed' }
  flutter test
  if ($LASTEXITCODE) { throw 'Tests failed' }
  # Flutter's generated Windows paths omit escaped drive-letter colons, which Android lint rejects.
  & "$PSScriptRoot/normalize-local-properties.ps1"
  Push-Location android
  try {
    .\gradlew.bat :app:testDebugUnitTest :app:lintDebug
    if ($LASTEXITCODE) { throw 'Android tests or lint failed' }
  } finally { Pop-Location }
  if (-not $SkipBuild) {
    flutter build apk --debug
    if ($LASTEXITCODE) { throw 'Android build failed' }
  }
} finally { Pop-Location }
