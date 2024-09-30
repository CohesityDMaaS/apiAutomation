
# ./Deploy_CCS_AWSsaasConns.ps1 -apiKey #### -CCSregionId us-east-1 -AWSregionId us-east-1 -AWSid #### -subnetId subnet-#### -securityGroupId sg-#### -vpcId vpc-#### -saasNo 2 -AWStag "label=value", "label=value" -connAdd

# install PowerShell, if on macOS: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-macos?view=powershell-7.2
# upgrade PowerShell Module to current revision of 7.2.4: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.2#msi


# process commandline arguments
[CmdletBinding()]
param (
    [Parameter(Mandatory = $True)][string]$apiKey,  # apiKey generated in CCS UI
    [Parameter(Mandatory = $True)][string]$CCSregionId,  # CCS region where AWS is Registered
    [Parameter(Mandatory = $True)][string]$AWSid,  # AWS Account ID
    [Parameter(Mandatory = $True)][string]$AWSregionId,  # AWS region where SaaS Connector EC2 Instance will be deployed 
    [Parameter(Mandatory = $True)][string]$subnetId,  # AWS Subnet Identifier
    [Parameter(Mandatory = $True)][string]$securityGroupId,  # AWS Network Security Group
    [Parameter(Mandatory = $True)][string]$vpcId,  # AWS VPC Id
    [Parameter()][int]$saasNo = 1,  # (optional) Number of AWS SaaS Connector EC2 Instances to create
    [Parameter()][array]$AWStag,  # (optional) AWS SaaS Connector EC2 Instance Tags (comma separated)
        # example: "label=value", "label2=value2"
    [Parameter()][string]$AWStags = '',  # (optional) text file of AWS SaaS Connector EC2 Instance Tags (one per line)
         # example: "label=value"
         #          "label2=value2"
    [Parameter()][switch]$connAdd  # (optional) call adding additional SaaS Connectors to already existing Connector Group
)


# set static variables
$dateString = (get-date).ToString('yyyy-MM-dd')
$dateTime = Get-Date -Format "dddd MM/dd/yyyy HH:mm"
$outfileName = "$PSScriptRoot\log-Deploy_CCS_AWSsaasConns-$dateString.txt"


# ensure the environment meets the PowerShell Module requirements of 5.1 or above 

write-host "`nValidating PowerShell Version...`n"
Write-Output "`n$dateTime    INFO    Validating PowerShell Version...`n" | Out-File -FilePath $outfileName -Append
$version = $PSVersionTable.PSVersion
if($version.major -lt 5.1){
    write-host "`nPlease upgrade the PowerShell Module to the current revision of 7.2.4 by downloading from the Microsoft site: `nhttps://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.2#msi" -ForegroundColor Yellow
    Write-Output "`n$dateTime    WARN    Please upgrade the PowerShell Module to the current revision of 7.2.4 by downloading from the Microsoft site: `nhttps://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.2#msi" | Out-File -FilePath $outfileName -Append
}
else {
    write-host "PowerShell Module is up to date." -ForegroundColor Green 
    Write-Output "$dateTime    INFO    PowerShell Module is up to date." | Out-File -FilePath $outfileName -Append
}


# gather list of AWS Tag's to Associate with SaaS Connector EC2 Instance
$tagsToAdd = @()
if('' -ne $AWStag){
    Write-Host "`nGathering list of AWS Tag's to Associate with SaaS Connector EC2 Instance..."
    Write-Output "`n$dateTime    INFO    Gathering list of AWS Tag's to Associate with SaaS Connector EC2 Instance..." | Out-File -FilePath $outfileName -Append 
    foreach($tag in $AWStag){
        $tagsToAdd += $tag
    }
}
if('' -ne $AWStags){
    Write-Host "`nGathering list of AWS Tag's to Associate with SaaS Connector EC2 Instance..."
    Write-Output "`n$dateTime    INFO    Gathering list of AWS Tag's to Associate with SaaS Connector EC2 Instance..." | Out-File -FilePath $outfileName -Append 
    if(Test-Path -Path $AWStags -PathType Leaf){
        $AWStag = Get-Content $AWStags
        foreach($tag in $AWStag){
            $tagsToAdd += [string]$tag
        }
    }else{
        Write-Host "`nAWS SaaS Connector Tags file $AWStags not found at specified directory!" -ForegroundColor Yellow 
        Write-Output "`n$dateTime    WARN    AWS SaaS Connector Tags file $AWStags not found at specified directory!" | Out-File -FilePath $outfileName -Append 
        exit
    }
}

