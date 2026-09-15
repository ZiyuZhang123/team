#!/bin/bash

# This script calls the API to create a work item.

# Function to display usage
usage() {
    echo "用法: $0 --title <标题> --content <内容> --type <类型> [--token <令牌>]"
    echo "  <title>: 工作项的标题"
    echo "  <content>: 工作项的详细内容"
    echo "  <type>: 工作项的类型 (2:需求, 3:缺陷/bug, 4:任务)"
    echo "  <token>: 认证令牌（token）。如果未提供，将从 YUNXIAO_SKILL_TOKEN 环境变量中读取，或提示您输入。"
    exit 1
}

# Constants
API_URL="http://ee-api.58dns.org/skill/api-yunxiao-iwork/work/saveWorkItem"
VERSION="1.0.8"

# Parse command-line arguments
TITLE=""
CONTENT=""
TYPE=""
TOKEN=""

while (( "$#" )); do
    case "$1" in
        --title)
            if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                TITLE=$2
                shift 2
            else
                echo "错误: --title 参数缺少值。" >&2
                usage
            fi
            ;;
        --content)
            if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                CONTENT=$2
                shift 2
            else
                echo "错误: --content 参数缺少值。" >&2
                usage
            fi
            ;;
        --type)
            if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                TYPE=$2
                shift 2
            else
                echo "错误: --type 参数缺少值。" >&2
                usage
            fi
            ;;
        --token)
            if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                TOKEN=$2
                shift 2
            else
                # This allows providing --token without a value, which might be cleared later
                shift 1
            fi
            ;;
        -?*)
            echo "错误: 未知选项: $1" >&2
            usage
            ;;
        *)
            echo "错误: 未知参数: $1" >&2
            usage
            ;;
    esac
done

# Check for required arguments
if [ -z "$TITLE" ] || [ -z "$CONTENT" ]; then
    echo "错误: 缺少必需参数: --title 和 --content 是必需的。" >&2
    usage
fi

# Handle the token
# Priority: --token argument > YUNXIAO_SKILL_TOKEN env var > interactive prompt.
if [ -z "$TOKEN" ]; then
    TOKEN=$YUNXIAO_SKILL_TOKEN
fi

# If token is still empty, prompt for it.
if [ -z "$TOKEN" ]; then
    echo "在环境变量中未找到令牌, 将提示输入..."
    read -p "请输入您的令牌（token）: " TOKEN
fi

# If token is still empty after all that, exit.
if [ -z "$TOKEN" ]; then
    echo "错误: 令牌（token）是必需的。" >&2
    exit 1
fi

# Handle the type
if [[ ! "$TYPE" =~ ^(2|3|4)$ ]]; then
    echo "错误: --type 无效或缺失。请输入一个有效的类型。"
    PS3="请选择工作项的类型: "
    options=("需求" "缺陷/bug" "任务")
    select opt in "${options[@]}"; do
        case $REPLY in
            1) TYPE=2; break;;
            2) TYPE=3; break;;
            3) TYPE=4; break;;
            *) echo "无效选项。请重试。";;
        esac
    done
fi


# Ensure 'curl' is installed
if ! command -v curl &> /dev/null; then
    echo "错误: 'curl' 未安装。请安装 'curl' 以使用此脚本。" >&2
    exit 1
fi

# Manually construct JSON payload (token is now in header)
TITLE_ESC=${TITLE//\\/\\\\}
TITLE_ESC=${TITLE_ESC//\"/\\\"}
TITLE_ESC=${TITLE_ESC//$'\n'/\\n}
CONTENT_ESC=${CONTENT//\\/\\\\}
CONTENT_ESC=${CONTENT_ESC//\"/\\\"}
CONTENT_ESC=${CONTENT_ESC//$'\n'/\\n}
TYPE_ESC=${TYPE//\\/\\\\}
TYPE_ESC=${TYPE_ESC//\"/\\\"}
TYPE_ESC=${TYPE_ESC//$'\n'/\\n}
VERSION_ESC=${VERSION//\\/\\\\}
VERSION_ESC=${VERSION_ESC//\"/\\\"}
VERSION_ESC=${VERSION_ESC//$'\n'/\\n}

JSON_PAYLOAD=$(printf '{"title":"%s","content":"%s","type":%s,"version":"%s"}' "$TITLE_ESC" "$CONTENT_ESC" "$TYPE_ESC" "$VERSION_ESC")

printf "JSON 数据: %s\n" "$JSON_PAYLOAD"

# Make the API call using curl
# The token is now passed in a custom header "token"
RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -H "token: $TOKEN" -d "$JSON_PAYLOAD" "$API_URL")

printf "API 响应: %s\n" "$RESPONSE"
# Check if curl command was successful
if [ $? -ne 0 ]; then
    echo "错误: 使用 'curl' 调用 API 失败。" >&2
    exit 1
fi

# Parse the response using sed
CODE=$(echo "$RESPONSE" | sed -n 's/.*"code":\s*\([0-9][0-9]*\).*/\1/p')
DATA=$(echo "$RESPONSE" | sed -n 's/.*"data":"\([^"]*\)".*/\1/p')

if [ "$CODE" == "200" ]; then
    echo "✅ 操作成功！"
    echo "工作项草稿已保存至云效。"
    echo "请务必点击下面的链接，在云效平台完成最终创建："
    echo "$DATA"
else
    echo "创建工作项失败。API 响应: $RESPONSE"
    exit 1
fi
