[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("trigger", "status", "result", "auto", "list")]
    [string]$Action,

    [string]$FlowId,
    [string]$TaskId,
    [string]$Url,
    [string]$Token,
    [string]$Version,
    [string]$VersionDesc,
    [int]$PollInterval = 10,
    [int]$Timeout = 1800,
    [int]$LimitNum = 5
)

$ApiTrigger = "http://ee-api.58dns.org/skill/api-yunxiao-ici/SkillService/miniProAutoRun"
$ApiStatus = "http://ee-api.58dns.org/skill/api-yunxiao-ici/SkillService/miniProAutoRunStatus"
$ApiResult = "http://ee-api.58dns.org/skill/api-yunxiao-ici/SkillService/miniProAutoRunResult"
$ApiFlowList = "http://ee-api.58dns.org/skill/api-yunxiao-ici/SkillService/getFlowList"

function Resolve-FlowId {
    param(
        [string]$ExplicitFlowId,
        [string]$PipelineUrl
    )

    if ($ExplicitFlowId) {
        return $ExplicitFlowId
    }

    if ($PipelineUrl -and $PipelineUrl -match "/base2/c/streams/(\d+)") {
        return $Matches[1]
    }

    if ($PipelineUrl) {
        throw "Unsupported mini program pipeline URL (must contain /base2/c/streams/<flowId>): $PipelineUrl"
    }

    throw "flowId is required. Use --flow-id or --url."
}

function Resolve-Token {
    param([string]$InputToken)

    if ($InputToken) {
        return $InputToken
    }

    if ($env:YUNXIAO_SKILL_TOKEN) {
        return $env:YUNXIAO_SKILL_TOKEN
    }

    $Prompted = Read-Host "YUNXIAO_SKILL_TOKEN not found. Apply for a Yunxiao token at https://ee.58corp.com/base2/openapi/skillsToken/page, then input token"
    if (-not $Prompted) {
        throw "token is required before calling the API. Apply at https://ee.58corp.com/base2/openapi/skillsToken/page"
    }

    return $Prompted
}

function Get-PropertyValue {
    param(
        [object]$Object,
        [string[]]$Names
    )

    foreach ($Name in $Names) {
        $Prop = $Object.PSObject.Properties[$Name]
        if ($Prop) {
            return $Prop.Value
        }
    }

    return $null
}

function Decode-EscapedString {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }

    return [System.Text.RegularExpressions.Regex]::Unescape([string]$Value)
}

function Invoke-MiniProApi {
    param(
        [string]$Endpoint,
        [hashtable]$Body,
        [string]$HeaderToken
    )

    $Headers = @{
        "Content-Type" = "application/json"
        "token" = $HeaderToken
    }

    $JsonBody = $Body | ConvertTo-Json -Compress
    return Invoke-RestMethod -Method Post -Uri $Endpoint -Headers $Headers -Body $JsonBody
}

function Get-RespData {
    param([object]$Response)

    if (-not $Response -or -not $Response.data) {
        throw "Unexpected response: $($Response | ConvertTo-Json -Compress)"
    }

    $Data = $Response.data
    if ($Data -is [string]) {
        $Data = $Data | ConvertFrom-Json
    }

    if ($Data.respCode -ne 0) {
        $ErrMsg = Get-PropertyValue -Object $Data -Names @("errMsg")
        if (-not $ErrMsg) {
            $ErrMsg = $Response | ConvertTo-Json -Compress
        }
        throw $ErrMsg
    }

    return $Data
}

function Get-StatusLabel {
    param([int]$Status)

    switch ($Status) {
        0 { "not_started" }
        1 { "running" }
        2 { "finished" }
        default { "unknown" }
    }
}

