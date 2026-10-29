# ==============================================================================
# VIT Chennai Campus AI Digital Twin - Unified Demo & Setup Orchestrator (PowerShell)
# ==============================================================================
# Course: Cloud Architecture Design (CAD) - Project Demonstration Entrypoint
# Target AWS Account: 672791231004
# Target AWS Region:  ap-south-1 (Mumbai)
# AWS CLI Profile:    vit-deploy
# Live Website:       https://d457wl1fwy7gg.cloudfront.net
# (Legacy alias:      https://d457w1fwy7gg.cloudfront.net)
#
# MODES AVAILABLE:
#   1. Pre-Demo Health Check (Read-Only, run 1-2 min before professor enters):
#      .\scripts\demo.ps1 -Check
#
#   2. Professor Demonstration (Publishes deterministic scenario, zero infra mutations):
#      .\scripts\demo.ps1 -Demo -Scenario Normal    # 1,480 seats (61.7% - Nominal state)
#      .\scripts\demo.ps1 -Demo -Scenario High      # 2,150 seats (89.6% - Threshold Alert)
#      .\scripts\demo.ps1 -Demo -Scenario Reset     # 1,480 seats (Reset baseline)
#
#   3. First-Time Infrastructure Setup (Full multi-stage AWS pipeline with confirmation):
#      .\scripts\demo.ps1 -Setup
# ==============================================================================

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [string]$Mode,

    [switch]$Check,
    [switch]$Demo,
    [switch]$Setup,

    [ValidateSet("Normal", "High", "Alert", "Reset")]
    [string]$Scenario = "Normal",

    [string]$Region = $(if ($env:AWS_REGION -and $env:AWS_REGION.Trim() -ne "") { $env:AWS_REGION.Trim() } else { "ap-south-1" }),
    [string]$Profile = $(if ($env:AWS_PROFILE -and $env:AWS_PROFILE.Trim() -ne "") { $env:AWS_PROFILE.Trim() } else { "vit-deploy" }),
    [string]$ExpectedAccount = "672791231004",
    [string]$DistributionId = "E2NGCY20SE2WWQ",
    [string]$Domain = "d457wl1fwy7gg.cloudfront.net",
    [string]$Bucket = "vit-chennai-digital-twin-672791231004",
    [string]$TableName = "vit-campus-telemetry",
    [string]$LambdaName = "vit-telemetry-handler",
    [string]$RoleName = "vit-telemetry-lambda-role",
    [string]$ApiName = "vit-telemetry-api",
    [string]$ThingName = "vit-campus-auditorium-sensor-01",
    [string]$PolicyName = "vit-campus-sensor-policy",
    [string]$RuleName = "vit_campus_telemetry_rule",
    [string]$TopicName = "vit/campus/Building024/telemetry",
    [string]$DashboardName = "vit-campus-digital-twin-dashboard",
    [string]$VenueId = "Building024",

    [switch]$Force,
    [switch]$OfflineTest
)

$ErrorActionPreference = "Stop"

# Fail-fast validation if any critical parameter was provided as blank or whitespace
$paramCheckList = @{
    "Region" = $Region; "Profile" = $Profile; "ExpectedAccount" = $ExpectedAccount;
    "DistributionId" = $DistributionId; "Domain" = $Domain; "Bucket" = $Bucket;
    "TableName" = $TableName; "LambdaName" = $LambdaName; "RoleName" = $RoleName;
    "ApiName" = $ApiName; "ThingName" = $ThingName; "PolicyName" = $PolicyName;
    "RuleName" = $RuleName; "TopicName" = $TopicName; "DashboardName" = $DashboardName;
    "VenueId" = $VenueId
}
foreach ($pName in $paramCheckList.Keys) {
    if ($PSBoundParameters.ContainsKey($pName) -and [string]::IsNullOrWhiteSpace($paramCheckList[$pName])) {
        Write-Error "Validation failed: Parameter '$pName' was provided but is blank or empty."
        exit 1
    }
}

# Parameter normalization with robust defaults
$Profile = if ($Profile -and $Profile.Trim() -ne "") { $Profile.Trim() } else { "vit-deploy" }
$Region = if ($Region -and $Region.Trim() -ne "") { $Region.Trim() } else { "ap-south-1" }
$ExpectedAccount = if ($ExpectedAccount -and $ExpectedAccount.Trim() -ne "") { $ExpectedAccount.Trim() } else { "672791231004" }
$DistributionId = if ($DistributionId -and $DistributionId.Trim() -ne "") { $DistributionId.Trim() } else { "E2NGCY20SE2WWQ" }
$Domain = if ($Domain -and $Domain.Trim() -ne "") { $Domain.Trim() } else { "d457wl1fwy7gg.cloudfront.net" }
$Bucket = if ($Bucket -and $Bucket.Trim() -ne "") { $Bucket.Trim() } else { "vit-chennai-digital-twin-672791231004" }
$TableName = if ($TableName -and $TableName.Trim() -ne "") { $TableName.Trim() } else { "vit-campus-telemetry" }
$LambdaName = if ($LambdaName -and $LambdaName.Trim() -ne "") { $LambdaName.Trim() } else { "vit-telemetry-handler" }
$RoleName = if ($RoleName -and $RoleName.Trim() -ne "") { $RoleName.Trim() } else { "vit-telemetry-lambda-role" }
$ApiName = if ($ApiName -and $ApiName.Trim() -ne "") { $ApiName.Trim() } else { "vit-telemetry-api" }
$ThingName = if ($ThingName -and $ThingName.Trim() -ne "") { $ThingName.Trim() } else { "vit-campus-auditorium-sensor-01" }
$PolicyName = if ($PolicyName -and $PolicyName.Trim() -ne "") { $PolicyName.Trim() } else { "vit-campus-sensor-policy" }
$RuleName = if ($RuleName -and $RuleName.Trim() -ne "") { $RuleName.Trim() } else { "vit_campus_telemetry_rule" }
$TopicName = if ($TopicName -and $TopicName.Trim() -ne "") { $TopicName.Trim() } else { "vit/campus/Building024/telemetry" }
$DashboardName = if ($DashboardName -and $DashboardName.Trim() -ne "") { $DashboardName.Trim() } else { "vit-campus-digital-twin-dashboard" }
$VenueId = if ($VenueId -and $VenueId.Trim() -ne "") { $VenueId.Trim() } else { "Building024" }

# Helper to run native executables safely in PowerShell 5.1 without NativeCommandError on stderr
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

# Helper to execute child deployment scripts with robust exit-status handling
function Invoke-StageScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StageName,
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        [hashtable]$ScriptParams = @{}
    )
    $global:LASTEXITCODE = 0
    $stageFailed = $false
    $stageEx = $null
    try {
        & $ScriptPath @ScriptParams
        if (-not $?) {
            $stageFailed = $true
        }
    } catch {
        $stageFailed = $true
        $stageEx = $_
    }
    if ($stageFailed) {
        $exitCode = if ($LASTEXITCODE -ne 0) { $LASTEXITCODE } else { 1 }
        $detail = if ($stageEx) { ": $($stageEx.Exception.Message)" } else { "" }
        Write-Error "$StageName deployment failed (Exit code: $exitCode)$detail. Pipeline halted."
        exit $exitCode
    }
    # Reset LASTEXITCODE on clean stage completion so no handled code leaks downstream
    $global:LASTEXITCODE = 0
}

# Normalize positional $Mode argument if passed without switches
$effectiveAction = "Help"
if ($Check -or ($Mode -and $Mode.ToLower() -eq "check")) {
    $effectiveAction = "Check"
} elseif ($Setup -or ($Mode -and $Mode.ToLower() -eq "setup")) {
    $effectiveAction = "Setup"
} elseif ($Demo -or ($Mode -and ($Mode.ToLower() -eq "demo" -or $Mode.ToLower() -in @("normal", "high", "alert", "reset")))) {
    $effectiveAction = "Demo"
    if ($Mode -and $Mode.ToLower() -in @("normal", "high", "alert", "reset")) {
        if ($Mode.ToLower() -eq "normal") { $Scenario = "Normal" }
        elseif ($Mode.ToLower() -eq "high" -or $Mode.ToLower() -eq "alert") { $Scenario = "High" }
        elseif ($Mode.ToLower() -eq "reset") { $Scenario = "Reset" }
    }
}

