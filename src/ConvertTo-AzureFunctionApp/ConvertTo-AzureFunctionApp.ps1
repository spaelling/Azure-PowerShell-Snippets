<#

#>
using namespace Microsoft.PowerShell.EditorServices.Extensions
function ConvertTo-AzureFunctionApp {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    param (
        [System.Management.Automation.FunctionInfo]$Command,
        [switch]$CreateFunctionApp
    )

    $CommandName = $Command.Name

    if([string]::IsNullOrEmpty($CommandName))
    {
        throw "Unable to determine function name"
    }

    Write-Verbose "Command name is '$($CommandName)'"

    # $MyInvocation | ConvertTo-Json | Write-Verbose

    # $PSScriptRoot seems to be blank if calling from vscode extension
    if([string]::IsNullOrEmpty($PSScriptRoot))
    {
        # TODO
        $PSScriptRoot = 'C:\git\Azure-PowerShell-Snippets\src\ConvertTo-AzureFunctionApp\'
    }
    $TemplatePath = (Resolve-Path -Path "$PSScriptRoot\template.ps1" -ErrorAction Stop).Path

    $Template = Get-Content -Path $TemplatePath

    Write-Verbose "Template:"
    $Template | Write-Verbose

    $FunctionCall = $CommandName

    $ParseParameterBlock = $Command.Parameters.GetEnumerator() | ForEach-Object {
        $Parameter = $_.Value
        # @{
        #     Name = $Parameter.Name
        #     ParameterType = $Parameter.ParameterType.FullName
        # } | ConvertTo-Json
        $ParameterName = $Parameter.Name
        $ParameterType = $Parameter.ParameterType.Name

        $FunctionCall += " -$ParameterName `$$ParameterName"

        # only do ::Parse if the parameter type has a parse function
        if($ParameterType -in @("Int32", "Char", "Byte", "Int64", "Boolean", "Decimal", "Single", "Double", "DateTime"))
        {
            $ParameterValue = @("[$ParameterType]::Parse(`$Request.Query.$ParameterName)","[$ParameterType]::Parse(`$Request.Body.$ParameterName)")
        }
        else {
            $ParameterValue = @("`$Request.Query.$ParameterName","`$Request.Body.$ParameterName")
        }
        
<#
TODO: 

seems to ignore newlines in following iterations of loop

#>
@"
    # get parameter value from request query
    # ParameterType $ParameterType
    `$$ParameterName = $($ParameterValue[0])
    if (`$null -eq `$$ParameterName) {
        # get parameter value from request body
        `$$ParameterName = $($ParameterValue[1])
    }
"@
    }

    $ParseParameterBlock | Write-Verbose

    $Out = $Template.Replace("<ParseParameterBlock>", $ParseParameterBlock).Replace("<FunctionCall>", $FunctionCall)

    if($CreateFunctionApp.IsPresent)
    {
        $FunctionDir = $Command.Name.Replace('-','_')
        $OutPath = (Resolve-Path -Path '.').Path
        Write-Verbose "Creating path '$OutPath\$FunctionDir'"
        $null = New-Item -ItemType Directory -Path "$OutPath\$FunctionDir" -Force
        $Runps1Path = "{0}\{1}\run.ps1" -f $OutPath, $FunctionDir
        Write-Verbose "Creating file '$Runps1Path'"
        $Out | Out-File -FilePath $Runps1Path -Force
        $FunctionJsonPath = "{0}\{1}\function.json" -f $OutPath, $FunctionDir
        Write-Verbose "Copying '$PSScriptRoot\function.json' to '$FunctionJsonPath'"
        $null = Copy-Item -Path "$PSScriptRoot\function.json" -Destination "$FunctionJsonPath" -Force
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
    $VerbosePreference = 'Continue'
    Write-Verbose "`n"
    # $context = $psEditor.GetEditorContext()
    $CurrentFile = $context.CurrentFile
    Write-Verbose "Current file: $($CurrentFile.Path)"
    [array]$TextLines = $CurrentFile.GetTextLines()
    Write-Verbose "Number of text lines = $($TextLines.Length)"
    # if($TextLines.Length -eq 1)
    # {
    #     Write-Verbose "$($CurrentFile.Path) only contains a single line"
    #     $TextLines = $TextLines.Split('`n')
    # }

    [int]$LineNumber = $context.SelectedRange.Start.Line
    # $TextLines | gm *
    $Line = $TextLines[($LineNumber-1)..$LineNumber]
    Write-Verbose "Line #$LineNumber contains: '$Line'"

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

    Write-Host "Converting '$FunctionName' to Azure Function App function..."
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