param(
    [string]$DeviceId = "emulator-5554",
    [switch]$SkipIntegration
)

$ErrorActionPreference = "Continue"
Set-Location (Split-Path $PSScriptRoot -Parent)

$results = [System.Collections.Generic.List[object]]::new()

function Invoke-TestStep {
    param(
        [string]$Name,
        [string[]]$Command
    )

    Write-Host "`n========================================" -ForegroundColor DarkGray
    Write-Host "RUNNING: $Name" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor DarkGray

    $exe = $Command[0]
    $cmdArgs = @()
    if ($Command.Count -gt 1) {
        $cmdArgs = $Command[1..($Command.Count - 1)]
    }

    & $exe @cmdArgs
    $exitCode = $LASTEXITCODE

    if ($null -eq $exitCode) {
        $exitCode = 0
    }

    $status = if ($exitCode -eq 0) { "PASS" } else { "FAIL" }
    $results.Add([PSCustomObject]@{
        Test   = $Name
        Status = $status
        ExitCode = $exitCode
    })

    if ($status -eq "PASS") {
        Write-Host "PASS: $Name" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $Name (exit code $exitCode)" -ForegroundColor Red
    }
}

Write-Host "`nPYP TEST RUNNER" -ForegroundColor Magenta
Write-Host "Project: $(Get-Location)"
Write-Host "Device: $DeviceId"

Invoke-TestStep -Name "Flutter static analysis" -Command @(
    "flutter", "analyze"
)

Invoke-TestStep -Name "Unit and widget tests" -Command @(
    "flutter", "test", "test"
)

if (-not $SkipIntegration) {
    Invoke-TestStep -Name "App launch smoke test" -Command @(
        "flutter", "test", "integration_test/app_smoke_test.dart",
        "-d", $DeviceId, "--reporter", "expanded"
    )

    Invoke-TestStep -Name "Authentication and marketplace UI test" -Command @(
        "flutter", "test", "integration_test/auth_marketplace_test.dart",
        "-d", $DeviceId, "--reporter", "expanded"
    )
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "FINAL TEST SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$results | Format-Table -AutoSize

$failed = @($results | Where-Object { $_.Status -eq "FAIL" })

Write-Host "Passed: $(@($results | Where-Object { $_.Status -eq 'PASS' }).Count)"
Write-Host "Failed: $($failed.Count)"

if ($failed.Count -gt 0) {
    Write-Host "Some checks failed. Review the output above." -ForegroundColor Red
    exit 1
}

Write-Host "All selected checks passed!" -ForegroundColor Green
exit 0
