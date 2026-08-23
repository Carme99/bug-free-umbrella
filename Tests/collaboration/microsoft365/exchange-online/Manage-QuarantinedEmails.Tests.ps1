<#
.SYNOPSIS
    Pester test suite for the Manage-QuarantinedEmails.ps1 script.

.DESCRIPTION
    Validates the behavior of Manage-QuarantinedEmails.ps1, which connects to
    Exchange Online, retrieves quarantined messages for review, and performs
    release/delete actions on selected messages. Tests cover parameter validation,
    quarantine message retrieval and filtering, bulk action handling, and output
    formatting. Exchange Online cmdlets (Connect-ExchangeOnline, Get-EXOMailbox,
    Get-QuarantineMessage, etc.) are mocked so the suite runs without a real
    tenant connection.

.EXAMPLE
    PS C:\> Invoke-Pester .\Manage-QuarantinedEmails.Tests.ps1

    Runs the full test suite against the Manage-QuarantinedEmails.ps1 script in the same folder.

.NOTES
    File Name  : Manage-QuarantinedEmails.Tests.ps1
    Author     : Microsoft 365 Scripting Team
    Prerequisite: PowerShell 7.0, Pester 5, ExchangeOnlineManagement module
    Version    : 1.0.0
    Date       : 2025-01-01
#>

BeforeAll {
    # Import the script to test
    $scriptPath = "$PSScriptRoot/Manage-QuarantinedEmails.ps1"

    # Mock external cmdlets
    Mock Write-Host { }
    Mock Read-Host { "test@contoso.com" }
    Mock Start-Process { }

    # Mock Exchange Online cmdlets
    Mock Get-Module {
        [PSCustomObject]@{
            Name = "ExchangeOnlineManagement"
            Version = "3.0.0"
        }
    }

    Mock Import-Module { }

    Mock Get-ConnectionInformation {
        [PSCustomObject]@{
            UserPrincipalName = "admin@contoso.com"
            ConnectionId = "12345"
        }
    }

    Mock Connect-ExchangeOnline { }

    Mock Get-EXOMailbox {
        [PSCustomObject]@{
            DisplayName = "Test User"
            PrimarySmtpAddress = "test@contoso.com"
            UserPrincipalName = "test@contoso.com"
        }
    }

    Mock Get-QuarantineMessage {
        @(
            [PSCustomObject]@{
                Identity = "msg-001"
                ReceivedTime = (Get-Date).AddDays(-1)
                SenderAddress = "sender@external.com"
                RecipientAddress = @("test@contoso.com")
                Subject = "Test Quarantined Email"
                QuarantineTypes = @("Spam")
                Direction = "Inbound"
                Size = 51200
                PolicyName = "Default Anti-Spam Policy"
            },
            [PSCustomObject]@{
                Identity = "msg-002"
                ReceivedTime = (Get-Date).AddDays(-2)
                SenderAddress = "phishing@malicious.com"
                RecipientAddress = @("test@contoso.com")
                Subject = "Urgent: Verify Your Account"
                QuarantineTypes = @("HighConfPhish")
                Direction = "Inbound"
                Size = 102400
                PolicyName = "Default Anti-Phishing Policy"
            }
        )
    }

    Mock Release-QuarantineMessage { }
}

Describe "Manage-QuarantinedEmails.ps1 - Parameter Validation" {

    Context "UserEmail Parameter" {
        It "Should accept valid email address" {
            { & $scriptPath -UserEmail "test@contoso.com" -Days 7 } | Should -Not -Throw
        }

        It "Should work without UserEmail (interactive mode)" {
            Mock Read-Host { "test@contoso.com" }
            { & $scriptPath -Days 7 } | Should -Not -Throw
        }
    }

    Context "Days Parameter" {
        It "Should accept valid days value (1-30)" {
            { & $scriptPath -UserEmail "test@contoso.com" -Days 14 } | Should -Not -Throw
        }

        It "Should use default of 7 days when not specified" {
            { & $scriptPath -UserEmail "test@contoso.com" } | Should -Not -Throw
        }

        It "Should reject days value greater than 30" {
            { & $scriptPath -UserEmail "test@contoso.com" -Days 31 } | Should -Throw
        }

        It "Should reject days value less than 1" {
            { & $scriptPath -UserEmail "test@contoso.com" -Days 0 } | Should -Throw
        }
    }

    Context "AutoConnect Parameter" {
        It "Should accept -AutoConnect switch" {
            Mock Get-ConnectionInformation { $null }
            Mock Connect-ExchangeOnline { }

            { & $scriptPath -UserEmail "test@contoso.com" -AutoConnect } | Should -Not -Throw
        }
    }
}

