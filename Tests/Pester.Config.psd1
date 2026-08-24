@{
    # Pester configuration file
    # This file defines default settings for running Pester tests

    Run = @{
        Path = @('./Tests')
        PassThru = $true
        Exit = $false
    }

    # Coverage is COLLECTED (JaCoCo XML for artifact upload) but no line-percentage
    # threshold is enforced. The enforced coverage contract is per-script test presence
    # (every script has a mirrored *.Tests.ps1 under Tests/), NOT a line-coverage percentage.
    CodeCoverage = @{
        Enabled = $true
        Path = @('./scripts', './src/BugFreeUmbrella')
        OutputPath = './Tests/CodeCoverage.xml'
        OutputFormat = 'JaCoCo'
        OutputEncoding = 'UTF8'
        RecursePaths = $true
    }

    TestResult = @{
        Enabled = $true
        OutputPath = './Tests/TestResults.xml'
        OutputFormat = 'NUnitXml'
        OutputEncoding = 'UTF8'
    }

    Output = @{
        Verbosity = 'Detailed'
        StackTraceVerbosity = 'Filtered'
        CIFormat = 'Auto'
    }

    Should = @{
        ErrorAction = 'Stop'
    }

    Debug = @{
        ShowFullErrors = $false
        WriteDebugMessages = $false
        WriteDebugMessagesFrom = @('Mock', 'ParameterBinding')
        ShowNavigationMarkers = $false
        ReturnRawResultObject = $false
    }

    Filter = @{
        Tag = @()
        ExcludeTag = @('Integration')  # Exclude integration tests by default
        Line = @()
        FullName = @()
    }
}
