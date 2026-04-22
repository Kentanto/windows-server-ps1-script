# Windows Server 2025 Domain Controller Automation

Automated setup and configuration of Windows Server 2025 as a domain controller for havgap-camping.no

## Project Structure

```
├── config/
│   ├── server-config.xml          # Main configuration file
│   └── credentials-template.xml   # Template for credentials (DO NOT COMMIT)
├── Step1-PreDCPromotion.ps1       # Pre-promotion script
├── Step2-PostDCPromotion.ps1      # Post-promotion script
├── includes/
│   ├── Functions-Common.ps1       # Shared functions
│   ├── Functions-Network.ps1      # Network configuration functions
│   ├── Functions-AD.ps1           # Active Directory functions
│   ├── Functions-GPO.ps1          # Group Policy functions
│   └── Functions-Roles.ps1        # Role installation functions
├── logs/                          # Execution logs
└── SETUP_GUIDE.md                # Detailed setup instructions
```

## Execution Flow

### Phase 1: Pre-DC Promotion (Step1-PreDCPromotion.ps1)
1. Load configuration
2. Rename computer
3. Configure static IP
4. Install required roles (DHCP, DNS, IIS)
5. Create shared folder structure
6. Prepare for promotion

### Phase 2: Post-DC Promotion (Step2-PostDCPromotion.ps1)
*Runs after server restart following DC promotion*

1. Verify DC promotion success
2. Create AD structure (OUs, groups, users)
3. Configure Group Policies (disable password restrictions, Ctrl+Alt+Del, drive mappings)
4. Configure DHCP scopes
5. Configure DNS zones
6. Finalize sharing and permissions

## Prerequisites

- Windows Server 2025 (fresh installation)
- Administrator privileges
- Execution policy allows script execution
- Network connectivity to 192.168.5.1 gateway

## Configuration

Edit `config/server-config.xml` before running scripts.

## Usage

```powershell
# Step 1: Pre-DC Promotion
.\Step1-PreDCPromotion.ps1

# Server will restart. After restart, run:
# Step 2: Post-DC Promotion
.\Step2-PostDCPromotion.ps1
```

## Logs

All operations are logged to `logs/` directory with timestamps.

## Security Notes

- Credentials are loaded from config file - never commit credentials to source control
- Use secure file permissions on config files
- Review all scripts before executing in production
