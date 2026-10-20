param(
  [switch]$CreateSigningKey,
  [string]$SigningDirectory = (Join-Path $env:LOCALAPPDATA 'SecretsSigning')
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/env.ps1"
. "$PSScriptRoot/signing.ps1"
$root = Split-Path -Parent $PSScriptRoot
$directory = [System.IO.Path]::GetFullPath($SigningDirectory)
$keyFile = Join-Path $directory 'secrets-release.p12'
$passwordFile = Join-Path $directory 'signing-password.dpapi'
$names = @('SECRETS_KEYSTORE','SECRETS_STORE_PASSWORD','SECRETS_KEY_ALIAS','SECRETS_KEY_PASSWORD')
$previous = @{}
foreach ($name in $names) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
  if (-not (Test-Path -LiteralPath $keyFile) -or -not (Test-Path -LiteralPath $passwordFile)) {
    if (-not $CreateSigningKey) { throw 'No signing identity found. Run with -CreateSigningKey once, or use an existing signing identity.' }
    if ((Test-Path -LiteralPath $keyFile) -or (Test-Path -LiteralPath $passwordFile)) { throw 'Incomplete signing identity; restore the matching key/password rather than overwriting it.' }
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $bytes = [byte[]]::new(48)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $env:SECRETS_STORE_PASSWORD = [Convert]::ToBase64String($bytes)
    Save-SigningPassword -Password $env:SECRETS_STORE_PASSWORD -Path $passwordFile
    & "$env:JAVA_HOME/bin/keytool.exe" -genkeypair -storetype PKCS12 -keystore $keyFile -alias secrets -keyalg RSA -keysize 3072 -validity 10000 -dname 'CN=Secrets, O=Secrets Open Source' -storepass:env SECRETS_STORE_PASSWORD -keypass:env SECRETS_STORE_PASSWORD
    if ($LASTEXITCODE) { throw 'Signing key generation failed; inspect the incomplete identity before retrying.' }
    Write-Output "Created encrypted signing identity in $directory. Back up the key and password independently."
  } else {
    $env:SECRETS_STORE_PASSWORD = Read-SigningPassword -Path $passwordFile
  }
  $env:SECRETS_KEYSTORE = $keyFile
  $env:SECRETS_KEY_ALIAS = 'secrets'
  $env:SECRETS_KEY_PASSWORD = $env:SECRETS_STORE_PASSWORD
  Push-Location $root
  try {
    flutter build apk --release
    if ($LASTEXITCODE) { throw 'Release build failed' }
    $apk = Join-Path $root 'build/app/outputs/flutter-apk/app-release.apk'
    & "$env:ANDROID_HOME/build-tools/36.0.0/apksigner.bat" verify --verbose --print-certs $apk |
      Tee-Object -FilePath "$apk.signing.txt"
    if ($LASTEXITCODE) { throw 'APK signature verification failed' }
    $hash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  app-release.apk" | Set-Content -LiteralPath "$apk.sha256"
  } finally { Pop-Location }
} finally {
  foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process') }
  $credential = $null
  $secure = $null
}
