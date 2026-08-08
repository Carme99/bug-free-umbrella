@{
    # Only report Errors and Warnings (not Information)
    Severity = @('Error', 'Warning')

    # Use default rules as a baseline
    IncludeDefaultRules = $true

    # Exclude rules that are too strict or cause false positives
    ExcludeRules = @(
        # Output and formatting
        'PSAvoidUsingWriteHost',              # Scripts need Write-Host for user output
        'PSProvideCommentHelp',               # Not all scripts need full help blocks

        # Style and formatting (too strict for existing codebase)
        'PSUseConsistentIndentation',
        'PSUseConsistentWhitespace',
        'PSPlaceOpenBrace',
        'PSPlaceCloseBrace',
        'PSUseCorrectCasing',

        # Compatibility checks (may be too strict)
        'PSUseCompatibleCmdlets',
        'PSUseCompatibleSyntax',

        # Positional parameters (sometimes needed for brevity)
        'PSAvoidUsingPositionalParameters',

        # Module-specific rules (not applicable to standalone scripts)
        'PSUseBOMForUnicodeEncodedFile',
        'PSUseToExportFieldsInManifest',
        'PSMissingModuleManifestField',

        # ShouldProcess rules (not needed for all scripts)
        'PSShouldProcess',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseSupportsShouldProcess',

        # Other overly strict rules
        'PSReviewUnusedParameter',
        'PSUseDeclaredVarsMoreThanAssignments',

        # Intentional Test-Connection -ComputerName "www.microsoft.com" connectivity probes, not sensitive
        'PSAvoidUsingComputerNameHardcoded'
    )
}
