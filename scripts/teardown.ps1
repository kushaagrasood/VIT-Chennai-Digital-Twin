# ==============================================================================
# VIT Chennai Campus AI Digital Twin - AWS Infrastructure Teardown & Resource Deallocation
# ==============================================================================
# Course: Cloud Architecture Design (CAD)
# Target AWS Account: 672791231004
# Target AWS Region:  ap-south-1 (Mumbai)
# AWS CLI Profile:    vit-deploy
#
# Usage (Interactive confirmation prompt, preserves S3 bucket):
#   .\scripts\teardown.ps1
#
# Usage (Dry-run simulation - Zero AWS mutations, outputs configured plan):
#   .\scripts\teardown.ps1 -DryRun
#
# Usage (Force deallocation without confirmation prompt):
#   .\scripts\teardown.ps1 -Force
#
# Usage (Deallocate and empty S3 bucket objects & versions, but preserve bucket):
#   .\scripts\teardown.ps1 -S3Action Empty -Force
#
# Usage (Deallocate everything including CloudFront, S3 bucket & all objects):
#   .\scripts\teardown.ps1 -S3Action Delete -Force
#
# Usage (Preserve CloudFront & OAC, deallocate serverless backend & IoT):
#   .\scripts\teardown.ps1 -CloudFrontAction Preserve -Force
# ==============================================================================

[CmdletBinding()]
param (
    [string]$Region = $(if ($env:AWS_REGION -and $env:AWS_REGION.Trim() -ne "") { $env:AWS_REGION.Trim() } else { "ap-south-1" }),
    [string]$Profile = $(if ($env:AWS_PROFILE -and $env:AWS_PROFILE.Trim() -ne "") { $env:AWS_PROFILE.Trim() } else { "vit-deploy" }),
    [string]$ExpectedAccount = "672791231004",
    [string]$DistributionId = "E2NGCY20SE2WWQ",
    [string]$OacId = "E1JUXBAG645J5A",
    [string]$Bucket = "vit-chennai-digital-twin-672791231004",
    [ValidateSet("Preserve", "Empty", "Delete")]
    [string]$S3Action = "Preserve",
    [switch]$EmptyS3,
    [switch]$DeleteS3,
    [ValidateSet("Delete", "Preserve")]
    [string]$CloudFrontAction = "Delete",
    [switch]$DeleteCloudFront,
    [switch]$SkipCloudFront,
    [string]$TableName = "vit-campus-telemetry",
    [string]$LambdaName = "vit-telemetry-handler",
    [string]$RoleName = "vit-telemetry-lambda-role",
    [string]$ApiName = "vit-telemetry-api",
    [string]$ThingName = "vit-campus-auditorium-sensor-01",
    [string]$PolicyName = "vit-campus-sensor-policy",
    [string]$RuleName = "vit_campus_telemetry_rule",
    [string]$DashboardName = "vit-campus-digital-twin-dashboard",
    [switch]$Force,
    [switch]$DryRun,
    [switch]$OfflineTest,
    [switch]$ResetLocalConfig
)

$ErrorActionPreference = "Stop"

# Parameter normalization & resolution
$Profile = if ($Profile -and $Profile.Trim() -ne "") { $Profile.Trim() } else { "vit-deploy" }
$Region = if ($Region -and $Region.Trim() -ne "") { $Region.Trim() } else { "ap-south-1" }
$ExpectedAccount = if ($ExpectedAccount -and $ExpectedAccount.Trim() -ne "") { $ExpectedAccount.Trim() } else { "672791231004" }
$DistributionId = if ($DistributionId -and $DistributionId.Trim() -ne "") { $DistributionId.Trim() } else { "E2NGCY20SE2WWQ" }
$OacId = if ($OacId -and $OacId.Trim() -ne "") { $OacId.Trim() } else { "E1JUXBAG645J5A" }
$Bucket = if ($Bucket -and $Bucket.Trim() -ne "") { $Bucket.Trim() } else { "vit-chennai-digital-twin-672791231004" }
$TableName = if ($TableName -and $TableName.Trim() -ne "") { $TableName.Trim() } else { "vit-campus-telemetry" }
$LambdaName = if ($LambdaName -and $LambdaName.Trim() -ne "") { $LambdaName.Trim() } else { "vit-telemetry-handler" }
$RoleName = if ($RoleName -and $RoleName.Trim() -ne "") { $RoleName.Trim() } else { "vit-telemetry-lambda-role" }
$ApiName = if ($ApiName -and $ApiName.Trim() -ne "") { $ApiName.Trim() } else { "vit-telemetry-api" }
$ThingName = if ($ThingName -and $ThingName.Trim() -ne "") { $ThingName.Trim() } else { "vit-campus-auditorium-sensor-01" }
$PolicyName = if ($PolicyName -and $PolicyName.Trim() -ne "") { $PolicyName.Trim() } else { "vit-campus-sensor-policy" }
$RuleName = if ($RuleName -and $RuleName.Trim() -ne "") { $RuleName.Trim() } else { "vit_campus_telemetry_rule" }
$DashboardName = if ($DashboardName -and $DashboardName.Trim() -ne "") { $DashboardName.Trim() } else { "vit-campus-digital-twin-dashboard" }

if ($EmptyS3) { $S3Action = "Empty" }
if ($DeleteS3) { $S3Action = "Delete" }
if ($SkipCloudFront) { $CloudFrontAction = "Preserve" }
if ($DeleteCloudFront) { $CloudFrontAction = "Delete" }
$isDryRun = $DryRun -or $OfflineTest

# Helper to execute native commands safely without triggering PowerShell NativeCommandError on stderr
function Invoke-Native {
    param([scriptblock]$Script)
    $prev = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & $Script
    } finally {
        $ErrorActionPreference = $prev
    }
}

# Results ledger supporting live and dry-run reporting
# Strict rule: during a dry run, no resource is ever marked DELETED; only WOULD_DELETE, WOULD_PRESERVE, WOULD_SKIP, or NOT_FOUND.
$script:results = @()
function Record-Result {
    param(
        [Parameter(Mandatory=$true)] [string]$Resource,
        [Parameter(Mandatory=$true)] [string]$Type,
        [Parameter(Mandatory=$true)] [ValidateSet("DELETED", "NOT_FOUND", "SKIPPED", "FAILED", "PENDING", "WOULD_DELETE", "WOULD_PRESERVE", "WOULD_SKIP")] [string]$Status,
        [Parameter(Mandatory=$true)] [string]$Details
    )
    $script:results += [PSCustomObject]@{
        Resource = $Resource
        Type     = $Type
        Status   = $Status
        Details  = $Details
    }
}

Write-Host "==============================================================================" -ForegroundColor Red
Write-Host "VIT CHENNAI CAMPUS AI DIGITAL TWIN - AWS RESOURCE TEARDOWN" -ForegroundColor Red
Write-Host "Target AWS Account: $ExpectedAccount" -ForegroundColor White
Write-Host "Target AWS Region:  $Region" -ForegroundColor White
Write-Host "AWS CLI Profile:    $Profile" -ForegroundColor White
Write-Host "CloudFront Action:  $CloudFrontAction" -ForegroundColor White
Write-Host "S3 Bucket Action:   $S3Action" -ForegroundColor White
if ($isDryRun) {
    Write-Host "EXECUTION MODE:     DRY-RUN AUDIT SIMULATION (CONFIGURED DELETION PLAN)" -ForegroundColor Green
    Write-Host "NOTE: Zero AWS mutations are performed in dry-run mode. Live resource presence and account" -ForegroundColor DarkGray
    Write-Host "ownership have NOT been queried against live endpoints; this reflects the configured plan." -ForegroundColor DarkGray
} else {
    Write-Host "EXECUTION MODE:     LIVE AWS RESOURCE MUTATION" -ForegroundColor Yellow
}
Write-Host "==============================================================================" -ForegroundColor Red

# Step 0: Verification of Caller Identity, Target Account & Region
if ($isDryRun) {
    Write-Host "`n[DryRun] Live AWS credentials check bypassed. Displaying configured deletion plan." -ForegroundColor Green
    $callerAccount = $ExpectedAccount
} else {
    Write-Host "`nVerifying AWS credentials for profile '$Profile'..." -ForegroundColor Yellow
    $callerRaw = Invoke-Native { aws sts get-caller-identity --profile $Profile --output json 2>&1 }
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($callerRaw)) {
        $errDetail = ($callerRaw | Out-String).Trim()
        Write-Error "Authentication failed for AWS CLI profile '$Profile':`n$errDetail`nPlease reauthenticate using 'aws login --profile $Profile' or 'aws configure'."
        exit 1
    }
    try {
        $callerObj = ($callerRaw | Out-String).Trim() | ConvertFrom-Json
    } catch {
        Write-Error "Failed to parse AWS STS caller identity response: $_"
        exit 1
    }
    $callerAccount = $callerObj.Account
    Write-Host "Authenticated as: $($callerObj.Arn)" -ForegroundColor Green

    if ($callerAccount -ne $ExpectedAccount) {
        Write-Error "Safety abort: Authenticated AWS account ($callerAccount) does not match expected target account ($ExpectedAccount)."
        exit 1
    }
    if ($Region -ne "ap-south-1") {
        Write-Error "Safety abort: Target region '$Region' does not match expected project region 'ap-south-1'."
        exit 1
    }
}

