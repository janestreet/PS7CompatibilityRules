using namespace Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic
using namespace System.Management.Automation.Language
function EnsureProperUseOfDotNetMethods {
    <#
    .SYNOPSIS
        Flag some .NET method calls that have different behavior in PS7/.NET Core
    .EXAMPLE
        EnsureProperUseOfDotNetMethods -ScriptBlockAst $Ast
    .INPUTS
        [ScriptBlockAst]
    .OUTPUTS
        [DiagnosticRecord[]]
    #>
    [CmdletBinding()]
    [OutputType([DiagnosticRecord[]])]
    param (
        # The scriptblock we will be using to find violations matching the defined predicate.
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ScriptBlockAst]
        $ScriptBlockAst
    )


    # Hashtable containing method names to validate and the criteria for when to flag it
    # the '$_' object in the criteria scriptblock will always be an AST of type [InvokeMemberExpressionAst]
    $methodsToValidate = @{
        'Split' = @{
            Criteria = {
                # We flag Split method invocation when there is a single argument and the argument is a variable or
                # a multi character string
                $_.Arguments.Count -eq 1 -and
                ($_.Arguments[0] -is [VariableExpressionAst] -or
                ($_.Arguments[0] -is [StringConstantExpressionAst] -and $_.Arguments[0].Value.Length -ne 1))
            }
            Message = ('The Split method behaves differently between PS5 and PS7 due to .NET changes. ' +
                       'Use -split or -csplit with regex instead.')
        }
    }

    $methodInvocationPredicate = {
        param (
            [Ast]
            $Ast
        )
        $Ast -is [InvokeMemberExpressionAst] -and
            # $Ast.Member can be a variable - we don't care about that.
            $Ast.Member -is [StringConstantExpressionAst] -and
            $methodsToValidate.ContainsKey($Ast.Member.Value) -and
            [bool]($Ast | where $methodsToValidate[$Ast.Member.Value].Criteria)
    }
    $violations = $ScriptBlockAst.FindAll($methodInvocationPredicate, $false)

    foreach ($violation in $violations) {
        $methodViolation = $methodsToValidate[$violation.Member.Value]
        [DiagnosticRecord]@{
            Message           = "Recommendation: $($methodViolation.Message)"
            Extent            = $violation.Extent
            RuleName          = $MyInvocation.MyCommand
            Severity          = 'Warning'
            RuleSuppressionId = $violation.Member.Value
        }
    }
}
