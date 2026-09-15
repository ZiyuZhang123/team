#
# advanced_create.ps1: A multi-purpose script for the advanced work item creation flow on Windows.
# This version explicitly handles UTF-8 encoding for API responses to prevent garbled text.
#

# --- GLOBALS & HELPERS ---

$global:TOKEN = $null
$BASE_API_URL = "http://ee-api.58dns.org/skill/api-yunxiao-iwork/work"

# Function to display usage
function Show-Usage {
    Write-Host "Usage: powershell -File .scriptsadvanced_create.ps1 <command> [options]"
    Write-Host "Commands:"
    Write-Host "  search_project  --keyword <keyword>"
    Write-Host "  get_config      --project-id <id> --type <type>"
    Write-Host "  create_item     --payload <json-string>"
    Write-Host ""
    Write-Host "All commands will automatically use the YUNXIAO_SKILL_TOKEN environment variable."
    Write-Host "If the variable is not set, you will be prompted to enter the token."
    exit 1
}

# Function to get the authentication token
function Handle-Token {
    if ($global:TOKEN) {
        return
    }

    if ($env:YUNXIAO_SKILL_TOKEN) {
        $global:TOKEN = $env:YUNXIAO_SKILL_TOKEN
    } else {
        try {
            $global:TOKEN = Read-Host "YUNXIAO_SKILL_TOKEN not set. Please enter your token"
        } catch {
            Write-Host '{"error": "YUNXIAO_SKILL_TOKEN is not set and no TTY is available for prompt."}'
            exit 1
        }
    }

    if ([string]::IsNullOrEmpty($global:TOKEN)) {
        Write-Host '{"error": "Token is required but could not be obtained."}'
        exit 1
    }
}

# Helper to parse arguments
function Get-Args($args) {
    $arguments = @{}
    for ($i = 0; $i -lt $args.Length; $i += 2) {
        $key = $args[$i].TrimStart('-')
        $value = $args[$i+1]
        $arguments[$key] = $value
    }
    return $arguments
}


# --- COMMANDS ---

# 1. Search Project
function Search-Project($args) {
    $arguments = Get-Args $args
    $keyword = $arguments['keyword']

    if ([string]::IsNullOrEmpty($keyword)) {
        Write-Host '{"error": "--keyword is required for search_project."}'; Show-Usage
    }
    
    Handle-Token
    $API_URL = "$BASE_API_URL/searchProject"
    $body = @{ keyword = $keyword } | ConvertTo-Json
    $headers = @{ "Content-Type" = "application/json"; "token" = $global:TOKEN }

    try {
        $response = Invoke-WebRequest -Uri $API_URL -Method Post -Headers $headers -Body $body
        $utf8Content = [System.Text.Encoding]::UTF8.GetString($response.RawContent)
        Write-Host $utf8Content
    } catch {
        Write-Host "{"error": "API call failed: $($_.Exception.Message)"}"
        exit 1
    }
}

# 2. Get Project Config
function Get-Config($args) {
    $arguments = Get-Args $args
    $projectId = $arguments['project-id']
    $type = $arguments['type']
    
    if ([string]::IsNullOrEmpty($projectId) -or [string]::IsNullOrEmpty($type)) {
        Write-Host '{"error": "--project-id and --type are required for get_config."}'; Show-Usage
    }

    Handle-Token
    $API_URL = "$BASE_API_URL/getProjectConfig"
    $body = @{ projectId = $projectId; type = [int]$type } | ConvertTo-Json
    $headers = @{ "Content-Type" = "application/json"; "token" = $global:TOKEN }

    try {
        $response = Invoke-WebRequest -Uri $API_URL -Method Post -Headers $headers -Body $body
        $utf8Content = [System.Text.Encoding]::UTF8.GetString($response.RawContent)
        Write-Host $utf8Content
    } catch {
        Write-Host "{"error": "API call failed: $($_.Exception.Message)"}"
        exit 1
    }
}

# 3. Create Work Item (Advanced)
function Create-Item($args) {
    $arguments = Get-Args $args
    $payload = $arguments['payload']
    
    if ([string]::IsNullOrEmpty($payload)) {
        Write-Host '{"error": "--payload is required for create_item."}'; Show-Usage
    }

    Handle-Token
    $API_URL = "$BASE_API_URL/createWorkAdvance"
    $headers = @{ "Content-Type" = "application/json"; "token" = $global:TOKEN }
    
    try {
        $response = Invoke-WebRequest -Uri $API_URL -Method Post -Headers $headers -Body $payload
        $utf8Content = [System.Text.Encoding]::UTF8.GetString($response.RawContent)
        Write-Host $utf8Content
    } catch {
        Write-Host "{"error": "API call failed: $($_.Exception.Message)"}"
        exit 1
    }
}


# --- MAIN DISPATCHER ---
$command = $args[0]
$commandArgs = $args[1..$args.Length]

switch ($command) {
    "search_project" { Search-Project $commandArgs }
    "get_config"     { Get-Config $commandArgs }
    "create_item"    { Create-Item $commandArgs }
    default          { Write-Host "{"error": "Unknown command: '$command'"}"; Show-Usage }
}
