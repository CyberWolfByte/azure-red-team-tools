<#
az-vault-extractor.ps1

Prompts for an Azure Subscription ID, lists visible resources in that subscription (quick RBAC/visibility check), then prompts for a Key Vault name to enumerate secrets and keys, with an option to retrieve selected secret values.
#>


Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-AzCli {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw "Azure CLI ('az') not found. Install Azure CLI and ensure it is on PATH."
    }
}

function Read-NonEmptyInput {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt
    )
    $value = Read-Host $Prompt
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Input cannot be empty."
    }
    return $value.Trim()
}

function Read-ValidSubscriptionId {
    param(
        [string]$Prompt = "Enter target Azure Subscription ID (GUID)"
    )

    $raw = Read-NonEmptyInput -Prompt $Prompt
    $guid = [guid]::Empty
    if (-not [guid]::TryParse($raw, [ref]$guid)) {
        throw "Invalid Subscription ID format. Expected a GUID (e.g., 291bba3f-e0a5-47bc-a099-3bdcb2a50a05)."
    }
    return $guid.ToString()
}

function Read-ValidVaultName {
    param(
        [string]$Prompt = "Enter Azure Key Vault name"
    )

    $name = Read-NonEmptyInput -Prompt $Prompt

    if ($name.Length -lt 3 -or $name.Length -gt 24) {
        throw "Vault name must be between 3 and 24 characters."
    }
    if ($name -notmatch '^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$') {
        throw "Vault name must start with a letter, end with a letter or digit, and contain only letters, digits, or hyphens."
    }

    return $name
}

function Invoke-AzJson {
    param(
        [Parameter(Mandatory)]
        [string[]]$AzArgs
    )

    $output = & az @AzArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: az $($AzArgs -join ' ')`n$output"
    }

    if ([string]::IsNullOrWhiteSpace($output)) {
        return $null
    }

    try {
        return $output | ConvertFrom-Json
    } catch {
        throw "Failed to parse JSON output from: az $($AzArgs -join ' ')`nRaw output:`n$output"
    }
}

function Parse-NameList {
    param(
        [Parameter(Mandatory)]
        [string]$Raw
    )

    $items = $Raw -split '[,\r\n\t ]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $items = $items | ForEach-Object { $_.Trim().Trim('"').Trim("'") } | Where-Object { $_ -ne '' }
    return ,$items
}

function Get-SecretNamesFromListResult {
    param(
        [Parameter(Mandatory)]
        $SecretsList
    )
    $names = @()
    foreach ($s in $SecretsList) {
        if ($null -ne $s.name -and $s.name -ne '') {
            $names += [string]$s.name
        }
    }
    return $names
}

function Show-SecretValues {
    param(
        [Parameter(Mandatory)]
        [string]$VaultName,
        [Parameter(Mandatory)]
        [string[]]$SecretNames
    )

    Write-Host ""
    Write-Host "Secret Values from vault $VaultName"
    foreach ($SecretName in $SecretNames) {
        try {
            $value = & az keyvault secret show --name $SecretName --vault-name $VaultName --query value -o tsv 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw $value
            }
            Write-Host "$SecretName - $value"
        }
        catch {
            Write-Warning "Failed to retrieve value for secret '$SecretName'. Details: $($_.Exception.Message)"
        }
    }
}

function Show-SubscriptionVisibility {
    param(
        [Parameter(Mandatory)]
        [string]$SubscriptionId
    )

    Write-Host ""
    Write-Host "Subscription access / visibility check (what your current identity can enumerate)"
    Write-Host "Active subscription: $SubscriptionId"
    Write-Host ""

    try {
        $resources = Invoke-AzJson -AzArgs @('resource', 'list', '-o', 'json')

        if (-not $resources -or $resources.Count -eq 0) {
            Write-Host "(No resources returned. This could mean the subscription is empty, or your identity cannot enumerate resources.)"
            return
        }

        $rows =
            $resources |
            Select-Object `
                @{Name='Name'; Expression={$_.name}}, `
                @{Name='ResourceGroup'; Expression={$_.resourceGroup}}, `
                @{Name='Location'; Expression={$_.location}}, `
                @{Name='Type'; Expression={$_.type}}, `
                @{Name='ProvisioningState'; Expression={$_.properties.provisioningState}}

        $rows | Format-Table -AutoSize -Wrap | Out-String | Write-Host
    }
    catch {
        Write-Warning "Failed to list resources in subscription (this may indicate limited permissions). Details: $($_.Exception.Message)"
    }
}

