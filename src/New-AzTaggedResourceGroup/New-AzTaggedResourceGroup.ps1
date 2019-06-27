##############################
## Author: Anders Spælling, spaelling@gmail.com
## Last modified: 27-06-2019
##
##############################

<#
.SYNOPSIS
Create new Azure resource group with autocomplete on tags

.DESCRIPTION
Create new Azure resource group with autocomplete on tags (based on existing tags). Tag names are defined in the function

.PARAMETER Name
Name of resource group

.PARAMETER Location
Location to create resource group, defaults to West Europe

.PARAMETER NoCache
Do not used cached tag values (runtime 2-3 seconds)

.EXAMPLE
New-AzTaggedResourceGroup -Name RG-Stuff42 -Project MeaningOfLife -Department IT -Environment Dev

.NOTES
General notes
#>
function New-AzTaggedResourceGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        [string]
        $Name,

        [string]
        $Location = 'westeurope',

        [switch]
        $NoCache
    )
    DynamicParam {        
        # we will cache the resource group tags in a global variable as getting them each time takes around 6-7 seconds

        # these tags are mandatory by policy - this will also become our dynamic parameter names
        [array]$ParameterNames = @('Department','Project','Environment')

        $Now = Get-Date
        if(
            $NoCache.IsPresent -or
            $null -eq $Global:ResourceGroupTags -or 
            $Global:ResourceGroupTags.Count -eq 0 -or 
            (Get-Date $Global:ResourceGroupTags['TimeStamp']).AddMinutes(5) -lt $Now # refresh tags after 5 minutes
        )
        {
            # check that there is an Azure context available
            try {
                $null = Get-AzContext -ErrorAction Stop
            }
            catch {
                throw "Please run 'Connect-AzAccount' to login"
            }
            # setup runspace to get tags
            $sessionstate = [system.management.automation.runspaces.initialsessionstate]::CreateDefault()
            $_Tags = @{
                TimeStamp = Get-Date
            }
            $sessionstate.Variables.Add(
                (New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry('Tags', $_Tags, $null))
            )
                        
            $runspacepool = [runspacefactory]::CreateRunspacePool(1, [int]$env:NUMBER_OF_PROCESSORS+1, $sessionstate, $Host)
            $runspacepool.Open()
            $runspaces = @() 
            
            foreach ($ParameterName in $ParameterNames) {
                $runspace = [powershell]::Create()
                $runspace.RunspacePool = $runspacepool    
                $null = $runspace.AddScript({
                    param($ParameterName)
                    $_Tags[$ParameterName] = (Get-AzTag -Name $ParameterName).Values.Name
                }).AddArgument($ParameterName)
                $runspaces += [PSCustomObject]@{ Pipe = $runspace; Status = $runspace.BeginInvoke() } 
            }
            while($runspaces.Status.IsCompleted -contains $false){Start-Sleep -Milliseconds 10}
            Set-Variable -Name 'ResourceGroupTags' -Scope Global -Value $_Tags
        }

        # Create the dictionary
        $RuntimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

        foreach ($ParameterName in $ParameterNames) {
            # Create the collection of attributes
            $AttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]

            # Create and set the parameters' attributes
            $ParameterAttribute = New-Object System.Management.Automation.ParameterAttribute
            $ParameterAttribute.Mandatory = $true

            # Add the attributes to the attributes collection
            $AttributeCollection.Add($ParameterAttribute)
      
            # https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_functions_advanced_parameters?view=powershell-6#argumentcompleter-attribute
            $ArgumentCompleterAttribute = New-Object System.Management.Automation.ArgumentCompleterAttribute({
                param ( $commandName,
                        $parameterName,
                        $wordToComplete,
                        $commandAst,
                        $fakeBoundParameters )

                $Global:ResourceGroupTags[$parameterName] | Where-Object {
                    $_ -like "$wordToComplete*"
                }
            })
            $AttributeCollection.Add($ArgumentCompleterAttribute) 

            $RuntimeParameter = New-Object System.Management.Automation.RuntimeDefinedParameter($ParameterName, [string], $AttributeCollection)
            $RuntimeParameterDictionary.Add($ParameterName, $RuntimeParameter)            
        }
        
        return $RuntimeParameterDictionary
    }
    
    begin
    {
        # check that there is an Azure context available
        try {
            $null = Get-AzContext -ErrorAction Stop
        }
        catch {
            throw "Please run 'Connect-AzAccount' to login"
        }

        foreach ($ParameterName in $ParameterNames) {
            Set-Variable -Name $ParameterName -Value $PSBoundParameters[$parameterName]
        }
    }

    process {
        # automatically tag with who created the resource group
        $CreatedBy = (Get-AzContext).Account.Id
        $Tag = @{
            Department = $Department
            Project = $Project
            Environment = $Environment
            CreatedBy = $CreatedBy
        }

        New-AzResourceGroup -Name $Name -Tag $Tag -Location $Location
    }
}
