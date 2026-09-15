# 云效普通流水线 Skill API

## 通用约定

- 请求方式：`POST`
- Header：`Content-Type: application/json`
- Header：`token: <云效 skill token>`（**必填**；本仓库脚本将 token 只放在 Header，**不**放入 Body）
- 成功时业务数据在响应的 `data` 中；部分响应里 `data` 可能是**字符串形式的 JSON**，需再解析一层
- 业务对象内：**`respCode === 0` 表示成功**，非 0 表示失败
- 字段名以 **`respCode`** 为准（勿与 `repCode` 混淆）

---

## 接口 1：触发构建 / 打包（runFlowBeta）

**URL**：`http://ee-api.58dns.org/skill/api-yunxiao-ici/SkillService/runFlowBeta`

**用途**：触发流水线中的 beta 构建、同城构建或本地版构建；若流水线中有多个构建步骤会同时触发；**默认复用该流水线上次构建参数**。

### 请求 Body（JSON）

```json
{
  "flowId": 25249
}
```

| 字段     | 类型 | 必填 | 说明 |
|----------|------|------|------|
| flowId   | int  | 是   | 流水线 id。可从 URL 解析：路径含 `/base2/c/streams/<flowId>` 或 `/base2/c/streams/<flowId>/auto` 时，`<flowId>` 即为该数字。 |

**URL 规则（与 skill 一致）**

- **不支持**：路径含 `/base2/c/release/canals/`（正式发布流水线）
- **不支持**：路径含 `/base2/c/streams/operation-lib`（组件流水线）
- **支持**：`/base2/c/streams/<flowId>`、`/base2/c/streams/<flowId>/auto` 及带查询参数的形式

### 响应示例

成功：

```json
{
  "data": {
    "errMsg": "",
    "respData": "触发成功",
    "respCode": 0
  }
}
```

失败：

```json
{
  "data": {
    "errMsg": "error：flowId错误:252419",
    "respCode": -1
  }
}
```

| 字段      | 说明 |
|-----------|------|
| errMsg    | 失败时的错误信息 |
| respData  | 成功时具体文案，**可直接展示给用户** |
| respCode  | 0 成功，其他为失败 |

---

## 接口 2：最近有执行记录的流水线列表（getFlowList）

**URL**：`http://ee-api.58dns.org/skill/api-yunxiao-ici/SkillService/getFlowList`

**用途**：获取当前用户最近有执行记录的流水线列表，供选择 **`flowId`** 后调用接口 1。

### 请求 Body（JSON）

```json
{
  "flowType": 4,
  "limitNum": 5
}
```

| 字段      | 类型 | 必填 | 说明 |
|-----------|------|------|------|
| flowType  | int  | 是   | 在本 skill 中**固定为 4**（默认类型流水线） |
| limitNum  | int  | 否   | 返回条数，默认 **5** |

### 响应示例

成功（`respData` 为数组）：

```json
{
  "data": {
    "errMsg": "",
    "respData": [
      {
        "prodOs": "Android",
        "CreateTime": "2026-03-20 00:00:00",
        "prodName": "demo",
        "prodId": 60,
        "flowId": 25244,
        "flowName": "测试测试"
      }
    ],
    "respCode": 0
  }
}
```

失败：

```json
{
  "data": {
    "errMsg": "error：必填参数是空",
    "respCode": -1
  }
}
```

### respData 数组元素字段

| 字段        | 说明 |
|-------------|------|
| prodOs      | app 平台 |
| CreateTime  | 该流水线最后一次构建时间；**对用户展示列表时列名用「最后构建时间」**（不要用「最近记录时间」） |
| prodName    | app 名 |
| prodId      | app id（对用户一般无直接操作含义） |
| flowId      | **流水线 id**，调用接口 1 时使用 |
| flowName    | 流水线名称 |
