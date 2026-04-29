
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
    # Step 1: Disable "password never expires"
    Set-ADUser -Identity "Administrator" -PasswordNeverExpires $false
    Log-Green "Disabled 'password never expires' for Administrator"

    # Step 2: Set temporary password
    $tempPass = ConvertTo-SecureString "Temp123!" -AsPlainText -Force

    Set-ADAccountPassword `
        -Identity "Administrator" `
        -NewPassword $tempPass `
        -Reset

    Log-Green "Administrator password reset"

    # Step 3: Force change at next logon
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
    Log-Red "Failed to update Default Domain Policy: $_"
}

# ===== FORCE PASSWORD CHANGE VIA DOMAIN POLICY =====

try {
    Set-ADDefaultDomainPasswordPolicy `
        -Identity $Domain.DistinguishedName `
        -MinPasswordLength 0 `
        -ComplexityEnabled $false `
        -PasswordHistoryCount 0 `
        -MaxPasswordAge (New-TimeSpan -Days 3650)

    Log-Green "Updated Default Domain Password Policy"
}
catch {
    Log-Red "Failed to update domain password policy '$_'"
}


gpupdate /force

Log-Green "Configuration complete"
}

# ===== SHARED FOLDERS =====

if (Confirm-Step "set up shared folders and permissions?") {

# ===== CONFIG =====
$BasePath = "D:\Shares"
$WorkPath = "$BasePath\Work"
$LeadPath = "$BasePath\LeadTeam"
$Server   = $env:COMPUTERNAME
$Domain   = Get-ADDomain
$DomainDN = $Domain.DistinguishedName

# ===== CREATE FOLDERS (SAFE) =====
foreach ($path in @($BasePath, $WorkPath, $LeadPath)) {
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path | Out-Null
        Log-Green "Created folder: $path"
    } else {
        Log-Green "Folder already exists: $path"
    }
}

# ===== NTFS PERMISSIONS =====
try {
    # Work (everyone)
    icacls $WorkPath /inheritance:r | Out-Null
    icacls $WorkPath /grant "Domain Users:(OI)(CI)M" | Out-Null

    # LeadTeam (restricted)
    icacls $LeadPath /inheritance:r | Out-Null
    icacls $LeadPath /grant "LeadTeam:(OI)(CI)M" | Out-Null

    Log-Green "NTFS permissions applied"
}
catch {
    Log-Red "Failed NTFS permissions"
}

# ===== SMB SHARES (SAFE) =====

if (-not (Get-SmbShare -Name "Work" -ErrorAction SilentlyContinue)) {
    New-SmbShare -Name "Work" -Path $WorkPath -FullAccess "Domain Users" | Out-Null
    Log-Green "Created share: Work"
} else {
    Log-Green "Share already exists: Work"
}

if (-not (Get-SmbShare -Name "LeadTeam" -ErrorAction SilentlyContinue)) {
    New-SmbShare -Name "LeadTeam" -Path $LeadPath -FullAccess "LeadTeam" | Out-Null
    Log-Green "Created share: LeadTeam"
} else {
    Log-Green "Share already exists: LeadTeam"
}


Set-SmbShare -Name "LeadTeam" -FolderEnumerationMode AccessBased

# ===== GPO: WORK DRIVE =====

$gpoWork = "DriveMap-Work"

if (-not (Get-GPO -Name $gpoWork -ErrorAction SilentlyContinue)) {
    New-GPO -Name $gpoWork | Out-Null
    Log-Green "Created GPO: $gpoWork"
}

$targetOU = "OU=Lab,$DomainDN"

if ((Get-GPInheritance -Target $targetOU).GpoLinks.DisplayName -notcontains $gpoWork) {
    New-GPLink -Name $gpoWork -Target $targetOU -LinkEnabled Yes | Out-Null
    Log-Green "Linked $gpoWork"
}

# Create Drive Maps XML (WORK)
$gpoIdWork = (Get-GPO $gpoWork).Id
$gpoPathWork = "\\$($Domain.DNSRoot)\SYSVOL\$($Domain.DNSRoot)\Policies\{$gpoIdWork}\User\Preferences\Drives"

if (-not (Test-Path $gpoPathWork)) {
    New-Item -ItemType Directory -Path $gpoPathWork -Force | Out-Null
}