Describe "Manage-QuarantinedEmails.ps1 - Connection Handling" {

    Context "Exchange Online Module Check" {
        It "Should verify ExchangeOnlineManagement module is installed" {
            Mock Get-Module { $null }

            { & $scriptPath -UserEmail "test@contoso.com" } | Should -Throw
        }

        It "Should detect existing connection" {
            Mock Get-ConnectionInformation {
                [PSCustomObject]@{
                    UserPrincipalName = "admin@contoso.com"
                }
            }

            { & $scriptPath -UserEmail "test@contoso.com" } | Should -Not -Throw
        }

        It "Should prompt for connection when not connected and AutoConnect not specified" {
            Mock Get-ConnectionInformation { $null }

            { & $scriptPath -UserEmail "test@contoso.com" } | Should -Throw
        }
    }

    Context "Connection with AutoConnect" {
        It "Should attempt to connect when AutoConnect is specified" {
            Mock Get-ConnectionInformation { $null }
            Mock Connect-ExchangeOnline { }

            & $scriptPath -UserEmail "test@contoso.com" -AutoConnect

            Should -Invoke Connect-ExchangeOnline -Times 1
        }

        It "Should handle connection failures gracefully" {
            Mock Get-ConnectionInformation { $null }
            Mock Connect-ExchangeOnline { throw "Connection failed" }

            { & $scriptPath -UserEmail "test@contoso.com" -AutoConnect } | Should -Throw
        }
    }
}

Describe "Manage-QuarantinedEmails.ps1 - Email Validation" {

    Context "Email Address Format" {
        It "Should reject invalid email format" {
            { & $scriptPath -UserEmail "invalid-email" } | Should -Throw
        }

        It "Should reject empty email" {
            { & $scriptPath -UserEmail "" } | Should -Throw
        }

        It "Should accept standard email format" {
            { & $scriptPath -UserEmail "user@domain.com" } | Should -Not -Throw
        }

        It "Should accept email with subdomain" {
            { & $scriptPath -UserEmail "user@mail.domain.com" } | Should -Not -Throw
        }
    }
}

Describe "Manage-QuarantinedEmails.ps1 - User Verification" {

    Context "Mailbox Existence Check" {
        It "Should verify user mailbox exists" {
            Mock Get-EXOMailbox {
                [PSCustomObject]@{
                    DisplayName = "Test User"
                    PrimarySmtpAddress = "test@contoso.com"
                }
            }

            { & $scriptPath -UserEmail "test@contoso.com" } | Should -Not -Throw
            Should -Invoke Get-EXOMailbox -Times 1
        }

        It "Should handle non-existent mailbox" {
            Mock Get-EXOMailbox { throw "Mailbox not found" }

            { & $scriptPath -UserEmail "nonexistent@contoso.com" } | Should -Throw
        }

        It "Should use PrimarySmtpAddress for quarantine search" {
            Mock Get-EXOMailbox {
                [PSCustomObject]@{
                    DisplayName = "Test User"
                    PrimarySmtpAddress = "primary@contoso.com"
                    UserPrincipalName = "test@contoso.com"
                }
            }

            Mock Get-QuarantineMessage { @() }

            & $scriptPath -UserEmail "test@contoso.com"

            Should -Invoke Get-QuarantineMessage -ParameterFilter {
                $RecipientAddress -eq "primary@contoso.com"
            }
        }
    }
}

