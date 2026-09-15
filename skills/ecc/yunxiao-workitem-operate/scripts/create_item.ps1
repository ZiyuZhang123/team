﻿# scripts/create_item.ps1
<#
.SYNOPSIS
    This script calls the API to create a work item.
.DESCRIPTION
    This script handles argument parsing, token acquisition (from argument, environment variable, or user prompt),
    and calls the iWork API to create a work item.
.PARAMETER Title
    The title of the work item.
.PARAMETER Content
    The detailed content of the work item.
.PARAMETER Type
    The type of the work item (2:Requirement, 3:Bug, 4:Task).
.PARAMETER Token
    The authentication token. If not provided, it will be read from the YUNXIAO_SKILL_TOKEN environment variable or prompted for.
.EXAMPLE
    ./create_item.ps1 -Title "New Feature" -Content "Details about the new feature." -Type 2
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Title,

    [Parameter(Mandatory=$true)]
    [string]$Content,

    [Parameter(Mandatory=$false)]
    [ValidateSet('2', '3', '4')]
    [string]$Type,

    [Parameter(Mandatory=$false)]
    [string]$Token
)

# Constants
$ApiUrl = "http://ee-api.58dns.org/skill/api-yunxiao-iwork/work/saveWorkItem"
$Version = "1.0.8"

# Handle the token
if ([string]::IsNullOrEmpty($Token)) {
    if ($env:YUNXIAO_SKILL_TOKEN) {
        $Token = $env:YUNXIAO_SKILL_TOKEN
        Write-Host "在环境变量中找到令牌（token）。"
    } else {
        Write-Host "在环境变量中未找到令牌, 将提示输入..."
        $Token = Read-Host "请输入您的令牌（token）"
    }
}
if ([string]::IsNullOrEmpty($Token)) {
    Write-Error "错误: 令牌（token）是必需的。"
    exit 1
}

# Handle the type
if ([string]::IsNullOrEmpty($Type)) {
    Write-Host "错误: -Type 无效或缺失。请输入一个有效的类型。"
    $options = @{
        '1' = '需求'
        '2' = '缺陷/bug'
        '3' = '任务'
    }
    while ($true) {
        $options.GetEnumerator() | ForEach-Object { Write-Host "$($_.Name). $($_.Value)" }
        $choice = Read-Host "请选择工作项的类型 (1-3)"
        if ($choice -in '1', '2', '3') {
            # Map choice back to API type value
            $typeMap = @{'1' = '2'; '2' = '3'; '3' = '4'}
            $Type = $typeMap[$choice]
            break
        } else {
            Write-Host "无效选项。请重试。"
        }
    }
}


# Construct JSON payload
# Using an ordered dictionary to maintain property order, although not strictly necessary for JSON
$payloadObject = [ordered]@{
    title = $Title
    content = $Content
    type = [int]$Type
    version = $Version
} 
$payloadJson = $payloadObject | ConvertTo-Json -Compress

# Construct headers
$headers = @{
    "token" = $Token
}

Write-Host "JSON 数据: $payloadJson"

# Make the API call
try {
    Write-Host "正在调用 API..."
    $response = Invoke-RestMethod -Uri $ApiUrl -Method Post -Headers $headers -Body $payloadJson -ContentType "application/json; charset=utf-8"
    
    Write-Host "API 响应: $($response | ConvertTo-Json -Depth 3)"

    if ($response.code -eq 200) {
        Write-Host "✅ 操作成功！"
        Write-Host "工作项草稿已保存至云效。"
        Write-Host "请务必点击下面的链接，在云效平台完成最终创建："
        Write-Host $response.data
    } else {
        Write-Error "创建工作项失败。API 响应: $($response | ConvertTo-Json -Depth 3)"
        exit 1
    }
} catch {
    Write-Error "错误: 调用 API 失败。"
    Write-Error $_.Exception.ToString()
    exit 1
}
