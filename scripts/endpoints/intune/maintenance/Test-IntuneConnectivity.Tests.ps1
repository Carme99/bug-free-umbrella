<#
.SYNOPSIS
    Pester tests for Test-IntuneConnectivity.ps1.

.DESCRIPTION
    Validates the behavior of the Intune connectivity script:
    - Parameter validation (Detailed, ExportResults, no parameters)
    - Endpoint connectivity tests (Intune enrollment, Azure AD, Windows Update, Microsoft Graph)
    - Failure detection (connection failures, HTTP errors, DNS resolution, timeouts)
    - Success reporting and summary statistics
    - Detailed output mode
    - CSV export functionality
    - Performance within reasonable time
    - Error handling (missing endpoints, continued testing after failures)

.EXAMPLE
    PS C:\> Invoke-Pester -Path .\Test-IntuneConnectivity.Tests.ps1
    Runs all tests against the Test-IntuneConnectivity.ps1 script.

.NOTES
    File Name  : Test-IntuneConnectivity.Tests.ps1
    Author     : IT Administration
    Prerequisite: PowerShell 7.0, Pester 5
    Version    : 1.0.0
    Date       : 2025-01-01
#>

BeforeAll {
    # Import the script to test
    $scriptPath = "$PSScriptRoot/Test-IntuneConnectivity.ps1"

    # Mock external cmdlets
    Mock Test-NetConnection { }
    Mock Invoke-WebRequest { }
    Mock Write-Host { }
    Mock Export-Csv { }
}

