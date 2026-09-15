#!/bin/sh

API_TRIGGER="http://ee-api.58dns.org/skill/api-yunxiao-ici/SkillService/runFlowBeta"
API_FLOW_LIST="http://ee-api.58dns.org/skill/api-yunxiao-ici/SkillService/getFlowList"

ACTION=""
FLOW_ID=""
URL_INPUT=""
TOKEN=""
LIMIT_NUM=5

usage() {
    cat <<'EOF'
Usage:
  beta_executor.sh trigger --flow-id <id>|--url <streams-url> [--token <token>]
  beta_executor.sh list [--limit-num <n>] [--token <token>]
EOF
    exit 1
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Error: '$1' is required." >&2
        exit 1
    fi
}

normalize_response() {
    flat=$(printf '%s' "$1" | tr -d '\n')

    if printf '%s' "$flat" | grep -q '"data":"{'; then
        inner=$(printf '%s' "$flat" | sed -n 's/.*"data":"\(.*\)".*/\1/p')
        printf '%s' "$inner" | sed 's/\\"/"/g; s/\\\\/\\/g'
        return
    fi

    if printf '%s' "$flat" | grep -q '"data":{'; then
        inner=$(printf '%s' "$flat" | sed -n 's/.*"data":\({.*}\).*/\1/p')
        printf '%s' "$inner"
        return
    fi

    printf '%s' "$flat"
}

extract_number() {
    printf '%s' "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\\(-\{0,1\}[0-9][0-9]*\\).*/\\1/p"
}

extract_string() {
    printf '%s' "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | sed 's/\\u003d/=/g; s/\\u0026/\&/g; s/\\u003f/?/g; s/\\u002f/\//g'
}

call_api() {
    _url=$1
    _payload=$2
    curl -sS -X POST \
        -H "Content-Type: application/json" \
        -H "token: $TOKEN" \
        -d "$_payload" \
        "$_url"
}

extract_flow_id() {
    if [ -n "$FLOW_ID" ]; then
        return
    fi

    if [ -n "$URL_INPUT" ]; then
        case "$URL_INPUT" in
            *"/base2/c/release/canals/"*)
                echo "Error: formal release pipelines are not supported by this skill." >&2
                exit 1
                ;;
            *"/base2/c/streams/operation-lib"*)
                echo "Error: component pipelines are not supported by this skill." >&2
                exit 1
                ;;
        esac

        FLOW_ID=$(printf '%s' "$URL_INPUT" | sed -n 's#.*\/base2\/c\/streams\/\([0-9][0-9]*\)\(/auto\)\{0,1\}.*#\1#p')
        if [ -z "$FLOW_ID" ]; then
            echo "Error: unsupported standard pipeline URL: $URL_INPUT" >&2
            exit 1
        fi
        return
    fi

    echo "Error: --flow-id or --url is required." >&2
    exit 1
}

resolve_token() {
    if [ -z "$TOKEN" ]; then
        TOKEN=$YUNXIAO_SKILL_TOKEN
    fi

    if [ -z "$TOKEN" ]; then
        printf 'YUNXIAO_SKILL_TOKEN not found. Apply for a Yunxiao token at https://ee.58corp.com/base2/openapi/skillsToken/page, then input token: '
        IFS= read -r TOKEN
    fi

    if [ -z "$TOKEN" ]; then
        echo "Error: token is required before calling the API. Apply at https://ee.58corp.com/base2/openapi/skillsToken/page" >&2
        exit 1
    fi
}

trigger_run() {
    extract_flow_id
    payload=$(printf '{"flowId":%s}' "$FLOW_ID")
    response=$(call_api "$API_TRIGGER" "$payload") || exit 1
    response=$(normalize_response "$response")

    resp_code=$(extract_number "$response" "respCode")
    err_msg=$(extract_string "$response" "errMsg")
    resp_data=$(extract_string "$response" "respData")

    if [ "$resp_code" != "0" ]; then
        echo "Trigger failed: ${err_msg:-$response}" >&2
        exit 1
    fi

    echo "Trigger succeeded."
    echo "flowId=$FLOW_ID"
    echo "message=${resp_data:-触发成功}"
}

list_run() {
    payload=$(printf '{"flowType":4,"limitNum":%s}' "$LIMIT_NUM")
    response=$(call_api "$API_FLOW_LIST" "$payload") || exit 1
    response=$(normalize_response "$response")

    resp_code=$(extract_number "$response" "respCode")
    err_msg=$(extract_string "$response" "errMsg")

    if [ "$resp_code" != "0" ]; then
        echo "List failed: ${err_msg:-$response}" >&2
        exit 1
    fi

    echo "List succeeded (flowType=4, limitNum=$LIMIT_NUM)."

    if command -v jq >/dev/null 2>&1; then
        if ! printf '%s' "$response" | jq -r '
          (if (.respData | type) == "string" then (.respData | fromjson) else .respData end) as $rows |
          "flowId\tflowName\tprodOs\tprodName\t最后构建时间",
          ($rows[] | [.flowId, .flowName, .prodOs, .prodName, .CreateTime] | @tsv)
        ' 2>/dev/null; then
            echo "respData_JSON=$(printf '%s' "$response" | tr -d '\n')"
            echo "Warning: could not render TSV from response; use respData_JSON above."
        fi
    else
        echo "respData_JSON=$(printf '%s' "$response" | tr -d '\n')"
        echo "(Install jq for a TSV table, or let the agent parse respData_JSON.)"
    fi
}

if [ $# -lt 1 ]; then
    usage
fi

ACTION=$1
shift

while [ $# -gt 0 ]; do
    case "$1" in
        --flow-id)
            FLOW_ID=$2
            shift 2
            ;;
        --url)
            URL_INPUT=$2
            shift 2
            ;;
        --token)
            TOKEN=$2
            shift 2
            ;;
        --limit-num)
            LIMIT_NUM=$2
            shift 2
            ;;
        *)
            echo "Error: unknown argument $1" >&2
            usage
            ;;
    esac
done

require_command curl
require_command sed
require_command grep
resolve_token

case "$ACTION" in
    trigger)
        trigger_run
        ;;
    list)
        list_run
        ;;
    *)
        echo "Error: unknown action '$ACTION'" >&2
        usage
        ;;
esac