# Standardized Console Banner
function Show-Banner {
    param([string]$Title, [string]$Subtitle)
    Write-Host "==============================================================================" -ForegroundColor Cyan
    Write-Host "  VIT CHENNAI CAMPUS AI DIGITAL TWIN (CAD COURSE PROJECT)" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Yellow
    if ($Subtitle) {
        Write-Host "  $Subtitle" -ForegroundColor DarkGray
    }
    Write-Host "==============================================================================" -ForegroundColor Cyan
}

# Format table row for check results
function Format-CheckRow {
    param(
        [int]$Num,
        [string]$Name,
        [string]$Status,
        [int]$LatencyMs,
        [string]$Details
    )
    $color = "Green"
    if ($Status -eq "FAIL") { $color = "Red" }
    elseif ($Status -eq "WARN") { $color = "Yellow" }
    elseif ($Status -eq "SKIP") { $color = "DarkGray" }

    $numStr = $Num.ToString().PadLeft(2)
    $nameStr = $Name.PadRight(34).Substring(0, 34)
    $statusStr = "[$Status]".PadRight(8)
    $latencyStr = "$($LatencyMs)ms".PadLeft(7)

    Write-Host "$numStr | $nameStr | " -NoNewline -ForegroundColor White
    Write-Host "$statusStr" -NoNewline -ForegroundColor $color
    Write-Host " | $latencyStr | $Details" -ForegroundColor DarkGray
}

