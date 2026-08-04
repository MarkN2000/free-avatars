[CmdletBinding()]
param(
    [string] $RepositoryRoot,
    [string] $PackagesDirectory,
    [string] $ThumbnailsDirectory,
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent $PSScriptRoot
}
$RepositoryRoot = [System.IO.Path]::GetFullPath($RepositoryRoot)

if ([string]::IsNullOrWhiteSpace($PackagesDirectory)) {
    $PackagesDirectory = Join-Path $RepositoryRoot '.work\staging\packages'
}
if ([string]::IsNullOrWhiteSpace($ThumbnailsDirectory)) {
    $ThumbnailsDirectory = Join-Path $RepositoryRoot '.work\staging\thumbnails'
}

$PackagesDirectory = [System.IO.Path]::GetFullPath($PackagesDirectory)
$ThumbnailsDirectory = [System.IO.Path]::GetFullPath($ThumbnailsDirectory)
$avatarsDirectory = Join-Path $RepositoryRoot 'avatars'

if (-not (Test-Path -LiteralPath $PackagesDirectory -PathType Container)) {
    throw "Package staging directory was not found: $PackagesDirectory"
}
if (-not (Test-Path -LiteralPath $ThumbnailsDirectory -PathType Container)) {
    throw "Thumbnail staging directory was not found: $ThumbnailsDirectory"
}

$packages = @(Get-ChildItem -LiteralPath $PackagesDirectory -File -Filter '*.resonitepackage' | Sort-Object BaseName)
if ($packages.Count -eq 0) {
    throw "No staged packages were found: $PackagesDirectory"
}

$duplicatePackages = @($packages | Group-Object BaseName | Where-Object Count -gt 1)
if ($duplicatePackages.Count -gt 0) {
    throw "Duplicate staged package names: $(($duplicatePackages.Name) -join ', ')"
}

$thumbnailByName = @{}
foreach ($thumbnail in Get-ChildItem -LiteralPath $ThumbnailsDirectory -File -Filter '*.webp') {
    if ($thumbnailByName.ContainsKey($thumbnail.BaseName)) {
        throw "Duplicate staged thumbnail name: $($thumbnail.BaseName)"
    }
    $thumbnailByName[$thumbnail.BaseName] = $thumbnail
}

$missingThumbnails = @($packages | Where-Object { -not $thumbnailByName.ContainsKey($_.BaseName) })
if ($missingThumbnails.Count -gt 0) {
    throw "Packages without thumbnails: $(($missingThumbnails.BaseName) -join ', ')"
}

New-Item -ItemType Directory -Path $avatarsDirectory -Force | Out-Null
$copied = 0
$skipped = 0

foreach ($package in $packages) {
    $avatarDirectory = Join-Path $avatarsDirectory $package.BaseName
    $targetPackage = Join-Path $avatarDirectory 'avatar.resonitepackage'
    $targetThumbnail = Join-Path $avatarDirectory 'thumbnail.webp'

    if ((Test-Path -LiteralPath $avatarDirectory) -and -not $Force) {
        if ((Test-Path -LiteralPath $targetPackage -PathType Leaf) -and
            (Test-Path -LiteralPath $targetThumbnail -PathType Leaf)) {
            $skipped++
            continue
        }
        throw "Incomplete avatar directory already exists; use -Force after inspection: $avatarDirectory"
    }

    New-Item -ItemType Directory -Path $avatarDirectory -Force | Out-Null
    Copy-Item -LiteralPath $package.FullName -Destination $targetPackage -Force
    Copy-Item -LiteralPath $thumbnailByName[$package.BaseName].FullName -Destination $targetThumbnail -Force
    $copied++
}

$unusedThumbnails = @($thumbnailByName.Keys | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $PackagesDirectory ($_ + '.resonitepackage')) -PathType Leaf)
} | Sort-Object)
if ($unusedThumbnails.Count -gt 0) {
    Write-Warning "Thumbnails without successful packages were not published: $($unusedThumbnails -join ', ')"
}

& (Join-Path $PSScriptRoot 'Update-Catalog.ps1') -RepositoryRoot $RepositoryRoot
& (Join-Path $PSScriptRoot 'Test-Repository.ps1') -RepositoryRoot $RepositoryRoot

Write-Host "Build complete: $copied copied, $skipped existing avatars skipped."
