param (
    [string]$taskId
)
$server = "https://treasuryreportsnprinting.tsyuat.treasury.westpac.com.au:4993"


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

    Start-Sleep -Seconds 5

    # Run a publish task
    $url = "$server/api/v1/tasks/$taskId/executions"
    try {
        [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
        $taskExecutionResponse = Invoke-RestMethod -WebSession $session -Uri $url -Method Post -Headers $hdrs
    } catch {
        Write-Output "Task execution API returned an error."
        continue
    }
