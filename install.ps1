#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$InstallRoot = 'C:\Program Files\QGroundControl',
    [string]$BackupRoot = 'C:\QGC-Backups',
    [string]$Version = 'v1.0.1'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$Repository = 'bondstas/QGroundControl_Patch'
$AssetName = "qgc-gstreamer-patch-$Version.zip"
$BaseUrl = "https://github.com/$Repository/releases/download/$Version"
$ZipUrl = "$BaseUrl/$AssetName"
$HashUrl = "$ZipUrl.sha256"

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run PowerShell as Administrator.'
    }
}

function Invoke-Robocopy {
    param([string]$Source, [string]$Destination, [switch]$Mirror)
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $mode = if ($Mirror) { '/MIR' } else { '/E' }
    & robocopy.exe $Source $Destination $mode /COPY:DAT /DCOPY:DAT /R:2 /W:1 /XJ /NFL /NDL /NP
    if ($LASTEXITCODE -gt 7) {
        throw "Robocopy failed with exit code ${LASTEXITCODE}: $Source -> $Destination"
    }
}

Assert-Administrator

$running = Get-Process QGroundControl -ErrorAction SilentlyContinue
if ($running) {
    throw 'Close all QGroundControl processes before installing.'
}

$exe = Join-Path $InstallRoot 'bin\QGroundControl.exe'
if (-not (Test-Path -LiteralPath $exe)) {
    throw "Chupacabra was not found: $exe"
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $BackupRoot "Chupacabra-$timestamp"
$temp = Join-Path ([IO.Path]::GetTempPath()) "QGC-Patch-$timestamp"
$zip = Join-Path $temp $AssetName
$hashFile = "$zip.sha256"
$extract = Join-Path $temp 'extracted'
$originalExeHash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
$backupComplete = $false

try {
    New-Item -ItemType Directory -Path $temp, $extract -Force | Out-Null

    Write-Host "Downloading patch $Version..." -ForegroundColor Cyan
    Invoke-WebRequest -UseBasicParsing -Uri $ZipUrl -OutFile $zip
    Invoke-WebRequest -UseBasicParsing -Uri $HashUrl -OutFile $hashFile

    $expectedZipHash = ((Get-Content -LiteralPath $hashFile -Raw).Trim() -split '\s+')[0].ToUpperInvariant()
    $actualZipHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($expectedZipHash -ne $actualZipHash) {
        throw 'Downloaded archive SHA-256 mismatch.'
    }

    Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
    $manifestPath = Join-Path $extract 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw 'manifest.json is missing from the archive.'
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    foreach ($file in $manifest.Files) {
        $payloadPath = Join-Path $extract $file.Path
        if (-not (Test-Path -LiteralPath $payloadPath)) {
            throw "Archive file is missing: $($file.Path)"
        }
        $actual = (Get-FileHash -LiteralPath $payloadPath -Algorithm SHA256).Hash
        if ($actual -ne $file.SHA256) {
            throw "File SHA-256 mismatch: $($file.Path)"
        }
    }

    Write-Host "Creating backup: $backup" -ForegroundColor Cyan
    Invoke-Robocopy -Source $InstallRoot -Destination $backup
    $backupComplete = $true

    # Never mix plugins from different GStreamer versions.
    $pluginTarget = Join-Path $InstallRoot 'lib\gstreamer-1.0'
    if (Test-Path -LiteralPath $pluginTarget) {
        $savedPluginTarget = Join-Path $InstallRoot "lib\gstreamer-1.0.pre-patch-$timestamp"
        Move-Item -LiteralPath $pluginTarget -Destination $savedPluginTarget
    }
    New-Item -ItemType Directory -Path $pluginTarget -Force | Out-Null

    foreach ($file in $manifest.Files) {
        $sourceFile = Join-Path $extract $file.Path
        $targetFile = Join-Path $InstallRoot $file.Path
        $targetDirectory = Split-Path -Parent $targetFile
        New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        Copy-Item -LiteralPath $sourceFile -Destination $targetFile -Force
    }

    $currentExeHash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
    if ($currentExeHash -ne $originalExeHash) {
        throw 'Safety check failed: custom QGroundControl.exe was modified.'
    }

    [ordered]@{
        Version = $Version
        InstalledAt = (Get-Date).ToString('o')
        Backup = $backup
        ArchiveSHA256 = $actualZipHash
        CustomExeSHA256 = $currentExeHash
        FileCount = @($manifest.Files).Count
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $InstallRoot 'PATCH-INSTALLED.json') -Encoding UTF8

    Write-Host 'Patch installed successfully.' -ForegroundColor Green
    Write-Host "Backup: $backup"
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    if ($backupComplete) {
        Write-Host 'Rolling back from backup...' -ForegroundColor Yellow
        Invoke-Robocopy -Source $backup -Destination $InstallRoot -Mirror
        Write-Host 'Original installation restored.' -ForegroundColor Green
    }
    throw
}
finally {
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
