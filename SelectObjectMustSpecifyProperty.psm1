using namespace Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic
using namespace System.Management.Automation.Language
function SelectObjectMustSpecifyProperty {
    <#
    .SYNOPSIS
        Select-Object ExcludeProperty is effective only when the command also includes a Property parameter
    .DESCRIPTION
        In PowerShell 5, Select-Object wouldn't modify the incoming object if ExcludeProperty was specified without
        Property parameter. In PowerShell 7 that is no longer the case, output would now be of type Selected.* so
        attempts to call methods and other operations that worked in PS5 could potentially fail. Ensuring that
        -Property is always specified will have consistent behaviour in PS5 and PS7.
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

    $selectObjectCommandPredicate = {
        param (
            [Ast]
            $Ast
        )
        $Ast -is [CommandAst] -and
            $Ast.CommandElements[0].StringConstantType -eq 'BareWord' -and
            $Ast.CommandElements[0].Value -in @('Select-Object', 'select')
    }
    $selectObjectCommands = $ScriptBlockAst.FindAll($selectObjectCommandPredicate, $true)

    $violations = $selectObjectCommands | where {
        $paramBindingResult = [StaticParameterBinder]::BindCommand($_, $true)
        $paramBindingResult.BoundParameters.ContainsKey('ExcludeProperty') -and
            -not $paramBindingResult.BoundParameters.ContainsKey('Property')
    }

    foreach ($violation in $violations) {
        [DiagnosticRecord]@{
            Message  = ('Select-Object -ExcludeProperty is effective only when the command also includes the ' +
                       '-Property parameter')
            Extent   = $violation.Extent
            RuleName = $MyInvocation.MyCommand
            Severity = 'Error'
        }
    }
}
