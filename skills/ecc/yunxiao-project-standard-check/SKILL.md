---
name: yunxiao-project-standard-check
description: 云效工程规范检查工具。用于检查本地Java、PHP、Go、WF项目的配置文件完整性和目录结构规范性。检查内容包括：1) Java项目：src/main/resources下是否存在config_online/offline/sandbox/stable四套配置文件，pom.xml是否直接依赖快照包，config_online中是否配置了远程debug端口；2) PHP项目：是否存在phpapps目录，子项目是否包含四套配置文件；3) Go项目：是否存在vendor目录，是否包含四套配置文件；4) WF项目：是否存在wfconfig目录，是否包含offline/sandbox/stable/online四套配置文件夹。
parameters:
  - name: project_path
    type: string
    description: 项目根目录路径，默认为当前目录。
    required: false
scripts:
  linux: yunxiao-project-standerd-check/scripts/yunxiao-project-standerd-check.sh
  windows: yunxiao-project-standerd-check/scripts/yunxiao-project-standerd-check.bat
---

# 云效工程规范检查

## 功能概述

对本地项目进行以下规范检查：

1. **Java项目检查**：
   - 配置文件目录检查 - 验证 `src/main/resources` 下是否存在config\_online、config\_sandbox、config\_offline、config\_stable四套环境配置文件
   - POM依赖检查 - 检查是否直接依赖快照包（SNAPSHOT）
   - 生产配置安全检查 - 检查 `config_online` 中是否配置了远程debug端口
2. **PHP项目检查**：
   - 代码结构检查 - 必须存在phpapps目录
   - 子项目配置检查 - 子项目必须包含config\_online、config\_sandbox、config\_offline、config\_stable四套配置文件
3. **Go项目检查**：
   - 依赖目录检查 - 必须存在vendor目录
   - 配置文件检查 - 必须存在config\_online、config\_sandbox、config\_offline、config\_stable四套配置文件
4. **WF项目检查**：
   - 项目类型判断 - 根目录下存在wfconfig目录
   - 配置文件目录检查 - wfconfig下必须存在offline、sandbox、stable、online四套配置文件夹
   - 目录结构检查 - 每套配置文件夹下只能有一个namespace目录，不能有同级目录
   - 配置文件检查 - namespace目录下必须有具体配置文件

## 使用流程

### 1. 选择项目

首先提示用户选择要检查的项目根目录。可以通过以下方式：

- 让用户输入项目路径
- 如果当前目录是项目，询问是否使用当前目录

### 2. 执行检查

运行检查脚本：

```bash
bash "$(dirname "$0")/scripts/yunxiao-project-standerd-check.sh" <project_path>
```

### 3. 输出结果

脚本会输出检查报告，包含：

- ✅ 通过的检查项
- ⚠️ 警告项（需要人工确认）
- ❌ 错误项（必须修复）

## 检查规则详解

### Java项目检查

#### 配置文件目录检查

**要求路径**: `src/main/resources/`

**必须存在的目录**:

- `config_online` - 生产环境配置
- `config_offline` - 离线环境配置
- `config_sandbox` - 沙箱环境配置
- `config_stable` - 稳定环境配置

**检查逻辑**:

- 检查 `src/main/resources` 是否存在
- 检查每个配置目录是否存在

#### POM依赖检查

**检查内容**: `pom.xml` 中的 `<dependencies>` 部分

**禁止项**:

- 直接依赖版本号包含 `SNAPSHOT` 的包
- 例如：`1.0.0-SNAPSHOT`、`2.1-SNAPSHOT`

**注意**: 只检查直接依赖，不检查传递依赖

#### 生产配置安全检查

**检查路径**: `src/main/resources/config_online/`

**禁止配置**:

- `jdwp` 相关配置（Java Debug Wire Protocol）
- `Xrunjdwp` 参数
- `agentlib:jdwp` 参数
- `debug` 端口配置（如 `debug.port`、`jdwp.port`）
- 任何包含 `address=.*:5ddd` 格式的调试端口

