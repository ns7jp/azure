[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^rg-[a-z0-9-]+$')]
    [string]$ResourceGroupName
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI (az) was not found.' }

az group show --name $ResourceGroupName --output none
if ($LASTEXITCODE -ne 0) { throw "Resource group '$ResourceGroupName' was not found or is not accessible." }

$resources = az resource list --resource-group $ResourceGroupName --query '[].{name:name,type:type,location:location}' --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Failed to list resources.' }

$requiredTypes = @(
    'Microsoft.Network/virtualNetworks',
    'Microsoft.Network/networkSecurityGroups',
    'Microsoft.Network/publicIPAddresses',
    'Microsoft.Network/networkInterfaces',
    'Microsoft.Compute/virtualMachines',
    'Microsoft.OperationalInsights/workspaces',
    'Microsoft.Insights/metricAlerts',
    'Microsoft.Insights/actionGroups',
    'Microsoft.Insights/dataCollectionRules',
    'Microsoft.Insights/dataCollectionRuleAssociations',
    'Microsoft.Compute/virtualMachines/extensions',
    'Microsoft.RecoveryServices/vaults'
)

$failed = $false
foreach ($type in $requiredTypes) {
    $found = @($resources | Where-Object type -eq $type).Count -gt 0
    '{0,-5} {1}' -f $(if ($found) { 'PASS' } else { 'FAIL' }), $type
    if (-not $found) { $failed = $true }
}

Write-Host "`nResource inventory"
$resources | Sort-Object type, name | Format-Table -AutoSize

$nsgNames = az network nsg list --resource-group $ResourceGroupName --query '[].name' --output tsv
if ($LASTEXITCODE -ne 0) { throw 'Failed to list network security groups.' }
$sshRules = $nsgNames | ForEach-Object {
    az network nsg rule list --resource-group $ResourceGroupName --nsg-name $_ --query "[?destinationPortRange=='22'].sourceAddressPrefix" --output tsv
    if ($LASTEXITCODE -ne 0) { throw "Failed to read NSG rules for '$_'." }
}
if ($sshRules -contains '0.0.0.0/0' -or $sshRules -contains '*') {
    Write-Host 'FAIL  SSH is open to an unrestricted source.'
    $failed = $true
} else {
    Write-Host 'PASS  SSH source is restricted.'
}

if ($failed) { throw 'One or more verification checks failed.' }
Write-Host 'Verification completed successfully.'
