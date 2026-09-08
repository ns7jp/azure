[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$ParameterFile,
    [string]$Location = 'japaneast',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$deploymentName = "portfolio-$((Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'))"
$resolvedParameterFile = (Resolve-Path -LiteralPath $ParameterFile).Path
$parameterText = Get-Content -LiteralPath $resolvedParameterFile -Raw

if ($parameterText -match 'param\s+adminCidr\s*=\s*[''"](?:0\.0\.0\.0/0|\*)[''"]') {
    throw 'Unsafe adminCidr: unrestricted SSH sources are not allowed.'
}
if ($parameterText -match 'REPLACE_WITH_YOUR_PUBLIC_KEY') {
    throw 'Replace the example SSH public key before running What-If.'
}
if ($parameterText -match 'REPLACE_WITH_YOUR_ALERT_EMAIL') {
    throw 'Replace the example alert email address before running What-If.'
}
if ($parameterText -match 'BEGIN (?:OPENSSH|RSA|EC|DSA) PRIVATE KEY') {
    throw 'A private key appears to be present. Use only an SSH public key and remove the private key from this file.'
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI (az) was not found. Install it before continuing.'
}

az account show --output none
if ($LASTEXITCODE -ne 0) { throw 'Azure CLI login is required. Run az login.' }

$account = az account show --query '{name:name,id:id,tenantId:tenantId}' --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Could not read the active Azure account.' }

Write-Host "Subscription: $($account.name) ($($account.id))"
Write-Host "Tenant:       $($account.tenantId)"
Write-Host "Parameters:   $resolvedParameterFile"

$parameterArgument = "@$resolvedParameterFile"

Write-Host 'Running Bicep build...'
az bicep build --file (Join-Path $PSScriptRoot '../infra/main.bicep') --stdout | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Bicep build failed.' }

Write-Host 'Running Azure What-If...'
az deployment sub what-if `
    --name $deploymentName `
    --location $Location `
    --template-file (Join-Path $PSScriptRoot '../infra/main.bicep') `
    --parameters $parameterArgument
if ($LASTEXITCODE -ne 0) { throw 'Azure What-If failed. No deployment was started.' }

if (-not $Apply) {
    Write-Host 'WHAT-IF ONLY: No resources were created. Re-run with -Apply after review.'
    return
}

if ($PSCmdlet.ShouldProcess("subscription $($account.id)", "Deploy $deploymentName")) {
    az deployment sub create `
        --name $deploymentName `
        --location $Location `
        --template-file (Join-Path $PSScriptRoot '../infra/main.bicep') `
        --parameters $parameterArgument `
        --output json
    if ($LASTEXITCODE -ne 0) { throw 'Azure deployment failed. Inspect the deployment operations and Activity Log.' }
}
