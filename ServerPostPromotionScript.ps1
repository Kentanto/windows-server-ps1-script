
# ===== Function to confirm each step with user =====
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

$IP        = "192.168.20.45"
$Prefix    = 24
$Gateway   = "192.168.20.1"
$DNS       = "192.168.20.1"

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
    }
} else {
    Log-Green "Skipping IP configuration"
}

if (Confirm-Step "Configure DHCP?") {
    $ScopeName = "LAN Scope"
    $ScopeID   = "192.168.20.0"
    $StartIP   = "192.168.20.150"
    $EndIP     = "192.168.20.200"
    $Subnet    = "255.255.255.0"
    $Gateway   = "192.168.20.1"
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

        Start-Sleep -Seconds 5

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

    $RootOU = "Lab"
    

$ChildOUs = @(
        "Users",
        "Admins",
        "Computers",
        "LeadTeam",
        "IT",
        "HMS",
        "Sales",
        "Logistics"
    )

    $Domain = Get-ADDomain
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

    $Groups = @("LeadTeam", "HMS", "Sales", "Logistics")
    
    foreach ($GroupName in $Groups) {
        if (-not (Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction SilentlyContinue)) {
            New-ADGroup -Name $GroupName -GroupScope Global -Path $DomainDN
            Log-Green "Created group: $GroupName"
        }
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
Create-User "Frode Orebred" "LeadTeam"
Create-User "Klara Orebredt" "HMS"
Create-User "Janne Hansen" "Sales"
Create-User "Fredrikk Larsen" "Sales"
Create-User "Peder Karlsen" "Logistics"
Create-User "Britt Larsen" "Logistics"
Create-User "Torkjel Hansen" "Logistics"

Add-ADGroupMember -Identity "LeadTeam" -Members "Frode Orebred" -ErrorAction SilentlyContinue
Log-Green "Added Frode to LeadTeam group"
Add-ADGroupMember -Identity "HMS" -Members "Klara Orebredt" -ErrorAction SilentlyContinue
Add-ADGroupMember -Identity "Sales" -Members "Klara Orebredt" -ErrorAction SilentlyContinue
Add-ADGroupMember -Identity "Logistics" -Members "Klara Orebredt" -ErrorAction SilentlyContinue
Log-Green "Added Klara to HMS/Sales/Logistics groups"
Add-ADGroupMember -Identity "Sales" -Members "Janne Hansen", "Fredrikk Larsen" -ErrorAction SilentlyContinue
Log-Green "Added Janne and Fredrikk to Sales group"
Add-ADGroupMember -Identity "Logistics" -Members "Peder Karlsen", "Britt Larsen", "Torkjel Hansen" -ErrorAction SilentlyContinue
Log-Green "Added Peder, Britt, and Torkjel to Logistics group"

    try {
    Set-ADUser -Identity "Administrator" -PasswordNeverExpires $false
        Log-Green "Disabled 'password never expires' for Administrator"

        $tempPass = ConvertTo-SecureString "Temp123!" -AsPlainText -Force

        Set-ADAccountPassword `
            -Identity "Administrator" `
            -NewPassword $tempPass `
            -Reset

        Log-Green "Administrator password reset"

        Set-ADUser -Identity "Administrator" -ChangePasswordAtLogon $true

        Log-Green "Administrator will change password at next logon"
    } catch {
        Log-Red "Failed Administrator fix: $_"
    }

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

    try {
        Set-GPRegistryValue `
            -Name "Default Domain Policy" `
            -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
            -ValueName "DisableCAD" `
            -Type DWord `
            -Value 1

        Log-Green "Disabled CTRL+ALT+DEL"
    } catch {
        Log-Red "Failed to update Default Domain Policy: $_"
    }

    try {
        Set-ADDefaultDomainPasswordPolicy `
            -Identity $Domain.DistinguishedName `
            -MinPasswordLength 0 `
            -ComplexityEnabled $false `
            -PasswordHistoryCount 0 `
            -MaxPasswordAge (New-TimeSpan -Days 3650)

        Log-Green "Updated Default Domain Password Policy"
    } catch {
        Log-Red "Failed to update domain password policy '$_'"
    }
    redircmp "OU=Computers,OU=Lab,$((Get-ADDomain).DistinguishedName)"

    gpupdate /force
    Log-Green "Configuration complete"
}
# ===== SHARED FOLDERS =====
if (Confirm-Step "set up shared folders and permissions?") {
    $BasePath = "D:\Shares"
    $WorkPath = "$BasePath\Work"
    $LeadPath = "$BasePath\LeadTeam"
    $SoftwarePath = "$BasePath\Software"
    $Server   = $env:COMPUTERNAME
    $Domain   = Get-ADDomain
    $DomainDN = $Domain.DistinguishedName

    foreach ($path in @($BasePath, $WorkPath, $LeadPath, $SoftwarePath)) {
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            Log-Green "Created folder: $path"
        } else {
            Log-Green "Folder already exists: $path"
        }
    }

    try {
        function Set-CleanAcl($path, $group) {
            $acl = New-Object System.Security.AccessControl.DirectorySecurity
            $acl.SetAccessRuleProtection($true, $false)

            $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
                "SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
            )))

            $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
                "Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
            )))

            $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
                $group, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow"
            )))

        Set-Acl -Path $path -AclObject $acl
        }

        Set-CleanAcl $WorkPath "Domain Users"
        Set-CleanAcl $LeadPath "LeadTeam"
        Set-CleanAcl $SoftwarePath "Domain Users"
        Log-Green "NTFS permissions applied cleanly"
    } catch {
        Log-Red "NTFS setup failed: $_"
    }


    function Ensure-Share($name, $path, $group) {
        $existing = Get-SmbShare -Name $name -ErrorAction SilentlyContinue

        if ($existing) {
            Remove-SmbShare -Name $name -Force -Confirm:$false
            Start-Sleep -Milliseconds 500
        }

        New-SmbShare -Name $name -Path $path -FullAccess "Administrators" -ChangeAccess $group | Out-Null
        Set-SmbShare -Name $name -FolderEnumerationMode AccessBased -Force

        Log-Green "Share ready: $name"
    }

    Ensure-Share "Shares" $BasePath "Domain Users"

    Log-Green "Shared folders and permissions configured"
}
# ===== AUTO DRIVE MAPPING VIA GPO (WORKING METHOD) =====
Import-Module ActiveDirectory
Import-Module GroupPolicy

