
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

$IP        = "192.168.15.2"
$Prefix    = 24
$Gateway   = "192.168.15.1"
$DNS       = "192.168.15.2"

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
    $StartIP   = "192.168.15.2"
    $EndIP     = "192.168.15.200"
    $Subnet    = "255.255.255.0"
    $Gateway   = "192.168.15.1"
    $DNS       = "192.168.15.2"
    $LeaseTime = "5.00:00:00"

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

    Set-DhcpServerv4OptionValue `
        -ScopeId $ScopeID `
        -Router $Gateway

    Log-Green "Gateway set"

    Set-DhcpServerv4OptionValue `
        -ScopeId $ScopeID `
        -DnsServer $DNS

    Log-Green "DNS set"
    $Exclusions = @(
        "192.168.15.2",
        "192.168.15.3",
        "192.168.15.4",
        "192.168.15.5",
        "192.168.15.6",
        "192.168.15.7",
        "192.168.15.8",
        "192.168.15.9",
        "192.168.15.10",
        "192.168.15.11",
        "192.168.15.12",
        "192.168.15.13",
        "192.168.15.14",
        "192.168.15.15",
        "192.168.15.16",
        "192.168.15.17",
        "192.168.15.18",
        "192.168.15.19",
        "192.168.15.20",
        "192.168.15.21"
    )

    foreach ($ip in $Exclusions) {
        try {
            Add-DhcpServerv4ExclusionRange -ScopeId $ScopeID -StartRange $ip -EndRange $ip -ErrorAction Stop
            Log-Green "Excluded IP: $ip"
        }
        catch {
            Log-Red "Failed to exclude: $ip"
        }
    }

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
        "Economics_Sales",
        "Logistics",
        "ServiceAccounts",
        "Activity_Hosts"
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

    $Groups = @("LeadTeam", "HMS", "Economics_Sales", "Logistics", "ServiceAccounts", "Activity_Hosts", "IT")
    
    foreach ($GroupName in $Groups) {
        if (-not (Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction SilentlyContinue)) {
            New-ADGroup -Name $GroupName -GroupScope Global -Path $DomainDN
            Log-Green "Created group: $GroupName"
        }
    }

    function Create-User {
        param($Name, $OU)

        # Generate valid SamAccountName from full name (firstname.lastname, max 20 chars)
        $nameParts = $Name -split " "
        $samAccountName = if ($nameParts.Count -ge 2) {
            "$($nameParts[0]).$($nameParts[-1])".ToLower() -replace "[^a-z0-9.]", ""
        } else {
            $Name.ToLower() -replace "[^a-z0-9]", ""
        }
        
        # Trim to 20 characters if needed
        if ($samAccountName.Length -gt 20) {
            $samAccountName = $samAccountName.Substring(0, 20)
        }

        $userPath = "OU=$OU,$rootPath"

        if (-not (Get-ADUser -Filter "SamAccountName -eq '$samAccountName'" -ErrorAction SilentlyContinue)) {
            try {
                $password = ConvertTo-SecureString "Temp123!" -AsPlainText -Force
                New-ADUser `
                    -Name $Name `
                    -SamAccountName $samAccountName `
                    -GivenName $nameParts[0] `
                    -Surname $nameParts[-1] `
                    -UserPrincipalName "$samAccountName@$($Domain.DNSRoot)" `
                    -Path $userPath `
                    -AccountPassword $password `
                    -Enabled $true -ErrorAction Stop

                Set-ADUser -Identity $samAccountName -ChangePasswordAtLogon $true

                Log-Green "Created user: $Name (sam: $samAccountName) in $OU"
            } catch {
                Log-Red "Failed to create user $Name : $_"
            }
        } else {
            Log-Green "User $samAccountName already exists"
        }
    }
Create-User "Maria Solberg" "LeadTeam"
Create-User "Henrik Dahl" "Economics_Sales"
Create-User "Emil Karlsen" "IT"
Create-User "Kristine Johansen" "Logistics"
Create-User "Nora Hansen" "ServiceAccounts"
Create-User "Sindre Olsen" "ServiceAccounts"
Create-User "Julie Berg" "Activity_Hosts"
Create-User "Tobias Nilsen" "Activity_Hosts"
Create-User "Amalie Lund" "Activity_Hosts"


Add-ADGroupMember -Identity "LeadTeam" -Members "Maria Solberg"
Add-ADGroupMember -Identity "Economics_Sales" -Members "Henrik Dahl"
Add-ADGroupMember -Identity "IT" -Members "Emil Karlsen"
Add-ADGroupMember -Identity "Logistics" -Members "Kristine Johansen"
Add-ADGroupMember -Identity "ServiceAccounts" -Members "Nora Hansen", "Sindre Olsen"
Add-ADGroupMember -Identity "Activity_Hosts" -Members "Julie Berg", "Tobias Nilsen", "Amalie Lund"
Log-Green "Added users to OU and groups"

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
    $BasePath = "P:\Shares"
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


$gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue

if (-not $gpo) {
    $gpo = New-GPO -Name $GpoName
    Log-Green "Created GPO: $GpoName"
}
else {
    Log-Green "GPO already exists"
}


$existingLinks = (Get-GPInheritance -Target $RootPath).GpoLinks.DisplayName

if ($existingLinks -notcontains $GpoName) {
    New-GPLink -Name $GpoName -Target $RootPath -LinkEnabled Yes | Out-Null
    Log-Green "Linked GPO to LAB root OU"
}
else {
    Log-Green "GPO already linked to LAB OU"
}

Set-GPPermission -Name $GpoName -TargetName "Authenticated Users" -TargetType Group -PermissionLevel GpoApply


# GPP registry-based mapping method, very fun

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

