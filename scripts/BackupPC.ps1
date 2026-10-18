[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Inventory', 'Backup', 'ExportWinget', 'Restore')]
    [string]$Mode = 'Menu'
)

$ErrorActionPreference = 'Stop'

function Get-InstalledSoftwareInventory {
    $items = [System.Collections.Generic.List[object]]::new()
    $uninstallKeys = @(
        @{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'; Source = 'Registro Windows 64 bit' },
        @{ Path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'; Source = 'Registro Windows 32 bit' },
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'; Source = 'Registro utente' },
        @{ Path = 'HKCU:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'; Source = 'Registro utente 32 bit' }
    )

    foreach ($entry in $uninstallKeys) {
        if (-not (Test-Path -Path ($entry.Path -replace '\\\*$', ''))) { continue }
        foreach ($app in (Get-ItemProperty -Path $entry.Path -ErrorAction SilentlyContinue)) {
            if ([string]::IsNullOrWhiteSpace([string]$app.DisplayName)) { continue }
            if ($app.SystemComponent -eq 1 -or $app.ParentKeyName -or $app.ReleaseType) { continue }

            $items.Add([pscustomobject]@{
                Name           = [string]$app.DisplayName
                Version        = [string]$app.DisplayVersion
                Publisher      = [string]$app.Publisher
                InstallLocation = [string]$app.InstallLocation
                Type           = 'Programma desktop'
                Source         = $entry.Source
            })
        }
    }

    if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) {
        foreach ($app in (Get-AppxPackage -ErrorAction SilentlyContinue)) {
            if ($app.IsFramework -or $app.IsResourcePackage -or [string]::IsNullOrWhiteSpace([string]$app.Name)) { continue }
            $items.Add([pscustomobject]@{
                Name            = [string]$app.Name
                Version         = [string]$app.Version
                Publisher       = [string]$app.Publisher
                InstallLocation = [string]$app.InstallLocation
                Type            = 'App Microsoft Store'
                Source          = 'Windows Appx'
            })
        }
    }

    $steamRoots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($registryPath in @('HKCU:\Software\Valve\Steam', 'HKCU:\Software\Valve\Steam\ActiveProcess')) {
        if (Test-Path -LiteralPath $registryPath) {
            $steamSettings = Get-ItemProperty -LiteralPath $registryPath -ErrorAction SilentlyContinue
            foreach ($propertyName in @('SteamPath', 'InstallPath')) {
                $value = [string]$steamSettings.$propertyName
                if (-not [string]::IsNullOrWhiteSpace($value) -and (Test-Path -LiteralPath $value -PathType Container)) {
                    [void]$steamRoots.Add([System.IO.Path]::GetFullPath($value))
                }
            }
        }
    }
    foreach ($programFilesRoot in @(${env:ProgramFiles(x86)}, $env:ProgramFiles) | Where-Object { $_ }) {
        $candidate = Join-Path $programFilesRoot 'Steam'
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Container)) {
            [void]$steamRoots.Add([System.IO.Path]::GetFullPath($candidate))
        }
    }

    $steamLibraries = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($steamRoot in $steamRoots) {
        [void]$steamLibraries.Add($steamRoot)
        $libraryFile = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $libraryFile -PathType Leaf) {
            foreach ($match in (Select-String -LiteralPath $libraryFile -Pattern '"path"\s+"([^"]+)"' -AllMatches).Matches) {
                $libraryPath = $match.Groups[1].Value.Replace('\\', '\')
                if (Test-Path -LiteralPath $libraryPath -PathType Container) {
                    [void]$steamLibraries.Add([System.IO.Path]::GetFullPath($libraryPath))
                }
            }
        }
    }

    foreach ($library in $steamLibraries) {
        $steamAppsPath = Join-Path $library 'steamapps'
        if (-not (Test-Path -LiteralPath $steamAppsPath -PathType Container)) { continue }
        foreach ($manifest in (Get-ChildItem -LiteralPath $steamAppsPath -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue)) {
            $contents = Get-Content -LiteralPath $manifest.FullName -Raw
            $nameMatch = [regex]::Match($contents, '"name"\s+"([^"]+)"')
            $folderMatch = [regex]::Match($contents, '"installdir"\s+"([^"]+)"')
            if (-not $nameMatch.Success -or -not $folderMatch.Success) { continue }
            $installLocation = Join-Path (Join-Path $steamAppsPath 'common') $folderMatch.Groups[1].Value
            $items.Add([pscustomobject]@{
                Name            = $nameMatch.Groups[1].Value
                Version         = ''
                Publisher       = ''
                InstallLocation = $installLocation
                Type            = 'Gioco Steam'
                Source          = 'Manifest Steam'
            })
        }
    }

    $epicManifestDirectory = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
    if (Test-Path -LiteralPath $epicManifestDirectory -PathType Container) {
        foreach ($manifest in (Get-ChildItem -LiteralPath $epicManifestDirectory -Filter '*.item' -File -ErrorAction Stop)) {
            $game = Get-Content -LiteralPath $manifest.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
            if ($game.bIsIncompleteInstall -or [string]::IsNullOrWhiteSpace([string]$game.DisplayName) -or
                [string]::IsNullOrWhiteSpace([string]$game.InstallLocation)) { continue }
            $items.Add([pscustomobject]@{
                Name            = [string]$game.DisplayName
                Version         = ''
                Publisher       = ''
                InstallLocation = [string]$game.InstallLocation
                Type            = 'Gioco Epic Games'
                Source          = 'Manifest Epic Games Launcher'
            })
        }
    }

    return $items | Sort-Object Name, Type, InstallLocation
}