# Display Resources and Policy Intent
Write-Host "`nProposed Deallocation Plan:" -ForegroundColor Yellow
Write-Host "  1. CloudFront Distribution:    $DistributionId ($CloudFrontAction)" -ForegroundColor White
Write-Host "  2. Origin Access Control:      $OacId (Delete only if unreferenced across all distributions)" -ForegroundColor White
Write-Host "  3. S3 Bucket & Objects:        s3://$Bucket ($S3Action)" -ForegroundColor White
Write-Host "  4. CloudWatch Dashboard:       $DashboardName" -ForegroundColor White
Write-Host "  5. CloudWatch Alarms:          vit-telemetry-lambda-errors, vit-telemetry-lambda-throttles, vit-auditorium-high-occupancy" -ForegroundColor White
Write-Host "  6. CloudWatch Metric Filter:   vit-high-occupancy-filter (/aws/lambda/$LambdaName)" -ForegroundColor White
Write-Host "  7. AWS IoT Topic Rule:         $RuleName (Disable before deletion)" -ForegroundColor White
Write-Host "  8. Lambda Trigger Permission:  vit-iot-rule-invoke" -ForegroundColor White
Write-Host "  9. AWS IoT Certificates:       Principals attached exclusively to $ThingName" -ForegroundColor White
Write-Host " 10. AWS IoT Policy:             $PolicyName" -ForegroundColor White
Write-Host " 11. AWS IoT Thing:              $ThingName" -ForegroundColor White
Write-Host " 12. Amazon API Gateway HTTP v2: $ApiName" -ForegroundColor White
Write-Host " 13. AWS Lambda Function:        $LambdaName" -ForegroundColor White
Write-Host " 14. CloudWatch Log Group:       /aws/lambda/$LambdaName" -ForegroundColor White
Write-Host " 15. IAM Execution Role:         $RoleName (inline policy vit-telemetry-access only)" -ForegroundColor White
Write-Host " 16. Amazon DynamoDB Table:      $TableName" -ForegroundColor White
Write-Host " 17. Local Files & Certs:        STRICTLY PRESERVED (certs/*, private keys, reports, source code)" -ForegroundColor Green

# Confirmation Gate
if (-not $Force -and -not $isDryRun) {
    Write-Host "`nWARNING: This action is permanent for selected resources." -ForegroundColor Red
    Write-Host "Local files and private keys will NOT be modified or deleted." -ForegroundColor Yellow
    $confirm = Read-Host "Type 'YES' to proceed with AWS resource deallocation"
    if ($confirm -ne "YES") {
        Write-Host "Teardown cancelled by user. No cloud resources were modified." -ForegroundColor Yellow
        exit 0
    }
}

# ==============================================================================
# PHASE 1: CLOUDFRONT DISTRIBUTION & ORIGIN ACCESS CONTROL (OAC)
# ==============================================================================
Write-Host "`n[1/15] Processing CloudFront Distribution '$DistributionId'..." -ForegroundColor Cyan
if ($CloudFrontAction -eq "Preserve") {
    Write-Host "  -> CloudFront distribution '$DistributionId' preserved (policy: Preserve)." -ForegroundColor DarkGray
    if ($isDryRun) {
        Record-Result $DistributionId "CloudFront Distribution" "WOULD_PRESERVE" "[DryRun] Preserved by configuration"
        Record-Result $OacId "Origin Access Control" "WOULD_PRESERVE" "[DryRun] Preserved because distribution is preserved"
    } else {
        Record-Result $DistributionId "CloudFront Distribution" "SKIPPED" "Preserved by configuration"
        Record-Result $OacId "Origin Access Control" "SKIPPED" "Preserved because distribution is preserved"
    }
} elseif ($isDryRun) {
    Record-Result $DistributionId "CloudFront Distribution" "WOULD_DELETE" "[DryRun] Would retrieve config, disable, wait deployed, and delete"
    Record-Result $OacId "Origin Access Control" "WOULD_DELETE" "[DryRun] Would inspect all paginated distributions and delete unreferenced OAC"
} else {
    # 1. Retrieve distribution configuration and ETag
    $distJson = Invoke-Native { aws cloudfront get-distribution-config --id $DistributionId --output json 2>&1 }
    $distJsonText = ($distJson | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        if ($distJsonText -match "NoSuchDistribution") {
            Write-Host "  -> CloudFront distribution '$DistributionId' not found." -ForegroundColor DarkGray
            Record-Result $DistributionId "CloudFront Distribution" "NOT_FOUND" "Distribution does not exist"
        } else {
            Write-Host "  -> Error accessing CloudFront distribution: $distJsonText" -ForegroundColor Red
            Record-Result $DistributionId "CloudFront Distribution" "FAILED" "Failed to get distribution: $distJsonText"
        }
    } else {
        $distObj = $distJsonText | ConvertFrom-Json
        $etag = $distObj.ETag
        $config = $distObj.DistributionConfig
        $canDelete = $false
        $discoveredOacIds = @()
        if ($config.Origins -and $config.Origins.Items) {
            foreach ($orig in $config.Origins.Items) {
                if ($orig.OriginAccessControlId -and $orig.OriginAccessControlId.Trim() -ne "") {
                    $discoveredOacIds += $orig.OriginAccessControlId.Trim()
                }
            }
        }

        # 2. Disable distribution if enabled
        if ($config.Enabled -eq $true) {
            Write-Host "  -> Distribution is currently Enabled. Disabling..." -ForegroundColor Yellow
            $config.Enabled = $false
            $tmpConfigFile = Join-Path $env:TEMP "cf-disable-$DistributionId-$([Guid]::NewGuid().ToString('N')).json"
            try {
                $jsonConfig = $config | ConvertTo-Json -Depth 25
                $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
                [System.IO.File]::WriteAllText($tmpConfigFile, $jsonConfig, $utf8NoBom)
                $updateOut = Invoke-Native {
                    aws cloudfront update-distribution --id $DistributionId --if-match $etag --distribution-config "file://$tmpConfigFile" 2>&1
                }
            } finally {
                if (Test-Path $tmpConfigFile) {
                    Remove-Item $tmpConfigFile -Force -ErrorAction SilentlyContinue
                }
            }

            if ($LASTEXITCODE -ne 0) {
                $err = ($updateOut | Out-String).Trim()
                Write-Host "  -> Failed to disable distribution: $err" -ForegroundColor Red
                Record-Result $DistributionId "CloudFront Distribution" "FAILED" "Disable failed: $err"
            } else {
                Write-Host "  -> Distribution disabled successfully. Waiting for status 'Deployed' (takes 2-5 minutes)..." -ForegroundColor Yellow
                $deployed = $false
                $elapsed = 0
                while ($elapsed -lt 900) {
                    Start-Sleep -Seconds 15
                    $elapsed += 15
                    $statusCheck = (Invoke-Native {
                        aws cloudfront get-distribution --id $DistributionId --query "Distribution.Status" --output text 2>$null
                    } | Out-String).Trim()
                    Write-Host "  -> Status: $statusCheck (${elapsed}s elapsed)" -ForegroundColor DarkGray
                    if ($statusCheck -eq "Deployed") {
                        $deployed = $true
                        break
                    }
                }
                if ($deployed) {
                    $canDelete = $true
                } else {
                    Record-Result $DistributionId "CloudFront Distribution" "PENDING" "Timed out waiting for status 'Deployed'"
                }
            }
        } else {
            Write-Host "  -> Distribution is already Disabled. Verifying status is 'Deployed'..." -ForegroundColor DarkGray
            $currentStatus = (Invoke-Native {
                aws cloudfront get-distribution --id $DistributionId --query "Distribution.Status" --output text 2>$null
            } | Out-String).Trim()
            if ($currentStatus -eq "Deployed") {
                $canDelete = $true
            } else {
                Write-Host "  -> Waiting for status to become 'Deployed'..." -ForegroundColor Yellow
                $deployed = $false
                $elapsed = 0
                while ($elapsed -lt 900) {
                    Start-Sleep -Seconds 15
                    $elapsed += 15
                    $statusCheck = (Invoke-Native {
                        aws cloudfront get-distribution --id $DistributionId --query "Distribution.Status" --output text 2>$null
                    } | Out-String).Trim()
                    Write-Host "  -> Status: $statusCheck (${elapsed}s elapsed)" -ForegroundColor DarkGray
                    if ($statusCheck -eq "Deployed") {
                        $deployed = $true
                        break
                    }
                }
                if ($deployed) { $canDelete = $true } else {
                    Record-Result $DistributionId "CloudFront Distribution" "PENDING" "Status InProgress, awaiting Deployed"
                }
            }
        }

        # 3. Retrieve updated ETag and delete
        if ($canDelete) {
            $updJson = Invoke-Native { aws cloudfront get-distribution-config --id $DistributionId --output json 2>&1 }
            if ($LASTEXITCODE -eq 0) {
                $updObj = ($updJson | Out-String).Trim() | ConvertFrom-Json
                $delEtag = $updObj.ETag
                Write-Host "  -> Deleting CloudFront distribution '$DistributionId'..." -ForegroundColor Yellow
                $delOut = Invoke-Native {
                    aws cloudfront delete-distribution --id $DistributionId --if-match $delEtag 2>&1
                }
                if ($LASTEXITCODE -eq 0) {
                    # 4. Strict post-deletion verification
                    $vOut = Invoke-Native { aws cloudfront get-distribution --id $DistributionId 2>&1 }
                    $vOutText = ($vOut | Out-String).Trim()
                    if ($vOutText -match "NoSuchDistribution") {
                        Write-Host "  -> CloudFront distribution '$DistributionId' deleted and disappearance verified." -ForegroundColor Green
                        Record-Result $DistributionId "CloudFront Distribution" "DELETED" "Disabled, deleted, and confirmed absent"
                    } elseif ($LASTEXITCODE -eq 0) {
                        Record-Result $DistributionId "CloudFront Distribution" "PENDING" "Deletion initiated; distribution still reported"
                    } else {
                        Record-Result $DistributionId "CloudFront Distribution" "FAILED" "Post-deletion verification failed: $vOutText"
                    }
                } else {
                    $err = ($delOut | Out-String).Trim()
                    Record-Result $DistributionId "CloudFront Distribution" "FAILED" "Delete failed: $err"
                }
            }
        }
    }

    # Process Origin Access Control (OAC) with full pagination
    $targetOacIds = @($OacId)
    if ($discoveredOacIds) { $targetOacIds += $discoveredOacIds }
    $targetOacIds = $targetOacIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    foreach ($currentOacId in $targetOacIds) {
        Write-Host "`n[2/15] Processing CloudFront Origin Access Control '$currentOacId'..." -ForegroundColor Cyan
        $oacInUse = $false
        $refDist = ""
        $distMarker = $null

        while ($true) {
            $params = @("cloudfront", "list-distributions", "--output", "json")
            if ($distMarker) { $params += @("--marker", $distMarker) }
            $listDistsOut = Invoke-Native { & aws @params 2>&1 }
            if ($LASTEXITCODE -ne 0) {
                $oacInUse = $true
                $refDist = "UNKNOWN (Failed to list distributions: $(($listDistsOut | Out-String).Trim()))"
                break
            }
            $distsObj = ($listDistsOut | Out-String).Trim() | ConvertFrom-Json
            if ($distsObj.DistributionList -and $distsObj.DistributionList.Items) {
                foreach ($d in $distsObj.DistributionList.Items) {
                    if ($d.Origins -and $d.Origins.Items) {
                        foreach ($orig in $d.Origins.Items) {
                            if ($orig.OriginAccessControlId -eq $currentOacId -or $orig.OriginAccessControlId -eq $OacId) {
                                $oacInUse = $true
                                $refDist = $d.Id
                                break
                            }
                        }
                    }
                    if ($oacInUse) { break }
                }
            }
            if ($oacInUse) { break }

            if ($distsObj.DistributionList -and $distsObj.DistributionList.IsTruncated -eq $true -and (-not [string]::IsNullOrWhiteSpace($distsObj.DistributionList.NextMarker))) {
                $distMarker = $distsObj.DistributionList.NextMarker
            } else {
                break
            }
        }

        if ($oacInUse) {
            Write-Host "  -> OAC '$currentOacId' is still referenced by distribution '$refDist'. Preserving." -ForegroundColor Yellow
            Record-Result $currentOacId "Origin Access Control" "SKIPPED" "Referenced by active distribution $refDist"
        } else {
            $oacJson = Invoke-Native { aws cloudfront get-origin-access-control --id $currentOacId --output json 2>&1 }
            $oacJsonText = ($oacJson | Out-String).Trim()
            if ($LASTEXITCODE -ne 0) {
                if ($oacJsonText -match "NoSuchOriginAccessControl") {
                    Write-Host "  -> OAC '$currentOacId' not found." -ForegroundColor DarkGray
                    Record-Result $currentOacId "Origin Access Control" "NOT_FOUND" "OAC does not exist"
                } else {
                    Record-Result $currentOacId "Origin Access Control" "FAILED" "Failed to get OAC: $oacJsonText"
                }
            } else {
                $oacObj = $oacJsonText | ConvertFrom-Json
                $oacEtag = $oacObj.ETag
                Write-Host "  -> Deleting unreferenced OAC '$currentOacId' using ETag '$oacEtag'..." -ForegroundColor Yellow
                $delOacOut = Invoke-Native {
                    aws cloudfront delete-origin-access-control --id $currentOacId --if-match $oacEtag 2>&1
                }
                if ($LASTEXITCODE -eq 0) {
                    # Strict post-deletion verification
                    $vOac = Invoke-Native { aws cloudfront get-origin-access-control --id $currentOacId 2>&1 }
                    $vOacText = ($vOac | Out-String).Trim()
                    if ($vOacText -match "NoSuchOriginAccessControl") {
                        Write-Host "  -> OAC '$currentOacId' deleted and disappearance verified." -ForegroundColor Green
                        Record-Result $currentOacId "Origin Access Control" "DELETED" "Unreferenced OAC confirmed absent"
                    } elseif ($LASTEXITCODE -eq 0) {
                        Record-Result $currentOacId "Origin Access Control" "PENDING" "Deletion initiated; OAC still reported"
                    } else {
                        Record-Result $currentOacId "Origin Access Control" "FAILED" "Post-deletion verification failed: $vOacText"
                    }
                } else {
                    $err = ($delOacOut | Out-String).Trim()
                    Record-Result $currentOacId "Origin Access Control" "FAILED" "Failed to delete OAC: $err"
                }
            }
        }
    }
}