$tagsToAdd = @($tagsToAdd | Where-Object {$_ -ne ''})

if($tagsToAdd.Count -gt 0){
    Write-Host "`nAWS SaaS Connector Tags parsed SUCCESSFULLY!`n" -ForegroundColor Green 
    Write-Output "`n$dateTime    INFO    AWS SaaS Connector Tags parsed SUCCESSFULLY!`n" | Out-File -FilePath $outfileName -Append 
    write-output $tagsToAdd | Out-File -FilePath $outfileName -Append 
}

# test API Connection
$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"

Write-host "`nTesting API Connection...`n" 
Write-Output "`n$dateTime    INFO    Testing API Connection...`n" | Out-File -FilePath $outfileName -Append 
$headers.Add("apiKey", "$apiKey")
$apiTest = Invoke-RestMethod 'https://helios.cohesity.com/irisservices/api/v1/public/mcm/clusters/info' -Method 'GET' -Headers $headers 

if(!$apiTest){
    write-host "`nInvalid API Key" -ForegroundColor Yellow 
    write-output "`n$dateTime    WARN    Invalid API Key" | Out-File -FilePath $outfileName -Append 
    exit
}else{
    Write-Host "`nConnection with apiKey SUCCESSFUL!`n" -ForegroundColor Green 
    write-output "`n$dateTime    INFO    Connection with apiKey SUCCESSFUL!`n" | Out-File -FilePath $outfileName -Append 
    write-output $apiTest | Out-File -FilePath $outfileName -Append 
}

# validate CCS Tenant ID
Write-host "`nValidating Tenant ID...`n"  
write-output "`n$dateTime    INFO    Validating Tenant ID...`n" | Out-File -FilePath $outfileName -Append 
$headers.Add("accept", "application/json, text/plain, */*")
#$headers.Add('content-type: application/json')
$tenant = Invoke-RestMethod 'https://helios.cohesity.com/irisservices/api/v1/mcm/userInfo' -Method 'GET' -Headers $headers

$tenantId = $tenant.user.profiles.tenantId 

if(!$tenantId){
    write-host "`nNo CCS Tenant ID found!" -ForegroundColor Yellow
    write-output "`n$dateTime    WARN    No CCS Tenant ID found!" | out-file -filepath $outfileName -Append
}
else{
    Write-host "`nTenant ID: $tenantId" -ForegroundColor Green 
    write-output "`n$dateTime    INFO    Tenant ID: $tenantId" | Out-File -FilePath $outfileName -Append 
}



# validate CCS Region ID
Write-host "`nValidating CCS Region ID...`n" 
write-output "`n$dateTime    INFO    Validating CCS Region ID...`n" | Out-File -FilePath $outfileName -Append 
$region = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/dms/tenants/regions?tenantId=$tenantId" -Method 'GET' -Headers $headers
$regions = $region.tenantRegionInfoList.regionId

$compareRegion = Compare-Object -IncludeEqual -ReferenceObject $regions -DifferenceObject $CCSregionId -ExcludeDifferent
$verRegion = $compareRegion.InputObject | where-object{$compareRegion.SideIndicator -eq "=="}

