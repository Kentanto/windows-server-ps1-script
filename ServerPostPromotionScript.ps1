
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
    }
} else {
    Log-Green "Skipping IP configuration"
}

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
        "IT"
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
    $Server   = $env:COMPUTERNAME
    $Domain   = Get-ADDomain
    $DomainDN = $Domain.DistinguishedName

    foreach ($path in @($BasePath, $WorkPath, $LeadPath)) {
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

    Ensure-Share "Work" $WorkPath "Domain Users"
    Ensure-Share "LeadTeam" $LeadPath "LeadTeam"


    $gpoWork = "DriveMap-Work"
    New-GPO -Name $gpoWork | Out-Null
    Log-Green "Created GPO: $gpoWork"


$targetOU = "OU=Lab,$DomainDN"

if ((Get-GPInheritance -Target $targetOU).GpoLinks.DisplayName -notcontains $gpoWork) {
    New-GPLink -Name $gpoWork -Target $targetOU -LinkEnabled Yes | Out-Null
}

$gpoIdWork = (Get-GPO $gpoWork).Id
$gpoPathWork = "\\$($Domain.DNSRoot)\SYSVOL\$($Domain.DNSRoot)\Policies\{$gpoIdWork}\User\Preferences\Drives"

New-Item -ItemType Directory -Path $gpoPathWork -Force | Out-Null

@"
<Drives clsid="{C631DF4C-088F-4156-B058-4375F0853CD8}">
    <Drive name="Work Drive" status="Enabled">
        <Properties action="U" letter="W" path="\\$Server\Work" />
    </Drive>
</Drives>
"@ | Out-File "$gpoPathWork\Drives.xml" -Encoding UTF8

Log-Green "Work drive mapped"

$gpoLead = "DriveMap-LeadTeam"

if (-not (Get-GPO -Name $gpoLead -ErrorAction SilentlyContinue)) {
    New-GPO -Name $gpoLead | Out-Null
}

$leadOU = "OU=LeadTeam,OU=Lab,$DomainDN"

if ((Get-GPInheritance -Target $leadOU).GpoLinks.DisplayName -notcontains $gpoLead) {
    New-GPLink -Name $gpoLead -Target $leadOU -LinkEnabled Yes | Out-Null
}

$gpoIdLead = (Get-GPO $gpoLead).Id
    $gpoPathLead = "\\$($Domain.DNSRoot)\SYSVOL\$($Domain.DNSRoot)\Policies\{$gpoIdLead}\User\Preferences\Drives"

    New-Item -ItemType Directory -Path $gpoPathLead -Force | Out-Null

    @"
<Drives clsid="{C631DF4C-088F-4156-B058-4375F0853CD8}">
    <Drive name="LeadTeam Drive" status="Enabled">
        <Properties action="U" letter="L" path="\\$Server\LeadTeam" />
    </Drive>
</Drives>
"@ | Out-File "$gpoPathLead\Drives.xml" -Encoding UTF8

    Log-Green "LeadTeam drive mapped"

    gpupdate /force
    Log-Green "Done - log off and log back in"
}
# ===== AUTO DRIVE MAPPING (WORKING METHOD) =====

if (Confirm-Step "configure automatic drive mapping?") {
    
    $Domain = Get-ADDomain
    $DomainName = $Domain.DNSRoot
    $Server = $env:COMPUTERNAME

    $ScriptName = "map-drives.bat"
    $ScriptPath = "\\$DomainName\NETLOGON\$ScriptName"

    if (-not (Test-Path $ScriptPath)) {
        $ScriptContent = @"
net use W: /delete /yes >nul 2>&1
net use W: \\$Server /persistent:no
"@

        $ScriptContent | Out-File $ScriptPath -Encoding ASCII
        Log-Green "Created logon script in NETLOGON"
    } else {
        Log-Green "Logon script already exists"
    }

    $Users = @("Hans", "Live", "Kine")

    foreach ($user in $Users) {
        try {
            Set-ADUser -Identity $user -ScriptPath $ScriptName
            Log-Green "Assigned script to $user"
        } catch {
            Log-Red "Failed to assign script to $user"
        }
    }

    gpupdate /force
    Log-Green "Done - LOG OFF and log back in as user"
}

# ===== SOFTWARE DEPLOYMENT (ALL-IN-ONE) =====

