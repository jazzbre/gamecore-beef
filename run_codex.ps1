# run_codex.ps1

$dir = $PSScriptRoot
$cmd = "codex resume --cd `"$dir`" --sandbox workspace-write --ask-for-approval never"

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent() `
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Start-Process powershell `
        -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
        -Verb RunAs
    exit
}

# Run codex
Set-Location $dir
Invoke-Expression $cmd