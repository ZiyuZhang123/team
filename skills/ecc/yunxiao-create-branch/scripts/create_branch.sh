#!/bin/bash
set -euo pipefail

# Ensure Chinese text in API responses is displayed correctly.
export LANG="${LANG:-zh_CN.UTF-8}"
export LC_ALL="${LC_ALL:-zh_CN.UTF-8}"
export PYTHONIOENCODING="${PYTHONIOENCODING:-utf-8}"

usage() {
  echo "用法: $0 (--use-current-branch | --new-branch --branch-name <name>) --work-base-ids <ids|\"\"> --is-branch-delete <0|1> [--token <token>]"
  echo "  --use-current-branch       使用当前本地分支名，isBranchExist=1"
  echo "  --new-branch               创建新分支，isBranchExist=0"
  echo "  --branch-name <name>        新分支名（仅在 --new-branch 时必填）"
  echo "  --work-base-ids <ids|\"\">   关联工作项ID（逗号分隔）；不关联可为空字符串"
  echo "  --is-branch-delete <0|1>    删除分支时是否删除远端分支"
  echo "  --token <token>             认证 token（可用环境变量 YUNXIAO_SKILL_TOKEN）"
  exit 1
}

TOKEN=""
MODE=""
BRANCH_NAME=""
WORK_BASE_IDS=""
WORK_BASE_IDS_SET=0
IS_BRANCH_DELETE=""
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CURRENT_SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
SKILLS_ROOT_DIR=$(cd "$CURRENT_SKILL_DIR/.." && pwd)
WORK_ITEMS_URL="http://ee-api.58dns.org/skill/api-yunxiao-iwork/work/getUserWorkItem"
CREATE_ITEM_SKILL_DIR="$SKILLS_ROOT_DIR/yunxiao-workitem-operate"
CREATE_ITEM_SCRIPT="$CREATE_ITEM_SKILL_DIR/scripts/create_item.sh"
CREATE_ITEM_DOWNLOAD_URL="http://skill-market.58dns.org/api/v1/download?slug=yunxiao-workitem-operate"
WORKSPACE_URL="https://ee.58corp.com/base2/workspace"

open_url() {
  local url="$1"
  if command -v open >/dev/null 2>&1; then
    open "$url" >/dev/null 2>&1 || true
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 || true
  fi
}

ensure_token() {
  if [ -n "$TOKEN" ]; then
    return 0
  fi

  if [ -n "${YUNXIAO_SKILL_TOKEN:-}" ]; then
    TOKEN="$YUNXIAO_SKILL_TOKEN"
  else
    if [ -f "$HOME/.zshrc" ]; then
      . "$HOME/.zshrc"
    fi
    if [ -n "${YUNXIAO_SKILL_TOKEN:-}" ]; then
      TOKEN="$YUNXIAO_SKILL_TOKEN"
    else
      echo "未检测到 YUNXIAO_SKILL_TOKEN。"
      echo "如果你没有 token 或不知道什么是 token，请先到以下链接申请："
      echo "https://ee.58corp.com/base2/t/apply/common/addToken"
      read -p "请输入 token（留空表示暂不处理）: " TOKEN
    fi
  fi

  if [ -z "$TOKEN" ]; then
    echo "错误: 未提供 token。请先前往 https://ee.58corp.com/base2/t/apply/common/addToken 申请后重试。" >&2
    exit 1
  fi

  export YUNXIAO_SKILL_TOKEN="$TOKEN"

  if [ -n "${HOME:-}" ]; then
    ZSHRC="$HOME/.zshrc"
    if [ -f "$ZSHRC" ]; then
      if ! grep -q "YUNXIAO_SKILL_TOKEN" "$ZSHRC"; then
        dprintf '\nexport YUNXIAO_SKILL_TOKEN="%s"\n' "$TOKEN" >> "$ZSHRC"
      fi
    fi
  fi
}

download_create_item_skill() {
  if [ -x "$CREATE_ITEM_SCRIPT" ]; then
    return 0
  fi

  local tmp_dir zip_file
  tmp_dir=$(mktemp -d)
  zip_file="$tmp_dir/yunxiao-workitem-operate.zip"

  if ! curl -sS "$CREATE_ITEM_DOWNLOAD_URL" -o "$zip_file"; then
    return 1
  fi

  if ! command -v unzip >/dev/null 2>&1; then
    return 1
  fi

  if ! unzip -q "$zip_file" -d "$tmp_dir"; then
    return 1
  fi

  mkdir -p "$SKILLS_ROOT_DIR"

  if [ -d "$tmp_dir/yunxiao-workitem-operate" ]; then
    cp -R "$tmp_dir/yunxiao-workitem-operate" "$SKILLS_ROOT_DIR/"
  else
    local extracted
    extracted=$(find "$tmp_dir" -maxdepth 2 -type d -name 'yunxiao-workitem-operate' | head -n 1)
    if [ -z "$extracted" ]; then
      return 1
    fi
    cp -R "$extracted" "$SKILLS_ROOT_DIR/"
  fi

  [ -x "$CREATE_ITEM_SCRIPT" ]
}

