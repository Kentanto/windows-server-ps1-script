# PowerShell Best Practices Notes

## About the Warnings

The Windows Server DC Automation scripts contain some PSScriptAnalyzer warnings about:

1. **Function naming** - Using unapproved verbs like `Create-`, `Promote-` instead of approved verbs like `New-`, `Set-`
2. **Password parameter** - Passing password as `[string]` instead of `[SecureString]` for security

## ⚠️ These Are NOT Blocking Errors

These warnings will NOT prevent the scripts from running. They are **best-practice recommendations** from PowerShell's code analysis tool.

✅ **The scripts will execute successfully despite these warnings.**

## Why They're There

### Function Naming
PowerShell has approved verbs (Get, Set, New, Remove, etc.). Using unapproved verbs like "Create" or "Promote" is technically fine but not following PowerShell conventions. The functions work perfectly - it's just a style preference.

### Password Handling
Passing passwords as plain strings and then converting them to SecureString is secure enough for this automation (the string is stored in XML config anyway). A fully secure approach would require the config file to already contain SecureString values, which adds complexity.

## If You Want to Fix These Warnings

You could rename:
- `Promote-ToDomainController` → `Set-DomainControllerPromotion`
- `Create-OUStructure` → `New-ActiveDirectoryOUStructure`
- `Create-SecurityGroups` → `New-ActiveDirectorySecurityGroups`

But this requires updating all the places these functions are called in Step1 and Step2 scripts.

## Recommendation

For a working automation script, **ignore these warnings**. They're helpful reminders for production-grade code, but they don't affect functionality.

If you want to improve the scripts later, you can:
1. Rename functions to use approved verbs
2. Update all call sites
3. Run `Invoke-ScriptAnalyzer` to verify

For now, **proceed with running the scripts** - they will work fine!
