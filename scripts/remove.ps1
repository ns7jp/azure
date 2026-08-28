[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^rg-[a-z0-9-]+$')]
    [string]$ResourceGroupName,
    [Parameter(Mandatory)]
    [string]$ConfirmResourceGroupName
)

$ErrorActionPreference = 'Stop'

if ($ResourceGroupName -cne $ConfirmResourceGroupName) {
    throw 'Safety check failed: both resource group names must match exactly.'
}
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI (az) was not found.' }

az group show --name $ResourceGroupName --output table
if ($LASTEXITCODE -ne 0) { throw "Resource group '$ResourceGroupName' was not found or is not accessible." }

az resource list --resource-group $ResourceGroupName --query '[].{name:name,type:type}' --output table
if ($LASTEXITCODE -ne 0) { throw 'Could not inventory the deletion target.' }

if ($PSCmdlet.ShouldProcess($ResourceGroupName, 'Permanently delete the resource group and every resource in it')) {
    az group delete --name $ResourceGroupName --yes
    if ($LASTEXITCODE -ne 0) { throw 'Resource group deletion failed.' }

    $stillExists = az group exists --name $ResourceGroupName --output tsv
    if ($LASTEXITCODE -ne 0) { throw 'Could not verify resource group deletion.' }
    if ($stillExists -ne 'false') { throw "Resource group '$ResourceGroupName' still exists." }
    Write-Host "Deletion verified. Check Cost Management for resources outside '$ResourceGroupName'."
}
