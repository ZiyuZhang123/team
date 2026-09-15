param(
  [ValidateSet("deploy", "create-env")]
  [string]$Mode = "deploy",
  [string]$ModuleName,
  [switch]$NoModulePrompt,
  [string]$ProjectsJson,
  [string]$ProjectsFile,
  [string]$Token
)

$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new()

$script:Token = $Token
$script:ProjectsJson = $ProjectsJson

$script:GetEnvUrl = "http://ee-api.58dns.org/skill/api-yunxiao-ione/envApi/skill/getEnvList"
$script:CreateEnvUrl = "http://ee-api.58dns.org/skill/api-yunxiao-ione/envApi/skill/createEnv"
$script:DeployUrl = "http://ee-api.58dns.org/skill/api-yunxiao-ione/envApi/skill/deploy"
$script:TokenApplyUrl = "https://ee.58corp.com/base2/t/apply/common/addToken"

function Fail {
  param([string]$msg)
  Write-Error $msg
  exit 1
}

function Resolve-Token {
  if (-not $script:Token -and $env:YUNXIAO_SKILL_TOKEN) {
    $script:Token = $env:YUNXIAO_SKILL_TOKEN
  }
  if (-not $script:Token) {
    Write-Host "未检测到 YUNXIAO_SKILL_TOKEN。"
    Write-Host "若不知道 token，请先申请：$script:TokenApplyUrl"
    $script:Token = Read-Host "请输入 token"
  }
  if (-not $script:Token) { Fail "未提供 token。" }
  if (-not $env:YUNXIAO_SKILL_TOKEN) {
    $env:YUNXIAO_SKILL_TOKEN = $script:Token
    try { setx YUNXIAO_SKILL_TOKEN $script:Token | Out-Null } catch { Write-Warning "无法持久化写入用户环境变量，请手动设置。" }
  }
}

function Build-ProjectsJson {
  if ($ProjectsFile -and $ProjectsJson) { Fail "--projects-file 与 --projects-json 不能同时使用。" }
  if ($ProjectsFile) {
    if (-not (Test-Path -LiteralPath $ProjectsFile)) { Fail "projects 文件不存在。" }
    $script:ProjectsJson = Get-Content -LiteralPath $ProjectsFile -Raw
  }
  if (-not $script:ProjectsJson) {
    $root = git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $root) { Fail "当前目录不是 git 仓库。" }
    $remote = git remote get-url origin 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $remote) { Fail "无 origin 远端。" }
    $pathPart = $null
    if ($remote -match "^[^:]+://[^/]+/(.+)$") { $pathPart = $Matches[1] }
    elseif ($remote -match "^[^:]+:(.+)$") { $pathPart = $Matches[1] }
    else { $pathPart = $remote }
    if ($pathPart -and $pathPart.EndsWith(".git")) { $pathPart = $pathPart.Substring(0, $pathPart.Length - 4) }
    $groupName = $null
    $projectName = $null
    if ($pathPart -and $pathPart.Contains("/")) {
      $ls = $pathPart.LastIndexOf("/")
      $groupName = $pathPart.Substring(0, $ls)
      $projectName = $pathPart.Substring($ls + 1)
    }
    if (-not $groupName -or -not $projectName) {
      $groupName = Read-Host "请输入 groupName"
      $projectName = Read-Host "请输入 projectName"
    }
    $branchName = git rev-parse --abbrev-ref HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $branchName -or $branchName -eq "HEAD") { Fail "无法获取当前分支。" }
    $effectiveModule = $ModuleName
    if (-not $effectiveModule -and -not $NoModulePrompt) {
      if (-not [Console]::IsInputRedirected) {
        Write-Host "moduleName 说明：用于父子工程中的「模块」。指定后，环境列表、新建环境、部署三个接口将只针对该模块；不指定则针对工程下全部模块。单工程一般无需指定。"
        $yn = Read-Host "是否指定 moduleName？(y/N)"
        if ($yn -match '^[Yy]$') { $effectiveModule = Read-Host "请输入 moduleName" }
      }
    }
    $row = @{ groupName = $groupName; projectName = $projectName; branchName = $branchName }
    if ($effectiveModule) { $row["moduleName"] = $effectiveModule }
    $obj = @($row)
    $script:ProjectsJson = $obj | ConvertTo-Json -Compress -Depth 5
  }
  if (-not $script:ProjectsJson) { Fail "projects 未设置。" }
  $arr = $script:ProjectsJson | ConvertFrom-Json
  $list = @($arr)
  foreach ($item in $list) {
    $p = $item.PSObject.Properties["moduleName"]
    if ($null -ne $p -and [string]::IsNullOrWhiteSpace([string]$p.Value)) {
      $null = $item.PSObject.Properties.Remove("moduleName")
    }
  }
  $script:ProjectsJson = $list | ConvertTo-Json -Compress -Depth 10
}

