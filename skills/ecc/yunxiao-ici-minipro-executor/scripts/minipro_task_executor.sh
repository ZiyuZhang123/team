#!/bin/sh

API_TRIGGER="http://ee-api.58dns.org/skill/api-yunxiao-ici/SkillService/miniProAutoRun"
API_STATUS="http://ee-api.58dns.org/skill/api-yunxiao-ici/SkillService/miniProAutoRunStatus"
API_RESULT="http://ee-api.58dns.org/skill/api-yunxiao-ici/SkillService/miniProAutoRunResult"
API_FLOW_LIST="http://ee-api.58dns.org/skill/api-yunxiao-ici/SkillService/getFlowList"

ACTION=""
FLOW_ID=""
TASK_ID=""
URL_INPUT=""
TOKEN=""
VERSION=""
VERSION_DESC=""
POLL_INTERVAL="10"
TIMEOUT_SECONDS="1800"
LIMIT_NUM=5

usage() {
    cat <<'EOF'
Usage:
  minipro_task_executor.sh list [--limit-num <n>] [--token <token>]
  minipro_task_executor.sh trigger --flow-id <id>|--url <streams-url> [--version <v>] [--version-desc <desc>] [--token <token>]
  minipro_task_executor.sh status --flow-id <id>|--url <streams-url> --task-id <id> [--token <token>]
  minipro_task_executor.sh result --flow-id <id>|--url <streams-url> --task-id <id> [--token <token>]
  minipro_task_executor.sh auto --flow-id <id>|--url <streams-url> [--version <v>] [--version-desc <desc>] [--token <token>] [--poll-interval <seconds>] [--timeout <seconds>]
EOF
    exit 1
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Error: '$1' is required." >&2
        exit 1
    fi
}

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
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
    value=$(printf '%s' "$1" | tr -d '\n' | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p")
    if [ -z "$value" ]; then
        value=$(printf '%s' "$1" | tr -d '\n' | sed -n "s/.*\"$2:\"[[:space:]]*:[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p")
    fi
    printf '%s' "$value"
}

extract_string() {
    value=$(printf '%s' "$1" | tr -d '\n' | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p")
    if [ -z "$value" ]; then
        value=$(printf '%s' "$1" | tr -d '\n' | sed -n "s/.*\"$2:\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p")
    fi
    printf '%s' "$value" | sed 's/\\u003d/=/g; s/\\u0026/\&/g; s/\\u003f/?/g; s/\\u002f/\//g'
}

extract_first_qrcode() {
    printf '%s' "$1" | tr -d '\n' | grep -o '"qrcodeUrl"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 | sed 's/.*"qrcodeUrl"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
}

resolve_flow_id() {
    if [ -n "$FLOW_ID" ]; then
        return
    fi

    if [ -n "$URL_INPUT" ]; then
        FLOW_ID=$(printf '%s' "$URL_INPUT" | sed -n 's#.*\/base2\/c\/streams\/\([0-9][0-9]*\).*#\1#p')
        if [ -z "$FLOW_ID" ]; then
            echo "Error: unsupported mini program pipeline URL (must contain /base2/c/streams/<flowId>): $URL_INPUT" >&2
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

call_api() {
    endpoint=$1
    payload=$2

    curl -sS -X POST \
        -H "Content-Type: application/json" \
        -H "token: $TOKEN" \
        -d "$payload" \
        "$endpoint"
}

status_label() {
    case "$1" in
        0) printf '%s' "not_started" ;;
        1) printf '%s' "running" ;;
        2) printf '%s' "finished" ;;
        *) printf '%s' "unknown" ;;
    esac
}

