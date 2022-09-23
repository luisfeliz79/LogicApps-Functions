function GetAccessTokenViaDeviceCode {
    [CmdletBinding()]
    param
    (
        # The tenant ID of the tenant to collect the OAUTH token from
        [Parameter(Mandatory = $true)]
        [System.String]
        $tenantID,

        # The resource ID of resource you want an OAUTH token for
        [Parameter(Mandatory = $true)]
        [System.String]
        $resourceID
    )
    # Known Client ID for PowerShell
    $clientid = '1950a258-227b-4e31-a9cf-717495945fc2'

    # Request device login @ Microsoft
    $DeviceCodeRequestParams = @{
        Method = 'POST'
        Uri    = "https://login.microsoftonline.com/$TenantID/oauth2/devicecode"
        Body   = @{
            client_id = $ClientId
            resource  = $ResourceID
        }
    }
    $DeviceCodeRequest = Invoke-RestMethod @DeviceCodeRequestParams

    # Show the user a message where he/she should login
    Write-Host $DeviceCodeRequest.message -ForegroundColor Yellow

    # Poll the token site to see or the user succesfully autorized
    do {
        try {
            $TokenRequestParams = @{
                Method = 'POST'
                Uri    = "https://login.microsoftonline.com/$TenantId/oauth2/token"
                Body   = @{
                    grant_type = "urn:ietf:params:oauth:grant-type:device_code"
                    code       = $DeviceCodeRequest.device_code
                    client_id  = $ClientId
                }
            }
            $TokenRequest = Invoke-RestMethod @TokenRequestParams

            If ($TokenRequest.access_token -ne $null) {
                # Return the token information
                return $TokenRequest
            }


            
            
        }
        catch {
            if ((convertfrom-json $_.ErrorDetails.Message).error -eq "authorization_pending") {
                write-host "." -NoNewline
                Start-Sleep -Seconds 5
            }
            else {
                throw "Unkown error while requesting token"
            }
        }
    } while ($true)

}

function GetAccessTokenViaRefreshToken {
    [CmdletBinding()]
    param
    (
        # The OAUTH refresh token
        [Parameter(Mandatory = $true)]
        [System.string]
        $refreshtoken,
        $TenantID,
        $clientid= '1950a258-227b-4e31-a9cf-717495945fc2',
        $scope
    )
    # Known Client ID for PowerShell
    
    $TokenRequestParams = @{
        Method = 'POST'
        Uri    = "https://login.microsoftonline.com/$TenantId/oauth2/token"
        Body   = @{
            grant_type    = "refresh_token"
            refresh_token = $refreshtoken
            client_id     = $ClientId
            scope         = $scope
        }
    }
    $TokenRequest = Invoke-RestMethod @TokenRequestParams
    return $TokenRequest
}



function CreateAuthorizationHeader($Authresult) {


    

    return "Bearer $($AuthResult.Access_Token)"
}

Function ListLogAnalyticsWorkspaces($Subscription,$AuthResult) {
#https://docs.microsoft.com/en-us/rest/api/appservice/app-service-plans/list

    $AuthZ = CreateAuthorizationHeader -Authresult $AuthResult
    $Header = @{
        "x-ms-version" = "2014-10-01"
        "Authorization" = $AuthZ
    }

    $URL= "https://management.azure.com/subscriptions/{0}/providers/Microsoft.OperationalInsights/workspaces?api-version=2021-12-01-preview" -f $Subscription
    $RestResult=Invoke-RestMethod -Method Get -Headers $Header -Uri $URL

    return $RestResult

    
}

Function ExecuteLogAnalyticsWorkspaceQuery($LAW,$AuthResult) {
#https://docs.microsoft.com/en-us/rest/api/appservice/app-service-plans/list

    $AuthZ = CreateAuthorizationHeader -Authresult $AuthResult
    $Header = @{
        "x-ms-version" = "2014-10-01"
        "Authorization" = $AuthZ
    }



    $query=[pscustomobject]@{
    
        query=@'
        Usage 
| where TimeGenerated > ago(32d)
| where StartTime >= startofday(ago(31d)) and EndTime < startofday(now())
| where IsBillable == true
| summarize BillableDataGB = sum(Quantity) / 1000 
'@
        workspaces=@($LAW)
    } | ConvertTo-Json

    $URL= "https://api.loganalytics.io/v1/workspaces/{0}/query" -f $LAW

    #Write-Warning $query
    #write-warning ($Header| Convertto-Json)
    #write-warning $URL

    #Write-Warning "entering prompt"
    #$host.EnterNestedPrompt()

    $RestResult=Invoke-RestMethod -Method POST -Headers $Header -Uri $URL -Body $query -ContentType 'application/json'

    return $RestResult
    
}









$Subscription="f263b677-361a-4ec3-91d6-c4e05012c36b"
$tenant="microsoft.onmicrosoft.com"

# First, lets get an access token
if ($AuthResult.access_token -eq $null) {
    $AuthResult=GetAccessTokenViaDeviceCode -tenantid "common" -resourceid "https://management.core.windows.net/"

}

# Get any additional tokens via refresh token
if ($AuthResultLogAnalytics.access_token -eq $null) {
    #$AuthResultLogAnalytics=GetAccessTokenViaRefreshToken -scope "https://api.loganalytics.io" -refreshtoken $AuthResult.Refresh_Token 
    $AuthResultLogAnalytics=GetAccessTokenViaDeviceCode -TenantID $tenant -resourceid "https://api.loganalytics.io"

}



 
#Get List of Plans    
$LAWs=(ListLogAnalyticsWorkspaces -Subscription $Subscription -AuthResult $AuthResult).value

#Get Info about each Law

$LAWs | foreach {

    $currentLaw=$_
    $queryResult=ExecuteLogAnalyticsWorkspaceQuery -LAW $currentLaw.properties.customerId -AuthResult $AuthResultLogAnalytics
    if ($queryResult.tables.rows -ne $null) {
        $Usage=[math]::Round($queryResult.tables.rows[0],2)
    }

    [PSCustomObject]@{
    
        name=$currentLaw.name
        customerId=$currentLaw.properties.customerId
        region=$currentLaw.location
        type=$currentLaw.location
        sku=$currentLaw.properties.sku.name
        quota=$currentLaw.properties.workspaceCapping.dailyquotagb
        quotestatus=$currentLaw.properties.workspaceCapping.dataIngestionStatus
        Usage=$Usage

    
    }


}


#ExecuteLogAnalyticsWorkspaceQuery2 -LAW $LAWs[3].id -AuthResult $AuthResult