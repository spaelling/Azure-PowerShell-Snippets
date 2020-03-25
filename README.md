# Azure-PowerShell-Snippets
A collection of functions or snippets useable in Azure PowerShell.

## ConvertTo-AzureFunctionApp

![Example](/src/ConvertTo-AzureFunctionApp/example1.gif)

## New-AzTaggedResourceGroup

![Example](/src/New-AzTaggedResourceGroup/Example.gif)

## Rename-AzNetworkSecurityRule

![Example](/src/Rename-AzNetworkSecurityRule/Example.gif)

## Get-AzEffectiveSecurityRules

Get NSG rules relevant for specified VM. This script is useful when an NSG has hundreds of rules where only a handful is relevant for the virtual machine in question.

## Get-AzCachedAccessToken

Retrieve an access token from cache if you are already logged in to `Az` - use to invoke Azure REST API