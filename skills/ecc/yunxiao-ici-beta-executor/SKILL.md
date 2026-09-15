---
name: yunxiao-ici-beta-executor
description: >-
  Triggers Yunxiao standard pipeline builds or package runs (beta / same-city /
  local), or lists recent pipelines for the user to pick. Use when the user
  wants to run a normal (default-type) pipeline build, package-only, or
  “构建/打包”, with or without a streams URL; supports runFlowBeta (trigger)
  and getFlowList (choose pipeline).
---

# yunxiao-ici-beta-executor

当用户想触发云效**普通（默认类型）流水线**的 beta 构建、同城构建、本地版构建或仅打包时，使用本 skill。提供两个后端能力：**触发构建（接口 1）**、**拉取最近有执行记录的流水线列表（接口 2）**。

## 适用场景

- 用户想触发普通流水线构建或打包。
- 用户提到 beta 构建、同城、本地版、打包、构建并打包等。
- 用户提供了受支持的 streams URL，希望直接触发。
- **用户未提供 URL**：先调接口 2 拿到流水线列表，以表格展示 **流水线 id、流水线名称、app 平台、app 名**，供用户选择后再用 **flowId** 调接口 1。
- 接口 2 的列表里没有目标流水线时，用户仍可**自行发 URL**，走接口 1。

## 需要收集的输入

- **触发（接口 1）**：`flowId`，或受支持的 streams URL（路径含 `/base2/c/streams/<flowId>` 或 `/base2/c/streams/<flowId>/auto`，可带查询参数）。
- **列表（接口 2）**：可选 `limitNum`。**与后端接口一致：不传或省略时默认 5**；本仓库脚本 `list` 未带 `--limit-num` 时也会发 `limitNum: 5`。`flowType` 在本 skill 内**固定为 4**（默认类型流水线）。
- **`token`**：云效访问 skill 的 token（与 OA 对应）；**所有 HTTP 调用**均放在 **Header** `token` 中。

## 规则

### Token

1. 优先从环境变量 **`YUNXIAO_SKILL_TOKEN`** 读取。
2. 若无，可请用户在**对话中**提供 token，再通过脚本 `--token` 传入。
3. 若仍没有 token，**在调用任何接口之前**须明确提示：必须提供 token，并给出申请地址：  
   `https://ee.58corp.com/base2/openapi/skillsToken/page`
4. **`token` 只放在 HTTP Header `token` 中**，请求 Body 中不传 token（与接口文档中部分示例可能不一致时，以本 skill 为准）。

### URL 与流水线类型

- 若 URL 含 **`/base2/c/release/canals/`**：不支持正式发布流水线，**不要调接口**，向用户说明原因。
- 若 URL 含 **`/base2/c/streams/operation-lib`**：不支持组件流水线，**不要调接口**，向用户说明原因。
- 支持的 URL 形态示例：`/base2/c/streams/<flowId>`、`/base2/c/streams/<flowId>/auto`，可继续带 `?prodId=...&tab=...` 等查询参数；完整 URL 的域名以用户给出的为准（文档示例可用 `https://ee.58corp.com/...`）。
- 接口 1 会复用流水线上次构建保存的参数；若流水线有多个构建步骤，会一并触发。

### 脚本调用方式

从本 skill 目录执行，使用**相对路径**（勿写死绝对安装路径）：

- macOS / Linux：`scripts/beta_executor.sh`
- Windows：`scripts\beta_executor.cmd`（内部调用 PowerShell）

## 命令

### macOS 或 Linux（在 skill 目录下）

```bash
# 接口 1：按 flowId 或 URL 触发构建/打包
bash scripts/beta_executor.sh trigger --flow-id 25249
bash scripts/beta_executor.sh trigger --url "https://ee.58corp.com/base2/c/streams/25253/auto?prodId=60&tab=1"

# 接口 2：最近有执行记录的流水线列表（flowType 固定 4；limitNum 默认 5，与接口一致）
bash scripts/beta_executor.sh list
bash scripts/beta_executor.sh list --limit-num 10
```

### Windows（在 skill 目录下）

```bat
.\scripts\beta_executor.cmd trigger --flow-id 25249
.\scripts\beta_executor.cmd trigger --url "https://ee.58corp.com/base2/c/streams/25253/auto?prodId=60&tab=1"
.\scripts\beta_executor.cmd list
.\scripts\beta_executor.cmd list --limit-num 10
```

PowerShell 下调用 `.cmd` 时请保留 `.\` 前缀。

## Agent 执行逻辑（与修改前相比：增加接口 2）

1. **用户发了受支持的 URL**  
   直接调 **接口 1**（`trigger --url` 或解析出 `flowId` 后 `trigger --flow-id`）。

2. **用户想触发构建/打包但未提供 URL**  
   - 先确保 token 可用（环境变量、或用户对话提供、`--token`）。  
   - 调 **接口 2**：优先执行 **`bash scripts/beta_executor.sh list`**（**不传 `--limit-num`**，即 **`limitNum` 默认 5**，与 `getFlowList` 接口约定一致）。仅当用户明确要求更多/更少条时再传 `--limit-num <n>`。  
   - 将返回中 `respData` 数组里的 **`flowId`、`flowName`、`prodOs`、`prodName`** 与时间（**`CreateTime`**，对用户列名为 **最后构建时间**）整理成**表格**展示，请用户选一条。  
   - 用户选定后，用对应 **`flowId`** 调 **接口 1**。

3. **列表中没有目标流水线**  
   告知用户可改用 **streams URL** 触发；用户给出 URL 后走接口 1。

## 输出要求

### 流水线列表表格（接口 2）

向用户展示列表时，时间列建议列名为 **最后构建时间**（取值接口字段 **`CreateTime`**），不要用「最近记录时间」。

- **接口 1 成功**：向用户展示接口返回的 **`respData`** 文案（成功提示等）。  
- **接口 1 失败**：展示 **`errMsg`**。  
- **接口 2 成功**：脚本会输出表格（Windows）或可解析的单行 JSON（macOS/Linux，见脚本说明）；Agent 应用表格字段向用户展示；若需从 JSON 转表，按 `references/api.md` 中字段含义展示，**时间列对用户用「最后构建时间」**。  
- **接口 2 失败**：展示 **`errMsg`**。  
- **`respCode`：0 为成功，非 0 为失败**（字段名以 `respCode` 为准）。  
- 不支持的 URL 须在调用 API **之前**说明原因。

接口 URL、入参、返回字段详见 [references/api.md](./references/api.md)。
