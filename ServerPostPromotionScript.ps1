
# ===== Function to confirm each step with user =====
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
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

$IP        = "192.168.15.177"
$Prefix    = 24
$Gateway   = "192.168.15.1"
$DNS       = "192.168.15.1"

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
    $ScopeID   = "192.168.15.0"
    $StartIP   = "192.168.15.150"
    $EndIP     = "192.168.15.200"
    $Subnet    = "255.255.255.0"
    $Gateway   = "192.168.15.1"
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

    # ===== DOMAIN INFO =====
    $Domain     = Get-ADDomain
    $DomainDN   = $Domain.DistinguishedName
    $DomainName = $Domain.DNSRoot
    $Server     = $env:COMPUTERNAME

    # ===== CONFIG =====
    $RootOU       = "Lab"
    $LabOU        = "OU=$RootOU,$DomainDN"
    $ComputerOU   = "OU=Computers,$LabOU"

    $GpoName      = "Software-Deployment"

    $BasePath     = "D:\Shares"
    $SoftwarePath = "$BasePath\Software"
    $SoftwareUNC  = "\\$Server.$DomainName\Software"

    # ==========================================
    # ✅ ENSURE COMPUTERS GO INTO LAB OU
    # ==========================================
    redircmp $ComputerOU
    Log-Green "Default computer location set to Lab OU"

    # Move existing computers (IMPORTANT)
    Get-ADComputer -Filter * | ForEach-Object {
        try { Move-ADObject $_.DistinguishedName -TargetPath $ComputerOU -ErrorAction Stop } catch {}
    }

    # ==========================================
    # ✅ CREATE SOFTWARE SHARE
    # ==========================================
    New-Item -ItemType Directory -Path $SoftwarePath -Force | Out-Null

    if (-not (Get-SmbShare -Name "Software" -ErrorAction SilentlyContinue)) {
        New-SmbShare -Name "Software" -Path $SoftwarePath `
            -FullAccess "Administrators" `
            -ReadAccess "Domain Computers" | Out-Null
    }

    icacls $SoftwarePath /inheritance:r | Out-Null
    icacls $SoftwarePath /grant "Administrators:(OI)(CI)F" | Out-Null
    icacls $SoftwarePath /grant "Domain Computers:(OI)(CI)RX" | Out-Null

    Log-Green "Software share ready"

    # ==========================================
    # ✅ DOWNLOAD SOFTWARE
    # ==========================================
    Invoke-WebRequest -Uri "https://www.7-zip.org/a/7z2409-x64.msi" `
        -OutFile "$SoftwarePath\7zip.msi" -UseBasicParsing

    Invoke-WebRequest -Uri "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.9.5/npp.8.9.5.Installer.x64.msi" `
        -OutFile "$SoftwarePath\npp.msi" -UseBasicParsing

    Log-Green "Software downloaded"

    # ==========================================
    # ✅ CREATE GPO + LINK
    # ==========================================
    $gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue
    if (-not $gpo) { $gpo = New-GPO -Name $GpoName }

    if (-not ((Get-GPInheritance -Target $LabOU).GpoLinks.DisplayName -contains $GpoName)) {
        New-GPLink -Name $GpoName -Target $LabOU -LinkEnabled Yes | Out-Null
    }

    # IMPORTANT: ALLOW ALL COMPUTERS
    Set-GPPermission -Name $GpoName `
        -TargetName "Authenticated Users" `
        -TargetType Group `
        -PermissionLevel GpoApply -Replace

    Log-Green "GPO ready and linked"


# ==========================================
# ✅ CREATE STARTUP SCRIPT (PROPER WAY)
# ==========================================
$gpoID = $gpo.Id.ToString()

$scriptFolder = "\\$DomainName\SYSVOL\$DomainName\Policies\{$gpoID}\Machine\Scripts\Startup"
New-Item -ItemType Directory -Path $scriptFolder -Force | Out-Null

$scriptFile = "$scriptFolder\install.ps1"

@"
Start-Sleep 30

`$share = "$SoftwareUNC"
`$log   = "C:\Windows\Temp\install.log"

Add-Content `$log "`$(Get-Date): START"

