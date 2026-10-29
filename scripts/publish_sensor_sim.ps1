# ==============================================================================
# VIT Chennai Campus AI Digital Twin - Sensor Telemetry Publisher & Simulator
# ==============================================================================
# Course: Cloud Architecture Design (CAD)
# Ingestion Flow:
#   publish_sensor_sim.ps1
#     -> AWS IoT Core (Topic: vit/campus/Building024/telemetry)
#       -> IoT Topic Rule (vit_campus_telemetry_rule)
#         -> AWS Lambda (vit-telemetry-handler)
#           -> Amazon DynamoDB (vit-campus-telemetry, sk: LATEST)
#             -> Polled by Live CloudFront Digital Twin (https://d457wl1fwy7gg.cloudfront.net)
#
# Usage (Single Synthetic Reading):
#   .\scripts\publish_sensor_sim.ps1 -Occupancy 1950 -FlowDelta 20
#
# Usage (Continuous Presentation Stream with Random Walk Drift):
#   .\scripts\publish_sensor_sim.ps1 -Stream -IntervalSeconds 3
# ==============================================================================

[CmdletBinding()]
param (
    [string]$VenueId = "Building024",
    [int]$Occupancy = 1920,
    [int]$FlowDelta = 15,
    [string]$Topic = "vit/campus/Building024/telemetry",
    [string]$Region = $(if ($env:AWS_REGION -and $env:AWS_REGION.Trim() -ne "") { $env:AWS_REGION.Trim() } else { "ap-south-1" }),
    [string]$Profile = $(if ($env:AWS_PROFILE -and $env:AWS_PROFILE.Trim() -ne "") { $env:AWS_PROFILE.Trim() } else { "vit-deploy" }),
    [string]$Domain = "d457wl1fwy7gg.cloudfront.net",
    [switch]$Stream,
    [int]$IntervalSeconds = 3,
    [int]$MaxIterations = 0
)

$ErrorActionPreference = "Stop"

$Profile = $Profile.Trim()
$Region = $Region.Trim()
$Domain = if ($Domain -and $Domain.Trim() -ne "") { $Domain.Trim() } else { "d457wl1fwy7gg.cloudfront.net" }

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "VIT Chennai AI Digital Twin - AWS IoT Sensor Simulator" -ForegroundColor Cyan
Write-Host "Target MQTT Topic: $Topic" -ForegroundColor DarkGray
Write-Host "Target Venue:      $VenueId (Mahatma Gandhi Auditorium)" -ForegroundColor DarkGray
Write-Host "AWS CLI Profile:   $Profile | Region: $Region" -ForegroundColor DarkGray
Write-Host "==============================================================================" -ForegroundColor Cyan

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

function Publish-Reading {
    param(
        [string]$vId,
        [int]$occ,
        [int]$flow
    )
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $payloadObj = @{
        venueId      = $vId
        occupancy    = $occ
        flowDelta    = $flow
        sensorSource = "IOT_MQTT_TURNSTILE"
        timestamp    = $timestamp
        isSimulated  = $true
    }
    $payloadJson = $payloadObj | ConvertTo-Json -Compress

    $tmpPayloadPath = Join-Path $env:TEMP "vit_mqtt_payload_$PID.json"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tmpPayloadPath, $payloadJson, $utf8NoBom)

    try {
        Invoke-Native {
            aws iot-data publish `
              --topic $Topic `
              --payload "fileb://$tmpPayloadPath" `
              --region $Region `
              --profile $Profile 2>$null
        }
    } finally {
        if (Test-Path $tmpPayloadPath) {
            Remove-Item -Path $tmpPayloadPath -Force -ErrorAction SilentlyContinue
        }
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] Published -> $Topic | Occupancy: $occ (Flow: $(if ($flow -ge 0) { "+$flow" } else { "$flow" }))" -ForegroundColor Green
    } else {
        Write-Error "Failed to publish MQTT message to AWS IoT Core (Exit code: $LASTEXITCODE)."
    }
}

if (-not $Stream) {
    # Single-shot publication
    Write-Host "`nPublishing single synthetic sensor reading..." -ForegroundColor Yellow
    Publish-Reading -vId $VenueId -occ $Occupancy -flow $FlowDelta
    Write-Host "`nEvent published to AWS IoT Core!" -ForegroundColor Green
    Write-Host "Open the live digital twin to observe the updated state:" -ForegroundColor Cyan
    Write-Host "https://$Domain" -ForegroundColor Cyan
} else {
    # Continuous live streaming simulation
    Write-Host "`nStarting continuous IoT sensor simulation stream (Press Ctrl+C to stop)..." -ForegroundColor Yellow
    $currentOcc = $Occupancy
    $iteration = 0

    while ($true) {
        $iteration++
        # Realistic pedestrian ingress/egress drift (-15 to +20 people)
        $delta = [Math]::Floor((Get-Random -Minimum -15 -Maximum 22))
        $currentOcc = [Math]::Max(100, [Math]::Min(2800, $currentOcc + $delta))

        Publish-Reading -vId $VenueId -occ $currentOcc -flow $delta

        if ($MaxIterations -gt 0 -and $iteration -ge $MaxIterations) {
            Write-Host "`nCompleted $iteration iterations." -ForegroundColor Green
            break
        }
        Start-Sleep -Seconds $IntervalSeconds
    }
}