try {
    Assert-AzCli

    # Subscription first
    $SubscriptionID = Read-ValidSubscriptionId

    # Set subscription + verify
    Write-Host "Setting active subscription to $SubscriptionID ..."
    $null = Invoke-AzJson -AzArgs @('account', 'set', '--subscription', $SubscriptionID, '-o', 'json')

    $acct = Invoke-AzJson -AzArgs @('account', 'show', '-o', 'json')
    if (-not $acct -or $acct.id -ne $SubscriptionID) {
        throw "Subscription context verification failed. Expected $SubscriptionID but got $($acct.id)."
    }

    # Show resource visibility before vault prompt
    Show-SubscriptionVisibility -SubscriptionId $SubscriptionID

    # Prompt for vault name
    $VaultName = Read-ValidVaultName

    # Vault enumeration
    Write-Host ""
    Write-Host "Listing secrets in vault '$VaultName' ..."
    $secrets = Invoke-AzJson -AzArgs @('keyvault', 'secret', 'list', '--vault-name', $VaultName, '-o', 'json')

    Write-Host "Listing keys in vault '$VaultName' ..."
    $keys = Invoke-AzJson -AzArgs @('keyvault', 'key', 'list', '--vault-name', $VaultName, '-o', 'json')

    # Secrets full IDs/links and names-only list
    Write-Host ""
    Write-Host "Secrets in vault $VaultName (full IDs)"
    $secretNamesInVault = @()

    if ($secrets -and $secrets.Count -gt 0) {
        $secretNamesInVault = Get-SecretNamesFromListResult -SecretsList $secrets

        foreach ($s in $secrets) {
            if ($null -ne $s.id -and $s.id -ne '') {
                Write-Host $s.id
            } elseif ($null -ne $s.name -and $s.name -ne '') {
                Write-Host $s.name
            }
        }

        Write-Host ""
        Write-Host "Target secrets in vault $VaultName"
        foreach ($n in $secretNamesInVault) {
            Write-Host $n
        }
    }
    else {
        Write-Host "(No secrets found or you do not have permissions to list secrets.)"
    }

    # Keys output
    Write-Host ""
    Write-Host "Keys in vault $VaultName"
    if ($keys -and $keys.Count -gt 0) {
        foreach ($key in $keys) {
            if ($null -ne $key.kid) { Write-Host $key.kid }
            elseif ($null -ne $key.id) { Write-Host $key.id }
        }
    } else {
        Write-Host "(No keys found or you do not have permissions to list keys.)"
    }

    # Guidance + prompt (back to original placement)
    if ($secretNamesInVault.Count -gt 0) {
        Write-Host ""
        Write-Host "You can retrieve secret values by entering one or more secret names."
        Write-Host "Tip: paste a comma-separated list (a,b,c) or space/newline-separated list."
        Write-Host "Enter '*' to retrieve ALL secret values (use with care)."
        Write-Host "Press Enter to skip."

        $raw = Read-Host "Secret names to retrieve"
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $requested = @()
            if ($raw.Trim() -eq '*') {
                $requested = $secretNamesInVault
            } else {
                $requested = Parse-NameList -Raw $raw
            }

            if ($requested.Count -eq 0) {
                Write-Warning "No valid secret names provided. Skipping secret retrieval."
            } else {
                # Validate against vault list to catch typos early
                $validSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                foreach ($n in $secretNamesInVault) { [void]$validSet.Add($n) }

                $final = @()
                $invalid = @()
                foreach ($n in $requested) {
                    if ($validSet.Contains($n)) { $final += $n } else { $invalid += $n }
                }

                if ($invalid.Count -gt 0) {
                    Write-Warning ("These secret names were not found in the vault list and will be skipped: " + ($invalid -join ', '))
                }

                if ($final.Count -gt 0) {
                    Show-SecretValues -VaultName $VaultName -SecretNames $final
                } else {
                    Write-Warning "No valid secret names remained after validation. Nothing to retrieve."
                }
            }
        }
    }

    Write-Host ""
    Write-Host "Done."
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
