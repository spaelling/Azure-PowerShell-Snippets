. .\ConvertTo-AzureFunctionApp.ps1

function Add-Numbers {
    param (
        [int]
        $Number1,
        [int]
        $Number2
    )
    
    return $Number1 + $Number2
}
Write-Host "`n`n`n`n"
$Command = Get-Command -Name 'Add-Numbers'
ConvertTo-AzureFunctionApp -Command $Command -CreateFunctionApp -WhatIf

Add-Numbers 40 2