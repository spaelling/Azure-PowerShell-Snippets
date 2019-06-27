##############################
## Author: Anders Spælling, spaelling@gmail.com
## Last modified: 27-06-2019
##
## TODO
## test service endpoints in NSG
##
##############################

#region helper
function CheckNetworkToSubnet ([uint32]$un2, [uint32]$ma2, [uint32]$un1)
{
    $un2 -eq ($ma2 -band $un1)
}

function CheckSubnetToNetwork ([uint32]$un1, [uint32]$ma1, [uint32]$un2)
{
    $un1 -eq ($ma1 -band $un2)
}

function CheckNetworkToNetwork ([uint32]$un1, [uint32]$un2)
{
    $un1 -eq $un2
}

function SubToBinary ([int]$sub)
{
    ((-bnot [uint32]0) -shl (32 - $sub))
}

function NetworkToBinary ($network)
{
    $a = [uint32[]]$network.split('.')
    ($a[0] -shl 24) + ($a[1] -shl 16) + ($a[2] -shl 8) + $a[3]
}

<#
.SYNOPSIS
 The function will check ip to ip, ip to subnet, subnet to ip or subnet to subnet belong to each other and return true or false and the direction of the check

.DESCRIPTION
Long description

.PARAMETER addr1
Parameter description

.PARAMETER addr2
Parameter description

.EXAMPLE
An example

.NOTES
General notes
#>

function checkSubnet ([string]$addr1, [string]$addr2)
{
    # Separate the network address and lenght
    $network1, [int]$subnetlen1 = $addr1.Split('/')
    $network2, [int]$subnetlen2 = $addr2.Split('/')

 
    #Convert network address to binary
    [uint32] $unetwork1 = NetworkToBinary $network1
    [uint32] $unetwork2 = NetworkToBinary $network2
 
    #Check if subnet length exists and is less then 32(/32 is host, single ip so no calculation needed) if so convert to binary
    if($subnetlen1 -lt 32){
        [uint32] $mask1 = SubToBinary $subnetlen1
    }
 
    if($subnetlen2 -lt 32){
        [uint32] $mask2 = SubToBinary $subnetlen2
    }
 
    #Compare the results
    if($mask1 -and $mask2){
        # If both inputs are subnets check which is smaller and check if it belongs in the larger one
        if($mask1 -lt $mask2){
            return CheckSubnetToNetwork $unetwork1 $mask1 $unetwork2
        }else{
            return CheckNetworkToSubnet $unetwork2 $mask2 $unetwork1
        }
    }ElseIf($mask1){
        # If second input is address and first input is subnet check if it belongs
        return CheckSubnetToNetwork $unetwork1 $mask1 $unetwork2
    }ElseIf($mask2){
        # If first input is address and second input is subnet check if it belongs
        return CheckNetworkToSubnet $unetwork2 $mask2 $unetwork1
    }Else{
        # If both inputs are ip check if they match
        CheckNetworkToNetwork $unetwork1 $unetwork2
    }
}

function Format-NSGRule {
    param (
        $Rule
    )
    $Rule | Select-Object -Property Name, Priority, Direction, Access, Protocol, `
        @{Name='Source';            Expression={(($_.SourceAddressPrefix + ($_.SourceApplicationSecurityGroups -split '/' | Select-Object -Last 1)) | Where-Object {$_}) -join ','}}, `
        @{Name='Source port';       Expression={$_.SourcePortRange -join ','}}, `
        @{Name='Destination';       Expression={(($_.DestinationAddressPrefix + ($_.DestinationApplicationSecurityGroups -split '/' | Select-Object -Last 1)) | Where-Object {$_}) -join ','}}, `
        @{Name='Destination port';  Expression={$_.DestinationPortRange -join ','}} 
}
#endregion

<#
.SYNOPSIS
Get NSG rules relevant for specified VM

.DESCRIPTION
Get NSG rules relevant for specified VM

.PARAMETER VMName
Name of VM

.PARAMETER VMResourceGroup
Resource group VM is in

.EXAMPLE
Get-AzEffectiveSecurityRules -VMResourceGroup 'RG-VMs' -VMName 'myvm01'

