[CmdletBinding()]
param(
    [string] $RepositoryRoot,
    [string] $SourceRoot,
    [string] $StagingDirectory,
    [string] $ResoPonPath,
    [string] $ResonitePath,
    [string[]] $AvatarName = @(),
    [string[]] $ExcludeAvatarName = @(),
    [ValidateRange(0, 100000)]
    [int] $Limit = 0,
    [ValidateRange(1, 100)]
    [int] $BatchSize = 50,
    [switch] $ContinueOnError,
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
if ([string]::IsNullOrWhiteSpace($StagingDirectory)) {
    $StagingDirectory = Join-Path $RepositoryRoot '.work\staging\packages'
}

$SourceRoot = [System.IO.Path]::GetFullPath($SourceRoot)
$StagingDirectory = [System.IO.Path]::GetFullPath($StagingDirectory)

if ([string]::IsNullOrWhiteSpace($ResoPonPath)) {
    $ResoPonPath = [System.Environment]::GetEnvironmentVariable('RESOPON_PATH', 'Process')
}
if ([string]::IsNullOrWhiteSpace($ResoPonPath)) {
    $resoPonCommand = Get-Command 'ResoPon.exe' -CommandType Application -ErrorAction SilentlyContinue
    if ($null -ne $resoPonCommand) {
        $ResoPonPath = $resoPonCommand.Source
    }
}
if ([string]::IsNullOrWhiteSpace($ResoPonPath)) {
    throw 'ResoPon.exe was not found. Specify -ResoPonPath, set RESOPON_PATH, or add ResoPon.exe to PATH.'
}
$ResoPonPath = [System.IO.Path]::GetFullPath($ResoPonPath)
if (-not (Test-Path -LiteralPath $ResoPonPath -PathType Leaf)) {
    throw "ResoPon.exe was not found at the configured path: $ResoPonPath"
}
if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
    throw "Source directory was not found: $SourceRoot"
}

$allVrms = @(Get-ChildItem -LiteralPath $SourceRoot -Recurse -File -Filter '*.vrm' | Sort-Object FullName)
if ($allVrms.Count -eq 0) {
    throw "No VRM files were found: $SourceRoot"
}

$duplicateNames = @($allVrms | Group-Object BaseName | Where-Object Count -gt 1)
if ($duplicateNames.Count -gt 0) {
    $names = ($duplicateNames | ForEach-Object Name) -join ', '
    throw "Duplicate VRM base names were found: $names"
}

