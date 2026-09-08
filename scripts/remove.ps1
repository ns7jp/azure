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

# Azure Backupで保護されたVMが残っていると、Recovery Services Vaultにデータが
# 残るため az group delete が失敗するか、Vaultだけが削除できずに残ることがある。
# RG削除の前に、保護を解除してバックアップデータを削除しておく(この操作は
# バックアップの取消不能な削除であり、元に戻せない)。
$vaultNames = az backup vault list --resource-group $ResourceGroupName --query '[].name' --output tsv
if ($LASTEXITCODE -ne 0) { throw 'Failed to list Recovery Services vaults.' }

foreach ($vaultName in $vaultNames) {
    if ([string]::IsNullOrWhiteSpace($vaultName)) { continue }

    Write-Host "Recovery Services Vault '$vaultName': checking protected items before deletion..."

    $items = az backup item list --resource-group $ResourceGroupName --vault-name $vaultName --output json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw "Failed to list backup items for vault '$vaultName'." }

    if ($items.Count -eq 0) {
        Write-Host "No protected items in '$vaultName'."
        continue
    }

    if ($PSCmdlet.ShouldProcess($vaultName, 'Stop backup protection and permanently delete backup data for all protected items')) {
        foreach ($item in $items) {
            $containerName = $item.properties.containerName
            $itemName = $item.properties.friendlyName
            Write-Host "Stopping protection and deleting backup data for '$itemName' in '$vaultName'..."
            az backup protection backup-item stop-protection `
                --resource-group $ResourceGroupName `
                --vault-name $vaultName `
                --container-name $containerName `
                --item-name $itemName `
                --backup-management-type AzureIaasVM `
                --delete-backup-data true `
                --yes
            if ($LASTEXITCODE -ne 0) { throw "Failed to stop protection for '$itemName' in vault '$vaultName'." }
        }
    }
}

if ($PSCmdlet.ShouldProcess($ResourceGroupName, 'Permanently delete the resource group and every resource in it')) {
    az group delete --name $ResourceGroupName --yes
    if ($LASTEXITCODE -ne 0) { throw 'Resource group deletion failed.' }

    $stillExists = az group exists --name $ResourceGroupName --output tsv
    if ($LASTEXITCODE -ne 0) { throw 'Could not verify resource group deletion.' }
    if ($stillExists -ne 'false') { throw "Resource group '$ResourceGroupName' still exists." }
    Write-Host "Deletion verified. Check Cost Management for resources outside '$ResourceGroupName'."
}
