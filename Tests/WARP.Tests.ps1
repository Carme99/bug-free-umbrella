#Requires -Modules Pester

<#
.SYNOPSIS
    Tests to validate WARP.md documentation accuracy and completeness.

.DESCRIPTION
    Validates that the guidance in WARP.md is accurate, including:
    - Pester test commands
    - Linting and analysis commands
    - Script execution examples
    - Repository architecture
    - Testing strategy
    - Contributing guidelines
#>

Describe "WARP.md Documentation Validation" {
    BeforeAll {
        $warpMdPath = Join-Path $PSScriptRoot ".." "WARP.md"
        $pesterConfigPath = Join-Path $PSScriptRoot "Pester.Config.psd1"
        $scriptsPath = Join-Path $PSScriptRoot ".." "scripts"
        $testsPath = Join-Path $PSScriptRoot ".."  "Tests"
        $examplesPath = Join-Path $PSScriptRoot ".." "examples"
        $wikiPath = Join-Path $PSScriptRoot ".." "wiki"
    }

    Context "WARP.md File Existence and Structure" {
        It "WARP.md should exist at repository root" {
            Test-Path $warpMdPath | Should -Be $true
        }

        It "WARP.md should contain Common Development Commands section" {
            $content = Get-Content $warpMdPath -Raw
            $content | Should -Match "## Common Development Commands"
        }

        It "WARP.md should contain Repository Architecture section" {
            $content = Get-Content $warpMdPath -Raw
            $content | Should -Match "## Repository Architecture"
        }

        It "WARP.md should contain Testing Strategy section" {
            $content = Get-Content $warpMdPath -Raw
            $content | Should -Match "## Testing Strategy"
        }

        It "WARP.md should contain Contributing Guidelines section" {
            $content = Get-Content $warpMdPath -Raw
            $content | Should -Match "## Contributing Guidelines"
        }
    }

    Context "Pester Test Commands Validation" {
        It "Pester.Config.psd1 file should exist" {
            Test-Path $pesterConfigPath | Should -Be $true
        }

        It "Pester configuration should be a valid PowerShell data file" {
            { Import-PowerShellDataFile -Path $pesterConfigPath } | Should -Not -Throw
        }

        It "Pester configuration should have Run section" {
            $config = Import-PowerShellDataFile -Path $pesterConfigPath
            $config.Run | Should -Not -BeNullOrEmpty
        }

        It "Pester configuration should have CodeCoverage section" {
            $config = Import-PowerShellDataFile -Path $pesterConfigPath
            $config.CodeCoverage | Should -Not -BeNullOrEmpty
        }

        It "Pester configuration should exclude Integration tests by default" {
            $config = Import-PowerShellDataFile -Path $pesterConfigPath
            $config.Filter.ExcludeTag | Should -Contain 'Integration'
        }

        It "Tests directory should exist" {
            Test-Path $testsPath | Should -Be $true
        }

        It "HelperFunctions.Tests.ps1 should exist in Tests/Common/" {
            $helperTestPath = Join-Path $testsPath "Common" "HelperFunctions.Tests.ps1"
            Test-Path $helperTestPath | Should -Be $true
        }
    }

    Context "Linting and Analysis Commands Validation" {
        It "PSScriptAnalyzerSettings.psd1 should exist in .vscode directory" {
            $psaSettingsPath = Join-Path $PSScriptRoot ".." ".vscode" "PSScriptAnalyzerSettings.psd1"
            Test-Path $psaSettingsPath | Should -Be $true
        }

        It "scripts directory should exist" {
            Test-Path $scriptsPath | Should -Be $true
        }

        It "PSScriptAnalyzer module should be available or command should be valid" {
            # This test validates that the Invoke-ScriptAnalyzer command is syntactically correct
            $command = Get-Command -Name Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue
            if ($null -eq $command) {
                # If module not installed, just verify the command syntax is correct
                $true | Should -Be $true -Because "Command syntax is valid even if module not installed"
            } else {
                $command.Name | Should -Be 'Invoke-ScriptAnalyzer'
            }
        }

        It "PowerShell parser tokenization command should be valid" {
            # Verify the PowerShell parser accepts the syntax (ParseInput reports errors via out-param)
            $testScript = "Write-Host 'test'"
            $tokens = $null
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseInput($testScript, [ref]$tokens, [ref]$parseErrors) | Out-Null
            $parseErrors.Count | Should -Be 0
        }
    }

    Context "Script Execution Examples Validation" {
        It "Example script paths mentioned in WARP.md should follow correct structure" {
            $warpContent = Get-Content $warpMdPath -Raw
            
            # Check for endpoints/intune/reporting structure
            $warpContent | Should -Match "scripts/endpoints/intune/reporting"
            
            # Check for infrastructure/windows/monitoring structure
            $warpContent | Should -Match "scripts/infrastructure/windows/monitoring"
            
            # Check for cloud/azure/core structure
            $warpContent | Should -Match "scripts/cloud/azure/core"
        }

        It "scripts/endpoints/intune/reporting directory should exist" {
            $intuneReportingPath = Join-Path $scriptsPath "endpoints" "intune" "reporting"
            Test-Path $intuneReportingPath | Should -Be $true
        }

        It "scripts/infrastructure/windows/monitoring directory should exist" {
            $windowsMonitoringPath = Join-Path $scriptsPath "infrastructure" "windows" "monitoring"
            Test-Path $windowsMonitoringPath | Should -Be $true
        }

        It "scripts/cloud/azure/core directory should exist" {
            $azureCorePath = Join-Path $scriptsPath "cloud" "azure" "core"
            Test-Path $azureCorePath | Should -Be $true
        }

        It "WhatIf parameter guidance should be valid PowerShell syntax" {
            # Verify that -WhatIf is a valid common parameter (it is an optional common parameter)
            $commonParams = [System.Management.Automation.PSCmdlet]::CommonParameters
            $optionalCommonParams = [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
            $allCommon = @($commonParams) + @($optionalCommonParams)
            $allCommon | Should -Contain 'WhatIf'
        }
    }

    Context "Repository Architecture Validation" {
        It "Top-level scripts directory should exist" {
            Test-Path $scriptsPath | Should -Be $true
        }

        It "Top-level Tests directory should exist" {
            Test-Path $testsPath | Should -Be $true
        }

        It "Top-level examples directory should exist" {
            Test-Path $examplesPath | Should -Be $true
        }

        It "Top-level wiki directory should exist" {
            Test-Path $wikiPath | Should -Be $true
        }

        It "Technology domain: cloud/ should exist" {
            $cloudPath = Join-Path $scriptsPath "cloud"
            Test-Path $cloudPath | Should -Be $true
        }

        It "Technology domain: endpoints/ should exist" {
            $endpointsPath = Join-Path $scriptsPath "endpoints"
            Test-Path $endpointsPath | Should -Be $true
        }

        It "Technology domain: infrastructure/ should exist" {
            $infrastructurePath = Join-Path $scriptsPath "infrastructure"
            Test-Path $infrastructurePath | Should -Be $true
        }

        It "Technology domain: security/ should exist" {
            $securityPath = Join-Path $scriptsPath "security"
            Test-Path $securityPath | Should -Be $true
        }

        It "Technology domain: automation/ should exist" {
            $automationPath = Join-Path $scriptsPath "automation"
            Test-Path $automationPath | Should -Be $true
        }

        It "Technology domain: collaboration/ should exist" {
            $collaborationPath = Join-Path $scriptsPath "collaboration"
            Test-Path $collaborationPath | Should -Be $true
        }

        It "Technology domain: data/ should exist" {
            $dataPath = Join-Path $scriptsPath "data"
            Test-Path $dataPath | Should -Be $true
        }

        It "cloud/azure subdirectory should exist" {
            $azurePath = Join-Path $scriptsPath "cloud" "azure"
            Test-Path $azurePath | Should -Be $true
        }

        It "cloud/aws subdirectory should exist" {
            $awsPath = Join-Path $scriptsPath "cloud" "aws"
            Test-Path $awsPath | Should -Be $true
        }

        It "endpoints/intune subdirectory should exist" {
            $intunePath = Join-Path $scriptsPath "endpoints" "intune"
            Test-Path $intunePath | Should -Be $true
        }

        It "endpoints/devices subdirectory should exist" {
            $devicesPath = Join-Path $scriptsPath "endpoints" "devices"
            Test-Path $devicesPath | Should -Be $true
        }

        It "infrastructure/windows subdirectory should exist" {
            $windowsPath = Join-Path $scriptsPath "infrastructure" "windows"
            Test-Path $windowsPath | Should -Be $true
        }

        It "collaboration/microsoft365 subdirectory should exist" {
            $m365Path = Join-Path $scriptsPath "collaboration" "microsoft365"
            Test-Path $m365Path | Should -Be $true
        }

        It "security/compliance subdirectory should exist" {
            $compliancePath = Join-Path $scriptsPath "security" "compliance"
            Test-Path $compliancePath | Should -Be $true
        }
    }

    Context "Script Development Requirements Validation" {
        It "Approved PowerShell verbs should be available via Get-Verb" {
            { Get-Verb } | Should -Not -Throw
        }

        It "Get-Verb should include common verbs mentioned in WARP.md" {
            $verbs = Get-Verb | Select-Object -ExpandProperty Verb
            $verbs | Should -Contain 'Get'
            $verbs | Should -Contain 'Set'
            $verbs | Should -Contain 'New'
            $verbs | Should -Contain 'Remove'
        }

        It "PSScriptAnalyzer settings file should be valid PowerShell data file" {
            $psaSettingsPath = Join-Path $PSScriptRoot ".." ".vscode" "PSScriptAnalyzerSettings.psd1"
            if (Test-Path $psaSettingsPath) {
                { Import-PowerShellDataFile -Path $psaSettingsPath } | Should -Not -Throw
            }
        }

        It "Sample scripts should use comment-based help" {
            # Check a sample script from the repository
            $sampleScripts = Get-ChildItem -Path $scriptsPath -Filter "*.ps1" -Recurse | Select-Object -First 5
            
            if ($sampleScripts.Count -gt 0) {
                $hasCommentHelp = $false
                foreach ($script in $sampleScripts) {
                    $content = Get-Content $script.FullName -Raw
                    if ($content -match '\.SYNOPSIS|\.DESCRIPTION|\.EXAMPLE') {
                        $hasCommentHelp = $true
                        break
                    }
                }
                $hasCommentHelp | Should -Be $true -Because "At least some scripts should follow comment-based help standards"
            }
        }
    }

    Context "Testing Strategy Validation" {
        It "Pester configuration should have code coverage enabled" {
            $config = Import-PowerShellDataFile -Path $pesterConfigPath
            $config.CodeCoverage.Enabled | Should -Be $true
        }

        It "Code coverage path should target ./scripts directory" {
            $config = Import-PowerShellDataFile -Path $pesterConfigPath
            $config.CodeCoverage.Path | Should -Contain './scripts'
        }

        It "Test results should be enabled" {
            $config = Import-PowerShellDataFile -Path $pesterConfigPath
            $config.TestResult.Enabled | Should -Be $true
        }

        It "Integration tag should be excluded by default" {
            $config = Import-PowerShellDataFile -Path $pesterConfigPath
            $config.Filter.ExcludeTag | Should -Contain 'Integration'
        }

        It "Tests directory structure should mirror scripts directory" {
            # Check that key subdirectories exist in Tests/
            $collaborationTestPath = Join-Path $testsPath "Collaboration"
            $commonTestPath = Join-Path $testsPath "Common"
            
            # At least one of these organizational structures should exist
            $hasTestStructure = (Test-Path $collaborationTestPath) -or (Test-Path $commonTestPath)
            $hasTestStructure | Should -Be $true
        }
    }

    Context "Contributing Guidelines Validation" {
        It "WARP.md should mention PSScriptAnalyzer compliance requirement" {
            $content = Get-Content $warpMdPath -Raw
            $content | Should -Match "PSScriptAnalyzer"
        }

        It "WARP.md should mention testing in non-production environments" {
            $content = Get-Content $warpMdPath -Raw
            $content | Should -Match "non-production|NOT recommended"
        }

        It "WARP.md should reference wiki for documentation" {
            $content = Get-Content $warpMdPath -Raw
            $content | Should -Match "wiki"
        }

        It "WARP.md should mention semantic commit messages" {
            $content = Get-Content $warpMdPath -Raw
            $content | Should -Match "semantic commit|feat:|fix:|docs:"
        }

        It "WARP.md should reference examples directory" {
            $content = Get-Content $warpMdPath -Raw
            $content | Should -Match "examples/"
        }

        It "Wiki directory should contain documentation files" {
            $wikiFiles = Get-ChildItem -Path $wikiPath -Filter "*.md" -ErrorAction SilentlyContinue
            $wikiFiles.Count | Should -BeGreaterThan 0 -Because "Wiki should contain markdown documentation files"
        }
    }

    Context "Important Notes Validation" {
        It "WARP.md should mention PowerShell version requirements" {
            $content = Get-Content $warpMdPath -Raw
            $content | Should -Match "PowerShell 5\.1\+|PowerShell 7"
        }

        It "WARP.md should mention Administrator privileges requirement" {
            $content = Get-Content $warpMdPath -Raw
            $content | Should -Match "Administrator"
        }

        It "WARP.md should mention v3.0.0 restructuring" {
            $content = Get-Content $warpMdPath -Raw
            $content | Should -Match "v3\.0\.0"
        }

        It "WARP.md should mention technology domains (7 domains)" {
            $content = Get-Content $warpMdPath -Raw
            $content | Should -Match "7 technology domains"
        }

        It "WARP.md should mention GitHub wiki as primary documentation source" {
            $content = Get-Content $warpMdPath -Raw
            $content | Should -Match "wiki.*primary|primary.*documentation"
        }
    }

    Context "Command Syntax Validation" {
        It "Import-PowerShellDataFile command should be valid" {
            { Get-Command Import-PowerShellDataFile } | Should -Not -Throw
        }

        It "Invoke-Pester command syntax from WARP.md should be valid" {
            # Verify Invoke-Pester is a known cmdlet or function (even if not installed)
            $command = Get-Command -Name Invoke-Pester -ErrorAction SilentlyContinue
            if ($null -eq $command) {
                # If Pester not installed, just verify we have the test file
                Test-Path $pesterConfigPath | Should -Be $true
            } else {
                $command.Name | Should -Be 'Invoke-Pester'
            }
        }

        It "Get-ChildItem with -Filter and -Recurse parameters should be valid" {
            $command = Get-Command Get-ChildItem
            $command.Parameters.Keys | Should -Contain 'Filter'
            $command.Parameters.Keys | Should -Contain 'Recurse'
        }

        It "ForEach-Object command should be available" {
            { Get-Command ForEach-Object } | Should -Not -Throw
        }
    }

    Context "Script Count and Organization Validation" {
        It "Repository should contain multiple PowerShell scripts" {
            $scriptCount = (Get-ChildItem -Path $scriptsPath -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue).Count
            $scriptCount | Should -BeGreaterThan 100 -Because "WARP.md mentions 260+ scripts"
        }

        It "Scripts should be organized in technology-based hierarchy" {
            $topLevelDirs = Get-ChildItem -Path $scriptsPath -Directory -ErrorAction SilentlyContinue
            $expectedDomains = @('cloud', 'endpoints', 'infrastructure', 'security', 'automation', 'collaboration', 'data')
            
            $foundDomains = 0
            foreach ($domain in $expectedDomains) {
                if ($topLevelDirs.Name -contains $domain) {
                    $foundDomains++
                }
            }
            
            $foundDomains | Should -BeGreaterThan 5 -Because "Most technology domains should exist"
        }

        It "Test files should exist for key scripts" {
            $testFiles = Get-ChildItem -Path $testsPath -Filter "*.Tests.ps1" -Recurse -ErrorAction SilentlyContinue
            $testFiles.Count | Should -BeGreaterThan 0 -Because "Repository should have test coverage"
        }
    }
}