.NOTES
General notes
#>
function Get-AzEffectiveSecurityRules {
    [CmdletBinding()]
    param (
        $VMName,
        $VMResourceGroup
    )

    Write-Verbose "Setting up runspaces..."
    # Sync'd hash table is accessible between threads
    $table = [HashTable]::Synchronized(@{})
    $table['Location'] = $null
    $table['VMId'] = $null
    $table['NicId'] = $null
    $table['PrivateIpAddress'] = $null
    $table['ApplicationSecurityGroupIds'] = $null
    $table['SubnetSecurityRules'] = $null
    $table['VMName'] = $VMName
    $table['VMResourceGroup'] = $VMResourceGroup

    $sessionstate = [system.management.automation.runspaces.initialsessionstate]::CreateDefault()
    $sessionstate.Variables.Add(
        (New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry('table', $table, $null))
    )
     
    $runspacepool = [runspacefactory]::CreateRunspacePool(1, [int]$env:NUMBER_OF_PROCESSORS+1, $sessionstate, $Host)
    $runspacepool.Open()
    $runspaces = @()

    $runspace1,$runspace2,$runspace3 = [powershell]::Create(),[powershell]::Create(),[powershell]::Create()
    $runspace1.RunspacePool = $runspace2.RunspacePool = $runspace3.RunspacePool = $runspacepool
     
    $runspace1.AddScript({
        $Now = Get-Date
        $VMName = $table['VMName']
        $VMResourceGroup = $table['VMResourceGroup']
        $VM = Get-AzVM -Name $VMName -ResourceGroupName $VMResourceGroup -ErrorAction Stop
        $table['Location'] = $VM.Location
        $table['VMId'] = $VM.Id
        $table['NicId'] = $VM.NetworkProfile.NetworkInterfaces.Id
        $Then = Get-Date
        $table['runspace1_runtime'] = ($Then - $Now).TotalMilliseconds
    }) > $null    
    $runspaces += [PSCustomObject]@{ Pipe = $runspace1; Status = $runspace1.BeginInvoke() }
    Write-Verbose "Invoking runspace1"

    $runspace2.AddScript({
        $Now = Get-Date
        # dependent on both runspaces to complete and then we make 2 API calls, so runtime ~8 seconds
        while($null -eq $table['VNet'] -or $null -eq $table['Subnet']){}

        $Subnet = (Get-AzResource -ResourceId $table['VNet'] -ExpandProperties).Properties.subnets | Where-Object {$_.name -eq $table['Subnet']}
        $NSGId = $Subnet.properties.networkSecurityGroup.id
        # NOTE: need to specify newer ApiVersion to get ASG info
        $rules = (Get-AzResource -ResourceId $NSGId -ExpandProperties -ApiVersion 2018-07-01).Properties | Select-Object -Property securityRules, defaultSecurityRules
        $table['SubnetSecurityRules'] = ($rules.securityRules + $rules.defaultSecurityRules) | Select-Object -Property `
            @{Name='Name';              Expression={$_.name}}, `
            @{Name='Id';                Expression={$_.id}}, `
            @{Name='Description';                               Expression={$_.properties.description}}, `
            @{Name='Protocol';                                  Expression={$_.properties.protocol}}, `
            @{Name='SourcePortRange';                           Expression={$_.properties.sourcePortRange}}, `
            @{Name='DestinationPortRange';                      Expression={$_.properties.destinationPortRange}}, `
            @{Name='SourceAddressPrefix';                       Expression={$_.properties.sourceAddressPrefix}}, `
            @{Name='DestinationAddressPrefix';                  Expression={$_.properties.destinationAddressPrefix}}, `
            @{Name='SourceApplicationSecurityGroups';           Expression={$_.properties.sourceApplicationSecurityGroups.id}}, `
            @{Name='DestinationApplicationSecurityGroups';      Expression={$_.properties.destinationApplicationSecurityGroups.id}}, `
            @{Name='Access';                                    Expression={$_.properties.access}}, `
            @{Name='Priority';                                  Expression={$_.properties.priority}}, `
            @{Name='Direction';                                 Expression={$_.properties.direction}}
        $Then = Get-Date
        $table['runspace2_runtime'] = ($Then - $Now).TotalMilliseconds
    }) > $null    
    $runspaces += [PSCustomObject]@{ Pipe = $runspace2; Status = $runspace2.BeginInvoke() }
    Write-Verbose "Invoking runspace2"

    $runspace3.AddScript({
        $Now = Get-Date
        while($null -eq $table['NicId']){}        
        $NIC = Get-AzNetworkInterface -ResourceId $table['NicId']
        $table['PrivateIpAddress'] = $NIC.IpConfigurations[0].PrivateIpAddress
        $table['ApplicationSecurityGroupIds'] = $NIC.IpConfigurations[0].ApplicationSecurityGroups.Id
        $VNet, $Subnet = $NIC.IpConfigurations[0].Subnet.Id -split '/subnets/'
        $table['VNet'] = $VNet
        $table['Subnet'] = $Subnet
        $Then = Get-Date
        $table['runspace3_runtime'] = ($Then - $Now).TotalMilliseconds        
    }) > $null 
    $runspaces += [PSCustomObject]@{ Pipe = $runspace3; Status = $runspace3.BeginInvoke() }
    Write-Verbose "Invoking runspace3"

    Write-Verbose "Waiting for runspaces to complete"
    $Now = Get-Date
    while($runspaces.Status.IsCompleted -contains $false){Start-Sleep -Milliseconds 10}
    $Then = Get-Date

    Write-Verbose "Runspaces completed in $([int]($Then-$Now).TotalMilliseconds) ms"
    Write-Verbose "Runspace1 completed in $($table['runspace1_runtime']) ms"
    Write-Verbose "Runspace2 completed in $($table['runspace2_runtime']) ms"
    Write-Verbose "Runspace3 completed in $($table['runspace3_runtime']) ms"
    $runspaces.Pipe.Dispose()
    $runspacepool.Dispose()

    $EffectiveSecurityRules = $table['SubnetSecurityRules']
    $IPv4, $ApplicationSecurityGroupIds = $table['PrivateIpAddress'], $table['ApplicationSecurityGroupIds']

    $Rules = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
    $sessionstate = [system.management.automation.runspaces.initialsessionstate]::CreateDefault()
    $sessionstate.Variables.Add(
        (New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry('Rules', $Rules, $null))
    )

    # require these functions to be available to the runspaces
    'checkSubnet', 'CheckNetworkToNetwork', 'CheckNetworkToSubnet', 'CheckSubnetToNetwork', 'SubToBinary', 'NetworkToBinary', 'Format-NSGRule' | ForEach-Object{
        $sessionstate.Commands.Add(
            (New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $_, (Get-Content "Function:\$_") -ErrorAction Stop)
        )
    }

    $runspacepool = [runspacefactory]::CreateRunspacePool(1, [int]$env:NUMBER_OF_PROCESSORS+1, $sessionstate, $Host)
    $runspacepool.Open()
    $runspaces = @()    
    # check each rule if it is relevant for that specific VM
    $Now = Get-Date
    foreach ($Rule in $EffectiveSecurityRules) {
        $runspace = [powershell]::Create()
        $runspace.RunspacePool = $runspacepool
        $Parameters = @{
            'Rule' = $Rule
            'IPv4' =  $IPv4
            'ApplicationSecurityGroupIds' =  $ApplicationSecurityGroupIds
        }
        $null = $runspace.AddScript({
            param($Rule, $ApplicationSecurityGroupIds, $IPv4)
            if($Rule.Direction -eq 'Inbound')
            {
                # need to check these first as 'checkSubnet' will fail if not a proper subnet
                if($null -ne $Rule.DestinationAddressPrefix -and ($Rule.DestinationAddressPrefix -eq '*' -or $Rule.DestinationAddressPrefix -eq 'VirtualNetwork'  -or $Rule.DestinationAddressPrefix -eq '0.0.0.0/0'))
                {
                    $Rules.Add((Format-NSGRule -Rule $Rule))
                    return
                }   
    
                Write-Debug "Checking if '$($Rule.Name)' ($IPv4) is included in '$($Rule.DestinationAddressPrefix)'"
                if($null -ne $Rule.DestinationAddressPrefix -and ($Rule.DestinationAddressPrefix | Where-Object{checkSubnet $IPv4 $_}).Count -gt 0)
                {
                    Write-Debug "Adding '$($Rule.Name)'' (Inbound)"
                    $Rules.Add((Format-NSGRule -Rule $Rule))
                    return
                }
    
                if($Rule.DestinationApplicationSecurityGroups.Count -gt 0 -and $Rule.DestinationApplicationSecurityGroups -in $ApplicationSecurityGroupIds)
                {
                    Write-Debug "Adding '$($Rule.Name)'' (Inbound)"
                    $Rules.Add((Format-NSGRule -Rule $Rule))
                    return
                }
                return
            }
            if($Rule.Direction -eq 'Outbound')
            {
                # need to check these first as 'checkSubnet' will fail if not a proper subnet
                if($null -ne $Rule.SourceAddressPrefix -and ($Rule.SourceAddressPrefix -eq '*' -or $Rule.SourceAddressPrefix -eq 'VirtualNetwork'  -or $Rule.SourceAddressPrefix -eq '0.0.0.0/0'))
                {
                    $Rules.Add((Format-NSGRule -Rule $Rule))
                    return
                }  
    
                Write-Debug "Checking if '$($Rule.Name)' ($IPv4) is included in '$($Rule.SourceAddressPrefix)'"
                if($null -ne $Rule.SourceAddressPrefix -and ($Rule.SourceAddressPrefix | Where-Object{checkSubnet $IPv4 $_}).Count -gt 0)
                {
                    Write-Debug "Adding '$($Rule.Name)'' (Outbound)"
                    $Rules.Add((Format-NSGRule -Rule $Rule))
                    return
                }  
    
                if($Rule.SourceApplicationSecurityGroups.Count -gt 0 -and $Rule.SourceApplicationSecurityGroups -in $ApplicationSecurityGroupIds)
                {
                    Write-Debug "Adding '$($Rule.Name)'' (Outbound)"
                    $Rules.Add((Format-NSGRule -Rule $Rule))
                    return
                }
                return
            }
        }).AddParameters($Parameters)
        $runspaces += [PSCustomObject]@{ Pipe = $runspace; Invocation = $runspace.BeginInvoke() }
    } # end foreach
    Write-Verbose "Waiting for runspaces to complete"
    while($runspaces.Invocation.IsCompleted -contains $false){}
    $Then = Get-Date
    Write-Host "processing completed in $([int]($Then-$Now).TotalMilliseconds) ms, $([int]((($Then-$Now).TotalMilliseconds)/($EffectiveSecurityRules.Count))) ms per rule"
    $FailedCount = ($runspaces.Pipe | Where-Object {$_.HadErrors}).Count
    Write-Verbose "$FailedCount runspaces failed"

    $runspaces.Pipe.Dispose()
    $runspacepool.Close()
    $runspacepool.Dispose()

    $Rules | Sort-Object -Property Direction, Priority
}
