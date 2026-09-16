#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RuntimeRoot = 'D:\QGC-Chupacabra-GStreamer-New',
    [string]$Repository = 'bondstas/QGroundControl_Patch',
    [string]$Version = 'v1.0.1'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$sourceBin = Join-Path $RuntimeRoot 'bin'
$sourcePlugins = Join-Path $RuntimeRoot 'lib\gstreamer-1.0'
if (-not (Test-Path -LiteralPath $sourceBin) -or -not (Test-Path -LiteralPath $sourcePlugins)) {
    throw "Verified working Chupacabra was not found: $RuntimeRoot"
}

if (-not (Get-Command gh.exe -ErrorAction SilentlyContinue)) {
    throw 'GitHub CLI (gh.exe) was not found.'
}

& gh.exe auth status
if ($LASTEXITCODE -ne 0) {
    throw 'Run gh auth login and try again.'
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
        throw "Failed to copy GStreamer plugins: $LASTEXITCODE"
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

    & gh.exe release create $Version $asset $hashFile --repo $Repository --title "QGroundControl Chupacabra GStreamer Patch $Version" --notes "GStreamer/RTSP update for Dahua Digest authentication. The installer creates a full backup before changing files."
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create GitHub Release $Version."
    }

    Write-Host "Release $Version published." -ForegroundColor Green
    Write-Host "One-command install: irm https://raw.githubusercontent.com/$Repository/main/install.ps1 | iex"
}
finally {
    if (Test-Path -LiteralPath $work) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
