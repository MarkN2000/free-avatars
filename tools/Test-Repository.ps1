[CmdletBinding()]
param(
    [string] $RepositoryRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent $PSScriptRoot
}

function Get-WebPDimensions {
    param([Parameter(Mandatory)][string] $Path)

    [byte[]] $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 20) {
        throw "WebP file is too short: $Path"
    }

    $ascii = [System.Text.Encoding]::ASCII
    if ($ascii.GetString($bytes, 0, 4) -ne 'RIFF' -or $ascii.GetString($bytes, 8, 4) -ne 'WEBP') {
        throw "Not a WebP file: $Path"
    }

    $offset = 12
    while ($offset + 8 -le $bytes.Length) {
        $chunkType = $ascii.GetString($bytes, $offset, 4)
        [uint32] $chunkSize = [System.BitConverter]::ToUInt32($bytes, $offset + 4)
        $dataOffset = $offset + 8
        if ([uint64] $dataOffset + $chunkSize -gt $bytes.Length) {
            throw "Invalid WebP chunk length: $Path"
        }

        switch ($chunkType) {
            'VP8X' {
                if ($chunkSize -lt 10) { throw "Invalid VP8X chunk: $Path" }
                $width = 1 + $bytes[$dataOffset + 4] + ($bytes[$dataOffset + 5] -shl 8) + ($bytes[$dataOffset + 6] -shl 16)
                $height = 1 + $bytes[$dataOffset + 7] + ($bytes[$dataOffset + 8] -shl 8) + ($bytes[$dataOffset + 9] -shl 16)
                return [pscustomobject]@{ Width = $width; Height = $height }
            }
            'VP8 ' {
                if ($chunkSize -lt 10 -or $bytes[$dataOffset + 3] -ne 0x9d -or $bytes[$dataOffset + 4] -ne 0x01 -or $bytes[$dataOffset + 5] -ne 0x2a) {
                    throw "Invalid VP8 frame header: $Path"
                }
                $width = ([System.BitConverter]::ToUInt16($bytes, $dataOffset + 6)) -band 0x3fff
                $height = ([System.BitConverter]::ToUInt16($bytes, $dataOffset + 8)) -band 0x3fff
                return [pscustomobject]@{ Width = $width; Height = $height }
            }
            'VP8L' {
                if ($chunkSize -lt 5 -or $bytes[$dataOffset] -ne 0x2f) {
                    throw "Invalid VP8L frame header: $Path"
                }
                $b1 = [uint32] $bytes[$dataOffset + 1]
                $b2 = [uint32] $bytes[$dataOffset + 2]
                $b3 = [uint32] $bytes[$dataOffset + 3]
                $b4 = [uint32] $bytes[$dataOffset + 4]
                $width = 1 + $b1 + (($b2 -band 0x3f) -shl 8)
                $height = 1 + ($b2 -shr 6) + ($b3 -shl 2) + (($b4 -band 0x0f) -shl 10)
                return [pscustomobject]@{ Width = $width; Height = $height }
            }
        }

        $offset = $dataOffset + [int] $chunkSize + ([int] $chunkSize -band 1)
    }

    throw "WebP image chunk was not found: $Path"
}

$repositoryRootPath = [System.IO.Path]::GetFullPath($RepositoryRoot)
$avatarsPath = Join-Path $repositoryRootPath 'avatars'
$catalogPath = Join-Path $repositoryRootPath 'catalog.json'

if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
    throw "catalog.json does not exist: $catalogPath"
}

$catalogText = [System.IO.File]::ReadAllText($catalogPath, [System.Text.Encoding]::UTF8)
$trimmedCatalog = $catalogText.Trim()
if (-not ($trimmedCatalog.StartsWith('[') -and $trimmedCatalog.EndsWith(']'))) {
    throw 'catalog.json must contain a top-level JSON array.'
}

$parsedCatalog = ConvertFrom-Json -InputObject $catalogText
$entries = @($parsedCatalog)
$expectedEntries = @()
$seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

$avatarDirectories = @()
if (Test-Path -LiteralPath $avatarsPath -PathType Container) {
    $avatarDirectories = @(
        Get-ChildItem -LiteralPath $avatarsPath -Directory |
            Sort-Object @{ Expression = { if ($_.Name -match '^\d{3}_') { 1 } else { 0 } } }, Name
    )
}

