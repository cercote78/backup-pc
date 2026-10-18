[CmdletBinding()]
param(
    [string]$InstallPath = (Join-Path $env:LOCALAPPDATA 'Programs\BackupPC')
)

$ErrorActionPreference = 'Stop'

$sourceRoot = $PSScriptRoot
$restoreScript = Join-Path $sourceRoot 'scripts\Restore-Backup.ps1'
$manifestPath = Join-Path $sourceRoot 'manifest\apps.json'
if (-not (Test-Path -LiteralPath $restoreScript -PathType Leaf)) {
    throw "Script di ripristino non trovato: $restoreScript"
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Manifest non trovato: $manifestPath"
}

$resolvedInstallPath = [System.IO.Path]::GetFullPath($InstallPath)
$installScriptsPath = Join-Path $resolvedInstallPath 'scripts'
$installManifestPath = Join-Path $resolvedInstallPath 'manifest'
$startMenuPath = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$shortcutPath = Join-Path $startMenuPath 'Backup PC.lnk'
$launcherPath = Join-Path $resolvedInstallPath 'Ripristina programmi.cmd'

New-Item -ItemType Directory -Path $installScriptsPath -Force | Out-Null
New-Item -ItemType Directory -Path $installManifestPath -Force | Out-Null
New-Item -ItemType Directory -Path $startMenuPath -Force | Out-Null

Copy-Item -LiteralPath $restoreScript -Destination $installScriptsPath -Force
Copy-Item -LiteralPath (Join-Path $sourceRoot 'scripts\Export-BackupManifest.ps1') -Destination $installScriptsPath -Force
Copy-Item -LiteralPath $manifestPath -Destination $installManifestPath -Force
if (Test-Path -LiteralPath (Join-Path $sourceRoot 'README.md') -PathType Leaf) {
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'README.md') -Destination $resolvedInstallPath -Force
}
if (Test-Path -LiteralPath (Join-Path $sourceRoot 'INSTALLAZIONI-MANUALI.md') -PathType Leaf) {
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'INSTALLAZIONI-MANUALI.md') -Destination $resolvedInstallPath -Force
}

$launcherContent = @'
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Restore-Backup.ps1"
if errorlevel 1 pause
'@
Set-Content -LiteralPath $launcherPath -Value $launcherContent -Encoding ASCII

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $launcherPath
$shortcut.WorkingDirectory = $resolvedInstallPath
$shortcut.Description = 'Mostra e ripristina i programmi dal manifest Backup PC'
$shortcut.Save()

Write-Output "Backup PC installato in: $resolvedInstallPath"
Write-Output "Collegamento creato: $shortcutPath"
Write-Output 'Per ripristinare, apri Backup PC dal menu Start e digita INSTALL solo se vuoi procedere.'
