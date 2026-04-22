using namespace Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic
using namespace System.Management.Automation.Language
function AvoidDeprecatedTypes {
    <#
    .SYNOPSIS
        Flag references to deprecated types that are incompatible with PS7
    .DESCRIPTION
        Could not find a definitive list of such deprecated types, adding as and when new ones are discovered
    .INPUTS
        [ScriptBlockAst]
    .OUTPUTS
        [DiagnosticRecord[]]
    #>
    [CmdletBinding()]
    [OutputType([DiagnosticRecord[]])]
    param (
        # Generic script block we are using to run our predicate against.
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ScriptBlockAst]
        $ScriptBlockAst
    )

    $httpClientSuggestion = ('Use System.Net.Http.HttpClient & System.Net.Http.HttpClientHandler to ensure ' +
        'compatibility with PS7 and future versions')

    $deprecatedTypes = @{
        # https://learn.microsoft.com/en-us/dotnet/core/compatibility/networking/6.0/webrequest-deprecated
        'System.Net.WebRequest'          = $httpClientSuggestion
        'System.Net.HttpWebRequest'      = $httpClientSuggestion
        'System.Net.WebClient'           = $httpClientSuggestion
        'System.Net.ServicePoint'        = $httpClientSuggestion
        'System.Net.ServicePointManager' = $httpClientSuggestion
        'System.Net.ServicePointManager_ServerCertificateValidationCallback' = (
            'This method is not available in PS7, you should use Invoke-{RestMethod|WebRequest} with ' +
            "'-SkipCertificateCheck' instead")
        'System.Runtime.Serialization.Formatters.Binary.BinaryFormatter' = ('BinaryFormatter implementation ' +
            'has been removed (PS 7.5 / .NET 9)')
    }

    # PowerShell implicitly resolves unqualified type names against the System namespace, so users may write
    # either [System.Net.WebRequest] or [Net.WebRequest]. Add an entry for the short form of every System.* type
    # so the check matches both spellings.
    $typesWithoutSystemPrefix = @{}

    $deprecatedTypes.GetEnumerator() | foreach {
        if ($_.Key -match '^System\.') {
            $typesWithoutSystemPrefix[$_.Key -replace '^System\.'] = $_.Value
        }
    }
    $typeRecommendations = $deprecatedTypes + $typesWithoutSystemPrefix

    [scriptblock]$codeBlockPredicate = {
        param (
            # AST object we're evaluating if it is relevant to this rule
            [Ast]
            $Ast
        )
        # Match [BadType]::new() style expressions
        ($Ast -is [TypeExpressionAst] -and
            $typeRecommendations.ContainsKey($Ast.TypeName.FullName)
        ) -or
        # Match [BadType]@{} explicit cast style expressions
        ($Ast -is [ConvertExpressionAst] -and
            $typeRecommendations.ContainsKey($Ast.Type.TypeName.FullName)
        ) -or
        # Match New-Object BadType style invocations
        ($Ast -is [CommandAst] -and
            $Ast.GetCommandName() -eq 'New-Object' -and
            ($Ast.CommandElements | where {
                $_ -is [StringConstantExpressionAst] -and
                $_.Value -ne 'New-Object' -and
                $typeRecommendations.ContainsKey($_.Value)
            })
        )
    }

    # Find all matches using the predicate above
    $codeBlockAst = $ScriptBlockAst.FindAll($codeBlockPredicate, $false)

    foreach ($violation in $codeBlockAst) {
        if ($violation -is [TypeExpressionAst]) {
            $suspectTypeName = $violation.TypeName.FullName
        }
        elseif ($violation -is [ConvertExpressionAst]) {
            $suspectTypeName = $violation.Type.TypeName.FullName
        }
        else {
            # New-Object <TypeName> case — find the element that matched a deprecated type
            $strings = $violation.CommandElements | where {
                $_ -is [StringConstantExpressionAst] -and
                $_.Value -ne 'New-Object' -and
                $typeRecommendations.ContainsKey($_.Value)
            }
            # This should never happen because we already found the type name when looking for the violations
            # themselves but if it ever did, we'll just skip to the next violation
            if ($strings.Count -lt 0) {continue}
            $suspectTypeName = $strings[0].Value
        }

        $recommendation = $typeRecommendations[$suspectTypeName]

        # Check if the specific method used has a specific action recommendation
        if ($violation.Parent -is [MemberExpressionAst] -and
            $typeRecommendations.ContainsKey("$($suspectTypeName)_$($violation.Parent.Member.Value)")) {
            $recommendation = $typeRecommendations["$($suspectTypeName)_$($violation.Parent.Member.Value)"]
        }

        [DiagnosticRecord]@{
            Message           = "Violation: $recommendation"
            Extent            = $violation.Extent
            RuleName          = $MyInvocation.MyCommand
            Severity          = 'Error'
            RuleSuppressionID = $suspectTypeName
        }
    }
}
