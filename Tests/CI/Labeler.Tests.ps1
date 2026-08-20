#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for the issue-labeler workflow regex logic.

.DESCRIPTION
    Validates that the label detection regexes used in .github/workflows/issue-labeler.yml
    correctly match representative issue titles and bodies. These tests run in CI via
    the test job in validate-powershell.yml and demonstrate that the Pester harness works.
    The regexes are intentionally duplicated from the workflow to catch drift.

.NOTES
    File Name      : Labeler.Tests.ps1
    Author         : Carme99
    Prerequisite   : Pester 5.5.0+
    Version        : 1.0.0
    Date           : 2026-08-20
#>

Describe "Issue Labeler - Technology Domain Detection" {

    BeforeAll {
        function Get-LabelsForIssue {
            [CmdletBinding()]
            param(
                [string]$Title,
                [string]$Body = ''
            )
            $combined = ("$Title $Body").ToLower()
            $labels = @()

            if ($combined -match '\b(azure|az-|microsoft azure)\b') { $labels += 'azure' }
            if ($combined -match '\b(aws|amazon web services)\b') { $labels += 'aws' }
            if ($combined -match '\b(docker|container|kubernetes|k8s)\b') { $labels += 'containers' }
            if ($combined -match '\b(intune|mem|endpoint manager)\b') { $labels += 'intune' }
            if ($combined -match '\b(winget|windows package manager)\b') { $labels += 'winget' }
            if ($combined -match '\b(proactive remediation|remediation script)\b') { $labels += 'proactive-remediations' }
            if ($combined -match '\b(autopatch|windows update)\b') { $labels += 'windows-update' }
            if ($combined -match '\b(bitlocker|encryption)\b') { $labels += 'bitlocker' }
            if ($combined -match '\b(windows server|server 2019|server 2022)\b') { $labels += 'windows-server' }
            if ($combined -match '\b(active directory|ad |domain controller)\b') { $labels += 'active-directory' }
            if ($combined -match '\b(group policy|gpo)\b') { $labels += 'group-policy' }
            if ($combined -match '\b(hyper-v|vmware|virtualization)\b') { $labels += 'virtualization' }
            if ($combined -match '\b(iis|web server)\b') { $labels += 'iis' }
            if ($combined -match '\b(linux|ubuntu|centos|rhel)\b') { $labels += 'linux' }
            if ($combined -match '\b(network|dns|dhcp|routing)\b') { $labels += 'networking' }
            if ($combined -match '\b(security|compliance|audit)\b') { $labels += 'security' }
            if ($combined -match '\b(cis|nist|pci-dss|hipaa|soc2|iso27001)\b') { $labels += 'compliance' }
            if ($combined -match '\b(hardening|baseline|security baseline)\b') { $labels += 'hardening' }
            if ($combined -match '\b(ci\/cd|pipeline|azure devops|github actions|gitlab)\b') { $labels += 'devops' }
            if ($combined -match '\b(terraform|bicep|infrastructure as code|iac)\b') { $labels += 'iac' }
            if ($combined -match '\b(microsoft 365|m365|office 365|o365)\b') { $labels += 'microsoft-365' }
            if ($combined -match '\b(exchange online|exchange server)\b') { $labels += 'exchange' }
            if ($combined -match '\b(teams|microsoft teams)\b') { $labels += 'teams' }
            if ($combined -match '\b(sharepoint|onedrive)\b') { $labels += 'sharepoint' }
            if ($combined -match '\b(azure ad|entra id|aad)\b') { $labels += 'azure-ad' }
            if ($combined -match '\b(defender|microsoft defender)\b') { $labels += 'defender' }
            if ($combined -match '\b(sql server|mysql|postgresql|mongodb|database)\b') { $labels += 'database' }
            if ($combined -match '\b(api|rest api|graph api)\b') { $labels += 'api' }
            if ($combined -match '\b(bug|error|problem|broken|fail|crash|exception)\b') { $labels += 'bug' }
            if ($combined -match '\b(feature request|enhancement|improvement|suggestion|would like|could you add|can you add|please add)\b') { $labels += 'enhancement' }
            if ($combined -match '\b(documentation|docs|readme|wiki|guide|tutorial|example)\b') { $labels += 'documentation' }
            if ($combined -match '\b(question|help|how to|how do|support)\b' -or $Title.ToLower().Contains('?')) { $labels += 'question' }
            if ($combined -match '\b(performance|slow|optimization|speed|timeout)\b') { $labels += 'performance' }
            if ($combined -match '\b(test|testing|pester|unit test|validation)\b') { $labels += 'testing' }
            if ($combined -match '\b(critical|urgent|emergency|security vulnerability|broken)\b') { $labels += 'priority-high' }
            if ($combined -match '\b(good first issue|good-first-issue|beginner|easy|simple)\b') { $labels += 'good-first-issue' }

            return $labels
        }
    }

    Context "Primary technology domains" {

        It "Should label 'Intune device compliance' with intune" {
            $labels = Get-LabelsForIssue -Title 'Intune device compliance'
            $labels | Should -Contain 'intune'
        }

        It "Should label Azure-related title with azure" {
            $labels = Get-LabelsForIssue -Title 'Azure cost optimization for VMs'
            $labels | Should -Contain 'azure'
        }

        It "Should label Winget issue with winget" {
            $labels = Get-LabelsForIssue -Title 'Winget package update fails on Windows 11'
            $labels | Should -Contain 'winget'
        }

        It "Should label Microsoft 365 issue with microsoft-365" {
            $labels = Get-LabelsForIssue -Title 'Microsoft 365 license assignment script error'
            $labels | Should -Contain 'microsoft-365'
        }
    }

    Context "Issue type and priority" {

        It "Should label bug report with bug" {
            $labels = Get-LabelsForIssue -Title 'Bug: script crashes on empty input' -Body 'Exception thrown'
            $labels | Should -Contain 'bug'
        }

        It "Should normalize 'good first issue' to 'good-first-issue'" {
            $labels = Get-LabelsForIssue -Title 'Good first issue: add documentation example'
            $labels | Should -Contain 'good-first-issue'
            $labels | Should -Not -Contain 'good first issue'
        }

        It "Should handle hyphenated good-first-issue" {
            $labels = Get-LabelsForIssue -Title 'good-first-issue: easy fix for beginners'
            $labels | Should -Contain 'good-first-issue'
        }

        It "Should label question when title contains ?" {
            $labels = Get-LabelsForIssue -Title 'How to configure Intune compliance policy?'
            $labels | Should -Contain 'question'
        }
    }

    Context "Multiple domains" {

        It "Should detect multiple labels for cross-domain issue" {
            $labels = Get-LabelsForIssue -Title 'Azure Intune device compliance pipeline broken' -Body 'CI/CD pipeline fails'
            $labels | Should -Contain 'azure'
            $labels | Should -Contain 'intune'
            $labels | Should -Contain 'bug'
            $labels | Should -Contain 'devops'
        }
    }
}
