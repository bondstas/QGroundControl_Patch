#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RuntimeRoot = 'C:\Program Files\QGroundContro_workl',
    [string]$Repository = 'bondstas/QGroundControl_Patch',
    [string]$Version = 'v1.0.0'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$sourceBin = Join-Path $RuntimeRoot 'bin'
$sourcePlugins = Join-Path $RuntimeRoot 'lib\gstreamer-1.0'
if (-not (Test-Path -LiteralPath $sourceBin) -or -not (Test-Path -LiteralPath $sourcePlugins)) {
    throw "Не найден проверенный runtime QGC 5.1: $RuntimeRoot"
}

if (-not (Get-Command gh.exe -ErrorAction SilentlyContinue)) {
    throw 'Не найден GitHub CLI (gh.exe). Установите: winget install GitHub.cli'
}

& gh.exe auth status
if ($LASTEXITCODE -ne 0) {
    throw 'Выполните gh auth login и повторите запуск.'
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$work = Join-Path ([IO.Path]::GetTempPath()) "QGC-Release-$timestamp"
$payload = Join-Path $work 'payload'
$payloadBin = Join-Path $payload 'bin'
$payloadPlugins = Join-Path $payload 'lib\gstreamer-1.0'
$assetName = "qgc-gstreamer-patch-$Version.zip"
$asset = Join-Path $work $assetName
$hashFile = "$asset.sha256"

try {
    New-Item -ItemType Directory -Path $payloadBin, $payloadPlugins -Force | Out-Null

    Get-ChildItem -LiteralPath $sourceBin -File | Where-Object {
        $_.Extension -eq '.dll' -and $_.Name -notlike 'Qt6*'
    } | Copy-Item -Destination $payloadBin -Force

    & robocopy.exe $sourcePlugins $payloadPlugins /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /XJ /NFL /NDL /NP
    if ($LASTEXITCODE -gt 7) {
        throw "Ошибка копирования GStreamer-плагинов: $LASTEXITCODE"
    }

    $files = Get-ChildItem -LiteralPath $payload -File -Recurse | ForEach-Object {
        [ordered]@{
            Path = $_.FullName.Substring($payload.Length).TrimStart('\')
            Length = $_.Length
            SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    }

    [ordered]@{
        Version = $Version
        BuiltAt = (Get-Date).ToString('o')
        Source = $RuntimeRoot
        Files = @($files)
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $payload 'manifest.json') -Encoding UTF8

    Compress-Archive -Path (Join-Path $payload '*') -DestinationPath $asset -CompressionLevel Optimal
    $assetHash = (Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash
    "$assetHash  $assetName" | Set-Content -LiteralPath $hashFile -Encoding ASCII

    & gh.exe release create $Version $asset $hashFile --repo $Repository --title "QGroundControl Chupacabra GStreamer Patch $Version" --notes "Обновление GStreamer/RTSP для Dahua Digest authentication. Перед установкой создаётся полная резервная копия."
    if ($LASTEXITCODE -ne 0) {
        throw "Не удалось создать GitHub Release $Version."
    }

    Write-Host "Release $Version опубликован." -ForegroundColor Green
    Write-Host "Однокомандная установка: irm https://raw.githubusercontent.com/$Repository/main/install.ps1 | iex"
}
finally {
    if (Test-Path -LiteralPath $work) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

