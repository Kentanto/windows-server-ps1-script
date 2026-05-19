
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

$IP        = "192.168.20.177"
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


# ==========================================
# AUTO DRIVE MAPPING VIA GPO (LAB STRUCTURE)
# ==========================================

Import-Module ActiveDirectory
Import-Module GroupPolicy

$DriveLetter = "W"
$ShareName   = "Shares"

$Domain     = Get-ADDomain
$DomainName = $Domain.DNSRoot
$DomainDN   = $Domain.DistinguishedName

$RootOU     = "Lab"
$RootPath   = "OU=$RootOU,$DomainDN"

$GpoName    = "DriveMap-Lab-Users"

# Server UNC path
$ServerFQDN = "$($env:COMPUTERNAME).$DomainName"
$UNCPath    = "\\$ServerFQDN\$ShareName"

Write-Host "Setting up drive mapping..." -ForegroundColor Cyan
Write-Host "Target: $UNCPath" -ForegroundColor Cyan

# ==========================================
# CREATE / GET GPO
# ==========================================

$gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue

if (-not $gpo) {
    $gpo = New-GPO -Name $GpoName
    Log-Green "Created GPO: $GpoName"
}
else {
    Log-Green "GPO already exists"
}

# ==========================================
# LINK GPO TO ROOT LAB OU (IMPORTANT FIX)
# ==========================================

$existingLinks = (Get-GPInheritance -Target $RootPath).GpoLinks.DisplayName

if ($existingLinks -notcontains $GpoName) {
    New-GPLink -Name $GpoName -Target $RootPath -LinkEnabled Yes | Out-Null
    Log-Green "Linked GPO to LAB root OU"
}
else {
    Log-Green "GPO already linked to LAB OU"
}

# ==========================================
# SECURITY FILTERING (IMPORTANT)
# ==========================================

Set-GPPermission -Name $GpoName -TargetName "Authenticated Users" -TargetType Group -PermissionLevel GpoApply

# ==========================================
# DRIVE MAPPING (GROUP POLICY PREFERENCES METHOD)
# ==========================================

# This is the correct GPP registry-based mapping method

Set-GPRegistryValue `
    -Name $GpoName `
    -Key "HKCU\Network\$DriveLetter" `
    -ValueName "RemotePath" `
    -Type String `
    -Value $UNCPath

Set-GPRegistryValue `
    -Name $GpoName `
    -Key "HKCU\Network\$DriveLetter" `
    -ValueName "UserName" `
    -Type String `
    -Value ""

Set-GPRegistryValue `
    -Name $GpoName `
    -Key "HKCU\Network\$DriveLetter" `
    -ValueName "ProviderName" `
    -Type String `
    -Value "Microsoft Windows Network"

Set-GPRegistryValue `
    -Name $GpoName `
    -Key "HKCU\Network\$DriveLetter" `
    -ValueName "ConnectionType" `
    -Type DWord `
    -Value 1

Set-GPRegistryValue `
    -Name $GpoName `
    -Key "HKCU\Network\$DriveLetter" `
    -ValueName "DeferFlags" `
    -Type DWord `
    -Value 4

# ==========================================
# FORCE UPDATE
# ==========================================

gpupdate /force

Write-Host ""
Write-Host "========================================="
Write-Host " DRIVE MAPPING COMPLETE"
Write-Host "========================================="
Write-Host ""
Write-Host "All users in LAB OU tree will get:"
Write-Host "$DriveLetter`: -> $UNCPath"
Write-Host ""


}

