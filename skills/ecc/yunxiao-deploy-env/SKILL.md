---
name: yunxiao-deploy-env
description: 用户说「部署」「部署环境」「部署 iONE 环境」「部署构建计划」「部署 iONE 构建计划」「部署云效环境」「部署云效构建计划」「构建」「发布 iONE」「新建环境」「创建新环境」等与部署/新建环境相关的表述时唤起本 skill。说部署类关键字时从步骤 1 起顺序执行；说新建环境、创建新环境等新建类关键字时跳过步骤 1，从步骤 2 起顺序执行。严格按本 skill 与脚本描述执行，勿自行联想或串改流程。禁止绕过本 skill 直接调用云效相关 HTTP 接口（须走本 skill 步骤与附带脚本）。
---

# 云效环境部署（yunxiao-deploy-env）

## 硬性规则（助理必须遵守）

- **禁止绕过本 skill 直接调用接口**：不得使用 `curl`、Postman、手写代码发起 HTTP 请求等方式，自行调用 **getEnvList**、**createEnv**、**deploy** 或其它与本 skill 流程等价的云效接口，以替代本 skill 规定的步骤。助理**必须**通过本 skill 文档中的步骤与 **`scripts/deploy_env.sh`**（macOS/Linux）、**`scripts/deploy_env.ps1`**（Windows）完成；由用户在终端执行脚本，或助理在明确符合 skill 的前提下代跑上述脚本（含参数与交互约定）。若脚本不可用或路径缺失，应**说明情况并引导用户按 skill 操作**，**不得**私自改走「直接调 API」的捷径。
- **新建环境只认本 skill**：用户要「新建环境 / 创建环境」时**只走本 skill 的步骤 2**。**`yunxiao-create-env` 已废弃**，助理**不得**再唤起、引用或依赖该 skill。
- **链接自动打开规则（勿搞反）**：**`createEnv` 成功**返回的环境链接（`result`）**不要**自动打开，**仅在对话中输出完整 URL**。**`deploy`** 返回的 `result` 若为 http(s) 链接，**要**自动打开（`open` / `xdg-open` / 浏览器，以环境为准），并在对话中输出；用户明确拒绝打开时除外。新建环境链路里同样是：**创建链接不弹窗，部署链接照常打开**。

## 唤起条件

下列意图**必须唤起本 skill**（措辞不必逐字相同）：

- **部署类**：部署、部署环境、部署 iONE 环境、部署构建计划、部署 iONE 构建计划、部署云效环境、部署云效构建计划、构建、发布 iONE 等。
- **新建环境类**：新建环境、创建新环境等与「新建环境」同义的说法。

## 流程分流

| 用户说法 | 执行顺序 |
|----------|----------|
| **部署类**（上表） | **从步骤 1** 开始：调用环境列表 → 再按后续步骤顺序执行。 |
| **新建环境类** | **跳过步骤 1**，**从步骤 2（新建环境）** 开始顺序执行。 |

---

## 公共：token（步骤 1 / 2 / 3 调用接口前均需满足）

- 请求 Header 携带：`token: <token>`。
- **获取顺序（须遵守，避免一上来就向用户索要 token）**：
  1. **先读当前环境变量 `YUNXIAO_SKILL_TOKEN`**（进程已继承的变量）。
  2. **若仍无**：在 macOS/Linux 上可尝试执行等价于 **`source ~/.zshrc`**（或用户实际使用的 shell 配置文件，如 `~/.bashrc`）后再读一次 **`YUNXIAO_SKILL_TOKEN`**（许多用户把 token 写在配置里，仅当前会话未加载）。
  3. **若仍无**：在 Windows 上可读取**用户级环境变量**中的 `YUNXIAO_SKILL_TOKEN`（例如此前用 `setx` 写入的）。
  4. **仅当以上方式都拿不到 token 时**，再**询问**用户提供 token；并说明若不知道或没有 token，可到  
     `https://ee.58corp.com/base2/t/apply/common/addToken`  
     申请。
- 用户**新提供**的 token：**默认写入本地全局**（如 macOS/Linux 追加到 `~/.zshrc` 等；Windows 可用 `setx` 等），便于下次被步骤 1～2 自动读到。
- **若在本次流程中已经能从环境变量拿到有效 token：不要重复写入**，直接使用即可。

---

## 公共：projects（三接口一致、可相互复用）