if (Confirm-Step "deploy software to clients?") {

Import-Module GroupPolicy
Import-Module ActiveDirectory

$Domain = Get-ADDomain
$DomainDN = $Domain.DistinguishedName
$DomainName = $Domain.DNSRoot

$Server = $env:COMPUTERNAME

# ===== PATHS =====
$SoftwarePath = "D:\Software"
$ShareName = "Software"

# ===== CREATE SOFTWARE FOLDER =====
if (-not (Test-Path $SoftwarePath)) {
    New-Item -ItemType Directory -Path $SoftwarePath -Force | Out-Null
    Log-Green "Created software folder"
} else {
    Log-Green "Software folder exists"
}

# ===== SHARE IT =====
if (-not (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue)) {
    New-SmbShare -Name $ShareName -Path $SoftwarePath -ReadAccess "Domain Computers" | Out-Null
    Log-Green "Created software share"
} else {
    Log-Green "Software share exists"
}

# ===== APP RECIPE =====
# ADD INSTALLERS HERE (place files manually in D:\Software)

# ===== DOWNLOAD INSTALLERS =====

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
            log-red "Error: $_"
        }
    }
    else {
        Log-Green "Already exists: $OutFile"
    }
}

# Notepad++
Get-Installer `
    -Url "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/latest/download/npp.8.9.4.Installer.x64.msi" `
    -OutFile "$SoftwarePath\notepadpp.msi"

# 7-Zip
Get-Installer `
    -Url "https://www.7-zip.org/a/7z2301-x64.exe" `
    -OutFile "$SoftwarePath\7zip.exe"

$Apps = @(
    @{
        Name = "NotepadPP"
        File = "notepadpp.msi"
        Args = "/S"
        Check = "C:\Program Files\Notepad++\notepad++.exe"
        Shortcut = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Notepad++.lnk"
    },
    @{
        Name = "7zip"
        File = "7zip.exe"
        Args = "/S"
        Check = "C:\Program Files\7-Zip\7z.exe"
        Shortcut = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\7-Zip.lnk"
    }
)

# ===== CREATE INSTALL SCRIPT CONTENT =====
$scriptContent = @"
`$share = "\\$Server\$ShareName"

function Install-App {
    param(`$name, `$file, `$args, `$check)

    if (-not (Test-Path `$check)) {
        Start-Process "`$share\`$file" -ArgumentList `$args -Wait
    }
}

`$desktop = "C:\Users\Public\Desktop"
`$shell = New-Object -ComObject WScript.Shell

"@

foreach ($app in $Apps) {

$scriptContent += @"

Install-App "$($app.Name)" "$($app.File)" "$($app.Args)" "$($app.Check)"

if (Test-Path "$($app.Check)") {
    `$sc = `$shell.CreateShortcut("`$desktop\$($app.Name).lnk")
    `$sc.TargetPath = "$($app.Check)"
    `$sc.Save()
}

"@
}

# ===== CREATE GPO =====
$gpoName = "Software-Deploy"

if (-not (Get-GPO -Name $gpoName -ErrorAction SilentlyContinue)) {
    New-GPO -Name $gpoName | Out-Null
    Log-Green "Created GPO"
}

# Link to Computers OU
$targetOU = (Get-ADOrganizationalUnit -Filter "Name -eq 'Computers'" -SearchBase $DomainDN).DistinguishedName

if ((Get-GPInheritance -Target $targetOU).GpoLinks.DisplayName -notcontains $gpoName) {
    New-GPLink -Name $gpoName -Target $targetOU -LinkEnabled Yes | Out-Null
    Log-Green "Linked GPO to Computers OU"
}

# ===== PLACE SCRIPT IN GPO =====
$gpoId = (Get-GPO $gpoName).Id
$scriptFolder = "\\$DomainName\SYSVOL\$DomainName\Policies\{$gpoId}\Machine\Scripts\Startup"

New-Item -ItemType Directory -Path $scriptFolder -Force | Out-Null

$scriptFile = "$scriptFolder\install-apps.ps1"
$scriptContent | Out-File $scriptFile -Encoding ASCII

# ===== CREATE scripts.ini =====
@"
[Startup]
0CmdLine=powershell.exe
0Parameters=-ExecutionPolicy Bypass -File install-apps.ps1
"@ | Out-File "$scriptFolder\scripts.ini" -Encoding ASCII

Log-Green "Startup script deployed"

# ===== FORCE POLICY =====
gpupdate /force

Log-Green "DONE - reboot client to install apps"
}

# sets up everything but still doesnt quite make auto installing work, set up new clones and try again