search_work_items() {
  local keyword="$1"
  curl -sS -X POST "$WORK_ITEMS_URL" \
    -H "Content-Type: application/json" \
    -H "token: $TOKEN" \
    -d "{\"keyword\":\"$keyword\"}"
}

write_work_items_file() {
  local response="$1"
  local items_file="$2"
  printf '%s' "$response" | python3 - "$items_file" <<'PY'
import json, sys
resp = json.load(sys.stdin)
items = None
if isinstance(resp, dict):
    data = resp.get("data", resp.get("result", resp))
    if isinstance(data, dict):
        for k in ("data", "list", "items", "result"):
            if isinstance(data.get(k), list):
                items = data.get(k)
                break
    elif isinstance(data, list):
        items = data
if items is None:
    items = []
with open(sys.argv[1], "w", encoding="utf-8") as f:
    for i, it in enumerate(items, 1):
        view_id = it.get("viewId") or it.get("view_id") or ""
        title = it.get("title") or it.get("name") or ""
        item_id = it.get("id") or it.get("workItemId") or ""
        f.write(f"{i}\t{item_id}\t{view_id}\t{title}\n")
PY
}

create_new_work_item() {
  if [ ! -x "$CREATE_ITEM_SCRIPT" ]; then
    echo "本地未安装 yunxiao-workitem-operate，尝试下载安装。"
    if ! download_create_item_skill; then
      echo "下载 yunxiao-workitem-operate 失败，请到平台手工创建工作项：$WORKSPACE_URL"
      open_url "$WORKSPACE_URL"
      return 1
    fi
  fi

  local title content type
  read -p "请输入工作项标题: " title
  read -p "请输入工作项描述: " content
  read -p "请输入工作项类型（2=需求, 3=缺陷/bug, 4=任务）: " type
  "$CREATE_ITEM_SCRIPT" --title "$title" --content "$content" --type "$type" --token "$TOKEN" || return 1
}

collect_work_base_ids() {
  local keyword="" resp items_file choice ids line item_id create_item_done
  while true; do
    read -p "请输入工作项关键词（可为空，也可输入 id、viewId 或描述）: " keyword
    resp=$(search_work_items "$keyword")
    items_file=$(mktemp)
    if ! write_work_items_file "$resp" "$items_file"; then
      echo "错误: 工作项列表返回无法解析，请稍后重试。" >&2
      rm -f "$items_file"
      exit 1
    fi

    if [ ! -s "$items_file" ]; then
      echo "未找到工作项。"
      read -p "是否需要帮你创建一个新的工作项？(y/n): " create_item_done
      if [[ "$create_item_done" =~ ^[Yy]$ ]]; then
        if ! create_new_work_item; then
          echo "请在平台创建工作项后继续。"
        fi
        read -p "是否已创建完成工作项？(y/n): " create_item_done
        rm -f "$items_file"
        if [[ "$create_item_done" =~ ^[Yy]$ ]]; then
          continue
        fi
      fi
      read -p "请输入 workBaseIds（逗号分隔，留空表示不关联）: " WORK_BASE_IDS
      rm -f "$items_file"
      break
    fi

    echo "工作项列表："
    awk -F '\t' '{printf "%s. %s\t%s\n", $1, $3, $4}' "$items_file"
    read -p "请输入要关联的序号（可多个，用逗号分隔；无匹配请输入 n）: " choice
    if [[ "$choice" =~ ^[Nn]$ ]]; then
      rm -f "$items_file"
      read -p "请输入新的检索内容（可输入 id、viewId 或描述）: " keyword
      if [ -n "$keyword" ]; then
        resp=$(search_work_items "$keyword")
        items_file=$(mktemp)
        if ! write_work_items_file "$resp" "$items_file"; then
          echo "错误: 工作项列表返回无法解析，请稍后重试。" >&2
          rm -f "$items_file"
          exit 1
        fi
        if [ -s "$items_file" ]; then
          echo "工作项列表："
          awk -F '\t' '{printf "%s. %s\t%s\n", $1, $3, $4}' "$items_file"
          read -p "请输入要关联的序号（可多个，用逗号分隔；无匹配请输入手工 workBaseIds）: " choice
        else
          rm -f "$items_file"
          read -p "请输入 workBaseIds（逗号分隔，留空表示不关联）: " WORK_BASE_IDS
          break
        fi
      else
        continue
      fi
    fi

    ids=""
    IFS=',' read -r -a arr <<< "$choice"
    for idx in "${arr[@]}"; do
      idx=$(echo "$idx" | xargs)
      line=$(sed -n "${idx}p" "$items_file" || true)
      item_id=$(echo "$line" | awk -F '\t' '{print $2}')
      if [ -n "$item_id" ]; then
        ids="${ids}${item_id},"
      fi
    done
    ids=${ids%,}
    rm -f "$items_file"

    if [ -n "$ids" ]; then
      WORK_BASE_IDS="$ids"
      break
    fi

    read -p "未选择到有效工作项，请直接输入 workBaseIds（逗号分隔，留空表示不关联）: " WORK_BASE_IDS
    break
  done
}

