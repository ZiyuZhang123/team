# iRepo 发包技能使用说明

本技能默认模式是：调用 API 直接发包（`quickUpload -> deploy*ForSkill -> getResultForSkill 轮询`）。

## 1) API 发包（推荐）

脚本：`scripts/deploy_from_quick_upload.py`

### Token 前置要求

- 优先读取环境变量：`YUNXIAO_SKILL_TOKEN`
- 若未读取到，脚本会尝试 `source ~/.zshrc` 后再次读取
- 仍没有 token 时，会提示去申请：
  - `https://ee.58corp.com/base2/t/apply/common/addToken`

### 示例

- PHP：
  - `python3 scripts/deploy_from_quick_upload.py php --groupId broker --artifactId scf-php-broker-info-dpl-proxy`
- JAR：
  - `python3 scripts/deploy_from_quick_upload.py jar --groupId com.bj58.arch.wcloud --artifactId arch-wcloud-skill-market-api`
- npm：
  - `python3 scripts/deploy_from_quick_upload.py npm --artifactId agent-base`
- 快照覆盖确认后继续发布：
  - `python3 scripts/deploy_from_quick_upload.py jar --module arch-wcloud-skill-market-api --param-source local --confirm-snapshot`
  - 默认会在 `status=2` 时询问是否覆盖；输入“需要覆盖/是”后继续二次覆盖发布

### 自动参数收集

未手动传参时，会从当前目录向上查找：
- PHP：`composer.json` 的 `name=vendor/name`
- JAR：`pom.xml` 的 `groupId/artifactId`（可回退 parent.groupId）
- npm：`package.json` 的 `name`（支持 `@scope/pkg`）

可用 `--cwd /path/to/project` 指定搜集起点目录。
- 用户直接说“发包”时默认用当前工程；若当前工程找不到对应配置，脚本会列出发现到的工程表格供点击选择。

### JAR 父子工程选择

- 当检测到 Maven 多模块工程（父子工程）且未显式选择时，脚本会先输出模块列表并暂停发包。
- 继续发布时可明确指定：
  - 指定模块：`--module <模块目录名>`
  - 全发（父工程/全量包）：`--all-modules`
- 在交互流程中，用户点击模块/全发选项后会直接进入下一步，不需要再输入 continue。

### Dry-run 预览

- 仅跑 `quickUpload` + 组装 deploy 参数，不真正发包：
  - `python3 scripts/deploy_from_quick_upload.py jar --groupId com.bj58.arch.wcloud --artifactId arch-wcloud-skill-market-api --dry-run`

### 分支发包（本地参数分支）

- 用户指定分支并选择本地参数时，脚本会从本地工程构建 deploy 参数：
  - `python3 scripts/deploy_from_quick_upload.py jar --branch master --module arch-wcloud-skill-market-api --param-source local`
  - 未指定 `--module` 且是父子工程时，仍会先提示模块列表。
- 分支校验：你指定的分支必须是当前编辑器已打开的本地分支，脚本不会自动切分支。

### 你会看到的输出（人性化）

- quickUpload 请求参数
- quickUpload 返回摘要
- 若 quickUpload 未返回 `gitUrl`，会自动调用 `getIdByPath(gitPath, token)` 获取 location
- 发包前参数来源二选一（quickUpload / 本地参数）及各自参数明细
- 在交互流程中，用户点击参数来源选项后会直接进入发布，不需要再输入 continue
- deploy 请求参数
- deploy 接口返回（非 dry-run）
- deploy 接口人性化结果（成功/失败、平台提示、关键字段）
- getResultForSkill 轮询最终结果（每 2 秒轮询，直到 `status != 4`，最多 5 次）
- 最终一句话：`<包名>包的全量包/模块包发布结束，状态为<msg>`

## 2) 兼容脚本（可选）

脚本：`scripts/make_confirm_link.py`（仅历史兼容，默认不使用）

### 示例

- `python3 scripts/make_confirm_link.py --print-md php`
- `python3 scripts/make_confirm_link.py --print-md jar`
- `python3 scripts/make_confirm_link.py --print-md npm`

## 依赖

- Python 3（建议 3.9+）
