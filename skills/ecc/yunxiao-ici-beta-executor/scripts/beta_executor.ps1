[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("trigger", "list")]
    [string]$Action,

    [string]$FlowId,
    [string]$Url,
    [string]$Token,
    [int]$LimitNum = 5
)

$ApiTrigger = "http://ee-api.58dns.org/skill/api-yunxiao-ici/SkillService/runFlowBeta"
$ApiFlowList = "http://ee-api.58dns.org/skill/api-yunxiao-ici/SkillService/getFlowList"

function Resolve-FlowId {
    param(
        [string]$ExplicitFlowId,
        [string]$PipelineUrl
    )

    if ($ExplicitFlowId) {
        return $ExplicitFlowId
    }

    if ($PipelineUrl -match "/base2/c/release/canals/") {
        throw "Formal release pipelines are not supported by this skill."
    }

    if ($PipelineUrl -match "/base2/c/streams/operation-lib") {
        throw "Component pipelines are not supported by this skill."
    }

    if ($PipelineUrl -and $PipelineUrl -match "/base2/c/streams/(\d+)(/auto)?") {
        return $Matches[1]
    }

    if ($PipelineUrl) {
        throw "Unsupported standard pipeline URL: $PipelineUrl"
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

function Decode-EscapedString {
    param([object]$Value)

    if ($null -eq $Value) {
        return $null
    }

    return [System.Text.RegularExpressions.Regex]::Unescape([string]$Value)
}

function Invoke-BetaApi {
    param(
        [string]$ResolvedFlowId,
        [string]$HeaderToken
    )

    $Headers = @{
        "Content-Type" = "application/json"
        "token" = $HeaderToken
    }

    $Body = @{ flowId = [int]$ResolvedFlowId } | ConvertTo-Json -Compress
    $Response = Invoke-RestMethod -Method Post -Uri $ApiTrigger -Headers $Headers -Body $Body
    $Data = Get-RespData -Response $Response
    $Message = Decode-EscapedString -Value (Get-PropertyValue -Object $Data -Names @("respData"))

    Write-Output "Trigger succeeded."
    Write-Output "flowId=$ResolvedFlowId"
    Write-Output "message=$Message"
}

function Invoke-FlowListApi {
    param(
        [string]$HeaderToken,
        [int]$Limit
    )

    $Headers = @{
        "Content-Type" = "application/json"
        "token" = $HeaderToken
    }

    $Body = @{ flowType = 4; limitNum = $Limit } | ConvertTo-Json -Compress
    $Response = Invoke-RestMethod -Method Post -Uri $ApiFlowList -Headers $Headers -Body $Body
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

    Write-Output "List succeeded (flowType=4, limitNum=$Limit)."
    Write-Output ""
    # 与 SKILL / minipro 一致：对用户不展示 prodId；平台 = prodOs
    Write-Output "flowId | 流水线名称 | 产品 | 平台 | 最后构建时间"
    Write-Output "------ | ---------- | ---- | ---- | ----------"

    foreach ($Row in $Rows) {
        $Fid = Get-PropertyValue -Object $Row -Names @("flowId")
        $Fname = Get-PropertyValue -Object $Row -Names @("flowName")
        $Os = Get-PropertyValue -Object $Row -Names @("prodOs")
        $Pname = Get-PropertyValue -Object $Row -Names @("prodName")
        $Ct = Get-PropertyValue -Object $Row -Names @("CreateTime")
        Write-Output ("{0} | {1} | {2} | {3} | {4}" -f $Fid, $Fname, $Os, $Pname, $Ct)
    }
}

try {
    if (-not $Action) {
        throw "action is required. Use trigger or list."
    }

    $ResolvedToken = Resolve-Token -InputToken $Token

    switch ($Action) {
        "trigger" {
            $ResolvedFlowId = Resolve-FlowId -ExplicitFlowId $FlowId -PipelineUrl $Url
            Invoke-BetaApi -ResolvedFlowId $ResolvedFlowId -HeaderToken $ResolvedToken
        }
        "list" {
            Invoke-FlowListApi -HeaderToken $ResolvedToken -Limit $LimitNum
        }
    }
}
catch {
    Write-Error $_
    exit 1
}
