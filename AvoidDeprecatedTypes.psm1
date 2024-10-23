<#
    .SYNOPSIS
        Flag references to deprecated types that are incompatible with PS7
    .DESCRIPTION
        Could not find a definitive list of such deprecated types, adding as and when new ones are discovered
    .INPUTS
        [System.Management.Automation.Language.ScriptBlockAst]
    .OUTPUTS
        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]]
#>
function AvoidDeprecatedTypes {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param (
        # Generic script block we are using to run our predicate against.
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]
        $ScriptBlockAst
    )

    $httpClientSuggestion = ('Use System.Net.Http.HttpClient & System.Net.Http.HttpClientHandler to ensure ' +
        'compatibility with PS7 and future versions')

    $typeRecommendations = @{
        # https://learn.microsoft.com/en-us/dotnet/core/compatibility/networking/6.0/webrequest-deprecated
        'System.Net.WebRequest'          = $httpClientSuggestion
        'System.Net.HttpWebRequest'      = $httpClientSuggestion
        'System.Net.WebClient'           = $httpClientSuggestion
        'System.Net.ServicePoint'        = $httpClientSuggestion
        'System.Net.ServicePointManager' = $httpClientSuggestion
        'System.Net.ServicePointManager_ServerCertificateValidationCallback' = (
            'This method is not available in PS7, you should use Invoke-{RestMethod|WebRequest} with ' +
            "'-SkipCertificateCheck' instead"
        )
    }

    [scriptblock]$codeBlockPredicate = {
        param (
            # AST object we're evaluating if it is relevant to this rule
            [System.Management.Automation.Language.Ast]
            $Ast
        )
        $Ast -is [System.Management.Automation.Language.TypeExpressionAst] -and
            $typeRecommendations.ContainsKey($Ast.TypeName.FullName)
    }

    # Find all matches using the predicate above
    $codeBlockAst = $ScriptBlockAst.FindAll($codeBlockPredicate, $false)

    foreach ($violation in $codeBlockAst) {
        $suspectTypeName = $violation.TypeName.FullName
        $recommendation = $typeRecommendations[$suspectTypeName]

        # Check if the specific method used has a specific action recommendation
        if ($violation.Parent -is [System.Management.Automation.Language.MemberExpressionAst] -and
            $typeRecommendations.ContainsKey("$($suspectTypeName)_$($violation.Parent.Member.Value)")
        ) {
            $recommendation = $typeRecommendations["$($suspectTypeName)_$($violation.Parent.Member.Value)"]
        }

        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
            Message           = "Violation: $recommendation"
            Extent            = $violation.Extent
            RuleName          = $MyInvocation.MyCommand
            Severity          = 'Error'
            RuleSuppressionID = $suspectTypeName
        }
    }
}