- **getEnvList**、**createEnv**、**deploy** 三个接口里，**`projects` 的含义与结构一致**（均为同一套工程对象数组：`groupName`、`projectName`、`branchName` 及可选 `moduleName` 等，规则相同）。
- **同一次流程内**：在任一步骤确定下来的 **`projects` JSON**，**可直接复用**到另外两个接口的 **`projects` 字段**，**无需**因接口不同而改换结构或字段语义；步骤 1 用过的可在步骤 2、3 继续用，步骤 2 请求里用过的也可在步骤 3 **原样复用**。
- 仅当无法复用（例如需增删工程、用户明确要求变更列表）时，再按**相同规则**重新组装。

---

## 公共：moduleName（说明、询问、三接口统一复用）

**含义（向用户说明时可用）**：`moduleName` 表示**父子工程**语境下的**模块**维度。  
- **指定了 `moduleName`**：查环境列表、新建环境、部署时，都**只针对该模块**（查该模块关联的环境、环境关联该模块、部署该模块）。  
- **不指定**（不带 `moduleName` 键）：上述三个接口均按**该工程下全部模块**处理。  
- **单工程**（非父子工程）：一般**不需要** `moduleName`。

**询问**：在**首次需要由助理组装 `projects`** 时（尚未有用户确认的完整 `projects` 数据前），须**先简短解释**上段含义，再**明确询问用户是否要指定模块名**。  
- 用户**不指定**：全流程步骤 1、2、3 的 `projects` 中均**不出现** `moduleName` 键。  
- 用户**指定**：将用户给出的模块名写入 `projects` 中相应 object（单工程一个 object 时带该键；多工程时按用户要求对每个 object 赋值）。随后在 **getEnvList、createEnv、deploy** 中**沿用同一份 `projects`（见上文「公共：projects」）**，不得在无新指令时擅自改换。

**例外**：用户已通过文件/粘贴等方式提供**完整 `projects` JSON** 且明确以此为准时，按其内容执行；若内容不含 `moduleName` 键则视为不指定。助理仍可用一句话复述 `moduleName` 含义供用户核对。

---

## 步骤 1：调用环境列表（仅「部署类」流程）

**URL**：`http://ee-api.58dns.org/skill/api-yunxiao-ione/envApi/skill/getEnvList`  
**Method**：`POST`  
**Header**：`token: <token>`  
**Body**：工程列表 JSON 数组（与下方字段一致）。

```json
[
  {
    "groupName": "",
    "projectName": "",
    "branchName": ""
  }
]
```

需要限定父子工程某一模块时，在该 object 上**增加**键 `"moduleName": "模块名"`。**moduleName 为空时不要带该键**（不要传 `"moduleName": ""`）。

字段说明：

1. **projects**（工程列表），每个工程一个 object：
   - **groupName**：当前工程的分组名。
   - **projectName**：当前工程的工程名。
   - **moduleName**：模块名；**单工程不需要**；**父子工程**使用，**非必填**。若需指定查找父子工程中**某一模块**关联的环境，则赋值；**不赋值**（或不带该键）则默认查找父子工程**所有模块**关联的环境。**为空时不要包含 `moduleName` 键。**
   - **branchName**：当前工程的分支名。
   - 多个工程时，每个工程一个 object。

2. **展示**：返回的环境为列表；在对话中**展示全部数据**，每一行至少包含：
   - **name**
   - **envType**：`0` 显示为 **环境**；**非 0** 显示为 **构建计划**
   - **deployType**：`0` 显示为 **测试**；`1` 显示为 **沙箱**

3. **用户选择后部署**：用户选定一条后，将该条 **id** → 部署接口 **envId**，**envType** → **envType**，**deployType** → **deployType**，**直接调用步骤 3 部署接口**（不再额外询问是否部署）。

4. **列表为空，或用户表示没有想要的环境**：询问是否需要**帮用户创建新环境**。  
   - **需要**：进入 **步骤 2**，调用新建环境接口。  
   - **不需要、也不创建**：流程结束。

---

## 步骤 2：新建环境（「新建环境类」从此开始；或由步骤 1.4 进入）

**URL**：`http://ee-api.58dns.org/skill/api-yunxiao-ione/envApi/skill/createEnv`  
**Method**：`POST`  
**Header**：`token: <token>`  
**Body**（JSON）：

```json
{
  "envName": "",
  "deployType": 0,
  "envType": 0,
  "projects": [
    {
      "groupName": "",
      "projectName": "",
      "branchName": ""
    }
  ]
}
```

**`projects`**：与步骤 1 **结构一致**，**优先直接复用**步骤 1 已使用的同一份 **`projects`**（见「公共：projects」）。各 object 的 **moduleName** 规则同步骤 1：**有模块名则带键，为空则不带键。**

说明（与接口注释一致，`deployType` / `envType` 传数值：沙箱为 `1`，测试为 `0`，创建环境时 `envType` 固定 `0`）：

