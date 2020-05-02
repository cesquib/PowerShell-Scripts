$DebugPreference = 'SilentlyContinue' #change to 'Continue' if you want the debug output to display
#Start-Transcript -OutputDirectory $PSScriptRoot
$script:config = @{
    hubitatBaseURL = 'http://10.0.0.84/apps/api' #baseURL for the hubitat Maker API.
    makerToken = '373e3f0e-06cd-45c3-ac13-7b50bb102d2d' #apiToken for the Hubitat Maker API
    MakerAPI = '6' #app ID for the Maker API App created
    UnifiBaseURL = 'https://unifi:8443' # UniFi Controller basee URL
    UnifiUser = 'unifi_service' #UniFi Controller username - recommend a 'read-only' admin user.
    UnifiSite = 'default' #Leave as default if you have a single site that was re-named from default. Otherwise, visit the Controller admin panel and look in the URL for the site for the sitename.  Case-sensitive.
    devicesList = import-csv -Path "$($PSScriptRoot)\devices.csv" #Wehre's the CSV file containing the devices you want to monitor?
    <#CSV File Tempalte
    name,mac,deviceid
    John Smith, 11:22:33:44:55:66, 1
    Jane Doe: 66:55:44:33:22:11, 2
    "DeviceID" in the CSV file is the Device ID assigned to the virtual presence device in the Hubitat.
    #>
    UnifiCred = "`{`"username`":`"changeme-username`",`"password`":`"changeme-password`"`}" #'UniFi credentials'
}

function Get-UnifiSession {
    #gets the initial UniFi controller session stored in -SessionVariable to use in later requests to the API.
    [CmdletBinding()]
    param (

    )
    try {
        Write-Debug "Get-UnifiSession:`$logonReq:$($config.UnifiBaseURL)/api/login -method post -body $($config.UnifiCred) -ContentType application/json; charset=utf-8"
        $logonReq = Invoke-RestMethod -Uri "$($config.UnifiBaseURL)/api/login" -method post -body "$($config.UnifiCred)" -ContentType "application/json; charset=utf-8"  -SessionVariable myWebSession
    } catch {
        #Stop-Transcript
        Write-Error "There was an exception logging into $($config.UnifiBaseURL).`n`nException: $($_.Exception.Message)`n`nDetails from Unifi: $($_.ErrorDetails)" -ErrorAction Stop        
    }
    Write-Debug "Unifi Logged in successfully. $(Get-Date)"
    $outSession = [PSCustomObject]@{
        meta = $logonReq.meta
        data = $logonReq.data
        session = $myWebSession
    }
    $outSession
}

function Get-UnifiStatus {
    #get the status of the device you want to monitor by basically looking at the Status API page and looking for the MAC. 
    [CmdletBinding()]
    param (
        # Parameter help description
        [Parameter(Mandatory=$true)]
        [string]
        $MAC
    )
    $UnifiLogon = $null
    $UnifiLogon = Get-UniFiSession
    if (-not($UnifiLogon.meta.rc -eq "ok")) {
        #Stop-Transcript
        Write-Error "Result from Unifi controller did not equal 'OK'.  RC=$($logon.result.meta.rc)" -ErrorAction Stop
    }
    try {
        Write-Debug "Get-UnifiStatus:`$unifiStatusReq=Invoke-RestMethod:$($Config.UnifiBaseURL)/api/s/$($config.UnifiSite)/stat/sta -WebSession `$logon.Session"
        $unifiStatusReq = $null
        $unifiStatusReq = Invoke-RestMethod -Uri "$($Config.UnifiBaseURL)/api/s/$($config.UnifiSite)/stat/sta" -WebSession $UnifiLogon.Session
    }
    catch {
        #Stop-Transcript
        Write-Error "There was an exception error when calling Get-UnifiStatus from $($Config.UnifiBaseURL) .`n`nException: $($_.Exception.Message)`n`nDetails from Hubitat: $($_.ErrorDetails)" -ErrorAction Stop        
    }

    if([string]::IsNullOrEmpty($unifiStatusReq.data)){
        #Stop-Transcript
        Write-Error "No data returned from UnifiStatusReq in Get-UnifiStatus - are you sure the controller is up and you're on the correct (v)LAN?" -ErrorAction Stop
    }
    
    $macSearch = $unifiStatusReq.data | Where-Object {$_.mac -eq $MAC}
    Write-Debug "`$macSearch = $macSearch"
    if ($macSearch) {
        $unifistatus = 'present'
    } else {
        $unifistatus = 'not present'
    }
    $unifistatus
}

