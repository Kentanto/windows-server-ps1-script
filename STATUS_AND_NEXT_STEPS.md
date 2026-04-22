# Setup Status & Next Steps

## What Was Fixed [OK]

### 1. **Code Syntax Error** (FIXED)
- **Issue:** Duplicate code at the end of `Functions-Common.ps1` causing syntax errors
- **Status:** [OK] RESOLVED - File cleaned up

### 2. **Missing SafeModePassword** (FIXED)
- **Issue:** `config/server-config.xml` had empty SafeModePassword field
- **Status:** [OK] RESOLVED - Placeholder password added (`ChangeMe@12345`)
- **Action Required:** Replace with your own secure password before running

### 3. **No Running Instructions** (FIXED)
- **Issue:** No clear guide on how to execute on Windows Server 2025 VM
- **Status:** [OK] RESOLVED - Created `RUN_ON_VM.md` with detailed steps

### 4. **PowerShell Warnings** (NOT BLOCKING)
- **Issue:** Some PSScriptAnalyzer warnings about function naming and parameter types
- **Status:** [INFO] DOCUMENTED - These don't prevent execution, see `POWERSHELL_WARNINGS.md`

---

## 📋 Your Checklist - Do This Now

- [ ] **Change SafeModePassword** in `config\server-config.xml`
  ```
  <SafeModePassword>YourStrongPassword@123</SafeModePassword>
  ```

- [ ] **Review Network Settings** in `config\server-config.xml`
  - IP: 192.168.5.10 (appropriate for your network?)
  - Gateway: 192.168.5.1 (correct?)
  - Domain: havgap-camping.no (keep or change?)

- [ ] **Copy Files to VM** at C:\Windows-Server-DC-Automation

- [ ] **Add Second Disk to VirtualBox** (D: drive, at least 20GB)

- [ ] **Read:** `CHEAT_SHEET.md` for quick reference

---

## When Ready to Run

### On Your Windows Server 2025 VM:

```powershell
# Open PowerShell as Administrator

# 1. Set execution policy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# 2. Navigate to scripts
cd C:\Windows-Server-DC-Automation

# 3. Run Phase 1
.\Step1-PreDCPromotion.ps1

# V Server will restart automatically V

# Phase 2 runs automatically after restart
# If not, manually run:
.\Step2-PostDCPromotion.ps1
```

**Total Time:** ~20-30 minutes including automatic restart

---

## 📁 Key Files Created

| File | Purpose |
|------|---------|
| `RUN_ON_VM.md` | Detailed step-by-step instructions for running on VM |
| `CHEAT_SHEET.md` | Quick reference guide |
| `POWERSHELL_WARNINGS.md` | Explanation of code warnings (non-blocking) |
| `config/server-config.xml` | ✏️ UPDATE: Add your SafeModePassword here |

---

## What Will Be Configured

**Phase 1 (Before Restart):**
- [OK] Computer name: DC01
- [OK] Static IP: 192.168.5.10
- [OK] Roles: AD-DS, DNS, DHCP, IIS
- [OK] Shared folders on D: drive
- [OK] Promotes to Domain Controller
- [OK] Schedules Phase 2
- [OK] Auto-restarts

**Phase 2 (After Restart):**
- [OK] Verifies DC promotion
- [OK] Creates OUs: IT, Finance, HR
- [OK] Creates security groups
- [OK] Configures DHCP: 192.168.5.100-200
- [OK] Configures DNS zones
- [OK] Applies Group Policies
- [OK] Sets up drive mappings

---

## ❓ Troubleshooting

**Q: Scripts won't run?**
A: Make sure execution policy is set: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force`

**Q: "File not found" error?**
A: Make sure you're in the `C:\Windows-Server-DC-Automation` directory when running the scripts.

**Q: "SafeModePassword" error?**
A: Edit `config\server-config.xml` and fill in the password field.

**Q: D: drive doesn't exist?**
A: Add a second disk in VirtualBox, initialize it in Disk Management.

For more help, see `RUN_ON_VM.md` - Troubleshooting section.

---

## 🎓 Your Scripts Are Ready!

The automation is complete and ready to use. The errors you saw earlier have been fixed.

**Next Action:** Update the config file with your SafeModePassword, then run on your Windows Server 2025 VM.

---

**Questions?** Review the documentation files or check the logs after running for detailed error messages.

Good luck! 🚀
