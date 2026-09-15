# 云效小程序流水线 Skill API（yunxiao-ici-minipro-executor）

## 通用约定

- 请求方式：`POST`
- Header：`Content-Type: application/json`
- Header：`token: <云效 skill token>`（**必填**；本仓库脚本将 token **只放在 Header**，**不**写入 Body）
- 成功时业务数据在响应的 `data` 中；部分响应里 `data` 可能是**字符串形式的 JSON**，需再解析
- 业务对象内：**`respCode === 0` 为成功**，非 0 为失败
- 字段名以 **`respCode`** 为准（勿与 `repCode` 混淆）
- 部分历史返回里键名可能带冒号（如 `taskId:`），脚本会兼容解析

---

## 接口 1：触发执行（miniProAutoRun）

**URL**：`http://ee-api.58dns.org/skill/api-yunxiao-ici/SkillService/miniProAutoRun`

**用途**：触发小程序流水线执行。

### 请求 Body（JSON，不含 token）

```json
{
  "flowId": 12345,
  "version": "1.0.0",
  "versionDesc": "升级了xxx功能"
}
```

| 字段         | 类型   | 必填 | 说明 |
|--------------|--------|------|------|
| flowId       | int    | 是   | 流水线 id。URL 中含 `/base2/c/streams/<flowId>`（可带 `/auto` 及查询参数）时，解析出的数字即 flowId。 |
| version      | string | 否   | 小程序发布版本号 |
| versionDesc  | string | 否   | 小程序发布版本描述 |

**URL 规则**：须为小程序流水线形态，包含 **`/base2/c/streams/<flowId>`**；否则不是本 skill 支持的小程序流水线 URL，**不要调用**。

### 响应 `respData`（成功时）

- **taskId**：任务 id，接口 2、3 使用  
- **msg**：提交结果说明；失败时也可能在业务错误里体现  
- **flowId**：与入参一致  

---

## 接口 2：执行状态（miniProAutoRunStatus）

**URL**：`http://ee-api.58dns.org/skill/api-yunxiao-ici/SkillService/miniProAutoRunStatus`

**用途**：根据 **接口 1** 返回的 **taskId** 查询执行状态。

### 请求 Body

```json
{
  "flowId": 12345,
  "taskId": 26
}
```

### `respData` 字段

| 字段    | 说明 |
|---------|------|
| status  | `0` 未开始，`1` 执行中，`2` 已结束 |
| taskId  | 同接口 1 |
| flowId  | 同接口 1 |

---

## 接口 3：执行结果（miniProAutoRunResult）

**URL**：`http://ee-api.58dns.org/skill/api-yunxiao-ici/SkillService/miniProAutoRunResult`

**用途**：任务结束后获取执行结果（预览/体验二维码等）。

**依赖**：建议先通过 **接口 2** 确认 **`status === 2`** 再调用。

### 请求 Body

```json
{
  "flowId": 12345,
  "taskId": 26
}
```

### `respData` 关键字段

| 路径 | 说明 |
|------|------|
| `result.resultQrcodes[].qrcodeUrl` | **预览版或体验版二维码**，用户最关心，可直接展示 URL |
| `logUrl` | 执行日志；用户问日志时再提供 |

---

## 接口 4：最近有执行记录的流水线列表（getFlowList）

**URL**：`http://ee-api.58dns.org/skill/api-yunxiao-ici/SkillService/getFlowList`

**用途**：获取用户最近有执行记录的流水线，供选择 **flowId** 后调用接口 1。

### 请求 Body（JSON，不含 token）

```json
{
  "flowType": 1,
  "limitNum": 5
}
```

| 字段      | 类型 | 必填 | 说明 |
|-----------|------|------|------|
| flowType  | int  | 是   | 本 skill **固定为 1**（小程序类型流水线） |
| limitNum  | int  | 否   | 返回条数，默认 **5** |

### `respData` 数组元素

| 字段        | 说明 |
|-------------|------|
| prodOs      | 平台（如 Minipro） |
| CreateTime  | 该流水线最后一次构建时间；**对用户展示列表时列名用「最后构建时间」**（不要用「最近记录时间」） |
| prodName    | app 名 |
| prodId      | app id（**Agent 向用户展示列表时不要出现在表格中**） |
| flowId      | **流水线 id**，对应接口 1 的 `flowId` |
| flowName    | 流水线名称 |

向用户整理表格时：**必须**包含 **平台类型**（取 `prodOs`）；**不要**展示 `prodId`。