$xmlWork = @"
<Drives clsid="{C631DF4C-088F-4156-B058-4375F0853CD8}">
    <Drive name="Work Drive" status="Enabled">
        <Properties action="U" letter="W" path="\\$Server\Work" />
    </Drive>
</Drives>
"@

$xmlWork | Out-File "$gpoPathWork\Drives.xml" -Encoding UTF8
Log-Green "Configured Work drive mapping"

# ===== GPO: LEADTEAM DRIVE =====

$gpoLead = "DriveMap-LeadTeam"

if (-not (Get-GPO -Name $gpoLead -ErrorAction SilentlyContinue)) {
    New-GPO -Name $gpoLead | Out-Null
    Log-Green "Created GPO: $gpoLead"
}

$leadOU = "OU=LeadTeam,OU=Lab,$DomainDN"

if ((Get-GPInheritance -Target $leadOU).GpoLinks.DisplayName -notcontains $gpoLead) {
    New-GPLink -Name $gpoLead -Target $leadOU -LinkEnabled Yes | Out-Null
    Log-Green "Linked $gpoLead"
}

# Create Drive Maps XML (LEADTEAM)
$gpoIdLead = (Get-GPO $gpoLead).Id
$gpoPathLead = "\\$($Domain.DNSRoot)\SYSVOL\$($Domain.DNSRoot)\Policies\{$gpoIdLead}\User\Preferences\Drives"

if (-not (Test-Path $gpoPathLead)) {
    New-Item -ItemType Directory -Path $gpoPathLead -Force | Out-Null
}

$xmlLead = @"
<Drives clsid="{C631DF4C-088F-4156-B058-4375F0853CD8}">
    <Drive name="LeadTeam Drive" status="Enabled">
        <Properties action="U" letter="L" path="\\$Server\LeadTeam" />
    </Drive>
</Drives>
"@

$xmlLead | Out-File "$gpoPathLead\Drives.xml" -Encoding UTF8
Log-Green "Configured LeadTeam drive mapping"

gpupdate /force

Log-Green "Done - log off and log back in to see mapped drives"
}

# ===== AUTO DRIVE MAPPING (LOGON SCRIPT METHOD) =====

if (Confirm-Step "configure automatic drive mapping?") {

# ===== CONFIG =====
$Domain      = Get-ADDomain
$DomainName  = $Domain.DNSRoot
$DomainDN    = $Domain.DistinguishedName
$Server      = $env:COMPUTERNAME

$ScriptName  = "map-drives.ps1"
$ScriptPath  = "\\$DomainName\SYSVOL\$DomainName\scripts\$ScriptName"
$GPOName     = "DriveMap-Script"
$TargetOU    = "OU=Lab,$DomainDN"

# ===== CREATE LOGON SCRIPT (SAFE) =====
if (-not (Test-Path $ScriptPath)) {

$ScriptContent = @"
# Map Work drive (everyone)
net use W: /delete /yes >nul 2>&1
net use W: \\$Server\Work /persistent:no

# Map LeadTeam drive (only if access exists)
net use L: /delete /yes >nul 2>&1
net use L: \\$Server\LeadTeam /persistent:no
"@

    $ScriptContent | Out-File $ScriptPath -Encoding ASCII
    Log-Green "Created logon script"
}
else {
    Log-Green "Logon script already exists"
}

# ===== CREATE GPO (SAFE) =====
if (-not (Get-GPO -Name $GPOName -ErrorAction SilentlyContinue)) {
    New-GPO -Name $GPOName | Out-Null
    Log-Green "Created GPO: $GPOName"
}
else {
    Log-Green "GPO already exists: $GPOName"
}

# ===== LINK GPO (SAFE) =====
$existingLinks = (Get-GPInheritance -Target $TargetOU).GpoLinks.DisplayName

if ($existingLinks -notcontains $GPOName) {
    New-GPLink -Name $GPOName -Target $TargetOU -LinkEnabled Yes | Out-Null
    Log-Green "Linked GPO to Lab OU"
}
else {
    Log-Green "GPO already linked"
}

# ===== ASSIGN LOGON SCRIPT =====
try {
    Set-GPLogonScript `
        -Name $GPOName `
        -ScriptName $ScriptName

    Log-Green "Assigned logon script"
}
catch {
    Log-Red "Failed to assign logon script '$_'"
}

# ===== APPLY =====
gpupdate /force

Log-Green "Done - LOG OFF and log back in as user to see drives"
}