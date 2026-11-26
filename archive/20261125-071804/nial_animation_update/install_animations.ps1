param([string]$ProjectRoot = 'C:\dev\nial_diary')
$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($ProjectRoot)
$expected = @{
  'lib\main.dart' = '42F477034192CFF1F9B1A4777EBC417F32EAE01AF76097157654B6FAB49019E0'
  'lib\services\nial_profile_card.dart' = '587D5461B1A78DCDA49700D9DA36DD55E5B79C6DF17B3BDC1EA889141FD16D1D'
}
$files = @('lib\main.dart','lib\services\nial_profile_card.dart','lib\services\nial_motion.dart','test\nial_motion_test.dart')
if (!(Test-Path -LiteralPath (Join-Path $root 'pubspec.yaml') -PathType Leaf)) {
    throw 'pubspec.yaml missing. Restore it before installing animations.'
}
foreach ($relative in $expected.Keys) {
    $target = Join-Path $root $relative
    $original = Join-Path $PSScriptRoot ('original\' + $relative)
    if (!(Test-Path -LiteralPath $original -PathType Leaf) -or
        (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash -ne $expected[$relative]) {
        throw "Original snapshot missing or corrupted: $relative"
    }
    if (!(Test-Path -LiteralPath (Split-Path -Parent $target) -PathType Container)) {
        throw "Project folder missing: $relative"
    }
    if (Test-Path -LiteralPath $target) {
        if (!(Test-Path -LiteralPath $target -PathType Leaf)) { throw "Not a file: $target" }
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $expected[$relative]) {
            throw "Source changed: $target. Nothing installed. Send current sources."
        }
    }
}
foreach ($relative in $files) {
    if (!(Test-Path -LiteralPath (Join-Path $PSScriptRoot $relative) -PathType Leaf)) {
        throw "Update file missing: $relative"
    }
    if (!$expected.ContainsKey($relative) -and (Test-Path -LiteralPath (Join-Path $root $relative))) {
        throw "New file already exists: $relative. Nothing installed."
    }
}
$backup = Join-Path 'C:\dev\nial_source_backups' ('animations_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
# Preserve snapshots outside the analyzed project, including recovery for missing files.
foreach ($relative in $expected.Keys) {
    $target = Join-Path $root $relative
    $saved = Join-Path $backup $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $saved) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('original\' + $relative)) -Destination $saved
    if (!(Test-Path -LiteralPath $target)) {
        [System.IO.File]::Copy($saved, $target, $false)
        Write-Host "Restored missing source from your uploaded snapshot: $target"
    }
}
$changed = @()
try {
    foreach ($relative in $files) {
        $target = Join-Path $root $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        $changed += $relative
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $relative) -Destination $target -Force
    }
} catch {
    foreach ($relative in $changed) {
        $target = Join-Path $root $relative
        if ($expected.ContainsKey($relative)) {
            Copy-Item -LiteralPath (Join-Path $backup $relative) -Destination $target -Force
        } elseif (Test-Path -LiteralPath $target) {
            Remove-Item -LiteralPath $target -Force
        }
    }
    throw
}
Write-Host 'Animation update installed.'
Write-Host "Original source backup: $backup"
