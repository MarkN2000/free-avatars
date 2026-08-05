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
    $rootFiles = @(Get-ChildItem -LiteralPath $directory.FullName -File)
    $hashDirectories = @(Get-ChildItem -LiteralPath $directory.FullName -Directory)
    if ($rootFiles.Count -ne 0 -or $hashDirectories.Count -ne 1) {
        throw "Avatar directory must contain exactly one package hash directory and no files: $($directory.FullName)"
    }

    $hashDirectory = $hashDirectories[0]
    if ($hashDirectory.Name -notmatch '^[0-9a-f]{8}$') {
        throw "Package hash directory must be the first 8 lowercase characters of a SHA-256 value: $($hashDirectory.FullName)"
    }

    $packagePath = Join-Path $hashDirectory.FullName 'avatar.resonitepackage'
    $thumbnailPath = Join-Path $hashDirectory.FullName 'thumbnail.webp'

    if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
        throw "Missing package: $packagePath"
    }
    if (-not (Test-Path -LiteralPath $thumbnailPath -PathType Leaf)) {
        throw "Missing thumbnail: $thumbnailPath"
    }

    $packageHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant().Substring(0, 8)
    if ($hashDirectory.Name -cne $packageHash) {
        throw "Package hash directory does not match the package content: $($hashDirectory.FullName)"
    }

    $relativeDirectory = "avatars/$($directory.Name)/$($hashDirectory.Name)"
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