list_run() {
    payload=$(printf '{"flowType":1,"limitNum":%s}' "$LIMIT_NUM")
    response=$(call_api "$API_FLOW_LIST" "$payload") || exit 1
    response=$(normalize_response "$response")

    resp_code=$(extract_number "$response" "respCode")
    err_msg=$(extract_string "$response" "errMsg")

    if [ "$resp_code" != "0" ]; then
        echo "List failed: ${err_msg:-$response}" >&2
        exit 1
    fi

    echo "List succeeded (flowType=1, limitNum=$LIMIT_NUM)."

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

trigger_run() {
    version_part=""
    version_desc_part=""

    if [ -n "$VERSION" ]; then
        version_part=$(printf ',"version":"%s"' "$(json_escape "$VERSION")")
    fi

    if [ -n "$VERSION_DESC" ]; then
        version_desc_part=$(printf ',"versionDesc":"%s"' "$(json_escape "$VERSION_DESC")")
    fi

    payload=$(printf '{"flowId":%s%s%s}' "$FLOW_ID" "$version_part" "$version_desc_part")
    response=$(call_api "$API_TRIGGER" "$payload") || exit 1
    response=$(normalize_response "$response")

    resp_code=$(extract_number "$response" "respCode")
    err_msg=$(extract_string "$response" "errMsg")

    if [ "$resp_code" != "0" ]; then
        echo "Trigger failed: ${err_msg:-$response}" >&2
        exit 1
    fi

    task_id=$(extract_number "$response" "taskId")
    msg=$(extract_string "$response" "msg")
    returned_flow_id=$(extract_number "$response" "flowId")

    echo "Trigger succeeded."
    echo "flowId=$returned_flow_id"
    echo "taskId=$task_id"
    echo "message=${msg:-submitted}"
}

get_status_raw() {
    payload=$(printf '{"flowId":%s,"taskId":%s}' "$FLOW_ID" "$TASK_ID")
    call_api "$API_STATUS" "$payload"
}

show_status() {
    response=$(get_status_raw) || exit 1
    response=$(normalize_response "$response")
    resp_code=$(extract_number "$response" "respCode")
    err_msg=$(extract_string "$response" "errMsg")

    if [ "$resp_code" != "0" ]; then
        echo "Status query failed: ${err_msg:-$response}" >&2
        exit 1
    fi

    status=$(extract_number "$response" "status")
    returned_task_id=$(extract_number "$response" "taskId")
    returned_flow_id=$(extract_number "$response" "flowId")

    echo "Status query succeeded."
    echo "flowId=$returned_flow_id"
    echo "taskId=$returned_task_id"
    echo "status=$status"
    echo "statusLabel=$(status_label "$status")"
}

require_finished() {
    response=$(get_status_raw) || exit 1
    response=$(normalize_response "$response")
    resp_code=$(extract_number "$response" "respCode")
    err_msg=$(extract_string "$response" "errMsg")

    if [ "$resp_code" != "0" ]; then
        echo "Status query failed: ${err_msg:-$response}" >&2
        exit 1
    fi

    status=$(extract_number "$response" "status")
    if [ "$status" != "2" ]; then
        echo "Task is not finished yet. Current status=$status ($(status_label "$status"))." >&2
        exit 1
    fi
}

show_result() {
    require_finished
    payload=$(printf '{"flowId":%s,"taskId":%s}' "$FLOW_ID" "$TASK_ID")
    response=$(call_api "$API_RESULT" "$payload") || exit 1
    response=$(normalize_response "$response")

    resp_code=$(extract_number "$response" "respCode")
    err_msg=$(extract_string "$response" "errMsg")

    if [ "$resp_code" != "0" ]; then
        echo "Result query failed: ${err_msg:-$response}" >&2
        exit 1
    fi

    qrcode_url=$(extract_first_qrcode "$response")
    log_url=$(extract_string "$response" "logUrl")
    detail_url=$(extract_string "$response" "detailUrl")

    echo "Result query succeeded."
    if [ -n "$qrcode_url" ]; then
        echo "qrcodeUrl=$qrcode_url"
    else
        echo "qrcodeUrl="
    fi
    if [ -n "$log_url" ]; then
        echo "logUrl=$log_url"
    fi
    if [ -n "$detail_url" ]; then
        echo "detailUrl=$detail_url"
    fi
}

auto_run() {
    trigger_output=$(trigger_run) || exit 1
    printf '%s\n' "$trigger_output"
    TASK_ID=$(printf '%s\n' "$trigger_output" | sed -n 's/^taskId=\([0-9][0-9]*\)$/\1/p')

    if [ -z "$TASK_ID" ]; then
        echo "Error: failed to parse taskId from trigger response." >&2
        exit 1
    fi

    elapsed=0
    while [ "$elapsed" -le "$TIMEOUT_SECONDS" ]; do
        response=$(get_status_raw) || exit 1
        response=$(normalize_response "$response")
        resp_code=$(extract_number "$response" "respCode")
        err_msg=$(extract_string "$response" "errMsg")

        if [ "$resp_code" != "0" ]; then
            echo "Status query failed while waiting: ${err_msg:-$response}" >&2
            exit 1
        fi

        status=$(extract_number "$response" "status")
        echo "Polling status: $status ($(status_label "$status")) after ${elapsed}s"

        if [ "$status" = "2" ]; then
            show_result
            return
        fi

        sleep "$POLL_INTERVAL"
        elapsed=$((elapsed + POLL_INTERVAL))
    done

    echo "Error: timed out after ${TIMEOUT_SECONDS}s waiting for the task to finish." >&2
    exit 1
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
        --task-id)
            TASK_ID=$2
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
        --version)
            VERSION=$2
            shift 2
            ;;
        --version-desc)
            VERSION_DESC=$2
            shift 2
            ;;
        --poll-interval)
            POLL_INTERVAL=$2
            shift 2
            ;;
        --timeout)
            TIMEOUT_SECONDS=$2
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
    list)
        list_run
        ;;
    trigger)
        resolve_flow_id
        trigger_run
        ;;
    status)
        resolve_flow_id
        [ -n "$TASK_ID" ] || { echo "Error: --task-id is required for status." >&2; exit 1; }
        show_status
        ;;
    result)
        resolve_flow_id
        [ -n "$TASK_ID" ] || { echo "Error: --task-id is required for result." >&2; exit 1; }
        show_result
        ;;
    auto)
        resolve_flow_id
        auto_run
        ;;
    *)
        echo "Error: unknown action '$ACTION'" >&2
        usage
        ;;
esac
