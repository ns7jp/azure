using '../main.bicep'

param location = 'japaneast'
param environment = 'dev'
param projectName = 'portfolio'
param owner = 'your-github-name'
param sshPublicKey = 'ssh-ed25519 REPLACE_WITH_YOUR_PUBLIC_KEY azure-portfolio'
param adminCidr = '203.0.113.10/32'
param openHttp = false
param vmSize = 'Standard_B1s'
param adminUsername = 'azureadmin'
param alertEmailAddress = 'REPLACE_WITH_YOUR_ALERT_EMAIL@example.com'
