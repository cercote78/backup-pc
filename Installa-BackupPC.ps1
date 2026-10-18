[CmdletBinding()]
param(
    [string]$InstallPath = (Join-Path $env:LOCALAPPDATA 'Programs\BackupPC')
)

$ErrorActionPreference = 'Stop'

$sourceRoot = $PSScriptRoot
$utilityScript = Join-Path $sourceRoot 'scripts\BackupPC.ps1'
if (-not (Test-Path -LiteralPath $utilityScript -PathType Leaf)) {
    throw "Script Backup PC non trovato: $utilityScript"
}

$resolvedInstallPath = [System.IO.Path]::GetFullPath($InstallPath)
$installScriptsPath = Join-Path $resolvedInstallPath 'scripts'
$startMenuPath = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$shortcutPath = Join-Path $startMenuPath 'Backup PC.lnk'
$launcherPath = Join-Path $resolvedInstallPath 'Avvia Backup PC.cmd'

New-Item -ItemType Directory -Path $installScriptsPath -Force | Out-Null
New-Item -ItemType Directory -Path $startMenuPath -Force | Out-Null

Copy-Item -LiteralPath $utilityScript -Destination $installScriptsPath -Force
if (Test-Path -LiteralPath (Join-Path $sourceRoot 'README.md') -PathType Leaf) {
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'README.md') -Destination $resolvedInstallPath -Force
}

$launcherContent = @'
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\BackupPC.ps1"
if errorlevel 1 pause
'@
Set-Content -LiteralPath $launcherPath -Value $launcherContent -Encoding ASCII

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $launcherPath
$shortcut.WorkingDirectory = $resolvedInstallPath
$shortcut.Description = 'Crea un inventario di programmi e giochi e un backup selettivo dei dati personali'
$shortcut.Save()

Write-Output "Backup PC installato in: $resolvedInstallPath"
Write-Output "Collegamento creato: $shortcutPath"
Write-Output 'Apri Backup PC dal menu Start per creare un inventario o selezionare dati personali da salvare.'
