#requires -Version 5.1
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CliArgv)
& (Join-Path $PSScriptRoot 'grokbot-desktop.ps1') @CliArgv
exit $LASTEXITCODE
