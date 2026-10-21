param([switch]$SkipResolve)
. "$PSScriptRoot/env.ps1"
Push-Location $projectRoot
try {
  if (-not $SkipResolve) {
    & ./android/gradlew.bat -p android -I ../scripts/license-inventory.gradle :app:releaseLicenseInventory --console=plain
    if ($LASTEXITCODE) { throw 'Release dependency resolution failed' }
  }
  $rows = Get-Content build/release-license-inventory.json -Raw | ConvertFrom-Json
  $nativeTexts = [System.Text.StringBuilder]::new()
  Add-Type -AssemblyName System.IO.Compression
  function Add-ArchiveNotices($stream, [string]$component) {
    $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read, $true)
    try {
      foreach ($entry in $zip.Entries) {
        if ($entry.FullName -match '(?i)(^|/)(license|notice|copying|copyright)([._/-]|$)') {
          if ($entry.Length -eq 0) { continue }
          $reader = [IO.StreamReader]::new($entry.Open())
          try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
          [void]$nativeTexts.AppendLine("`n### $component / $($entry.FullName)`n")
          [void]$nativeTexts.AppendLine('```text')
          [void]$nativeTexts.AppendLine($text.TrimEnd())
          [void]$nativeTexts.AppendLine('```')
        } elseif ($entry.FullName -match '\.jar$') {
          $nested = [IO.MemoryStream]::new()
          $inputStream = $entry.Open()
          try { $inputStream.CopyTo($nested) } finally { $inputStream.Dispose() }
          $nested.Position = 0
          try { Add-ArchiveNotices $nested "$component / $($entry.FullName)" } finally { $nested.Dispose() }
        }
      }
    } finally { $zip.Dispose() }
  }
  $doc = [System.Text.StringBuilder]::new()
  [void]$doc.AppendLine(@'
# Component licenses and notices

Generated with `scripts/update-licenses.ps1` from the pinned Dart package cache,
resolved Android release artifacts/POMs and upstream notices. Regenerate after
changing dependencies. Resolved coordinates can include code later removed by R8.
This inventory describes licensing, not a vulnerability assessment.

The app's license screen is intentionally absent. APKs retain Flutter's generated
NOTICES.Z, LICENSE and native notice assets. Distribute this document with every
release APK as well. A repository link alone does not replace required notices.
Google Play services has separate SDK terms and is not Apache-licensed project code.

## Android release components

| Component / version | Upstream license declaration |
| --- | --- |
'@)
  foreach ($row in ($rows | Sort-Object component -Unique)) {
    $parts = $row.component.Split(':')
    $cache = Join-Path $env:GRADLE_USER_HOME "caches/modules-2/files-2.1/$($parts[0])/$($parts[1])/$($parts[2])"
    $pomFile = Get-ChildItem -LiteralPath $cache -Recurse -Filter '*.pom' | Select-Object -First 1
    $license = ''
    if ($pomFile) {
      [xml]$pom = Get-Content $pomFile.FullName -Raw
      $license = @($pom.project.licenses.license | ForEach-Object { "[$($_.name)]($($_.url))" }) -join '; '
    }
    if (-not $license) {
      if ($parts[0] -eq 'io.flutter') { $license = 'BSD-3-Clause plus bundled engine notices (see Flutter/sky_engine below)' }
      elseif ($row.component -eq 'com.google.guava:listenablefuture:1.0') { $license = '[Apache-2.0](https://github.com/google/guava/blob/master/COPYING)' }
      else { throw "Missing license declaration: $($row.component)" }
    }
    [void]$doc.AppendLine("| $($row.component) | $license |")
  }
  foreach ($file in ($rows.file | Sort-Object -Unique)) {
    $component = ($rows | Where-Object file -eq $file | Select-Object -First 1).component
    $stream = [IO.File]::OpenRead($file)
    try { Add-ArchiveNotices $stream $component } finally { $stream.Dispose() }
  }
  $desugar = Get-ChildItem "$env:GRADLE_USER_HOME/caches/modules-2/files-2.1/com.android.tools/desugar_jdk_libs/2.1.5" -Recurse -Filter '*.jar' | Select-Object -First 1
  if (-not $desugar) { throw 'Resolve desugar_jdk_libs before generating notices' }
  $stream = [IO.File]::OpenRead($desugar.FullName)
  try { Add-ArchiveNotices $stream 'com.android.tools:desugar_jdk_libs:2.1.5' } finally { $stream.Dispose() }
  [void]$doc.AppendLine("`nCore library desugaring: com.android.tools:desugar_jdk_libs:2.1.5; [GPL-2.0 with Classpath Exception](https://github.com/google/desugar_jdk_libs/blob/2.1.5/LICENSE). Corresponding upstream source: https://github.com/google/desugar_jdk_libs/tree/2.1.5. OkHttp's public suffix data additionally uses MPL-2.0; JSch bundles JZlib (BSD-3-Clause) and jBCrypt (ISC); see notices below.`n")
  [void]$doc.AppendLine("## Dart and Flutter components`n`nIncludes development/test packages, which are not all shipped in an APK.`n`n| Component | License |`n| --- | --- |")
  $packages = (Get-Content .dart_tool/package_config.json -Raw | ConvertFrom-Json).packages
  $texts = [System.Text.StringBuilder]::new()
  foreach ($package in ($packages | Sort-Object name)) {
    if ($package.name -eq 'secrets') { continue }
    $uri = [uri]$package.rootUri
    $root = if ($uri.IsAbsoluteUri) { $uri.LocalPath } else { [IO.Path]::GetFullPath((Join-Path "$projectRoot/.dart_tool" $package.rootUri)) }
    $licenseFile = Join-Path $root 'LICENSE'
    if (-not (Test-Path $licenseFile) -and $root.StartsWith($env:FLUTTER_ROOT)) {
      $licenseFile = Join-Path $env:FLUTTER_ROOT 'LICENSE'
    }
    if (-not (Test-Path $licenseFile)) { throw "Missing license: $($package.name)" }
    $body = Get-Content $licenseFile -Raw
    $type = if ($body -match 'Apache License') { 'Apache-2.0' } elseif ($body -match 'Permission is hereby granted, free of charge') { 'MIT' } elseif ($body -match 'Redistribution and use in source and binary forms') { 'BSD-3-Clause' } else { 'Bundled third-party notices; see full text below' }
    if ($package.name -eq 'sky_engine') { $type = 'BSD-3-Clause and bundled third-party licenses (full notices below)' }
    [void]$doc.AppendLine("| $($package.name) | $type |")
    [void]$texts.AppendLine("`n### $($package.name)`n")
    [void]$texts.AppendLine('```text')
    [void]$texts.AppendLine($body.TrimEnd())
    [void]$texts.AppendLine('```')
  }
  [void]$doc.AppendLine("`nFlutter SDK: 3.47.7; engine revision deb287481e3ce9468f3434937ced4240a70539ca. Package versions are pinned by pubspec.lock; SDK packages use this Flutter revision.`n")
  foreach ($source in @(@('Native embedded notices', 'assets/native_licenses.txt'), @('Apache-2.0 full text', 'LICENSE'))) {
    [void]$doc.AppendLine("`n## $($source[0])`n")
    [void]$doc.AppendLine('```text')
    [void]$doc.AppendLine((Get-Content $source[1] -Raw).TrimEnd())
    [void]$doc.AppendLine('```')
  }
  [void]$doc.AppendLine("`n## Dart / Flutter full notices")
  [void]$doc.Append($texts)
  [void]$doc.AppendLine("`n## Notices extracted from resolved Android artifacts")
  [void]$doc.Append($nativeTexts)
  [IO.File]::WriteAllText((Join-Path $projectRoot 'THIRD_PARTY_LICENSES.md'), $doc.ToString().Replace("`r`n", "`n"), [Text.UTF8Encoding]::new($false))
  Write-Output 'Updated THIRD_PARTY_LICENSES.md.'
} finally { Pop-Location }
