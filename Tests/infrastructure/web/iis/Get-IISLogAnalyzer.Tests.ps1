#Requires -Modules Pester

Describe "Get-IISLogAnalyzer" {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot "../../../../scripts/infrastructure/web/iis/Get-IISLogAnalyzer.ps1"
        $scriptText = Get-Content -LiteralPath $scriptPath -Raw

        # Safe: the script's top-level guard skips Main when dot-sourced.
        . $scriptPath

        # Avoid touching the real home directory when resolving the Reports folder.
        Mock New-Item { }

        function New-TestLogDir {
            param([string[]]$Lines)
            $logDir = Join-Path $TestDrive ("logs-" + [guid]::NewGuid().ToString('N'))
            [void][System.IO.Directory]::CreateDirectory($logDir)
            Set-Content -LiteralPath (Join-Path $logDir 'u_ex260823.log') -Value $Lines
            return $logDir
        }
    }

    Context "Help & Metadata" {
        It "Declares the complete header block" {
            $scriptText | Should -Match '(?m)^\.SYNOPSIS'
            $scriptText | Should -Match '(?m)^\.DESCRIPTION'
            $scriptText | Should -Match '(?m)^\.NOTES'
        }

        It "Populates all five .NOTES fields correctly" {
            $scriptText | Should -Match 'File Name\s*:\s*Get-IISLogAnalyzer\.ps1'
            $scriptText | Should -Match 'Author\s*:\s*\S'
            $scriptText | Should -Match 'Prerequisite\s*:\s*PowerShell'
            $scriptText | Should -Match 'Version\s*:\s*1\.0\.0'
            $scriptText | Should -Match 'Date\s*:\s*2026-08-23'
        }

        It "Has at least 2 examples with PS C:\> prompts" {
            ([regex]::Matches($scriptText, '(?m)^\.EXAMPLE')).Count | Should -BeGreaterOrEqual 2
            ([regex]::Matches($scriptText, [regex]::Escape('PS C:\>'))).Count | Should -BeGreaterOrEqual 2
        }

        It "Documents one .PARAMETER per declared parameter, in order" {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
            $declared = $ast.ParamBlock.Parameters.Name.VariablePath.UserPath
            $documented = [regex]::Matches($scriptText, '(?m)^\.PARAMETER\s+(\S+)') |
                    ForEach-Object { $_.Groups[1].Value }
            $documented | Should -Be $declared
        }
    }

    Context "Syntax & Static" {
        It "Parses with zero errors" {
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                    $scriptPath, [ref]$tokens, [ref]$errors) | Out-Null
            $errors | Should -BeNullOrEmpty
        }

        It "Contains no PS7-only operators without a #Requires -Version 7.0 opt-out" {
            if ($scriptText -notmatch '(?m)^#Requires\s+-Version\s+7\.0') {
                $tokens = $null
                $parseErrors = $null
                [System.Management.Automation.Language.Parser]::ParseInput(
                        $scriptText, [ref]$tokens, [ref]$parseErrors) | Out-Null
                $kindType = [System.Management.Automation.Language.TokenKind]
                $ps7Kinds = @('AmpersandAmpersand', 'BarBar', 'QuestionMark', 'QuestionQuestionEquals') |
                    Where-Object { $kindType.GetMember($_) }
                $offenders = @($tokens | Where-Object { $ps7Kinds -contains [string]$_.Kind })
                $offenders | Should -BeNullOrEmpty -Because "PS7-only operators require #Requires opt-out"
            }
        }

        It "Uses the mandatory Main entrypoint and dot-source guard" {
            $guard = "if (`$MyInvocation.InvocationName -ne '.') { exit (Main) }"
            $scriptText.Contains($guard) | Should -BeTrue
        }
    }

    Context "Behavior" {
        It "Parses W3C log entries and returns 0 with success output" {
            $LogPath = New-TestLogDir -Lines @(
                '#Software: Microsoft IIS'
                '#Date: 2026-08-23'
                '2026-08-23 12:00:00 10.0.0.1 GET /index.html - 80 - 172.16.0.9 Mozilla/5.0 - 200 0 120 512'
                '2026-08-23 12:01:00 10.0.0.2 POST /api/login user=1 443 - 172.16.0.9 Mozilla/5.0 - 401 0 340 1024'
            )
            $out = Main *>&1

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match '\[\+\] Found 1 log files'
            ($out | Out-String) | Should -Match 'Parsed 2 log entries \(0 parse errors\)'
        }

        It "Returns 1 with [!] output when no log files exist in range" {
            $LogPath = New-TestLogDir -Lines @()
            Remove-Item -LiteralPath (Join-Path $LogPath 'u_ex260823.log') -Force

            $out = Main *>&1

            ($out | Out-String) | Should -Match '\[!\]'
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
        }

        It "Detects SQL injection attempts when -IncludeSecurityAnalysis is set" {
            $LogPath = New-TestLogDir -Lines @(
                '2026-08-23 12:00:00 10.0.0.1 GET /index.html - 80 - 172.16.0.9 Mozilla/5.0 - 200 0 120 512'
                '2026-08-23 13:00:00 10.0.0.66 GET /index.html?q=union+select - 80 - 172.16.0.66 sqlmap - 200 0 55 100'
            )
            $IncludeSecurityAnalysis = $true
            $out = Main *>&1
            $text = $out | Out-String

            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text | Should -Match 'Security Threats Detected:'
            $text | Should -Match 'SQL Injection'
        }
    }
}
