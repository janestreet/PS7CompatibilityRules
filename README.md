A collection of [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) rules to highlight
potential PowerShell 7 compatibility issues when migrating from PowerShell 5.1

# Usage
```powershell
git clone https://github.com/janestreet/PS7CompatibilityRules.git
Invoke-ScriptAnalyzer -Path '<your_code_path>' -Recurse -CustomRulePath .\PS7CompatibilityRules
```
# Included Rules

| Rule | Description |
| -----| ----------- |
| AvoidDeprecatedCommands  | Flag commands that are listed on Microsoft's website as incompatible with PS7 |
| AvoidDeprecatedTypes  | Flag references to deprecated types that are incompatible with PS7 |
| AvoidGetSetAccessControl  | Flag GetAccessControl() or SetAccessControl() calls |
| CommandRecommendations  | Recommendations for specific commands that have different behavior in PS7 |
| NoHtmlParsing  | Flag code that relies on HTML parsing done in web cmdlets |
| SelectObjectMustSpecifyProperty  | Select-Object ExcludeProperty is effective only when the command also includes a Property parameter |