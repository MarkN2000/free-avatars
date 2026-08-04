[CmdletBinding()]
param(
    [string] $RepositoryRoot,
    [string] $SourceRoot,
    [string] $OutputDirectory,
    [string] $BlenderPath = 'C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe',
    [string[]] $AvatarName,
    [ValidateRange(0, 100000)]
    [int] $Limit = 0,
    [ValidateRange(0, 100)]
    [int] $Quality = 70,
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent $PSScriptRoot
}
$RepositoryRoot = [System.IO.Path]::GetFullPath($RepositoryRoot)

if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Join-Path $RepositoryRoot '.work\sources\PolygonalMind-100Avatars-v24.02.1'
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $RepositoryRoot '.work\staging\thumbnails'
}

$BlenderPath = [System.IO.Path]::GetFullPath($BlenderPath)
$SourceRoot = [System.IO.Path]::GetFullPath($SourceRoot)
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$renderScript = Join-Path $PSScriptRoot 'Render-VrmThumbnails.py'

if (-not (Test-Path -LiteralPath $BlenderPath -PathType Leaf)) {
    throw "Blender was not found: $BlenderPath"
}
if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
    throw "Source directory was not found: $SourceRoot"
}
if (-not (Test-Path -LiteralPath $renderScript -PathType Leaf)) {
    throw "Thumbnail renderer was not found: $renderScript"
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logPath = Join-Path $RepositoryRoot ".work\logs\thumbnails_$timestamp.json"
$arguments = @(
    '--background',
    '--factory-startup',
    '--python', $renderScript,
    '--',
    '--source-root', $SourceRoot,
    '--output-root', $OutputDirectory,
    '--log', $logPath,
    '--quality', $Quality
)
foreach ($name in $AvatarName) {
    $arguments += @('--avatar-name', $name)
}
if ($Limit -gt 0) {
    $arguments += @('--limit', $Limit)
}
if ($Force) {
    $arguments += '--force'
}

& $BlenderPath @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Thumbnail rendering failed with exit code $LASTEXITCODE. Log: $logPath"
}

Write-Host "Thumbnail rendering succeeded. Log: $logPath"