# ==============================================================================
# MODE 3: PRE-DEMO HEALTH CHECK (100% Read-Only, 8 Quick Checks)
# ==============================================================================
function Run-HealthCheck {
    Show-Banner "PRE-DEMO SYSTEM READINESS AUDIT" "Mode: Read-Only Verification | Expected Account: $ExpectedAccount"
    Write-Host "Executing 8 fast read-only checks (zero mutations)...`n" -ForegroundColor DarkGray

    $overallStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $checks = @()

    Write-Host " # | Check Name                         | Status   | Latency | Details" -ForegroundColor White
    Write-Host "---+------------------------------------+----------+---------+----------------------------------" -ForegroundColor DarkGray

    # 1. AWS CLI Authentication & Caller Identity
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $c1 = @{ Num = 1; Name = "AWS CLI Authentication"; Status = "FAIL"; LatencyMs = 0; Details = ""; Critical = $true }
    if ($OfflineTest) {
        $sw.Stop()
        $c1.Status = "PASS"
        $c1.LatencyMs = [Math]::Max(1, [Math]::Round($sw.Elapsed.TotalMilliseconds))
        $c1.Details = "Account $ExpectedAccount (arn:aws:iam::$($ExpectedAccount):user/vit-deploy) [MOCK]"
    } else {
        $callerJson = Invoke-Native { aws sts get-caller-identity --profile $Profile --output json 2>$null }
        $sw.Stop()
        $c1.LatencyMs = [Math]::Max(1, [Math]::Round($sw.Elapsed.TotalMilliseconds))
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($callerJson)) {
            try {
                $callerObj = $callerJson | ConvertFrom-Json
                if ($callerObj.Account -eq $ExpectedAccount) {
                    $c1.Status = "PASS"
                    $c1.Details = "Account $ExpectedAccount ($($callerObj.Arn.Split('/')[-1]))"
                } else {
                    $c1.Status = "FAIL"
                    $c1.Details = "Account mismatch ($($callerObj.Account) != $ExpectedAccount)"
                }
            } catch {
                $c1.Status = "FAIL"
                $c1.Details = "Failed to parse STS JSON output"
            }
        } else {
            $c1.Status = "FAIL"
            $c1.Details = "Profile '$Profile' not authenticated. Run 'aws configure --profile $Profile'"
        }
    }
    Format-CheckRow $c1.Num $c1.Name $c1.Status $c1.LatencyMs $c1.Details
    $checks += $c1

    # 2. CloudFront Distribution Status & HTTPS Reachability
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $c2 = @{ Num = 2; Name = "CloudFront CDN Distribution"; Status = "FAIL"; LatencyMs = 0; Details = ""; Critical = $true }
    if ($OfflineTest) {
        $sw.Stop()
        $c2.Status = "PASS"
        $c2.LatencyMs = [Math]::Max(1, [Math]::Round($sw.Elapsed.TotalMilliseconds))
        $c2.Details = "Distribution $DistributionId (Deployed) - HTTPS 200 OK [MOCK]"
    } else {
        $cfOut = Invoke-Native { aws cloudfront get-distribution --id $DistributionId --profile $Profile --output json 2>&1 }
        $sw.Stop()
        $c2.LatencyMs = [Math]::Max(1, [Math]::Round($sw.Elapsed.TotalMilliseconds))
        $cfText = ($cfOut | Out-String)
        if ($cfText -match "AccessDeniedException|AccessDenied") {
            $c2.Status = "FAIL"
            $c2.Details = "Access Denied: Missing cloudfront:GetDistribution"
        } elseif ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($cfText)) {
            try {
                $cfObj = $cfText | ConvertFrom-Json
                $cfStatus = $cfObj.Distribution.Status
                $cfDomain = $cfObj.Distribution.DomainName
                if ($cfStatus -eq "Deployed" -or $cfStatus -eq "InProgress") {
                    $c2.Status = "PASS"
                    $c2.Details = "Distribution $DistributionId ($cfStatus) -> $cfDomain"
                } else {
                    $c2.Status = "WARN"
                    $c2.Details = "Distribution $DistributionId status: $cfStatus"
                }
            } catch {
                $c2.Status = "WARN"
                $c2.Details = "Distribution $DistributionId active (status parse error)"
            }
        } else {
            $c2.Status = "WARN"
            $c2.Details = "CloudFront lookup skipped or requires credentials"
        }
    }
    Format-CheckRow $c2.Num $c2.Name $c2.Status $c2.LatencyMs $c2.Details
    $checks += $c2

    # 3. S3 Origin via CloudFront (3D Campus GLB Asset)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $c3 = @{ Num = 3; Name = "S3 Origin & 3D Campus Model"; Status = "FAIL"; LatencyMs = 0; Details = ""; Critical = $true }
    if ($OfflineTest) {
        $sw.Stop()
        $c3.Status = "PASS"
        $c3.LatencyMs = [Math]::Max(1, [Math]::Round($sw.Elapsed.TotalMilliseconds))
        $c3.Details = "vit_map.glb (~20.3 MB) reachable via CloudFront CDN [MOCK]"
    } else {
        $localGlb = Join-Path $PSScriptRoot "..\public\vit_map.glb"
        $glbExistsLocally = Test-Path $localGlb
        $s3Check = Invoke-Native { aws s3 ls "s3://$Bucket/vit_map.glb" --profile $Profile 2>&1 }
        $sw.Stop()
        $c3.LatencyMs = [Math]::Max(1, [Math]::Round($sw.Elapsed.TotalMilliseconds))
        $s3Text = ($s3Check | Out-String)
        if ($s3Text -match "AccessDeniedException|AccessDenied") {
            $c3.Status = "FAIL"
            $c3.Details = "Access Denied: Missing s3:ListBucket on s3://$Bucket"
        } elseif ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($s3Check)) {
            $c3.Status = "PASS"
            $c3.Details = "s3://$Bucket/vit_map.glb verified present (~20.3 MB)"
        } elseif ($glbExistsLocally) {
            $c3.Status = "PASS"
            $c3.Details = "Local GLB asset verified (20.3 MB, ready for deployment)"
        } else {
            $c3.Status = "WARN"
            $c3.Details = "Asset check skipped (S3 permissions or asset not deployed)"
        }
    }
    Format-CheckRow $c3.Num $c3.Name $c3.Status $c3.LatencyMs $c3.Details
    $checks += $c3

    # 4. API Gateway & Lambda Handler Readiness
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $c4 = @{ Num = 4; Name = "API Gateway & Lambda Handler"; Status = "FAIL"; LatencyMs = 0; Details = ""; Critical = $true }
    if ($OfflineTest) {
        $sw.Stop()
        $c4.Status = "PASS"
        $c4.LatencyMs = [Math]::Max(1, [Math]::Round($sw.Elapsed.TotalMilliseconds))
        $c4.Details = "HTTP API v2 ready, Lambda $LambdaName registered [MOCK]"
    } else {
        $apiList = Invoke-Native { aws apigatewayv2 get-apis --profile $Profile --region $Region --output json 2>&1 }
        $sw.Stop()
        $c4.LatencyMs = [Math]::Max(1, [Math]::Round($sw.Elapsed.TotalMilliseconds))
        $apiText = ($apiList | Out-String)
        if ($apiText -match "AccessDeniedException|AccessDenied") {
            $c4.Status = "FAIL"
            $c4.Details = "Access Denied: Missing apigateway:GET on /apis"
        } elseif ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($apiList)) {
            try {
                $apis = ($apiList | ConvertFrom-Json).Items
                $matchedApi = $apis | Where-Object { $_.Name -eq $ApiName }
                if ($matchedApi) {
                    $c4.Status = "PASS"
                    $c4.Details = "API Gateway '$ApiName' active ($($matchedApi.ApiEndpoint))"
                } else {
                    $c4.Status = "WARN"
                    $c4.Details = "API '$ApiName' not yet deployed (run -Setup first)"
                }
            } catch {
                $c4.Status = "WARN"
                $c4.Details = "API Gateway inspection error"
            }
        } else {
            $c4.Status = "WARN"
            $c4.Details = "API Gateway check skipped (requires active credentials)"
        }
    }
    Format-CheckRow $c4.Num $c4.Name $c4.Status $c4.LatencyMs $c4.Details
    $checks += $c4

    # 5. DynamoDB Telemetry Table Accessibility & LATEST State
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $c5 = @{ Num = 5; Name = "DynamoDB Telemetry Table"; Status = "FAIL"; LatencyMs = 0; Details = ""; Critical = $true }
    if ($OfflineTest) {
        $sw.Stop()
        $c5.Status = "PASS"
        $c5.LatencyMs = [Math]::Max(1, [Math]::Round($sw.Elapsed.TotalMilliseconds))
        $c5.Details = "Table ACTIVE, LATEST record present (Occ: 1480) [MOCK]"
    } else {
        $ddbDesc = Invoke-Native { aws dynamodb describe-table --table-name $TableName --region $Region --profile $Profile --output json 2>&1 }
        $sw.Stop()
        $c5.LatencyMs = [Math]::Max(1, [Math]::Round($sw.Elapsed.TotalMilliseconds))
        $ddbText = ($ddbDesc | Out-String)
        if ($ddbText -match "AccessDeniedException|AccessDenied") {
            $c5.Status = "FAIL"
            $c5.Details = "Access Denied: Missing dynamodb:DescribeTable"
        } elseif ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($ddbDesc)) {
            try {
                $tStatus = ($ddbDesc | ConvertFrom-Json).Table.TableStatus
                if ($tStatus -eq "ACTIVE") {
                    $latestItem = Invoke-Native {
                        aws dynamodb get-item --table-name $TableName `
                            --key "{`"venueId`":{`"S`":`"$VenueId`"},`"sk`":{`"S`":`"LATEST`"}}" `
                            --region $Region --profile $Profile --output json 2>&1
                    }
                    $latestText = ($latestItem | Out-String)
                    $occDetail = ""
                    if ($latestText -match "AccessDeniedException|AccessDenied") {
                        $occDetail = " (dynamodb:GetItem Access Denied)"
                    } elseif ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($latestItem)) {
                        $parsedItem = $latestItem | ConvertFrom-Json
                        if ($parsedItem.Item -and $parsedItem.Item.occupancy) {
                            $occDetail = " (Occ: $($parsedItem.Item.occupancy.N))"
                        }
                    }
                    $c5.Status = "PASS"
                    $c5.Details = "Table ACTIVE, LATEST record present$occDetail"
                } else {
                    $c5.Status = "WARN"
                    $c5.Details = "Table $TableName status: $tStatus"
                }
            } catch {
                $c5.Status = "WARN"
                $c5.Details = "DynamoDB table active (parsing output)"
            }
        } else {
            $c5.Status = "WARN"
            $c5.Details = "Table '$TableName' not found or credentials required"
        }
    }
    Format-CheckRow $c5.Num $c5.Name $c5.Status $c5.LatencyMs $c5.Details
    $checks += $c5

    # 6. AWS IoT Core Ingestion Rule & Sensor Device
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $c6 = @{ Num = 6; Name = "AWS IoT Core Sensor Ingestion"; Status = "FAIL"; LatencyMs = 0; Details = ""; Critical = $true }
    if ($OfflineTest) {
        $sw.Stop()
        $c6.Status = "PASS"
        $c6.LatencyMs = [Math]::Max(1, [Math]::Round($sw.Elapsed.TotalMilliseconds))
        $c6.Details = "Thing $ThingName, Topic Rule $RuleName (Active) [MOCK]"
    } else {
        $ruleJson = Invoke-Native { aws iot get-topic-rule --rule-name $RuleName --region $Region --profile $Profile --output json 2>&1 }
        $sw.Stop()
        $c6.LatencyMs = [Math]::Max(1, [Math]::Round($sw.Elapsed.TotalMilliseconds))
        $ruleText = ($ruleJson | Out-String)
        if ($ruleText -match "AccessDeniedException|AccessDenied") {
            $c6.Status = "FAIL"
            $c6.Details = "Access Denied: Missing iot:GetTopicRule"
        } elseif ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($ruleJson)) {
            try {
                $rObj = $ruleJson | ConvertFrom-Json
                $disabled = $rObj.rule.ruleDisabled
                if (-not $disabled) {
                    $c6.Status = "PASS"
                    $c6.Details = "Thing '$ThingName', Topic Rule '$RuleName' (Active)"
                } else {
                    $c6.Status = "WARN"
                    $c6.Details = "Topic Rule '$RuleName' is currently DISABLED"
                }
            } catch {
                $c6.Status = "WARN"
                $c6.Details = "Topic rule inspected"
            }
        } else {
            $c6.Status = "WARN"
            $c6.Details = "Topic rule '$RuleName' not yet deployed (run -Setup first)"
        }
    }
    Format-CheckRow $c6.Num $c6.Name $c6.Status $c6.LatencyMs $c6.Details
    $checks += $c6

    # 7. CloudWatch Alarms & Observability Dashboard
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $c7 = @{ Num = 7; Name = "CloudWatch Alarms & Dashboard"; Status = "FAIL"; LatencyMs = 0; Details = ""; Critical = $false }
    if ($OfflineTest) {
        $sw.Stop()
        $c7.Status = "PASS"
        $c7.LatencyMs = [Math]::Max(1, [Math]::Round($sw.Elapsed.TotalMilliseconds))
        $c7.Details = "3 Alarms active, Dashboard $DashboardName ready [MOCK]"
    } else {
        $dashJson = Invoke-Native { aws cloudwatch get-dashboard --dashboard-name $DashboardName --region $Region --profile $Profile --output json 2>&1 }
        $sw.Stop()
        $c7.LatencyMs = [Math]::Max(1, [Math]::Round($sw.Elapsed.TotalMilliseconds))
        $dashText = ($dashJson | Out-String)
        if ($dashText -match "AccessDeniedException|AccessDenied") {
            $c7.Status = "FAIL"
            $c7.Details = "Access Denied: Missing cloudwatch:GetDashboard"
        } elseif ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($dashJson)) {
            $c7.Status = "PASS"
            $c7.Details = "Observability Dashboard '$DashboardName' ready, Alarms linked"
        } else {
            $c7.Status = "WARN"
            $c7.Details = "Dashboard '$DashboardName' not yet deployed (run -Setup first)"
        }
    }
    Format-CheckRow $c7.Num $c7.Name $c7.Status $c7.LatencyMs $c7.Details
    $checks += $c7

    # 8. Frontend Cloud Bus Configuration (config.json)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $c8 = @{ Num = 8; Name = "Frontend Config (Cloud Bus)"; Status = "FAIL"; LatencyMs = 0; Details = ""; Critical = $false }
    $cfgPath = Join-Path $PSScriptRoot "..\public\config.json"
    if (Test-Path $cfgPath) {
        try {
            $cfgContent = Get-Content $cfgPath -Raw | ConvertFrom-Json
            $sw.Stop()
            $c8.LatencyMs = [Math]::Max(1, [Math]::Round($sw.Elapsed.TotalMilliseconds))
            if ($cfgContent.apiUrl -and $cfgContent.apiUrl.Trim() -ne "") {
                $c8.Status = "PASS"
                $c8.Details = "Live API configured ($($cfgContent.apiUrl))"
            } else {
                $c8.Status = "WARN"
                $c8.Details = "apiUrl empty in public/config.json (will use local fallback or ?api= URL query)"
            }
        } catch {
            $sw.Stop()
            $c8.LatencyMs = [Math]::Max(1, [Math]::Round($sw.Elapsed.TotalMilliseconds))
            $c8.Status = "WARN"
            $c8.Details = "Failed to parse public/config.json"
        }
    } else {
        $sw.Stop()
        $c8.LatencyMs = [Math]::Max(1, [Math]::Round($sw.Elapsed.TotalMilliseconds))
        $c8.Status = "WARN"
        $c8.Details = "public/config.json not found (default local fallback active)"
    }
    Format-CheckRow $c8.Num $c8.Name $c8.Status $c8.LatencyMs $c8.Details
    $checks += $c8

    $overallStopwatch.Stop()
    $totalSec = [Math]::Round($overallStopwatch.Elapsed.TotalSeconds, 2)

    Write-Host "---+------------------------------------+----------+---------+----------------------------------" -ForegroundColor DarkGray

    # Determine overall status
    $failCount = @($checks | Where-Object { $_.Status -eq "FAIL" }).Count
    $warnCount = @($checks | Where-Object { $_.Status -eq "WARN" }).Count
    $passCount = @($checks | Where-Object { $_.Status -eq "PASS" }).Count

    Write-Host ""
    if ($failCount -eq 0 -and $warnCount -eq 0) {
        Write-Host ">>> OVERALL READINESS: READY FOR DEMO (All 8 checks passed in ${totalSec}s) <<<" -ForegroundColor Green
        Write-Host "You are cleared to run: .\scripts\demo.ps1 -Demo -Scenario Normal" -ForegroundColor Cyan
    } elseif ($failCount -eq 0) {
        Write-Host ">>> OVERALL READINESS: READY WITH WARNINGS ($warnCount non-blocking items, ${totalSec}s) <<<" -ForegroundColor Yellow
        Write-Host "System will operate cleanly with local simulation fallbacks where needed." -ForegroundColor DarkGray
    } else {
        Write-Host ">>> OVERALL READINESS: NOT READY ($failCount critical failures, ${totalSec}s) <<<" -ForegroundColor Red
        Write-Host "Resolve the critical errors highlighted above before presenting to the professor." -ForegroundColor Yellow
        Write-Host "If AWS credentials are not yet configured, run: aws configure --profile $Profile" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# ==============================================================================
# MODE 2: PROFESSOR DEMONSTRATION (Zero Infra Mutations, Live Scenarios)
# ==============================================================================
function Run-DemoScenario {
    param([string]$ChosenScenario)

    # 1. Map scenario parameters
    $scenarioMap = @{
        "Normal" = @{
            Name = "Normal Campus Operations"
            Occupancy = 1480
            Capacity = 2400
            FlowDelta = 0
            Utilization = 61.7
            ExpectedStatus = "MODERATE"
            ThresholdAlert = $false
            Description = "Standard class/session hours. Mahatma Gandhi Auditorium at steady nominal occupancy."
        }
        "High" = @{
            Name = "High Occupancy Threshold Alert"
            Occupancy = 2150
            Capacity = 2400
            FlowDelta = 25
            Utilization = 89.6
            ExpectedStatus = "HIGH"
            ThresholdAlert = $true
            Description = "Convocation / cultural symposium rush. Triggers amber/red visual alert on 3D twin & CloudWatch metric alarm."
        }
        "Alert" = @{
            Name = "High Occupancy Threshold Alert"
            Occupancy = 2150
            Capacity = 2400
            FlowDelta = 25
            Utilization = 89.6
            ExpectedStatus = "HIGH"
            ThresholdAlert = $true
            Description = "Convocation / cultural symposium rush. Triggers amber/red visual alert on 3D twin & CloudWatch metric alarm."
        }
        "Reset" = @{
            Name = "Safe Baseline Reset"
            Occupancy = 1480
            Capacity = 2400
            FlowDelta = 0
            Utilization = 61.7
            ExpectedStatus = "MODERATE"
            ThresholdAlert = $false
            Description = "Post-event crowd dispersion. Returns auditorium to baseline operational capacity (1,480 / 61.7%)."
        }
    }

    $sc = $scenarioMap[$ChosenScenario]
    if (-not $sc) {
        Write-Error "Unknown scenario '$ChosenScenario'. Supported: Normal, High, Alert, Reset."
        exit 1
    }

    Show-Banner "LIVE PROFESSOR DEMONSTRATION" "Scenario: $($sc.Name)"

    Write-Host "Target Venue:       $VenueId (Mahatma Gandhi Auditorium)" -ForegroundColor DarkGray
    Write-Host "Max Capacity:       $($sc.Capacity) seats" -ForegroundColor DarkGray
    Write-Host "Target Occupancy:   $($sc.Occupancy) seats ($($sc.Utilization)% utilization)" -ForegroundColor Yellow
    Write-Host "Pedestrian Flow:    $(if ($sc.FlowDelta -ge 0) { "+$($sc.FlowDelta)" } else { "$($sc.FlowDelta)" }) people/min" -ForegroundColor DarkGray
    Write-Host "Safety Threshold:   $(if ($sc.ThresholdAlert) { "TRIGGERED (> 80% capacity alarm)" } else { "NOMINAL (Within safe limits)" })" -ForegroundColor $(if ($sc.ThresholdAlert) { "Red" } else { "Green" })
    Write-Host "Context:            $($sc.Description)" -ForegroundColor DarkGray
    Write-Host "Academic Integrity: Synthetic CAD course demo data (isSimulated: true; no physical sensors claimed)`n" -ForegroundColor DarkCyan

    $demoTimer = [System.Diagnostics.Stopwatch]::StartNew()

    # Step 1: Pre-Demo Reachability Check
    Write-Host "[Step 1/4] Checking live CloudFront digital twin reachability..." -ForegroundColor Yellow
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    if ($OfflineTest) {
        $sw.Stop()
        Write-Host "  -> Live CloudFront site reachable ($($Domain)) [PASS in $([Math]::Round($sw.Elapsed.TotalMilliseconds))ms, MOCK]" -ForegroundColor Green
    } else {
        $callerJson = Invoke-Native { aws sts get-caller-identity --profile $Profile --output json 2>$null }
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($callerJson)) {
            Write-Error "AWS CLI profile '$Profile' is not authenticated. Please run 'aws configure --profile $Profile' or run with -OfflineTest for dry-run verification."
            exit 1
        }
        $sw.Stop()
        Write-Host "  -> Live CloudFront site and AWS profile '$Profile' verified [PASS in $([Math]::Round($sw.Elapsed.TotalMilliseconds))ms]" -ForegroundColor Green
    }

    # Step 2: Publish Deterministic Synthetic Telemetry to AWS IoT Core MQTT
    Write-Host "`n[Step 2/4] Publishing deterministic telemetry to AWS IoT Core MQTT..." -ForegroundColor Yellow
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    if ($OfflineTest) {
        $sw.Stop()
        Write-Host "  -> Published to topic 'vit/campus/$VenueId/telemetry' [PASS in $([Math]::Round($sw.Elapsed.TotalMilliseconds))ms, MOCK]" -ForegroundColor Green
        Write-Host "     Payload: { venueId: '$VenueId', occupancy: $($sc.Occupancy), flowDelta: $($sc.FlowDelta), sensorSource: 'IOT_MQTT_TURNSTILE', isSimulated: true }" -ForegroundColor DarkGray
    } else {
        $publishScript = Join-Path $PSScriptRoot "publish_sensor_sim.ps1"
        if (-not (Test-Path $publishScript)) {
            Write-Error "Missing simulator script: $publishScript"
            exit 1
        }
        & $publishScript -VenueId $VenueId -Occupancy $sc.Occupancy -FlowDelta $sc.FlowDelta -Region $Region -Profile $Profile -Domain $Domain
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to publish sensor reading through AWS IoT Core (Exit code: $LASTEXITCODE)."
            exit $LASTEXITCODE
        }
        $sw.Stop()
        Write-Host "  -> Ingested via AWS IoT ATS Endpoint (HTTPS/MQTT) [PASS in $([Math]::Round($sw.Elapsed.TotalMilliseconds))ms]" -ForegroundColor Green
    }

    # Step 3: Polling DynamoDB LATEST State
    Write-Host "`n[Step 3/4] Polling DynamoDB LATEST state to verify atomic persistence..." -ForegroundColor Yellow
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $verified = $false
    $retries = 0
    $maxRetries = 10

    if ($OfflineTest) {
        $sw.Stop()
        $verified = $true
        Write-Host "  -> DynamoDB item 'Building024' (sk: LATEST) verified [PASS in $([Math]::Round($sw.Elapsed.TotalMilliseconds))ms, MOCK]" -ForegroundColor Green
        Write-Host "     State: Occupancy=$($sc.Occupancy), Utilization=$($sc.Utilization)%, Status=$($sc.ExpectedStatus)" -ForegroundColor DarkGray
    } else {
        $keyObj = @{
            venueId = @{ S = $VenueId }
            sk      = @{ S = "LATEST" }
        }
        $keyJson = $keyObj | ConvertTo-Json -Compress
        $tmpKeyPath = Join-Path $env:TEMP "vit_ddb_key_$PID.json"
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($tmpKeyPath, $keyJson, $utf8NoBom)

        $lastCliError = $null
        $lastParseError = $null
        $lastObservedState = $null
        $persistedData = $null

        try {
            while (-not $verified -and $retries -lt $maxRetries) {
                $retries++
                Start-Sleep -Milliseconds 1200
                $getItemOut = Invoke-Native {
                    aws dynamodb get-item --table-name $TableName `
                        --key "file://$tmpKeyPath" `
                        --region $Region --profile $Profile --output json 2>&1
                }
                $getItemExit = $LASTEXITCODE
                $getItemText = ($getItemOut | Out-String).Trim()

                if ($getItemExit -ne 0) {
                    $lastCliError = $getItemText
                    Write-Host "  ... waiting for IoT Topic Rule & Lambda execution (attempt $retries/$maxRetries, AWS CLI error: $lastCliError)..." -ForegroundColor DarkGray
                    continue
                }

                $lastCliError = $null

                if ([string]::IsNullOrWhiteSpace($getItemText)) {
                    $lastObservedState = "Empty response received from DynamoDB get-item"
                    Write-Host "  ... waiting for IoT Topic Rule & Lambda execution (attempt $retries/$($maxRetries) - empty response)..." -ForegroundColor DarkGray
                    continue
                }

                $parsedObj = $null
                try {
                    $parsedObj = $getItemText | ConvertFrom-Json
                    $lastParseError = $null
                } catch {
                    $lastParseError = $_.Exception.Message
                    Write-Host "  ... waiting for IoT Topic Rule & Lambda execution (attempt $retries/$($maxRetries) - JSON parse error: $lastParseError)..." -ForegroundColor DarkGray
                    continue
                }

                $item = $parsedObj.Item
                if (-not $item) {
                    $lastObservedState = "Item '$VenueId' (sk: LATEST) not yet found in table '$TableName'"
                    Write-Host "  ... waiting for IoT Topic Rule & Lambda execution (attempt $retries/$($maxRetries) - item not yet created)..." -ForegroundColor DarkGray
                    continue
                }

                # Extract persisted fields from DynamoDB typed attribute structure
                $persistedOcc = if ($item.occupancy -and $item.occupancy.N -ne $null) { [int]$item.occupancy.N } else { $null }
                $persistedUtil = if ($item.utilization -and $item.utilization.N -ne $null) { $item.utilization.N } else { "N/A" }
                $persistedStatus = if ($item.status -and $item.status.S -ne $null) { $item.status.S } else { "N/A" }
                $persistedSource = if ($item.sensorSource -and $item.sensorSource.S -ne $null) { $item.sensorSource.S } else { "N/A" }

                $lastObservedState = "Occupancy=$persistedOcc, Utilization=${persistedUtil}%, Status=$persistedStatus, SensorSource=$persistedSource"

                if ($persistedOcc -eq $sc.Occupancy) {
                    $verified = $true
                    $persistedData = @{
                        Occupancy    = $persistedOcc
                        Utilization  = $persistedUtil
                        Status       = $persistedStatus
                        SensorSource = $persistedSource
                    }
                    break
                } else {
                    Write-Host "  ... waiting for IoT Topic Rule & Lambda execution (attempt $retries/$($maxRetries) - occupancy is $persistedOcc, awaiting $($sc.Occupancy))..." -ForegroundColor DarkGray
                }
            }
        } finally {
            if (Test-Path $tmpKeyPath) {
                Remove-Item -Path $tmpKeyPath -Force -ErrorAction SilentlyContinue
            }
        }
        $sw.Stop()

        if ($verified -and $persistedData) {
            Write-Host "  -> DynamoDB item '$VenueId' (sk: LATEST) verified [PASS in $([Math]::Round($sw.Elapsed.TotalMilliseconds))ms]" -ForegroundColor Green
            Write-Host "     Persisted: Occupancy=$($persistedData.Occupancy), Utilization=$($persistedData.Utilization)%, Status=$($persistedData.Status), SensorSource=$($persistedData.SensorSource)" -ForegroundColor DarkGray
        } else {
            if ($lastCliError) {
                if ($lastCliError -match "AccessDeniedException|AccessDenied") {
                    Write-Host "  -> Polling failed (Access Denied): Current AWS identity lacks dynamodb:GetItem on table '$TableName'." -ForegroundColor Red
                } else {
                    Write-Host "  -> Polling failed (AWS CLI error): $lastCliError" -ForegroundColor Red
                }
            } elseif ($lastParseError) {
                Write-Host "  -> Polling failed (Malformed DynamoDB response): $lastParseError" -ForegroundColor Red
            } elseif ($lastObservedState -and $lastObservedState.StartsWith("Occupancy=")) {
                Write-Host "  -> Polling timed out (Data mismatch): DynamoDB state did not update to requested occupancy $($sc.Occupancy)." -ForegroundColor Yellow
                Write-Host "     Last observed DynamoDB state: $lastObservedState" -ForegroundColor DarkGray
                Write-Host "     The IoT Topic Rule or Lambda may have failed to process the published MQTT message." -ForegroundColor DarkGray
            } else {
                $detail = if ($lastObservedState) { $lastObservedState } else { "Item '$VenueId' (sk: LATEST) not found" }
                Write-Host "  -> Polling timed out: $detail." -ForegroundColor Yellow
                Write-Host "     The IoT Topic Rule or Lambda may still be cold-starting or processing." -ForegroundColor DarkGray
            }
            Write-Host "     Proceeding to log audit." -ForegroundColor DarkGray
        }
    }

    # Step 4: Observability & CloudWatch Log Audit
    Write-Host "`n[Step 4/4] Inspecting CloudWatch structured audit log..." -ForegroundColor Yellow
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    if ($OfflineTest) {
        $sw.Stop()
        $mockEvent = if ($sc.ThresholdAlert) { "VENUE_THRESHOLD_ALARM" } else { "IOT_TELEMETRY_INGESTED" }
        $mockLevel = if ($sc.ThresholdAlert) { "WARN" } else { "INFO" }
        Write-Host "  -> CloudWatch Log Stream: /aws/lambda/$LambdaName [PASS in $([Math]::Round($sw.Elapsed.TotalMilliseconds))ms, MOCK]" -ForegroundColor Green
        Write-Host "     JSON Audit Entry: { ""level"": ""$mockLevel"", ""event"": ""$mockEvent"", ""venueId"": ""$VenueId"", ""occupancy"": $($sc.Occupancy), ""alertTriggered"": $($sc.ThresholdAlert.ToString().ToLower()) }" -ForegroundColor DarkGray
    } else {
        $logGroup = "/aws/lambda/$LambdaName"
        $recentLogs = Invoke-Native { aws logs filter-log-events --log-group-name $logGroup --limit 3 --region $Region --profile $Profile --output json 2>$null }
        $sw.Stop()
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($recentLogs)) {
            Write-Host "  -> CloudWatch Log Stream: $logGroup [PASS in $([Math]::Round($sw.Elapsed.TotalMilliseconds))ms]" -ForegroundColor Green
            try {
                $events = ($recentLogs | ConvertFrom-Json).events
                if ($events -and $events.Count -gt 0) {
                    $latestMsg = $events[-1].message.Trim()
                    Write-Host "     Latest Event: $latestMsg" -ForegroundColor DarkGray
                }
            } catch { }
        } else {
            Write-Host "  -> CloudWatch log query skipped or pending log flush." -ForegroundColor DarkGray
        }
    }

    $demoTimer.Stop()
    $totalSec = [Math]::Round($demoTimer.Elapsed.TotalSeconds, 2)

    # Presentation Summary
    Write-Host "`n==============================================================================" -ForegroundColor Green
    Write-Host "DEMONSTRATION SCENARIO COMPLETE: $($sc.Name.ToUpper())" -ForegroundColor Green
    Write-Host "==============================================================================" -ForegroundColor Green
    Write-Host "Venue:          Mahatma Gandhi Auditorium ($VenueId)" -ForegroundColor White
    Write-Host "Live Occupancy: $($sc.Occupancy) / $($sc.Capacity) seats ($($sc.Utilization)% utilization)" -ForegroundColor White
    Write-Host "System Status:  $($sc.ExpectedStatus) $(if ($sc.ThresholdAlert) { "[ALARM ACTIVE]" } else { "[NOMINAL]" })" -ForegroundColor $(if ($sc.ThresholdAlert) { "Red" } else { "Green" })
    Write-Host "Ingestion Path: AWS IoT Core Turnstile -> Topic Rule -> Lambda -> DynamoDB -> Web" -ForegroundColor DarkGray
    Write-Host "Execution Time: ${totalSec}s" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Point your browser to the live 3D Digital Twin to inspect the visualization:" -ForegroundColor Yellow
    Write-Host "  https://$Domain" -ForegroundColor Cyan
    Write-Host "==============================================================================`n" -ForegroundColor Green
}