if (-not (Test-Path `$share)) {
    Add-Content `$log "Share not ready"
    exit
}

Get-ChildItem `$share -Filter *.msi | ForEach-Object {

    `$file = `$_.FullName
    `$name = `$_.Name

    Add-Content `$log "Installing `$name"

    Start-Process msiexec.exe -ArgumentList "/i `"`$file`" /qn /norestart" -Wait

    Add-Content `$log "Done `$name"
}

Add-Content `$log "FINISHED"
"@ | Out-File $scriptFile -Encoding UTF8 -Force

# ==========================================
# ✅ CREATE BATCH WRAPPER (FIXED PATH)
# ==========================================
$batchScriptName = "run-installer.bat"

@"
@echo off
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "\\$DomainName\SYSVOL\$DomainName\Policies\{$gpoID}\Machine\Scripts\Startup\install.ps1"
"@ | Out-File "$scriptFolder\$batchScriptName" -Encoding ASCII -Force

# ==========================================
# ✅ REGISTER SCRIPT (REAL WAY)
# ==========================================
$scriptsIniPath = "$scriptFolder\scripts.ini"

@"
[Startup]
0CmdLine=$batchScriptName
0Parameters=
"@ | Out-File $scriptsIniPath -Encoding ASCII -Force

# ==========================================
# ✅ BUMP GPO VERSION (THIS WAS MISSING)
# ==========================================

$gptIni = "\\$DomainName\SYSVOL\$DomainName\Policies\{$gpoID}\gpt.ini"

if (-not (Test-Path $gptIni)) {
    @"
[General]
Version=1
"@ | Out-File $gptIni -Encoding ASCII
}
else {
    $content = Get-Content $gptIni -Raw

    if ($content -match "Version=(\d+)") {
        $currentVersion = [int]$Matches[1]
        $newVersion = $currentVersion + 1

        $content = $content -replace "Version=\d+", "Version=$newVersion"
        $content | Set-Content $gptIni
    }
    else {
        # fallback if Version line missing
        Add-Content $gptIni "`nVersion=1"
    }
}


Log-Green "Startup script registered CORRECTLY (gpt.ini updated)"

# ==========================================
# ✅ FINAL
# ==========================================
gpupdate /force
}