function Export-InstalledSoftwareInventory {
    $inventory = @(Get-InstalledSoftwareInventory)
    $outputDirectory = Join-Path $env:USERPROFILE 'Documents\Backup PC\Inventario'
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $jsonPath = Join-Path $outputDirectory "inventario-$timestamp.json"
    $csvPath = Join-Path $outputDirectory "inventario-$timestamp.csv"

    ConvertTo-Json -InputObject $inventory -Depth 4 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    $inventory | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
    Write-Host "Elementi trovati: $($inventory.Count)"
    Write-Host "Inventario JSON: $jsonPath"
    Write-Host "Inventario CSV:  $csvPath"
}

function Get-WingetPackages {
    param([Parameter(Mandatory)][string]$ManifestPath)

    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
    $packages = @(
        foreach ($source in @($manifest.Sources)) {
            foreach ($package in @($source.Packages)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$package.PackageIdentifier)) {
                    $package
                }
            }
        }
        foreach ($package in @($manifest.Packages)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$package.PackageIdentifier)) {
                $package
            }
        }
    )

    if ($packages.Count -eq 0) {
        throw "Il manifest non contiene pacchetti winget reinstallabili: $ManifestPath"
    }
    return $packages
}

function Export-WingetRestoreManifest {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw 'Windows Package Manager (winget) non è installato o non è disponibile.'
    }

    $outputDirectory = Join-Path $env:USERPROFILE 'Documents\Backup PC\Ripristino'
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    $manifestPath = Join-Path $outputDirectory ('winget-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')

    Write-Host 'Creo un manifest dei pacchetti che winget riconosce sul PC.'
    Write-Host 'Programmi e giochi non disponibili nei cataloghi winget non potranno essere inclusi.'
    & winget.exe export --output $manifestPath --include-versions --accept-source-agreements --disable-interactivity
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "winget export non è riuscito (codice $exitCode)."
    }
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'winget export non ha creato il manifest.'
    }

    $packages = @(Get-WingetPackages -ManifestPath $manifestPath)
    Write-Host "Pacchetti riconosciuti: $($packages.Count)"
    Write-Host "Manifest da copiare sul PC nuovo: $manifestPath"
}

function Restore-WingetPackages {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw 'Windows Package Manager (winget) non è installato o non è disponibile.'
    }

    $manifestInput = Read-Host 'Percorso del manifest winget copiato dal vecchio PC'
    if ([string]::IsNullOrWhiteSpace($manifestInput)) { throw 'Il percorso del manifest è obbligatorio.' }
    $manifestPath = (Resolve-Path -LiteralPath $manifestInput -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Il manifest deve essere un file.' }

    $packages = @(Get-WingetPackages -ManifestPath $manifestPath)
    Write-Host ''
    Write-Host 'ANTEPRIMA: winget installerà i pacchetti elencati, usando le versioni disponibili correnti.'
    Write-Host "Manifest: $manifestPath"
    Write-Host "Pacchetti: $($packages.Count)"
    foreach ($package in $packages) {
        $version = if ([string]::IsNullOrWhiteSpace([string]$package.Version)) { 'versione disponibile' } else { [string]$package.Version }
        Write-Host "  $($package.PackageIdentifier) ($version)"
    }
    Write-Host ''
    Write-Host 'Potrebbero essere richieste autorizzazioni amministrative; controlla le richieste di winget.'
    $confirmation = Read-Host 'Digita INSTALL per avviare la reinstallazione'
    if ($confirmation -cne 'INSTALL') {
        Write-Host 'Operazione annullata; non è stato installato nulla.'
        return
    }

    & winget.exe import --import-file $manifestPath --ignore-versions --accept-package-agreements --accept-source-agreements
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "winget import non è riuscito o ha segnalato errori (codice $exitCode). Controlla l'output di winget per i pacchetti non installati."
    }
    Write-Host "Importazione completata. Verifica l'output di winget per eventuali pacchetti saltati."
}

