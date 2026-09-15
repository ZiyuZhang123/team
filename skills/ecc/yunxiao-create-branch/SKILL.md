---
name: yunxiao-create-branch
description: 通过云效接口创建或同步分支并关联工作项。用户提到“创建分支”“新建分支”“创建云效分支”“创建 iONE 分支”“申请变更”“创建变更”等分支/变更申请相关表述时必须唤起此技能。执行时必须先确认“是否关联工作项”和“是否上线后删除分支”，并严格按顺序执行：解析仓库信息 -> 选择分支模式 ->（若同步当前分支则先 git push）-> 调用 createBranch API。
---

# 云效分支创建

## 概述

按用户意图创建云效分支或同步本地已有分支，并可关联工作项与设置删除策略。必须从本地仓库解析 `groupName` 与 `projectName`，并携带 `token` 调用接口。

## 强约束（不得省略）

- 不得跳过询问：在执行前必须明确得到用户对以下两项的回答：
  - 是否关联工作项（是/否）
  - 上线后是否删除分支（是/否）
- 若用户选择“创建本地已有分支到云效”（`isBranchExist=1`），必须先执行 `git push -u origin <branch>`，推送成功后才能调用创建接口。
- 若任一必填参数缺失（`token/groupName/projectName/branchName/isBranchExist/isBranchDelete/workBaseIds`），禁止调用接口。
- 成功/失败均要把接口原始返回（`code/msg/result`）明确反馈给用户。

## 标准执行顺序（严格按序）

1. 获取认证 token
- 优先读取环境变量 `YUNXIAO_SKILL_TOKEN`。
- 若未设置，先主动 `source ~/.zshrc` 再尝试读取环境变量；仍未获取到则询问用户提供 token。
- 若用户没有 token 或不知道什么是 token，明确告知去 `https://ee.58corp.com/base2/t/apply/common/addToken` 申请。
- 用户提供 token 后，在当前会话内设置 `YUNXIAO_SKILL_TOKEN` 以便后续调用复用。
- 当用户提供 token 时，默认写入全局环境变量（macOS/Linux 追加到 `~/.zshrc`；Windows 使用 `setx` 写入用户环境变量）。

2. 解析当前仓库的 `groupName` 与 `projectName`
- 仅从本地仓库获取（建议解析 `git remote get-url origin`）。
- 解析规则：从远端路径提取最后一级为 `projectName`，其父路径为 `groupName`。
- 若无法解析：
  - 提示用户确认在正确仓库目录且存在 `origin` 远端；
  - 若仍无法解析，要求用户手工提供 `groupName` 与 `projectName` 继续流程。

3. 询问分支类型
- 创建本地已有分支到云效：
  - 使用 `git rev-parse --abbrev-ref HEAD` 获取当前分支名。
  - 赋值 `branchName=<当前分支>`，`isBranchExist=1`。
- 在云效新建全新分支：
  - 让用户提供 `branchName`。
  - 校验分支名不包含特殊字符（仅允许字母、数字、下划线）。
  - 赋值 `branchName=<用户提供>`，`isBranchExist=0`。

4. 必问：是否关联工作项
- 先询问用户是否需要关联工作项；若用户选择“否”，赋值 `workBaseIds=""`。
- 若用户选择“是”，调用工作项列表接口：
  - URL: `http://ee-api.58dns.org/skill/api-yunxiao-iwork/work/getUserWorkItem`
  - Method: `POST`
  - Header：**token 必须放在 Header 中**，键名为 `token`，值为用户 token（不要放在 Body）。
  - 示例：`Header: token: <token>`
  - Body: `{"keyword":""}`（`keyword` 非必填）
- 当工作项列表返回数据不为空时：
  - 默认按接口顺序展示前 20 条供用户选择；
  - 每行至少显示 `viewId` 和 `title`（建议同时显示序号和 `id`）。
- 若用户说没有想要的工作项：
  - 让用户提供检索描述（支持 `id`、`viewId` 或文本）；
  - 使用该关键词再次检索并继续展示供选择。
- 若工作项列表返回为空时：
  - 先询问用户是否需要创建全新的工作项；
  - 若本地存在 `yunxiao-workitem-operate` skill，则直接唤起辅助创建；
  - 若不存在，则尝试从 `http://skill-market.58dns.org/api/v1/download?slug=yunxiao-workitem-operate` 下载；
  - 若下载成功且为 zip 包，解压到本地 skill 所在目录并唤起 skill 创建工作项；
  - 若返回“技能不存在”或下载结果不是可解压文件，视为下载失败，弹出 `https://ee.58corp.com/base2/workspace` 让用户去平台创建。
- 创建流程完成后，询问用户是否已创建完成；完成后再次调用工作项列表接口并展示给用户选择。
- 用户选择完成后，将选中工作项 `id` 以英文逗号拼接赋值给 `workBaseIds`。
- 若所有返回结果均不满足，允许用户直接输入工作项 `id`（多个用英文逗号分隔）并赋值给 `workBaseIds`。

5. 必问：上线完成后是否删除分支
- “是”则 `isBranchDelete=1`，否则 `isBranchDelete=0`。

6. 参数完整性检查
- 必填：`token`、`groupName`、`projectName`、`branchName`、`isBranchExist`、`isBranchDelete`、`workBaseIds`。
- `workBaseIds` 允许为空字符串（表示不关联）。

7. 本地分支同步与检出
- 若 `isBranchExist=1`：先执行 `git push -u origin <branchName>`，确认成功后进入下一步。
- 若 `isBranchExist=0`：跳过 push。

8. 调用创建分支接口（POST JSON）
- URL: `http://ee-api.58dns.org/skill/api-yunxiao-ione/envApi/skill/createBranch`
- Header：**token 必须放在 Header 中**，键名 `token`，值为用户 token。
- 示例：`Header: token: <token>`
- Body:
  ```json
  {
    "groupName":"...",
    "projectName":"...",
    "branchName":"...",
    "workBaseIds":"...",
    "isBranchExist":0,
    "isBranchDelete":0
  }
  ```

9. 结果处理
- 返回 `code=0`：
  - 若 `isBranchExist=0` 且 `result` 为分支名，先执行 `git fetch origin <result>`，再执行 `git checkout -b <result> origin/<result>`；
  - 自动打开分支列表页面：`https://ee.58corp.com/base2/o/branch/list`。
- 返回 `code!=0`：
  - 直接展示 `code/msg/result`，并说明失败原因。

## 对话模板（防遗漏）

执行前统一向用户确认：
- 分支模式：`1 同步当前分支` / `2 新建分支`
- 是否关联工作项：`是/否`
- 上线后是否删除分支：`是/否`

若用户未完整回答，必须追问补齐后再执行。

## 脚本

优先使用脚本完成解析与调用：
- `scripts/create_branch.sh`
- Windows 使用：`scripts/create_branch.ps1`

示例：

使用当前本地分支同步到云效：
```bash
scripts/create_branch.sh --use-current-branch --work-base-ids "123,456" --is-branch-delete 0
```

新建云效分支：
```bash
scripts/create_branch.sh --new-branch --branch-name "feature_login" --work-base-ids "" --is-branch-delete 0
```

Windows PowerShell 示例：
```powershell
scripts\\create_branch.ps1 -NewBranch -BranchName "feature_login" -WorkBaseIds "" -IsBranchDelete 0
```

如需显式传 token：
```bash
scripts/create_branch.sh --use-current-branch --work-base-ids "123" --is-branch-delete 1 --token "<token>"
```
