$DebugPreference = 'SilentlyContinue'
#Start-Transcript -OutputDirectory $PSScriptRoot
$script:config = @{
    hubitatBaseURL = 'http://10.0.0.84/apps/api' #baseURL for the hubitat Maker API.
    makerToken = '373e3f0e-06cd-45c3-ac13-7b50bb102d2d' #apiToken for the 
    MakerAPI = '6' #app ID for the Maker API
    UnifiBaseURL = 'https://unifi:8443'
    UnifiUser = 'unifi_service'
    UnifiSite = 'default'
    devicesList = import-csv -Path "$($PSScriptRoot)\devices.csv"
    UnifiCred = "`{`"username`":`"unifi_service`",`"password`":`"seaquake-justify-control-gully-macaque`"`}"
}

#$devices = Import-Csv -Path "$($config.devicesList)"
#start-sleep -seconds 60

function Get-UnifiSession {
    
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