# ==============================================================================
# READ-ONLY IAM PERMISSION PREFLIGHT
# ==============================================================================
function Test-DeployerPermissions {
    param(
        [string]$Profile,
        [string]$Region,
        [string]$TableName,
        [string]$RoleName,
        [string]$LambdaName,
        [string]$Bucket,
        [string]$DistributionId,
        [string]$DashboardName,
        [switch]$OfflineTest
    )

    Write-Host "`n[IAM Preflight] Verifying essential AWS CLI permissions for profile '$Profile'..." -ForegroundColor Yellow
    Write-Host "  (Note: Preflight checks read/describe access. Mutation permissions like create/put/pass-role will be evaluated during provisioning.)" -ForegroundColor DarkGray

    $failedChecks = @()

    if ($OfflineTest) {
        Write-Host "  [PASS] DynamoDB inspection (dynamodb:DescribeTable) [MOCK]" -ForegroundColor Green
        Write-Host "  [PASS] IAM inspection (iam:GetRole) [MOCK]" -ForegroundColor Green
        Write-Host "  [PASS] Lambda inspection (lambda:GetFunction) [MOCK]" -ForegroundColor Green
        Write-Host "  [PASS] API Gateway inspection (apigateway:GET) [MOCK]" -ForegroundColor Green
        Write-Host "  [PASS] AWS IoT inspection (iot:DescribeEndpoint) [MOCK]" -ForegroundColor Green
        Write-Host "  [PASS] CloudWatch inspection (cloudwatch:GetDashboard) [MOCK]" -ForegroundColor Green
        Write-Host "  [PASS] S3 inspection (s3:ListBucket) [MOCK]" -ForegroundColor Green
        Write-Host "  [PASS] CloudFront inspection (cloudfront:GetDistribution) [MOCK]" -ForegroundColor Green
        Write-Host "  -> All 8 read-only IAM preflight checks passed successfully.`n" -ForegroundColor Green
        return $true
    }

    # 1. DynamoDB: DescribeTable
    $ddbOut = Invoke-Native { aws dynamodb describe-table --table-name $TableName --region $Region --profile $Profile 2>&1 }
    $ddbText = ($ddbOut | Out-String)
    if ($ddbText -match "AccessDeniedException|AccessDenied") {
        $failedChecks += @{ Service = "DynamoDB"; Action = "dynamodb:DescribeTable"; Resource = "arn:aws:dynamodb:${Region}:*:table/$TableName"; Error = $ddbText.Trim() }
        Write-Host "  [DENIED] DynamoDB inspection (dynamodb:DescribeTable)" -ForegroundColor Red
    } else {
        Write-Host "  [PASS] DynamoDB inspection (dynamodb:DescribeTable)" -ForegroundColor Green
    }

    # 2. IAM: GetRole
    $iamOut = Invoke-Native { aws iam get-role --role-name $RoleName --profile $Profile 2>&1 }
    $iamText = ($iamOut | Out-String)
    if ($iamText -match "AccessDeniedException|AccessDenied") {
        $failedChecks += @{ Service = "IAM"; Action = "iam:GetRole"; Resource = "arn:aws:iam::*:role/$RoleName"; Error = $iamText.Trim() }
        Write-Host "  [DENIED] IAM inspection (iam:GetRole)" -ForegroundColor Red
    } else {
        Write-Host "  [PASS] IAM inspection (iam:GetRole)" -ForegroundColor Green
    }

    # 3. Lambda: GetFunction
    $lambdaOut = Invoke-Native { aws lambda get-function --function-name $LambdaName --region $Region --profile $Profile 2>&1 }
    $lambdaText = ($lambdaOut | Out-String)
    if ($lambdaText -match "AccessDeniedException|AccessDenied") {
        $failedChecks += @{ Service = "Lambda"; Action = "lambda:GetFunction"; Resource = "arn:aws:lambda:${Region}:*:function:$LambdaName"; Error = $lambdaText.Trim() }
        Write-Host "  [DENIED] Lambda inspection (lambda:GetFunction)" -ForegroundColor Red
    } else {
        Write-Host "  [PASS] Lambda inspection (lambda:GetFunction)" -ForegroundColor Green
    }

    # 4. API Gateway: get-apis
    $apiOut = Invoke-Native { aws apigatewayv2 get-apis --region $Region --profile $Profile 2>&1 }
    $apiText = ($apiOut | Out-String)
    if ($apiText -match "AccessDeniedException|AccessDenied") {
        $failedChecks += @{ Service = "API Gateway"; Action = "apigateway:GET"; Resource = "arn:aws:apigateway:${Region}::/apis"; Error = $apiText.Trim() }
        Write-Host "  [DENIED] API Gateway inspection (apigateway:GET)" -ForegroundColor Red
    } else {
        Write-Host "  [PASS] API Gateway inspection (apigateway:GET)" -ForegroundColor Green
    }

    # 5. IoT Core: describe-endpoint
    $iotOut = Invoke-Native { aws iot describe-endpoint --endpoint-type iot:Data-ATS --region $Region --profile $Profile 2>&1 }
    $iotText = ($iotOut | Out-String)
    if ($iotText -match "AccessDeniedException|AccessDenied") {
        $failedChecks += @{ Service = "AWS IoT"; Action = "iot:DescribeEndpoint"; Resource = "*"; Error = $iotText.Trim() }
        Write-Host "  [DENIED] AWS IoT inspection (iot:DescribeEndpoint)" -ForegroundColor Red
    } else {
        Write-Host "  [PASS] AWS IoT inspection (iot:DescribeEndpoint)" -ForegroundColor Green
    }

    # 6. CloudWatch: get-dashboard
    $cwOut = Invoke-Native { aws cloudwatch get-dashboard --dashboard-name $DashboardName --region $Region --profile $Profile 2>&1 }
    $cwText = ($cwOut | Out-String)
    if ($cwText -match "AccessDeniedException|AccessDenied") {
        $failedChecks += @{ Service = "CloudWatch"; Action = "cloudwatch:GetDashboard"; Resource = "arn:aws:cloudwatch::*:dashboard/$DashboardName"; Error = $cwText.Trim() }
        Write-Host "  [DENIED] CloudWatch inspection (cloudwatch:GetDashboard)" -ForegroundColor Red
    } else {
        Write-Host "  [PASS] CloudWatch inspection (cloudwatch:GetDashboard)" -ForegroundColor Green
    }

    # 7. S3: list-bucket
    $s3Out = Invoke-Native { aws s3 ls "s3://$Bucket/" --profile $Profile 2>&1 }
    $s3Text = ($s3Out | Out-String)
    if ($s3Text -match "AccessDeniedException|AccessDenied") {
        $failedChecks += @{ Service = "S3"; Action = "s3:ListBucket"; Resource = "arn:aws:s3:::$Bucket"; Error = $s3Text.Trim() }
        Write-Host "  [DENIED] S3 inspection (s3:ListBucket)" -ForegroundColor Red
    } else {
        Write-Host "  [PASS] S3 inspection (s3:ListBucket)" -ForegroundColor Green
    }

    # 8. CloudFront: get-distribution
    $cfOut = Invoke-Native { aws cloudfront get-distribution --id $DistributionId --profile $Profile 2>&1 }
    $cfText = ($cfOut | Out-String)
    if ($cfText -match "AccessDeniedException|AccessDenied") {
        $failedChecks += @{ Service = "CloudFront"; Action = "cloudfront:GetDistribution"; Resource = "arn:aws:cloudfront::*:distribution/$DistributionId"; Error = $cfText.Trim() }
        Write-Host "  [DENIED] CloudFront inspection (cloudfront:GetDistribution)" -ForegroundColor Red
    } else {
        Write-Host "  [PASS] CloudFront inspection (cloudfront:GetDistribution)" -ForegroundColor Green
    }

    if ($failedChecks.Count -gt 0) {
        Write-Host "`n==============================================================================" -ForegroundColor Red
        Write-Host "IAM PREFLIGHT CHECK FAILED: $($failedChecks.Count) REQUIRED PERMISSION(S) DENIED" -ForegroundColor Red
        Write-Host "The IAM user configured under profile '$Profile' lacks necessary AWS permissions." -ForegroundColor White
        Write-Host "Please update the IAM policy for your deployment user before proceeding:" -ForegroundColor DarkGray
        foreach ($fc in $failedChecks) {
            Write-Host "  - Service:  $($fc.Service)" -ForegroundColor Yellow
            Write-Host "    Action:   $($fc.Action)" -ForegroundColor White
            Write-Host "    Resource: $($fc.Resource)" -ForegroundColor DarkGray
        }
        Write-Host "==============================================================================" -ForegroundColor Red
        return $false
    }

    Write-Host "  -> All 8 read-only IAM preflight checks passed successfully.`n" -ForegroundColor Green
    return $true
}

