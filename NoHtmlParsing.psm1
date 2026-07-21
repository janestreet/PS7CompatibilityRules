using namespace Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic
using namespace System.Management.Automation.Language
function NoHtmlParsing {
    <#
    .SYNOPSIS
        Flag code that relies on HTML parsing in Invoke-WebRequest, either by accessing parsed-HTML properties or
        by invoking it without -UseBasicParsing
    .INPUTS
        [System.Management.Automation.Language.ScriptBlockAst]
    .OUTPUTS
        [Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]]
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.Powershell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param (
        # Generic script block we are using to run our predicate against.
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]
        $ScriptBlockAst
    )

    $targetWebCmdlet = 'Invoke-WebRequest'

    $webCmdletInvocationPredicate = {
        param (
            [Ast]
            $Ast
        )
        # Skip invocations that splat a variable: we cannot reasonably determine whether the splatted
        # collection contains UseBasicParsing, so we assume it does to avoid false positives
        $Ast -is [CommandAst] -and
            $Ast.CommandElements[0].Value -eq $targetWebCmdlet -and
            $Ast.CommandElements.Splatted -notcontains $true
    }
    $invocations = $ScriptBlockAst.FindAll($webCmdletInvocationPredicate, $false)

    foreach ($invocation in $invocations) {
        $boundParameters = [StaticParameterBinder]::BindCommand($invocation, $true).BoundParameters
        # -OutFile skips parsing because the response goes to disk, unless -PassThru also returns it
        if ($boundParameters.ContainsKey('UseBasicParsing') -or
            ($boundParameters.ContainsKey('OutFile') -and -not $boundParameters.ContainsKey('PassThru'))) {
            continue
        }
        [DiagnosticRecord]@{
            Message  = ('Violation: To ensure compatibility with PowerShell 7, always pass ' +
                        '-UseBasicParsing to Invoke-WebRequest. This also avoids an HTML parsing ' +
                        'security prompt in patched Windows PowerShell 5.1.')
            Extent   = $invocation.Extent
            RuleName = $MyInvocation.MyCommand
            Severity = 'Error'
        }
    }

    # Look for variables that hold the result of web cmdlet calls
    $webCmdletsAssignmentPredicate = {
        param (
            [System.Management.Automation.Language.Ast]
            $Ast
        )
        $Ast -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $Ast.Right -is [System.Management.Automation.Language.PipelineAst] -and
            $Ast.Right.PipelineElements[0] -is [System.Management.Automation.Language.CommandAst] -and
            $Ast.Right.PipelineElements[0].CommandElements[0].Value -eq $targetWebCmdlet
    }
    $resultAssignments = $ScriptBlockAst.FindAll($webCmdletsAssignmentPredicate, $false)

    # Get the variables as an array of variable names (strings)
    if ($resultAssignments) {
        $targetVars = $resultAssignments.Left | foreach {$_.ToString()}
    }

    # These properties hold results of HTML parsing
    $suspectProperties = @(
        'Forms',
        # 'Images',      # actually available in PS7 without the legacy HTML parsing
        # 'InputFields', # actually available in PS7 without the legacy HTML parsing
        # 'Links',       # actually available in PS7 without the legacy HTML parsing
        'ParsedHtml'
    )

    # Look for HTML property access on variables that we've found earlier
    $propertyAccessPredicate = {
        param (
            [System.Management.Automation.Language.Ast]
            $Ast
        )
        $Ast -is [System.Management.Automation.Language.MemberExpressionAst] -and
        (
            (
                # Look for access of one of the special HTML properties on a variable that has been assigned
                # web cmdlet output
                $targetVars -and
                $Ast.Expression.ToString() -in $targetVars -and
                $Ast.Member.ToString() -in $suspectProperties
            ) -or (
                # or the code accesses 'ParsedHtml' which we treat as a special case, because it's very
                # obviously named and there are handful of instances where it's accessed in a way that we can't
                # detect with the method above
                $Ast.Member.ToString() -eq 'ParsedHtml'
            ) -or (
                # Check that the member accessed is one of the suspect properties and that the expression
                # contains a call to one of the target cmdlets
                $Ast.Member.ToString() -in $suspectProperties -and
                [bool](
                    $Ast.Expression.Pipeline.PipelineElements |
                      where {$_.CommandElements[0].Value -eq $targetWebCmdlet}
                )
            )
        )
    }
    $violations = $ScriptBlockAst.FindAll($propertyAccessPredicate, $false)

    foreach ($violation in $violations) {
        [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
            Message  = ('Violation: This property depends on Invoke-WebRequest HTML parsing and is not ' +
                        'available in PowerShell 7. On patched Windows PowerShell 5.1, HTML parsing requires an ' +
                        'interactive confirmation prompt.')
            Extent   = $violation.Extent
            RuleName = $MyInvocation.MyCommand
            Severity = 'Error'
        }
    }
}