if($verRegion){
    Write-Host "`nCCS Region ID Verified: $verRegion" -ForegroundColor Green
    write-output "`n$dateTime    INFO    CCS Region ID Verified: $verRegion`n" | Out-File -FilePath $outfileName -Append 
}
else{
    write-host "`nThere are no matching CCS Region Ids asssociated with the specified Tenant ID!" -ForegroundColor Yellow 
    write-output "`n$dateTime    WARN    There are no matching CCS Region Ids asssociated with the specified Tenant ID!" | Out-File -FilePath $outfileName -Append 
    exit
}

$headers.Add("regionId", "$CCSregionId")


# validate if this script is intended to add to current SaaS Connector count

Write-host "`nPulling AWS Source Info...`n" 
write-output "`n$dateTime    INFO    Pulling AWS Source Info...`n" | Out-File -FilePath $outfileName -Append 

$awsSources = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/data-protect/sources?environments=kAWS" -Method 'GET' -Headers $headers
$awsSource = $awsSources.sources | where-object {$_.name -eq "$AWSid"}
$awsSourceId = $awsSource.sourceInfoList.sourceId
$regId = $awsSource.sourceInfoList.registrationId

Write-host "`nCCS AWS Registration ID: $regId`n" 
write-output "`n$dateTime    INFO    CCS AWS Registration ID: $regId`n" | Out-File -FilePath $outfileName -Append 

#$proSources = Invoke-RestMethod "https://helios.cohesity.com/irisservices/api/v1/public/protectionSources?useCachedData=true&id=$awsSourceId" -Method 'GET' -Headers $headers

#$awsConnInfo = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/dms/tenants/regions/aws-cloud-source?tenantId=$tenantId&destinationRegionId=$CCSregionId&awsAccountNumber=$AWSid" -Method 'GET' -headers $headers

$rigelInfo = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/data-protect/sources/registrations/$regId" -Method 'GET' -headers $headers
$groupId = $rigelInfo.connections.connectionId

Write-host "`nCCS AWS SaaS Connection Group ID: $groupId`n" 
write-output "`n$dateTime    INFO    CCS AWS SaaS Connection Group ID: $groupId`n" | Out-File -FilePath $outfileName -Append 

if($groupId){
    # $saasConn = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/rigelmgmt/rigel-groups?tenantId=$tenandId&regionId=$CCSregionId&groupId=$groupId&getConnectionStatus=true" -Method 'GET' -headers $headers
    # $saasConnNum = $saasConn.rigelGroups.expectedNumberOfRigels
    # UPDATE
    $saasConn = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/rigelmgmt/rigel-groups?tenantId=$tenandId&groupId=$groupId&fetchToken=true" -Method 'GET' -headers $headers
    $saasConnNum = $saasConn.rigelGroups.expectedNumberOfRigels

    Write-host "`nNumber of CCS AWS SaaS Connectors already implemented: $saasConnNum`n" 
    write-output "`n$dateTime    INFO    Number of CCS AWS SaaS Connectors already implemented: $saasConnNum`n" | Out-File -FilePath $outfileName -Append 
}

if($saasConnNum -gt 0 -and $connAdd -eq $false){
    Write-host "`nThis CCS AWS Source already has $saasConnNum SaaS Connector(s) deployed!`n" -ForegroundColor Yellow
    write-output "`n$dateTime    WARN    This CCS AWS Source already has $saasConnNum SaaS Connector(s) deployed!`n" | Out-File -FilePath $outfileName -Append 

    $connAddOverride = read-host -prompt "`nDo you need to add additional CCS AWS SaaS Connectors to the already existing CCS AWS SaaS Connection Group? (y/n)"
    write-output "`n$dateTime    WARN    Do you need to add additional CCS AWS SaaS Connectors to the already existing CCS AWS SaaS Connection Group? (y/n)`nUSER RESPONSE: $connAddOverride" | Out-File -FilePath $outfileName -Append 

    if($connAddOverride -eq $false){
        Write-host "`nIf you are attempting to to create a new CCS AWS SaaS Connection Group in addition to the one which already exists, please know that Cohesity only supports one Connection Group per AWS Region.`n" -ForegroundColor Yellow
        write-output "`n$dateTime    WARN    If you are attempting to to create a new CCS AWS SaaS Connection Group in addition to the one which already exists, please know that Cohesity only supports one Connection Group per AWS Region.`n" | Out-File -FilePath $outfileName -Append 
    }
    else{
        $connAdd = $true
        Write-host "`nEnabled the 'connAdd' switch to perform an addition to the already existing AWS SaaS Connection Group.`n" -ForegroundColor Green
        write-output "`n$dateTime    INFO    Enabled the 'connAdd' switch to perform an addition to the already existing AWS SaaS Connection Group.`n" | Out-File -FilePath $outfileName -Append
    }
    
}


