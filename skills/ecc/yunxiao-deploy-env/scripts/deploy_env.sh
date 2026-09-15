#!/bin/bash
set -euo pipefail

export LANG="${LANG:-zh_CN.UTF-8}"
export LC_ALL="${LC_ALL:-zh_CN.UTF-8}"

GET_ENV_URL="http://ee-api.58dns.org/skill/api-yunxiao-ione/envApi/skill/getEnvList"
CREATE_ENV_URL="http://ee-api.58dns.org/skill/api-yunxiao-ione/envApi/skill/createEnv"
DEPLOY_URL="http://ee-api.58dns.org/skill/api-yunxiao-ione/envApi/skill/deploy"
TOKEN_APPLY_URL="https://ee.58corp.com/base2/t/apply/common/addToken"

MODE="deploy"
TOKEN=""
PROJECTS_FILE=""
PROJECTS_JSON=""
MODULE_NAME=""
NO_MODULE_PROMPT=0

usage() {
  echo "用法: $0 [--mode deploy|create-env] [--module-name <名>] [--no-module-prompt] [--projects-json <json>] [--projects-file <path>] [--token <token>]"
  echo "  --mode deploy          从环境列表选择并部署（默认）"
  echo "  --mode create-env      跳过列表：新建环境成功后立即部署"
  echo "  --module-name <名>     指定后写入 projects，getEnvList/createEnv/deploy 三接口复用"
  echo "  --no-module-prompt     自动组装 projects 时不询问 moduleName（需非交互时用）"
  echo "  --projects-json        projects 数组 JSON"
  echo "  --projects-file        projects JSON 文件路径"
  echo "  --token                认证 token（可用 YUNXIAO_SKILL_TOKEN）"
  exit 1
}

while (( "$#" )); do
  case "$1" in
    --mode)
      MODE=${2:-deploy}
      shift 2
      ;;
    --token)
      TOKEN=${2:-""}
      shift 2
      ;;
    --projects-file)
      PROJECTS_FILE=${2:-""}
      shift 2
      ;;
    --projects-json)
      PROJECTS_JSON=${2:-""}
      shift 2
      ;;
    --module-name)
      MODULE_NAME=${2:-""}
      shift 2
      ;;
    --no-module-prompt)
      NO_MODULE_PROMPT=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "错误: 未知参数 $1" >&2
      usage
      ;;
  esac
done

if [[ "$MODE" != "deploy" && "$MODE" != "create-env" ]]; then
  echo "错误: --mode 只能是 deploy 或 create-env" >&2
  exit 1
fi

# token：优先环境变量；已存在则不重复写入 zshrc
resolve_token() {
  if [ -z "$TOKEN" ]; then
    if [ -n "${YUNXIAO_SKILL_TOKEN:-}" ]; then
      TOKEN="$YUNXIAO_SKILL_TOKEN"
    elif [ -f "${HOME:-}/.zshrc" ]; then
      # shellcheck source=/dev/null
      . "$HOME/.zshrc" || true
      if [ -n "${YUNXIAO_SKILL_TOKEN:-}" ]; then
        TOKEN="$YUNXIAO_SKILL_TOKEN"
      fi
    fi
  fi
  if [ -z "$TOKEN" ]; then
    echo "未检测到 YUNXIAO_SKILL_TOKEN。"
    echo "若不知道 token，请先申请：$TOKEN_APPLY_URL"
    read -r -p "请输入 token: " TOKEN || true
  fi
  if [ -z "$TOKEN" ]; then
    echo "错误: 未提供 token。" >&2
    exit 1
  fi
  if [ -z "${YUNXIAO_SKILL_TOKEN:-}" ]; then
    export YUNXIAO_SKILL_TOKEN="$TOKEN"
    if [ -n "${HOME:-}" ] && [ -f "$HOME/.zshrc" ]; then
      if ! grep -q "YUNXIAO_SKILL_TOKEN" "$HOME/.zshrc" 2>/dev/null; then
        printf '\nexport YUNXIAO_SKILL_TOKEN="%s"\n' "$TOKEN" >> "$HOME/.zshrc"
      fi
    fi
  fi
}

# 从 git 组装 projects 前：说明 moduleName 并询问是否指定（三接口共用同一份 projects）
prompt_module_name_if_needed() {
  if [ -n "${MODULE_NAME:-}" ]; then return 0; fi
  if [ "${NO_MODULE_PROMPT}" = "1" ]; then return 0; fi
  if [ ! -t 0 ]; then return 0; fi
  cat <<'EOF' >&2
moduleName 说明：用于父子工程中的「模块」。指定后，环境列表、新建环境、部署三个接口将只针对该模块；不指定则针对工程下全部模块。单工程一般无需指定。
EOF
  read -r -p "是否指定 moduleName？(y/N): " yn || true
  if [[ "$yn" =~ ^[Yy]$ ]]; then
    read -r -p "请输入 moduleName: " MODULE_NAME || true
  fi
}

