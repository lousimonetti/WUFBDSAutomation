import-module Microsoft.Graph.Authentication #-RequiredVersion 2.11.1 or newer
$graphUrl = 'https://graph.microsoft.com'

function Get-PatchTue {
	<#
    from: https://gist.github.com/BanterBoy/97d7766ad8bb24b72215b1d41a055f3c
	.SYNOPSIS
	Get the Patch Tuesday of a month
	.PARAMETER month
	The month to check
	.PARAMETER year
	The year to check
	.EXAMPLE
	Get-PatchTue -month 6 -year 2015
	.EXAMPLE
	Get-PatchTue June 2015
	#>
	param(
		[string]$month = (get-date).month,
		[string]$year = (get-date).year)
	$firstdayofmonth = [datetime] ([string]$month + "/1/" + [string]$year)
	(0..30 | ForEach-Object {
			$firstdayofmonth.adddays($_)
		} |
		Where-Object {
			$_.dayofweek -like "Tue*"
		})[1]
}

# Get the Access token function using client ID and Secret
function Get-Authentication()
{

    Add-Type -AssemblyName System.Web
    #$secret
    #UrlEscapeDataString($secret)
    $tokenUrl = 'https://login.microsoftonline.com/c3e32f53-cb7f-4809-968d-1cc4ccc785fe/oauth2/v2.0/token'
    $secret = '<client secret here from Entra ID app registration>'
    $clientId = '<clientId here from Entra ID app registration>'
    $encodedSecret = [System.Web.HttpUtility]::UrlEncode($secret)
    $scope = 'https://graph.microsoft.com/.default'
    $scopeEncoded = [System.Web.HttpUtility]::UrlEncode($scope)
    $clientCredential = "client_id=$($clientId)&scope=$($scopeEncoded)&client_secret=$($encodedSecret)&grant_type=client_credentials"
    
    $response = Invoke-webrequest -uri $tokenUrl -Body $clientCredential -Method POST -ContentType 'application/x-www-form-urlencoded' -UseBasicParsing
    $token = $response.Content | ConvertFrom-Json | select -expand access_token
    
    # we don't need this header anymore
    # $authenticationHeader=  @{"Authorization"= "bearer $($token)"}
    $securetoken = ConvertTo-SecureString -String $token -AsPlainText -Force
    
    Connect-Graph -accesstoken $securetoken
}


## Invoke GET Authentication in the GRAPH
Get-Authentication
## NOTE: if you are using a Managed identity comment out the previous line and uncomment this line. 
##Connect-Graph -identity 
##

Function Get-AllPolicies()
{

    ## GET ALL the Policies
    $allPoliciesUrl = $graphUrl + '/beta/deviceManagement/windowsDriverUpdateProfiles?$select=id,displayName,description,newUpdates,approvalType,createdDateTime,deviceReporting,assignments&$expand=assignments'
    $allPolicies = (Invoke-GraphRequest -Uri $allPoliciesUrl -Method GET).value
    $json = $allPolicies | ConvertTo-Json
    $policies = ($json | ConvertFrom-Json)
    return $policies;     
}

$policies = Get-AllPolicies;

### This function will invoke all the approvals to be dated on Patch tuesday
Function Invoke-ApprovalOnPolicy() 
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]
        $PolicyID,
        [Parameter()]
        [bool]
        $IncludeFirmware = $false
    ) 
    # $nextLinkFound = $false;
    # building the body for the request 
    $date = Get-PatchTue;
    $formatedDate= Get-Date -Date $date -UFormat "%Y-%m-%dT05:00:00.000Z";
    $bodyRequest = @"
{
 "actionName":"Approve",
 "driverIds":[
 ],
 "deploymentDate":"$($formatedDate)"
}
"@
# Convert to an object
    $bodyobject  = $bodyRequest |Convertfrom-json

## Collect the drivers pending approval
## making a drivers array to hold all the drivers 
    $drivers = @();
    ## initial call to the policy ID URI
    $policy = (Invoke-GraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsDriverUpdateProfiles/$($PolicyID)/driverInventories?`$filter=category%20eq%20%27recommended%27 and approvalStatus eq 'needsReview'&`$select=id,name,manufacturer,releaseDateTime,applicableDeviceCount,approvalStatus,category,driverClass" -Method GET ) 
    # is there more than 200 drivers?
    while($null -ne $policy.'@odata.nextLink' )
    {
        $drivers += $policy.value | Convertto-json | convertfrom-json
        $policy = (Invoke-GraphRequest -Uri $policy.'@odata.nextLink' -Method GET ) 
             
    }
    $drivers = $policy.value | Convertto-json | convertfrom-json 
    $batchsize = 50;
    if ($drivers.count -gt 0) {
        for ($i = 0; $i -lt $drivers.Length; $i += $batchsize) 
        { 
            $currentBatch = $drivers[$i..($I + $batchsize)]; 
            if(-not($IncludeFirmware)) {
                if($drivers[$i].driverClass -ne 'Firmware'){
                    $bodyobject.driverIds= $currentBatch.id; 
                    $bodyJson = $bodyobject | Convertto-json; 
                    $bodyobject.deploymentDate = "$($formatedDate)"; 
                    #$bodyJson
                }
            } else
            {
                $bodyobject.driverIds= $currentBatch.id; 
                $bodyJson = $bodyobject | Convertto-json; 
                $bodyobject.deploymentDate = "$($formatedDate)"; 
            }
            Invoke-GraphRequest -URI "https://graph.microsoft.com/beta/deviceManagement/windowsDriverUpdateProfiles/$($policyId)/ExecuteAction" -Method POST -Body $bodyJson 

        }
    }

    #return $drivers 

}

## for all policies, you could do the following: 
$inluceFirmware = $false;
foreach ($policy in $policies) {
    if ($policy.approvalType -eq 'manual') {
        $policyId = $policy.Id;
        ### if we were to idenfify a group for including or excluding firmware we could do a trigger like this 
        ### if you have policies named PROD something this could be used to match only your produciton policies 
        ### if(($policy.displayName -match "PROD*") -and ($policy.newUpdates -gt 0)){
        ### if not, and you just want ot run against all policies do the following, otherwise comment it out and use the previous line:
        if($policy.newUpdates -gt 0){
            if(-not($includeFirmware)){
                Invoke-ApprovalOnPolicy -PolicyID $policyId -IncludeFirmware $false
            }
            else {
                Invoke-ApprovalOnPolicy -PolicyID $policyId -IncludeFirmware $true
            }
        }

    }
}
