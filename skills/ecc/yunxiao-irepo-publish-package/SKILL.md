---
name: irepo-confirm-link
description: 指定工程之后，自动收集参数并通过 iRepo quickUpload + deploy 接口直接发布 PHP Composer / Maven2 JAR / npm 包，并将接口返回翻译成人性化结果。
---

# iRepo 直接发包（API）

## 作用

- 自动收集 `groupId / artifactId / format`，并按类型调用 iRepo 发布接口：
  1) `POST http://ee-api.58dns.org/skill/api-yunxiao-irepo/api/quickUpload`（`JarSearchEntity`）
  1.1) 当 `quickUpload` 未返回 `gitUrl` 时，调用 `POST http://ee-api.58dns.org/skill/api-yunxiao-irepo/api/getIdByPath`（`{"gitPath":"xxx","token":"xxx"}`）兜底获取 location（`data.obj`）
  2) `POST deployPhpForSkill / deployJarForSkill / deployNpmForSkill`（`JarReleaseDeployEntity`）
  3) `POST http://ee-api.58dns.org/skill/api-yunxiao-irepo/api/getResultForSkill`（`{"workSpaceUUID":"xxx"}`），使用 deploy 返回的 `workSpaceUUID`
     - 固定每 2 秒轮询一次
     - 返回 `status != 4` 时停止轮询，代表发包结束
     - 最多轮询 5 次，超过 5 次仍为 `status=4` 时结束本次查询并提示“任务仍在进行中”
- 不生成确认链接，直接返回“人性化发布结果”。

## 固定发布流程（必须按此顺序）

### 1) PHP（`format=composer`）

- 先调用 quickUpload，请求（`JarSearchEntity`）：
  - `{"groupId":"<groupId>","artifactId":"<artifactId>","format":"composer"}`
- 再调用 `POST http://ee-api.58dns.org/skill/api-yunxiao-irepo/api/deployPhpForSkill`，请求（`JarReleaseDeployEntity`）映射：
  - `repositoryType` = `"3"`
  - `judgeType` = `"0"`
  - `location` = `quickUpload.data.gitUrl`
  - `branch` = `quickUpload.data.gitBranch`
  - `pomPath` = `quickUpload.data.realPomLocation`
  - `version` = `quickUpload.data.version`
  - `releaseDescription` = `quickUpload.data.releaseDescription`
### 2) JAR / Maven2（`format=maven2`）

- 先调用 quickUpload，请求（`JarSearchEntity`）：
  - `{"groupId":"<groupId>","artifactId":"<artifactId>","format":"maven2"}`
- 再调用 `POST http://ee-api.58dns.org/skill/api-yunxiao-irepo/api/deployJarForSkill`，请求（`JarReleaseDeployEntity`）映射：
  - `repositoryType` = `"1"`
  - `deployType` = `"1"`
  - `versionType` = `""`
  - `location` = `quickUpload.data.gitUrl`
  - `compileVersion` = `int(quickUpload.data.jdkVersion)`
  - `deployPom` = `quickUpload.data.deployPom or ""`
  - `compilePom` = `quickUpload.data.compilePom or ""`
  - `pomPath` = `quickUpload.data.realPomLocation`
  - `branch` = `quickUpload.data.gitBranch`
  - `advancedOptions` = `false`
  - `scanOptions` = `false`
  - `releaseDescription` = `quickUpload.data.releaseDescription`
  - `snapshotConfirm` = `false`
  - `scanOpen` = `"1"`
  - `mavenType` = `quickUpload.data.mavenType`
  - `requestUUID` = 运行时生成 UUID
  - 其他字段保持默认空值：`groupId/artifactId/version/projectId/workSpaceUUID/commitId/compileIp=""`，`checkAccess=0`
### 3) npm（`format=npm`）

- 先调用 quickUpload，请求（`JarSearchEntity`）：
  - `{"groupId":null,"artifactId":"<artifactId>","format":"npm"}`
  - 若有 scope，也可传 `groupId`
- 再调用 `POST http://ee-api.58dns.org/skill/api-yunxiao-irepo/api/deployNpmForSkill`，请求（`JarReleaseDeployEntity`）映射：
  - `location` = `quickUpload.data.gitUrl`
  - `branch` = `quickUpload.data.gitBranch`
  - `releaseDescription` = `quickUpload.data.releaseDescription`
  - `pomPath` = `quickUpload.data.realPomLocation`
  - `compileVersion` = `int(quickUpload.data.jdkVersion)`
  - `buildCommand` = `quickUpload.data.buildCommand`
  - `buildTool` = `quickUpload.data.buildTool or "npm"`
  - `publishParam` = `quickUpload.data.publishParam`
  - `advancedOptions` = `false`
## 输出要求（对话内）

- 成功发布后默认输出五段：
1) `发包结果：<deploy接口返回里的关键信息>`
2) `平台提示：<msg>`
3) `关键返回：<taskId/jobId/...>`
4) `getResultForSkill` 最终返回（结束态）
5) 最终结论：`<包名>包的全量包/模块包发布结束，状态为<msg>`
- 失败时追加建议（参数/分支/权限检查）

