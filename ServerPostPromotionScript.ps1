
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



if (Confirm-Step "Add OU, users, groups, and GPOs?") {

Import-Module ActiveDirectory
Import-Module GroupPolicy

# ===== CONFIG =====
$RootOU = "Lab"

$ChildOUs = @(
    "Users",
    "Admins",
    "Computers",
    "LeadTeam",
    "IT"
)

$Domain = Get-ADDomain
$DomainDN = $Domain.DistinguishedName
$rootPath = "OU=$RootOU,$DomainDN"

# ===== CREATE ROOT OU =====
if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$RootOU'" -ErrorAction SilentlyContinue)) {
    New-ADOrganizationalUnit -Name $RootOU -Path $DomainDN
    Log-Green "Created root OU"
}

# ===== CREATE CHILD OUs =====
foreach ($ou in $ChildOUs) {
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$ou'" -SearchBase $rootPath -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $ou -Path $rootPath
        Log-Green "Created OU: $ou"
    }
}

# ===== CREATE GROUP =====
$GroupName = "LeadTeam"

if (-not (Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction SilentlyContinue)) {
    New-ADGroup -Name $GroupName -GroupScope Global -Path $DomainDN
    Log-Green "Created group: $GroupName"
}

# ===== CREATE USERS =====

function Create-User {
    param($Name, $OU)

    $userPath = "OU=$OU,$rootPath"

    if (-not (Get-ADUser -Filter "SamAccountName -eq '$Name'" -ErrorAction SilentlyContinue)) {

        $password = ConvertTo-SecureString "Temp123!" -AsPlainText -Force

        New-ADUser `
            -Name $Name `
            -SamAccountName $Name `
            -UserPrincipalName "$Name@$($Domain.DNSRoot)" `
            -Path $userPath `
            -AccountPassword $password `
            -Enabled $true

        # Force password change AFTER creation
        Set-ADUser -Identity $Name -ChangePasswordAtLogon $true

        Log-Green "Created user: $Name in $OU"
    }
}

# Hans + Live → LeadTeam OU
Create-User "Hans" "LeadTeam"
Create-User "Live" "LeadTeam"

# Kine → IT OU
Create-User "Kine" "IT"

# Add Hans + Live to group
Add-ADGroupMember -Identity "LeadTeam" -Members "Hans","Live" -ErrorAction SilentlyContinue
Log-Green "Added Hans and Live to LeadTeam group"

# ===== FIX ADMINISTRATOR =====
try {
    $tempPass = ConvertTo-SecureString "Temp123!" -AsPlainText -Force

    Set-ADAccountPassword -Identity "Administrator" -NewPassword $tempPass -Reset
    Set-ADUser -Identity "Administrator" -ChangePasswordAtLogon $true

    Log-Green "Administrator will change password at next logon"
}
catch {
    Log-Red "Failed Administrator fix: $_"
}

# ===== CREATE GPOs FOR OUs =====

foreach ($ou in $ChildOUs) {

    $gpoName = "$ou-GPO"

    if (-not (Get-GPO -Name $gpoName -ErrorAction SilentlyContinue)) {

        New-GPO -Name $gpoName | Out-Null
        Log-Green "Created GPO: $gpoName"

        New-GPLink `
            -Name $gpoName `
            -Target "OU=$ou,$rootPath" `
            -LinkEnabled Yes

        Log-Green "Linked GPO to OU: $ou"
    }
}

# ===== MODIFY DEFAULT DOMAIN POLICY =====

try {
    Set-GPRegistryValue `
        -Name "Default Domain Policy" `
        -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
        -ValueName "DisableCAD" `
        -Type DWord `
        -Value 1

    Log-Green "Disabled CTRL+ALT+DEL"
}
catch {
    Log-Red "Failed to update Default Domain Policy"
}

# ===== FORCE PASSWORD CHANGE VIA DOMAIN POLICY =====

try {
    Set-ADDefaultDomainPasswordPolicy `
        -MinPasswordLength 0 `
        -ComplexityEnabled $false `
        -PasswordHistoryCount 0 `
        -MaxPasswordAge (New-TimeSpan -Days 3650)

    Log-Green "Updated Default Domain Password Policy"
}
catch {
    Log-Red "Failed to update domain password policy"
}

# ===== APPLY GPO =====
gpupdate /force

Log-Green "Configuration complete"
}