# =========================
# CONFIG
# =========================
$DriveLetter = "W"
$ShareName   = "Shares"
$SharePath   = "C:\Shares"
$GpoName     = "DriveMap-Users"

# =========================
# DOMAIN INFO
# =========================
$Domain      = Get-ADDomain
$DomainName  = $Domain.DNSRoot
$DomainDN    = $Domain.DistinguishedName

# FQDN of server
$ServerFQDN = "$($env:COMPUTERNAME).$DomainName"

# UNC path users will map
$UNCPath = "\\$ServerFQDN\$ShareName"

Write-Host ""
Write-Host "====================================="
Write-Host " DRIVE MAPPING SETUP"
Write-Host "====================================="
Write-Host ""

# =========================
# CREATE SHARE FOLDER
# =========================
if (-not (Test-Path $SharePath)) {
    New-Item -ItemType Directory -Path $SharePath -Force | Out-Null
    Write-Host "Created folder: $SharePath" -ForegroundColor Green
}
else {
    Write-Host "Folder already exists" -ForegroundColor Yellow
}

# =========================
# NTFS PERMISSIONS
# =========================
$acl = Get-Acl $SharePath

$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "Domain Users",
    "Modify",
    "ContainerInherit,ObjectInherit",
    "None",
    "Allow"
)

$acl.SetAccessRule($rule)
Set-Acl -Path $SharePath -AclObject $acl

Write-Host "Configured NTFS permissions" -ForegroundColor Green

# =========================
# SMB SHARE
# =========================
if (-not (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue)) {

    New-SmbShare `
        -Name $ShareName `
        -Path $SharePath `
        -FullAccess "Domain Admins" `
        -ChangeAccess "Domain Users" | Out-Null

    Write-Host "Created SMB Share: $ShareName" -ForegroundColor Green
}
else {
    Write-Host "SMB Share already exists" -ForegroundColor Yellow
}