function Get-Presence {
    #get the current presence status on the Hubitat for your device(s) so you can later compare then.
    [CmdletBinding()]
    param (
        # Parameter help description
        [Parameter(Mandatory=$true)]
        [string]
        $deviceID
    )
    try {
        Write-Debug "Get-Presence:Invoke-RestMethod:$($config.hubitatBaseURL)/$($config.MakerAPI)/devices/$deviceID`?access_token=$($config.makerToken)"
        $getPresenceReq = Invoke-RestMethod -Uri "$($config.hubitatBaseURL)/$($config.MakerAPI)/devices/$deviceID`?access_token=$($config.makerToken)"
    }
    catch {
        #Stop-Transcript
        Write-Error "There was an exception calling the Hubitat Maker API using Get-Presence.`n`nException: $($_.Exception.Message)`n`nDetails from Hubitat: $($_.ErrorDetails)" -ErrorAction Stop        
    }
    Write-Debug "Get-Presence success. $(Get-Date)"
    $getPresenceReq.attributes.currentValue
}

function Set-Presence {
    #set the precense on your device(s) within Hubitat
    [CmdletBinding()]
    param (
        # Parameter help description
        [Parameter(Mandatory=$true)]
        [string]
        $deviceID,
        # Parameter help description
        [Parameter(Mandatory=$true)]
        [ValidateSet('not present','present')]
        [string]
        $status
    )
    #'not present' = 'departed'
    #'present' = 'arrived'
    if($status -eq 'not present') {
        $apiStatus = 'departed'
    } elseif ($status -eq 'present'){
        $apiStatus = 'arrived'
    } else {
        #Stop-Transcript
        Write-Error "How in the world did you wind up here with a validateset of 'not present' or 'present' and you put $status" -ErrorAction Stop
    }
    try {
        Write-Debug "Set-Presence:Invoke-RestMethod:$($config.hubitatBaseURL)/$($config.MakerAPI)/devices/$deviceID/$apiStatus`?access_token=$($config.makerToken)"
        Invoke-RestMethod -Uri "$($config.hubitatBaseURL)/$($config.MakerAPI)/devices/$deviceID/$apiStatus`?access_token=$($config.makerToken)"
        
    }
    catch {
        #Stop-Transcript
        Write-Error "There was an exception calling the Hubitat Maker API using Set-Presence.`n`nException: $($_.Exception.Message)`n`nDetails from Hubitat: $($_.ErrorDetails)" -ErrorAction Stop        
    }
    Write-Debug "Get-Presence request success. $(Get-Date)"
    Write-Debug "Confirming presence change..."
    $presenceReq = Get-Presence -deviceID $deviceID
    Write-Debug "`$presenceReq: $presenceReq | `$apiStatus: $apiStatus"
    if($presenceReq -eq $status) {
        
        $result = 'Success'
    }else {
        $result = 'Fail'
    }
    Write-Debug "Set-Presence:`$presenceReq:$presenceReq`:`$status:$status`:`$apiStatus:$apiStatus"
    $result    
}

Write-Debug "*********************************************************************************"
$devices = $config.devicesList
foreach ($device in $devices){
    Write-Debug "Processing:`n`n$($device.name)`n$($device.mac)`n$($device.deviceid)"
    $unifiStatus = Get-UnifiStatus -MAC $device.mac #$unifiStatus.DeviceID or $unifistatus.Status
    $hubitatPresence = Get-Presence -deviceID $device.deviceid
    if($hubitatPresence -ne $unifiStatus) {
        Write-Debug "`$hubitatPresence->'$hubitatPresence' does NOT equal `$UnifiStatus->'$UnifiStatus' so we're going to call Set-Presence"
        $presenceSet = Set-Presence -deviceID $($device.deviceid) -status $unifiStatus
        if($presenceSet -eq 'Fail') {
            #Stop-Transcript
            Write-Error "Setting presence on Hubitat failed for $($device.name)"
        }
    } else {
        Write-Debug "`$hubitatPresence->'$hubitatPresence' EQUALS `$UnifiStatus->'$UnifiStatus' - DO NOTHING"
    }
}
#Stop-Transcript