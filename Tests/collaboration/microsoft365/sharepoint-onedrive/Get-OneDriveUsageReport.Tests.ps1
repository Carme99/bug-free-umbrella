#Requires -Modules Pester

Describe 'Get-OneDriveUsageReport' {
    BeforeAll {
        # Mirrored layout: this file lives at Tests/collaboration/microsoft365/sharepoint-onedrive/ ->
        # the script is four levels up plus across under scripts/.
        $scriptDir = Join-Path $PSScriptRoot '../../../../scripts/collaboration/microsoft365/sharepoint-onedrive'
        $scriptPath = Join-Path $scriptDir 'Get-OneDriveUsageReport.ps1'

        # Sample Graph OneDrive usage CSV rows (headers match the report schema the script parses).
        $csvHeader = @(
            'Report Refresh Date','Site URL','Owner Display Name','Owner Principal Name','Is Deleted'
            'Last Activity Date','File Count','Active File Count','Storage Used (Byte)','Storage Allocated (Byte)'
        ) -join ','
        $heavyRow = @(
            '2026-08-22','https://contoso-my.sharepoint.com/personal/alice_contoso_com'
            'Alice Heavy','alice@contoso.com','False','2026-08-20','5000','1200','9663676416','10737418240'
        ) -join ','
        $staleRow = @(
            '2026-08-22','https://contoso-my.sharepoint.com/personal/bob_contoso_com'
            'Bob Stale','bob@contoso.com','False','2026-01-15','120','3','1073741824','10737418240'
        ) -join ','

        # Stub product-module cmdlets not installed on this machine so Pester can mock them.
        function Write-ReportTextFile { }

        # Safe: the top-level guard skips Main when dot-sourced.
        . $scriptPath
        function Connect-MgGraph { }
        function Disconnect-MgGraph { }
        function Get-MgReportOneDriveUsageAccountDetail { }

        # Mock ALL external commands so nothing leaves the machine (offline Linux CI).
        # The Graph cmdlet writes a CSV to -OutFile; the script then Import-Csv's it for real.
        Mock Get-Module { [pscustomobject]@{ Name = 'Microsoft.Graph' } }
        Mock Connect-MgGraph { }
        Mock Disconnect-MgGraph { }
        Mock Get-MgReportOneDriveUsageAccountDetail { param($Period, $OutFile)
            Set-Content -Path $OutFile -Value @($csvHeader, $heavyRow, $staleRow) -Encoding UTF8
        }
        Mock Remove-Item { }
        Mock Test-Path { $true }
        Mock New-Item { }
        Mock Write-ReportTextFile { }
        Mock Export-Csv { }

    }

    Context 'Help & Metadata' {
        It 'Declares Version 1.0.0 and relaunch Date 2026-08-23 in .NOTES' {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match '(?m)^\s*Version\s*:\s*1\.0\.0\s*$'
            $raw | Should -Match '(?m)^\s*Date\s*:\s*2026-08-23\s*$'
        }

        It 'Records File Name matching the disk filename and PowerShell 7.0 prerequisite' {
            $raw = Get-Content -Path $scriptPath -Raw
            $raw | Should -Match '(?m)^\s*File Name\s*:\s*Get-OneDriveUsageReport\.ps1\s*$'
            $raw | Should -Match '(?m)^\s*Prerequisite\s*:\s*PowerShell 7\.0\s*$'
        }

        It 'Has exactly one .PARAMETER entry per declared parameter, in declaration order' {
            $toks = $null
            $errs = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$toks, [ref]$errs)
            $declaredParams = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
            $helpParams = @(Select-String -Path $scriptPath -Pattern '^\s*\.PARAMETER\s+(\S+)' |
                ForEach-Object { $_.Matches[0].Groups[1].Value })
            $helpParams.Count | Should -Be $declaredParams.Count
            $helpParams | Should -Be $declaredParams
        }

        It 'Provides at least two .EXAMPLE blocks with PS C:\> prompt lines' {
            $raw = Get-Content -Path $scriptPath -Raw
            ([regex]::Matches($raw, '(?m)^\.EXAMPLE\s*$')).Count | Should -BeGreaterOrEqual 2
            $raw | Should -Match 'PS C:\\>'
        }
    }

    Context 'Syntax & Static' {
        It 'Parses with zero syntax errors' {
            $toks = $null
            $errs = $null
            [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$toks, [ref]$errs) | Out-Null
            $parseErrors | Should -BeNullOrEmpty
        }

        It 'Contains no PS7-only operators unless #Requires -Version 7.0 is present' {
            $raw = Get-Content -Path $scriptPath -Raw
            if ($raw -notmatch '(?m)^#Requires\s+-Version\s+7\.0') {
                $raw | Should -Not -Match '\?\?|\?\?=|\|\||&&'
            }
        }

        It 'Uses exit only in the top-level dot-source guard line' {
            $toks = $null
            $errs = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$toks, [ref]$errs)
            $findExit = { $args[0] -is [System.Management.Automation.Language.ExitStatementAst] }
            $exitStatements = @($ast.FindAll($findExit, $true))
            $exitStatements.Count | Should -Be 1
            $exitStatements[0].Parent.ToString() | Should -Match 'exit \(Main\)'
        }

        It 'Is saved as UTF-8 with BOM and CRLF line endings' {
            $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
            ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeTrue
            $text = [System.IO.File]::ReadAllText($scriptPath)
            $text | Should -Not -Match '(?<!\r)\n'
        }
    }

    Context 'Behavior' {
        It 'Connects to Microsoft Graph and returns 0 with site counts' {
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $text = $out | Out-String
            $text | Should -Match '\[\*\] Connecting to Microsoft Graph'
            $text | Should -Match '\[\+\] Found 2 OneDrive site\(s\)'
            $text | Should -Match '\[\*\] Total Storage Used: 10 GB'
            Should -Invoke Connect-MgGraph -Times 1 -Exactly
            Should -Invoke Disconnect-MgGraph -Times 1 -Exactly
        }

        It 'Flags sites above the storage warning threshold as warnings' {
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'Storage Warnings \(> 80%\): 1'
        }

        It 'Counts sites older than the inactivity threshold as inactive' {
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            ($out | Out-String) | Should -Match 'Inactive Sites \(> 90 days\): 1'
        }

        It 'Exports results through Export-Csv when -ExportCSV is set' {
            $ExportCSV = $true
            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 0
            $filter = { $Path -like '*OneDriveUsageReport_*.csv' }
            Should -Invoke Export-Csv -ParameterFilter $filter
        }

        It 'Returns 1 when the SharePoint Online module is missing' {
            Mock Get-Module { $null }

            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\] SharePoint Online module not found!'
        }

        It 'Returns 1 and writes [-] output when the Graph connection fails' {
            Mock Connect-MgGraph { throw 'sign-in was cancelled' }

            $out = Main *>&1
            ($out | Where-Object { $_ -is [int] }) | Should -Be 1
            ($out | Out-String) | Should -Match '\[-\] Error: sign-in was cancelled'
        }

        It 'Is idempotent: repeated read-only runs both return 0' {
            (Main *>&1) | Where-Object { $_ -is [int] } | Should -Be 0
            (Main *>&1) | Where-Object { $_ -is [int] } | Should -Be 0
        }
    }
}
