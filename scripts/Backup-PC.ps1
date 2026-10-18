[CmdletBinding()]
param(
    [string]$DestinationRoot = 'E:\BackupPC'
)

$ErrorActionPreference = 'Stop'

function Get-UserBackupFolders {
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

    $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $folders.GetEnumerator()) {
        if ($entry.Value -and (Test-Path -LiteralPath $entry.Value -PathType Container)) {
            $path = [System.IO.Path]::GetFullPath($entry.Value)
            if ($seenPaths.Add($path)) {
                [pscustomobject]@{ Name = $entry.Key; Path = $path }
            }
        }
    }
}

function Get-InstalledSoftwareInventory {
    $uninstallRoots = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $excludedNamePatterns = @(
        '^Disable Windows Defender(?: 2\.0)?$',
        '\b(?:driver|firmware)\b',
        '\b(?:Redistributable|Runtime|Shared Framework)\b'
    )

    $entries = @(
        foreach ($root in $uninstallRoots) {
            if (Test-Path -LiteralPath $root) {
                foreach ($key in Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue) {
                    $app = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
                    $name = [string]$app.DisplayName
                    if ([string]::IsNullOrWhiteSpace($name)) { continue }

                    $excluded = $false
                    foreach ($pattern in $excludedNamePatterns) {
                        if ($name -match $pattern) { $excluded = $true; break }
                    }
                    if (-not $excluded) {
                        [pscustomobject]@{
                            name = $name
                            version = [string]$app.DisplayVersion
                            publisher = [string]$app.Publisher
                            kind = 'desktop'
                        }
                    }
                }
            }
        }
        if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) {
            foreach ($app in Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { -not $_.IsFramework -and -not $_.IsResourcePackage }) {
                if ($app.Name -notmatch 'DisableWindowsDefender|Security_Xploded') {
                    [pscustomobject]@{
                        name = [string]$app.Name
                        version = [string]$app.Version
                        publisher = [string]$app.Publisher
                        kind = 'store'
                    }
                }
            }
        }
    )

    @($entries | Sort-Object name, version, kind -Unique)
}

function Get-WingetPackageIds {
    param([string]$ExportPath)

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Warning 'winget non disponibile: salvo inventario software, ma non gli ID reinstallabili automaticamente.'
        return @()
    }

    & $winget.Source export --output $ExportPath --accept-source-agreements --disable-interactivity 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "winget export è terminato con codice $LASTEXITCODE."
    }
    if (-not (Test-Path -LiteralPath $ExportPath -PathType Leaf)) {
        throw 'winget export non ha creato il file previsto.'
    }

    $export = Get-Content -LiteralPath $ExportPath -Raw | ConvertFrom-Json
    if ($null -eq $export.Sources) {
        throw 'Il file winget non contiene la sezione Sources attesa.'
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
    @(
        foreach ($source in $export.Sources) {
            foreach ($package in $source.Packages) {
                $id = [string]$package.PackageIdentifier
                if ([string]::IsNullOrWhiteSpace($id)) { continue }
                $excluded = $false
                foreach ($pattern in $excludedIdPatterns) {
                    if ($id -match $pattern) { $excluded = $true; break }
                }
                if (-not $excluded) { $id }
            }
        }
    ) | Sort-Object -Unique
}

$resolvedDestinationRoot = [System.IO.Path]::GetFullPath($DestinationRoot)
$destinationVolume = [System.IO.Path]::GetPathRoot($resolvedDestinationRoot)
if (-not (Test-Path -LiteralPath $destinationVolume -PathType Container)) {
    throw "Unità di backup non trovata: $destinationVolume. Collega il disco USB o indica il percorso corretto."
}
$sourceFolders = @(Get-UserBackupFolders)
foreach ($folder in $sourceFolders) {
    $sourcePath = [System.IO.Path]::GetFullPath($folder.Path).TrimEnd('\')
    $backupRoot = $resolvedDestinationRoot.TrimEnd('\')
    if ($backupRoot.Equals($sourcePath, [System.StringComparison]::OrdinalIgnoreCase) -or
        $backupRoot.StartsWith($sourcePath + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "La destinazione del backup è dentro la cartella '$($folder.Name)'. Scegli una cartella esterna ai dati da copiare."
    }
}

if (-not (Test-Path -LiteralPath $resolvedDestinationRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $resolvedDestinationRoot -Force | Out-Null
}

$backupPath = Join-Path $resolvedDestinationRoot (Get-Date -Format 'yyyy-MM-dd_HHmmss')
New-Item -ItemType Directory -Path $backupPath -ErrorAction Stop | Out-Null
$filesPath = Join-Path $backupPath 'Files'
$softwarePath = Join-Path $backupPath 'Software'
New-Item -ItemType Directory -Path $filesPath, $softwarePath -Force | Out-Null

foreach ($folder in $sourceFolders) {
    $target = Join-Path $filesPath $folder.Name
    Write-Output ("Copia {0}..." -f $folder.Name)
    & robocopy.exe $folder.Path $target /E /COPY:DAT /DCOPY:DAT /XJ /R:2 /W:2 /NFL /NDL /NP
    $robocopyCode = $LASTEXITCODE
    if ($robocopyCode -ge 8) {
        throw "Copia della cartella '$($folder.Name)' non riuscita (robocopy $robocopyCode). Controlla lo spazio e ripeti il backup."
    }
}

$installedSoftware = Get-InstalledSoftwareInventory
$installedSoftwareJson = ConvertTo-Json -InputObject @($installedSoftware) -Depth 5
$installedSoftwareJson |
    Set-Content -LiteralPath (Join-Path $softwarePath 'installed-software.json') -Encoding UTF8

$temporaryExport = Join-Path ([System.IO.Path]::GetTempPath()) ("backup-pc-{0}.json" -f [guid]::NewGuid())
try {
    $packageIds = @(Get-WingetPackageIds -ExportPath $temporaryExport)
    $packageManifest = [ordered]@{
        schemaVersion = 1
        generatedAt = (Get-Date).ToString('yyyy-MM-dd')
        packages = @($packageIds | ForEach-Object { [ordered]@{ id = $_ } })
    }
    $packageManifest |
        ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $softwarePath 'winget-packages.json') -Encoding UTF8
}
finally {
    if (Test-Path -LiteralPath $temporaryExport) {
        Remove-Item -LiteralPath $temporaryExport -Force
    }
}

$backupInfo = [ordered]@{
    schemaVersion = 1
    createdAt = (Get-Date).ToString('o')
    folders = @((Get-ChildItem -LiteralPath $filesPath -Directory | Select-Object -ExpandProperty Name))
    desktopSoftwareCount = @($installedSoftware | Where-Object kind -eq 'desktop').Count
    storeAppsCount = @($installedSoftware | Where-Object kind -eq 'store').Count
    wingetPackageCount = $packageIds.Count
}
$backupInfo |
    ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath (Join-Path $backupPath 'backup-info.json') -Encoding UTF8

Write-Output ''
Write-Output "Backup completato: $backupPath"
Write-Output ("Cartelle copiate: {0}" -f (@($backupInfo.folders) -join ', '))
Write-Output ("Programmi catalogati: {0}; pacchetti winget reinstallabili: {1}" -f $installedSoftware.Count, $packageIds.Count)
Write-Output 'Le app non disponibili in winget, le licenze e i dati degli account richiedono procedure manuali.'
