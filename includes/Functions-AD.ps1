<# 
    Active Directory Functions for Windows Server DC Automation
#>

<#
.SYNOPSIS
    Renames the computer and returns hostname
#>
function Rename-ServerComputer {
    param(
        [xml]$Config
    )
    
    $newName = $Config.Configuration.Server.ComputerName
    $currentName = $env:COMPUTERNAME
    
    if ($currentName -eq $newName) {
        Write-Log "✓ Computer already named: $newName" -Verbose
        return $true
    }
    
    Write-Log "Renaming computer from $currentName to $newName"
    
    try {
        Rename-Computer -NewName $newName -Force -ErrorAction Stop
        Write-Log "✓ Computer renamed to: $newName" -Verbose
        Write-Log "  Restart required for name change to take effect"
        return $true
    } catch {
        Write-Log "✗ Failed to rename computer: $_" -IsError
        return $false
    }
}

<#
.SYNOPSIS
    Promotes server to Domain Controller
#>
function Promote-ToDomainController {
    param(
        [xml]$Config,
        [string]$SafeModePassword
    )
    
    $domain = $Config.Configuration.ActiveDirectory.Domain
    $forestLevel = [Microsoft.DirectoryServices.ActiveDirectory.ForestMode]::$($Config.Configuration.ActiveDirectory.ForestFunctionalLevel)
    $domainLevel = [Microsoft.DirectoryServices.ActiveDirectory.DomainMode]::$($Config.Configuration.ActiveDirectory.DomainFunctionalLevel)
    
    Write-Log "Promoting server to Domain Controller for domain: $domain"
    Write-Log "  Forest Mode: $($Config.Configuration.ActiveDirectory.ForestFunctionalLevel)"
    Write-Log "  Domain Mode: $($Config.Configuration.ActiveDirectory.DomainFunctionalLevel)"
    
    try {
        # Convert password to secure string
        $safeModeSecurePassword = ConvertTo-SecureString $SafeModePassword -AsPlainText -Force
        
        # Install AD DS first if not installed
        Install-WindowsFeature AD-Domain-Services -IncludeManagementTools -ErrorAction Stop | Out-Null
        
        # Promote to DC
        Install-ADDSForest -DomainName $domain `
            -ForestMode $forestLevel `
            -DomainMode $domainLevel `
            -SafeModeAdministratorPassword $safeModeSecurePassword `
            -InstallDns:$true `
            -NoRebootOnCompletion:$false `
            -SkipPreChecks:$false `
            -ErrorAction Stop | Out-Null
        
        Write-Log "✓ Domain Controller promotion initiated" -Verbose
        Write-Log "  Server will restart automatically"
        
        return $true
    } catch {
        Write-Log "✗ Failed to promote Domain Controller: $_" -IsError
        return $false
    }
}

<#
.SYNOPSIS
    Verifies DC promotion success after restart
#>
function Test-DCPromotion {
    param(
        [string]$Domain
    )
    
    Write-Log "Verifying Domain Controller promotion..."
    
    try {
        # Check if domain controller
        $dc = Get-ADDomainController -Identity $env:COMPUTERNAME -ErrorAction Stop
        
        Write-Log "✓ Domain Controller verification successful" -Verbose
        Write-Log "  Domain: $($dc.Domain)"
        Write-Log "  Hostname: $($dc.HostName)"
        Write-Log "  Operating System: $($dc.OperatingSystem)"
        
        return $true
    } catch {
        Write-Log "✗ Domain Controller verification failed: $_" -Warning
        return $false
    }
}

<#
.SYNOPSIS
    Creates Organizational Unit structure
#>
function Create-OUStructure {
    param(
        [xml]$Config
    )
    
    $domain = $Config.Configuration.ActiveDirectory.Domain
    $domainDN = "DC=" + ($domain -replace '\.',',DC=')
    
    Write-Log "Creating Organizational Unit structure for domain: $domain"
    
    try {
        # Create root OUs
        foreach ($ou in $Config.Configuration.OUStructure.OU) {
            $ouPath = "OU=$($ou.Name),$domainDN"
            
            # Check if OU exists
            if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ouPath'" -ErrorAction SilentlyContinue)) {
                New-ADOrganizationalUnit -Name $ou.Name -Path $domainDN -ErrorAction Stop | Out-Null
                Write-Log "  ✓ Created OU: $($ou.Name)"
            } else {
                Write-Log "  ↻ OU already exists: $($ou.Name)"
            }
            
            # Create sub-OUs
            if ($ou.SubOU) {
                foreach ($subOU in $ou.SubOU) {
                    $subOUPath = "OU=$($subOU.Name),$ouPath"
                    
                    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$subOUPath'" -ErrorAction SilentlyContinue)) {
                        New-ADOrganizationalUnit -Name $subOU.Name -Path $ouPath -ErrorAction Stop | Out-Null
                        Write-Log "    ✓ Created Sub-OU: $($subOU.Name)"
                    } else {
                        Write-Log "    ↻ Sub-OU already exists: $($subOU.Name)"
                    }
                }
            }
        }
        
        Write-Log "✓ OU structure created successfully" -Verbose
        return $true
    } catch {
        Write-Log "✗ Failed to create OU structure: $_" -IsError
        return $false
    }
}

<#
.SYNOPSIS
    Creates security groups
#>
function Create-SecurityGroups {
    param(
        [xml]$Config
    )
    
    $domain = $Config.Configuration.ActiveDirectory.Domain
    $domainDN = "DC=" + ($domain -replace '\.',',DC=')
    $groupsOUPath = "OU=Groups,$domainDN"
    
    Write-Log "Creating security groups..."
    
    try {
        foreach ($group in $Config.Configuration.SecurityGroups.Group) {
            $groupName = $group.Name
            
            # Check if group exists
            if (-not (Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue)) {
                New-ADGroup -Name $groupName `
                    -SamAccountName ($groupName -replace ' ', '') `
                    -GroupScope $group.Scope `
                    -GroupCategory Security `
                    -Path $groupsOUPath `
                    -ErrorAction Stop | Out-Null
                
                Write-Log "  ✓ Created group: $groupName"
            } else {
                Write-Log "  ↻ Group already exists: $groupName"
            }
        }
        
        Write-Log "✓ Security groups created successfully" -Verbose
        return $true
    } catch {
        Write-Log "✗ Failed to create security groups: $_" -IsError
        return $false
    }
}

<#
.SYNOPSIS
    Gets domain DN for distinguishedName queries
#>
function Get-DomainDN {
    param(
        [string]$Domain
    )
    
    return "DC=" + ($Domain -replace '\.',',DC=')
}
