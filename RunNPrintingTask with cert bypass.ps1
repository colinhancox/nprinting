# Load variables from CSV file
#$variables = Import-Csv -Path "\\10.38.151.102\e$\QlikView\Source Documents\Phoenix\Phoenix NPrinting\4.Scripts\NPParameters.txt"
#$server = $variables.server
$server = "https://treasuryreportsnprinting.tsydev.treasury.westpac.com.au:4993"
#$taskId = $variables.taskId
$taskId = "50089a1c-a6d4-4752-8623-fad23a544ca9"

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

    # Run a publish task
    $url = "$server/api/v1/tasks/$taskId/executions"
    try {
        [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
        $taskExecutionResponse = Invoke-RestMethod -WebSession $session -Uri $url -Method Post -Headers $hdrs
    } catch {
        Write-Output "Task execution API returned an error."
        continue
    }