if (Confirm-Step "create IIS website?") {

    Import-Module WebAdministration

    $sitePath = "C:\inetpub\wwwroot"

    if (-not (Test-Path $sitePath)) {
        New-Item -ItemType Directory -Path $sitePath -Force | Out-Null
    }

    # CLEAR EXISTING CONTENT
    Get-ChildItem $sitePath -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    $html = @"
<!DOCTYPE html>
<html lang="no">
<head>
    <meta charset="UTF-8">
    <title>Kriseberedskap AS</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>

    <div class="hero">
        <h1>Welcome to Kriseberedaskap AS, her er vi alle F.Orebredt.</h1>

        <div class="buttons">
            <button>Om oss</button>
            <button>Tjenester</button>
            <button>Kontakt</button>
        </div>
    </div>

    <div class="gallery">
        <img src="image1.png">
        <img src="image2.png">
        <img src="image3.png">
        <img src="image4.png">
    </div>

</body>
</html>
"@

    $css = @"
body {
    margin: 0;
    font-family: Arial, sans-serif;
    background: url('image1.png') no-repeat center center fixed;
    background-size: cover;
    color: white;
}

.hero {
    text-align: center;
    padding: 80px 20px;
    background: rgba(0,0,0,0.6);
}

.buttons button {
    margin: 10px;
    padding: 12px 20px;
    border: none;
    cursor: pointer;
    background: #1e90ff;
    color: white;
    border-radius: 6px;
}

.buttons button:hover {
    background: #0f78d1;
}

.gallery {
    display: flex;
    justify-content: center;
    gap: 10px;
    padding: 40px;
}

.gallery img {
    width: 150px;
    height: auto;
    border-radius: 8px;
    border: 2px solid white;
}
"@

    Set-Content -Path "$sitePath\index.html" -Value $html -Encoding UTF8
    Set-Content -Path "$sitePath\style.css" -Value $css -Encoding UTF8
    

    $images = @(
    "https://raw.githubusercontent.com/Kentanto/windows-server-ps1-script/master/image1.png",
    "https://raw.githubusercontent.com/Kentanto/windows-server-ps1-script/master/image2.png",
    "https://raw.githubusercontent.com/Kentanto/windows-server-ps1-script/master/image3.png",
    "https://raw.githubusercontent.com/Kentanto/windows-server-ps1-script/master/image4.png"
)

    foreach ($img in $images) {

    $fileName = Split-Path $img -Leaf
    $outPath = "$wallDir\$fileName"

    if (-not (Test-Path $outPath)) {

        try {
            Invoke-WebRequest `
                -Uri $img `
                -OutFile $outPath `
                -UseBasicParsing `
                -Headers @{ "User-Agent" = "Mozilla/5.0" }

            Log-Green "Downloaded: $fileName"
        }
        catch {
            Log-Red "Failed: $img"
            Log-Red $_
        }
    }
}

    Start-Service W3SVC -ErrorAction SilentlyContinue
    iisreset | Out-Null

    Log-Green "Clean IIS site deployed to http://localhost"
}

if (Confirm-Step "deploy automatic wallpaper GPO for all users?") {

    Import-Module GroupPolicy
    Import-Module ActiveDirectory

    $domain = Get-ADDomain
    $domainName = $domain.DNSRoot
    $domainDN = $domain.DistinguishedName

    $gpoName = "Force-Global-Wallpaper"

    $wallDir = "\\$domainName\SYSVOL\$domainName\scripts\Wallpapers"

    if (-not (Test-Path $wallDir)) {
        New-Item -ItemType Directory -Path $wallDir -Force | Out-Null
    }

    $images = @(
    "https://raw.githubusercontent.com/Kentanto/windows-server-ps1-script/master/background_image.png"
)

    foreach ($img in $images) {

    $fileName = Split-Path $img -Leaf
    $outPath = "$wallDir\$fileName"

    if (-not (Test-Path $outPath)) {

        try {
            Invoke-WebRequest `
                -Uri $img `
                -OutFile $outPath `
                -UseBasicParsing `
                -Headers @{ "User-Agent" = "Mozilla/5.0" }

            Log-Green "Downloaded: $fileName"
        }
        catch {
            Log-Red "Failed: $img"
            Log-Red $_
        }
    }
}

    if (-not (Get-GPO -Name $gpoName -ErrorAction SilentlyContinue)) {
        New-GPO -Name $gpoName | Out-Null
    }

    $wallpaperFile = "background_image.png"
    $wallpaperPath = "\\$domainName\SYSVOL\$domainName\scripts\Wallpapers\$wallpaperFile"

    Set-GPRegistryValue -Name $gpoName `
        -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
        -ValueName "Wallpaper" `
        -Type String `
        -Value $wallpaperPath

    Set-GPRegistryValue -Name $gpoName `
        -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
        -ValueName "WallpaperStyle" `
        -Type String `
        -Value "2"

    Set-GPRegistryValue -Name $gpoName `
        -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop" `
        -ValueName "NoChangingWallPaper" `
        -Type DWord `
        -Value 1

    $existing = (Get-GPInheritance -Target $domainDN).GpoLinks.DisplayName

    if ($existing -notcontains $gpoName) {
        New-GPLink -Name $gpoName -Target $domainDN -LinkEnabled Yes | Out-Null
    }

    gpupdate /force

    Log-Green "Wallpaper GPO deployed to entire domain"
}