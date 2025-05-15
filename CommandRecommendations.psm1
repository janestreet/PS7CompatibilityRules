using namespace Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic
using namespace System.Management.Automation.Language
function CommandRecommendations {
    <#
    .SYNOPSIS
        Rrecommendations for specific commands that have different behavior in PS7
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

    # CustomExclusionCondition accepts a commandAst and returns a bool. Returning true will exclude the finding
    $commandsRecommendations = @{
        'ConvertFrom-Json' = @{
            Message = ('In PS7, "ConvertFrom-Json" performs automatic conversion on values that look like' +
                      ' datetime which can have adverse effect on your code. Ensure you are not trying to' +
                      ' convert datetime objects again.')
        }
        'Send-MailMessage' = @{
            Message = ('The "Send-MailMessage" cmdlet is obsolete because it doesn''t guarantee secure' +
                      ' connections to SMTP servers. No immediate replacement available in PowerShell')
        }
        'Out-File'         = @{
            Message = ('Default encoding for "Out-File" has changed from unicode to UTF-8NoBOM. Specify' +
                      ' "-Encoding Unicode" to ensure consistent behavior between PS versions.')
            CustomExclusionCondition = {
                $index = @($_.CommandElements.Extent.Text).IndexOf('-Encoding')
                @($_.CommandElements)[$index + 1].Extent.Text -in @('unicode', 'ascii')
            }
        }
    }
    # Dynamically add recommendations for all external programs (EP) (i.e. *.exe)
    # https://github.com/PowerShell/PowerShell/pull/13361
    # https://learn.microsoft.com/en-us/powershell/scripting/learn/experimental-features?view=powershell-7.4#psnativecommanderroractionpreference
    $epRecommendation = ('Ensure you''re not reliant on stderr output from external program generating an' +
                        ' exception. Also, consider $PSNativeCommandUseErrorActionPreference.')

    # Excluding command names that are also executable names
    $overlappingExternalCommands = @('sort', 'where', 'help', 'cd', 'compare')
    # External executable extensions to target
    $epRegex = '\.COM$|\.EXE$|\.BAT$|\.CMD$'

    $epInPath = $env:PATH -split ';' | foreach {
        Get-ChildItem $_.Trim() -ErrorAction SilentlyContinue | where {$_.Name -match $epRegex}
    }
    $epInPath.BaseName | foreach {$commandsRecommendations[$_] = @{Message = $epRecommendation -f $_}}
    $epInPath.Name | foreach {$commandsRecommendations[$_] = @{Message = $epRecommendation -f $_}}

    $commandAstPredicate = {
        param (
            # Generic AST type to be converted.
            [Ast]
            $Ast
        )
        if ($Ast -is [CommandAst]) {
            $maybeEP = $Ast.CommandElements[0].Extent.Text
            if ($commandsRecommendations[$maybeEP] -and $maybeEP -notin $overlappingExternalCommands) {
                if ($commandsRecommendations[$maybeEP].CustomExclusionCondition) {
                    # if anything is returned from Where, it should be excluded. effectively we return false if
                    # anything was found
                    -not [bool]($Ast.Where($commandsRecommendations[$maybeEP].CustomExclusionCondition))
                }
                else {
                    $true
                }
            }
            # Also return any command that ends with any of the extensions specified
            elseif ($maybeEP -match $epRegex) {
                # Adding the executable to the hashtable so we can later retrieve the recommendation
                $commandsRecommendations[$maybeEP] = @{Message = $epRecommendation -f $maybeEP}
                $true
            }
        }
    }
    $violations = $ScriptBlockAst.FindAll($commandAstPredicate, $false)

    foreach ($violation in $violations) {
        $recommendation = $commandsRecommendations[$violation.CommandElements[0].ToString()].Message
        [DiagnosticRecord]@{
            Message           = "Recommendation: $recommendation"
            Extent            = $violation.Extent
            RuleName          = $MyInvocation.MyCommand
            Severity          = 'Info'
            RuleSuppressionID = $violation.CommandElements[0].ToString()
        }
    }
}
