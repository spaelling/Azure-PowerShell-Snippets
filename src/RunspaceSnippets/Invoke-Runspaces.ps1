function Invoke-Runspaces {
    [CmdletBinding()]
    param (
        [HashTable]
        $SessionStateVariable,

        [string]
        $SessionStateVariableName,
        
        [Array]
        $ScriptBlocks
    )
    
    begin {
        Write-Verbose "Setting up runspaces..."
        $NumOfRunspaces = $ScriptBlocks.Count
        # create a session state
        $sessionstate = [system.management.automation.runspaces.initialsessionstate]::CreateDefault()
        # inside the runspace refer to the name of the variable (ex. table), and outside to the variable, ex. $table
        $SessionStateVariableEntry = (New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry('table', $table, $null))
        $sessionstate.Variables.Add(
            $SessionStateVariableEntry
        )
        
        # create the runspace pool and include the session state
        $runspacepool = [runspacefactory]::CreateRunspacePool(1, [int]$env:NUMBER_OF_PROCESSORS+1, $sessionstate, $Host)
        $runspacepool.Open()        
    }
    
    process {
        $runspaces = 1..$NumOfRunspaces | ForEach-Object {
            $runspace = [powershell]::Create()
            $runspace.RunspacePool = $runspacepool
            $runspace
        }
        
        $runspaces = for ($i = 0; $i -lt $runspaces.Count; $i++) {
            $runspace = $runspaces[$i]
            $null = $runspace.AddScript($ScriptBlocks[$i])
            [PSCustomObject]@{ Pipe = $runspace; Status = $runspace.BeginInvoke() }    
        }
        
        Write-Verbose "Waiting for $($runspaces.Count) runspaces to complete"
        $Now = Get-Date
        while($runspaces.Status.IsCompleted -contains $false){Start-Sleep -Milliseconds 10}
        $Then = Get-Date
        
        Write-Verbose "Runspaces completed in $([int]($Then-$Now).TotalMilliseconds) ms"
        for ($i = 0; $i -lt $runspaces.Count; $i++) {
            Write-Verbose "Runspace$i completed in $($table["runspace$($i)_runtime"]) ms"
        }
    }
    
    end {
        $runspaces.Pipe.Dispose()
        $runspacepool.Dispose()        
    }
}