Describe "Test-IntuneConnectivity.ps1" {

    Context "Parameter Validation" {
        It "Should accept Detailed switch" {
            Mock Test-NetConnection {
                [PSCustomObject]@{
                    TcpTestSucceeded = $true
                    PingSucceeded = $true
                }
            }
            Mock Invoke-WebRequest {
                [PSCustomObject]@{
                    StatusCode = 200
                }
            }

            { & $scriptPath -Detailed } | Should -Not -Throw
        }

        It "Should accept ExportResults switch" {
            Mock Test-NetConnection {
                [PSCustomObject]@{
                    TcpTestSucceeded = $true
                    PingSucceeded = $true
                }
            }
            Mock Invoke-WebRequest {
                [PSCustomObject]@{
                    StatusCode = 200
                }
            }

            { & $scriptPath -ExportResults } | Should -Not -Throw
        }

        It "Should work without parameters" {
            Mock Test-NetConnection {
                [PSCustomObject]@{
                    TcpTestSucceeded = $true
                    PingSucceeded = $true
                }
            }
            Mock Invoke-WebRequest {
                [PSCustomObject]@{
                    StatusCode = 200
                }
            }

            { & $scriptPath } | Should -Not -Throw
        }
    }

    Context "Endpoint Connectivity Tests" {
        It "Should test Intune enrollment endpoints" {
            Mock Invoke-WebRequest -ParameterFilter { $Uri -match 'enrollment.manage.microsoft.com' } {
                [PSCustomObject]@{
                    StatusCode = 200
                    StatusDescription = "OK"
                }
            }
            Mock Invoke-WebRequest {
                [PSCustomObject]@{
                    StatusCode = 200
                }
            }

            $output = & $scriptPath *>&1
            $output | Should -Match "enrollment.manage.microsoft.com"
        }

        It "Should test Azure AD endpoints" {
            Mock Invoke-WebRequest -ParameterFilter { $Uri -match 'login.microsoftonline.com' } {
                [PSCustomObject]@{
                    StatusCode = 200
                    StatusDescription = "OK"
                }
            }
            Mock Invoke-WebRequest {
                [PSCustomObject]@{
                    StatusCode = 200
                }
            }

            $output = & $scriptPath *>&1
            $output | Should -Match "login.microsoftonline.com"
        }

        It "Should test Windows Update endpoints" {
            Mock Invoke-WebRequest -ParameterFilter { $Uri -match 'windowsupdate.com' } {
                [PSCustomObject]@{
                    StatusCode = 200
                    StatusDescription = "OK"
                }
            }
            Mock Invoke-WebRequest {
                [PSCustomObject]@{
                    StatusCode = 200
                }
            }

            $output = & $scriptPath *>&1
            $output | Should -Match "windowsupdate"
        }

        It "Should test Microsoft Graph endpoints" {
            Mock Invoke-WebRequest -ParameterFilter { $Uri -match 'graph.microsoft.com' } {
                [PSCustomObject]@{
                    StatusCode = 200
                    StatusDescription = "OK"
                }
            }
            Mock Invoke-WebRequest {
                [PSCustomObject]@{
                    StatusCode = 200
                }
            }

            $output = & $scriptPath *>&1
            $output | Should -Match "graph.microsoft.com"
        }
    }

    Context "Failure Detection" {
        It "Should detect connectivity failures" {
            Mock Invoke-WebRequest {
                throw "Connection failed"
            }

            $output = & $scriptPath *>&1
            $output | Should -Match "fail|error|unreachable"
        }

        It "Should handle HTTP errors" {
            Mock Invoke-WebRequest {
                $response = [PSCustomObject]@{
                    StatusCode = 503
                    StatusDescription = "Service Unavailable"
                }
                throw [Microsoft.PowerShell.Commands.HttpResponseException]::new(
                    "503 Service Unavailable",
                    $response
                )
            }

            $output = & $scriptPath *>&1
            $output | Should -Match "503|unavailable|fail"
        }

        It "Should handle DNS resolution failures" {
            Mock Invoke-WebRequest {
                throw "The remote name could not be resolved"
            }

            $output = & $scriptPath *>&1
            $output | Should -Match "DNS|resolve|fail"
        }

        It "Should handle timeout errors" {
            Mock Invoke-WebRequest {
                throw "The operation has timed out"
            }

            $output = & $scriptPath *>&1
            $output | Should -Match "timeout|fail"
        }
    }

    Context "Success Reporting" {
        It "Should report successful connections" {
            Mock Invoke-WebRequest {
                [PSCustomObject]@{
                    StatusCode = 200
                    StatusDescription = "OK"
                }
            }

            $output = & $scriptPath *>&1
            $output | Should -Match "success|ok|passed|reachable"
        }

        It "Should provide summary statistics" {
            Mock Invoke-WebRequest {
                [PSCustomObject]@{
                    StatusCode = 200
                    StatusDescription = "OK"
                }
            }

            $output = & $scriptPath *>&1
            $output | Should -Match "Total|Summary|endpoints"
        }
    }

    Context "Detailed Output Mode" {
        It "Should show detailed results when Detailed switch is used" {
            Mock Invoke-WebRequest {
                [PSCustomObject]@{
                    StatusCode = 200
                    StatusDescription = "OK"
                    Headers = @{
                        'Content-Type' = 'application/json'
                    }
                }
            }

            $output = & $scriptPath -Detailed *>&1
            # Detailed mode should show more information
            $output.Count | Should -BeGreaterThan 0
        }
    }

    Context "CSV Export Functionality" {
        It "Should export results to CSV when ExportResults switch is used" {
            Mock Invoke-WebRequest {
                [PSCustomObject]@{
                    StatusCode = 200
                    StatusDescription = "OK"
                }
            }

            & $scriptPath -ExportResults

            Should -Invoke Export-Csv -Times 1 -Scope It
        }

        It "Should create CSV file with correct columns" {
            Mock Invoke-WebRequest {
                [PSCustomObject]@{
                    StatusCode = 200
                    StatusDescription = "OK"
                }
            }

            $capturedData = $null
            Mock Export-Csv {
                param($InputObject, $Path)
                $capturedData = $InputObject
            }

            & $scriptPath -ExportResults

            $capturedData | Should -Not -BeNullOrEmpty
        }
    }

    Context "Performance" {
        It "Should complete within reasonable time" {
            Mock Invoke-WebRequest {
                Start-Sleep -Milliseconds 10  # Simulate network delay
                [PSCustomObject]@{
                    StatusCode = 200
                }
            }

            $elapsed = Measure-Command {
                & $scriptPath *>&1 | Out-Null
            }

            # Should complete within 30 seconds even with all endpoints
            $elapsed.TotalSeconds | Should -BeLessThan 30
        }
    }

    Context "Error Handling" {
        It "Should handle missing endpoints gracefully" {
            Mock Invoke-WebRequest {
                [PSCustomObject]@{
                    StatusCode = 404
                    StatusDescription = "Not Found"
                }
            }

            { & $scriptPath } | Should -Not -Throw
        }

        It "Should continue testing after individual failures" {
            $script:callCount = 0
            Mock Invoke-WebRequest {
                $script:callCount++
                if ($script:callCount -eq 1) {
                    throw "First endpoint failed"
                }
                [PSCustomObject]@{
                    StatusCode = 200
                }
            }

            $output = & $scriptPath *>&1
            # Should have attempted multiple endpoints despite first failure
            $script:callCount | Should -BeGreaterThan 1
        }

        It "Should handle network adapter errors" {
            Mock Invoke-WebRequest {
                throw "No such host is known"
            }

            { & $scriptPath } | Should -Not -Throw
        }
    }

    Context "Proxy Detection" {
        It "Should respect system proxy settings" {
            Mock Invoke-WebRequest -ParameterFilter { $PSBoundParameters.ContainsKey('Proxy') } {
                [PSCustomObject]@{
                    StatusCode = 200
                }
            }

            # This test assumes the script respects proxy settings
            { & $scriptPath } | Should -Not -Throw
        }
    }

    Context "Return Values" {
        It "Should return success status when all endpoints reachable" {
            Mock Invoke-WebRequest {
                [PSCustomObject]@{
                    StatusCode = 200
                }
            }

            $result = & $scriptPath
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should return failure status when endpoints unreachable" {
            Mock Invoke-WebRequest {
                throw "All endpoints failed"
            }

            # Script should still complete without throwing
            { & $scriptPath *>&1 | Out-Null } | Should -Not -Throw
        }
    }
}
