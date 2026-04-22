<# 
    Shared Folder Functions for Windows Server DC Automation
#>

<#
.SYNOPSIS
    Creates shared folder structure
#>
function Add-SharedFolders {
    param(
        [xml]$Config
    )
    
    $folders = $Config.Configuration.SharedFolders.Folder
    
    Write-Log "Creating shared folder structure..."
    
    try {
        foreach ($folder in $folders) {
            $path = $folder.Path
            $name = $folder.Name
            
            # Create directory if not exists
            if (-not (Test-Path $path)) {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
                Write-Log "  ✓ Created directory: $path"
            } else {
                Write-Log "  ↻ Directory already exists: $path"
            }
            
            # Set NTFS permissions
            $acl = Get-Acl $path
            
            # Clear inherited permissions
            $acl.SetAccessRuleProtection($true, $false)
            
            # Add permissions based on configuration
            $permissions = $folder.Permission -split ','
            foreach ($permission in $permissions) {
                $parts = $permission.Trim() -split ':'
                $identity = $parts[0].Trim()
                $accessLevel = $parts[1].Trim()
                
                # Convert access level to FileSystemRights
                $fileSystemRights = switch ($accessLevel) {
                    "Read" { [System.Security.AccessControl.FileSystemRights]::ReadAndExecute }
                    "ReadWrite" { [System.Security.AccessControl.FileSystemRights]::Modify }
                    "FullControl" { [System.Security.AccessControl.FileSystemRights]::FullControl }
                    default { [System.Security.AccessControl.FileSystemRights]::Read }
                }
                
                $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                    $identity,
                    $fileSystemRights,
                    [System.Security.AccessControl.InheritanceFlags]"ContainerInherit, ObjectInherit",
                    [System.Security.AccessControl.PropagationFlags]::None,
                    [System.Security.AccessControl.AccessControlType]::Allow
                )
                
                $acl.AddAccessRule($rule)
            }
            
            Set-Acl -Path $path -AclObject $acl -ErrorAction Stop
            Write-Log "    Permissions configured for: $name"
        }
        
        Write-Log "✓ Shared folders created successfully" -Verbose
        return $true
    } catch {
        Write-Log "✗ Failed to create shared folders: $_" -IsError
        return $false
    }
}

<#
.SYNOPSIS
    Creates SMB shares
#>
function Add-SmbShares {
    param(
        [xml]$Config
    )
    
    $folders = $Config.Configuration.SharedFolders.Folder
    
    Write-Log "Creating SMB shares..."
    
    try {
        foreach ($folder in $folders) {
            $path = $folder.Path
            $name = $folder.Name
            
            # Check if share already exists
            $existingShare = Get-SmbShare -Name $name -ErrorAction SilentlyContinue
            
            if (-not $existingShare) {
                New-SmbShare -Name $name `
                    -Path $path `
                    -FullAccess "Everyone" `
                    -ErrorAction Stop | Out-Null
                
                Write-Log "  ✓ Created share: $name -> $path"
            } else {
                Write-Log "  ↻ Share already exists: $name"
            }
        }
        
        Write-Log "✓ SMB shares created successfully" -Verbose
        return $true
    } catch {
        Write-Log "✗ Failed to create SMB shares: $_" -IsError
        return $false
    }
}

<#
.SYNOPSIS
    Configures share permissions
#>
function Set-SharePermissions {
    param(
        [string]$ShareName,
        [string]$Identity,
        [string]$Permission
    )
    
    $permissionMap = @{
        "Read" = "Change"
        "ReadWrite" = "Change"
        "FullControl" = "Full"
    }
    
    try {
        $permissionLevel = $permissionMap[$Permission]
        Grant-SmbShareAccess -Name $ShareName -AccountName $Identity `
            -AccessRight $permissionLevel -Force -ErrorAction Stop | Out-Null
        
        Write-Log "✓ Permissions set: $ShareName -> $Identity ($Permission)" -Verbose
        return $true
    } catch {
        Write-Log "✗ Failed to set share permissions: $_" -IsError
        return $false
    }
}

<#
.SYNOPSIS
    Gets list of created shares
#>
function Get-ConfiguredShares {
    param(
        [xml]$Config
    )
    
    $shares = @()
    foreach ($folder in $Config.Configuration.SharedFolders.Folder) {
        $shares += @{
            Name = $folder.Name
            Path = $folder.Path
            Permission = $folder.Permission
        }
    }
    
    return $shares
}

<#
.SYNOPSIS
    Verifies shared folder creation
#>
function Test-SharedFolders {
    param(
        [xml]$Config
    )
    
    Write-Log "Verifying shared folders..."
    
    try {
        $shares = Get-SmbShare -ErrorAction Stop
        
        foreach ($folder in $Config.Configuration.SharedFolders.Folder) {
            $share = $shares | Where-Object { $_.Name -eq $folder.Name }
            
            if ($share) {
                Write-Log "  ✓ Share verified: $($folder.Name)" -Verbose
            } else {
                Write-Log "  ✗ Share not found: $($folder.Name)" -Warning
            }
        }
        
        return $true
    } catch {
        Write-Log "✗ Failed to verify shared folders: $_" -IsError
        return $false
    }
}