foreach ($directory in $avatarDirectories) {
    $files = @(Get-ChildItem -LiteralPath $directory.FullName -File)
    $subdirectories = @(Get-ChildItem -LiteralPath $directory.FullName -Directory)
    if ($files.Count -ne 0 -or $subdirectories.Count -ne 1) {
        throw "Avatar directory must contain exactly one package hash directory and no files: $($directory.FullName)"
    }

    $hashDirectory = $subdirectories[0]
    if ($hashDirectory.Name -notmatch '^[0-9a-f]{8}$') {
        throw "Package hash directory must be the first 8 lowercase characters of a SHA-256 value: $($hashDirectory.FullName)"
    }

    $hashFiles = @(Get-ChildItem -LiteralPath $hashDirectory.FullName -File)
    $hashSubdirectories = @(Get-ChildItem -LiteralPath $hashDirectory.FullName -Directory)
    $unexpectedHashFiles = @($hashFiles | Where-Object Name -notin @('avatar.resonitepackage', 'thumbnail.webp'))
    if ($hashSubdirectories.Count -ne 0 -or $unexpectedHashFiles.Count -ne 0 -or $hashFiles.Count -ne 2) {
        throw "Package hash directory must contain only avatar.resonitepackage and thumbnail.webp: $($hashDirectory.FullName)"
    }

    $package = Get-Item -LiteralPath (Join-Path $hashDirectory.FullName 'avatar.resonitepackage')
    $thumbnail = Get-Item -LiteralPath (Join-Path $hashDirectory.FullName 'thumbnail.webp')
    if ($package.Length -eq 0) { throw "Package is empty: $($package.FullName)" }
    if ($thumbnail.Length -eq 0) { throw "Thumbnail is empty: $($thumbnail.FullName)" }

    $packageHash = (Get-FileHash -LiteralPath $package.FullName -Algorithm SHA256).Hash.ToLowerInvariant().Substring(0, 8)
    if ($hashDirectory.Name -cne $packageHash) {
        throw "Package hash directory does not match the package content: $($hashDirectory.FullName)"
    }

    $dimensions = Get-WebPDimensions -Path $thumbnail.FullName
    if ($dimensions.Width -ne 256 -or $dimensions.Height -ne 256) {
        throw "Thumbnail must be 256x256: $($thumbnail.FullName) ($($dimensions.Width)x$($dimensions.Height))"
    }

    $relativeDirectory = "avatars/$($directory.Name)/$($hashDirectory.Name)"
    $expectedEntries += [pscustomobject][ordered]@{
        path = "$relativeDirectory/avatar.resonitepackage"
        thumbnail = "$relativeDirectory/thumbnail.webp"
    }
}

for ($index = 0; $index -lt $entries.Count; $index++) {
    $entry = $entries[$index]
    $propertyNames = @($entry.PSObject.Properties.Name)
    if ($propertyNames.Count -ne 2 -or 'path' -notin $propertyNames -or 'thumbnail' -notin $propertyNames) {
        throw "Catalog entry $index must contain only path and thumbnail."
    }
    if (-not $seenPaths.Add([string] $entry.path)) {
        throw "Duplicate catalog path: $($entry.path)"
    }
}

$actualJson = ConvertTo-Json -InputObject @($entries) -Compress
$expectedJson = ConvertTo-Json -InputObject @($expectedEntries) -Compress
if ($actualJson -cne $expectedJson) {
    throw 'catalog.json is out of date. Run tools/Update-Catalog.ps1.'
}

if ($entries.Count -gt 0) {
    $packagePaths = @($entries | ForEach-Object { [string] $_.path })
    for ($offset = 0; $offset -lt $packagePaths.Count; $offset += 50) {
        $batch = @($packagePaths | Select-Object -Skip $offset -First 50)
        $attributes = @(& git -C $repositoryRootPath check-attr filter -- @batch)
        if ($LASTEXITCODE -ne 0 -or @($attributes | Where-Object { $_ -notmatch ': filter: lfs$' }).Count -ne 0) {
            throw 'One or more .resonitepackage files are not covered by Git LFS.'
        }
    }
}

Write-Host "Repository validation passed ($($entries.Count) avatars)."
