using namespace Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic
using namespace System.Management.Automation.Language
function AvoidDeprecatedCommands {
    <#
    .SYNOPSIS
        Flag commands that were deemed incompatible with PS7
    .DESCRIPTION
        Find and flag commands that are listed on Microsoft's website as incompatible with PS7. The full list is in
        https://learn.microsoft.com/en-us/powershell/scripting/whats-new/differences-from-windows-powershell?view=powershell-7.4
    .NOTES
        Parameter-specific deny list entries are evaluated using [StaticParameterBinder]::BindCommand, which
        binds parameters the same way PowerShell itself would. This robustly handles both '-Parameter Value'
        and '-Parameter:Value' syntax instead of manually walking the command elements. Commands are not
        resolved (BindCommand resolve = $false), so the rule works without the command being available in the
        session.
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
    # This list does not include aliases, add them if necessary e.g. 'gwmi' = @{'*' = '*'}
    # Format: 'commandName' = @{ parameter = value }. use * to indicate all
    $commandDenyList = @{
        # https://learn.microsoft.com/en-us/powershell/scripting/whats-new/differences-from-windows-powershell?view=powershell-7.4#modules-no-longer-shipped-with-powershell
        '*-JobTrigger'                    = @{'*' = '*'}
        '*-ScheduledJob'                  = @{'*' = '*'}
        '*-ScheduledJobOption'            = @{'*' = '*'}
        '*-OperationValidation'           = @{'*' = '*'}
        'Export-ODataEndpointProxy'       = @{'*' = '*'}
        'New-PSWorkflowSession'           = @{'*' = '*'}
        'Invoke-AsWorkflow'               = @{'*' = '*'}
        'New-PSWorkflowExecutionOption'   = @{'*' = '*'}

        # https://learn.microsoft.com/en-us/powershell/scripting/whats-new/differences-from-windows-powershell?view=powershell-7.4#wmi-v1-cmdlets
        '*-WmiObject'                     = @{'*' = '*'}
        'Invoke-WmiMethod'                = @{'*' = '*'}
        'Register-WmiEvent'               = @{'*' = '*'}
        'Set-WmiInstance'                 = @{'*' = '*'}
        'gwmi'                            = @{'*' = '*'}
        # https://learn.microsoft.com/en-us/powershell/scripting/whats-new/differences-from-windows-powershell?view=powershell-7.4#new-webserviceproxy-cmdlet-removed
        'New-WebServiceProxy'             = @{'*' = '*'}

        # https://learn.microsoft.com/en-us/powershell/scripting/whats-new/differences-from-windows-powershell?view=powershell-7.4#-eventlog-cmdlets
        '*-EventLog'                      = @{'*' = '*'}

        # https://learn.microsoft.com/en-us/powershell/scripting/whats-new/differences-from-windows-powershell?view=powershell-7.4#-transaction-cmdlets-removed
        '*-Transaction'                   = @{'*' = '*'}

        #https://learn.microsoft.com/en-us/powershell/scripting/whats-new/differences-from-windows-powershell?view=powershell-7.4#unify-cmdlets-with-parameter--encoding-to-be-of-type-systemtextencoding
        '*-Content'                     = @{'Encoding' = 'Byte'}

        # https://learn.microsoft.com/en-us/powershell/scripting/whats-new/differences-from-windows-powershell?view=powershell-7.4#remove--protocol-from--computer-cmdlets
        '*-Computer'                      = @{'Protocol' = '*'}

        # https://learn.microsoft.com/en-us/powershell/scripting/whats-new/differences-from-windows-powershell?view=powershell-7.4#remove--computername-from--service-cmdlets
        '*-Service'                       = @{'ComputerName' = '*'}

        # https://learn.microsoft.com/en-us/powershell/scripting/whats-new/differences-from-windows-powershell?view=powershell-7.4#cmdlets-removed-from-powershell
        # From Microsoft.PowerShell.Core
        '*-PSSnapin'                      = @{'*' = '*'}
        'Export-Console'                  = @{'*' = '*'}
        'Resume-Job'                      = @{'*' = '*'}
        'Suspend-Job'                     = @{'*' = '*'}
        # From Microsoft.PowerShell.Diagnostics
        'Export-Counter'                  = @{'*' = '*'}
        'Import-Counter'                  = @{'*' = '*'}
        # From Microsoft.PowerShell.Management
        '*-ComputerRestore'               = @{'*' = '*'}
        'Test-ComputerSecureChannel'      = @{'*' = '*'}
        '*-ControlPanelItem'              = @{'*' = '*'}
        'Add-Computer'                    = @{'*' = '*'}
        'Restore-Computer'                = @{'*' = '*'}
        'Checkpoint-Computer'             = @{'*' = '*'}
        'Remove-Computer'                 = @{'*' = '*'}
        'Get-ComputerRestorePoint'        = @{'*' = '*'}
        'Reset-ComputerMachinePassword'   = @{'*' = '*'}
        # From Microsoft.PowerShell.Utility
        'Convert-String'                  = @{'*' = '*'}
        'ConvertFrom-String'              = @{'*' = '*'}
        # From PSDesiredStateConfiguration
        '*-DscConfiguration'              = @{'*' = '*'}
        '*-DscLocalConfigurationManager'  = @{'*' = '*'}
        'Remove-DscConfigurationDocument' = @{'*' = '*'}
        'Get-DscConfigurationStatus'      = @{'*' = '*'}
        '*-DscDebug'                      = @{'*' = '*'}
    }

    $commandDenyListPS7 = @{
        'Remove-Service'   = @{'*' = '*'}
        '*-Markdown'       = @{'*' = '*'}
        '*-MarkdownOption' = @{'*' = '*'}
        'Test-Json'        = @{'*' = '*'}
        'Remove-Alias'     = @{'*' = '*'}
        'Join-String'      = @{'*' = '*'}
        'Get-Uptime'       = @{'*' = '*'}
        'Get-Error'        = @{'*' = '*'}
        'Out-File'         = @{'Path' = '*'}
        'Set-Service'      = @{'StartupType' = 'AutomaticDelayedStart'}
    }

    $commandDenyList += $commandDenyListPS7

    [scriptblock]$incompatibleCommandPredicate = {
        param (
            # The AST node currently being evaluated by FindAll.
            [Ast]
            $Ast
        )
        $isViolation = $false
        if ($Ast -is [CommandAst]) {
            foreach ($deprecatedCommandName in $commandDenyList.Keys) {
                # Stop as soon as we know the command is a violation.
                if ($isViolation) {
                    break
                }
                # Is the command on the deny list?
                if ($Ast.CommandElements[0] -notlike $deprecatedCommandName) {
                    continue
                }
                $incompatibleCommand = $commandDenyList[$deprecatedCommandName]
                # Is the command always incompatible or just for selected parameters?
                if ($incompatibleCommand.ContainsKey('*')) {
                    $isViolation = $true
                    continue
                }
                # Let PowerShell bind the parameters for us. resolve = $false binds parameters syntactically and
                # does not require the command to be available in the session.
                try {
                    $bindingResult = [StaticParameterBinder]::BindCommand($Ast, $false)
                }
                catch {
                    # If the command cannot be bound (e.g. duplicate parameters) we cannot evaluate its
                    # parameters, so skip the parameter-level checks for this command.
                    $bindingResult = $null
                }
                if ($null -eq $bindingResult) {
                    continue
                }
                foreach ($boundParameter in $bindingResult.BoundParameters.GetEnumerator()) {
                    foreach ($deprecatedParameterName in $incompatibleCommand.Keys) {
                        # Is the bound parameter on the deny list?
                        if ($boundParameter.Key -notlike $deprecatedParameterName) {
                            continue
                        }
                        # Is the parameter always incompatible ('*') or just for a selected value?
                        $deprecatedValue = $incompatibleCommand[$deprecatedParameterName]
                        $boundValue = $boundParameter.Value.ConstantValue
                        if ($deprecatedValue -eq '*' -or $boundValue -eq $deprecatedValue) {
                            $isViolation = $true
                        }
                    }
                }
            }
        }
        $isViolation
    }

    $violations = $ScriptBlockAst.FindAll($incompatibleCommandPredicate, $false)
    foreach ($violation in $violations) {
            [DiagnosticRecord] @{
                Message           = ("The command $($violation.CommandElements[0].Extent.Text) or one of its " +
                                    'parameters or parameter values is not compatible with both PS5 and PS7. ' +
                                    'Consider using a different command.')
                Extent            = $violation.Extent
                RuleName          = $MyInvocation.MyCommand
                Severity          = 'Error'
                RuleSuppressionID = $violation.ToString()
            }
    }
}