# creating Paylog for CCS API call
if($connAdd -eq $true){
    [int]$addConns = [int]$saasConnNum + [int]$saasNo

    $payload = @{
    "currentNumOfConnectors" = $saasConnNum; 
    "numberOfConnectors" = $addConns;
    "ConnectionId" = $groupId
    }

    # deploy additional AWS SaaS Connector to current Connection Group
    #$payloadJson = $payload | ConvertTo-Json 
    $payloadJson = ConvertTo-Json -Compress -Depth 99 $payload 
    write-host "`nDeployment of Additional CCS SaaS Connector to already existing SaaS Connection Group API Payload: `n$payloadJson"  
    write-output "`n$dateTime    INFO    Deployment of Additional CCS SaaS Connector to already existing SaaS Connection Group API Payload: `n$payloadJson" | Out-File -FilePath $outfileName -Append  

    $response = Invoke-RestMethod 'https://helios.cohesity.com/v2/mcm/rigelmgmt/rigel-groups' -Method 'PUT' -Headers $headers -Body $payloadJson -ContentType 'application/json'     
    $response | ConvertTo-Json
    Write-host "$response" -ForegroundColor Green 
    write-output "$dateTime    INFO    Response from Deployment of CCS SaaS Connection for AWS API Payload:  API: `n$response" | Out-File -FilePath $outfileName -Append

    if($response){
        Write-host "`nDeployment of Additional CCS SaaS Connector to already existing SaaS Connection Group in AWS Accouut ID $AWSaccount SUCCESSFUL!`n" -ForegroundColor Green
        write-output "`n$dateTime    INFO    Deployment of Additional CCS SaaS Connector to already existing SaaS Connection Group in AWS Accouut ID $AWSaccount SUCCESSFUL!`n"  | Out-File -FilePath $outfileName -Append
    }

    else{
        Write-host "`nDeployment of Additional CCS SaaS Connector to already existing SaaS Connection Group in AWS Accouut ID $AWSaccount UNSUCCESSFUL!`n" -ForegroundColor Red 
        write-output "`n$dateTime    WARN    Deployment of Additional CCS SaaS Connector to already existing SaaS Connection Group in AWS Accouut ID $AWSaccount UNSUCCESSFUL!`n"  | Out-File -FilePath $outfileName -Append
    }
}
else{


# create Payload for CCS API call

if($AWSid){
    Write-Host "`nPreparing CCS AWS SaaS Connection data for Connector Creation..."
    write-output "`n$dateTime    INFO    Preparing CCS AWS SaaS Connection data for Connector Creation..." | Out-File -FilePath $outfileName -Append
    
    $body = @{
        "tenantId" = "$tenantId";
        "connectorType" = "AWS";
        "useCase" = " Ec2Backup";
        "name" = "$AWSid-$AWSregionId-$CCSregionId";
        "numberOfRigels" = $saasNo;
        "regionId" = "$CCSregionId";
        "rigelCloudInfraInfo" = @{
            "awsRigelInfraInfo" = @{
                "accountNumber" = "$AWSid";
                "regionId" = "$AWSregionId";
                "subnetId" = "$subnetId";
                "securityGroupId" = "$securityGroupId";
                "vpcId" = "$vpcId";
                "tags" = @()
                    
            }
        }
    }

    #$body = "{`n    `"tenantId`": `"{{tenantId}}`",`n    `"connectorType`": `"AWS`",`n    `"useCase`": `"Ec2Backup`",`n    `"name`": `"{{accountId}}-{{rigelRegionId}}-{{regionId}}`",`n    `"numberOfRigels`": 1,`n    `"regionId`": `"{{regionId}}`",`n    `"rigelCloudInfraInfo`": {`n        `"awsRigelInfraInfo`": {`n            `"accountNumber`": `"{{accountNumber}}`",`n            `"regionId`": `"{{rigelRegionId}}`",`n            `"subnetId`": `"{{subnetId}}`",`n            `"securityGroupId`": `"{{sgId}}`",`n            `"vpcId`": `"{{vpcId}}`",`n            `"tags`": []`n        }`n    }`n}"

    # {"tenantId":"0012J00002QxadFQAR:b049b48c9f/","connectorType":"AWS","useCase":"Ec2Backup","name":"204166215890-us-east-1-us-east-1","numberOfRigels":1,"regionId":"us-east-1","rigelCloudInfraInfo":{"awsRigelInfraInfo":{"accountNumber":"204166215890","regionId":"us-east-1","subnetId":"subnet-39840b18","securityGroupId":"sg-4d308679","vpcId":"vpc-9a38e5e7","tags":[{"key":"label","value":"value"},{"key":" label","value":"value2"}]}}}

    if($tagsToAdd -gt 0){
        foreach($tagToAdd in $tagsToAdd){
            $tag = $tagToAdd -split "="
            $hashTable = [ordered] @{"key" = $tag[0]; "value" = $tag[1]}
                write-host $hashTable
                $body.rigelCloudInfraInfo.awsRigelInfraInfo.tags += $hashTable; 
            }  
        }

    Write-Host "`nCreating New CCS SaaS Connector for AWS Account ID $AWSaccount...`n" 
    write-output "`n$dateTime    INFO    Creating New CCS SaaS Connector for AWS Account ID $AWSaccount...`n" | Out-File -FilePath $outfileName -Append     

    # prepare body of REST API Call
    write-host "Body Value: `n" $body
    #$bodyJson = $body | ConvertTo-Json 
    $bodyJson = ConvertTo-Json -Compress -Depth 99 $body 
    write-host "`nCreation of New CCS SaaS Connector for AWS API Payload: `n$bodyJson"  
    write-output "`n$dateTime    INFO    Creation of New CCS SaaS Connector for AWS API Payload: `n$bodyJson" | Out-File -FilePath $outfileName -Append  

    Write-Host "`n*****Launching SaaS Connector in your selected subnets. This could take a few minutes.*****`n" 
    write-output "`n$dateTime    INFO    *****Launching SaaS Connector in your selected subnets. This could take a few minutes.*****`n" | Out-File -FilePath $outfileName -Append 


    # create new AWS SaaS Connector
    $response = Invoke-RestMethod 'https://helios.cohesity.com/v2/mcm/rigelmgmt/rigel-groups' -Method 'POST' -Headers $headers -Body $bodyJson -ContentType 'application/json'     
    $response | ConvertTo-Json
    Write-host "$response" -ForegroundColor Green 
    
    write-output "$dateTime    INFO    Response from Creation of New CCS SaaS Connector for AWS: `n$response" | Out-File -FilePath $outfileName -Append

    if($response){
        Write-host "`nCreation of New CCS SaaS Connector for AWS Accouut ID $AWSaccount SUCCESSFUL!`n" -ForegroundColor Green
        write-output "`n$dateTime    INFO    Creation of New CCS SaaS Connector for AWS Accouut ID $AWSaccount SUCCESSFUL!`n"  | Out-File -FilePath $outfileName -Append
    }

    else{
        Write-host "`nCreation of New CCS SaaS Connector for AWS Accouut ID $AWSaccount UNSUCCESSFUL!`n" -ForegroundColor Red 
        write-output "`n$dateTime    WARN    Creation of New CCS SaaS Connector for AWS Accouut ID $AWSaccount UNSUCCESSFUL!`n"  | Out-File -FilePath $outfileName -Append
    }

    # associate new AWS Saas Connection to CCS AWS Source
    $awsInfo = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/dms/tenants/regions/aws-cloud-source?tenantId=$tenantId&destinationRegionId=$AWSregionId&awsAccountNumber=$AWSid-" -Method 'GET' -Headers $headers -ContentType 'application/json'
    $iam_role_arn = $awsInfo.awsIamRoleArn
    $cp_role_arn = $awsInfo.tenantCpRoleArn

    $rigelInfo = Invoke-RestMethod "https://helios.cohesity.com/v2/mcm/data-protect/sources/registrations/$regId" -Method 'GET' -headers $headers
    $connections = $rigelInfo.connections

    Write-Host "`nPreparing CCS AWS SaaS Connector data for association with AWS ID: " $AWSid
    write-output "`n$dateTime    INFO    Preparing CCS AWS SaaS Connector data for association with AWS ID: " $AWSid | Out-File -FilePath $outfileName -Append
    
    $body = @{
        "environment" = "kAWS";
        "awsParams" = @{
            "subscriptionType" = "kAWSCommercial" ;
            "standardParams" = @{
                "authMethodType" = "$AWSid";
                "iamRoleAwsCredentials" = @{
                    "iamRoleArn" = "$iam_role_arn";
                    "cpIamRoleArn" = "$cp_role_arn"

                }
            }
        };
        "connections" = $connections
    }

    # prepare body of REST API Call
    write-host "Body Value: `n" $body
    $bodyJson = ConvertTo-Json -Compress -Depth 99 $body 
    write-host "`nAssociation of New CCS AWS SaaS Connector with AWS Source Payload: `n$bodyJson"  
    write-output "`n$dateTime    INFO    Association of New CCS AWS SaaS Connector with AWS Source Payload: `n$bodyJson" | Out-File -FilePath $outfileName -Append  

    Write-Host "`nAssociating New CCS SaaS Connector with AWS Account ID $AWSaccount...`n" 
    write-output "`n$dateTime    INFO    Associating New CCS SaaS Connector with AWS Account ID $AWSaccount...`n" | Out-File -FilePath $outfileName -Append  

    $response = Invoke-RestMethod '"https://helios.cohesity.com/v2/mcm/data-protect/sources/registrations/$regId"' -Method 'POST' -Headers $headers -Body $bodyJson -ContentType 'application/json'     
    $response | ConvertTo-Json
    Write-host "$response" -ForegroundColor Green 
    
    write-output "$dateTime    INFO    Response from the Association of New CCS AWS SaaS Connector with AWS Source: `n$response" | Out-File -FilePath $outfileName -Append

    if($response){
        Write-host "`nAssociation of New CCS SaaS Connector with AWS Accouut ID $AWSaccount SUCCESSFUL!`n" -ForegroundColor Green
        write-output "`n$dateTime    INFO    Association of New CCS SaaS Connector with AWS Accouut ID $AWSaccount SUCCESSFUL!`n"  | Out-File -FilePath $outfileName -Append
    }

    else{
        Write-host "`nAssociation of New CCS SaaS Connector with AWS Accouut ID $AWSaccount UNSUCCESSFUL!`n" -ForegroundColor Red 
        write-output "`n$dateTime    WARN    Association of New CCS SaaS Connector with AWS Accouut ID $AWSaccount UNSUCCESSFUL!`n"  | Out-File -FilePath $outfileName -Append
    }
}

else {
    write-host "`nNo valid AWS Account ID' provided!`n" -ForegroundColor Yellow
    write-output "`n$dateTime    WARN    No valid AWS Account ID' provided!`n" | Out-File -FilePath $outfileName -Append 
    }
}