## 参数收集规则

- PHP：从 `composer.json` 的 `name=vendor/name` 推导 `groupId/artifactId`
- JAR：从 `pom.xml` 读取，`groupId` 缺失时使用 `<parent><groupId>`
- npm：从 `package.json` 的 `name` 读取；`@scope/pkg` 时 `groupId=scope`，普通包可无 `groupId`

## Token 规则（必须执行）

- 获取认证 token：
  1) 优先读取环境变量 `YUNXIAO_SKILL_TOKEN`
  2) 若未设置，先主动 `source ~/.zshrc` 后再次读取
  3) 仍未获取到则询问用户提供 token
- 若用户没有 token 或不知道 token，明确告知申请地址：
  - `https://ee.58corp.com/base2/t/apply/common/addToken`
- 用户提供 token 后：
  - 当前会话内设置 `YUNXIAO_SKILL_TOKEN`
  - 默认写入全局环境变量（macOS/Linux 追加到 `~/.zshrc`；Windows 使用 `setx`）
- 调用 `quickUpload`、`deploy*ForSkill`、`getResultForSkill` 时都要携带该 token。
- token 传递方式采用双写兼容：
  - Header：`token: <YUNXIAO_SKILL_TOKEN>`
  - Body：`"token":"<YUNXIAO_SKILL_TOKEN>"`

## 快捷交互（发包）

按以下约定执行：

1) `skill-market` 默认指向 JAR（`format=maven2`）发布流程（从 `arch-wcloud-skill-market-api/pom.xml` 解析坐标）
2) 自动在本机常见位置寻找工程：
   - 优先：`~/IdeaProjects/skill-market-service`
   - 其次：`~/trae/skill-market-service`
3) 用户直接输入“发包”时：
   - 默认发布当前工程（以当前目录向上查找工程配置文件）
   - 若当前工程未识别到可发布配置，则列出已发现工程表格并让用户点击选择
4) 收到发包命令后，先检查是否父子工程（是否存在 Maven modules）：
   - 若是父子工程，先输出模块选择表格（包含可选模块和“全发”一行）：
     - 列：`选项 / 发布目标 / 说明`
     - 每个模块一行，另加一行：`全发 -> 发布父工程全量包`
   - 用户点击选项后立即进入下一步，不需要额外输入 continue
   - 等用户明确选择后再执行发包：
     - 用户给模块名 -> 按指定模块发包
     - 用户说“全发” -> 按父工程/全量包发包
5) 完成选择后再调用 API 发包，并输出人性化发布结果。
6) 分支发布规则：
   - 用户只说“XXX工程发包” -> 按默认流程：`quickUpload -> deploy*ForSkill -> getResultForSkill`
   - 用户说“XXX工程，XXX分支发包” -> 跳过 `quickUpload`，先检查本地工程并构建 deploy 参数，然后直接调用 `deploy*ForSkill -> getResultForSkill`
   - 分支限制：指定分支必须等于当前编辑器打开的本地分支；skill 不负责切换分支拿参数
7) 参数来源二选一（发包前必须展示）：
   - 选项1：`上次发布参数（quickUpload）`，并展示参数明细
   - 选项2：`本地参数`，并展示参数明细
   - 用户点击 quick 选项后立即继续：使用 quickUpload 参数发布
   - 用户点击 local 选项后立即继续：走本地参数分支发布
   - 不需要再让用户输入 continue
8) 快照覆盖发布：
   - 当 `getResultForSkill` 返回 `status=2` 且提示“是否覆盖已有快照版本”时，先询问用户是否覆盖
   - 用户回复“需要覆盖/是”后再继续覆盖发布；否则结束流程
   - 非交互执行时可通过 `--confirm-snapshot` 直接确认覆盖
   - 使用返回 `data`（`groupId/artifactId/version/projectId/commitId/workSpaceUUID`）构建覆盖参数并二次调用 `deployJarForSkill`
   - 覆盖参数关键字段：`snapshotConfirm=true`、`checkAccess=1`，并保留原 deploy 参数中的通用字段
   - 覆盖 deploy 后继续 `getResultForSkill` 轮询直到结束

## 推荐执行方式（终端）

在该 skill 目录执行：
- 执行 API 发包（推荐）：
  - PHP：`python3 scripts/deploy_from_quick_upload.py php --groupId broker --artifactId scf-php-broker-info-dpl-proxy`
  - JAR：`python3 scripts/deploy_from_quick_upload.py jar --groupId com.bj58.arch.wcloud --artifactId arch-wcloud-skill-market-api`
  - JAR 指定模块：`python3 scripts/deploy_from_quick_upload.py jar --module arch-wcloud-skill-market-api`
  - JAR 全发：`python3 scripts/deploy_from_quick_upload.py jar --all-modules`
  - npm：`python3 scripts/deploy_from_quick_upload.py npm --artifactId agent-base`
  - 仅预览参数（不真正发包）：追加 `--dry-run`
- 旧脚本 `make_confirm_link.py` 仅用于历史兼容，不作为默认流程。

完整用法见：`USAGE.md`