$vrms = $allVrms
if ($null -ne $AvatarName -and $AvatarName.Length -gt 0) {
    $requestedNames = [System.Collections.Generic.HashSet[string]]::new(
        [string[]] $AvatarName,
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $vrms = @($allVrms | Where-Object { $requestedNames.Contains($_.BaseName) })
    $foundNames = [System.Collections.Generic.HashSet[string]]::new(
        [string[]] @($vrms.BaseName),
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $missingNames = @($AvatarName | Where-Object { -not $foundNames.Contains($_) })
    if ($missingNames.Count -gt 0) {
        throw "Requested avatars were not found: $($missingNames -join ', ')"
    }
}
if ($null -ne $ExcludeAvatarName -and $ExcludeAvatarName.Length -gt 0) {
    $excludedNames = [System.Collections.Generic.HashSet[string]]::new(
        [string[]] $ExcludeAvatarName,
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $vrms = @($vrms | Where-Object { -not $excludedNames.Contains($_.BaseName) })
}
if ($Limit -gt 0) {
    $vrms = @($vrms | Select-Object -First $Limit)
}

New-Item -ItemType Directory -Path $StagingDirectory -Force | Out-Null
$logsDirectory = Join-Path $RepositoryRoot '.work\logs'
New-Item -ItemType Directory -Path $logsDirectory -Force | Out-Null

$pending = @()
$skipped = 0
foreach ($vrm in $vrms) {
    $expectedOutput = Join-Path $StagingDirectory ($vrm.BaseName + '.resonitepackage')
    if (-not $Force -and (Test-Path -LiteralPath $expectedOutput -PathType Leaf) -and (Get-Item -LiteralPath $expectedOutput).Length -gt 0) {
        $skipped++
        continue
    }
    $pending += $vrm
}

if ($pending.Count -eq 0) {
    Write-Host "Nothing to convert ($skipped existing packages skipped)."
    return
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$failedAvatars = @()
$failedBatches = @()
$previousNoPause = [System.Environment]::GetEnvironmentVariable('RESOPON_NOPAUSE', 'Process')
[System.Environment]::SetEnvironmentVariable('RESOPON_NOPAUSE', '1', 'Process')

$conversionGroups = @(
    [pscustomobject]@{
        Name = 'standard'
        PointFilterTextures = $false
        Vrms = @($pending | Where-Object { $_.Directory.Name -notlike '*_Voxel' })
    }
    [pscustomobject]@{
        Name = 'voxel'
        PointFilterTextures = $true
        Vrms = @($pending | Where-Object { $_.Directory.Name -like '*_Voxel' })
    }
) | Where-Object { $_.Vrms.Count -gt 0 }

$classifiedCount = ($conversionGroups | ForEach-Object { $_.Vrms.Count } | Measure-Object -Sum).Sum
if ($classifiedCount -ne $pending.Count) {
    throw "VRM classification failed. Pending: $($pending.Count), classified: $classifiedCount."
}

Write-Host ("Conversion groups: standard={0}, voxel={1}." -f
    @($pending | Where-Object { $_.Directory.Name -notlike '*_Voxel' }).Count,
    @($pending | Where-Object { $_.Directory.Name -like '*_Voxel' }).Count)

try {
    foreach ($group in $conversionGroups) {
        for ($offset = 0; $offset -lt $group.Vrms.Count; $offset += $BatchSize) {
            $lastIndex = [System.Math]::Min($offset + $BatchSize - 1, $group.Vrms.Count - 1)
            $batch = @($group.Vrms[$offset..$lastIndex])
            $batchNumber = [int] ($offset / $BatchSize) + 1
            $batchLog = Join-Path $logsDirectory ("resopon_{0}_{1}_batch{2:D3}.log" -f $timestamp, $group.Name, $batchNumber)

            if ($Force) {
                foreach ($vrm in $batch) {
                    $previousOutput = Join-Path $StagingDirectory ($vrm.BaseName + '.resonitepackage')
                    if (Test-Path -LiteralPath $previousOutput -PathType Leaf) {
                        Remove-Item -LiteralPath $previousOutput -Force
                    }
                }
            }

            $arguments = @($batch.FullName)
            $arguments += @(
                '--output', $StagingDirectory,
                '--no-protection',
                '--default-user-scale',
                '--no-avatar-loading-display',
                '--view-forward', '0.18',
                '--view-up', '0.1',
                '--near-clip', '0.14',
                '--import-timeout', '300'
            )
            if ($group.PointFilterTextures) {
                $arguments += '--point-filter-textures'
            }
            if (-not [string]::IsNullOrWhiteSpace($ResonitePath)) {
                $arguments += @('--resonite-path', [System.IO.Path]::GetFullPath($ResonitePath))
            }

            Write-Host ("Converting {0} batch {1}: {2} VRM(s)..." -f $group.Name, $batchNumber, $batch.Count)
            $previousErrorActionPreference = $ErrorActionPreference
            try {
                # Windows PowerShell wraps native stderr as ErrorRecord objects. ResoPon writes
                # engine diagnostics there even on success, so capture them as ordinary log text.
                $ErrorActionPreference = 'Continue'
                & $ResoPonPath @arguments 2>&1 |
                    ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_ } } |
                    Tee-Object -FilePath $batchLog
                $exitCode = $LASTEXITCODE
            }
            finally {
                $ErrorActionPreference = $previousErrorActionPreference
            }

            $missingOutputs = @()
            foreach ($vrm in $batch) {
                $outputPath = Join-Path $StagingDirectory ($vrm.BaseName + '.resonitepackage')
                if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf) -or (Get-Item -LiteralPath $outputPath).Length -eq 0) {
                    $missingOutputs += $vrm.BaseName
                }
            }

            if ($exitCode -ne 0 -or $missingOutputs.Count -gt 0) {
                $failureMessage = "ResoPon $($group.Name) batch $batchNumber failed (exit $exitCode). Missing outputs: $($missingOutputs -join ', '). Log: $batchLog"
                if (-not $ContinueOnError) {
                    throw $failureMessage
                }
                $failedBatches += "$($group.Name)/$batchNumber (exit $exitCode)"
                $failedAvatars += $missingOutputs
                Write-Warning $failureMessage
            }
        }
    }
}
finally {
    [System.Environment]::SetEnvironmentVariable('RESOPON_NOPAUSE', $previousNoPause, 'Process')
}

if ($failedBatches.Count -gt 0) {
    throw "ResoPon conversion finished with failed batches: $($failedBatches -join ', '). Missing avatars: $($failedAvatars -join ', ')"
}

Write-Host ("ResoPon conversion complete: {0} converted, {1} skipped." -f $pending.Count, $skipped)
