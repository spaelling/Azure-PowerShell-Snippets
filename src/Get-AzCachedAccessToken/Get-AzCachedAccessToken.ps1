<#

DISCLAIMER: Someone else made this, will add credits when I figure out who. This is so I can find it again when I need it!

.SYNOPSIS
Get cachec access token

.DESCRIPTION
Get cachec access token

.EXAMPLE
An example

.NOTES
This will fail if multiple accounts are logged in (to the same tenant?), check with Get-AzContext -ListAvailable, there should be only one listed
Remove accounts using Disconnect-AzAccount
#>

function Get-AzCachedAccessToken()
{
    $ErrorActionPreference = 'Stop'
  
    if(-not (Get-Module Az.Accounts)) {
        Import-Module Az.Accounts
    }
    $azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
    if(-not $azProfile.Accounts.Count) {
        Write-Error "Ensure you have logged in before calling this function."    
    }
  
    $currentAzureContext = Get-AzContext
    $profileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($azProfile)
    Write-Debug ("Getting access token for tenant" + $currentAzureContext.Tenant.TenantId)
    $token = $profileClient.AcquireAccessToken($currentAzureContext.Tenant.TenantId)
    $token.AccessToken
}
