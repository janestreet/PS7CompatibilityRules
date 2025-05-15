using namespace Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic
using namespace System.Management.Automation.Language
function AvoidDeprecatedCommands {
    <#
    .SYNOPSIS
        Flag commands that were deemed incompatible with PS7
    .DESCRIPTION
        Find and flag commands that are listed on Microsoft's website as incompatible with PS7. The full list is in
        https://learn.microsoft.com/en-us/powershell/scripting/whats-new/differences-from-windows-powershell?view=powershell-7.4
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
            [Ast]
            $Ast
        )
        if ($Ast -is [CommandAst]) {
            $isViolation = $false
            $commandDenyList.Keys | where {$Ast.CommandElements[0] -like $_} | foreach {
                $incompatibleCommand = $commandDenyList[$_]
                # Is command always incompatible or just for selected paramters?
                if ($incompatibleCommand.ContainsKey('*')) {
                    $isViolation = $true
                }
                else {
                    # Loop through command params. Starting from 1 because the fitst element is the command itself
                    for ($i = 1; $i -lt $Ast.CommandElements.Count -and -not $isViolation; $i++) {
                        # Is command parameter on deny list?
                        $incompatibleParameter = $incompatibleCommand.Keys |
                            where {$Ast.CommandElements[$i].ParameterName -like $_} |
                            foreach {$incompatibleCommand[$_]}
                        # Is command parameter always incompatible or just for selected parameter values?
                        if ($incompatibleParameter -eq '*') {
                            $isViolation = $true
                        }
                        else {
                            # Is command parameter value on deny list?
                            $isViolation = (
                                $Ast.CommandElements[$i].Argument -and
                                $Ast.CommandElements[$i].Argument -eq $incompatibleParameter
                            ) -or (
                                $Ast.CommandElements[$i + 1].Value -and
                                $Ast.CommandElements[$i + 1].Value -eq $incompatibleParameter
                            )
                        }
                    }
                }
            }
            $isViolation
        }
    }

    $violations = $ScriptBlockAst.FindAll($incompatibleCommandPredicate, $false)
    foreach ($violation in $violations) {
            [DiagnosticRecord] @{
                Message           = ("The command $($Violation.CommandElements[0].Extent.Text) or one of its " +
                                    'parameters or parameter values is not compatible with both PS5 and PS7. ' +
                                    'Consider using a different command.')
                Extent            = $violation.Extent
                RuleName          = $MyInvocation.MyCommand
                Severity          = 'Error'
                RuleSuppressionID = $violation.ToString()
            }
    }
}
