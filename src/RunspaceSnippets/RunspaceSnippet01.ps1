<#
runspace template
#>

. .\Invoke-Runspaces.ps1

$VerbosePreference = 'Continue'

# define your scriptblocks
$ScriptBlocks = @(
    {
        $Now = Get-Date
        # get stuff from $table
        $VMName = $table['VMName']
        $VMResourceGroup = $table['VMResourceGroup']
        # do stuff
        Start-Sleep -Milliseconds 2542
        # then put stuff into $table
        $table['Location'] = "<location of something>"
        $Then = Get-Date
        # could also register the runtime
        $table['runspace0_runtime'] = ($Then - $Now).TotalMilliseconds
    },
    {
        $Now = Get-Date
        # get stuff from $table
        $VMName = $table['VMName']
        $VMResourceGroup = $table['VMResourceGroup']
        # do stuff
        Start-Sleep -Milliseconds 4242
        # then put stuff into $table
        $table['Location'] = "<location of something>"
        $Then = Get-Date
        # could also register the runtime
        $table['runspace1_runtime'] = ($Then - $Now).TotalMilliseconds
    }
)

# Sync'd hash table is accessible between threads
$table = [HashTable]::Synchronized(@{})
# we can prepopulate the hash table
$table['VMName'] = "<a VM name>"
$table['VMResourceGroup'] = "<a VM resource group>"

Invoke-Runspaces -SessionStateVariable $table -SessionStateVariableName 'table' -ScriptBlocks $ScriptBlocks