**常见违规模式**:

```
# 这些配置会被标记为警告
java.opts=-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=5005
debug.port=5005
jdwp.enabled=true
```

### PHP项目检查

#### 代码结构检查

**要求路径**: `phpapps/`

**结构要求**:

```
├── phpapps                  ---PHP项目，目录固定
    ├── 工程项目名称         ---PHP工程项目 (可有多个子项目)
      ├── config_offline     ---测试环境对等的配置文件目录
      ├── config_online      ---线上环境对等的配置文件目录
      ├── config_stable      ---稳定环境配置文件目录
      ├── config_sandbox     ---沙箱环境配置文件目录
```

**检查逻辑**:

- 检查 `phpapps` 目录是否存在
- 检查每个子项目是否包含四套配置文件

### Go项目检查

#### 依赖目录检查

**要求路径**: `vendor/`

**检查逻辑**:

- 检查 `vendor` 目录是否存在

#### 配置文件检查

**要求路径**: 项目根目录

**必须存在的目录**:

- `config_online` - 生产环境配置
- `config_offline` - 离线环境配置
- `config_sandbox` - 沙箱环境配置
- `config_stable` - 稳定环境配置

**检查逻辑**:

- 检查每个配置目录是否存在

## 脚本参数

```bash
bash "$(dirname "$0")/scripts/yunxiao-project-standerd-check.sh" <project_path> [options]

参数:
  project_path    项目根目录绝对路径

选项:
  --json          输出JSON格式报告
  --quiet         静默模式，只输出错误和警告
```

## 执行要求（严格执行）

1. **禁止自动更改 SKILL.md 的内容** - 任何对 SKILL.md 的修改必须由人工操作
2. **严格执行 SKILL.md 中配置的脚本** - 必须使用上述命令执行 `yunxiao-project-standerd-check.sh` 脚本
3. **禁止自动生成脚本文件** - 脚本文件必须已存在，不得自动创建
4. **禁止自动执行名称不相同的脚本** - 只能执行 SKILL.md 中明确指定的脚本文件名
5. **如果脚本文件不存在，必须报错** - 不得尝试执行其他脚本或自动创建脚本

## 输出格式示例

```
========================================
Java项目规范检查报告
项目路径: /path/to/project
检查时间: 2024-01-15 10:30:00
========================================

[配置文件检查]
✅ src/main/resources 存在
✅ config_online 存在 (3个配置文件)
✅ config_offline 存在 (3个配置文件)
⚠️  config_sandbox 缺失
❌  config_stable 缺失

[POM依赖检查]
❌ 发现SNAPSHOT依赖:
   - com.example:api-client:1.0.0-SNAPSHOT
   - org.test:utils:2.1-SNAPSHOT

[生产配置安全检查]
⚠️  config_online/application.properties 中发现debug配置:
   行15: java.opts=-agentlib:jdwp=transport=dt_socket,address=5005

========================================
总结: 2个错误, 2个警告
========================================
```

```
========================================
PHP项目规范检查报告
项目路径: /path/to/project
检查时间: 2024-01-15 10:30:00
========================================

[代码结构检查]
✅ phpapps 目录存在
✅ 子项目 project1 包含所有配置目录
✅ 子项目 project2 包含所有配置目录

[配置文件检查]
✅ config_online 存在
✅ config_offline 存在
✅ config_sandbox 存在
✅ config_stable 存在

========================================
总结: 0个错误, 0个警告
========================================
```

```
========================================
Go项目规范检查报告
项目路径: /path/to/project
检查时间: 2024-01-15 10:30:00
========================================

[依赖目录检查]
✅ vendor 目录存在

[配置文件检查]
✅ config_online 存在
✅ config_offline 存在
✅ config_sandbox 存在
✅ config_stable 存在

========================================
总结: 0个错误, 0个警告
========================================
```

