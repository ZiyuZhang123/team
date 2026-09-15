param(
  [switch]$UseCurrentBranch,
  [switch]$NewBranch,
  [string]$BranchName,
  [string]$WorkBaseIds,
  [ValidateSet("0","1")] [string]$IsBranchDelete,
  [string]$Token
)

$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new()

$CurrentSkillDir = Split-Path -Parent $PSScriptRoot
$SkillsRootDir = Split-Path -Parent $CurrentSkillDir
$WorkItemsUrl = "http://ee-api.58dns.org/skill/api-yunxiao-iwork/work/getUserWorkItem"
$CreateItemSkillDir = Join-Path $SkillsRootDir "yunxiao-workitem-operate"
$CreateItemScriptPs1 = Join-Path $CreateItemSkillDir "scripts/create_item.ps1"
$CreateItemScriptSh = Join-Path $CreateItemSkillDir "scripts/create_item.sh"
$CreateItemDownloadUrl = "http://skill-market.58dns.org/api/v1/download?slug=yunxiao-workitem-operate"
$WorkspaceUrl = "https://ee.58corp.com/base2/workspace"
$TokenApplyUrl = "https://ee.58corp.com/base2/t/apply/common/addToken"

function Fail($msg) {
  Write-Error $msg
  exit 1
}

function Ensure-Token {
  if ($script:Token) { return }

  if ($env:YUNXIAO_SKILL_TOKEN) {
    $script:Token = $env:YUNXIAO_SKILL_TOKEN
  } else {
    Write-Host "未检测到 YUNXIAO_SKILL_TOKEN。"
    Write-Host "如果你没有 token 或不知道什么是 token，请先到以下链接申请："
    Write-Host $TokenApplyUrl
    $script:Token = Read-Host "请输入 token（留空表示暂不处理）"
  }

  if (-not $script:Token) {
    Fail "未提供 token。请先前往 $TokenApplyUrl 申请后重试。"
  }

  $env:YUNXIAO_SKILL_TOKEN = $script:Token
  try {
    setx YUNXIAO_SKILL_TOKEN $script:Token | Out-Null
  } catch {
    Write-Warning "无法持久化写入用户环境变量，请手动设置。"
  }
}

function Search-WorkItems([string]$Keyword) {
  Ensure-Token
  $body = @{ keyword = $Keyword } | ConvertTo-Json -Compress
  return Invoke-RestMethod -Method Post -Uri $WorkItemsUrl -Headers @{ token = $script:Token } -ContentType "application/json" -Body $body
}

function Get-WorkItemRows($Response) {
  $items = $null
  if ($Response -and $Response.data) {
    if ($Response.data.data) { $items = $Response.data.data }
    elseif ($Response.data.list) { $items = $Response.data.list }
    elseif ($Response.data.items) { $items = $Response.data.items }
    elseif ($Response.data.result) { $items = $Response.data.result }
  } elseif ($Response -and $Response.result) {
    $items = $Response.result
  }

  if (-not $items) { return @() }

  $rows = @()
  $index = 1
  foreach ($item in $items) {
    $rows += [pscustomobject]@{
      Index = $index
      Id = if ($item.id) { "$($item.id)" } elseif ($item.workItemId) { "$($item.workItemId)" } else { "" }
      ViewId = if ($item.viewId) { "$($item.viewId)" } elseif ($item.view_id) { "$($item.view_id)" } else { "" }
      Title = if ($item.title) { "$($item.title)" } elseif ($item.name) { "$($item.name)" } else { "" }
    }
    $index++
  }
  return $rows
}

function Download-CreateItemSkill {
  if (Test-Path $CreateItemSkillDir) { return $true }

  $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("yunxiao-workitem-operate-" + [guid]::NewGuid().ToString("N"))
  $zipFile = Join-Path $tmpDir "yunxiao-workitem-operate.zip"
  New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

  try {
    Invoke-WebRequest -Uri $CreateItemDownloadUrl -OutFile $zipFile | Out-Null
    Expand-Archive -Path $zipFile -DestinationPath $tmpDir -Force
    $sourceDir = Join-Path $tmpDir "yunxiao-workitem-operate"
    if (-not (Test-Path $sourceDir)) {
      $sourceDir = Get-ChildItem -Path $tmpDir -Directory -Recurse | Where-Object { $_.Name -eq "yunxiao-workitem-operate" } | Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $sourceDir) { return $false }
    New-Item -ItemType Directory -Path $SkillsRootDir -Force | Out-Null
    Copy-Item -Path $sourceDir -Destination $SkillsRootDir -Recurse -Force
    return (Test-Path $CreateItemSkillDir)
  } catch {
    return $false
  }
}

function Create-NewWorkItem {
  if (-not (Test-Path $CreateItemSkillDir)) {
    Write-Host "本地未安装 yunxiao-workitem-operate，尝试下载安装。"
    if (-not (Download-CreateItemSkill)) {
      Write-Host "下载 yunxiao-workitem-operate 失败，请到平台手工创建工作项：$WorkspaceUrl"
      Start-Process $WorkspaceUrl | Out-Null
      return $false
    }
  }

  Ensure-Token
  $title = Read-Host "请输入工作项标题"
  $content = Read-Host "请输入工作项描述"
  $type = Read-Host "请输入工作项类型（2=需求, 3=缺陷/bug, 4=任务）"

  if (Test-Path $CreateItemScriptPs1) {
    & $CreateItemScriptPs1 -title $title -content $content -type $type -token $script:Token
    return ($LASTEXITCODE -eq 0)
  }

  if (Test-Path $CreateItemScriptSh -and (Get-Command bash -ErrorAction SilentlyContinue)) {
    & bash $CreateItemScriptSh --title $title --content $content --type $type --token $script:Token
    return ($LASTEXITCODE -eq 0)
  }

  Start-Process $WorkspaceUrl | Out-Null
  return $false
}

