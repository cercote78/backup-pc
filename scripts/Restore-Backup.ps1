[CmdletBinding()]
param(
    [string]$ManifestPath
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path $PSScriptRoot '..\manifest\apps.json'
}

$winget = Get-Command winget -ErrorAction SilentlyContinue
if (-not $winget) {
    throw 'winget non è disponibile. Installa o aggiorna App Installer e riprova.'
}

$resolvedManifestPath = [System.IO.Path]::GetFullPath($ManifestPath)
if (-not (Test-Path -LiteralPath $resolvedManifestPath -PathType Leaf)) {
    throw "Manifest non trovato: $resolvedManifestPath. Generalo con scripts\Export-BackupManifest.ps1."
}

$manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $null -eq $manifest.packages) {
    throw 'Manifest non valido: sono richiesti schemaVersion 1 e packages.'
}

$packages = @($manifest.packages)
if ($packages.Count -eq 0) {
    throw 'Il manifest non contiene pacchetti da installare.'
}

foreach ($package in $packages) {
    $id = [string]$package.id
    if ([string]::IsNullOrWhiteSpace($id) -or $id -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*$') {
        throw "Identificativo winget non valido nel manifest: '$id'."
    }
    $excludedPatterns = @(
        '^Microsoft\.(?:VCLibs|VCRedist|DotNet|UI\.Xaml|WindowsAppRuntime|GameInput)(?:\.|$)',
        '^Microsoft\.AppInstaller$',
        '^Microsoft\.Gaming\.RemoteIterationClient$',
        '^EpicGames\.EpicOnlineServices$',
        '^Python\.Launcher$',
        '^OpenJS\.NodeJS(?:\.|$)',
        '^Intel\.IntelDriverAndSupportAssistant$',
        '^Lenovo\.ServiceBridge$',
        '^Apple\.Bonjour$',
        '^Canonical\.UbuntuProforWSL$',
        '^EPSON\.(?:PrinterConnectionChecker|EpsonNetPrint)$',
        '^DisableWindowsDefender',
        '^Security_Xploded\.'
    )
    $isExcluded = $false
    foreach ($pattern in $excludedPatterns) {
        if ($id -match $pattern) {
            $isExcluded = $true
            break
        }
    }
    if ($isExcluded) {
        throw "Il pacchetto '$id' è escluso per sicurezza o perché è un componente/runtime: rimuovilo dal manifest."
    }
}

Write-Output ''
Write-Output 'Pacchetti che verranno installati da winget:'
foreach ($package in $packages) {
    Write-Output ("  - {0}" -f $package.id)
}
Write-Output ''
Write-Output 'Le installazioni richiedono conferma; licenze e attivazioni non vengono ripristinate.'
$confirmation = Read-Host 'Digita INSTALL per avviare'
if ($confirmation -cne 'INSTALL') {
    Write-Output 'Operazione annullata; nessuna installazione avviata.'
    return
}

foreach ($package in $packages) {
    Write-Output ("Installazione di {0}..." -f $package.id)
    & $winget.Source install --id $package.id --exact --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        throw "Installazione di '$($package.id)' fallita con codice $LASTEXITCODE."
    }
}

Write-Output 'Ripristino completato.'
