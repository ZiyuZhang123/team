---
name: yunxiao-ici-minipro-executor
description: >-
  Triggers Yunxiao mini program pipeline runs, polls status, fetches QR/preview
  results, or lists recent mini program pipelines (flowType=1). Use when the user
  wants mini program pipeline execution, task status, execution results, or to
  pick a pipeline from recent history with or without a streams URL.
---

# yunxiao-ici-minipro-executor

当用户想**触发云效小程序流水线执行**、**查询执行状态**、**获取执行结果（预览/体验二维码等）**，或**从最近执行过的流水线里选择一条再触发**时，使用本 skill。涉及四个 HTTP 接口：**触发（接口 1）**、**状态（接口 2）**、**结果（接口 3）**、**流水线列表（接口 4）**。

## 适用场景

- 触发小程序流水线执行（可带 `version` / `versionDesc`）。
- 根据 `taskId` 查询执行状态。
- 任务结束后获取结果，优先向用户展示 **`resultQrcodes` 中的 `qrcodeUrl`**。
- **未提供 URL**：先调接口 4 列出小程序流水线，表格展示后用户选定 **flowId**，再调接口 1。

## 需要收集的输入

- **触发（接口 1）**：`flowId` 或包含 **`/base2/c/streams/<flowId>`** 的 streams URL（可带查询参数）；可选 `version`、`versionDesc`（若流水线要求，须向用户索取真实值，禁止编造）。
- **状态（接口 2）**：`flowId`、`taskId`（来自接口 1）。
- **结果（接口 3）**：`flowId`、`taskId`；**应先通过接口 2 确认 `status === 2`（已结束）** 再调接口 3。
- **列表（接口 4）**：可选 `limitNum`；**默认 5**（脚本执行 `list` 且**不传** `--limit-num` 即可）。本 skill 内 **`flowType` 固定为 1**（小程序流水线）。
- **`token`**：所有请求均放在 **Header** `token` 中。

## 规则

### Token

1. 优先 **`YUNXIAO_SKILL_TOKEN`**。
2. 若无，可请用户在对话中提供，并通过脚本 **`--token`** 传入。
3. 若仍无 token，**在调用任何接口之前**提示必须提供，并给出申请地址：  
   `https://ee.58corp.com/base2/openapi/skillsToken/page`
4. **`token` 只放在 HTTP Header，不放入 JSON Body**（与部分文档示例可能不一致时以本 skill 为准）。

### URL 与流水线类型

- 小程序流水线 URL 须包含 **`/base2/c/streams/<flowId>`**（可带 `/auto` 及查询参数）。**不包含该形态**的 URL → 说明**不是本 skill 支持的小程序流水线 URL**，不要调用接口 1。
- 接口 4 列表中若无目标流水线，用户仍可**自行提供**符合上述规则的 **URL** 后走接口 1。

### version / versionDesc

- 可选；若流水线或团队要求填写，**必须由用户明确提供**，助手不得猜测或自动填充占位值。

### 状态与结果

- **接口 2**：`status` — `0` 未开始，`1` 执行中，`2` 已结束。
- **接口 3**：建议在 **`status === 2`** 后再调用；结果里用户通常关心 **`resultQrcodes[].qrcodeUrl`**；用户问日志时再提供 **`logUrl`**。

### 列表 limitNum

- **默认 5**：拉取最近小程序流水线列表时，优先执行 `bash scripts/minipro_task_executor.sh list`（**不要**默认加 `--limit-num 10` 等更大值）。
- 仅当用户**明确要求**更多/更少条数时，再使用 `--limit-num <n>`。

### 脚本路径

从本 skill 目录执行相对路径，例如 `scripts/minipro_task_executor.sh`，勿写死绝对路径。

## 命令

### macOS / Linux（在 skill 目录下）

```bash
# 接口 4：最近有执行记录的小程序流水线（flowType=1），limitNum 默认 5
bash scripts/minipro_task_executor.sh list
# 需要更多条时再指定（示例：10 条）
bash scripts/minipro_task_executor.sh list --limit-num 10

# 接口 1：触发（flowId 或 URL）
bash scripts/minipro_task_executor.sh trigger --flow-id 25253 --version 1.0.0 --version-desc "升级说明"
bash scripts/minipro_task_executor.sh trigger --url "https://ee.58corp.com/base2/c/streams/25253/auto?prodId=60&tab=1"

# 接口 2 / 3
bash scripts/minipro_task_executor.sh status --flow-id 25253 --task-id 26
bash scripts/minipro_task_executor.sh result --flow-id 25253 --task-id 26

# 触发后轮询直到结束再拉结果
bash scripts/minipro_task_executor.sh auto --url "https://ee.58corp.com/base2/c/streams/25253/auto?prodId=60&tab=1"
```

### Windows

```bat
.\scripts\minipro_task_executor.cmd list
.\scripts\minipro_task_executor.cmd list --limit-num 10
.\scripts\minipro_task_executor.cmd trigger --flow-id 25253
.\scripts\minipro_task_executor.cmd status --flow-id 25253 --task-id 26
.\scripts\minipro_task_executor.cmd result --flow-id 25253 --task-id 26
.\scripts\minipro_task_executor.cmd auto --url "https://ee.58corp.com/base2/c/streams/25253/auto?prodId=60&tab=1"
```

## Agent 执行逻辑

1. **触发执行**  
   - 用户提供了符合规则的 **URL** → 直接调 **接口 1**。  
   - **未提供 URL** → 先调 **接口 4**（`list` **不传** `--limit-num`，即 **limitNum=5**；用户要更多条再带 `--limit-num`），将结果做成**面向用户的表格**供选择（见下方「流水线列表表格」）；选定后用 **`flowId`** 调 **接口 1**。列表中无目标时，用户仍可发 **URL** 再调接口 1。

2. **查询执行状态** → **接口 2**（`flowId` + `taskId`）。

3. **获取执行结果** → 先 **接口 2** 确认 **`status === 2`**，再 **接口 3**；向用户优先展示 **`resultQrcodes` 的 `qrcodeUrl`**。

## 输出要求

### 流水线列表表格（接口 4）

向用户展示列表时，**至少包含**以下列（从接口字段取值）：

| 建议列名 | 接口字段 | 说明 |
|----------|----------|------|
| flowId | `flowId` | 流水线 id |
| 流水线名称 | `flowName` | |
| 产品 | `prodName` | |
| 平台类型 | `prodOs` | 如 MiniPro 等，**必须展示** |
| 最后构建时间 | `CreateTime` | 接口字段名仍为 `CreateTime`，对用户列名用「最后构建时间」 |

- **不要**在表格中展示 **`prodId`**（内部标识，用户无需看到）。
- 脚本在 macOS/Linux 无 jq 时可能只输出 `respData_JSON`，Agent 解析后仍按上表整理，**不得**把 `prodId` 列给用户。

### 其它输出

- **触发成功**：返回 **`taskId`**、**`flowId`**、接口提示文案（如 `msg`）。
- **状态**：返回数值 **`status`** 及可读标签（未开始 / 执行中 / 已结束）。
- **结果**：优先 **`qrcodeUrl`**；仅当用户要日志或排查时再给 **`logUrl`**。
- **失败**：展示接口 **`errMsg`**；**`respCode !== 0`** 为失败。

详细字段见 [references/api.md](./references/api.md)。