function Invoke-FlowListApi {
    param(
        [string]$HeaderToken,
        [int]$Limit
    )

    $Body = @{ flowType = 1; limitNum = $Limit }
    $Response = Invoke-MiniProApi -Endpoint $ApiFlowList -Body $Body -HeaderToken $HeaderToken
    $Data = Get-RespData -Response $Response

    $Rows = $Data.respData
    if ($Rows -is [string]) {
        $Rows = $Rows | ConvertFrom-Json
    }

    if (-not $Rows) {
        $Rows = @()
    }
    elseif ($Rows -isnot [System.Array]) {
        $Rows = @($Rows)
    }

    Write-Output "List succeeded (flowType=1, limitNum=$Limit)."
    Write-Output ""
    # User-facing columns: 不展示 prodId；平台类型 = prodOs
    Write-Output "flowId | 流水线名称 | 产品 | 平台类型 | 最后构建时间"
    Write-Output "------ | ---------- | ---- | -------- | ----------"

    foreach ($Row in $Rows) {
        $Fid = Get-PropertyValue -Object $Row -Names @("flowId")
        $Fname = Get-PropertyValue -Object $Row -Names @("flowName")
        $Os = Get-PropertyValue -Object $Row -Names @("prodOs")
        $Pname = Get-PropertyValue -Object $Row -Names @("prodName")
        $Ct = Get-PropertyValue -Object $Row -Names @("CreateTime")
        Write-Output ("{0} | {1} | {2} | {3} | {4}" -f $Fid, $Fname, $Os, $Pname, $Ct)
    }
}

function Invoke-Trigger {
    param(
        [string]$ResolvedFlowId,
        [string]$HeaderToken,
        [string]$PipelineVersion,
        [string]$PipelineVersionDesc
    )

    $Body = @{ flowId = [int]$ResolvedFlowId }
    if ($PipelineVersion) { $Body.version = $PipelineVersion }
    if ($PipelineVersionDesc) { $Body.versionDesc = $PipelineVersionDesc }

    $Response = Invoke-MiniProApi -Endpoint $ApiTrigger -Body $Body -HeaderToken $HeaderToken
    $Data = Get-RespData -Response $Response
    $RespData = $Data.respData

    $RunTaskId = Get-PropertyValue -Object $RespData -Names @("taskId", "taskId:")
    $RunFlowId = Get-PropertyValue -Object $RespData -Names @("flowId", "flowId:")
    $Message = Get-PropertyValue -Object $RespData -Names @("msg", "msg:")

    [pscustomobject]@{
        FlowId = [string]$RunFlowId
        TaskId = [string]$RunTaskId
        Message = [string]$Message
    }
}

function Show-TriggerResult {
    param([pscustomobject]$TriggerResult)

    Write-Output "Trigger succeeded."
    Write-Output "flowId=$($TriggerResult.FlowId)"
    Write-Output "taskId=$($TriggerResult.TaskId)"
    Write-Output "message=$($TriggerResult.Message)"
}

function Invoke-Status {
    param(
        [string]$ResolvedFlowId,
        [string]$ResolvedTaskId,
        [string]$HeaderToken
    )

    $Body = @{
        flowId = [int]$ResolvedFlowId
        taskId = [int]$ResolvedTaskId
    }

    $Response = Invoke-MiniProApi -Endpoint $ApiStatus -Body $Body -HeaderToken $HeaderToken
    $Data = Get-RespData -Response $Response
    $RespData = $Data.respData

    $Status = [int](Get-PropertyValue -Object $RespData -Names @("status", "status:"))
    $RunTaskId = Get-PropertyValue -Object $RespData -Names @("taskId", "taskId:")
    $RunFlowId = Get-PropertyValue -Object $RespData -Names @("flowId", "flowId:")

    [pscustomobject]@{
        Status = $Status
        FlowId = [string]$RunFlowId
        TaskId = [string]$RunTaskId
    }
}

function Show-Status {
    param([pscustomobject]$StatusInfo)

    Write-Output "Status query succeeded."
    Write-Output "flowId=$($StatusInfo.FlowId)"
    Write-Output "taskId=$($StatusInfo.TaskId)"
    Write-Output "status=$($StatusInfo.Status)"
    Write-Output "statusLabel=$(Get-StatusLabel -Status $StatusInfo.Status)"
}

