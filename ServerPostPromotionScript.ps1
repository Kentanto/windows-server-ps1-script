
# ===== Function to confirm each stepwith user =====
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

if (Confirm-Step "Configure DHCP?") {


# ===== DHCP Configuration=====

$ScopeName = "LAN Scope"
$ScopeID   = "192.168.5.0"
$StartIP   = "192.168.5.150"
$EndIP     = "192.168.5.200"
$Subnet    = "255.255.255.0"
$Gateway   = "192.168.5.1"
$DNS       = "192.168.5.1"
$LeaseTime = "2.00:00:00"

try {
    try {
    Restart-Service DHCPServer -Force
    Log-Green "DHCP service restarted to apply DNS settings"
    }
    catch {
        Log-Red "Failed to restart DHCP service"
    }
    $serverIP = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -like "192.168.*" } |
        Select-Object -First 1 -ExpandProperty IPAddress)

    $serverName = "$env:COMPUTERNAME.$env:USERDNSDOMAIN"

    try {
        $existing = Get-DhcpServerInDC -ErrorAction SilentlyContinue |
            Where-Object { $_.DnsName -eq $serverName }

        if ($existing) {
            Log-Green "DHCP already authorized in AD"
        }
        else {
            Add-DhcpServerInDC -DnsName $serverName -IPAddress $serverIP
            Log-Green "DHCP authorized in AD"
        }
    }
    catch {
        Log-Red "Failed to authorize DHCP: $_"
    }

    start-sleep -Seconds 5

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

# ===== GPO and ou/user Configuration =====

if (Confirm-Step "Add OU and users/groups?") {

# ===== CONFIG =====
$RootOU = "Lab"

$ChildOUs = @(
    "Users",
    "Admins",
    "Computers"
)

$UsersToCreate = @(
    "Hans",
    "Live",
    "Kine"
)

$GroupName  = "LeadTeam"
$PolicyName = "LeadTeamPolicy"

$Domain = Get-ADDomain
$DomainDN = $Domain.DistinguishedName

# ===== CREATE ROOT OU =====
try {
    $rootPath = "OU=$RootOU,$DomainDN"

    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$RootOU'" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $RootOU -Path $DomainDN
        Log-Green "Created root OU: $RootOU"
    } else {
        Log-Green "Root OU already exists"
    }
}
catch {
    Log-Red "Failed to create root OU: $_"
}

# ===== CREATE CHILD OUs =====
foreach ($ou in $ChildOUs) {
    try {
        if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$ou'" -SearchBase $rootPath -ErrorAction SilentlyContinue)) {
            New-ADOrganizationalUnit -Name $ou -Path $rootPath
            Log-Green "Created OU: $ou"
        } else {
            Log-Green "OU already exists: $ou"
        }
    }
    catch {
        Log-Red "Failed to create OU $ou : $_"
    }
}

# ===== CREATE GROUP =====
try {
    if (-not (Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction SilentlyContinue)) {
        New-ADGroup `
            -Name $GroupName `
            -GroupScope Global `
            -Path $DomainDN

        Log-Green "Created group: $GroupName"
    }
    else {
        Log-Green "Group already exists: $GroupName"
    }
}
catch {
    Log-Red "Failed to create group: $_"
}

# ===== CREATE FGPP =====
try {
    if (-not (Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$PolicyName'" -ErrorAction SilentlyContinue)) {

        New-ADFineGrainedPasswordPolicy `
            -Name $PolicyName `
            -Precedence 1 `
            -MinPasswordLength 0 `
            -PasswordHistoryCount 0 `
            -ComplexityEnabled $false `
            -MaxPasswordAge (New-TimeSpan -Days 0) `
            -MinPasswordAge (New-TimeSpan -Days 0)

        Log-Green "Created password policy"
    }
    else {
        Log-Green "Password policy already exists"
    }
}
catch {
    Log-Red "Failed to create password policy: $_"
}

# ===== LINK FGPP TO GROUP =====
try {
    Add-ADFineGrainedPasswordPolicySubject `
        -Identity $PolicyName `
        -Subjects $GroupName `
        -ErrorAction SilentlyContinue

    Log-Green "Linked policy to group"
}
catch {
    Log-Red "Failed to link policy: $_"
}

# ===== CREATE USERS =====
foreach ($user in $UsersToCreate) {
    try {
        $userPath = "OU=Users,$rootPath"

        if (-not (Get-ADUser -Filter "SamAccountName -eq '$user'" -ErrorAction SilentlyContinue)) {

            $password = ConvertTo-SecureString "Temp123!" -AsPlainText -Force

            New-ADUser `
                -Name $user `
                -SamAccountName $user `
                -UserPrincipalName "$user@$($Domain.DNSRoot)" `
                -Path $userPath `
                -AccountPassword $password `
                -Enabled $true `
                -ChangePasswordAtLogon $true

            Log-Green "Created user: $user"
        }
        else {
            Log-Green "User already exists: $user"
        }

        # ===== ADD USER TO GROUP =====
        try {
            Add-ADGroupMember -Identity $GroupName -Members $user -ErrorAction SilentlyContinue
            Log-Green "Added $user to $GroupName"            
        }
        catch {
            Log-Red "Failed to add $user to group"
        }

        try {
            Add-ADGroupMember -Identity $GroupName -Members "Administrator" -ErrorAction SilentlyContinue
            Log-Green "Added Administrator to $GroupName"        
        }
        catch {
            Log-Red "Failed to add Administrator to group"
        }

    }
    catch {
        Log-Red "Failed to create user $user : $_"
    }
}
try {
    Set-ADUser -Identity "Administrator" -ChangePasswordAtLogon $true
    Log-Green "Administrator must change password at next logon"
}
catch {
    Log-Red "Failed to set password change requirement"
}

}