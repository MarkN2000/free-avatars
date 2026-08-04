[CmdletBinding()]
param(
    [string] $RepositoryRoot,
    [string] $AccountId = $env:CLOUDFLARE_ACCOUNT_ID,
    [string] $BucketName = 'free-avatars'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent $PSScriptRoot
}

if ([string]::IsNullOrWhiteSpace($AccountId)) {
    throw 'Cloudflare account ID is required. Set CLOUDFLARE_ACCOUNT_ID or pass -AccountId.'
}

if ([string]::IsNullOrWhiteSpace($BucketName)) {
    throw 'R2 bucket name is required.'
}

$awsCommand = Get-Command 'aws' -ErrorAction SilentlyContinue
if ($null -eq $awsCommand) {
    throw 'AWS CLI was not found in PATH.'
}

$repositoryRootPath = [System.IO.Path]::GetFullPath($RepositoryRoot)
$avatarsPath = Join-Path $repositoryRootPath 'avatars'
$catalogPath = Join-Path $repositoryRootPath 'catalog.json'
$testScriptPath = Join-Path $PSScriptRoot 'Test-Repository.ps1'

if (-not (Test-Path -LiteralPath $avatarsPath -PathType Container)) {
    throw "avatars directory does not exist: $avatarsPath"
}

if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
    throw "catalog.json does not exist: $catalogPath"
}

& $testScriptPath -RepositoryRoot $repositoryRootPath

$parsedCatalog = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($catalogPath, [System.Text.Encoding]::UTF8))
$catalog = @($parsedCatalog)
if ($catalog.Count -eq 0) {
    throw 'Deployment is blocked because catalog.json is empty.'
}

$expectedKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($entry in $catalog) {
    [void] $expectedKeys.Add([string] $entry.path)
    [void] $expectedKeys.Add([string] $entry.thumbnail)
}

$localFiles = @(Get-ChildItem -LiteralPath $avatarsPath -Recurse -File)
if ($localFiles.Count -ne $expectedKeys.Count) {
    throw "Deployment is blocked because the local file count ($($localFiles.Count)) does not match the catalog-derived count ($($expectedKeys.Count))."
}

$endpointUrl = "https://$AccountId.r2.cloudflarestorage.com"
$avatarsDestination = "s3://$BucketName/avatars/"

function Invoke-Aws {
    param([Parameter(Mandatory)][string[]] $Arguments)

    & $awsCommand.Source @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "AWS CLI failed with exit code $LASTEXITCODE."
    }
}

function Invoke-AwsJson {
    param([Parameter(Mandatory)][string[]] $Arguments)

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $awsCommand.Source @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($exitCode -ne 0) {
        throw "AWS CLI failed with exit code $exitCode.`n$($output -join [System.Environment]::NewLine)"
    }

    return ($output -join [System.Environment]::NewLine)
}

function Get-RemoteAvatarKeys {
    $json = Invoke-AwsJson -Arguments @(
        's3api', 'list-objects-v2',
        '--bucket', $BucketName,
        '--prefix', 'avatars/',
        '--query', 'Contents[].Key',
        '--output', 'json',
        '--endpoint-url', $endpointUrl
    )

    if ([string]::IsNullOrWhiteSpace($json) -or $json.Trim() -eq 'null') {
        return @()
    }

    return @((ConvertFrom-Json -InputObject $json) | Where-Object { -not [string]::IsNullOrWhiteSpace([string] $_) })
}

Write-Host "Uploading all avatar packages to R2 bucket '$BucketName'..."
Invoke-Aws -Arguments @(
    's3', 'cp', $avatarsPath, $avatarsDestination,
    '--recursive',
    '--exclude=*',
    '--include=*.resonitepackage',
    '--content-type', 'application/octet-stream',
    '--no-guess-mime-type',
    '--only-show-errors',
    '--endpoint-url', $endpointUrl
)

Write-Host "Uploading all thumbnails to R2 bucket '$BucketName'..."
Invoke-Aws -Arguments @(
    's3', 'cp', $avatarsPath, $avatarsDestination,
    '--recursive',
    '--exclude=*',
    '--include=*.webp',
    '--content-type', 'image/webp',
    '--no-guess-mime-type',
    '--only-show-errors',
    '--endpoint-url', $endpointUrl
)

Write-Host 'Uploading catalog.json...'
Invoke-Aws -Arguments @(
    's3', 'cp', $catalogPath, "s3://$BucketName/catalog.json",
    '--content-type', 'application/json',
    '--cache-control', 'no-cache',
    '--no-guess-mime-type',
    '--only-show-errors',
    '--endpoint-url', $endpointUrl
)

$remoteKeys = @(Get-RemoteAvatarKeys)
$obsoleteKeys = @($remoteKeys | Where-Object { -not $expectedKeys.Contains([string] $_) } | Sort-Object)
foreach ($key in $obsoleteKeys) {
    Write-Host "Deleting obsolete R2 object: $key"
    Invoke-Aws -Arguments @(
        's3api', 'delete-object',
        '--bucket', $BucketName,
        '--key', [string] $key,
        '--endpoint-url', $endpointUrl
    )
}

$publishedKeys = @(Get-RemoteAvatarKeys)
$missingKeys = @($expectedKeys | Where-Object { $_ -notin $publishedKeys })
$unexpectedKeys = @($publishedKeys | Where-Object { -not $expectedKeys.Contains([string] $_) })
if ($missingKeys.Count -ne 0 -or $unexpectedKeys.Count -ne 0) {
    throw "R2 verification failed. Missing: $($missingKeys.Count), unexpected: $($unexpectedKeys.Count)."
}

Write-Host "R2 deployment completed ($($catalog.Count) avatars, $($obsoleteKeys.Count) obsolete objects deleted)."