1. 根据 **groupName**、**projectName** 生成**建议环境名**，询问用户是否采纳；**不采纳**则请用户给出环境名并赋给 **envName**。
2. 询问创建**沙箱**还是**测试**：沙箱 → **deployType = 1**；测试 → **deployType = 0**。
3. **envType** 暂时只支持创建环境，**默认为 0**，**不必向用户展示**。
4. **projects**（工程列表）：
   - **groupName**、**projectName**、**branchName** 含义同步骤 1。
   - **moduleName**：单工程不需要；父子工程非必填。若需环境关联**某一模块**则赋值；**不赋值**（或不带该键）则默认关联父子工程**所有模块**。**为空时不要包含该键。**
   - 多个工程时，每个工程一个 object。
5. **返回**：**code 为 0** 则创建成功，会返回环境链接（`result`）。**在对话中输出完整 URL**；**不要**因该接口成功而自动打开浏览器（**仅此一条**：**仅**针对 **createEnv 成功** 返回的 `result` 链接不自动打开）。从链接解析 **id** → **envId**，**dt** → **deployType**，**envType 取 0**，**不再获取其他信息**，**直接进入步骤 3 部署**。若创建失败，提示用户到**云效平台手动创建**。

---

## 步骤 3：部署

**URL**：`http://ee-api.58dns.org/skill/api-yunxiao-ione/envApi/skill/deploy`  
**Method**：`POST`  
**Header**：必须携带 **`token: <token>`**（与步骤 1、2 相同）。  
**token 获取**：与「公共：token」一致——**优先**读环境变量 **`YUNXIAO_SKILL_TOKEN`**；未设置则 **`source ~/.zshrc`**（或用户实际 shell 配置）后再读；仍无则**询问用户**；用户不知道或没有 token 时告知申请链接：  
`https://ee.58corp.com/base2/t/apply/common/addToken`  
用户**新提供**的 token **默认写入本地全局**（如 `~/.zshrc` / Windows `setx`）；**若环境变量里已有有效 token，不要二次写入**，直接使用。

**Body**（JSON，`deployType` / `envType` 与平台约定一致，一般为数值 `0`/`1`）：

```json
{
  "envId": "",
  "deployType": 0,
  "envType": 0,
  "projects": [
    {
      "groupName": "",
      "projectName": "",
      "branchName": "",
      "moduleName": ""
    }
  ]
}
```

**projects**（工程列表）说明：

1. **可直接复用**步骤 1 **getEnvList** 的请求体（工程数组），或步骤 2 **createEnv** 里的 **`projects`**；**同一次流程内结构一致**，无需改字段语义。若无法复用，则在本地**实时**组装：
   - **groupName**：当前仓库/工程在 Git 上的**分组名**（如 `origin` URL 中的 group）。
   - **projectName**：**工程名**（仓库名）。
   - **moduleName**：**父子工程**场景下的模块名；**单工程一般不需要**；**非必填**。若需**只部署某一子模块**则赋值；**不赋值**（或不带该键）表示部署该工程下**全部模块**。**为空时不要传该键**（不要 `"moduleName": ""`）。
   - **branchName**：当前要部署的**分支名**。
2. 多个工程时，**每个工程一个 object** 放入 **`projects`** 数组。

**重试时可选字段 `vipFlg`**：仅在「不使用 VIP 再次部署」场景下，在**每个**工程 object 上增加 **`"vipFlg": 0`**（与 `moduleName` 等同 object 内字段），再次 POST 部署接口。详见下文异常处理。

---

### 步骤 3.1：部署接口返回与异常处理

调用部署接口后**先展示完整返回 JSON**（便于排查）。

1. **`code === 0`（或整数 0）**  
   - 表示**触发部署成功**（**deploy** 接口）。  
   - **在对话中输出** `result` 完整 URL。  
   - **在浏览器中打开** `result` 链接，方便用户查看流水线/部署状态（用户明确拒绝打开时除外）。**注意**：这与步骤 2 **createEnv** 成功返回的链接**不同**——**createEnv** 的 `result` **不**自动打开；**仅 deploy** 的 `result` 按本条打开。

2. **`code` 非 0**  
   - 表示**部署触发失败**。  
   - **展示 `msg` 全文**，并明确提示：**部署触发失败**。  
   - 若 **`result` 为 http(s) 链接**：**在对话中输出**，并**在浏览器中打开**，便于到平台查看详情（用户明确拒绝打开时除外）。

