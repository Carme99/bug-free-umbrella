@{
    # Pester configuration file
    # This file defines default settings for running Pester tests

    Run = @{
        Path = @('./Tests')
        PassThru = $true
        Exit = $false
    }

    CodeCoverage = @{
        Enabled = $true
        Path = @('./scripts', './src/BugFreeUmbrella')
        OutputPath = './Tests/CodeCoverage.xml'
        OutputFormat = 'JaCoCo'
        OutputEncoding = 'UTF8'
        RecursePaths = $true
        CoveragePercentTarget = 30
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
