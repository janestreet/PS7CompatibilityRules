<#
    .SYNOPSIS
        Select-Object ExcludeProperty is effective only when the command also includes a Property parameter
    .DESCRIPTION
        In PowerShell 5, Select-Object wouldn't modify the incoming object if ExcludeProperty was specified without
        Property parameter. In PowerShell 7 that is no longer the case, output would now be of type Selected.* so
        attempts to call methods and other operations that worked in PS5 could potentially fail. Ensuring that
        -Property is always specified will have consistent behaviour in PS5 and PS7.
    .INPUTS
        [System.Management.Automation.Language.ScriptBlockAst]
    .OUTPUTS
        [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]]
#>
function SelectObjectMustSpecifyProperty {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param (
        # Generic script block we are using to run our predicate against.
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]
        $ScriptBlockAst
    )

    $selectObjectCommandPredicate = {
        param (
            [System.Management.Automation.Language.Ast]
            $Ast
        )
        $Ast -is [System.Management.Automation.Language.CommandAst] -and
            $Ast.CommandElements[0].StringConstantType -eq 'BareWord' -and
            $Ast.CommandElements[0].Value -in @('Select-Object', 'select')
    }
    $selectObjectCommands = $ScriptBlockAst.FindAll($selectObjectCommandPredicate, $true)

    $violations = $selectObjectCommands | where {
        $paramBindingResult = [System.Management.Automation.Language.StaticParameterBinder]::BindCommand($_, $true)
        $paramBindingResult.BoundParameters.ContainsKey('ExcludeProperty') -and
            -not $paramBindingResult.BoundParameters.ContainsKey('Property')
    }

    foreach ($violation in $violations) {
        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
            Message  = ('Select-Object -ExcludeProperty is effective only when the command also includes the ' +
                       '-Property parameter')
            Extent   = $violation.Extent
            RuleName = $MyInvocation.MyCommand
            Severity = 'Error'
        }
    }
}
