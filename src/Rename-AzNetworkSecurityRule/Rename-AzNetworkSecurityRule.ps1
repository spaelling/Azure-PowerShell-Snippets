######################################################################
## Author: Anders Spælling, spaelling@gmail.com                     ##
## Last modified: 03-07-2019                                        ##
## Source: https://github.com/spaelling/Azure-PowerShell-Snippets/  ##
##                                                                  ##
######################################################################

<#
.SYNOPSIS
Rename a NSG security rule

.DESCRIPTION
Rename a NSG security rule

.PARAMETER NewName
Security rule will be renamed to this

.PARAMETER NetworkSecurityRuleName
The name of the security rule to rename

.PARAMETER NetworkSecurityGroupName
Name of the network security group that this rule is part of

.PARAMETER ResourceGroupName
Name of the resource group that the NSG is in

.EXAMPLE
$NetworkSecurityRuleName = "AllowInboundRdp"
$NewName = "AllowInboundTCP3389"
$NetworkSecurityGroupName = "nsg01"
$ResourceGroupName = "rg01"
Rename-AzNetworkSecurityRule -NewName $NewName -NetworkSecurityRuleName $NetworkSecurityRuleName -NetworkSecurityGroupName $NetworkSecurityGroupName -ResourceGroupName $ResourceGroupName

.NOTES
Delete locks have no effect on Remove-AzNetworkSecurityRuleConfig. This means the original rule can and will be deleted even with the presence of a delete lock. This is subject to change.
#>

function Rename-AzNetworkSecurityRule {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $NewName,

        [Parameter(Mandatory=$true)]
        [string]
        $NetworkSecurityRuleName,

        [Parameter(Mandatory=$true)]
        [string]
        $NetworkSecurityGroupName,

        [Parameter(Mandatory=$true)]
        [string]
        $ResourceGroupName,
        
        [Parameter(Mandatory=$false)]
        [switch]
        $AzureRm    
    )

    if($AzureRm.IsPresent)
    {
        # Create aliases so that this also works works with AzureRm
        New-Alias -Name "Get-AzSubscription" Get-AzureRmSubscription
        New-Alias -Name "Get-AzNetworkSecurityGroup" Get-AzureRmNetworkSecurityGroup
        New-Alias -Name "Get-AzNetworkSecurityRuleConfig" Get-AzureRmNetworkSecurityRuleConfig
        New-Alias -Name "Set-AzNetworkSecurityGroup" Set-AzureRmNetworkSecurityGroup
        #New-Alias -Name "" 
    }
    
    try {
        Write-Verbose "Checking connection to Azure..."
        Get-AzSubscription -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Error -Message "Not logged into Azure, please run 'Connect-AzAccount'. Error was $_" -ErrorAction Stop
    }
    
    Write-Verbose "Getting Azure NSG with name $NetworkSecurityGroupName..."
    $NetworkSecurityGroup = Get-AzNetworkSecurityGroup -Name $NetworkSecurityGroupName -ResourceGroupName $ResourceGroupName
    Write-Verbose "Getting security rules in $NetworkSecurityGroupName..."
    $NetworkSecurityRules = $NetworkSecurityGroup | Get-AzNetworkSecurityRuleConfig
    $TargetNetworkSecurityRule = $NetworkSecurityRules | Where-Object {$_.Name -eq $NetworkSecurityRuleName}
    if($null -eq $TargetNetworkSecurityRule)
    {
        $NetworkSecurityRules.Name
        Write-Error -Message "NSG Rule with name $NetworkSecurityRuleName not found" -ErrorAction Stop
    }

    Write-Verbose "Changing '$NetworkSecurityRuleName' to '$NewName'"
    ($NetworkSecurityGroup.SecurityRules | Where-Object {$_.Name -eq $NetworkSecurityRuleName}).Name = $NewName
    # commit to Azure
    $NetworkSecurityGroup | Set-AzNetworkSecurityGroup | Out-Null
}
