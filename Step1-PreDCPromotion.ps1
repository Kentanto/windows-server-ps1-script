function Confirm-Step {
    param([string]$Message)

    if ($script:AutoAccept) {
        Log-Green "Auto-accepted: $Message"
        return $true
    }

    Write-Host ""
    Write-Host "$Message" -ForegroundColor Cyan
    Write-Host "[Y] Yes  [N] No  [A] Yes to all" -ForegroundColor Yellow

    $choice = Read-Host "Choose"

    switch ($choice.ToLower()) {
        "y" { return $true }
        "n" { return $false }
        "a" {
            $script:AutoAccept = $true
            Log-Green "Auto-accept enabled for remaining steps"
            return $true
        }
        default {
            Log-Red "Invalid input, defaulting to No"
            return $false
        }
    }
}

# ===== CONFIG =====
$IP        = "192.168.5.45"
$Prefix    = 24
$Gateway   = "192.168.5.1"
$DNS       = "192.168.5.1"

# ===== LOGGING =====
function Log-Green {
    param([string]$msg)
    Write-Host "[OK] $msg" -ForegroundColor Green
}

function Log-Red {
    param([string]$msg)
    Write-Host "[ERROR] $msg" -ForegroundColor Red
}

# ===== MAIN IP Configuration =====
if (Confirm-Step "Set static IP?") {
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1

if (-not $adapter) {
    Log-Red "No active network adapter found"
    return
}

$ifIndex = $adapter.InterfaceIndex
Log-Green "Using adapter: $($adapter.Name)"


try {
    Set-NetIPInterface -InterfaceIndex $ifIndex -Dhcp Disabled -ErrorAction Stop
    Log-Green "DHCP disabled"
} catch {
    Log-Red "DHCP disable skipped or failed"
}

Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    ForEach-Object {
        try {
            Remove-NetIPAddress -InterfaceIndex $ifIndex -IPAddress $_.IPAddress -Confirm:$false -ErrorAction Stop
            Log-Green "Removed IP $($_.IPAddress)"
        } catch {
            Log-Red "Could not remove IP $($_.IPAddress)"
        }
    }

Get-NetRoute -InterfaceIndex $ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
    ForEach-Object {
        try {
            Remove-NetRoute -InterfaceIndex $ifIndex -DestinationPrefix "0.0.0.0/0" -Confirm:$false -ErrorAction Stop
            Log-Green "Removed existing gateway"
        } catch {
            Log-Red "Could not remove gateway"
        }
    }
try {
    New-NetIPAddress `
        -InterfaceIndex $ifIndex `
        -IPAddress $IP `
        -PrefixLength $Prefix `
        -DefaultGateway $Gateway `
        -ErrorAction Stop

    Log-Green "IP and gateway set"
} catch {
    Log-Red "Failed to set IP"
}
try {
    Set-DnsClientServerAddress `
        -InterfaceIndex $ifIndex `
        -ServerAddresses $DNS `
        -ErrorAction Stop

    Log-Green "DNS set to $DNS"
} catch {
    Log-Red "Failed to set DNS"
}}
else {
    Log-Green "Skipping IP configuration"}

if (Confirm-Step "Configuse DHCP?") {

    # ===== CONFIG =====
$ScopeName = "LAN Scope"
$ScopeID   = "192.168.5.0"
$StartIP   = "192.168.5.150"
$EndIP     = "192.168.5.200"
$Subnet    = "255.255.255.0"
$Gateway   = "192.168.5.1"
$DNS       = "192.168.5.1"
$LeaseTime = "2.00:00:00"

try {
    # Check if scope already exists
    $existing = Get-DhcpServerv4Scope -ScopeId $ScopeID -ErrorAction SilentlyContinue

    if ($existing) {
        Log-Green "Scope already exists. Skipping creation."
    }
    else {
        Add-DhcpServerv4Scope `
            -Name $ScopeName `
            -StartRange $StartIP `
            -EndRange $EndIP `
            -SubnetMask $Subnet `
            -State Active `
            -LeaseDuration $LeaseTime `
            -ErrorAction Stop

        Log-Green "DHCP scope created"
    }

    # Set gateway option (Router = 003)
    Set-DhcpServerv4OptionValue `
        -ScopeId $ScopeID `
        -Router $Gateway

    Log-Green "Gateway set"

    # Set DNS option (006)
    Set-DhcpServerv4OptionValue `
        -ScopeId $ScopeID `
        -DnsServer $DNS

    Log-Green "DNS set"

    Log-Green "DHCP configuration complete"
}
catch {
    Log-Red "DHCP setup failed: $_"
}

} 