while (( "$#" )); do
  case "$1" in
    --token)
      TOKEN=${2:-""}
      shift 2
      ;;
    --use-current-branch)
      MODE="current"
      shift 1
      ;;
    --new-branch)
      MODE="new"
      shift 1
      ;;
    --branch-name)
      BRANCH_NAME=${2:-""}
      shift 2
      ;;
    --work-base-ids)
      WORK_BASE_IDS=${2:-""}
      WORK_BASE_IDS_SET=1
      shift 2
      ;;
    --is-branch-delete)
      IS_BRANCH_DELETE=${2:-""}
      shift 2
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

ensure_token

if [ -z "$MODE" ]; then
  echo "错误: 必须指定 --use-current-branch 或 --new-branch。" >&2
  exit 1
fi

if [ "$WORK_BASE_IDS_SET" -ne 1 ]; then
  read -p "是否关联工作项？(y/n): " ASSOCIATE
  if [[ "$ASSOCIATE" =~ ^[Yy]$ ]]; then
    collect_work_base_ids
  else
    WORK_BASE_IDS=""
  fi
fi

if [[ ! "$IS_BRANCH_DELETE" =~ ^(0|1)$ ]]; then
  echo "错误: isBranchDelete 必须为 0 或 1。" >&2
  exit 1
fi

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$ROOT" ]; then
  echo "错误: 当前目录不是 git 仓库。" >&2
  exit 1
fi

REMOTE=$(git remote get-url origin 2>/dev/null || true)
if [ -z "$REMOTE" ]; then
  echo "错误: 找不到 origin 远端，无法解析 groupName/projectName。" >&2
  exit 1
fi

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
  echo "提示: 无法从远端解析 groupName/projectName，请手工输入。" >&2
  read -p "请输入 groupName: " GROUP_NAME
  read -p "请输入 projectName: " PROJECT_NAME
fi

if [ -z "$GROUP_NAME" ] || [ -z "$PROJECT_NAME" ]; then
  echo "错误: groupName/projectName 必填。" >&2
  exit 1
fi

if [ "$MODE" = "current" ]; then
  BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  if [ -z "$BRANCH_NAME" ] || [ "$BRANCH_NAME" = "HEAD" ]; then
    echo "错误: 无法获取当前分支名（可能处于 detached HEAD）。" >&2
    exit 1
  fi
  git push -u origin "$BRANCH_NAME"
  IS_BRANCH_EXIST=1
else
  if [ -z "$BRANCH_NAME" ]; then
    echo "错误: 新建分支时必须提供 --branch-name。" >&2
    exit 1
  fi
  if [[ ! "$BRANCH_NAME" =~ ^[A-Za-z0-9_]+$ ]]; then
    echo "错误: 分支名不能包含特殊字符（仅允许字母、数字、下划线）。" >&2
    exit 1
  fi
  IS_BRANCH_EXIST=0
fi

API_URL="http://ee-api.58dns.org/skill/api-yunxiao-ione/envApi/skill/createBranch"

JSON_PAYLOAD=$(printf '{"groupName":"%s","projectName":"%s","branchName":"%s","workBaseIds":"%s","isBranchExist":%s,"isBranchDelete":%s}' \
  "$GROUP_NAME" "$PROJECT_NAME" "$BRANCH_NAME" "$WORK_BASE_IDS" "$IS_BRANCH_EXIST" "$IS_BRANCH_DELETE")

RESPONSE=$(curl -sS -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "token: $TOKEN" \
  -d "$JSON_PAYLOAD")

echo "$RESPONSE"

if [ "$MODE" = "new" ]; then
  CODE=$(echo "$RESPONSE" | sed -n 's/.*"code":\s*\([0-9][0-9]*\).*/\1/p')
  RESULT=$(echo "$RESPONSE" | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')
  if [ "$CODE" = "0" ] && [ -n "$RESULT" ]; then
    git fetch origin "$RESULT"
    git checkout -b "$RESULT" "origin/$RESULT"
  fi

else
  CODE=$(echo "$RESPONSE" | sed -n 's/.*"code":\s*\([0-9][0-9]*\).*/\1/p')
fi

if [ "$CODE" = "0" ]; then
  LIST_URL="https://ee.58corp.com/base2/o/branch/list"
  open_url "$LIST_URL"
fi
