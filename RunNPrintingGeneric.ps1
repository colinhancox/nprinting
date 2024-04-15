# Load variables from CSV file
$variables = Import-Csv -Path ".\NPParameters.txt"
$server = $variables.server
$appId = $variables.appId
$connectionId = $variables.connectionId
$filterId = $variables.filterId
$filterName = $variables.filterName
$taskId = $variables.taskId
$directory = $variables.selectionsfolder

# Set TLS to minimum 1.1 for NPrinting Feb 2018 (using 1.2 in this example)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Authenticate and get cookie
$url = "$server/api/v1/login/ntlm"
Invoke-RestMethod -UseDefaultCredentials -Uri $url -Method Get -Headers $hdrs -SessionVariable websession
$cookies = $websession.Cookies.GetCookies($url)
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$session.Cookies.Add($cookies)

# Extract XSRF token from cookie
$xsrf_token = $($cookies | Where-Object {$_.Name -eq "NPWEBCONSOLE_XSRF-TOKEN"}).Value

$hdrs = @{}
$hdrs.Add("X-XSRF-token", $xsrf_token)

# Get all the files in the directory
$files = Get-ChildItem -Path $directory -File

# Loop through each file in the directory
foreach ($file in $files) {
    # Read data from CSV file
    $data = Import-Csv -Path $file.FullName

    # Convert filter fields to JSON
    $fields = @()

    # Group the data by name
    $groupedData = $data | Group-Object -Property name

    # Loop through each group in the grouped data
    foreach ($group in $groupedData) {
        # Create an empty array to hold the values
        $values = @()

        # Loop through each row in the group
        foreach ($row in $group.Group) {
            # Split the values into an array
            $valueArray = $row.value -split ";"

            # Loop through each value
            foreach ($value in $valueArray) {
                # Create a new PSObject and add properties to it
                $valueObject = New-Object PSObject
                $valueObject | Add-Member -Type NoteProperty -Name "value" -Value $value
                $valueObject | Add-Member -Type NoteProperty -Name "type" -Value $row.type

                # Add the new object to the values array
                $values += $valueObject
            }
        }

        # Create a new PSObject and add properties to it
        $field = New-Object PSObject
        $field | Add-Member -Type NoteProperty -Name "connectionId" -Value $connectionId
        $field | Add-Member -Type NoteProperty -Name "name" -Value $group.Name
        $field | Add-Member -Type NoteProperty -Name "values" -Value $values

        # Add the new object to the fields array
        $fields += $field
    }

    $updatedBody = @{
        enabled = $true
        name = $filterName
        appId = $appId
        fields = $fields
    } | ConvertTo-Json -Depth 4

    $url = "$server/api/v1/filters/$($filterId)"
    try {
        $filterUpdateResponse = Invoke-RestMethod -WebSession $session -Uri $url -Method Put -ContentType 'application/json' -Headers $hdrs -Body $updatedBody
    } catch {
        Write-Output "Filter update API returned an error. The file will not be deleted."
        continue
    }
    
    Start-Sleep -Seconds 5
    
    # Run a publish task
    $url = "$server/api/v1/tasks/$taskId/executions"
    try {
        $taskExecutionResponse = Invoke-RestMethod -WebSession $session -Uri $url -Method Post -Headers $hdrs
    } catch {
        Write-Output "Task execution API returned an error. The file will not be deleted."
        continue
    }

    # If no errors, delete the file
    Remove-Item -Path $file.FullName
}