build_projects_json() {
  if [ -n "$PROJECTS_FILE" ] && [ -n "$PROJECTS_JSON" ]; then
    echo "错误: --projects-file 与 --projects-json 不能同时使用。" >&2
    exit 1
  fi
  if [ -n "$PROJECTS_FILE" ]; then
    [ -f "$PROJECTS_FILE" ] || { echo "错误: projects 文件不存在。" >&2; exit 1; }
    PROJECTS_JSON=$(cat "$PROJECTS_FILE")
  fi
  if [ -z "$PROJECTS_JSON" ]; then
    ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
    [ -n "$ROOT" ] || { echo "错误: 当前目录不是 git 仓库。" >&2; exit 1; }
    REMOTE=$(git remote get-url origin 2>/dev/null || true)
    [ -n "$REMOTE" ] || { echo "错误: 无 origin 远端。" >&2; exit 1; }
    if [[ "$REMOTE" == *"://"* ]]; then
      PATH_PART=${REMOTE#*://}
      PATH_PART=${PATH_PART#*/}
    elif [[ "$REMOTE" == *":"* ]]; then
      PATH_PART=${REMOTE#*:}
    else
      PATH_PART=$REMOTE
    fi
    PATH_PART=${PATH_PART%.git}
    GROUP_NAME=${PATH_PART%/*}
    PROJECT_NAME=${PATH_PART##*/}
    if [ -z "$GROUP_NAME" ] || [ -z "$PROJECT_NAME" ] || [ "$GROUP_NAME" = "$PROJECT_NAME" ]; then
      read -r -p "请输入 groupName: " GROUP_NAME
      read -r -p "请输入 projectName: " PROJECT_NAME
    fi
    BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    [ -n "$BRANCH_NAME" ] && [ "$BRANCH_NAME" != "HEAD" ] || { echo "错误: 无法获取当前分支。" >&2; exit 1; }
    prompt_module_name_if_needed
    export _GN="$GROUP_NAME" _PN="$PROJECT_NAME" _BN="$BRANCH_NAME" _MN="${MODULE_NAME:-}"
    PROJECTS_JSON=$(python3 -c "import json,os; r={'groupName':os.environ['_GN'],'projectName':os.environ['_PN'],'branchName':os.environ['_BN']}; m=os.environ.get('_MN','').strip();
if m: r['moduleName']=m
print(json.dumps([r]))")
    unset _GN _PN _BN _MN
  fi
  if [ -z "$PROJECTS_JSON" ]; then
    echo "错误: projects 未设置。" >&2
    exit 1
  fi
  # moduleName 为空或仅空白时不带该键
  PROJECTS_JSON=$(printf '%s' "$PROJECTS_JSON" | python3 -c "import json,sys
a=json.load(sys.stdin)
if not isinstance(a,list):
    sys.stderr.write('错误: projects 须为 JSON 数组\n')
    sys.exit(1)
for o in a:
    if isinstance(o,dict) and 'moduleName' in o:
        v=o['moduleName']
        if v is None or (isinstance(v,str) and not str(v).strip()):
            del o['moduleName']
print(json.dumps(a,ensure_ascii=False))") || exit 1
}

# 从 createEnv 返回 JSON 中取 result 链接里的 id、dt（两行：id、dt）
parse_create_result() {
  CR="$1" python3 - <<'PY'
import json, re, os, sys
o = json.loads(os.environ["CR"])
if o.get("code") != 0:
    print(o.get("msg", ""), file=sys.stderr)
    sys.exit(2)
url = o.get("result") or ""
m = re.search(r"[?&]id=(\d+)", url)
d = re.search(r"[?&]dt=(\d+)", url)
if not m or not d:
    print("无法从 result 解析 id/dt", file=sys.stderr)
    sys.exit(3)
print(m.group(1))
print(d.group(1))
PY
}

# msg 是否提示 VIP 数量 / 配额不足（用于询问是否无 VIP 重试）
msg_match_vip_quota() {
  printf '%s' "$1" | python3 -c "import sys
t=sys.stdin.read()
if not t.strip():
    sys.exit(1)
# 与 skill 一致：vip数量、配额不足等
k=t.lower()
ok=('vip' in t and '数量' in t) or '配额不足' in t or ('配额' in t and '不足' in t)
sys.exit(0 if ok else 1)" 2>/dev/null
}

# msg 是否提示需合并 master / 分支非最新
msg_match_merge_master() {
  printf '%s' "$1" | python3 -c "import sys
t=sys.stdin.read()
if not t.strip():
    sys.exit(1)
tl=t.lower().replace(' ','')
ok='需要合并master' in tl
ok=ok or ('master' in tl and ('合并' in t or '最新' in t))
ok=ok or ('当前分支' in t and '最新' in t and '不是' in t)
sys.exit(0 if ok else 1)" 2>/dev/null
}

projects_add_vip_flg_zero() {
  printf '%s' "$PROJECTS_JSON" | python3 -c "import json,sys
a=json.load(sys.stdin)
if not isinstance(a,list):
    print('错误: projects 须为数组', file=sys.stderr)
    sys.exit(1)
for o in a:
    if isinstance(o,dict):
        o['vipFlg']=0
print(json.dumps(a,ensure_ascii=False))" || exit 1
}

# 拉取并合并 origin/master 或 origin/main，再 push 当前分支
git_merge_origin_default_and_push() {
  local merge_ref=""
  git fetch origin || { echo "错误: git fetch origin 失败。" >&2; return 1; }
  if git rev-parse --verify origin/master >/dev/null 2>&1; then
    merge_ref="origin/master"
  elif git rev-parse --verify origin/main >/dev/null 2>&1; then
    merge_ref="origin/main"
  else
    echo "错误: 未找到 origin/master 或 origin/main，无法自动合并。" >&2
    return 1
  fi
  if ! git merge -m "merge ${merge_ref} for yunxiao deploy" "$merge_ref"; then
    echo "错误: 合并失败或存在冲突，请手动解决后 push 再重新部署。" >&2
    return 1
  fi
  if ! git push; then
    echo "错误: git push 失败，请检查远端权限或上游分支。" >&2
    return 1
  fi
  return 0
}

open_result_url_if_any() {
  local result="$1"
  if [[ "$result" == http* ]]; then
    command -v open >/dev/null 2>&1 && open "$result" 2>/dev/null || true
    command -v xdg-open >/dev/null 2>&1 && xdg-open "$result" 2>/dev/null || true
  fi
}

call_deploy() {
  local env_id="$1" dep_type="$2" env_type="$3"
  local payload dep code result msg vip_retried merge_retried yn
  vip_retried=0
  merge_retried=0

  while true; do
    export EID="$env_id" DT="$dep_type" ET="$env_type" PJ="$PROJECTS_JSON"
    payload=$(python3 -c "import json,os; p=json.loads(os.environ['PJ']); print(json.dumps({'envId':str(os.environ['EID']),'deployType':int(os.environ['DT']),'envType':int(os.environ['ET']),'projects':p}))")
    unset EID DT ET PJ
    dep=$(curl -sS -X POST "$DEPLOY_URL" -H "Content-Type: application/json" -H "token: $TOKEN" -d "$payload")
    echo "$dep"
    code=$(echo "$dep" | python3 -c "import json,sys; print(json.load(sys.stdin).get('code',''))" 2>/dev/null || echo "")
    result=$(echo "$dep" | python3 -c "import json,sys; print(json.load(sys.stdin).get('result','') or '')" 2>/dev/null || echo "")
    msg=$(echo "$dep" | python3 -c "import json,sys; print(json.load(sys.stdin).get('msg','') or '')" 2>/dev/null || echo "")

    if [ "$code" = "0" ]; then
      open_result_url_if_any "$result"
      return 0
    fi

    [ -n "$msg" ] && echo "$msg" >&2
    echo "部署触发失败（code 非 0）。若 result 为链接将尝试打开以便到平台查看。" >&2
    open_result_url_if_any "$result"

    if [ "$vip_retried" = "0" ] && msg_match_vip_quota "$msg"; then
      if [ -t 0 ]; then
        read -r -p "检测到可能与 VIP/配额相关。是否不使用 VIP 再次部署？(y/n): " yn || true
        if [[ "$yn" =~ ^[Yy]$ ]]; then
          PROJECTS_JSON=$(projects_add_vip_flg_zero)
          vip_retried=1
          echo "已为本轮 projects 各工程增加 vipFlg=0，重新调用部署接口…" >&2
          continue
        fi
      else
        echo "（非交互终端）跳过「不使用 VIP 重试」询问；可手动加 vipFlg:0 后重试。" >&2
      fi
    fi

    if [ "$merge_retried" = "0" ] && msg_match_merge_master "$msg"; then
      echo "尝试拉取并合并远端 master/main 后 push，然后再次部署…" >&2
      if git_merge_origin_default_and_push; then
        merge_retried=1
        continue
      fi
    fi

    break
  done
  return 1
}

# 步骤 2：新建环境 + 步骤 3：部署（不依赖 create_env.sh）
create_env_then_deploy() {
  local suggested env_name adopt dtp body cr id dt
  suggested=$(python3 -c "import json,sys; p=json.loads(sys.argv[1]); x=p[0]; print(x['groupName']+'_'+x['projectName']+'_'+x['branchName'])" "$PROJECTS_JSON")
  read -r -p "建议环境名: $suggested 是否采纳？(y/n): " adopt
  if [[ "$adopt" =~ ^[Yy]$ ]]; then
    env_name="$suggested"
  else
    read -r -p "请输入环境名: " env_name
    [ -z "$env_name" ] && env_name="$suggested"
  fi
  read -r -p "环境类型：1=沙箱，0=测试: " dtp
  [[ "$dtp" =~ ^(0|1)$ ]] || { echo "错误: 请输入 0 或 1" >&2; exit 1; }
  export _EN="$env_name" _PJ="$PROJECTS_JSON" _DT="$dtp"
  body=$(python3 -c "import json,os; p=json.loads(os.environ['_PJ']); print(json.dumps({'envName':os.environ['_EN'],'deployType':int(os.environ['_DT']),'envType':0,'projects':p}))")
  unset _EN _PJ _DT
  cr=$(curl -sS -X POST "$CREATE_ENV_URL" -H "Content-Type: application/json" -H "token: $TOKEN" -d "$body")
  echo "$cr"
  if ! echo "$cr" | python3 -c "import json,sys; import sys as s; j=json.load(sys.stdin); s.exit(0 if j.get('code')==0 else 1)" 2>/dev/null; then
    echo "创建环境失败，请到云效平台手动创建。" >&2
    exit 1
  fi
  lines=$(parse_create_result "$cr") || exit 1
  id=$(echo "$lines" | head -1)
  dt=$(echo "$lines" | tail -1)
  echo "创建成功，正在部署 envId=$id deployType=$dt …" >&2
  call_deploy "$id" "$dt" "0"
}

resolve_token
build_projects_json

if [ "$MODE" = "create-env" ]; then
  create_env_then_deploy
  exit 0
fi

# --- mode deploy：步骤 1 环境列表 ---
ENV_LIST_RESP=$(curl -sS -X POST "$GET_ENV_URL" -H "Content-Type: application/json" -H "token: $TOKEN" -d "$PROJECTS_JSON")
echo "$ENV_LIST_RESP"

ITEMS=$(echo "$ENV_LIST_RESP" | python3 -c "import json,sys; r=json.load(sys.stdin); print(len(r.get('result') or []))" 2>/dev/null || echo "0")

if [ "$ITEMS" = "0" ] || [ -z "$ITEMS" ]; then
  read -r -p "环境列表为空，是否创建新环境？(y/n): " yn
  if [[ "$yn" =~ ^[Yy]$ ]]; then
    create_env_then_deploy
  fi
  exit 0
fi

echo "$ENV_LIST_RESP" | python3 -c "
import json, sys
r = json.load(sys.stdin)
items = r.get('result') or []
print('可选环境（序号 | name | 类型 | 部署类型）')
for i, it in enumerate(items, 1):
    name = it.get('name', '')
    et = '环境' if it.get('envType') == 0 else '构建计划'
    dt = it.get('deployType')
    ds = '沙箱' if dt == 1 else '测试' if dt == 0 else str(dt)
    print(f'{i}\t{name}\t{et}\t{ds}')
"

read -r -p "请选择序号（或输入 n 表示没有合适环境）: " CHOICE
if [[ "$CHOICE" =~ ^[Nn]$ ]]; then
  read -r -p "是否创建新环境？(y/n): " yn
  if [[ "$yn" =~ ^[Yy]$ ]]; then
    create_env_then_deploy
  fi
  exit 0
fi

if ! [[ "$CHOICE" =~ ^[0-9]+$ ]]; then
  echo "错误: 无效序号" >&2
  exit 1
fi

SEL=$(echo "$ENV_LIST_RESP" | python3 -c "import json,sys; r=json.load(sys.stdin); a=r.get('result') or []; i=int(sys.argv[1])-1; print(json.dumps(a[i]) if 0<=i<len(a) else '')" "$CHOICE")
[ -n "$SEL" ] && [ "$SEL" != "null" ] || { echo "错误: 序号超出范围" >&2; exit 1; }

EID=$(echo "$SEL" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))")
ET=$(echo "$SEL" | python3 -c "import json,sys; print(json.load(sys.stdin).get('envType',''))")
DT=$(echo "$SEL" | python3 -c "import json,sys; print(json.load(sys.stdin).get('deployType',''))")

call_deploy "$EID" "$DT" "$ET"