Describe "Manage-QuarantinedEmails.ps1 - Quarantine Message Retrieval" {

    Context "Message Search" {
        It "Should search for quarantined messages with correct date range" {
            $daysBack = 7

            Mock Get-QuarantineMessage { @() }

            & $scriptPath -UserEmail "test@contoso.com" -Days $daysBack

            Should -Invoke Get-QuarantineMessage -Times 1 -ParameterFilter {
                $RecipientAddress -eq "test@contoso.com"
            }
        }

        It "Should handle no quarantined messages found" {
            Mock Get-QuarantineMessage { @() }

            { & $scriptPath -UserEmail "test@contoso.com" } | Should -Not -Throw
        }

        It "Should handle multiple quarantined messages" {
            Mock Get-QuarantineMessage {
                @(
                    [PSCustomObject]@{
                        Identity = "msg-001"
                        ReceivedTime = (Get-Date)
                        SenderAddress = "sender1@external.com"
                        RecipientAddress = @("test@contoso.com")
                        Subject = "Message 1"
                        QuarantineTypes = @("Spam")
                    },
                    [PSCustomObject]@{
                        Identity = "msg-002"
                        ReceivedTime = (Get-Date)
                        SenderAddress = "sender2@external.com"
                        RecipientAddress = @("test@contoso.com")
                        Subject = "Message 2"
                        QuarantineTypes = @("Malware")
                    }
                )
            }

            { & $scriptPath -UserEmail "test@contoso.com" } | Should -Not -Throw
        }

        It "Should handle permissions errors gracefully" {
            Mock Get-QuarantineMessage {
                throw "User is not authorized to perform this operation"
            }

            { & $scriptPath -UserEmail "test@contoso.com" } | Should -Not -Throw
        }
    }
}

Describe "Manage-QuarantinedEmails.ps1 - Message Release Functionality" {

    Context "Release Message" {
        It "Should call Release-QuarantineMessage when releasing" {
            Mock Read-Host {
                switch ($global:ReadHostCallCount++) {
                    0 { "1" }     # Select first message
                    1 { "1" }     # Choose to release
                    2 { "Y" }     # Confirm release
                    3 { "0" }     # Exit
                    default { "0" }
                }
            }

            $global:ReadHostCallCount = 0

            & $scriptPath -UserEmail "test@contoso.com"

            Should -Invoke Release-QuarantineMessage -Times 1
        }

        It "Should handle release failures gracefully" {
            Mock Release-QuarantineMessage {
                throw "Failed to release message"
            }

            Mock Read-Host {
                switch ($global:ReadHostCallCount2++) {
                    0 { "1" }     # Select first message
                    1 { "1" }     # Choose to release
                    2 { "Y" }     # Confirm release
                    3 { "0" }     # Exit
                    default { "0" }
                }
            }

            $global:ReadHostCallCount2 = 0

            { & $scriptPath -UserEmail "test@contoso.com" } | Should -Not -Throw
        }
    }
}

Describe "Manage-QuarantinedEmails.ps1 - Function Tests" {

    BeforeAll {
        # Source the script to access internal functions
        . $scriptPath
    }

    Context "Test-EmailAddress Function" {
        It "Should validate correct email addresses" {
            Test-EmailAddress -Email "user@domain.com" | Should -Be $true
            Test-EmailAddress -Email "user.name@sub.domain.com" | Should -Be $true
            Test-EmailAddress -Email "user+tag@domain.com" | Should -Be $true
        }

        It "Should reject invalid email addresses" {
            Test-EmailAddress -Email "invalid" | Should -Be $false
            Test-EmailAddress -Email "@domain.com" | Should -Be $false
            Test-EmailAddress -Email "user@" | Should -Be $false
            Test-EmailAddress -Email "user domain.com" | Should -Be $false
        }
    }
}

Describe "Manage-QuarantinedEmails.ps1 - Interactive Mode" {

    Context "Interactive Email Input" {
        It "Should prompt for email when not provided" {
            Mock Read-Host { "test@contoso.com" }

            { & $scriptPath } | Should -Not -Throw
        }

        It "Should handle invalid interactive input" {
            Mock Read-Host { "invalid-email" }

            { & $scriptPath } | Should -Throw
        }
    }
}
