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




# ==== SIMPLE LOGGING FUNCTION ====
function Log-Green {
    param([string]$msg)
    Write-Host "[OK] $msg" -ForegroundColor Green
}

function Log-Red {
    param([string]$msg)
    Write-Host "[ERROR] $msg" -ForegroundColor Red
}

# ===== MAIN IP Configuration =====

$IP        = "192.168.5.45"
$Prefix    = 24
$Gateway   = "192.168.5.1"
$DNS       = "192.168.5.1"
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



$ScopeName = "LAN Scope"
$ScopeID   = "192.168.5.0"
$StartIP   = "192.168.5.150"
$EndIP     = "192.168.5.200"
$Subnet    = "255.255.255.0"
$Gateway   = "192.168.5.1"
$DNS       = "127.0.0.1"
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

    Set-DhcpServerv4OptionValue `
        -ScopeId $ScopeID `
        -Router $Gateway

    Log-Green "Gateway set"

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
# ===== GPO AND OU / USER CONFIGURATION =====

if (Confirm-Step "Add OU, users, groups, and GPOs?") {

Import-Module ActiveDirectory
Import-Module GroupPolicy

$RootOU = "Lab"

$ChildOUs = @(
    "Users",
    "Admins",
    "Computers",
    "LeadTeam",
    "IT"
)

$Domain   = Get-ADDomain
$DomainDN = $Domain.DistinguishedName
$rootPath = "OU=$RootOU,$DomainDN"

if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$RootOU'" -ErrorAction SilentlyContinue)) {
    New-ADOrganizationalUnit -Name $RootOU -Path $DomainDN
    Log-Green "Created root OU"
}

foreach ($ou in $ChildOUs) {
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$ou'" -SearchBase $rootPath -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $ou -Path $rootPath
        Log-Green "Created OU: $ou"
    }
}

$GroupName = "LeadTeam"

if (-not (Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction SilentlyContinue)) {
    New-ADGroup -Name $GroupName -GroupScope Global -Path $DomainDN
    Log-Green "Created group: $GroupName"
}

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

        Set-ADUser -Identity $Name -ChangePasswordAtLogon $true

        Log-Green "Created user: $Name in $OU"
    }
}

Create-User "Hans" "LeadTeam"
Create-User "Live" "LeadTeam"
Create-User "Kine" "IT"

Add-ADGroupMember -Identity "LeadTeam" -Members "Hans","Live" -ErrorAction SilentlyContinue
Log-Green "Added Hans and Live to LeadTeam group"

# ===== ADMIN FIX =====
try {
    Set-ADUser -Identity "Administrator" -PasswordNeverExpires $false

    $tempPass = ConvertTo-SecureString "Temp123!" -AsPlainText -Force

    Set-ADAccountPassword -Identity "Administrator" -NewPassword $tempPass -Reset
    Set-ADUser -Identity "Administrator" -ChangePasswordAtLogon $true

    Log-Green "Administrator password reset + forced change"
}
catch {
    Log-Red "Failed Administrator fix: $_"
}

# ===== OU GPOS =====
foreach ($ou in $ChildOUs) {

    $gpoName = "$ou-GPO"

    if (-not (Get-GPO -Name $gpoName -ErrorAction SilentlyContinue)) {

        New-GPO -Name $gpoName | Out-Null
        Log-Green "Created GPO: $gpoName"

        New-GPLink -Name $gpoName -Target "OU=$ou,$rootPath" -LinkEnabled Yes
        Log-Green "Linked GPO: $gpoName to $ou"
    }
}

# ===== DEFAULT DOMAIN POLICY TWEAK =====
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
    Log-Red "Failed Default Domain Policy update: $_"
}

# ===== PASSWORD POLICY =====
try {
    Set-ADDefaultDomainPasswordPolicy `
        -Identity $Domain.DistinguishedName `
        -MinPasswordLength 0 `
        -ComplexityEnabled $false `
        -PasswordHistoryCount 0 `
        -MaxPasswordAge (New-TimeSpan -Days 3650)

    Log-Green "Updated password policy"
}
catch {
    Log-Red "Password policy failed: $_"
}

gpupdate /force
Log-Green "AD setup complete"
}

# ===== SHARED FOLDERS + DRIVE MAPPING (CLEAN FINAL VERSION) =====

if (Confirm-Step "set up shared folders and permissions?") {

$BasePath = "D:\Shares"
$WorkPath = "$BasePath\Work"
$LeadPath = "$BasePath\LeadTeam"

$Domain = Get-ADDomain
$Server = $Domain.DNSRoot
$DomainDN = $Domain.DistinguishedName

foreach ($path in @($BasePath, $WorkPath, $LeadPath)) {
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Log-Green "Created folder: $path"
    }
}

# ===== NTFS =====
function Set-CleanAcl($path, $group) {
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)

    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "SYSTEM","FullControl","ContainerInherit,ObjectInherit","None","Allow"
    )))

    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Administrators","FullControl","ContainerInherit,ObjectInherit","None","Allow"
    )))

    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        $group,"Modify","ContainerInherit,ObjectInherit","None","Allow"
    )))

    Set-Acl -Path $path -AclObject $acl
}

Set-CleanAcl $WorkPath "Domain Users"
Set-CleanAcl $LeadPath "LeadTeam"

Log-Green "NTFS set"

# ===== SMB SHARES =====
function Ensure-Share($name, $path, $group) {

    if (Get-SmbShare -Name $name -ErrorAction SilentlyContinue) {
        Remove-SmbShare -Name $name -Force -Confirm:$false
    }

    New-SmbShare -Name $name -Path $path -FullAccess "Administrators" -ChangeAccess $group | Out-Null
    Set-SmbShare -Name $name -FolderEnumerationMode AccessBased -Force

    Log-Green "Share ready: $name"
}

Ensure-Share "Work" $WorkPath "Domain Users"
Ensure-Share "LeadTeam" $LeadPath "LeadTeam"

# ===== CLEAN GPO DRIVE MAPPING (ONLY METHOD USED) =====

function Add-DriveGPO($name, $letter, $share, $ou) {

    if (-not (Get-GPO -Name $name -ErrorAction SilentlyContinue)) {
        New-GPO -Name $name | Out-Null
    }

    if ((Get-GPInheritance -Target $ou).GpoLinks.DisplayName -notcontains $name) {
        New-GPLink -Name $name -Target $ou -LinkEnabled Yes
    }

    $gpo = Get-GPO $name

    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<DriveMaps>
    <Drive>
        <Properties action="U" driveLetter="$letter" path="\\$Server\$share" persistent="0" />
    </Drive>
</DriveMaps>
"@

    $path = "\\$($Domain.DNSRoot)\SYSVOL\$($Domain.DNSRoot)\Policies\{$($gpo.Id)}\User\Preferences\Drives"

    New-Item -ItemType Directory -Path $path -Force | Out-Null
    $xml | Out-File "$path\Drives.xml" -Encoding UTF8

    Log-Green "Mapped $share -> $letter"
}

Add-DriveGPO "DriveMap-Work" "W:" "Work" "OU=Lab,$DomainDN"
Add-DriveGPO "DriveMap-LeadTeam" "L:" "LeadTeam" "OU=LeadTeam,OU=Lab,$DomainDN"

gpupdate /force
Log-Green "Shares + drives complete"
}