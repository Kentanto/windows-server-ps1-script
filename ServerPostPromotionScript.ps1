
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

$IP        = "192.168.1.45"
$Prefix    = 24
$Gateway   = "192.168.1.1"
$DNS       = "192.168.1.1"

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
    $ScopeID   = "192.168.1.0"
    $StartIP   = "192.168.1.150"
    $EndIP     = "192.168.1.200"
    $Subnet    = "255.255.255.0"
    $Gateway   = "192.168.1.1"
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

if (Confirm-Step "configure automatic drive mapping?") {
    
    $Domain = Get-ADDomain
    $DomainDN = $Domain.DistinguishedName
    $DomainName = $Domain.DNSRoot
    $Server = $env:COMPUTERNAME

    # ===== CREATE GPO FOR DRIVE MAPPING =====
    $driveMapGpoName = "DriveMap-Logon"

    if (-not (Get-GPO -Name $driveMapGpoName -ErrorAction SilentlyContinue)) {
        New-GPO -Name $driveMapGpoName | Out-Null
        Log-Green "Created GPO: $driveMapGpoName"
    }

    # Link GPO to Users OU
    $usersOU = (Get-ADOrganizationalUnit -Filter "Name -eq 'Users'" -SearchBase "$rootPath" -ErrorAction SilentlyContinue).DistinguishedName
    
    if ($usersOU) {
        if (-not ((Get-GPInheritance -Target $usersOU -ErrorAction SilentlyContinue).GpoLinks.DisplayName -contains $driveMapGpoName)) {
            New-GPLink -Name $driveMapGpoName -Target $usersOU -LinkEnabled Yes | Out-Null
            Log-Green "Linked GPO to Users OU"
        } else {
            Log-Green "GPO already linked to Users OU"
        }
    } else {
        Log-Red "Users OU not found"
        return
    }

    # ===== CREATE DRIVE MAPPING SCRIPT IN GPO =====
    $driveMapGpoId = (Get-GPO $driveMapGpoName).Id
    $gpoScriptPath = "\\$DomainName\SYSVOL\$DomainName\Policies\{$driveMapGpoId}\User\Scripts\Logon"

    if (-not (Test-Path $gpoScriptPath)) {
        New-Item -ItemType Directory -Path $gpoScriptPath -Force | Out-Null
        Log-Green "Created GPO logon script folder"
    }

    # Create drive mapping script (batch file for reliability)
    $driveMapScript = @"
@echo off
REM Delete existing W: mapping
net use W: /delete /yes >nul 2>&1

REM Map W: drive to Shares root folder
net use W: \\$Server\Shares /persistent:no >nul 2>&1

exit /b 0
"@

    $driveMapFile = "$gpoScriptPath\map-drives.bat"
    $driveMapScript | Out-File $driveMapFile -Encoding ASCII -Force
    Log-Green "Deployed drive mapping script to GPO"

    # ===== CREATE scripts.ini TO REGISTER THE SCRIPT =====
    $scriptsIni = @"
[Logon]
0CmdLine=map-drives.bat
"@

    $scriptsIni | Out-File "$gpoScriptPath\scripts.ini" -Encoding ASCII -Force
    Log-Green "Created scripts.ini for GPO logon script"

    Log-Green ""
    Log-Green "===== DRIVE MAPPING READY ====="
    Log-Green "GPO: $driveMapGpoName is linked to Users OU"
    Log-Green "Script: $driveMapFile"
    Log-Green "Users will have:"
    Log-Green "  W: = \\$Server\Shares (all shared folders)"
    Log-Green ""

    gpupdate /force
    Log-Green "Done - users will see drives mapped on next logon"
}

# ===== SOFTWARE DEPLOYMENT VIA GPO =====