# ==============================================================================
# PHASE 2: S3 BUCKET & VERSIONED OBJECT CLEANUP
# ==============================================================================
Write-Host "`n[3/15] Processing S3 Bucket 's3://$Bucket' ($S3Action)..." -ForegroundColor Cyan

function Empty-S3BucketAllVersions {
    param([string]$TargetBucket, [string]$TargetProfile, [string]$TargetRegion)
    Write-Host "  -> Purging all object versions and delete markers from 's3://$TargetBucket' (paginated service-level, max 1,000 per batch)..." -ForegroundColor DarkGray
    
    $keyMarker = $null
    $versionIdMarker = $null
    $totalPurged = 0

    while ($true) {
        # Service-level pagination using ListObjectVersions API parameters without client-side max-items limit
        $params = @(
            "s3api", "list-object-versions",
            "--bucket", $TargetBucket,
            "--profile", $TargetProfile,
            "--region", $TargetRegion,
            "--output", "json"
        )
        if ($keyMarker) { $params += @("--key-marker", $keyMarker) }
        if ($versionIdMarker) { $params += @("--version-id-marker", $versionIdMarker) }

        $verJson = Invoke-Native { & aws @params 2>&1 }
        if ($LASTEXITCODE -ne 0) {
            return @{ Success = $false; Error = ($verJson | Out-String).Trim() }
        }
        $verObj = ($verJson | Out-String).Trim() | ConvertFrom-Json
        $toDelete = @()
        if ($verObj.Versions) {
            foreach ($v in $verObj.Versions) {
                $toDelete += @{ Key = $v.Key; VersionId = $v.VersionId }
            }
        }
        if ($verObj.DeleteMarkers) {
            foreach ($dm in $verObj.DeleteMarkers) {
                $toDelete += @{ Key = $dm.Key; VersionId = $dm.VersionId }
            }
        }

        if ($toDelete.Count -gt 0) {
            # Chunk into batches of at most 1,000 objects (Amazon S3 delete-objects hard limit)
            for ($i = 0; $i -lt $toDelete.Count; $i += 1000) {
                $chunkSize = [Math]::Min(1000, $toDelete.Count - $i)
                $chunk = $toDelete[$i..($i + $chunkSize - 1)]

                $delPayload = @{ Objects = $chunk; Quiet = $false }
                $tmpDelFile = Join-Path $env:TEMP "s3-del-$([Guid]::NewGuid().ToString('N')).json"
                $delOut = $null
                try {
                    $jsonDel = $delPayload | ConvertTo-Json -Depth 5
                    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
                    [System.IO.File]::WriteAllText($tmpDelFile, $jsonDel, $utf8NoBom)
                    $delOut = Invoke-Native {
                        aws s3api delete-objects --bucket $TargetBucket --delete "file://$tmpDelFile" --profile $TargetProfile --region $TargetRegion 2>&1
                    }
                } finally {
                    if (Test-Path $tmpDelFile) {
                        Remove-Item $tmpDelFile -Force -ErrorAction SilentlyContinue
                    }
                }

                if ($LASTEXITCODE -ne 0) {
                    return @{ Success = $false; Error = ($delOut | Out-String).Trim() }
                }

                # Check response payload for individual object deletion errors
                try {
                    $delObj = ($delOut | Out-String).Trim() | ConvertFrom-Json
                    if ($delObj.Errors -and $delObj.Errors.Count -gt 0) {
                        $errDetails = ($delObj.Errors | ForEach-Object { "$($_.Key) ($($_.Code): $($_.Message))" }) -join "; "
                        return @{ Success = $false; Error = "delete-objects encountered $($delObj.Errors.Count) error(s): $errDetails" }
                    }
                } catch {
                    return @{ Success = $false; Error = "Failed to parse delete-objects response JSON: $_" }
                }

                $totalPurged += $chunkSize
            }
            Write-Host "  -> Purged $totalPurged versions/markers so far..." -ForegroundColor DarkGray
        }

        # Check service-level pagination flag
        if ($verObj.IsTruncated -eq $true) {
            $keyMarker = $verObj.NextKeyMarker
            $versionIdMarker = $verObj.NextVersionIdMarker
        } else {
            break
        }
    }

    # Additional purge of standard non-versioned objects
    Invoke-Native {
        aws s3 rm "s3://$TargetBucket/" --recursive --profile $TargetProfile --region $TargetRegion 2>$null
    } | Out-Null

    # Strict dual verification: both current objects AND versions/delete markers must be absent
    $checkV2 = Invoke-Native {
        aws s3api list-objects-v2 --bucket $TargetBucket --max-keys 1 --profile $TargetProfile --region $TargetRegion --output json 2>&1
    }
    if ($LASTEXITCODE -ne 0) {
        return @{ Success = $false; Error = "Failed to verify object absence: $(($checkV2 | Out-String).Trim())" }
    }
    $v2Obj = ($checkV2 | Out-String).Trim() | ConvertFrom-Json
    if ($v2Obj.KeyCount -gt 0) {
        return @{ Success = $false; Error = "Bucket still contains $($v2Obj.KeyCount) current object(s)." }
    }

    $finalVerCheck = Invoke-Native {
        aws s3api list-object-versions --bucket $TargetBucket --profile $TargetProfile --region $TargetRegion --output json 2>&1
    }
    if ($LASTEXITCODE -ne 0) {
        return @{ Success = $false; Error = "Failed to verify version absence: $(($finalVerCheck | Out-String).Trim())" }
    }
    $fvObj = ($finalVerCheck | Out-String).Trim() | ConvertFrom-Json
    $remainingVers = if ($fvObj.Versions) { $fvObj.Versions.Count } else { 0 }
    $remainingDms = if ($fvObj.DeleteMarkers) { $fvObj.DeleteMarkers.Count } else { 0 }
    if ($remainingVers -gt 0 -or $remainingDms -gt 0) {
        return @{ Success = $false; Error = "Bucket still contains $remainingVers version(s) and $remainingDms delete marker(s)." }
    }

    return @{ Success = $true; Error = $null }
}

