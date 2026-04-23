# ===== CONFIG (EDIT THESE) =====
$IP        = "192.168.5.15"
$Prefix    = 24              # 255.255.255.0 = /24
$Gateway   = "192.168.5.1"
$DNS       = "192.168.5.1"  # usually your DC itself

# ===== LOGGING =====
function Log-Green {
    param([string]$msg)
    Write-Host "[OK] $msg" -ForegroundColor Green
}

function Log-Red {
    param([string]$msg)
    Write-Host "[ERROR] $msg" -ForegroundColor Red
}

# ===== MAIN =====
try {
    # Get active adapter
    $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1

    if (-not $adapter) {
        Log-Red "No active network adapter found"
        exit
    }

    Log-Green "Using adapter: $($adapter.Name)"

    # Remove existing IPs
    Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

    Log-Green "Old IP addresses removed"

    # Set new IP
    New-NetIPAddress `
        -InterfaceIndex $adapter.InterfaceIndex `
        -IPAddress $IP `
        -PrefixLength $Prefix `
        -DefaultGateway $Gateway

    Log-Green "New IP address set: $IP"

    # Set DNS
    Set-DnsClientServerAddress `
        -InterfaceIndex $adapter.InterfaceIndex `
        -ServerAddresses $DNS

    Log-Green "DNS server set: $DNS"

}
catch {
    Log-Red "Failed: $_"
}