function Parse-CreateResult {
  param($Resp)
  if ($Resp.code -ne 0) { throw "创建失败: $($Resp.msg)" }
  $url = [string]$Resp.result
  if ($url -match 'id=(\d+)') { $id = $Matches[1] } else { throw "无法从 result 解析 id" }
  if ($url -match 'dt=(\d+)') { $dt = $Matches[1] } else { throw "无法从 result 解析 dt" }
  return @{ id = $id; dt = $dt }
}

function Test-DeployMsgVipQuota {
  param([string]$Msg)
  if ([string]::IsNullOrWhiteSpace($Msg)) { return $false }
  if ($Msg -match '配额不足') { return $true }
  if (($Msg -match '(?i)vip') -and ($Msg -match '数量')) { return $true }
  if (($Msg -match '配额') -and ($Msg -match '不足')) { return $true }
  return $false
}

function Test-DeployMsgMergeMaster {
  param([string]$Msg)
  if ([string]::IsNullOrWhiteSpace($Msg)) { return $false }
  if ($Msg -match '需要合并\s*master') { return $true }
  if (($Msg -match '(?i)master') -and (($Msg -match '合并') -or ($Msg -match '最新'))) { return $true }
  if (($Msg -match '当前分支') -and ($Msg -match '最新') -and ($Msg -match '不是')) { return $true }
  return $false
}

function Add-VipFlgZeroToProjectsJson {
  $arr = $script:ProjectsJson | ConvertFrom-Json
  $list = @($arr)
  foreach ($item in $list) {
    Add-Member -InputObject $item -NotePropertyName vipFlg -NotePropertyValue 0 -Force
  }
  $script:ProjectsJson = $list | ConvertTo-Json -Compress -Depth 10
}

function Invoke-MergeOriginDefaultAndPush {
  git fetch origin 2>$null
  if ($LASTEXITCODE -ne 0) {
    Write-Host "错误: git fetch origin 失败。"
    return $false
  }
  $ref = $null
  git rev-parse --verify origin/master 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) { $ref = "origin/master" }
  else {
    git rev-parse --verify origin/main 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $ref = "origin/main" }
  }
  if (-not $ref) {
    Write-Host "错误: 未找到 origin/master 或 origin/main。"
    return $false
  }
  git merge -m "merge $ref for yunxiao deploy" $ref
  if ($LASTEXITCODE -ne 0) {
    Write-Host "错误: 合并失败或存在冲突，请手动解决后 push 再重新部署。"
    return $false
  }
  git push
  if ($LASTEXITCODE -ne 0) {
    Write-Host "错误: git push 失败。"
    return $false
  }
  return $true
}

function Open-DeployResultUrl {
  param($Url)
  if ($Url -and ($Url -match '^https?://')) {
    Start-Process $Url | Out-Null
  }
}

function Invoke-DeployCall {
  param([string]$EnvId, [int]$DeployType, [int]$EnvType)
  $vipRetried = $false
  $mergeRetried = $false
  while ($true) {
    $projects = $script:ProjectsJson | ConvertFrom-Json
    $payload = @{
      envId = "$EnvId"
      deployType = $DeployType
      envType = $EnvType
      projects = $projects
    }
    $deployResp = Invoke-RestMethod -Method Post -Uri $script:DeployUrl -Headers @{ token = $script:Token } -ContentType "application/json" -Body ($payload | ConvertTo-Json -Compress -Depth 10)
    $deployResp | ConvertTo-Json -Compress
    if ($deployResp.code -eq 0) {
      Open-DeployResultUrl $deployResp.result
      return
    }
    if ($deployResp.msg) { Write-Host $deployResp.msg }
    Write-Host "部署触发失败（code 非 0）。若 result 为链接将尝试打开以便到平台查看。"
    Open-DeployResultUrl $deployResp.result

    if (-not $vipRetried -and (Test-DeployMsgVipQuota $deployResp.msg)) {
      if (-not [Console]::IsInputRedirected) {
        $yn = Read-Host "检测到可能与 VIP/配额相关。是否不使用 VIP 再次部署？(y/n)"
        if ($yn -match '^[Yy]$') {
          Add-VipFlgZeroToProjectsJson
          $vipRetried = $true
          Write-Host "已为 projects 各工程增加 vipFlg=0，重新调用部署接口…"
          continue
        }
      } else {
        Write-Host "（非交互终端）跳过「不使用 VIP 重试」询问；可手动加 vipFlg:0 后重试。"
      }
    }

    if (-not $mergeRetried -and (Test-DeployMsgMergeMaster $deployResp.msg)) {
      Write-Host "尝试拉取并合并远端 master/main 后 push，然后再次部署…"
      if (Invoke-MergeOriginDefaultAndPush) {
        $mergeRetried = $true
        continue
      }
    }
    break
  }
}

