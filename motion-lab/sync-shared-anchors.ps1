param(
    [string]$PatrickFaceRoot = (Split-Path -Parent $PSScriptRoot)
)

$shared = Join-Path $PatrickFaceRoot "style-library\patrick-anchor-manifest.json"
$browserTarget = Join-Path $PSScriptRoot "patrick-anchor-manifest.fallback.json"
$watchTarget = Join-Path $PSScriptRoot "watchOS\PatrickMotionLab\patrick-anchor-manifest.fallback.json"

if (-not (Test-Path $shared)) {
    Write-Host "Shared manifest is not present; keeping the local procedural fallback."
    Write-Host "Expected: $shared"
    exit 0
}

$manifest = Get-Content $shared -Raw | ConvertFrom-Json
$required = @("characterRoot", "hourArmPivot", "minuteArmPivot", "faceRoot")
foreach ($anchor in $required) {
    if (-not $manifest.anchors.$anchor) {
        throw "Shared manifest is missing required anchor '$anchor'. Local fallbacks were not changed."
    }
}

Copy-Item $shared $browserTarget -Force
Copy-Item $shared $watchTarget -Force
Write-Host "Synced shared anchors into motion-lab browser and watchOS bundle copies."
