# Load parameters from CSV file
$parameters = Import-Csv -Path "\\treasuryanalytics\4.Analytics\IRL\ARF117\9.NPRINT\NPParameters1171.txt"
$server = $parameters.server
$appId = $parameters.appId
$connectionId = $parameters.connectionId
$filterId = $parameters.filterId
$filterName = $parameters.filterName
$directory = $parameters.formsfolder
$taskId = $parameters.taskId
$xmlfile = $parameters.form
$computerName = $env:COMPUTERNAME
$logFile = "\\treasuryanalytics\4.Analytics\IRL\ARF117\9.NPRINT\error_log.txt"
$userId = $env:USERNAME

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

# Load the XML file
[xml]$xml = Get-Content -Path $xmlfile

# Function to log errors
function Log-Error {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $message"
    Add-Content -Path $logFile -Value $logMessage
}

# Iterate through each record
foreach ($record in $xml.records.record) {
    # Find the fm_RunStatus element
    $runStatus = $record.value | Where-Object { $_.name -eq "fm_RunStatus" }
    $runResult = $record.value | Where-Object { $_.name -eq "fm_RunResult" }
    if ($runStatus.'#text' -eq "2") {
        # Split the key field into variables
        $keyParts = $record.key -split '\|\|'
        $frequency = $keyParts[0]
        $date = $keyParts[1]
    
        # Convert filter fields to JSON
        $fields = @()
        $values = @()

        $valueObject = New-Object PSObject
        $valueObject | Add-Member -Type NoteProperty -Name "value" -Value $frequency
        $valueObject | Add-Member -Type NoteProperty -Name "type" -Value 'text'
        $values += $valueObject

        $field = New-Object PSObject
        $field | Add-Member -Type NoteProperty -Name "connectionId" -Value $connectionId
        $field | Add-Member -Type NoteProperty -Name "name" -Value 'Frequency'
        $field | Add-Member -Type NoteProperty -Name "values" -Value $values
        $fields += $field

        # Add date filter
        $dateValues = @()
        $dateValueObject = New-Object PSObject
        $dateValueObject | Add-Member -Type NoteProperty -Name "value" -Value $date
        $dateValueObject | Add-Member -Type NoteProperty -Name "type" -Value 'number'
        $dateValues += $dateValueObject

        $dateField = New-Object PSObject
        $dateField | Add-Member -Type NoteProperty -Name "connectionId" -Value $connectionId
        $dateField | Add-Member -Type NoteProperty -Name "name" -Value 'NumdBusinessDate'
        $dateField | Add-Member -Type NoteProperty -Name "values" -Value $dateValues
        $fields += $dateField

        $updatedBody = @{
            enabled = $true
            name = $filterName
            appId = $appId
            fields = $fields
        } | ConvertTo-Json -Depth 4
        
        $url = "$server/api/v1/filters/$filterId"
        try {
            [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
            $filterUpdateResponse = Invoke-RestMethod -WebSession $session -Uri $url -Method Put -ContentType 'application/json' -Headers $hdrs -Body $updatedBody
        } catch {
            $runStatus.'#text' = "1"
            $runResult.'#text' = "Filter update API returned an error on $computerName - user: $userId"
            $xml.Save($xmlfile)
            Log-Error "Filter update API error: $($_.Exception.Message)"
            return
        }

        Start-Sleep -Seconds 5

        # Run a publish task
        $url = "$server/api/v1/tasks/$taskId/executions"
        
        try {
            [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
            $taskExecutionResponse = Invoke-RestMethod -WebSession $session -Uri $url -Method Post -Headers $hdrs 
            # Update fm_RunStatus to 3
            $runStatus.'#text' = "3"
            $runResult.'#text' = "Task executed successfully"
            $xml.Save($xmlfile)
        } catch {
            $runStatus.'#text' = "1"
            $runResult.'#text' = "Task execution API returned an error on $computerName - user: $userId"
            $xml.Save($xmlfile)
            Log-Error "Task execution API error: $($_.Exception.Message)"
        }
        continue
    }
}