function Invoke-CreateEnvThenDeploy {
  $arr = $script:ProjectsJson | ConvertFrom-Json
  $first = $arr | Select-Object -First 1
  $suggested = "$($first.groupName)_$($first.projectName)_$($first.branchName)"
  $adopt = Read-Host "建议环境名: $suggested 是否采纳？(y/n)"
  if ($adopt -match '^[Yy]$') {
    $envName = $suggested
  } else {
    $envName = Read-Host "请输入环境名"
    if (-not $envName) { $envName = $suggested }
  }
  $dtp = Read-Host "环境类型：1=沙箱，0=测试"
  if ($dtp -notmatch '^(0|1)$') { Fail "请输入 0 或 1。" }
  $projects = $script:ProjectsJson | ConvertFrom-Json
  $createBody = @{
    envName = $envName
    deployType = [int]$dtp
    envType = 0
    projects = $projects
  }
  $createResp = Invoke-RestMethod -Method Post -Uri $script:CreateEnvUrl -Headers @{ token = $script:Token } -ContentType "application/json" -Body ($createBody | ConvertTo-Json -Compress -Depth 10)
  $createResp | ConvertTo-Json -Compress
  if ($createResp.code -ne 0) {
    Write-Host "创建环境失败，请到云效平台手动创建。"
    exit 1
  }
  $parsed = Parse-CreateResult $createResp
  Write-Host "创建成功，正在部署 envId=$($parsed.id) deployType=$($parsed.dt) …"
  Invoke-DeployCall -EnvId $parsed.id -DeployType ([int]$parsed.dt) -EnvType 0
}

Resolve-Token
Build-ProjectsJson

if ($Mode -eq "create-env") {
  Invoke-CreateEnvThenDeploy
  exit 0
}

$envListResp = Invoke-RestMethod -Method Post -Uri $script:GetEnvUrl -Headers @{ token = $script:Token } -ContentType "application/json" -Body $script:ProjectsJson
$envListResp | ConvertTo-Json -Compress
$items = $envListResp.result
if (-not $items -or $items.Count -eq 0) {
  $yn = Read-Host "环境列表为空，是否创建新环境？(y/n)"
  if ($yn -match '^[Yy]$') { Invoke-CreateEnvThenDeploy }
  exit 0
}

Write-Host "可选环境（序号 | name | 类型 | 部署类型）"
for ($i = 0; $i -lt $items.Count; $i++) {
  $it = $items[$i]
  $dtype = if ($it.deployType -eq 1) { "沙箱" } elseif ($it.deployType -eq 0) { "测试" } else { $it.deployType }
  $etype = if ($it.envType -eq 0) { "环境" } else { "构建计划" }
  Write-Host ("{0}. {1} ({2}, {3})" -f ($i + 1), $it.name, $etype, $dtype)
}

$choice = Read-Host "请选择序号（或输入 n 表示没有合适环境）"
if ($choice -match '^[Nn]$') {
  $yn = Read-Host "是否创建新环境？(y/n)"
  if ($yn -match '^[Yy]$') { Invoke-CreateEnvThenDeploy }
  exit 0
}
if (-not ($choice -match '^[0-9]+$')) { Fail "无效序号。" }
$idx = [int]$choice - 1
if ($idx -lt 0 -or $idx -ge $items.Count) { Fail "序号超出范围。" }

$selected = $items[$idx]
Invoke-DeployCall -EnvId $selected.id -DeployType $selected.deployType -EnvType $selected.envType