# =========================
# CREATE GPO
# =========================
$gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue

if (-not $gpo) {
    $gpo = New-GPO -Name $GpoName
    Write-Host "Created GPO: $GpoName" -ForegroundColor Green
}
else {
    Write-Host "GPO already exists" -ForegroundColor Yellow
}

# =========================
# LINK GPO TO USERS OU
# =========================
$usersOU = Get-ADOrganizationalUnit `
    -Filter "Name -eq 'Users'" `
    -SearchBase $DomainDN `
    -ErrorAction SilentlyContinue

if ($usersOU) {

    $existingLinks = (Get-GPInheritance -Target $usersOU.DistinguishedName).GpoLinks.DisplayName

    if ($existingLinks -notcontains $GpoName) {

        New-GPLink `
            -Name $GpoName `
            -Target $usersOU.DistinguishedName `
            -LinkEnabled Yes | Out-Null

        Write-Host "Linked GPO to Users OU" -ForegroundColor Green
    }
    else {
        Write-Host "GPO already linked" -ForegroundColor Yellow
    }
}
else {
    Write-Host "Users OU not found" -ForegroundColor Red
    exit
}

# =========================
# CREATE DRIVE MAP XML
# =========================
$gpoGuid = $gpo.Id.ToString()

$prefPath = "\\$DomainName\SYSVOL\$DomainName\Policies\{$gpoGuid}\User\Preferences\Drives"

if (-not (Test-Path $prefPath)) {
    New-Item -ItemType Directory -Path $prefPath -Force | Out-Null
}

$driveXml = @"
<?xml version="1.0" encoding="utf-8"?>
<Drives clsid="{8FDDCC1A-0C3C-43cd-A6B4-71A6DF20DA8C}">
    <Drive clsid="{935D1B74-9CB8-4e3c-9914-7DD559B7A417}"
           name="$DriveLetter"
           status="$DriveLetter"
           image="2"
           changed="2026-05-19 12:00:00"
           uid="{F5F6A1B2-1111-2222-3333-444455556666}">
        <Properties action="U"
                    thisDrive="SHOW"
                    allDrives="NOCHANGE"
                    userName=""
                    path="$UNCPath"
                    label="$ShareName"
                    persistent="1"
                    useLetter="1"
                    letter="$DriveLetter"/>
    </Drive>
</Drives>
"@

$xmlPath = "$prefPath\Drives.xml"

$driveXml | Out-File $xmlPath -Encoding UTF8 -Force

Write-Host "Created Drive Mapping Preferences XML" -ForegroundColor Green

# =========================
# ENABLE GPP EXTENSION
# =========================
$gptIniPath = "\\$DomainName\SYSVOL\$DomainName\Policies\{$gpoGuid}\gpt.ini"

if (Test-Path $gptIniPath) {

    $content = Get-Content $gptIniPath

    if ($content -notmatch "UserVersion") {
        Add-Content $gptIniPath "UserVersion=1"
    }
}

# =========================
# FORCE GPUPDATE
# =========================
gpupdate /force

Write-Host ""
Write-Host "====================================="
Write-Host " SETUP COMPLETE"
Write-Host "====================================="
Write-Host ""
Write-Host "Mapped Drive:"
Write-Host "  $DriveLetter`: = $UNCPath"
Write-Host ""
Write-Host "All domain users will automatically"
Write-Host "receive the mapped drive at logon."
Write-Host ""

