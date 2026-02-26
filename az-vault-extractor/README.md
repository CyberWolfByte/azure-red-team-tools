# Azure Vault Extractor

Azure Vault Extractor is a lightweight Azure Key Vault enumeration and extraction helper that uses the Azure CLI to validate subscription access by listing visible resources, enumerate a target Key Vault’s secrets + keys, and optionally retrieve selected secret values.

## Features
- Prompts for Subscription ID and verifies the active context
- Performs a quick RBAC/visibility check by listing resources in the subscription
- Enumerates Key Vault:
  - Secrets (full IDs/URIs
  - Target secrets
  - Keys
- Optional interactive retrieval of secret values by name (supports `*` for all)
- Input validation + error handling (bad GUIDs, invalid vault names, Azure CLI failures)

## Requirements
- PowerShell 5.1+ or PowerShell 7+
- Azure CLI installed (`az`)
- Logged in to Azure CLI (`az login`)
- Permissions to list resources and access Key Vault metadata/values

## Usage
```powershell
# Windows PowerShell
.\azure-vault-extractor.ps1

# If your execution policy blocks local scripts
powershell -ExecutionPolicy Bypass -File .\azure-vault-extractor.ps1
```
## How It Works

- Prompts for a Subscription ID, sets it as active via az account set, and confirms the context with `az account show`
- Lists subscription resources using `az resource list` and renders a readable table in PowerShell
- Prompts for a Key Vault name, then:
  - Lists secrets with `az keyvault secret list`
  - Lists keys with `az keyvault key list`
- If secrets exist, prompts for one or more secret names and retrieves values with:
  - `az keyvault secret show --query value -o tsv`

## Output Examples
```
Setting active subscription to 7f3c2d91-1a23-4f2c-bc12-6d9e8a3f41c7 ...

Subscription access / visibility check (what your current identity can enumerate)
Active subscription: 7f3c2d91-1a23-4f2c-bc12-6d9e8a3f41c7

Name             ResourceGroup       Location  Type                         ProvisioningState
----             -------------       --------  ----                         -----------------
acme-sec-vault   rg-security-core    eastus    Microsoft.KeyVault/vaults     Succeeded

Listing secrets in vault 'acme-sec-vault' ...
Listing keys in vault 'acme-sec-vault' ...

Secrets in vault acme-sec-vault (full IDs)
https://acme-sec-vault.vault.azure.net/secrets/maya-collins
https://acme-sec-vault.vault.azure.net/secrets/eli-thompson
https://acme-sec-vault.vault.azure.net/secrets/sofia-navarro

Target secrets in vault acme-sec-vault
maya-collins
eli-thompson
sofia-navarro

Keys in vault acme-sec-vault
(No keys found or you do not have permissions to list keys.)

You can retrieve secret values by entering one or more secret names.
Tip: paste a comma-separated list (a,b,c) or space/newline-separated list.
Enter '*' to retrieve ALL secret values (use with care).
Press Enter to skip.
```
## Contributing
If you have an idea for improvement or wish to collaborate, feel free to contribute.

## Use responsibly and only with explicit authorization. This tool is intended for red teamers, security auditors, and penetration testers with proper authorization.