# Attempted auto software deployment, doesnt quite work, but makes the manuall job easier later
if (Confirm-Step "set up software deployment via GPO?") {

    Import-Module ActiveDirectory
    Import-Module GroupPolicy

    $Domain     = Get-ADDomain
    $DomainDN   = $Domain.DistinguishedName
    $DomainName = $Domain.DNSRoot
    $Server     = $env:COMPUTERNAME
    # by making the structure
    $RootOU       = "Lab"
    $LabOU        = "OU=$RootOU,$DomainDN"
    $ComputerOU   = "OU=Computers,$LabOU"

    $GpoName      = "Software-Deployment"

    $BasePath     = "P:\Shares"
    $SoftwarePath = "$BasePath\Software"
    $SoftwareUNC  = "\\$Server.$DomainName\Software"

    redircmp $ComputerOU
    Log-Green "Default computer location set to Lab OU"

    # Move existing computers to the correct OU to apply GPO to them
    Get-ADComputer -Filter * | ForEach-Object {
        try { Move-ADObject $_.DistinguishedName -TargetPath $ComputerOU -ErrorAction Stop } catch {}
    }

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
    # Download it in the previously set up paths
    Invoke-WebRequest -Uri "https://www.7-zip.org/a/7z2409-x64.msi" `
        -OutFile "$SoftwarePath\7zip.msi" -UseBasicParsing

    Invoke-WebRequest -Uri "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.9.5/npp.8.9.5.Installer.x64.msi" `
        -OutFile "$SoftwarePath\npp.msi" -UseBasicParsing

    Log-Green "Software downloaded"

    $gpo = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue
    if (-not $gpo) { $gpo = New-GPO -Name $GpoName }

    if (-not ((Get-GPInheritance -Target $LabOU).GpoLinks.DisplayName -contains $GpoName)) {
        New-GPLink -Name $GpoName -Target $LabOU -LinkEnabled Yes | Out-Null
    }
    # And allowing them to access the software
    Set-GPPermission -Name $GpoName `
        -TargetName "Authenticated Users" `
        -TargetType Group `
        -PermissionLevel GpoApply -Replace

    Log-Green "GPO ready and linked"


$gpoID = $gpo.Id.ToString()

$scriptFolder = "\\$DomainName\SYSVOL\$DomainName\Policies\{$gpoID}\Machine\Scripts\Startup"
New-Item -ItemType Directory -Path $scriptFolder -Force | Out-Null

$scriptFile = "$scriptFolder\install.ps1"
# This is where it fails tho as i cant find a good method for Logon to actually run the script and apply it. The issue is most likely permission to run the installers
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

$batchScriptName = "run-installer.bat"

@"
@echo off
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "\\$DomainName\SYSVOL\$DomainName\Policies\{$gpoID}\Machine\Scripts\Startup\install.ps1"
"@ | Out-File "$scriptFolder\$batchScriptName" -Encoding ASCII -Force

$scriptsIniPath = "$scriptFolder\scripts.ini"

@"
[Startup]
0CmdLine=$batchScriptName
0Parameters=
"@ | Out-File $scriptsIniPath -Encoding ASCII -Force

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
        Add-Content $gptIni "`nVersion=1"
    }
}

# and so it doesnt really work as i havent figured out how to bypass windows security safely and consistently for this purpose 
Log-Green "Startup script registered CORRECTLY (gpt.ini updated)"

gpupdate /force
}
# This is something completely different, basicly a bunch of pictures i want for the IIS website and desktop wallpaper for all computer under the domain


if (Confirm-Step "create IIS website?") {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $url = "https://api.github.com/repos/Kentanto/windows-server-ps1-script/contents?ref=master"

    try {
        $items = Invoke-RestMethod -Uri $url -Headers @{ "User-Agent" = "PowerShell" }
    }
    catch {
        Log-Red "GitHub API failed"
        Log-Red $_
        return
    }

    $images = @($items) | Where-Object {
        $_.type -eq "file" -and $_.name -match "\.(png|jpg|jpeg|gif|webp)$"
    }
    Import-Module WebAdministration

    $sitePath = "C:\inetpub\wwwroot"

    if (-not (Test-Path $sitePath)) {
        New-Item -ItemType Directory -Path $sitePath -Force | Out-Null
    }

    Get-ChildItem $sitePath -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    
    # Funny way to automatically make website on the server XD i love this way.
    $html = @"
<!DOCTYPE html>
<html lang="no">
<head>
    <meta charset="UTF-8">
    <title>Innlandet Aktivitetsenter AS</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>

    <div class="hero">
        <h1>Welcome to Innlandet Aktivitetsenter AS, Dette er vår første testside</h1>

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

    foreach ($img in $images) {

        $outPath = Join-Path $sitePath $img.name

        try {
            Invoke-WebRequest `
                -Uri $img.download_url `
                -OutFile $outPath `
                -Headers @{ "User-Agent" = "Mozilla/5.0" }

            Log-Green "IIS downloaded: $($img.name)"
        }
        catch {
            Log-Red "IIS failed: $($img.name)"
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

    foreach ($img in $images) {

        $outPath = Join-Path $wallDir $img.name

        try {
            Invoke-WebRequest `
                -Uri $img.download_url `
                -OutFile $outPath `
                -Headers @{ "User-Agent" = "Mozilla/5.0" }

            Log-Green "GPO downloaded: $($img.name)"
        }
        catch {
            Log-Red "GPO failed: $($img.name)"
        }
    }

    if (-not (Get-GPO -Name $gpoName -ErrorAction SilentlyContinue)) {
        New-GPO -Name $gpoName | Out-Null
    }

    $wallpaperFile = ($images | Where-Object { $_.name -match "background" }).name
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