if ($S3Action -eq "Preserve") {
    Write-Host "  -> S3 bucket 's3://$Bucket' and objects preserved (policy: Preserve)." -ForegroundColor DarkGray
    if ($isDryRun) {
        Record-Result "s3://$Bucket" "S3 Bucket" "WOULD_PRESERVE" "[DryRun] Preserved by configuration"
    } else {
        Record-Result "s3://$Bucket" "S3 Bucket" "SKIPPED" "Preserved by configuration"
    }
} elseif ($isDryRun) {
    if ($S3Action -eq "Empty") {
        Record-Result "s3://$Bucket (Objects)" "S3 Objects" "WOULD_DELETE" "[DryRun] Would purge all versions/delete markers (service-level pagination, batches <= 1000)"
        Record-Result "s3://$Bucket (Bucket)" "S3 Bucket" "WOULD_PRESERVE" "[DryRun] Bucket would be preserved"
    } else {
        Record-Result "s3://$Bucket" "S3 Bucket" "WOULD_DELETE" "[DryRun] Would purge all objects/versions and delete bucket"
    }
} else {
    $headOut = Invoke-Native { aws s3api head-bucket --bucket $Bucket --profile $Profile 2>&1 }
    $headOutText = ($headOut | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        if ($headOutText -match "404|NoSuchBucket|NotFound") {
            Write-Host "  -> S3 bucket 's3://$Bucket' not found." -ForegroundColor DarkGray
            Record-Result "s3://$Bucket" "S3 Bucket" "NOT_FOUND" "Bucket does not exist"
        } else {
            Write-Host "  -> Error accessing S3 bucket: $headOutText" -ForegroundColor Red
            Record-Result "s3://$Bucket" "S3 Bucket" "FAILED" "Failed to head bucket: $headOutText"
        }
    } else {
        $emptyRes = Empty-S3BucketAllVersions -TargetBucket $Bucket -TargetProfile $Profile -TargetRegion $Region
        if (-not $emptyRes.Success) {
            Write-Host "  -> Failed to empty S3 bucket: $($emptyRes.Error)" -ForegroundColor Red
            Record-Result "s3://$Bucket" "S3 Objects" "FAILED" "Failed to empty objects: $($emptyRes.Error)"
        } else {
            Write-Host "  -> All objects, versions, and delete markers purged." -ForegroundColor Green
            if ($S3Action -eq "Empty") {
                Record-Result "s3://$Bucket (Objects)" "S3 Objects" "DELETED" "All objects and versions purged"
                Record-Result "s3://$Bucket (Bucket)" "S3 Bucket" "SKIPPED" "Bucket preserved by configuration"
            } elseif ($S3Action -eq "Delete") {
                Write-Host "  -> Deleting empty S3 bucket 's3://$Bucket'..." -ForegroundColor Yellow
                $delBucketOut = Invoke-Native {
                    aws s3api delete-bucket --bucket $Bucket --region $Region --profile $Profile 2>&1
                }
                if ($LASTEXITCODE -eq 0) {
                    # Strict post-deletion verification
                    $vBucket = Invoke-Native { aws s3api head-bucket --bucket $Bucket --profile $Profile 2>&1 }
                    $vBucketText = ($vBucket | Out-String).Trim()
                    if ($vBucketText -match "404|NoSuchBucket|NotFound") {
                        Write-Host "  -> S3 bucket 's3://$Bucket' deleted and disappearance verified." -ForegroundColor Green
                        Record-Result "s3://$Bucket" "S3 Bucket" "DELETED" "Bucket deleted and confirmed absent"
                    } elseif ($LASTEXITCODE -eq 0) {
                        Record-Result "s3://$Bucket" "S3 Bucket" "PENDING" "Deletion issued; bucket still reported"
                    } else {
                        Record-Result "s3://$Bucket" "S3 Bucket" "FAILED" "Post-deletion verification failed: $vBucketText"
                    }
                } else {
                    $err = ($delBucketOut | Out-String).Trim()
                    Record-Result "s3://$Bucket" "S3 Bucket" "FAILED" "Failed to delete bucket: $err"
                }
            }
        }
    }
}

# ==============================================================================
# PHASE 3: CLOUDWATCH OBSERVABILITY (DASHBOARDS, ALARMS, METRIC FILTERS)
# ==============================================================================
Write-Host "`n[4/15] Deallocating CloudWatch Dashboard '$DashboardName'..." -ForegroundColor Cyan
if ($isDryRun) {
    Record-Result $DashboardName "CloudWatch Dashboard" "WOULD_DELETE" "[DryRun] Would delete dashboard"
} else {
    $dashCheck = Invoke-Native { aws cloudwatch get-dashboard --dashboard-name $DashboardName --region $Region --profile $Profile 2>&1 }
    $dashCheckText = ($dashCheck | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        if ($dashCheckText -match "ResourceNotFound") {
            Record-Result $DashboardName "CloudWatch Dashboard" "NOT_FOUND" "Dashboard does not exist"
        } else {
            Record-Result $DashboardName "CloudWatch Dashboard" "FAILED" "Failed to inspect dashboard: $dashCheckText"
        }
    } else {
        $delDashOut = Invoke-Native {
            aws cloudwatch delete-dashboards --dashboard-names $DashboardName --region $Region --profile $Profile 2>&1
        }
        if ($LASTEXITCODE -eq 0) {
            # Strict post-deletion verification
            $vDash = Invoke-Native { aws cloudwatch get-dashboard --dashboard-name $DashboardName --region $Region --profile $Profile 2>&1 }
            $vDashText = ($vDash | Out-String).Trim()
            if ($vDashText -match "ResourceNotFound") {
                Write-Host "  -> CloudWatch Dashboard '$DashboardName' deleted and disappearance verified." -ForegroundColor Green
                Record-Result $DashboardName "CloudWatch Dashboard" "DELETED" "Confirmed absent"
            } elseif ($LASTEXITCODE -eq 0) {
                Record-Result $DashboardName "CloudWatch Dashboard" "PENDING" "Dashboard still present"
            } else {
                Record-Result $DashboardName "CloudWatch Dashboard" "FAILED" "Post-deletion verification failed: $vDashText"
            }
        } else {
            $err = ($delDashOut | Out-String).Trim()
            Record-Result $DashboardName "CloudWatch Dashboard" "FAILED" "Failed to delete dashboard: $err"
        }
    }
}

Write-Host "`n[5/15] Deallocating CloudWatch Metric Alarms..." -ForegroundColor Cyan
$alarmsToDelete = @("vit-telemetry-lambda-errors", "vit-telemetry-lambda-throttles", "vit-auditorium-high-occupancy")
if ($isDryRun) {
    Record-Result ($alarmsToDelete -join ", ") "CloudWatch Alarms" "WOULD_DELETE" "[DryRun] Would delete 3 metric alarms"
} else {
    $existingAlarmsOut = Invoke-Native {
        aws cloudwatch describe-alarms --alarm-names $alarmsToDelete --region $Region --profile $Profile --output json 2>&1
    }
    $foundAlarms = @()
    if ($LASTEXITCODE -eq 0) {
        try {
            $alarmObj = ($existingAlarmsOut | Out-String).Trim() | ConvertFrom-Json
            $foundAlarms = $alarmObj.MetricAlarms | ForEach-Object { $_.AlarmName }
        } catch { }
    }

    if ($foundAlarms.Count -eq 0) {
        Write-Host "  -> None of the project CloudWatch alarms were found." -ForegroundColor DarkGray
        Record-Result ($alarmsToDelete -join ", ") "CloudWatch Alarms" "NOT_FOUND" "Alarms not found"
    } else {
        Write-Host "  -> Deleting alarms: $($foundAlarms -join ', ')..." -ForegroundColor Yellow
        $delAlarmsOut = Invoke-Native {
            aws cloudwatch delete-alarms --alarm-names $foundAlarms --region $Region --profile $Profile 2>&1
        }
        if ($LASTEXITCODE -eq 0) {
            # Strict post-deletion verification
            $vAlarms = Invoke-Native {
                aws cloudwatch describe-alarms --alarm-names $foundAlarms --region $Region --profile $Profile --output json 2>&1
            }
            $remaining = @()
            if ($LASTEXITCODE -eq 0) {
                try { $remaining = (($vAlarms | Out-String).Trim() | ConvertFrom-Json).MetricAlarms } catch { }
            }
            if ($LASTEXITCODE -eq 0 -and $remaining.Count -eq 0) {
                Write-Host "  -> CloudWatch alarms deleted and disappearance verified." -ForegroundColor Green
                Record-Result ($foundAlarms -join ", ") "CloudWatch Alarms" "DELETED" "Alarms confirmed absent"
            } elseif ($LASTEXITCODE -eq 0) {
                Record-Result ($foundAlarms -join ", ") "CloudWatch Alarms" "PENDING" "$($remaining.Count) alarms still reported"
            } else {
                Record-Result ($foundAlarms -join ", ") "CloudWatch Alarms" "FAILED" "Post-deletion verification failed: $(($vAlarms | Out-String).Trim())"
            }
        } else {
            $err = ($delAlarmsOut | Out-String).Trim()
            Record-Result ($foundAlarms -join ", ") "CloudWatch Alarms" "FAILED" "Failed to delete alarms: $err"
        }
    }
}

