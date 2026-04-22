<# 
    Network Configuration Functions for Windows Server DC Automation
#>

<#
.SYNOPSIS
    Sets static IP configuration
#>
function Set-StaticIPConfiguration {
    param(
        [xml]$Config
    )
    
    $networkConfig = $Config.Configuration.Network
    $interfaceName = $networkConfig.NetworkInterface
    
    Write-Log "Configuring static IP: $($networkConfig.StaticIP)"
    
    try {
        # Get network adapter
        $adapter = Get-NetAdapter -Name $interfaceName -ErrorAction Stop
        
        # Remove existing IP configuration
        $adapter | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        $adapter | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
        
        # Set static IP
        $adapter | New-NetIPAddress -IPAddress $networkConfig.StaticIP `
            -PrefixLength (Convert-SubnetMaskToPrefix $networkConfig.SubnetMask) `
            -DefaultGateway $networkConfig.Gateway -ErrorAction Stop | Out-Null
        
        # Set DNS servers
        Set-DnsClientServerAddress -InterfaceAlias $interfaceName `
            -ServerAddresses ($networkConfig.PrimaryDNS, $networkConfig.SecondaryDNS) `
            -ErrorAction Stop
        
        Write-Log "✓ Static IP configured successfully" -Verbose
        Write-Log "  IP: $($networkConfig.StaticIP)/$($networkConfig.SubnetMask)"
        Write-Log "  Gateway: $($networkConfig.Gateway)"
        Write-Log "  DNS: $($networkConfig.PrimaryDNS), $($networkConfig.SecondaryDNS)"
        
        return $true
    } catch {
        Write-Log "✗ Failed to configure static IP: $_" -IsError
        return $false
    }
}

<#
.SYNOPSIS
    Converts subnet mask to prefix length
#>
function Convert-SubnetMaskToPrefix {
    param(
        [string]$SubnetMask
    )
    
    $ipAddress = [ipaddress]$SubnetMask
    $binaryString = [convert]::ToString($ipAddress.Address, 2).PadLeft(32, '0')
    return ($binaryString -replace '0+$').Length
}

<#
.SYNOPSIS
    Tests network connectivity
#>
function Test-NetworkConnectivity {
    param(
        [xml]$Config
    )
    
    $gateway = $Config.Configuration.Network.Gateway
    
    Write-Log "Testing network connectivity to gateway: $gateway"
    
    if (Test-Connection -ComputerName $gateway -Count 2 -Quiet) {
        Write-Log "✓ Network connectivity verified" -Verbose
        return $true
    } else {
        Write-Log "✗ Cannot reach gateway: $gateway" -Warning
        return $false
    }
}

<#
.SYNOPSIS
    Configures DHCP scope
#>
function Configure-DHCPScope {
    param(
        [xml]$Config
    )
    
    $dhcpConfig = $Config.Configuration.DHCP
    
    if (-not $dhcpConfig.Enabled -eq "true") {
        Write-Log "DHCP not enabled in configuration"
        return $true
    }
    
    Write-Log "Configuring DHCP scope: $($dhcpConfig.ScopeName)"
    
    try {
        # Add DHCP scope
        Add-DhcpServerv4Scope -Name $dhcpConfig.ScopeName `
            -StartRange $dhcpConfig.StartRange `
            -EndRange $dhcpConfig.EndRange `
            -SubnetMask $dhcpConfig.SubnetMask `
            -State Active -ErrorAction Stop | Out-Null
        
        # Configure DHCP options
        Set-DhcpServerv4OptionValue -ScopeId $dhcpConfig.StartRange `
            -OptionId 3 -Value $dhcpConfig.Gateway -ErrorAction Stop
        
        Set-DhcpServerv4OptionValue -ScopeId $dhcpConfig.StartRange `
            -OptionId 6 -Value $Config.Configuration.Network.PrimaryDNS -ErrorAction Stop
        
        # Set lease duration
        Set-DhcpServerv4Scope -ScopeId $dhcpConfig.StartRange `
            -LeaseDuration ([timespan]::FromSeconds($dhcpConfig.LeaseDuration)) `
            -ErrorAction Stop
        
        Write-Log "✓ DHCP scope configured successfully" -Verbose
        Write-Log "  Scope: $($dhcpConfig.ScopeName)"
        Write-Log "  Range: $($dhcpConfig.StartRange) - $($dhcpConfig.EndRange)"
        
        return $true
    } catch {
        Write-Log "✗ Failed to configure DHCP scope: $_" -IsError
        return $false
    }
}

<#
.SYNOPSIS
    Configures DNS zone
#>
function Configure-DNSZone {
    param(
        [xml]$Config
    )
    
    $dnsConfig = $Config.Configuration.DNS
    
    if (-not $dnsConfig.Enabled -eq "true") {
        Write-Log "DNS not enabled in configuration"
        return $true
    }
    
    Write-Log "Configuring DNS zone: $($dnsConfig.Zone)"
    
    try {
        # Create forward lookup zone
        Add-DnsServerPrimaryZone -Name $dnsConfig.Zone `
            -ZoneFile "$($dnsConfig.Zone).dns" -ErrorAction Stop | Out-Null
        
        # Create reverse lookup zone
        Add-DnsServerPrimaryZone -NetworkId $Config.Configuration.Network.StaticIP/24 `
            -ZoneFile "$($dnsConfig.ReverseZone).dns" -ErrorAction Stop | Out-Null
        
        # Add A record for DC
        Add-DnsServerResourceRecordA -ZoneName $dnsConfig.Zone `
            -Name $Config.Configuration.Server.ComputerName `
            -IPv4Address $Config.Configuration.Network.StaticIP `
            -ErrorAction Stop | Out-Null
        
        Write-Log "✓ DNS zone configured successfully" -Verbose
        Write-Log "  Forward Zone: $($dnsConfig.Zone)"
        Write-Log "  Reverse Zone: $($dnsConfig.ReverseZone)"
        
        return $true
    } catch {
        Write-Log "✗ Failed to configure DNS zone: $_" -IsError
        return $false
    }
}

<#
.SYNOPSIS
    Verifies DNS resolution
#>
function Test-DNSResolution {
    param(
        [string]$HostName,
        [string]$DNSServer
    )
    
    try {
        $result = Resolve-DnsName -Name $HostName -Server $DNSServer -ErrorAction Stop
        Write-Log "✓ DNS resolution verified for $HostName -> $($result.IPAddress)" -Verbose
        return $true
    } catch {
        Write-Log "✗ DNS resolution failed for $HostName on $DNSServer" -Warning
        return $false
    }
}
