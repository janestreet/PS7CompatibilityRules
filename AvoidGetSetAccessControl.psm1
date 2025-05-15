using namespace Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic
using namespace System.Management.Automation.Language
function AvoidGetSetAccessControl {
    <#
    .SYNOPSIS
        Generates errors for GetAccessControl() or SetAccessControl() calls
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

    $accessControlMethodsPredicate = {
        param (
            [Ast]
            $Ast
        )
        $Ast -is [InvokeMemberExpressionAst] -and
            $Ast.Member.ToString() -match '(Set|Get)AccessControl'
    }
    $violations = $ScriptBlockAst.FindAll($accessControlMethodsPredicate, $false)

    foreach ($violation in $violations) {
        [DiagnosticRecord]@{
            Message           = ("In PS7, the $($violation.Member.ToString()) method is not available. Please " +
                                'use Get-Acl and Set-Acl')
            Extent            = $violation.Extent
            RuleName          = $MyInvocation.MyCommand
            Severity          = 'Error'
            RuleSuppressionID = $violation.Member.ToString()
        }
    }
}
