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
    $files = @(Get-ChildItem -LiteralPath $directory.FullName -File)
    $subdirectories = @(Get-ChildItem -LiteralPath $directory.FullName -Directory)
    $packages = @($files | Where-Object Extension -eq '.resonitepackage')
    $thumbnailPath = Join-Path $directory.FullName 'thumbnail.webp'
    if ($subdirectories.Count -ne 0 -or $files.Count -ne 2 -or $packages.Count -ne 1) {
        throw "Avatar directory must contain exactly one .resonitepackage and thumbnail.webp: $($directory.FullName)"
    }

    $packagePath = $packages[0].FullName

    if (-not (Test-Path -LiteralPath $thumbnailPath -PathType Leaf)) {
        throw "Missing thumbnail: $thumbnailPath"
    }

    $packageHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant().Substring(0, 8)
    $expectedPackageName = "$($directory.Name).$packageHash.resonitepackage"
    if ($packages[0].Name -cne $expectedPackageName) {
        throw "Package file name does not match the avatar name and package hash: $packagePath"
    }

    $relativeDirectory = "avatars/$($directory.Name)"
    $entries += [pscustomobject][ordered]@{
        path = "$relativeDirectory/$expectedPackageName"
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
