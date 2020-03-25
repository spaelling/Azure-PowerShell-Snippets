using namespace Microsoft.PowerShell.EditorServices.Extensions
function ConvertTo-AzureFunctionApp {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    param (
        [System.Management.Automation.FunctionInfo]$Command,
        [switch]$CreateFunctionApp
    )

    # $MyInvocation | ConvertTo-Json | Write-Verbose

    # $PSScriptRoot seems to be blank if calling from vscode extension
    if([string]::IsNullOrEmpty($PSScriptRoot))
    {
        # TODO
        $PSScriptRoot = 'C:\git\Azure-PowerShell-Snippets\src\ConvertTo-AzureFunctionApp\'
    }
    $TemplatePath = (Resolve-Path -Path "$PSScriptRoot\template.ps1" -ErrorAction Stop).Path

    $Template = Get-Content -Path $TemplatePath

    $Template | Write-Verbose

    $FunctionCall = $Command.Name

    $ParseParameterBlock = $Command.Parameters.GetEnumerator() | ForEach-Object {
        $Parameter = $_.Value
        # @{
        #     Name = $Parameter.Name
        #     ParameterType = $Parameter.ParameterType.FullName
        # } | ConvertTo-Json
        $ParameterName = $Parameter.Name

        $FunctionCall += " -$ParameterName `$$ParameterName"
# TODO: seems to ignore newlines in following iterations of loop
@"
# get parameter value from request query
`$$ParameterName = `$Request.Query.$ParameterName
if (`$null -eq `$$ParameterName) {
    # get parameter value from request body
    `$$ParameterName = `$Request.Body.$ParameterName
}
"@
    }

    $ParseParameterBlock | Write-Verbose

    $Out = $Template.Replace("<ParseParameterBlock>", $ParseParameterBlock).Replace("<FunctionCall>", $FunctionCall)

    if($CreateFunctionApp.IsPresent)
    {
        $FunctionDir = $Command.Name.Replace('-','_')
        $OutPath = (Resolve-Path -Path '.').Path
        $null = New-Item -ItemType Directory -Path "$OutPath\$FunctionDir" -Force
        $Out | Out-File -FilePath "$OutPath\$FunctionDir\run.ps1" -Force
        $null = Copy-Item -Path "$PSScriptRoot\function.json" -Destination "$OutPath\$FunctionDir\function.json" -Force
    }
    else {
        return $Out
    }
}

function Invoke-ConvertToFunctionApp {
    [CmdletBinding()]
    param (
        # [Microsoft.PowerShell.EditorServices.Extensions.EditorContext]
        $context
    )
    Write-Host "`n"
    # $context = $psEditor.GetEditorContext()
    $CurrentFile = $context.CurrentFile
    Write-Host "Current file: $($CurrentFile.Path)"
    [array]$TextLines = $CurrentFile.GetTextLines()
    Write-Host "Number of text lines = $($TextLines.Length)"
    # if($TextLines.Length -eq 1)
    # {
    #     Write-Host "$($CurrentFile.Path) only contains a single line"
    #     $TextLines = $TextLines.Split('`n')
    # }

    [int]$LineNumber = $context.SelectedRange.Start.Line
    # $TextLines | gm *
    $Line = $TextLines[($LineNumber-1)..$LineNumber]
    Write-Host "Line #$LineNumber contains: '$Line'"

    $LineTokens = $Line.Split(" ")
    $FirstToken = $LineTokens | Select-Object -Index 0
    # also works if line is the function definition
    if($FirstToken -eq 'function')
    {
        $FunctionName =  $LineTokens | Select-Object -Index 1
    }
    else {
        $FunctionName = $FirstToken
    }
    
    if([string]::IsNullOrEmpty($FunctionName))
    {
        throw "Please select a function to convert"
    }
    # TODO: check if whatever is selected is an actual function, use get-command

    Write-Host "Converting '$FunctionName' to Azure Function App function...`n`n`n`n"
    try {
        $Command = Get-Command $FunctionName
    }
    catch {
        throw $_
    }
    ConvertTo-AzureFunctionApp -Command $Command -CreateFunctionApp -Verbose
}

if($psEditor)
{
    Register-EditorCommand `
        -Name "Create Function App function" `
        -DisplayName "Convert PS function to Azure Function App function" `
        -Function Invoke-ConvertToFunctionApp
}