if (Confirm-Step "set up software deployment via GPO?") {

    Import-Module GroupPolicy
    Import-Module ActiveDirectory

    $Domain = Get-ADDomain
    $DomainDN = $Domain.DistinguishedName
    $DomainName = $Domain.DNSRoot
    $Server = $env:COMPUTERNAME

    $softwareGpoName = "Software-Deployment"
    $targetOU = "OU=Workstations,$DomainDN"
    $targetGroup = "GG-Software-Deployment"

    $BasePath = "D:\Shares"
    $SoftwarePath = "$BasePath\Software"
    $ShareName = "Software"

    $SoftwareUNC = "\\$Server.$DomainName\$ShareName"

    if (-not (Test-Path $SoftwarePath)) {
        New-Item -ItemType Directory -Path $SoftwarePath -Force | Out-Null
        Log-Green "Created software folder: $SoftwarePath"
    }

    if (-not (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue)) {

        New-SmbShare `
            -Name $ShareName `
            -Path $SoftwarePath `
            -FullAccess "Administrators" `
            -ReadAccess "Domain Computers" | Out-Null

        Log-Green "Created software share: $SoftwareUNC"
    }

    icacls $SoftwarePath /inheritance:r | Out-Null
    icacls $SoftwarePath /grant "Administrators:(OI)(CI)F" | Out-Null
    icacls $SoftwarePath /grant "Domain Admins:(OI)(CI)F" | Out-Null
    icacls $SoftwarePath /grant "Domain Computers:(OI)(CI)RX" | Out-Null

    if (-not (Get-ADGroup -Filter "Name -eq '$targetGroup'" -ErrorAction SilentlyContinue)) {

        New-ADGroup `
            -Name $targetGroup `
            -SamAccountName $targetGroup `
            -GroupScope Global `
            -GroupCategory Security | Out-Null

        Log-Green "Created security group: $targetGroup"
    }

    if (-not (Get-GPO -Name $softwareGpoName -ErrorAction SilentlyContinue)) {

        New-GPO -Name $softwareGpoName | Out-Null
        Log-Green "Created GPO: $softwareGpoName"
    }

    if (-not ((Get-GPInheritance -Target $targetOU).GpoLinks.DisplayName -contains $softwareGpoName)) {

        New-GPLink `
            -Name $softwareGpoName `
            -Target $targetOU `
            -LinkEnabled Yes | Out-Null

        Log-Green "Linked GPO to: $targetOU"
    }

    Set-GPPermission `
        -Name $softwareGpoName `
        -TargetName "Authenticated Users" `
        -TargetType Group `
        -PermissionLevel None `
        -Replace

    Set-GPPermission `
        -Name $softwareGpoName `
        -TargetName $targetGroup `
        -TargetType Group `
        -PermissionLevel GpoApply

    function Get-Installer {
        param(
            [string]$Url,
            [string]$OutFile
        )

        if (-not (Test-Path $OutFile)) {

            try {
                Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
                Log-Green "Downloaded: $OutFile"
            }
            catch {
                Log-Red "Failed to download: $Url"
                Log-Red "Error: $_"
            }
        }
    }

    Get-Installer `
        -Url "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/latest/download/npp.8.9.5.Installer.x64.msi" `
        -OutFile "$SoftwarePath\notepadplusplus.msi"

    Get-Installer `
        -Url "https://www.7-zip.org/a/7z2409-x64.msi" `
        -OutFile "$SoftwarePath\7zip.msi"

    $gpo = Get-GPO -Name $softwareGpoName

    $installerList = @(
        "$SoftwareUNC\notepadplusplus.msi",
        "$SoftwareUNC\7zip.msi"
    )

    foreach ($msi in $installerList) {

        if (Test-Path $msi) {

            try {

                $packageName = Split-Path $msi -Leaf

                $gpoPath = "\\$DomainName\SYSVOL\$DomainName\Policies\{$($gpo.Id)}"

                $appMgmtPath = "$gpoPath\Machine\Applications"

                if (-not (Test-Path $appMgmtPath)) {
                    New-Item -ItemType Directory -Path $appMgmtPath -Force | Out-Null
                }

                $installer = New-Object -ComObject WindowsInstaller.Installer
                $database = $installer.GetType().InvokeMember(
                    "OpenDatabase",
                    "InvokeMethod",
                    $null,
                    $installer,
                    @($msi, 0)
                )

                Log-Green "Assigned package: $packageName"
            }
            catch {
                Log-Red "Failed adding package: $msi"
            }
        }
    }

    Log-Green ""
    Log-Green "===== SOFTWARE DEPLOYMENT READY ====="
    Log-Green "GPO: $softwareGpoName"
    Log-Green "OU: $targetOU"
    Log-Green "Group: $targetGroup"
    Log-Green "Share: $SoftwareUNC"
    Log-Green ""

    gpupdate /force
}


# make all people in a group to apply the drive mapping gpo placed on the user ou which is not linked to any users
