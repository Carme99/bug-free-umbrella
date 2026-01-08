# Security and Bug Fixes Required for v3.3.0

## Critical Issues to Fix Before Release

### 1. **BROKEN FEATURE** - Release-QuarantineMessage Alternate Recipient
**File:** `Manage-QuarantinedEmails.ps1:260-310`
**Issue:** The alternate recipient feature is non-functional. `Release-QuarantineMessage` only supports releasing to original recipients.

**Current Code:**
```powershell
$targetRecipient = $Message.RecipientAddress[0]
if ($ReleaseToAlt) {
    # Get alternate email...
    $targetRecipient = $altEmail.Trim()
}
# But then Release-QuarantineMessage ignores $targetRecipient!
Release-QuarantineMessage -Identity $Message.Identity -ReleaseToAll:$false
```

**Fix Options:**
1. **Remove the alternate recipient feature entirely** (RECOMMENDED)
2. Document that releases always go to original recipient
3. Use `-ReleaseToAll $true` flag (releases to ALL original recipients)

**Recommendation:** Remove `-ReleaseToAlternate` parameter and menu option 2. Update documentation to clarify messages are released to original recipients only.

---

### 2. **SECURITY** - XSS Vulnerabilities in HTML Exports
**Files:**
- `Get-M365UserInfo.ps1:542+`
- `Get-UserMailboxPermissions.ps1:208+`
- `Get-UserMailRules.ps1:276+`

**Issue:** User-provided data embedded in HTML without encoding creates XSS risks.

**Vulnerable Code:**
```powershell
$html += "<td>$($user.DisplayName)</td>"  # No encoding!
```

**Fix:** Add HTML encoding function:
```powershell
function ConvertTo-HtmlSafe {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    return [System.Web.HttpUtility]::HtmlEncode($Text)
}

# Usage:
$html += "<td>$(ConvertTo-HtmlSafe $user.DisplayName)</td>"
```

**Note:** Requires `Add-Type -AssemblyName System.Web`

---

### 3. **SECURITY** - No Domain Validation for Alternate Emails
**File:** `Manage-QuarantinedEmails.ps1:262-272`
**Issue:** Alternate email validation only checks format, not domain.

**Current Code:**
```powershell
if (-not (Test-EmailAddress -Email $altEmail)) {
    Write-Host "[-] Invalid email address!" -ForegroundColor Red
    return $false
}
```

**Fix:** Add domain validation:
```powershell
function Test-InternalDomain {
    param([string]$Email)

    $domain = $Email.Split('@')[1]

    # Get accepted domains from Exchange Online
    try {
        $acceptedDomains = Get-AcceptedDomain -ErrorAction Stop
        return ($acceptedDomains.DomainName -contains $domain)
    }
    catch {
        Write-Host "[-] Could not verify domain. Defaulting to deny." -ForegroundColor Red
        return $false
    }
}
```

---

### 4. **BUG** - Wrong ErrorActionPreference
**File:** `Get-M365UserInfo.ps1:87`
**Issue:** Uses `$ErrorActionPreference = "Continue"` instead of "Stop"

**Fix:**
```powershell
$ErrorActionPreference = "Stop"
```

Then add try-catch blocks where needed for graceful degradation.

---

### 5. **BUG** - Array Bounds Not Checked
**File:** `Manage-QuarantinedEmails.ps1:260`
**Issue:** Accesses `$Message.RecipientAddress[0]` without null/bounds check

**Current Code:**
```powershell
$targetRecipient = $Message.RecipientAddress[0]
```

**Fix:**
```powershell
if ($null -eq $Message.RecipientAddress -or $Message.RecipientAddress.Count -eq 0) {
    Write-Host "[-] Message has no recipients!" -ForegroundColor Red
    return $false
}
$targetRecipient = $Message.RecipientAddress[0]
```

---

### 6. **SECURITY** - Path Traversal in File Exports
**Files:** All scripts with `-ExportReport` or `-ExportHTML`
**Issue:** User email in filename without sanitization

**Vulnerable Code:**
```powershell
$reportPath = "$env:USERPROFILE\Desktop\M365_UserReport_$($script:UserData.UserPrincipalName.Replace('@','_'))_$timestamp.html"
```

**Fix:**
```powershell
function Get-SafeFileName {
    param([string]$FileName)

    $invalid = [IO.Path]::GetInvalidFileNameChars()
    $safe = $FileName
    foreach ($char in $invalid) {
        $safe = $safe.Replace($char, '_')
    }

    # Additional security: Remove path traversal attempts
    $safe = $safe.Replace('..', '_').Replace('/', '_').Replace('\', '_')

    return $safe
}

# Usage:
$safeEmail = Get-SafeFileName $script:UserData.UserPrincipalName
$reportPath = "$env:USERPROFILE\Desktop\M365_UserReport_${safeEmail}_$timestamp.html"
```

---

### 7. **BUG** - Fragile String Parsing
**File:** `Get-M365UserInfo.ps1:283-289`
**Issue:** Mailbox size calculation uses brittle string parsing

