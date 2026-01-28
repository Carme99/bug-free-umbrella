# Security Troubleshooting

[![Tier 3](https://img.shields.io/badge/Documentation-Tier%203-blue)]()
[![Security](https://img.shields.io/badge/Focus-Security-red)]()
[![Troubleshooting](https://img.shields.io/badge/Type-Troubleshooting-yellow)]()

## Table of Contents

- [Overview](#overview)
- [Certificate Issues](#certificate-issues)
- [Authentication Failures](#authentication-failures)
- [Permission Problems](#permission-problems)
- [Audit Logging](#audit-logging)
- [Common Security Issues](#common-security-issues)
- [Diagnostic Tools](#diagnostic-tools)
- [Remediation Procedures](#remediation-procedures)

## Overview

Security issues can silently fail or cause cascading problems. This guide helps diagnose and resolve authentication, authorization, and encryption issues.

## Certificate Issues

### SSL/TLS Certificate Validation

```powershell
function Test-CertificateValidity {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,
        
        [int]$Port = 443
    )
    
    try {
        $tcpClient = [System.Net.Sockets.TcpClient]::new()
        $tcpClient.Connect($ServerName, $Port)
        
        $sslStream = [System.Net.Security.SslStream]::new(
            $tcpClient.GetStream(),
            $false,
            { $true }  # Accept any certificate (for testing)
        )
        
        $sslStream.AuthenticateAsClient($ServerName)
        
        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]$sslStream.RemoteCertificate
        
        $results = [PSCustomObject]@{
            ServerName     = $ServerName
            Subject        = $cert.Subject
            Issuer         = $cert.Issuer
            Thumbprint     = $cert.Thumbprint
            NotBefore      = $cert.NotBefore
            NotAfter       = $cert.NotAfter
            IsValid        = (Get-Date) -gt $cert.NotBefore -and (Get-Date) -lt $cert.NotAfter
            DaysToExpiry   = ($cert.NotAfter - (Get-Date)).Days
            SerialNumber   = $cert.SerialNumber
        }
        
        return $results
    }
    catch {
        Write-Error "Failed to retrieve certificate: $_"
    }
    finally {
        $sslStream.Close()
        $tcpClient.Close()
    }
}

# Usage
Test-CertificateValidity -ServerName "api.example.com" -Port 443 | Format-List
```

### Certificate Store Issues

```powershell
function Find-DuplicateCertificates {
    param(
        [ValidateSet("CurrentUser", "LocalMachine")]
        [string]$StoreLocation = "LocalMachine"
    )
    
    $store = [System.Security.Cryptography.X509Certificates.X509Store]::new(
        "My",
        [System.Security.Cryptography.X509Certificates.StoreLocation]::$StoreLocation
    )
    $store.Open("ReadOnly")
    
    $duplicates = @{}
    
    foreach ($cert in $store.Certificates) {
        $key = "$($cert.Issuer)|$($cert.SerialNumber)"
        
        if ($duplicates.ContainsKey($key)) {
            $duplicates[$key] += @($cert)
        } else {
            $duplicates[$key] = @($cert)
        }
    }
    
    $store.Close()
    
    return $duplicates | Where-Object { $_.Value.Count -gt 1 }
}
```

## Authentication Failures

### Testing Authentication Methods

```powershell
function Test-AuthenticationMethod {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Basic", "Bearer", "NTLM", "Negotiate")]
        [string]$AuthType,
        
        [string]$Username,
        [securestring]$Password,
        [string]$Token,
        [string]$TestUrl
    )
    
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        switch ($AuthType) {
            "Basic" {
                $bytes = [Text.Encoding]::ASCII.GetBytes("$Username:$([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($Password)))")
                $headers = @{
                    Authorization = "Basic " + [Convert]::ToBase64String($bytes)
                }
            }
            "Bearer" {
                $headers = @{
                    Authorization = "Bearer $Token"
                }
            }
            "NTLM" {
                # NTLM handled by -UseDefaultCredentials
                $headers = @{}
            }
            "Negotiate" {
                # Negotiate handled by -UseDefaultCredentials
                $headers = @{}
            }
        }
        
        $params = @{
            Uri             = $TestUrl
            UseBasicParsing = $true
            TimeoutSec      = 10
            ErrorAction     = "Stop"
        }
        
        if ($headers.Count -gt 0) {
            $params["Headers"] = $headers
        } else {
            $params["UseDefaultCredentials"] = $true
        }
        
        $response = Invoke-WebRequest @params
        $sw.Stop()
        
        return [PSCustomObject]@{
            Status          = "Success"
            AuthType        = $AuthType
            StatusCode      = $response.StatusCode
            ResponseTimeMS  = $sw.ElapsedMilliseconds
            Authenticated   = $true
        }
    }
    catch {
        $sw.Stop()
        return [PSCustomObject]@{
            Status         = "Failed"
            AuthType       = $AuthType
            Error          = $_.Exception.Message
            ResponseTimeMS = $sw.ElapsedMilliseconds
            Authenticated  = $false
        }
    }
}
```

## Permission Problems

### NTFS Permission Diagnosis

```powershell
function Get-FilePermissionIssue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [string]$User = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    )
    
    if (-not (Test-Path $FilePath)) {
        return "File does not exist: $FilePath"
    }
    
    $acl = Get-Acl -Path $FilePath
    $userHasAccess = $false
    
    foreach ($access in $acl.Access) {
        if ($access.IdentityReference -eq $User) {
            $userHasAccess = $true
            
            return [PSCustomObject]@{
                User        = $User
                FilePath    = $FilePath
                HasAccess   = $userHasAccess
                Permissions = $access.FileSystemRights
                AccessType  = $access.AccessControlType
                IsInherited = $access.IsInherited
            }
        }
    }
    
    if (-not $userHasAccess) {
        return "User '$User' has no explicit permissions on '$FilePath'"
    }
}

### Registry Permission Diagnosis

function Test-RegistryAccess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RegistryPath
    )
    
    try {
        $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($RegistryPath)
        
        if ($null -eq $key) {
            return "Registry key not found: HKLM:\$RegistryPath"
        }
        
        $key.GetValueNames() | Out-Null
        $key.Close()
        
        return "Access granted to HKLM:\$RegistryPath"
    }
    catch [UnauthorizedAccessException] {
        return "Access denied to HKLM:\$RegistryPath"
    }
    catch {
        return "Error accessing HKLM:\$RegistryPath: $_"
    }
}
```

## Audit Logging

### Enable and Monitor Audit Logs

```powershell
function Enable-PowerShellAuditing {
    # Enable PowerShell script block logging
    $regPath = "HKLM:\Software\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
    
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    
    Set-ItemProperty -Path $regPath -Name "EnableScriptBlockLogging" -Value 1 -Force
    
    # Enable module logging
    $modulePath = "HKLM:\Software\Policies\Microsoft\Windows\PowerShell\ModuleLogging"
    if (-not (Test-Path $modulePath)) {
        New-Item -Path $modulePath -Force | Out-Null
    }
    
    Set-ItemProperty -Path $modulePath -Name "EnableModuleLogging" -Value 1 -Force
    
    Write-Host "PowerShell auditing enabled. Check Event Viewer > Windows Logs > Application"
}

function Get-PowerShellAuditLog {
    param(
        [int]$Hours = 24
    )
    
    $startTime = (Get-Date).AddHours(-$Hours)
    
    Get-WinEvent -FilterHashtable @{
        LogName   = "Windows PowerShell"
        StartTime = $startTime
    } -ErrorAction SilentlyContinue | 
        Select-Object TimeCreated, UserId, Message | 
        Format-Table -AutoSize
}
```

## Common Security Issues

| Issue | Symptom | Diagnosis | Resolution |
|-------|---------|-----------|------------|
| Expired certificate | "Certificate validation failed" | Run Test-CertificateValidity | Renew certificate |
| Token expired | "Unauthorized (401)" | Check token expiry | Refresh/regenerate token |
| Permission denied | "Access denied" exception | Run Get-FilePermissionIssue | Grant permissions |
| SSL/TLS version | "HTTPS connection failed" | Check OS TLS support | Update .NET/OS |
| Credential leakage | Plaintext passwords in logs | Review audit logs | Use SecureString/Key Vault |

## Diagnostic Tools

### Certificate Checker

```powershell
function Invoke-CertificateDiagnostic {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName
    )
    
    $results = @{}
    
    # Check DNS resolution
    try {
        $ip = [System.Net.Dns]::GetHostAddresses($ServerName)[0].IPAddressToString
        $results["DNSResolution"] = "Success: $ip"
    }
    catch {
        $results["DNSResolution"] = "Failed: $_"
    }
    
    # Check connectivity
    if (Test-NetConnection -ComputerName $ServerName -Port 443 -InformationLevel Quiet) {
        $results["Connectivity"] = "Success"
    } else {
        $results["Connectivity"] = "Failed"
    }
    
    # Check certificate
    $cert = Test-CertificateValidity -ServerName $ServerName
    $results["Certificate"] = if ($cert.IsValid) { "Valid" } else { "Invalid or Expired" }
    
    return $results
}
```

## Remediation Procedures

### Certificate Renewal Runbook

```powershell
<#
.SYNOPSIS
Steps to resolve certificate expiration

.PROCEDURE
1. Identify expiring certificate
2. Generate CSR
3. Submit to CA
4. Install new certificate
5. Update application binding
6. Test connectivity
7. Monitor for issues
#>

function Renew-ApplicationCertificate {
    param(
        [string]$ServerName,
        [string]$CertPath,
        [string]$AppBinding
    )
    
    # Step 1: Check current certificate
    $cert = Test-CertificateValidity -ServerName $ServerName
    if ($cert.DaysToExpiry -gt 30) {
        Write-Host "Certificate is still valid for $($cert.DaysToExpiry) days"
        return
    }
    
    # Step 2: Backup old certificate
    $backup = "$CertPath.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -Path $CertPath -Destination $backup
    Write-Host "Backup created: $backup"
    
    # Step 3-7: [Manual or automated renewal steps]
    Write-Host "Please proceed with certificate renewal process"
}
```

---

**See Also:** [Security-Compliance.md](Security-Compliance.md) | [Advanced-Monitoring.md](Advanced-Monitoring.md)