#!/bin/bash

#
# advanced_create.sh: A multi-purpose script for the advanced work item creation flow.
#

# --- GLOBALS & HELPERS ---

TOKEN=""
BASE_API_URL="http://ee-api.58dns.org/skill/api-yunxiao-iwork/work"

# Function to display usage
usage() {
    echo "Usage: $0 <command> [options]"
    echo "Commands:"
    echo "  search_project  --keyword <keyword>"
    echo "  get_config      --project-id <id> --type <type>"
    echo "  create_item     --payload <json-string>"
    echo ""
    echo "All commands will automatically use the YUNXIAO_SKILL_TOKEN environment variable."
    echo "If the variable is not set, you will be prompted to enter the token."
    exit 1
}

# Ensure 'curl' is installed
if ! command -v curl &> /dev/null; then
    echo "{"error": "'curl' is not installed. Please install 'curl' to use this script."}" >&2
    exit 1
fi

# Function to get the authentication token
# Priority: YUNXIAO_SKILL_TOKEN env var > interactive prompt.
handle_token() {
    if [ -n "$TOKEN" ]; then
        return
    fi

    if [ -n "$YUNXIAO_SKILL_TOKEN" ]; then
        TOKEN=$YUNXIAO_SKILL_TOKEN
    else
        # Since this script might be called by an automated process,
        # it's better to inform the user that a TTY is needed for the prompt.
        if [ -t 0 ]; then
            read -p "YUNXIAO_SKILL_TOKEN not set. Please enter your token: " TOKEN
        else
            echo "{"error": "YUNXIAO_SKILL_TOKEN is not set and no TTY is available for prompt."}" >&2
            exit 1
        fi
    fi

    if [ -z "$TOKEN" ]; then
        echo "{"error": "Token is required but could not be obtained."}" >&2
        exit 1
    fi
}

# --- COMMANDS ---

# 1. Search Project
search_project() {
    KEYWORD=""
    while (( "$#" )); do
        case "$1" in
            --keyword)
                if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                    KEYWORD=$2; shift 2
                else
                    echo "{"error": "--keyword argument is missing a value."}" >&2; usage
                fi
                ;;
            *)
                echo "{"error": "Unknown option for search_project: $1"}" >&2; usage
                ;;
        esac
    done

    if [ -z "$KEYWORD" ]; then
        echo "{"error": "--keyword is required for search_project."}" >&2; usage
    fi
    
    handle_token
    API_URL="$BASE_API_URL/searchProject"
    JSON_PAYLOAD=$(printf '{"keyword":"%s"}' "$KEYWORD")

    curl -s -X POST -H "Content-Type: application/json" -H "token: $TOKEN" -d "$JSON_PAYLOAD" "$API_URL"
}

# 2. Get Project Config
get_config() {
    PROJECT_ID=""
    TYPE=""
    while (( "$#" )); do
        case "$1" in
            --project-id)
                if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                    PROJECT_ID=$2; shift 2
                else
                    echo "{"error": "--project-id argument is missing a value."}" >&2; usage
                fi
                ;;
            --type)
                if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                    TYPE=$2; shift 2
                else
                    echo "{"error": "--type argument is missing a value."}" >&2; usage
                fi
                ;;
            *)
                echo "{"error": "Unknown option for get_config: $1"}" >&2; usage
                ;;
        esac
    done

    if [ -z "$PROJECT_ID" ] || [ -z "$TYPE" ]; then
        echo "{"error": "--project-id and --type are required for get_config."}" >&2; usage
    fi

    handle_token
    API_URL="$BASE_API_URL/getProjectConfig"
    JSON_PAYLOAD=$(printf '{"projectId":%s, "type":%s}' "$PROJECT_ID" "$TYPE")

    curl -s -X POST -H "Content-Type: application/json" -H "token: $TOKEN" -d "$JSON_PAYLOAD" "$API_URL"
}

# 3. Create Work Item (Advanced)
create_item() {
    PAYLOAD=""
     while (( "$#" )); do
        case "$1" in
            --payload)
                if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                    PAYLOAD=$2; shift 2
                else
                    echo "{"error": "--payload argument is missing a value."}" >&2; usage
                fi
                ;;
            *)
                echo "{"error": "Unknown option for create_item: $1"}" >&2; usage
                ;;
        esac
    done

    if [ -z "$PAYLOAD" ]; then
        echo "{"error": "--payload is required for create_item."}" >&2; usage
    fi

    handle_token
    API_URL="$BASE_API_URL/createWorkAdvance"
    
    curl -s -X POST -H "Content-Type: application/json" -H "token: $TOKEN" -d "$PAYLOAD" "$API_URL"
}


# --- MAIN DISPATCHER ---
COMMAND="$1"
if [ -z "$COMMAND" ]; then
    usage
fi
shift

case "$COMMAND" in
    search_project)
        search_project "$@"
        ;;
    get_config)
        get_config "$@"
        ;;
    create_item)
        create_item "$@"
        ;;
    *)
        echo "{"error": "Unknown command: '$COMMAND'"}" >&2
        usage
        ;;
esac