**Current Code:**
```powershell
$mailboxSizeGB = if ($stats.TotalItemSize) {
    [math]::Round(($stats.TotalItemSize.ToString().Split('(')[1].Split(' ')[0].Replace(',','') -as [double]) / 1GB, 2)
} else { 0 }
```

**Fix:**
```powershell
function Get-MailboxSizeGB {
    param($TotalItemSize)

    if (-not $TotalItemSize) { return 0 }

    try {
        # Match pattern: "12.34 GB (13,271,234 bytes)"
        $sizeString = $TotalItemSize.ToString()
        if ($sizeString -match '\((\d{1,3}(?:,\d{3})*(?:\.\d+)?)\s+bytes\)') {
            $bytes = [double]($Matches[1] -replace ',', '')
            return [math]::Round($bytes / 1GB, 2)
        }

        # Fallback to old method
        $bytes = ($sizeString.Split('(')[1].Split(' ')[0].Replace(',','') -as [double])
        return [math]::Round($bytes / 1GB, 2)
    }
    catch {
        Write-Host "[!] Warning: Could not parse mailbox size: $($_.Exception.Message)" -ForegroundColor Yellow
        return 0
    }
}

# Usage:
$mailboxSizeGB = Get-MailboxSizeGB $stats.TotalItemSize
```

---

### 8. **LIMITATION** - Localization Issues with Folder Names
**File:** `Get-UserMailboxPermissions.ps1:170`
**Issue:** Hardcoded English folder names won't work for non-English mailboxes

**Current Code:**
```powershell
$folders = @("Calendar", "Inbox", "Contacts", "Tasks")
```

**Fix Options:**
1. **Use well-known folder IDs** (RECOMMENDED):
```powershell
# Use EWS folder IDs instead of names
$wellKnownFolders = @{
    Calendar = "calendar"
    Inbox = "inbox"
    Contacts = "contacts"
    Tasks = "tasks"
}

foreach ($folder in $wellKnownFolders.Keys) {
    try {
        $folderPath = "${UserEmail}:\$($wellKnownFolders[$folder])"
        # This works across all localizations
    }
    catch {
        # Log and continue
    }
}
```

2. **Add error handling and document limitation**:
```powershell
Write-Host "[!] Note: Folder names are in English. Non-English mailboxes may not show all permissions." -ForegroundColor Yellow
```

---

### 9. **BUG** - Test Execution Issue
**File:** `Manage-QuarantinedEmails.Tests.ps1:318`
**Issue:** Sourcing the script will execute main logic

**Fix in Main Script:**
```powershell
# At the end of Manage-QuarantinedEmails.ps1
# Only execute if not dot-sourced
if ($MyInvocation.InvocationName -ne '.') {
    # ... main execution logic here ...
}
```

---

### 10. **PERFORMANCE** - N+1 Query Problem
**File:** `Get-M365UserInfo.ps1:362`
**Issue:** Individual API calls for each group

**Current Code:**
```powershell
foreach ($group in $groupList) {
    $groupDetails = Get-MgGroup -GroupId $group.Id -ErrorAction SilentlyContinue
    # ... process group ...
}
```

**Fix:**
```powershell
# Batch request
$groupIds = $groupList.Id
$groupDetails = Get-MgGroup -Filter "id in ('$($groupIds -join "','")')" -ErrorAction SilentlyContinue

foreach ($group in $groupDetails) {
    # ... process group ...
}
```

---

### 11. **VALIDATION** - Email Regex Too Permissive
**Files:** Multiple
**Issue:** Regex allows `user@.com`

**Current Regex:**
```powershell
$Email -match '^[\w\.-]+@[\w\.-]+\.\w+$'
```

**Fix:**
```powershell
function Test-EmailAddress {
    param([string]$Email)

    if ([string]::IsNullOrWhiteSpace($Email)) { return $false }

    # More strict regex
    $pattern = '^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$'

    return $Email -match $pattern
}
```

---

### 12. **METADATA** - Missing Author and Version Info
**All Scripts**
**Issue:** Generic "IT Operations" author, no version tracking

**Fix:** Add proper metadata:
```powershell
<#
.NOTES
    Author: Your Name / IT Team
    Version: 1.0.0
    Created: 2026-01-08
    Modified: 2026-01-08

    Changelog:
    1.0.0 - Initial release
#>
```

---

## Priority Levels

### Must Fix Before Release (P0):
1. ✅ Broken Release-QuarantineMessage feature (remove or fix)
2. ✅ XSS vulnerabilities in HTML exports
3. ✅ Path traversal in file exports
4. ✅ Array bounds checking
5. ✅ Domain validation for alternate emails

### Should Fix Before Release (P1):
6. ✅ Wrong ErrorActionPreference
7. ✅ Fragile string parsing
8. ✅ Test execution issue
9. ⚠️ Email regex validation

### Can Fix in Patch Release (P2):
10. ⚠️ N+1 query problem (performance)
11. ⚠️ Localization documentation
12. ⚠️ Author metadata

---

## Recommended Action Plan

1. **Immediate:** Fix P0 issues (security critical)
2. **Before v3.3.0 release:** Fix P1 issues (functionality)
3. **v3.3.1 patch:** Fix P2 issues (quality of life)

Would you like me to implement these fixes now?