3. **`msg` 与 VIP / 配额相关**  
   - 若 `msg` 含义上属于 **「vip 数量不足」**、**「配额不足」** 等（文案可能含 **「vip」「配额」** 等关键字，以实际 `msg` 为准）：  
     - **询问用户**是否愿意**不使用 VIP** 再次触发部署。  
     - 若用户给出**肯定回答**（是 / 可以 / 好 等）：在 **`projects` 的每个 object** 中增加 **`vipFlg`，值为 `0`**，**其余字段与上次请求保持一致**（含已选的 `envId`、`deployType`、`envType` 与同一份 `projects` 结构），**再次调用部署接口**。  
     - **仅询问一次**；用户拒绝或再次失败则按失败结束（可再次展示 `msg`）。

4. **`msg` 与合并 master 相关**  
   - 若 `msg` 提示需要**将 master 最新代码合并到当前分支**、或 **「当前分支不是最新代码」** 等（以实际 `msg` 为准，可匹配「合并」「master」「最新代码」等组合）：  
     - 在**当前仓库**执行：**拉取远端**后，将 **远端默认主干（优先 `origin/master`，若无则 `origin/main`）合并进当前分支**；合并成功后 **push 到远端**（当前分支跟踪的远程分支）。  
     - 若 **merge 冲突或 push 失败**：**停止自动重试**，提示用户**手动解决冲突 / 推送**后再部署。  
     - 合并并推送成功后：**不改动**已组好的 **`projects`（及 `envId` 等）**，**再次调用部署接口**。  
     - **自动合并最多尝试一轮**；若仍返回同类错误，勿死循环，改为展示 `msg` 并请用户人工处理。

5. **助理（对话）执行时**：在依次处理异常时，若**同时**命中 VIP 类与合并类提示，**优先询问 VIP**；合并 master 需在用户本机 git 仓库中操作，**确认 cwd 为正确工程目录**。

---

**moduleName** 规则仍与「公共：moduleName」一致：**有值才带键，为空不带键。**

说明（与上文合并）：

1. **projects** 优先复用步骤 1 / 步骤 2 的同一份 JSON；否则本地按上表实时组装。  
2. **返回与异常** 按 **步骤 3.1** 执行。

---

## 本地脚本（与上文一致，勿串改）

| 文件 | 说明 |
|------|------|
| `scripts/deploy_env.sh` | macOS / Linux |
| `scripts/deploy_env.ps1` | Windows（PowerShell） |

**token**：`deploy_env.sh` 与 skill 一致——**先读 `YUNXIAO_SKILL_TOKEN`，再 `source ~/.zshrc` 后重读，仍无才交互询问**；申请链接为 `https://ee.58corp.com/base2/t/apply/common/addToken`；**仅当当前进程尚未继承该变量时**才写入 `~/.zshrc`。`deploy_env.ps1` **先读环境变量**，没有再询问；**仅当未设置 `YUNXIAO_SKILL_TOKEN` 时**才 `setx` 持久化。

**部署失败自动处理（与步骤 3.1 对齐，交互式终端下）**：

- **`msg` 疑似 VIP/配额不足**：询问是否**不使用 VIP**；确认后为 **`projects` 每个 object 增加 `vipFlg: 0`** 并**再次 POST 部署**（仅一轮）。
- **`msg` 疑似需合并 master / 分支非最新**：执行 **`git fetch origin`**，合并 **`origin/master`**（若无则 **`origin/main`**），成功后 **`git push`**，再**再次调用部署**（自动合并仅一轮）。

**参数**：

- `--mode deploy`（默认）：步骤 1 → 选环境 → 步骤 3；列表为空或「无合适环境」时可进入步骤 2 再步骤 3。
- `--mode create-env`：跳过步骤 1，从步骤 2 开始，成功后步骤 3。
- `--token`、`--projects-json`、`--projects-file`：与常见用法相同。
- `--module-name <名>`（可选）：自动从 git 组装 `projects` 时直接带上该键，**三接口共用**同一份 `projects`，不再交互询问。
- `--no-module-prompt`：自动从 git 组装且**未**传 `--module-name` 时，**不**弹出「是否指定 moduleName」的说明与询问（非交互场景使用）。
- 若既未传 `--module-name` 也未传 `--no-module-prompt`，且终端为交互式：脚本会**打印 moduleName 说明**并询问是否指定；指定则写入 `projects`，**同一份 `projects` 用于三个接口**（与「公共：projects」一致）。
- `--projects-json` / `--projects-file`：以文件内容为准，**不**再询问 moduleName；其中空字符串的 `moduleName` 会在请求前去掉该键。

脚本直接调用 **getEnvList**、**createEnv**、**deploy** 三个接口。