function Invoke-Result {
    param(
        [string]$ResolvedFlowId,
        [string]$ResolvedTaskId,
        [string]$HeaderToken
    )

    $StatusInfo = Invoke-Status -ResolvedFlowId $ResolvedFlowId -ResolvedTaskId $ResolvedTaskId -HeaderToken $HeaderToken
    if ($StatusInfo.Status -ne 2) {
        throw "Task is not finished yet. Current status=$($StatusInfo.Status) ($(Get-StatusLabel -Status $StatusInfo.Status))."
    }

    $Body = @{
        flowId = [int]$ResolvedFlowId
        taskId = [int]$ResolvedTaskId
    }

    $Response = Invoke-MiniProApi -Endpoint $ApiResult -Body $Body -HeaderToken $HeaderToken
    $Data = Get-RespData -Response $Response
    $RespData = $Data.respData
    $Result = $RespData.result

    $QrCodeUrl = $null
    if ($Result -and $Result.resultQrcodes -and $Result.resultQrcodes.Count -gt 0) {
        $QrCodeUrl = $Result.resultQrcodes[0].qrcodeUrl
    }

    Write-Output "Result query succeeded."
    Write-Output "qrcodeUrl=$QrCodeUrl"

    if ($RespData.logUrl) {
        Write-Output "logUrl=$(Decode-EscapedString -Value $RespData.logUrl)"
    }
    if ($RespData.detailUrl) {
        Write-Output "detailUrl=$(Decode-EscapedString -Value $RespData.detailUrl)"
    }
}

try {
    if (-not $Action) {
        throw "action is required. Use trigger, status, result, auto, or list."
    }

    $ResolvedToken = Resolve-Token -InputToken $Token

    switch ($Action) {
        "list" {
            Invoke-FlowListApi -HeaderToken $ResolvedToken -Limit $LimitNum
        }
        "trigger" {
            $ResolvedFlowId = Resolve-FlowId -ExplicitFlowId $FlowId -PipelineUrl $Url
            $TriggerResult = Invoke-Trigger -ResolvedFlowId $ResolvedFlowId -HeaderToken $ResolvedToken -PipelineVersion $Version -PipelineVersionDesc $VersionDesc
            Show-TriggerResult -TriggerResult $TriggerResult
        }
        "status" {
            $ResolvedFlowId = Resolve-FlowId -ExplicitFlowId $FlowId -PipelineUrl $Url
            if (-not $TaskId) { throw "taskId is required for status." }
            $StatusInfo = Invoke-Status -ResolvedFlowId $ResolvedFlowId -ResolvedTaskId $TaskId -HeaderToken $ResolvedToken
            Show-Status -StatusInfo $StatusInfo
        }
        "result" {
            $ResolvedFlowId = Resolve-FlowId -ExplicitFlowId $FlowId -PipelineUrl $Url
            if (-not $TaskId) { throw "taskId is required for result." }
            Invoke-Result -ResolvedFlowId $ResolvedFlowId -ResolvedTaskId $TaskId -HeaderToken $ResolvedToken
        }
        "auto" {
            $ResolvedFlowId = Resolve-FlowId -ExplicitFlowId $FlowId -PipelineUrl $Url
            $TriggerResult = Invoke-Trigger -ResolvedFlowId $ResolvedFlowId -HeaderToken $ResolvedToken -PipelineVersion $Version -PipelineVersionDesc $VersionDesc
            Show-TriggerResult -TriggerResult $TriggerResult
            $AutoTaskId = $TriggerResult.TaskId
            $Elapsed = 0

            while ($Elapsed -le $Timeout) {
                $StatusInfo = Invoke-Status -ResolvedFlowId $ResolvedFlowId -ResolvedTaskId $AutoTaskId -HeaderToken $ResolvedToken
                Write-Output "Polling status: $($StatusInfo.Status) ($(Get-StatusLabel -Status $StatusInfo.Status)) after ${Elapsed}s"

                if ($StatusInfo.Status -eq 2) {
                    Invoke-Result -ResolvedFlowId $ResolvedFlowId -ResolvedTaskId $AutoTaskId -HeaderToken $ResolvedToken
                    exit 0
                }

                Start-Sleep -Seconds $PollInterval
                $Elapsed += $PollInterval
            }

            throw "Timed out after ${Timeout}s waiting for the task to finish."
        }
    }
}
catch {
    Write-Error $_
    exit 1
}
