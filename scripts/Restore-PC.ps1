[CmdletBinding()]
param(
    [string]$BackupPath,
    [string]$DestinationRoot = 'E:\BackupPC'
)

$ErrorActionPreference = 'Stop'

function Get-UserRestoreFolders {
    $profile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    $folders = [ordered]@{
        Desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
        Documents = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
        Downloads = ''
        Pictures = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyPictures)
        Music = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyMusic)
        Videos = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyVideos)
        SavedGames = ''
    }
    $shellFolders = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction SilentlyContinue
    if ($shellFolders) {
        $knownFolderIds = @{
            Downloads = '{374DE290-123F-4565-9164-39C4925E467B}'
            SavedGames = '{4C5C32FF-BB9D-43B0-BF5B-1952F0D1B4B8}'
        }
        foreach ($mapping in $knownFolderIds.GetEnumerator()) {
            $value = $shellFolders.PSObject.Properties[$mapping.Value]
            if ($value -and $value.Value) {
                $folders[$mapping.Key] = [Environment]::ExpandEnvironmentVariables([string]$value.Value)
            }
        }
    }
    if (-not $folders.Downloads) { $folders.Downloads = Join-Path $profile 'Downloads' }
    if (-not $folders.SavedGames) { $folders.SavedGames = Join-Path $profile 'Saved Games' }

    foreach ($entry in $folders.GetEnumerator()) {
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.Value)) {
            [pscustomobject]@{ Name = $entry.Key; Path = [System.IO.Path]::GetFullPath($entry.Value) }
        }
    }
}

$resolvedDestinationRoot = [System.IO.Path]::GetFullPath($DestinationRoot)
if ([string]::IsNullOrWhiteSpace($BackupPath)) {
    if (-not (Test-Path -LiteralPath $resolvedDestinationRoot -PathType Container)) {
        throw "Unità o cartella di backup non trovata: $resolvedDestinationRoot."
    }
    $backup = Get-ChildItem -LiteralPath $resolvedDestinationRoot -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'backup-info.json') } |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if (-not $backup) {
        throw "Nessun backup valido trovato in $resolvedDestinationRoot."
    }
    $BackupPath = $backup.FullName
}

$resolvedBackupPath = [System.IO.Path]::GetFullPath($BackupPath)
$backupInfoPath = Join-Path $resolvedBackupPath 'backup-info.json'
$filesPath = Join-Path $resolvedBackupPath 'Files'
$softwarePath = Join-Path $resolvedBackupPath 'Software'
$packageManifestPath = Join-Path $softwarePath 'winget-packages.json'
if (-not (Test-Path -LiteralPath $backupInfoPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $filesPath -PathType Container)) {
    throw "Il percorso non contiene un backup Backup PC valido: $resolvedBackupPath."
}

$backupInfo = Get-Content -LiteralPath $backupInfoPath -Raw | ConvertFrom-Json
if ($backupInfo.schemaVersion -ne 1 -or $null -eq $backupInfo.folders) {
    throw 'Indice del backup non valido o non supportato.'
}
$packageIds = @()
if (Test-Path -LiteralPath $packageManifestPath -PathType Leaf) {
    $manifest = Get-Content -LiteralPath $packageManifestPath -Raw | ConvertFrom-Json
    if ($manifest.schemaVersion -ne 1 -or $null -eq $manifest.packages) {
        throw 'Manifest software non valido.'
    }
    $packageIds = @($manifest.packages | ForEach-Object { [string]$_.id })
}

$excludedIdPatterns = @(
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
foreach ($id in $packageIds) {
    if ([string]::IsNullOrWhiteSpace($id) -or $id -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*$') {
        throw "Identificativo winget non valido nel backup: '$id'."
    }
    foreach ($pattern in $excludedIdPatterns) {
        if ($id -match $pattern) {
            throw "Il backup include un pacchetto escluso per sicurezza o perché è un componente/runtime: '$id'."
        }
    }
}

$winget = Get-Command winget -ErrorAction SilentlyContinue
Write-Output "Backup selezionato: $resolvedBackupPath"
Write-Output ("Cartelle presenti: {0}" -f (@($backupInfo.folders) -join ', '))
Write-Output ("Pacchetti winget disponibili per il ripristino: {0}" -f $packageIds.Count)
Write-Output 'I file esistenti non verranno sovrascritti né eliminati; verranno copiati solo file mancanti.'
if ($packageIds.Count -gt 0 -and -not $winget) {
    Write-Warning 'winget non è disponibile: i file potranno essere ripristinati, i software no.'
}
if ($packageIds.Count -gt 0 -and $winget) {
    Write-Output ''
    Write-Output 'Software che winget proverà a reinstallare:'
    $packageIds | ForEach-Object { Write-Output "  - $_" }
}

$confirmation = Read-Host 'Digita RIPRISTINA per continuare'
if ($confirmation -cne 'RIPRISTINA') {
    Write-Output 'Ripristino annullato; non sono stati copiati file o avviate installazioni.'
    return
}

$folderMap = @{}
foreach ($folder in Get-UserRestoreFolders) {
    $folderMap[$folder.Name] = $folder.Path
}
foreach ($folderName in $backupInfo.folders) {
    $source = Join-Path $filesPath ([string]$folderName)
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Cartella dichiarata nel backup ma mancante: $source"
    }
    if (-not $folderMap.ContainsKey([string]$folderName)) {
        Write-Warning "Cartella '$folderName' non riconosciuta; saltata."
        continue
    }

    $destination = $folderMap[[string]$folderName]
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Write-Output "Ripristino file in $destination..."
    & robocopy.exe $source $destination /E /COPY:DAT /DCOPY:DAT /XJ /R:2 /W:2 /XC /XN /XO /NFL /NDL /NP
    $robocopyCode = $LASTEXITCODE
    if ($robocopyCode -ge 8) {
        throw "Ripristino della cartella '$folderName' non riuscito (robocopy $robocopyCode)."
    }
}

if ($packageIds.Count -gt 0 -and $winget) {
    foreach ($id in $packageIds) {
        Write-Output "Installazione di $id..."
        & $winget.Source install --id $id --exact --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity
        if ($LASTEXITCODE -ne 0) {
            throw "Installazione di '$id' fallita con codice $LASTEXITCODE. I file già ripristinati non sono stati eliminati."
        }
    }
}

Write-Output 'Ripristino dei file completato.'
if ($packageIds.Count -gt 0 -and -not $winget) {
    Write-Warning 'Per ripristinare i software installa winget e riesegui lo script.'
} else {
    Write-Output 'winget non può reinstallare i programmi non riconosciuti, trasferire licenze o ripristinare account e attivazioni.'
}