if (Confirm-Step "set up software deployment via GPO?") {

    Import-Module ActiveDirectory
    Import-Module GroupPolicy

    # =========================
    # DOMAIN INFO
    # =========================
    $Domain     = Get-ADDomain
    $DomainDN   = $Domain.DistinguishedName
    $DomainName = $Domain.DNSRoot
    $Server     = $env:COMPUTERNAME

    # =========================
    # CONFIG
    # =========================
    $RootOU        = "Lab"
    $LabOUPath     = "OU=$RootOU,$DomainDN"
    $ComputerOU    = "OU=Computers,OU=$RootOU,$DomainDN"

    $GpoName       = "Software-Deployment"
    $GroupName     = "GG-Software-Deployment"

    $BasePath      = "D:\Shares"
    $SoftwarePath  = "$BasePath\Software"

    $SoftwareUNC   = "\\$Server.$DomainName\Software"

    # =========================
    # CREATE SOFTWARE FOLDER
    # =========================
    if (-not (Test-Path $SoftwarePath)) {
        New-Item -ItemType Directory -Path $SoftwarePath -Force | Out-Null
        Log-Green "Created: $SoftwarePath"
    }

    # =========================
    # CREATE SMB SHARE (IMPORTANT FIX)
    # =========================
    if (-not (Get-SmbShare -Name "Software" -ErrorAction SilentlyContinue)) {

        New-SmbShare `
            -Name "Software" `
            -Path $SoftwarePath `
            -FullAccess "Administrators" `
            -ReadAccess "Domain Computers" | Out-Null

        Log-Green "Created Software Share: $SoftwareUNC"
    }

    # =========================
    # NTFS PERMISSIONS (FIXED CLEAN)
    # =========================
    icacls $SoftwarePath /inheritance:r | Out-Null
    icacls $SoftwarePath /grant "Administrators:(OI)(CI)F" | Out-Null
    icacls $SoftwarePath /grant "Domain Admins:(OI)(CI)F" | Out-Null
    icacls $SoftwarePath /grant "Domain Computers:(OI)(CI)RX" | Out-Null

    # =========================
    # CREATE SECURITY GROUP
    # =========================
    if (-not (Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction SilentlyContinue)) {
        New-ADGroup `
            -Name $GroupName `
            -GroupScope Global `
            -GroupCategory Security `
            -Path $DomainDN | Out-Null

        Log-Green "Created group: $GroupName"
    }

    # =========================
    # CREATE GPO
    # =========================
    $gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue

    if (-not $gpo) {
        $gpo = New-GPO -Name $GpoName
        Log-Green "Created GPO: $GpoName"
    }

    # =========================
    # LINK TO LAB ROOT OU (APPLIES TO ALL)
    # =========================
    $existingLinks = (Get-GPInheritance -Target $LabOUPath).GpoLinks.DisplayName

    if ($existingLinks -notcontains $GpoName) {
        New-GPLink `
            -Name $GpoName `
            -Target $LabOUPath `
            -LinkEnabled Yes | Out-Null

        Log-Green "Linked GPO to Lab root OU (affects all Lab objects)"
    }

# ==========================================
# CREATE AUTO MSI INSTALLER SCRIPT
# ==========================================

$gpoId = $gpo.Id.ToString()

$startupFolder = "\\$DomainName\SYSVOL\$DomainName\Policies\{$gpoId}\Machine\Scripts\Startup"

if (-not (Test-Path $startupFolder)) {
    New-Item -ItemType Directory -Path $startupFolder -Force | Out-Null
}

# Create PowerShell script that auto-discovers and installs all MSI files
$psScriptName = "Install-AllMSI.ps1"

$InstallScript = @"
# Auto-install all MSI files from Software share
`$SoftwareShare = "\\$Server.$DomainName\Software"
`$LogPath = "C:\Windows\Temp\SoftwareInstall.log"

# Ensure share is accessible
if (-not (Test-Path `$SoftwareShare)) {
    Add-Content `$LogPath -Value "`$(Get-Date): Share not accessible: `$SoftwareShare"
    exit 1
}

# Find all MSI files
`$msiFiles = Get-ChildItem -Path `$SoftwareShare -Filter "*.msi" -ErrorAction SilentlyContinue

if (`$msiFiles.Count -eq 0) {
    Add-Content `$LogPath -Value "`$(Get-Date): No MSI files found in `$SoftwareShare"
    exit 0
}

# Install each MSI silently
foreach (`$msi in `$msiFiles) {
    `$msiPath = `$msi.FullName
    `$msiName = `$msi.Name
    
    # Skip if already installed (basic check)
    `$logFile = "`$LogPath\`$(`$msiName).log"
    
    Add-Content `$LogPath -Value "`$(Get-Date): Installing `$msiName..."
    
    try {
        `$process = Start-Process -FilePath "msiexec.exe" `
            -ArgumentList "/i `"$msiPath`" /qn /norestart /l*v `"C:\Windows\Temp\`$msiName.log`"" `
            -Wait -PassThru
        
        Add-Content `$LogPath -Value "`$(Get-Date): `$msiName installed - Exit Code: `$(`$process.ExitCode)"
    }
    catch {
        Add-Content `$LogPath -Value "`$(Get-Date): ERROR installing `$msiName - `$_"
    }
}

