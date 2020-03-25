using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

$status = $body = $null

try {
    <ParseParameterBlock>    
}
catch {
    $status = [HttpStatusCode]::BadRequest
    $body = "Invalid input"
}

# may have been already set due to exception when parsing input
if($null -eq $status)
{
    try {
        $body = <FunctionCall>
        $status = [HttpStatusCode]::OK
    }
    catch {
        $status = [HttpStatusCode]::BadRequest
        $body = $_
    }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $status
    Body = $body
})