if (Confirm-Step "set up software deployment via GPO?") {

    Import-Module GroupPolicy
    Import-Module ActiveDirectory

    $Domain = Get-ADDomain
    $DomainDN = $Domain.DistinguishedName
    $DomainName = $Domain.DNSRoot
    $Server = $env:COMPUTERNAME

    # ===== CREATE SOFTWARE SHARE =====
    $BasePath = "D:\Shares"
    $SoftwarePath = "$BasePath\Software"
    $ShareName = "Software"

    if (-not (Test-Path $SoftwarePath)) {
        New-Item -ItemType Directory -Path $SoftwarePath -Force | Out-Null
        Log-Green "Created software folder: $SoftwarePath"
    }

    if (-not (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue)) {
        New-SmbShare -Name $ShareName -Path $SoftwarePath -FullAccess "Administrators" -ChangeAccess "Domain Computers" | Out-Null
        Log-Green "Created network share: \\$Server\$ShareName"
    } else {
        Log-Green "Share already exists: \\$Server\$ShareName"
    }

    # ===== CREATE GPO AND LINK TO USERS OU =====
    $softwareGpoName = "Software-Install-Logon"

    if (-not (Get-GPO -Name $softwareGpoName -ErrorAction SilentlyContinue)) {
        New-GPO -Name $softwareGpoName | Out-Null
        Log-Green "Created GPO: $softwareGpoName"
    }

    # Link GPO to Users OU (where user accounts are)
    $usersOU = (Get-ADOrganizationalUnit -Filter "Name -eq 'Users'" -SearchBase "$rootPath" -ErrorAction SilentlyContinue).DistinguishedName
    
    if ($usersOU) {
        if (-not ((Get-GPInheritance -Target $usersOU -ErrorAction SilentlyContinue).GpoLinks.DisplayName -contains $softwareGpoName)) {
            New-GPLink -Name $softwareGpoName -Target $usersOU -LinkEnabled Yes | Out-Null
            Log-Green "Linked GPO to Users OU"
        } else {
            Log-Green "GPO already linked to Users OU"
        }
    } else {
        Log-Red "Users OU not found - cannot link GPO"
    }

    # ===== PLACE LOGON SCRIPT IN GPO =====
    $softwareGpoId = (Get-GPO $softwareGpoName).Id
    $gpoScriptPath = "\\$DomainName\SYSVOL\$DomainName\Policies\{$softwareGpoId}\User\Scripts\Logon"

    if (-not (Test-Path $gpoScriptPath)) {
        New-Item -ItemType Directory -Path $gpoScriptPath -Force | Out-Null
        Log-Green "Created GPO logon script folder"
    }

    # Copy script to GPO folder
    $gpoScriptFile = "$gpoScriptPath\install-software.ps1"
    $logonScript | Out-File $gpoScriptFile -Encoding ASCII -Force
    Log-Green "Deployed logon script to GPO"

    # ===== CREATE scripts.ini TO REGISTER THE SCRIPT =====
    $scriptsIni = @"
[Logon]
0CmdLine=powershell.exe
0Parameters=-ExecutionPolicy Bypass -File install-software.ps1
"@

    $scriptsIni | Out-File "$gpoScriptPath\scripts.ini" -Encoding ASCII -Force
    Log-Green "Created scripts.ini for GPO logon script"

    # ===== DOWNLOAD INSTALLERS =====

    # ===== CREATE LOGON SCRIPT FOR SOFTWARE INSTALLATION =====
    $scriptName = "install-software.ps1"
    $scriptPath = "\\$DomainName\NETLOGON\$scriptName"

    $logonScript = @"
# Software installation script - runs at user logon
# Place MSI files in \\$Server\Software and they will be auto-installed

`$softwareShare = "\\$Server\$ShareName"

if (-not (Test-Path `$softwareShare)) {
    exit 0
}

# Get all MSI files from the software share
`$installers = Get-ChildItem -Path `$softwareShare -Filter "*.msi" -ErrorAction SilentlyContinue

foreach (`$installer in `$installers) {
    `$appPath = `$installer.FullName
    `$appName = `$installer.BaseName
    
    # Check if already installed (basic check by looking for registry or file)
    # You can customize this per application
    
    try {
        # Silent install MSI
        Start-Process msiexec.exe -ArgumentList "/i `"$`appPath`" /quiet /norestart" -Wait -NoNewWindow
        Write-Host "[OK] Installed: `$appName" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Failed to install: `$appName" -ForegroundColor Red
    }
}
"@

    $logonScript | Out-File $scriptPath -Encoding ASCII -Force

    Log-Green "Logon script created: $scriptPath"
    Log-Green "Script will install all .msi files from \\$Server.$DomainName\$ShareName"
    
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
        else {
            Log-Green "Already exists: $OutFile"
        }
    }

    # Download installers to network share (fully qualified path for GPO reliability)
    $SoftwareSharePath = "\\$Server.$DomainName\$ShareName"
    
    # Notepad++
    Get-Installer `
        -Url "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/latest/download/npp.8.9.5.Installer.x64.msi" `
        -OutFile "$SoftwareSharePath\notepadpp.msi"

    Log-Green ""
    Log-Green "===== SOFTWARE DEPLOYMENT VIA GPO READY ====="
    Log-Green "INSTRUCTIONS:"
    Log-Green "1. Copy .MSI installer files to: \\$Server.$DomainName\$ShareName"
    Log-Green "2. Users in the Users OU will auto-install on next logon via GPO"
    Log-Green "3. GPO: $softwareGpoName is linked to Users OU"
    Log-Green "4. Script location: $gpoScriptFile"
    Log-Green ""

    gpupdate /force
}
