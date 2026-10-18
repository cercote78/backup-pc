[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\manifest\apps.json')
)

$ErrorActionPreference = 'Stop'
$winget = Get-Command winget -ErrorAction SilentlyContinue
if (-not $winget) {
    throw 'winget non è disponibile. Installa o aggiorna App Installer e riprova.'
}

$resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$temporaryPath = Join-Path ([System.IO.Path]::GetTempPath()) ("backup-pc-{0}.json" -f [guid]::NewGuid())
try {
    & $winget.Source export --output $temporaryPath --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        throw "winget export è terminato con codice $LASTEXITCODE."
    }
    if (-not (Test-Path -LiteralPath $temporaryPath -PathType Leaf)) {
        throw 'winget export non ha creato il file di inventario atteso.'
    }

    $export = Get-Content -LiteralPath $temporaryPath -Raw | ConvertFrom-Json
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
        '^EPSON\.PrinterConnectionChecker$',
        '^EPSON\.EpsonNetPrint$'
    )

    $packageIds = @(
        foreach ($source in $export.Sources) {
            foreach ($package in $source.Packages) {
                $id = [string]$package.PackageIdentifier
                if ([string]::IsNullOrWhiteSpace($id) -or $id -match '^Microsoft\.Security\.' -or
                    $id -match '^DisableWindowsDefender' -or $id -match '^Security_Xploded\.') {
                    continue
                }

                $excluded = $false
                foreach ($pattern in $excludedIdPatterns) {
                    if ($id -match $pattern) {
                        $excluded = $true
                        break
                    }
                }
                if (-not $excluded) {
                    $id
                }
            }
        }
    ) | Sort-Object -Unique

    if ($packageIds.Count -eq 0) {
        throw 'Non è stato trovato alcun pacchetto winget idoneo. Il manifest esistente è stato mantenuto.'
    }

    $manifest = [ordered]@{
        schemaVersion = 1
        generatedAt = (Get-Date).ToString('yyyy-MM-dd')
        packages = @($packageIds | ForEach-Object { [ordered]@{ id = $_ } })
    }
    $json = $manifest | ConvertTo-Json -Depth 5
    Set-Content -LiteralPath $resolvedOutputPath -Value $json -Encoding UTF8
    Write-Output ("Manifest creato: {0} ({1} pacchetti)." -f $resolvedOutputPath, $packageIds.Count)
    Write-Output 'Verifica gli identificativi e conserva questo inventario personale nel repository privato.'
}
finally {
    if (Test-Path -LiteralPath $temporaryPath) {
        Remove-Item -LiteralPath $temporaryPath -Force
    }
}