Write-Host "`n[6/15] Deallocating CloudWatch Metric Filter 'vit-high-occupancy-filter'..." -ForegroundColor Cyan
if ($isDryRun) {
    Record-Result "vit-high-occupancy-filter" "Metric Filter" "WOULD_DELETE" "[DryRun] Would delete metric filter"
} else {
    $mfCheck = Invoke-Native {
        aws logs describe-metric-filters --log-group-name "/aws/lambda/$LambdaName" --filter-name-prefix "vit-high-occupancy-filter" --region $Region --profile $Profile --output json 2>&1
    }
    $mfFound = $false
    if ($LASTEXITCODE -eq 0) {
        try {
            $mfs = (($mfCheck | Out-String).Trim() | ConvertFrom-Json).metricFilters
            if ($mfs | Where-Object { $_.filterName -eq "vit-high-occupancy-filter" }) {
                $mfFound = $true
            }
        } catch { }
    }

    if (-not $mfFound) {
        Write-Host "  -> Metric filter 'vit-high-occupancy-filter' not found." -ForegroundColor DarkGray
        Record-Result "vit-high-occupancy-filter" "Metric Filter" "NOT_FOUND" "Filter does not exist"
    } else {
        $delMfOut = Invoke-Native {
            aws logs delete-metric-filter --log-group-name "/aws/lambda/$LambdaName" `
              --filter-name "vit-high-occupancy-filter" --region $Region --profile $Profile 2>&1
        }
        if ($LASTEXITCODE -eq 0) {
            # Strict post-deletion verification
            $vMf = Invoke-Native {
                aws logs describe-metric-filters --log-group-name "/aws/lambda/$LambdaName" --filter-name-prefix "vit-high-occupancy-filter" --region $Region --profile $Profile --output json 2>&1
            }
            $vFound = $false
            if ($LASTEXITCODE -eq 0) {
                try {
                    $vmfs = (($vMf | Out-String).Trim() | ConvertFrom-Json).metricFilters
                    if ($vmfs | Where-Object { $_.filterName -eq "vit-high-occupancy-filter" }) { $vFound = $true }
                } catch { }
            }
            if ($LASTEXITCODE -eq 0 -and -not $vFound) {
                Write-Host "  -> Metric filter 'vit-high-occupancy-filter' deleted and disappearance verified." -ForegroundColor Green
                Record-Result "vit-high-occupancy-filter" "Metric Filter" "DELETED" "Filter confirmed absent"
            } elseif ($LASTEXITCODE -eq 0) {
                Record-Result "vit-high-occupancy-filter" "Metric Filter" "PENDING" "Filter still reported"
            } else {
                Record-Result "vit-high-occupancy-filter" "Metric Filter" "FAILED" "Post-deletion verification failed: $(($vMf | Out-String).Trim())"
            }
        } else {
            $err = ($delMfOut | Out-String).Trim()
            Record-Result "vit-high-occupancy-filter" "Metric Filter" "FAILED" "Failed to delete filter: $err"
        }
    }
}

# ==============================================================================
# PHASE 4: AWS IOT CORE INGESTION RESOURCES & CERTIFICATES
# ==============================================================================
Write-Host "`n[7/15] Deallocating AWS IoT Topic Rule '$RuleName'..." -ForegroundColor Cyan
if ($isDryRun) {
    Record-Result $RuleName "IoT Topic Rule" "WOULD_DELETE" "[DryRun] Would disable rule, delete, and verify specific ResourceNotFoundException"
} else {
    $ruleList = Invoke-Native { aws iot list-topic-rules --region $Region --profile $Profile --output json 2>&1 }
    $ruleExists = $false
    if ($LASTEXITCODE -eq 0) {
        try {
            $rules = (($ruleList | Out-String).Trim() | ConvertFrom-Json).rules
            if ($rules | Where-Object { $_.ruleName -eq $RuleName }) {
                $ruleExists = $true
            }
        } catch { }
    }

    if (-not $ruleExists) {
        Write-Host "  -> IoT Topic Rule '$RuleName' not found." -ForegroundColor DarkGray
        Record-Result $RuleName "IoT Topic Rule" "NOT_FOUND" "Topic rule does not exist"
    } else {
        # 1. Disable the topic rule before deletion
        Write-Host "  -> Disabling IoT topic rule '$RuleName'..." -ForegroundColor DarkGray
        Invoke-Native {
            aws iot disable-topic-rule --rule-name $RuleName --region $Region --profile $Profile 2>&1
        } | Out-Null

        # 2. Delete the topic rule
        Write-Host "  -> Deleting IoT topic rule '$RuleName'..." -ForegroundColor Yellow
        $delRuleOut = Invoke-Native { aws iot delete-topic-rule --rule-name $RuleName --region $Region --profile $Profile 2>&1 }
        if ($LASTEXITCODE -eq 0) {
            # 3. Strict post-deletion verification: only ResourceNotFoundException/NotFoundException proves absence
            $vRule = Invoke-Native { aws iot get-topic-rule --rule-name $RuleName --region $Region --profile $Profile 2>&1 }
            $vRuleText = ($vRule | Out-String).Trim()
            $ruleConfirmedAbsent = $false
            if ($vRuleText -match "ResourceNotFoundException|NotFoundException") {
                $ruleConfirmedAbsent = $true
            } elseif ($vRuleText -match "UnauthorizedException") {
                # In AWS IoT, get-topic-rule against a non-existent rule may return UnauthorizedException.
                # Conclusively verify absence via list-topic-rules:
                $vList = Invoke-Native { aws iot list-topic-rules --region $Region --profile $Profile --output json 2>&1 }
                if ($LASTEXITCODE -eq 0) {
                    try {
                        $vRules = (($vList | Out-String).Trim() | ConvertFrom-Json).rules
                        if (-not ($vRules | Where-Object { $_.ruleName -eq $RuleName })) {
                            $ruleConfirmedAbsent = $true
                        }
                    } catch { }
                }
            }

            if ($ruleConfirmedAbsent) {
                Write-Host "  -> IoT Topic Rule '$RuleName' disabled, deleted, and disappearance verified." -ForegroundColor Green
                Record-Result $RuleName "IoT Topic Rule" "DELETED" "Disabled, deleted, and confirmed absent"
            } elseif ($LASTEXITCODE -eq 0) {
                Write-Host "  -> IoT Topic Rule '$RuleName' is still reported by AWS." -ForegroundColor Yellow
                Record-Result $RuleName "IoT Topic Rule" "PENDING" "Deletion issued; rule still present"
            } else {
                Write-Host "  -> Verification query failed for IoT topic rule '$RuleName': $vRuleText" -ForegroundColor Red
                Record-Result $RuleName "IoT Topic Rule" "FAILED" "Post-deletion verification failed: $vRuleText"
            }
        } else {
            $err = ($delRuleOut | Out-String).Trim()
            Record-Result $RuleName "IoT Topic Rule" "FAILED" "Failed to delete topic rule: $err"
        }
    }
}

Write-Host "`n[8/15] Removing IoT invocation permission from Lambda '$LambdaName'..." -ForegroundColor Cyan
if ($isDryRun) {
    Record-Result "vit-iot-rule-invoke" "Lambda Permission" "WOULD_DELETE" "[DryRun] Would remove IoT invoke permission from Lambda"
} else {
    $permOut = Invoke-Native {
        aws lambda remove-permission --function-name $LambdaName `
          --statement-id "vit-iot-rule-invoke" --region $Region --profile $Profile 2>&1
    }
    if ($LASTEXITCODE -eq 0) {
        # Strict post-deletion verification
        $vPol = Invoke-Native { aws lambda get-policy --function-name $LambdaName --region $Region --profile $Profile 2>&1 }
        $vPolText = ($vPol | Out-String).Trim()
        $stmtAbsent = $false
        if ($vPolText -match "ResourceNotFoundException") {
            $stmtAbsent = $true
        } elseif ($LASTEXITCODE -eq 0) {
            try {
                $polDoc = ($vPolText | ConvertFrom-Json).Policy
                if (-not ($polDoc | Select-String -Pattern "vit-iot-rule-invoke")) { $stmtAbsent = $true }
            } catch { }
        }
        if ($stmtAbsent) {
            Write-Host "  -> Lambda permission 'vit-iot-rule-invoke' removed and verified." -ForegroundColor Green
            Record-Result "vit-iot-rule-invoke" "Lambda Permission" "DELETED" "Permission removed and confirmed absent"
        } else {
            Record-Result "vit-iot-rule-invoke" "Lambda Permission" "PENDING" "Statement still reported"
        }
    } else {
        $err = ($permOut | Out-String).Trim()
        if ($err -match "ResourceNotFoundException") {
            Record-Result "vit-iot-rule-invoke" "Lambda Permission" "NOT_FOUND" "Permission statement not found"
        } else {
            Record-Result "vit-iot-rule-invoke" "Lambda Permission" "FAILED" "Failed to remove permission: $err"
        }
    }
}

Write-Host "`n[9/15] Inspecting and deallocating IoT Certificates & Thing Principals..." -ForegroundColor Cyan
if ($isDryRun) {
    Record-Result "IoT Certificates & Principals" "IoT Certificate" "WOULD_DELETE" "[DryRun] Would inspect attachments, detach project policy & thing, deactivate and delete unshared certs"
} else {
    $thingDesc = Invoke-Native { aws iot describe-thing --thing-name $ThingName --region $Region --profile $Profile 2>&1 }
    $thingDescText = ($thingDesc | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        if ($thingDescText -match "ResourceNotFoundException") {
            Write-Host "  -> Thing '$ThingName' not found. Skipping principal discovery." -ForegroundColor DarkGray
            Record-Result "IoT Certificates" "IoT Certificate" "NOT_FOUND" "Thing does not exist"
        } else {
            Record-Result "IoT Certificates" "IoT Certificate" "FAILED" "Failed to inspect thing: $thingDescText"
        }
    } else {
        # Verify thing ownership
        try {
            $tObj = $thingDescText | ConvertFrom-Json
            if ($tObj.thingArn -and -not ($tObj.thingArn -match ":$ExpectedAccount:thing/$ThingName")) {
                Write-Error "Safety abort: Thing ARN ($($tObj.thingArn)) does not match expected account $ExpectedAccount."
                exit 1
            }
        } catch { }

        # Discover principals attached strictly to THIS thing
        $principalsJson = Invoke-Native {
            aws iot list-thing-principals --thing-name $ThingName --region $Region --profile $Profile --output json 2>&1
        }
        $principals = @()
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($principalsJson)) {
            try {
                $principals = (($principalsJson | Out-String).Trim() | ConvertFrom-Json).principals
            } catch { }
        }

        if ($principals.Count -eq 0) {
            Write-Host "  -> No active certificates or principals attached to '$ThingName'." -ForegroundColor DarkGray
            Record-Result "IoT Certificates" "IoT Certificate" "NOT_FOUND" "No principals attached to Thing"
        } else {
            foreach ($p in $principals) {
                Write-Host "  -> Inspecting attached principal: $p" -ForegroundColor DarkGray

                # Check and detach project policy safely
                $attachedPolJson = Invoke-Native {
                    aws iot list-attached-policies --target $p --region $Region --profile $Profile --output json 2>&1
                }
                $hasForeignPolicy = $false
                if ($LASTEXITCODE -eq 0) {
                    try {
                        $attachedPols = (($attachedPolJson | Out-String).Trim() | ConvertFrom-Json).policies
                        foreach ($pol in $attachedPols) {
                            if ($pol.policyName -eq $PolicyName) {
                                Write-Host "  -> Detaching policy '$($pol.policyName)' from principal..." -ForegroundColor DarkGray
                                Invoke-Native {
                                    aws iot detach-policy --policy-name $pol.policyName --target $p --region $Region --profile $Profile 2>$null
                                } | Out-Null
                            } else {
                                $hasForeignPolicy = $true
                                Write-Host "  -> Foreign policy '$($pol.policyName)' detected on principal. Preserving foreign attachment." -ForegroundColor Yellow
                            }
                        }
                    } catch { }
                }

                # Detach principal from Thing
                Write-Host "  -> Detaching principal from Thing '$ThingName'..." -ForegroundColor DarkGray
                Invoke-Native {
                    aws iot detach-thing-principal --thing-name $ThingName --principal $p --region $Region --profile $Profile 2>$null
                } | Out-Null

                # If principal is a certificate ARN, verify it is not attached to other things before deallocating
                if ($p -match 'cert/([a-f0-9]+)') {
                    $certId = $matches[1]
                    $otherThingsJson = Invoke-Native {
                        aws iot list-principal-things --principal $p --region $Region --profile $Profile --output json 2>&1
                    }
                    $otherThings = @()
                    if ($LASTEXITCODE -eq 0) {
                        try { $otherThings = (($otherThingsJson | Out-String).Trim() | ConvertFrom-Json).things } catch { }
                    }

                    if ($otherThings.Count -gt 0) {
                        Write-Host "  -> Certificate '$certId' is shared with other things ($($otherThings -join ', ')). Preserving." -ForegroundColor Yellow
                        Record-Result $certId "IoT Certificate" "SKIPPED" "Attached to other things: $($otherThings -join ', ')"
                    } elseif ($hasForeignPolicy) {
                        Write-Host "  -> Certificate '$certId' has non-project policies attached. Preserving." -ForegroundColor Yellow
                        Record-Result $certId "IoT Certificate" "SKIPPED" "Has non-project policies attached"
                    } else {
                        Write-Host "  -> Deactivating and deleting certificate '$certId'..." -ForegroundColor DarkGray
                        Invoke-Native {
                            aws iot update-certificate --certificate-id $certId --new-status INACTIVE --region $Region --profile $Profile 2>$null
                        } | Out-Null
                        $delCertOut = Invoke-Native {
                            aws iot delete-certificate --certificate-id $certId --region $Region --profile $Profile 2>&1
                        }
                        if ($LASTEXITCODE -eq 0) {
                            # Strict post-deletion verification
                            $vCert = Invoke-Native { aws iot describe-certificate --certificate-id $certId --region $Region --profile $Profile 2>&1 }
                            $vCertText = ($vCert | Out-String).Trim()
                            if ($vCertText -match "ResourceNotFoundException") {
                                Write-Host "  -> Certificate '$certId' deleted and disappearance verified." -ForegroundColor Green
                                Record-Result $certId "IoT Certificate" "DELETED" "Deactivated, deleted, and confirmed absent"
                            } elseif ($LASTEXITCODE -eq 0) {
                                Record-Result $certId "IoT Certificate" "PENDING" "Certificate still reported"
                            } else {
                                Record-Result $certId "IoT Certificate" "FAILED" "Post-deletion verification failed: $vCertText"
                            }
                        } else {
                            $err = ($delCertOut | Out-String).Trim()
                            Record-Result $certId "IoT Certificate" "FAILED" "Failed to delete certificate: $err"
                        }
                    }
                }
            }
        }
    }
}

Write-Host "`n[10/15] Deallocating AWS IoT Policy '$PolicyName'..." -ForegroundColor Cyan
if ($isDryRun) {
    Record-Result $PolicyName "IoT Policy" "WOULD_DELETE" "[DryRun] Would detach targets and delete policy"
} else {
    $polCheck = Invoke-Native { aws iot get-policy --policy-name $PolicyName --region $Region --profile $Profile 2>&1 }
    $polCheckText = ($polCheck | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        if ($polCheckText -match "ResourceNotFoundException") {
            Record-Result $PolicyName "IoT Policy" "NOT_FOUND" "Policy does not exist"
        } else {
            Record-Result $PolicyName "IoT Policy" "FAILED" "Failed to inspect policy: $polCheckText"
        }
    } else {
        # Detach remaining targets
        $targetsOut = Invoke-Native { aws iot list-targets-for-policy --policy-name $PolicyName --region $Region --profile $Profile --output json 2>&1 }
        if ($LASTEXITCODE -eq 0) {
            try {
                $targets = (($targetsOut | Out-String).Trim() | ConvertFrom-Json).targets
                foreach ($t in $targets) {
                    Write-Host "  -> Detaching policy '$PolicyName' from remaining target '$t'..." -ForegroundColor DarkGray
                    Invoke-Native { aws iot detach-policy --policy-name $PolicyName --target $t --region $Region --profile $Profile 2>$null } | Out-Null
                }
            } catch { }
        }
        $delPolOut = Invoke-Native { aws iot delete-policy --policy-name $PolicyName --region $Region --profile $Profile 2>&1 }
        if ($LASTEXITCODE -eq 0) {
            # Strict post-deletion verification
            $vPol = Invoke-Native { aws iot get-policy --policy-name $PolicyName --region $Region --profile $Profile 2>&1 }
            $vPolText = ($vPol | Out-String).Trim()
            if ($vPolText -match "ResourceNotFoundException") {
                Write-Host "  -> IoT Policy '$PolicyName' deleted and disappearance verified." -ForegroundColor Green
                Record-Result $PolicyName "IoT Policy" "DELETED" "Confirmed absent"
            } elseif ($LASTEXITCODE -eq 0) {
                Record-Result $PolicyName "IoT Policy" "PENDING" "Policy still reported"
            } else {
                Record-Result $PolicyName "IoT Policy" "FAILED" "Post-deletion verification failed: $vPolText"
            }
        } else {
            $err = ($delPolOut | Out-String).Trim()
            Record-Result $PolicyName "IoT Policy" "FAILED" "Failed to delete policy: $err"
        }
    }
}

Write-Host "`n[11/15] Deallocating AWS IoT Thing '$ThingName'..." -ForegroundColor Cyan
if ($isDryRun) {
    Record-Result $ThingName "IoT Thing" "WOULD_DELETE" "[DryRun] Would delete IoT thing and verify"
} else {
    $thingCheck = Invoke-Native { aws iot describe-thing --thing-name $ThingName --region $Region --profile $Profile 2>&1 }
    $thingCheckText = ($thingCheck | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        if ($thingCheckText -match "ResourceNotFoundException") {
            Record-Result $ThingName "IoT Thing" "NOT_FOUND" "Thing does not exist"
        } else {
            Record-Result $ThingName "IoT Thing" "FAILED" "Failed to inspect thing: $thingCheckText"
        }
    } else {
        $delThingOut = Invoke-Native { aws iot delete-thing --thing-name $ThingName --region $Region --profile $Profile 2>&1 }
        if ($LASTEXITCODE -eq 0) {
            # Strict post-deletion verification
            $vThing = Invoke-Native { aws iot describe-thing --thing-name $ThingName --region $Region --profile $Profile 2>&1 }
            $vThingText = ($vThing | Out-String).Trim()
            if ($vThingText -match "ResourceNotFoundException") {
                Write-Host "  -> IoT Thing '$ThingName' deleted and disappearance verified." -ForegroundColor Green
                Record-Result $ThingName "IoT Thing" "DELETED" "Confirmed absent"
            } elseif ($LASTEXITCODE -eq 0) {
                Record-Result $ThingName "IoT Thing" "PENDING" "Thing still reported"
            } else {
                Record-Result $ThingName "IoT Thing" "FAILED" "Post-deletion verification failed: $vThingText"
            }
        } else {
            $err = ($delThingOut | Out-String).Trim()
            Record-Result $ThingName "IoT Thing" "FAILED" "Failed to delete thing: $err"
        }
    }
}

# ==============================================================================
# PHASE 5: SERVERLESS API, COMPUTE, LOGS & ROLES
# ==============================================================================
Write-Host "`n[12/15] Deallocating Amazon API Gateway HTTP API v2 '$ApiName'..." -ForegroundColor Cyan
if ($isDryRun) {
    Record-Result $ApiName "API Gateway HTTP v2" "WOULD_DELETE" "[DryRun] Would delete API Gateway and verify"
} else {
    $apiListJson = Invoke-Native {
        aws apigatewayv2 get-apis --region $Region --profile $Profile --output json 2>&1
    }
    if ($LASTEXITCODE -ne 0) {
        $err = ($apiListJson | Out-String).Trim()
        Record-Result $ApiName "API Gateway HTTP v2" "FAILED" "Failed to list APIs: $err"
    } else {
        $matchingApis = @()
        try {
            $matchingApis = (($apiListJson | Out-String).Trim() | ConvertFrom-Json).Items | Where-Object { $_.Name -eq $ApiName }
        } catch { }

        if (-not $matchingApis -or $matchingApis.Count -eq 0) {
            Write-Host "  -> API Gateway '$ApiName' not found." -ForegroundColor DarkGray
            Record-Result $ApiName "API Gateway HTTP v2" "NOT_FOUND" "No matching API"
        } else {
            foreach ($api in $matchingApis) {
                $targetApiId = $api.ApiId
                Write-Host "  -> Deleting API Gateway '$ApiName' ($targetApiId)..." -ForegroundColor Yellow
                $delApiOut = Invoke-Native {
                    aws apigatewayv2 delete-api --api-id $targetApiId --region $Region --profile $Profile 2>&1
                }
                if ($LASTEXITCODE -eq 0) {
                    # Strict post-deletion verification
                    $vApi = Invoke-Native { aws apigatewayv2 get-api --api-id $targetApiId --region $Region --profile $Profile 2>&1 }
                    $vApiText = ($vApi | Out-String).Trim()
                    if ($vApiText -match "NotFoundException") {
                        Write-Host "  -> API Gateway '$ApiName' ($targetApiId) deleted and disappearance verified." -ForegroundColor Green
                        Record-Result "$ApiName ($targetApiId)" "API Gateway HTTP v2" "DELETED" "Confirmed absent"
                    } elseif ($LASTEXITCODE -eq 0) {
                        Record-Result "$ApiName ($targetApiId)" "API Gateway HTTP v2" "PENDING" "API still reported"
                    } else {
                        Record-Result "$ApiName ($targetApiId)" "API Gateway HTTP v2" "FAILED" "Post-deletion verification failed: $vApiText"
                    }
                } else {
                    $err = ($delApiOut | Out-String).Trim()
                    Record-Result "$ApiName ($targetApiId)" "API Gateway HTTP v2" "FAILED" "Failed to delete API: $err"
                }
            }
        }
    }
}

Write-Host "`n[13/15] Deallocating AWS Lambda Function '$LambdaName' & Log Group..." -ForegroundColor Cyan
if ($isDryRun) {
    Record-Result $LambdaName "Lambda Function" "WOULD_DELETE" "[DryRun] Would delete Lambda function and verify"
    Record-Result "/aws/lambda/$LambdaName" "CloudWatch Log Group" "WOULD_DELETE" "[DryRun] Would delete log group and verify"
} else {
    # 1. Lambda function
    $fnCheck = Invoke-Native { aws lambda get-function --function-name $LambdaName --region $Region --profile $Profile 2>&1 }
    $fnCheckText = ($fnCheck | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        if ($fnCheckText -match "ResourceNotFoundException") {
            Record-Result $LambdaName "Lambda Function" "NOT_FOUND" "Function does not exist"
        } else {
            Record-Result $LambdaName "Lambda Function" "FAILED" "Failed to check function: $fnCheckText"
        }
    } else {
        # Verify function ownership
        try {
            $fObj = $fnCheckText | ConvertFrom-Json
            if ($fObj.Configuration.FunctionArn -and -not ($fObj.Configuration.FunctionArn -match ":$ExpectedAccount:function:$LambdaName")) {
                Write-Error "Safety abort: Lambda ARN ($($fObj.Configuration.FunctionArn)) does not match expected account $ExpectedAccount."
                exit 1
            }
        } catch { }

        $delFnOut = Invoke-Native {
            aws lambda delete-function --function-name $LambdaName --region $Region --profile $Profile 2>&1
        }
        if ($LASTEXITCODE -eq 0) {
            # Strict post-deletion verification
            $vFn = Invoke-Native { aws lambda get-function --function-name $LambdaName --region $Region --profile $Profile 2>&1 }
            $vFnText = ($vFn | Out-String).Trim()
            if ($vFnText -match "ResourceNotFoundException") {
                Write-Host "  -> Lambda function '$LambdaName' deleted and disappearance verified." -ForegroundColor Green
                Record-Result $LambdaName "Lambda Function" "DELETED" "Confirmed absent"
            } elseif ($LASTEXITCODE -eq 0) {
                Record-Result $LambdaName "Lambda Function" "PENDING" "Function still reported"
            } else {
                Record-Result $LambdaName "Lambda Function" "FAILED" "Post-deletion verification failed: $vFnText"
            }
        } else {
            $err = ($delFnOut | Out-String).Trim()
            Record-Result $LambdaName "Lambda Function" "FAILED" "Failed to delete function: $err"
        }
    }

    # 2. CloudWatch Log Group
    $logGroupName = "/aws/lambda/$LambdaName"
    $lgCheck = Invoke-Native {
        aws logs describe-log-groups --log-group-name-prefix $logGroupName --region $Region --profile $Profile --output json 2>&1
    }
    $lgExists = $false
    if ($LASTEXITCODE -eq 0) {
        try {
            $lgs = (($lgCheck | Out-String).Trim() | ConvertFrom-Json).logGroups
            if ($lgs | Where-Object { $_.logGroupName -eq $logGroupName }) {
                $lgExists = $true
            }
        } catch { }
    }

    if (-not $lgExists) {
        Record-Result $logGroupName "CloudWatch Log Group" "NOT_FOUND" "Log group does not exist"
    } else {
        $delLgOut = Invoke-Native {
            aws logs delete-log-group --log-group-name $logGroupName --region $Region --profile $Profile 2>&1
        }
        if ($LASTEXITCODE -eq 0) {
            # Strict post-deletion verification
            $vLg = Invoke-Native {
                aws logs describe-log-groups --log-group-name-prefix $logGroupName --region $Region --profile $Profile --output json 2>&1
            }
            $vExists = $false
            if ($LASTEXITCODE -eq 0) {
                try {
                    $vlgs = (($vLg | Out-String).Trim() | ConvertFrom-Json).logGroups
                    if ($vlgs | Where-Object { $_.logGroupName -eq $logGroupName }) { $vExists = $true }
                } catch { }
            }
            if ($LASTEXITCODE -eq 0 -and -not $vExists) {
                Write-Host "  -> CloudWatch Log Group '$logGroupName' deleted and disappearance verified." -ForegroundColor Green
                Record-Result $logGroupName "CloudWatch Log Group" "DELETED" "Log group confirmed absent"
            } elseif ($LASTEXITCODE -eq 0) {
                Record-Result $logGroupName "CloudWatch Log Group" "PENDING" "Log group still reported"
            } else {
                Record-Result $logGroupName "CloudWatch Log Group" "FAILED" "Post-deletion verification failed: $(($vLg | Out-String).Trim())"
            }
        } else {
            $err = ($delLgOut | Out-String).Trim()
            Record-Result $logGroupName "CloudWatch Log Group" "FAILED" "Failed to delete log group: $err"
        }
    }
}

Write-Host "`n[14/15] Deallocating IAM Role '$RoleName'..." -ForegroundColor Cyan
if ($isDryRun) {
    Record-Result $RoleName "IAM Role" "WOULD_DELETE" "[DryRun] Would verify only project inline policy 'vit-telemetry-access' exists, delete it, and delete role"
} else {
    $roleCheck = Invoke-Native { aws iam get-role --role-name $RoleName --profile $Profile 2>&1 }
    $roleCheckText = ($roleCheck | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        if ($roleCheckText -match "NoSuchEntity") {
            Record-Result $RoleName "IAM Role" "NOT_FOUND" "Role does not exist"
        } else {
            Record-Result $RoleName "IAM Role" "FAILED" "Failed to inspect role: $roleCheckText"
        }
    } else {
        # Verify role ownership
        try {
            $rObj = $roleCheckText | ConvertFrom-Json
            if ($rObj.Role.Arn -and -not ($rObj.Role.Arn -match ":$ExpectedAccount:role/$RoleName")) {
                Write-Error "Safety abort: IAM Role ARN ($($rObj.Role.Arn)) does not match expected account $ExpectedAccount."
                exit 1
            }
        } catch { }

        # 1. Inspect inline policies: ONLY delete project-owned 'vit-telemetry-access'.
        # If any foreign/unrecognized inline policy exists, stop for safety.
        $inlinePolsOut = Invoke-Native {
            aws iam list-role-policies --role-name $RoleName --profile $Profile --output json 2>&1
        }
        $inlinePols = @()
        if ($LASTEXITCODE -eq 0) {
            try {
                $inlinePols = (($inlinePolsOut | Out-String).Trim() | ConvertFrom-Json).PolicyNames
            } catch { }
        }

        $canProceedRole = $true
        foreach ($pol in $inlinePols) {
            if ($pol -eq "vit-telemetry-access") {
                Write-Host "  -> Deleting project inline policy 'vit-telemetry-access' from role '$RoleName'..." -ForegroundColor DarkGray
                $delPolOut = Invoke-Native {
                    aws iam delete-role-policy --role-name $RoleName --policy-name $pol --profile $Profile 2>&1
                }
                if ($LASTEXITCODE -eq 0) {
                    Record-Result "$RoleName/$pol" "IAM Inline Policy" "DELETED" "Project inline policy deleted"
                } else {
                    $err = ($delPolOut | Out-String).Trim()
                    Record-Result "$RoleName/$pol" "IAM Inline Policy" "FAILED" "Failed to delete inline policy: $err"
                    $canProceedRole = $false
                }
            } else {
                Write-Warning "Foreign inline policy '$pol' detected on role '$RoleName'. Ownership ambiguous. Halting role deletion."
                Record-Result "$RoleName/$pol" "IAM Inline Policy" "SKIPPED" "Foreign inline policy preserved; ownership ambiguous"
                $canProceedRole = $false
            }
        }

        # 2. Inspect attached managed policies: the project attached ZERO managed policies.
        # If any managed policy is attached, do NOT detach or delete it; stop for safety.
        $attPolsOut = Invoke-Native {
            aws iam list-attached-role-policies --role-name $RoleName --profile $Profile --output json 2>&1
        }
        $attPols = @()
        if ($LASTEXITCODE -eq 0) {
            try {
                $attPols = (($attPolsOut | Out-String).Trim() | ConvertFrom-Json).AttachedPolicies
            } catch { }
        }

        if ($attPols.Count -gt 0) {
            $pNames = ($attPols | ForEach-Object { $_.PolicyName }) -join ", "
            Write-Warning "Foreign managed policy attachments ($pNames) detected on role '$RoleName'. Preserving attachments. Role will not be deleted."
            Record-Result $RoleName "IAM Role" "SKIPPED" "Preserved: Foreign managed policies attached ($pNames)"
            $canProceedRole = $false
        }

        # 3. Delete IAM Role strictly if verified clean of foreign policies
        if ($canProceedRole) {
            $delRoleOut = Invoke-Native { aws iam delete-role --role-name $RoleName --profile $Profile 2>&1 }
            if ($LASTEXITCODE -eq 0) {
                # Strict post-deletion verification
                $vRole = Invoke-Native { aws iam get-role --role-name $RoleName --profile $Profile 2>&1 }
                $vRoleText = ($vRole | Out-String).Trim()
                if ($vRoleText -match "NoSuchEntity") {
                    Write-Host "  -> IAM Role '$RoleName' deleted and disappearance verified." -ForegroundColor Green
                    Record-Result $RoleName "IAM Role" "DELETED" "Confirmed absent"
                } elseif ($LASTEXITCODE -eq 0) {
                    Record-Result $RoleName "IAM Role" "PENDING" "Role still reported"
                } else {
                    Record-Result $RoleName "IAM Role" "FAILED" "Post-deletion verification failed: $vRoleText"
                }
            } else {
                $err = ($delRoleOut | Out-String).Trim()
                Record-Result $RoleName "IAM Role" "FAILED" "Failed to delete role: $err"
            }
        }
    }
}

# ==============================================================================
# PHASE 6: PERSISTENCE LAYER (DYNAMODB TABLE)
# ==============================================================================
Write-Host "`n[15/15] Deallocating Amazon DynamoDB Table '$TableName'..." -ForegroundColor Cyan
if ($isDryRun) {
    Record-Result $TableName "DynamoDB Table" "WOULD_DELETE" "[DryRun] Would delete DynamoDB table and poll until specific ResourceNotFoundException"
} else {
    $descTable = Invoke-Native { aws dynamodb describe-table --table-name $TableName --region $Region --profile $Profile 2>&1 }
    $descTableText = ($descTable | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        if ($descTableText -match "ResourceNotFoundException") {
            Record-Result $TableName "DynamoDB Table" "NOT_FOUND" "Table does not exist"
        } else {
            Record-Result $TableName "DynamoDB Table" "FAILED" "Failed to inspect table: $descTableText"
        }
    } else {
        # Verify table ownership
        try {
            $tObj = $descTableText | ConvertFrom-Json
            if ($tObj.Table.TableArn -and -not ($tObj.Table.TableArn -match ":$ExpectedAccount:table/$TableName")) {
                Write-Error "Safety abort: DynamoDB Table ARN ($($tObj.Table.TableArn)) does not match expected account $ExpectedAccount."
                exit 1
            }
        } catch { }

        Write-Host "  -> Initiating deletion of DynamoDB table '$TableName'..." -ForegroundColor Yellow
        $delTableOut = Invoke-Native {
            aws dynamodb delete-table --table-name $TableName --region $Region --profile $Profile 2>&1
        }
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  -> Waiting for DynamoDB table '$TableName' deletion to complete and verify disappearance..." -ForegroundColor DarkGray
            $tblGone = $false
            $tblElapsed = 0
            $pollFailed = $false
            $lastPollErr = ""
            while ($tblElapsed -lt 180) {
                Start-Sleep -Seconds 5
                $tblElapsed += 5
                $chk = Invoke-Native { aws dynamodb describe-table --table-name $TableName --region $Region --profile $Profile 2>&1 }
                $chkText = ($chk | Out-String).Trim()
                if ($chkText -match "ResourceNotFoundException") {
                    $tblGone = $true
                    break
                } elseif ($LASTEXITCODE -ne 0) {
                    # Unexpected polling error (e.g. AccessDenied, Network timeout)
                    $pollFailed = $true
                    $lastPollErr = $chkText
                    break
                }
                Write-Host "  -> Table still terminating... (${tblElapsed}s elapsed)" -ForegroundColor DarkGray
            }
            if ($tblGone) {
                Write-Host "  -> DynamoDB table '$TableName' deleted and disappearance verified." -ForegroundColor Green
                Record-Result $TableName "DynamoDB Table" "DELETED" "Table confirmed absent via ResourceNotFoundException"
            } elseif ($pollFailed) {
                Record-Result $TableName "DynamoDB Table" "FAILED" "Post-deletion polling failed with unexpected error: $lastPollErr"
            } else {
                Record-Result $TableName "DynamoDB Table" "PENDING" "Deletion initiated; table still deallocating after 180s"
            }
        } else {
            $err = ($delTableOut | Out-String).Trim()
            Record-Result $TableName "DynamoDB Table" "FAILED" "Failed to delete table: $err"
        }
    }
}

# ==============================================================================
# LOCAL FILE INTEGRITY REPORT (STRICT PRESERVATION GUARANTEE)
# ==============================================================================
Write-Host "`nLocal File Preservation:" -ForegroundColor Cyan
Write-Host "  -> certs/ (private keys, certificates, metadata): PRESERVED" -ForegroundColor Green
Write-Host "  -> Source code, documentation, and reports:       PRESERVED" -ForegroundColor Green
if ($ResetLocalConfig) {
    if ($isDryRun) {
        Record-Result "public/config.json" "Local Config" "WOULD_DELETE" "[DryRun] Would reset apiUrl to empty string"
    } else {
        $configPath = Join-Path $PSScriptRoot "..\public\config.json"
        if (Test-Path $configPath) {
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($configPath, "{`n  `"apiUrl`": `"`"`n}`n", $utf8NoBom)
            Write-Host "  -> Reset public/config.json (-ResetLocalConfig specified)." -ForegroundColor Yellow
            Record-Result "public/config.json" "Local Config" "DELETED" "Reset apiUrl to empty string"
        }
    }
} else {
    Write-Host "  -> public/config.json:                           PRESERVED (use -ResetLocalConfig to reset)" -ForegroundColor DarkGray
}

# ==============================================================================
# SUMMARY TABLE & OUTCOME VALIDATION
# ==============================================================================
Write-Host "`n==============================================================================" -ForegroundColor Green
if ($isDryRun) {
    Write-Host "AWS INFRASTRUCTURE TEARDOWN - CONFIGURED DELETION PLAN (DRY-RUN)" -ForegroundColor Green
} else {
    Write-Host "AWS INFRASTRUCTURE TEARDOWN & DEALLOCATION SUMMARY" -ForegroundColor Green
}
Write-Host "==============================================================================" -ForegroundColor Green

$script:results | Format-Table -Property Resource, Type, Status, Details -AutoSize

if ($isDryRun) {
    $wouldDeleteCount   = @($script:results | Where-Object { $_.Status -eq "WOULD_DELETE" }).Count
    $wouldPreserveCount = @($script:results | Where-Object { $_.Status -eq "WOULD_PRESERVE" }).Count
    $wouldSkipCount     = @($script:results | Where-Object { $_.Status -eq "WOULD_SKIP" }).Count
    $notFoundCount      = @($script:results | Where-Object { $_.Status -eq "NOT_FOUND" }).Count

    Write-Host "Dry-Run Plan Breakdown: $wouldDeleteCount WOULD_DELETE | $wouldPreserveCount WOULD_PRESERVE | $wouldSkipCount WOULD_SKIP | $notFoundCount NOT_FOUND" -ForegroundColor Cyan
    Write-Host "`nDRY-RUN SIMULATION COMPLETE: Zero AWS mutations were performed." -ForegroundColor Green
    Write-Host "This output represents the configured deletion plan. No live AWS resources were queried, modified, or deleted." -ForegroundColor Green
    $global:LASTEXITCODE = 0
    exit 0
} else {
    $deletedCount  = @($script:results | Where-Object { $_.Status -eq "DELETED" }).Count
    $notFoundCount = @($script:results | Where-Object { $_.Status -eq "NOT_FOUND" }).Count
    $skippedCount  = @($script:results | Where-Object { $_.Status -eq "SKIPPED" }).Count
    $failedCount   = @($script:results | Where-Object { $_.Status -eq "FAILED" }).Count
    $pendingCount  = @($script:results | Where-Object { $_.Status -eq "PENDING" }).Count

    Write-Host "Live Result Breakdown: $deletedCount DELETED | $notFoundCount NOT_FOUND | $skippedCount SKIPPED | $failedCount FAILED | $pendingCount PENDING" -ForegroundColor Cyan

    if ($failedCount -gt 0) {
        Write-Host "`nTeardown encountered errors on $failedCount resource(s). Review the failure details above." -ForegroundColor Red
        $global:LASTEXITCODE = 1
        exit 1
    } elseif ($pendingCount -gt 0) {
        Write-Host "`nTeardown initiated. $pendingCount resource(s) are in PENDING state awaiting AWS propagation." -ForegroundColor Yellow
        $global:LASTEXITCODE = 0
        exit 0
    } elseif ($skippedCount -gt 0) {
        Write-Host "`nTeardown finished successfully. $skippedCount resource(s) were intentionally preserved as configured." -ForegroundColor Yellow
        $global:LASTEXITCODE = 0
        exit 0
    } else {
        Write-Host "`nTeardown verified complete! All targeted project cloud resources have been deallocated." -ForegroundColor Green
        $global:LASTEXITCODE = 0
        exit 0
    }
}