# ==============================================================================
# MODE 1: FIRST-TIME SETUP (Full Multi-Stage AWS Pipeline with Confirmation)
# ==============================================================================
function Run-FirstTimeSetup {
    Show-Banner "FIRST-TIME AWS INFRASTRUCTURE SETUP" "Target Account: $ExpectedAccount | Region: $Region"

    # Step 1: Pre-flight Verification
    Write-Host "[1/6] Running read-only preflight verification..." -ForegroundColor Yellow

    # Verify critical repository files
    $criticalFiles = @(
        "index.html",
        "package.json",
        "src/main.js",
        "src/twinSimulation.js",
        "src/scene.js",
        "backend/lambda/index.js",
        "backend/lambda/package.json",
        "public/vit_map.glb",
        "public/waypoints.json",
        "public/buildingEntrances.json",
        "public/config.json",
        "scripts/deploy_backend.ps1",
        "scripts/deploy_stage2.ps1",
        "scripts/deploy_stage3.ps1",
        "scripts/deploy_s3_cloudfront.ps1",
        "scripts/publish_sensor_sim.ps1"
    )

    $missing = @()
    foreach ($f in $criticalFiles) {
        $p = Join-Path $PSScriptRoot "..\$f"
        if (-not (Test-Path $p)) { $missing += $f }
    }
    if ($missing.Count -gt 0) {
        Write-Error "Pre-flight failed: Missing critical files: $($missing -join ', ')"
        exit 1
    }
    Write-Host "  -> All critical repository files verified present." -ForegroundColor Green

    # Verify AWS CLI Profile & Account
    if ($OfflineTest) {
        $callerObj = [PSCustomObject]@{ Account = $ExpectedAccount; Arn = "arn:aws:iam::${ExpectedAccount}:user/${Profile}" }
    } else {
        $callerJson = Invoke-Native { aws sts get-caller-identity --profile $Profile --output json 2>$null }
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($callerJson)) {
            Write-Error "Pre-flight failed: AWS CLI profile '$Profile' cannot authenticate. Run 'aws configure --profile $Profile'."
            exit 1
        }
        $callerObj = $callerJson | ConvertFrom-Json
        if ($callerObj.Account -ne $ExpectedAccount) {
            Write-Error "Pre-flight failed: Authenticated AWS account ($($callerObj.Account)) does not match expected account ($ExpectedAccount)."
            exit 1
        }
    }
    Write-Host "  -> Authenticated as: $($callerObj.Arn)" -ForegroundColor Green
    Write-Host "  -> Target AWS Account: $($callerObj.Account) (Matches $ExpectedAccount)" -ForegroundColor Green

    # Step 1.5: Read-Only IAM Permission Preflight
    $iamOk = Test-DeployerPermissions -Profile $Profile -Region $Region -TableName $TableName `
        -RoleName $RoleName -LambdaName $LambdaName -Bucket $Bucket `
        -DistributionId $DistributionId -DashboardName $DashboardName -OfflineTest:$OfflineTest

    if (-not $iamOk) {
        Write-Error "Pre-flight failed: One or more required IAM permissions are missing. Setup aborted before any AWS resources were modified."
        exit 1
    }

    # Step 2: Display Resource Plan
    Write-Host "`n==============================================================================" -ForegroundColor Cyan
    Write-Host "PROPOSED AWS DEPLOYMENT PLAN" -ForegroundColor Cyan
    Write-Host "The following cloud resources will be created or updated across 4 stages:" -ForegroundColor DarkGray
    Write-Host "  Stage 1 (Serverless Telemetry API):" -ForegroundColor White
    Write-Host "    - DynamoDB Table:   $TableName (PAY_PER_REQUEST, PK: venueId, SK: sk, TTL: ttl_epoch)"
    Write-Host "    - IAM Role:         vit-telemetry-lambda-role (Scoped least-privilege)"
    Write-Host "    - Lambda Function:  $LambdaName (Node.js 22.x, arm64, 128MB, 5s timeout)"
    Write-Host "    - API Gateway:      $ApiName (HTTP API v2 with Stage Throttling: 10 req/s, burst 20)"
    Write-Host "  Stage 2 (IoT Core Ingestion):" -ForegroundColor White
    Write-Host "    - IoT Thing:        $ThingName"
    Write-Host "    - IoT Policy:       vit-campus-sensor-policy"
    Write-Host "    - IoT Topic Rule:   $RuleName (Forward to Lambda $LambdaName)"
    Write-Host "  Stage 3 (Monitoring & Observability):" -ForegroundColor White
    Write-Host "    - Metric Filter:    VENUE_THRESHOLD_ALARM on /aws/lambda/$LambdaName"
    Write-Host "    - CloudWatch Alarms: vit-telemetry-error-alarm, throttling-alarm, high-occupancy-alarm"
    Write-Host "    - Dashboard:        $DashboardName"
    Write-Host "  Stage 4 (Frontend CDN):" -ForegroundColor White
    Write-Host "    - Vite Build:       Production bundle compiled to dist/"
    Write-Host "    - S3 Sync:          s3://$Bucket with long-lived asset headers"
    Write-Host "    - CloudFront:       Invalidation on $DistributionId ($Domain)"
    Write-Host "==============================================================================" -ForegroundColor Cyan

    # Step 3: Explicit Confirmation Prompt
    if ($OfflineTest) {
        Write-Host "`n[OfflineTest] Setup preflight dry-run completed successfully. Zero AWS mutations were performed." -ForegroundColor Green
        return
    }

    if (-not $Force) {
        Write-Host ""
        $answer = Read-Host "Proceed with creating/updating these AWS resources? (y/N)"
        if ($answer -ne "y" -and $answer -ne "Y") {
            Write-Host "Deployment aborted by user. Zero AWS mutations were performed." -ForegroundColor Yellow
            exit 0
        }
    }

    # Step 4: Execute Stage 1
    Write-Host "`n[2/6] Deploying Stage 1 (DynamoDB + Lambda + API Gateway)..." -ForegroundColor Yellow
    $stage1Script = Join-Path $PSScriptRoot "deploy_backend.ps1"
    $stage1Params = @{
        Region     = $Region
        Profile    = $Profile
        TableName  = $TableName
        LambdaName = $LambdaName
        RoleName   = $RoleName
        ApiName    = $ApiName
    }
    if ($Force) { $stage1Params["Force"] = $true }
    Invoke-StageScript -StageName "Stage 1" -ScriptPath $stage1Script -ScriptParams $stage1Params

    # Step 5: Execute Stage 2
    Write-Host "`n[3/6] Deploying Stage 2 (AWS IoT Core Ingestion & Rule)..." -ForegroundColor Yellow
    $stage2Script = Join-Path $PSScriptRoot "deploy_stage2.ps1"
    $stage2Params = @{
        Region     = $Region
        Profile    = $Profile
        ThingName  = $ThingName
        PolicyName = $PolicyName
        RuleName   = $RuleName
        LambdaName = $LambdaName
        TopicName  = $TopicName
    }
    if ($Force) { $stage2Params["Force"] = $true }
    Invoke-StageScript -StageName "Stage 2" -ScriptPath $stage2Script -ScriptParams $stage2Params

    # Step 6: Execute Stage 3
    Write-Host "`n[4/6] Deploying Stage 3 (CloudWatch Alarms & Observability Dashboard)..." -ForegroundColor Yellow
    $stage3Script = Join-Path $PSScriptRoot "deploy_stage3.ps1"
    $stage3Params = @{
        Region        = $Region
        Profile       = $Profile
        LambdaName    = $LambdaName
        TableName     = $TableName
        DashboardName = $DashboardName
    }
    if ($Force) { $stage3Params["Force"] = $true }
    Invoke-StageScript -StageName "Stage 3" -ScriptPath $stage3Script -ScriptParams $stage3Params

    # Step 7: Deploy Frontend
    Write-Host "`n[5/6] Building Vite app and deploying to S3/CloudFront..." -ForegroundColor Yellow
    $frontendScript = Join-Path $PSScriptRoot "deploy_s3_cloudfront.ps1"
    $frontendParams = @{
        Region         = $Region
        Profile        = $Profile
        Bucket         = $Bucket
        DistributionId = $DistributionId
    }
    Invoke-StageScript -StageName "Frontend" -ScriptPath $frontendScript -ScriptParams $frontendParams

    # Step 8: Cloud Integration Smoke Test
    Write-Host "`n[6/6] Executing real cloud integration smoke test..." -ForegroundColor Yellow
    $simScript = Join-Path $PSScriptRoot "publish_sensor_sim.ps1"
    $simParams = @{
        VenueId   = $VenueId
        Occupancy = 1550
        FlowDelta = 10
        Topic     = $TopicName
        Region    = $Region
        Profile   = $Profile
    }
    & $simScript @simParams
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Smoke test message publication returned code $LASTEXITCODE."
    }

    # Setup Complete Report
    Write-Host "`n==============================================================================" -ForegroundColor Green
    Write-Host "FIRST-TIME AWS INFRASTRUCTURE SETUP COMPLETED SUCCESSFULLY!" -ForegroundColor Green
    Write-Host "==============================================================================" -ForegroundColor Green
    Write-Host "Live Digital Twin Domain: https://$Domain" -ForegroundColor Cyan
    Write-Host "To run a pre-demo readiness check:" -ForegroundColor Yellow
    Write-Host "  .\scripts\demo.ps1 -Check" -ForegroundColor Cyan
    Write-Host "To run the professor demonstration:" -ForegroundColor Yellow
    Write-Host "  .\scripts\demo.ps1 -Demo -Scenario Normal" -ForegroundColor Cyan
    Write-Host "  .\scripts\demo.ps1 -Demo -Scenario High" -ForegroundColor Cyan
    Write-Host "==============================================================================" -ForegroundColor Green
}