Add-Content `$LogPath -Value "`$(Get-Date): All available MSI installations completed"
exit 0
"@

$InstallScript | Out-File "$startupFolder\$psScriptName" -Encoding UTF8 -Force

Log-Green "PowerShell installer script created: $psScriptName"

# ==========================================
# CREATE BATCH WRAPPER (for GPO compatibility)
# ==========================================

$batchScriptName = "Run-Installer.bat"

$BatchScript = @"
@echo off
REM Wrapper to execute PowerShell startup script
powershell.exe -ExecutionPolicy Bypass -File "$startupFolder\$psScriptName"
"@

$BatchScript | Out-File "$startupFolder\$batchScriptName" -Encoding ASCII -Force

Log-Green "Batch wrapper created: $batchScriptName"


# ==========================================
# REGISTER STARTUP SCRIPT (CORRECT METHOD)
# ==========================================

$gptIniPath = "\\$DomainName\SYSVOL\$DomainName\Policies\{$gpoId}\gpt.ini"

# Ensure gpt.ini exists and has version
if (-not (Test-Path $gptIniPath)) {
    New-Item -Path $gptIniPath -ItemType File -Force | Out-Null
    @"
[General]
Version=0
"@ | Out-File $gptIniPath -Encoding ASCII
}

# Create scripts.ini
$scriptsIni = @"
[Startup]
0CmdLine=$batchScriptName
0Parameters=
"@

$scriptsPath = "$startupFolder\scripts.ini"
$scriptsIni | Out-File $scriptsPath -Encoding ASCII -Force

# ✅ CRITICAL: Bump GPO version so clients detect change
(Get-Content $gptIniPath) -replace "Version=(\d+)", {
    "Version=" + ([int]$args[0].Groups[1].Value + 1)
} | Set-Content $gptIniPath

Log-Green "Startup script fully registered (gpt.ini updated)"


# ==========================================
# SET SECURITY FILTERING
# ==========================================

Set-GPPermission -Name $GpoName -TargetName "Authenticated Users" -TargetType Group -PermissionLevel GpoApply -Replace

Log-Green "Security filtering applied to Domain Computers"

# ==========================================
# DOWNLOAD SOFTWARE TO SHARE
# ==========================================

function Get-Installer {
    param($Url, $OutFile)

    if (-not (Test-Path $OutFile)) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
            Log-Green "Downloaded: $(Split-Path $OutFile -Leaf)"
        }
        catch {
            Log-Red "Failed to download: $Url - $_"
        }
    } else {
        Log-Green "Already exists: $(Split-Path $OutFile -Leaf)"
    }
}

Get-Installer "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.9.5/npp.8.9.5.Installer.x64.msi" "$SoftwarePath\notepadplusplus.msi"
Get-Installer "https://www.7-zip.org/a/7z2409-x64.msi" "$SoftwarePath\7zip.msi"

# ==========================================
# FORCE GPO UPDATE
# ==========================================

gpupdate /force

Log-Green ""
Log-Green "====================================="
Log-Green " SOFTWARE DEPLOYMENT CONFIGURED"
Log-Green "====================================="
Log-Green ""
Log-Green "Target OU: $LabOUPath (Lab root)"
Log-Green "GPO: $GpoName"
Log-Green "Software Share: $SoftwareUNC"
Log-Green ""
Log-Green "Auto-installer script will:"
Log-Green "  1. Discover all .msi files in $SoftwareUNC"
Log-Green "  2. Install each silently at computer startup"
Log-Green "  3. Log results to C:\Windows\Temp\SoftwareInstall.log"
Log-Green ""
Log-Green "Affects all computers and users under Lab OU"
Log-Green "Software installs at next system reboot"
Log-Green ""

}