function Collect-WorkBaseIds {
  while ($true) {
    $keyword = Read-Host "请输入工作项关键词（可为空，也可输入 id、viewId 或描述）"
    try {
      $response = Search-WorkItems $keyword
    } catch {
      Fail "获取工作项列表失败：$($_.Exception.Message)"
    }

    $rows = Get-WorkItemRows $response
    if (-not $rows -or $rows.Count -eq 0) {
      Write-Host "未找到工作项。"
      $createItem = Read-Host "是否需要帮你创建一个新的工作项？(y/n)"
      if ($createItem -match '^[Yy]$') {
        [void](Create-NewWorkItem)
        $created = Read-Host "是否已创建完成工作项？(y/n)"
        if ($created -match '^[Yy]$') { continue }
      }
      return (Read-Host "请输入 workBaseIds（逗号分隔，留空表示不关联）")
    }

    Write-Host "工作项列表："
    foreach ($row in $rows) {
      Write-Host ("{0}. {1}`t{2}" -f $row.Index, $row.ViewId, $row.Title)
    }

    $choice = Read-Host "请输入要关联的序号（可多个，用逗号分隔；无匹配请输入 n）"
    if ($choice -match '^[Nn]$') { continue }

    $ids = @()
    foreach ($idx in ($choice -split ',')) {
      $trimmed = $idx.Trim()
      if ($trimmed -match '^[0-9]+$') {
        $selected = $rows | Where-Object { $_.Index -eq [int]$trimmed } | Select-Object -First 1
        if ($selected -and $selected.Id) { $ids += $selected.Id }
      }
    }

    if ($ids.Count -gt 0) {
      return ($ids -join ",")
    }

    return (Read-Host "未选择到有效工作项，请直接输入 workBaseIds（逗号分隔，留空表示不关联）")
  }
}

if (-not $UseCurrentBranch -and -not $NewBranch) {
  Fail "必须指定 -UseCurrentBranch 或 -NewBranch。"
}

if (-not $PSBoundParameters.ContainsKey("WorkBaseIds")) {
  $associate = Read-Host "是否关联工作项？(y/n)"
  if ($associate -match '^[Yy]$') {
    $WorkBaseIds = Collect-WorkBaseIds
  } else {
    $WorkBaseIds = ""
  }
}

if (-not $PSBoundParameters.ContainsKey("IsBranchDelete")) {
  Fail "isBranchDelete 必填，且只能为 0 或 1。"
}

Ensure-Token

$root = git rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0 -or -not $root) {
  Fail "当前目录不是 git 仓库。"
}

$remote = git remote get-url origin 2>$null
if ($LASTEXITCODE -ne 0 -or -not $remote) {
  Fail "找不到 origin 远端，无法解析 groupName/projectName。"
}

$pathPart = $null
if ($remote -match "://") {
  if ($remote -match "^[^:]+://[^/]+/(.+)$") { $pathPart = $Matches[1] }
} elseif ($remote -match "^[^:]+:(.+)$") {
  $pathPart = $Matches[1]
} else {
  $pathPart = $remote
}

if ($pathPart -and $pathPart.EndsWith(".git")) {
  $pathPart = $pathPart.Substring(0, $pathPart.Length - 4)
}

$groupName = $null
$projectName = $null
if ($pathPart -and $pathPart.Contains("/")) {
  $lastSlash = $pathPart.LastIndexOf("/")
  $groupName = $pathPart.Substring(0, $lastSlash)
  $projectName = $pathPart.Substring($lastSlash + 1)
}

if (-not $groupName -or -not $projectName) {
  Write-Warning "无法从远端解析 groupName/projectName，请手工输入。"
  $groupName = Read-Host "请输入 groupName"
  $projectName = Read-Host "请输入 projectName"
}

if (-not $groupName -or -not $projectName) {
  Fail "groupName/projectName 必填。"
}

if ($UseCurrentBranch) {
  $branchName = git rev-parse --abbrev-ref HEAD 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $branchName -or $branchName -eq "HEAD") {
    Fail "无法获取当前分支名（可能处于 detached HEAD）。"
  }
  git push -u origin $branchName | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Fail "推送远端失败。"
  }
  $isBranchExist = 1
} else {
  if (-not $BranchName) {
    Fail "新建分支时必须提供 -BranchName。"
  }
  if ($BranchName -notmatch "^[A-Za-z0-9_]+$") {
    Fail "分支名不能包含特殊字符（仅允许字母、数字、下划线）。"
  }
  $branchName = $BranchName
  $isBranchExist = 0
}

$apiUrl = "http://ee-api.58dns.org/skill/api-yunxiao-ione/envApi/skill/createBranch"
$payload = @{
  groupName = $groupName
  projectName = $projectName
  branchName = $branchName
  workBaseIds = "$WorkBaseIds"
  isBranchExist = $isBranchExist
  isBranchDelete = [int]$IsBranchDelete
}

$response = Invoke-RestMethod -Method Post -Uri $apiUrl -Headers @{ token = $Token } -ContentType "application/json" -Body ($payload | ConvertTo-Json -Compress)
$response | ConvertTo-Json -Compress

if ($NewBranch -and $response -and $response.code -eq 0 -and $response.result) {
  git fetch origin $response.result | Out-Null
  git checkout -b $response.result "origin/$($response.result)" | Out-Null

  if ($LASTEXITCODE -ne 0) {
    Fail "本地切换分支失败。"
  }
}

if ($response -and $response.code -eq 0) {
  Start-Process "https://ee.58corp.com/base2/o/branch/list" | Out-Null
}