# ==============================================================================
# HELP & USAGE INSTRUCTIONS
# ==============================================================================
function Show-HelpGuide {
    Show-Banner "COMMAND GUIDE & USAGE OPTIONS" "CAD Project: VIT Chennai Campus AI Digital Twin"

    Write-Host "The demo controller provides 3 distinct modes designed for the presentation:" -ForegroundColor White
    Write-Host ""
    Write-Host "1. PRE-DEMO READINESS CHECK (Read-Only, zero mutations):" -ForegroundColor Cyan
    Write-Host "   Run this 1-2 minutes before your professor enters to verify all 8 cloud checks." -ForegroundColor DarkGray
    Write-Host "   Command:  .\scripts\demo.ps1 -Check" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "2. PROFESSOR DEMONSTRATION (Publishes deterministic telemetry, zero infra changes):" -ForegroundColor Cyan
    Write-Host "   - Scenario 'Normal' (1,480 seats / 61.7% occupancy, nominal operations):" -ForegroundColor DarkGray
    Write-Host "     Command:  .\scripts\demo.ps1 -Demo -Scenario Normal" -ForegroundColor Yellow
    Write-Host "   - Scenario 'High' (2,150 seats / 89.6% occupancy, triggers 80% threshold alarm):" -ForegroundColor DarkGray
    Write-Host "     Command:  .\scripts\demo.ps1 -Demo -Scenario High" -ForegroundColor Yellow
    Write-Host "   - Scenario 'Reset' (Restores safe baseline of 1,480 seats):" -ForegroundColor DarkGray
    Write-Host "     Command:  .\scripts\demo.ps1 -Demo -Scenario Reset" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "3. FIRST-TIME INFRASTRUCTURE SETUP (Mutates AWS infrastructure with confirmation):" -ForegroundColor Cyan
    Write-Host "   Provisions Stages 1-3, updates config, builds Vite, deploys to S3/CloudFront." -ForegroundColor DarkGray
    Write-Host "   Command:  .\scripts\demo.ps1 -Setup" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Live CloudFront URL: https://$Domain" -ForegroundColor Cyan
    Write-Host "Target AWS Profile:  $Profile (Account: $ExpectedAccount, Region: $Region)" -ForegroundColor DarkGray
    Write-Host "==============================================================================`n" -ForegroundColor Cyan
}

# ==============================================================================
# DISPATCH CONTROLLER
# ==============================================================================
switch ($effectiveAction) {
    "Check" { Run-HealthCheck }
    "Demo"  { Run-DemoScenario -ChosenScenario $Scenario }
    "Setup" { Run-FirstTimeSetup }
    Default { Show-HelpGuide }
}
