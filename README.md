# Azure PowerShell Snippets

A collection of functions or snippets useable in Azure PowerShell.

## ConvertTo-AzureFunctionApp

Generates the code needed to execute a PowerShell function in an Azure Function App function.

The code necessary to parse the request query or body is generated, and the function is called using the function parameters.

![Example](/src/ConvertTo-AzureFunctionApp/example1.gif)

## New-AzTaggedResourceGroup

Create a new Azure resource group with autocompletion for tags. Especially useful when policies demand specific tags to be set in order to create a resource group.

The tag names are defined in the function.

![Example](/src/New-AzTaggedResourceGroup/Example.gif)

## Rename-AzNetworkSecurityRule

Rename existing network security rule.

![Example](/src/Rename-AzNetworkSecurityRule/Example.gif)

## Get-AzEffectiveSecurityRules

Get NSG rules relevant for specified VM. This script is useful when an NSG has hundreds of rules where only a handful is relevant for the virtual machine in question.

## Get-AzCachedAccessToken

Retrieve an access token from cache if you are already logged in to `Az` - use to invoke Azure REST API