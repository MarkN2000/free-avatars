[CmdletBinding()]
param(
    [string] $RepositoryRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent $PSScriptRoot
}

$repositoryRootPath = [System.IO.Path]::GetFullPath($RepositoryRoot)
$avatarsPath = Join-Path $repositoryRootPath 'avatars'
$catalogPath = Join-Path $repositoryRootPath 'catalog.json'

$avatarDirectories = @()
if (Test-Path -LiteralPath $avatarsPath -PathType Container) {
    $avatarDirectories = @(
        Get-ChildItem -LiteralPath $avatarsPath -Directory |
            Sort-Object @{ Expression = { if ($_.Name -match '^\d{3}_') { 1 } else { 0 } } }, Name
    )
}

$entries = @()
foreach ($directory in $avatarDirectories) {
    $packagePath = Join-Path $directory.FullName 'avatar.resonitepackage'
    $thumbnailPath = Join-Path $directory.FullName 'thumbnail.webp'

    if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
        throw "Missing package: $packagePath"
    }
    if (-not (Test-Path -LiteralPath $thumbnailPath -PathType Leaf)) {
        throw "Missing thumbnail: $thumbnailPath"
    }

    $relativeDirectory = "avatars/$($directory.Name)"
    $entries += [pscustomobject][ordered]@{
        path = "$relativeDirectory/avatar.resonitepackage"
        thumbnail = "$relativeDirectory/thumbnail.webp"
    }
}

$json = ConvertTo-Json -InputObject @($entries) -Compress
[System.IO.File]::WriteAllText(
    $catalogPath,
    $json + [System.Environment]::NewLine,
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host "Updated catalog.json ($($entries.Count) entries)."
