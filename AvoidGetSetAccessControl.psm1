<#
    .SYNOPSIS
         Generates errors for GetAccessControl() or SetAccessControl() calls
    .DESCRIPTION
    
    .INPUTS
        [System.Management.Automation.Language.ScriptBlockAst]
    .OUTPUTS
        [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]]
#>
function PS7NoGetSetAccessControl {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param (
        # Generic script block we are using to run our predicate against.
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]
        $ScriptBlockAst
    )

    $accessControlMethodsPredicate = {
        param (
            [System.Management.Automation.Language.Ast]
            $Ast
        )
        $Ast -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
            $Ast.Member.ToString() -match '(Set|Get)AccessControl'
    }
    $violations = $ScriptBlockAst.FindAll($accessControlMethodsPredicate, $false)

    foreach ($violation in $violations) {
        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
            Message  = ('In PS7, GetAccessControl and SetAccessControl are not available. Please use Get-Acl and' +
                       ' Set-Acl')
            Extent   = $violation.Extent
            RuleName = $MyInvocation.MyCommand
            Severity = 'Error'
        }
    }
}
