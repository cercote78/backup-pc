[CmdletBinding()]
param(
    [string]$InstallPath = (Join-Path $env:LOCALAPPDATA 'Programs\BackupPC')
)

$ErrorActionPreference = 'Stop'

$sourceRoot = $PSScriptRoot
$restoreScript = Join-Path $sourceRoot 'scripts\Restore-Backup.ps1'
$backupPcScript = Join-Path $sourceRoot 'scripts\Backup-PC.ps1'
$restorePcScript = Join-Path $sourceRoot 'scripts\Restore-PC.ps1'
$manifestPath = Join-Path $sourceRoot 'manifest\apps.json'
if (-not (Test-Path -LiteralPath $restoreScript -PathType Leaf)) {
    throw "Script di ripristino non trovato: $restoreScript"
}
if (-not (Test-Path -LiteralPath $backupPcScript -PathType Leaf) -or
    -not (Test-Path -LiteralPath $restorePcScript -PathType Leaf)) {
    throw 'Mancano gli script di backup/ripristino dei file.'
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Manifest non trovato: $manifestPath"
}

$resolvedInstallPath = [System.IO.Path]::GetFullPath($InstallPath)
$installScriptsPath = Join-Path $resolvedInstallPath 'scripts'
$installManifestPath = Join-Path $resolvedInstallPath 'manifest'
$startMenuPath = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$shortcutPath = Join-Path $startMenuPath 'Backup PC.lnk'
$backupShortcutPath = Join-Path $startMenuPath 'Backup PC - Crea backup.lnk'
$restoreLauncherPath = Join-Path $resolvedInstallPath 'Ripristina backup.cmd'
$backupLauncherPath = Join-Path $resolvedInstallPath 'Crea backup.cmd'

New-Item -ItemType Directory -Path $installScriptsPath -Force | Out-Null
New-Item -ItemType Directory -Path $installManifestPath -Force | Out-Null
New-Item -ItemType Directory -Path $startMenuPath -Force | Out-Null

Copy-Item -LiteralPath $restoreScript -Destination $installScriptsPath -Force
Copy-Item -LiteralPath $backupPcScript -Destination $installScriptsPath -Force
Copy-Item -LiteralPath $restorePcScript -Destination $installScriptsPath -Force
Copy-Item -LiteralPath (Join-Path $sourceRoot 'scripts\Export-BackupManifest.ps1') -Destination $installScriptsPath -Force
Copy-Item -LiteralPath $manifestPath -Destination $installManifestPath -Force
if (Test-Path -LiteralPath (Join-Path $sourceRoot 'README.md') -PathType Leaf) {
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'README.md') -Destination $resolvedInstallPath -Force
}
if (Test-Path -LiteralPath (Join-Path $sourceRoot 'INSTALLAZIONI-MANUALI.md') -PathType Leaf) {
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'INSTALLAZIONI-MANUALI.md') -Destination $resolvedInstallPath -Force
}

$restoreLauncherContent = @'
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Restore-PC.ps1"
if errorlevel 1 pause
'@
$backupLauncherContent = @'
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Backup-PC.ps1"
if errorlevel 1 pause
'@
Set-Content -LiteralPath $restoreLauncherPath -Value $restoreLauncherContent -Encoding ASCII
Set-Content -LiteralPath $backupLauncherPath -Value $backupLauncherContent -Encoding ASCII

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $restoreLauncherPath
$shortcut.WorkingDirectory = $resolvedInstallPath
$shortcut.Description = 'Ripristina file mancanti e reinstalla programmi disponibili da un backup Backup PC'
$shortcut.Save()

$backupShortcut = $shell.CreateShortcut($backupShortcutPath)
$backupShortcut.TargetPath = $backupLauncherPath
$backupShortcut.WorkingDirectory = $resolvedInstallPath
$backupShortcut.Description = 'Crea il backup dei file personali e dell inventario software su E:\BackupPC'
$backupShortcut.Save()

Write-Output "Backup PC installato in: $resolvedInstallPath"
Write-Output "Collegamenti creati: $backupShortcutPath e $shortcutPath"
Write-Output 'Per il backup, collega il disco USB come E: e apri “Backup PC - Crea backup”.'
Write-Output 'Per il ripristino, apri “Backup PC”; i file esistenti non verranno sovrascritti.'