function Test-PathWithin {
    param([string]$Path, [string]$Root)

    $normalizedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    $normalizedRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
    return $normalizedPath.Equals($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalizedPath.StartsWith($normalizedRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-PersonalDataFiles {
    param([string]$SourcePath)

    $allowedExtensions = @(
        '.cfg', '.conf', '.dat', '.db', '.dsv', '.ini', '.json', '.log', '.plist',
        '.sav', '.save', '.srm', '.sqlite', '.sqlite3', '.toml', '.txt', '.xml',
        '.yaml', '.yml'
    )
    $pendingDirectories = [System.Collections.Generic.Stack[string]]::new()
    $pendingDirectories.Push($SourcePath)
    $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

    while ($pendingDirectories.Count -gt 0) {
        $directory = $pendingDirectories.Pop()
        foreach ($childDirectory in (Get-ChildItem -LiteralPath $directory -Directory -Force -ErrorAction Stop)) {
            if (($childDirectory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
                $pendingDirectories.Push($childDirectory.FullName)
            }
        }
        foreach ($file in (Get-ChildItem -LiteralPath $directory -File -Force -ErrorAction Stop)) {
            if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            if ($allowedExtensions -contains $file.Extension.ToLowerInvariant()) {
                $stream = [System.IO.File]::OpenRead($file.FullName)
                try {
                    $isPortableExecutable = $stream.ReadByte() -eq 0x4D -and $stream.ReadByte() -eq 0x5A
                }
                finally {
                    $stream.Dispose()
                }
                if (-not $isPortableExecutable) { $files.Add($file) }
            }
        }
    }
    return $files | Sort-Object FullName
}

function Start-PersonalDataBackup {
    $sourceInput = Read-Host 'Percorso della cartella specifica con salvataggi o impostazioni personali'
    if ([string]::IsNullOrWhiteSpace($sourceInput)) { throw 'Il percorso sorgente è obbligatorio.' }
    $sourcePath = (Resolve-Path -LiteralPath $sourceInput -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) { throw 'La sorgente deve essere una cartella.' }
    $sourcePath = [System.IO.Path]::GetFullPath($sourcePath)

    $profileRoots = @(
        $env:USERPROFILE,
        (Join-Path $env:USERPROFILE 'AppData'),
        (Join-Path $env:USERPROFILE 'Documents'),
        (Join-Path $env:USERPROFILE 'Desktop'),
        (Join-Path $env:USERPROFILE 'Downloads'),
        (Join-Path $env:USERPROFILE 'Pictures'),
        (Join-Path $env:USERPROFILE 'Music'),
        (Join-Path $env:USERPROFILE 'Videos')
    ) | Where-Object { $_ }
    $blockedRoots = @($profileRoots, $env:windir, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData) |
        Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) }
    foreach ($blockedRoot in $blockedRoots) {
        if ([System.IO.Path]::GetFullPath($sourcePath).TrimEnd('\').Equals(
            [System.IO.Path]::GetFullPath($blockedRoot).TrimEnd('\'),
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            throw "Selezione troppo ampia: scegli una sottocartella specifica, non '$blockedRoot'."
        }
        if ((Test-PathWithin -Path $sourcePath -Root $blockedRoot) -and
            ($blockedRoot -eq $env:windir -or $blockedRoot -eq $env:ProgramFiles -or
             $blockedRoot -eq ${env:ProgramFiles(x86)} -or $blockedRoot -eq $env:ProgramData)) {
            throw "La sorgente è in una cartella di sistema o programmi: '$sourcePath'."
        }
    }

    $destinationInput = Read-Host 'Cartella di destinazione del backup'
    if ([string]::IsNullOrWhiteSpace($destinationInput)) { throw 'Il percorso di destinazione è obbligatorio.' }
    $destinationPath = [System.IO.Path]::GetFullPath($destinationInput)
    if ((Test-PathWithin -Path $destinationPath -Root $sourcePath) -or
        (Test-PathWithin -Path $sourcePath -Root $destinationPath)) {
        throw 'Sorgente e destinazione non possono coincidere né contenersi a vicenda.'
    }

    $inventory = @(Get-InstalledSoftwareInventory)
    foreach ($app in $inventory) {
        if (-not [string]::IsNullOrWhiteSpace($app.InstallLocation) -and
            (Test-Path -LiteralPath $app.InstallLocation -PathType Container) -and
            (Test-PathWithin -Path $sourcePath -Root $app.InstallLocation)) {
            throw "La sorgente è dentro la cartella di installazione di '$($app.Name)'. Seleziona solo i dati personali, non i file del programma o del gioco."
        }
        if (-not [string]::IsNullOrWhiteSpace($app.InstallLocation) -and
            (Test-Path -LiteralPath $app.InstallLocation -PathType Container) -and
            (Test-PathWithin -Path $app.InstallLocation -Root $sourcePath)) {
            throw "La cartella selezionata contiene l'installazione di '$($app.Name)'. Scegli una cartella più specifica con soli dati personali."
        }
    }

    $files = @(Get-PersonalDataFiles -SourcePath $sourcePath)
    if ($files.Count -eq 0) {
        throw 'Nessun file di impostazioni o salvataggio con estensione supportata trovato; non è stato copiato nulla.'
    }

    $totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
    Write-Host ''
    Write-Host 'ANTEPRIMA: verranno copiati solo file con estensioni di configurazione/salvataggio riconosciute.'
    Write-Host "Sorgente:      $sourcePath"
    Write-Host "Destinazione:  $destinationPath"
    Write-Host "File:          $($files.Count)"
    Write-Host ('Dimensione:    {0:N2} MB' -f ($totalBytes / 1MB))
    foreach ($file in $files) {
        Write-Host ('  {0} ({1:N0} byte)' -f $file.FullName, $file.Length)
    }
    Write-Host ''
    $confirmation = Read-Host 'Digita BACKUP per confermare la copia'
    if ($confirmation -cne 'BACKUP') {
        Write-Host 'Operazione annullata; non è stato copiato nulla.'
        return
    }

    $backupPath = Join-Path $destinationPath ('BackupPC-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
    foreach ($file in $files) {
        $relativePath = $file.FullName.Substring($sourcePath.TrimEnd('\').Length).TrimStart('\')
        $targetPath = Join-Path $backupPath $relativePath
        $targetDirectory = Split-Path -Parent $targetPath
        New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $targetPath
    }

    $manifest = [pscustomobject]@{
        CreatedAt   = (Get-Date).ToString('o')
        Source      = $sourcePath
        FileCount   = $files.Count
        TotalBytes  = [long]$totalBytes
        Files       = @($files | ForEach-Object {
            [pscustomobject]@{
                RelativePath = $_.FullName.Substring($sourcePath.TrimEnd('\').Length).TrimStart('\')
                Bytes        = $_.Length
            }
        })
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backupPath 'backup-manifest.json') -Encoding UTF8
    Write-Host "Backup completato: $backupPath"
    Write-Host "File copiati: $($files.Count)"
}

function Show-Menu {
    Write-Host ''
    Write-Host 'Backup PC - catalogo e backup dei dati personali'
    Write-Host '1. Crea inventario di programmi e giochi installati'
    Write-Host '2. Backup di impostazioni o salvataggi selezionati'
    Write-Host '3. Esporta i pacchetti reinstallabili con winget'
    Write-Host '4. Reinstalla i pacchetti da un manifest winget'
    Write-Host 'Q. Esci'
    switch ((Read-Host 'Scegli una opzione').Trim().ToUpperInvariant()) {
        '1' { Export-InstalledSoftwareInventory }
        '2' { Start-PersonalDataBackup }
        '3' { Export-WingetRestoreManifest }
        '4' { Restore-WingetPackages }
        'Q' { return }
        default { throw 'Opzione non valida.' }
    }
}

switch ($Mode) {
    'Inventory' { Export-InstalledSoftwareInventory }
    'Backup' { Start-PersonalDataBackup }
    'ExportWinget' { Export-WingetRestoreManifest }
    'Restore' { Restore-WingetPackages }
    'Menu' { Show-Menu }
}
