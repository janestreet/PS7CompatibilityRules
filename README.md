A collection of [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) rules to highlight
potential PowerShell 7 compatibility issues when migrating from PowerShell 5.1

This module was featured in [Shell Renovations: Refactoring Your PowerShell Empire for V7](https://www.youtube.com/watch?v=riu5WywOrAI) talk at PSConfEU 2025


# Usage
```powershell
git clone https://github.com/janestreet/PS7CompatibilityRules.git
Invoke-ScriptAnalyzer -Path '<your_code_path>' -Recurse -CustomRulePath .\PS7CompatibilityRules\*.psm1
```

> [!NOTE]
> If instead of using `git clone` you've downloaded a zip file of this repo, you might need to run `Get-ChildItem .\PS7CompatibilityRules | Unblock-File`


# Included Rules
| Rule                            | Description                                                                                         |
| ------------------------------- | --------------------------------------------------------------------------------------------------- |
| AvoidDeprecatedCommands         | Flag commands that are listed on Microsoft's website as incompatible with PS7                       |
| AvoidDeprecatedTypes            | Flag references to deprecated types that are incompatible with PS7                                  |
| AvoidGetSetAccessControl        | Flag GetAccessControl() or SetAccessControl() calls                                                 |
| CommandRecommendations          | Recommendations for specific commands that have different behavior in PS7                           |
| NoHtmlParsing                   | Flag code that relies on HTML parsing done in web cmdlets                                           |
| SelectObjectMustSpecifyProperty | Select-Object ExcludeProperty is effective only when the command also includes a Property parameter |
| EnsureProperUseOfDotNetMethods  | Flag some .NET method calls that have different behavior in PS7/.NET Core                           |


# Example
Let's examine `Demo.ps1` that has compatibility issues:
```powershell
$webClient = [System.Net.WebClient]::new()
$webClient.DownloadString("https://example.com") | Out-File -FilePath "C:\temp\example.txt"

$acl = Get-Acl -Path "C:\temp\example.txt"
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "ReadAndExecute", "Allow")
$acl.AddAccessRule($rule)
$acl.SetAccessControl("C:\temp\example.txt")

Get-WmiObject -Class Win32_OperatingSystem | Select-Object Caption, Version | Format-Table -AutoSize

'One,Two;Three Four'.Split(' ,;') | foreach { "Processing: $_" }
```

Rules will report these findings:
```shell
> Invoke-ScriptAnalyzer -Path .\Demo.ps1 -CustomRulePath .\PS7CompatibilityRules\*.psm1

RuleName                            Severity     ScriptName Line  Message
--------                            --------     ---------- ----  -------
AvoidDeprecatedCommands             Error        Demo.ps1   9     The command Get-WmiObject or one of its parameters or
                                                                  parameter values is not compatible with both PS5 and PS7.
                                                                  Consider using a different command.
AvoidDeprecatedTypes                Error        Demo.ps1   1     Violation: Use System.Net.Http.HttpClient &
                                                                  System.Net.Http.HttpClientHandler to ensure compatibility
                                                                  with PS7 and future versions
AvoidGetSetAccessControl            Error        Demo.ps1   7     In PS7, GetAccessControl and SetAccessControl are not
                                                                  available. Please use Get-Acl and Set-Acl
CommandRecommendations              Information  Demo.ps1   2     Recommendation: Default encoding for "Out-File" has changed
                                                                  from unicode to UTF-8NoBOM. Specify "-Encoding Unicode" to
                                                                  ensure consistent behavior between PS versions.
EnsureProperUseOfDotNetMethods      Warning      Demo.ps1   11    Recommendation: The Split method behaves differently
                                                                  between PS5 and PS7 due to .NET changes. Use -split or
                                                                  -csplit with regex instead.
```

# Using these rules in Visual Studio Code

1. In your workspace create a PSScriptAnalyzer settings file (`.vscode\PSScriptAnalyzerSettings.psd1`)
    ```powershell
    @{
        CustomRulePath = @(
            '<path_to>\PS7CompatibilityRules\*.psm1'
        )
    }
    ```
2. Create or edit your workspace's settings file (`.vscode\settings.json`) to include these settings
    ```json
    {
        "powershell.scriptAnalysis.settingsPath": ".vscode\\PSScriptAnalyzerSettings.psd1",
        "powershell.scriptAnalysis.enable": true
    }
    ```
Rule violations should now be highlighted as you're editing code.


For more details, see
  - [Settings Support in ScriptAnalyzer](https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/using-scriptanalyzer?view=ps-modules#settings-support-in-scriptanalyzer)
  - [Custom rules](https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/using-scriptanalyzer?view=ps-modules#custom-rules)
  - [Using custom rules in Visual Studio Code](https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/using-scriptanalyzer?view=ps-modules#using-custom-rules-in-visual-studio-code)

