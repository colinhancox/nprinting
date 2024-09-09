# Ultimate script that works for fields, variables and tasks
# Load parameters from CSV file
#$parameters = Import-Csv -Path "\\10.38.151.102\e$\QlikView\Source Documents\Phoenix\MonthEnd_PnL\5.NPrinting\Scripts\NPParameters.txt"
$parameters = Import-Csv -Path "\\reports-portal\e$\QlikView\Source Documents\Phoenix\MonthEnd_PnL\5.NPrinting\Scripts\NPParameters.txt"
$server = $parameters.server
$appId = $parameters.appId
$connectionId = $parameters.connectionId
$filterId = $parameters.filterId
$filterName = $parameters.filterName
#$taskId = $parameters.taskId
$directory = $parameters.selectionsfolder

add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

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
	$variables = @()

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

		if ($row.type -eq 'variable') {
			# Create a new PSObject and add properties to it
			$variable = New-Object PSObject
			$variable | Add-Member -Type NoteProperty -Name "connectionId" -Value $connectionId
			$variable | Add-Member -Type NoteProperty -Name "name" -Value $group.Name
			$variable | Add-Member -Type NoteProperty -Name "value" -Value $values[0].value
			$variable | Add-Member -Type NoteProperty -Name "evaluate" -Value $false

			# Add the new object to the variables array
			$variables += $variable
		} elseif ($row.type -eq 'text' -or $row.type -eq 'number') {
    
			# Create a new PSObject and add properties to it
			$field = New-Object PSObject
			$field | Add-Member -Type NoteProperty -Name "connectionId" -Value $connectionId
			$field | Add-Member -Type NoteProperty -Name "name" -Value $group.Name
			$field | Add-Member -Type NoteProperty -Name "values" -Value $values

			# Add the new object to the fields array
			$fields += $field
		} elseif ($row.type -eq 'task') {
    
			$taskId = $row.value
		}
    }

    $updatedBody = @{
        enabled = $true
        name = $filterName
        appId = $appId
        fields = $fields
        variables = $variables
    } | ConvertTo-Json -Depth 4

	
    $url = "$server/api/v1/filters/$filterId"
    try {
        [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
        $filterUpdateResponse = Invoke-RestMethod -WebSession $session -Uri $url -Method Put -ContentType 'application/json' -Headers $hdrs -Body $updatedBody
    } catch {
        Write-Output "Filter update API returned an error. The file will not be deleted."
        continue
    }
	
	Start-Sleep -Seconds 5

    # Run a publish task
    $url = "$server/api/v1/tasks/$taskId/executions"
    try {
        [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
        $taskExecutionResponse = Invoke-RestMethod -WebSession $session -Uri $url -Method Post -Headers $hdrs
    } catch {
        Write-Output "Task execution API returned an error. The file will not be deleted."
        continue
    }

    # If no errors, delete the file
    Remove-Item -Path $file.FullName
}
