param(
    [Parameter(Position = 0)]
    [string]$Domain
)

if ([string]::IsNullOrWhiteSpace($Domain)) {
    $Domain = Read-Host "Enter the target domain"
}

$recordTypes = @('A', 'AAAA', 'MX', 'TXT', 'NS', 'CNAME')
$records = @()

function New-DnsRecordObject {
    param(
        [string]$Name,
        [string]$Type,
        [string]$Data,
        [string]$Resolver
    )

    [pscustomobject]@{
        Name     = $Name
        Type     = $Type
        Data     = $Data
        Resolver = $Resolver
    }
}

if (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue) {
    foreach ($type in $recordTypes) {
        try {
            $results = Resolve-DnsName -Name $Domain -Type $type -ErrorAction Stop

            foreach ($r in $results) {
                $data = switch ($type) {
                    'A'     { $r.IPAddress }
                    'AAAA'  { $r.IPAddress }
                    'MX'    {
                        if ($null -ne $r.Preference -and $r.Exchange) {
                            "$($r.Preference) $($r.Exchange)"
                        } else {
                            $r.Exchange
                        }
                    }
                    'TXT'   {
                        if ($r.Strings) { $r.Strings -join ' ' }
                    }
                    'NS'    { $r.NameHost }
                    'CNAME' { $r.NameHost }
                }

                if (-not [string]::IsNullOrWhiteSpace($data)) {
                    $records += New-DnsRecordObject -Name $r.Name -Type $type -Data $data -Resolver 'Resolve-DnsName'
                }
            }
        }
        catch {
            # Ignore missing record types
        }
    }
}
elseif (Get-Command dig -ErrorAction SilentlyContinue) {
    foreach ($type in $recordTypes) {
        $results = & dig +short $Domain $type 2>$null

        foreach ($line in $results) {
            $value = $line.ToString().Trim()
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $records += New-DnsRecordObject -Name $Domain -Type $type -Data $value -Resolver 'dig'
            }
        }
    }
}
elseif (Get-Command nslookup -ErrorAction SilentlyContinue) {
    foreach ($type in $recordTypes) {
        $results = & nslookup "-type=$type" $Domain 2>$null

        foreach ($line in $results) {
            $value = $line.ToString().Trim()

            if ([string]::IsNullOrWhiteSpace($value)) { continue }
            if ($value -match '^(Server:|Address:|Non-authoritative answer:|Aliases:|Name:|DNS request timed out)') { continue }

            $records += New-DnsRecordObject -Name $Domain -Type $type -Data $value -Resolver 'nslookup'
        }
    }
}
else {
    Write-Error "No supported resolver found. Install 'dig', use 'nslookup', or run on Windows with Resolve-DnsName available."
    exit 1
}

if (-not $records -or $records.Count -eq 0) {
    Write-Warning "No DNS records found for $Domain"
    exit 1
}

$records | Sort-Object Type, Data | Format-Table -AutoSize