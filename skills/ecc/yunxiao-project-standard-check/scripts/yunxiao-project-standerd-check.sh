#!/bin/bash

# 云效工程规范检查脚本
# 检查项：
# 1. Java项目：src/main/resources下是否存在config_online/offline/sandbox/stable四套配置文件，pom.xml是否直接依赖快照包，config_online中是否配置了远程debug端口
# 2. PHP项目：是否存在phpapps目录，子项目是否包含四套配置文件
# 3. Go项目：是否存在vendor目录，是否包含四套配置文件

# 颜色定义
GREEN='\033[92m'
YELLOW='\033[93m'
RED='\033[91m'
BLUE='\033[94m'
RESET='\033[0m'

# 检查结果计数器
total_errors=0
total_warnings=0

# 打印报告头
print_header() {
    local project_path=$1
    local project_type=$2
    echo "=================================================="
    echo "${project_type}项目规范检查报告"
    echo "项目路径: $project_path"
    echo "检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=================================================="
    echo
}

# 打印模块报告头
print_module_header() {
    local module_name=$1
    echo ""
    echo "--------------------------------------------------"
    echo "模块: $module_name"
    echo "--------------------------------------------------"
    echo ""
}

# 打印总结
print_summary() {
    echo
    echo "=================================================="
    echo "Debug info: total_errors=$total_errors, total_warnings=$total_warnings"
    
    if [ $total_errors -eq 0 ] && [ $total_warnings -eq 0 ]; then
        echo "✅ All checks passed!"
    else
        if [ $total_errors -gt 0 ]; then
            echo "❌ Summary: $total_errors errors, $total_warnings warnings"
        else
            echo "⚠️  Summary: $total_errors errors, $total_warnings warnings"
        fi
    fi
    echo "=================================================="
}

# 检查模块是否为依赖模块（jar类型或无resources目录的模块）
is_jar_module() {
    local project_path=$1
    local pom_path="$project_path/pom.xml"
    
    if [ ! -f "$pom_path" ]; then
        return 1
    fi
    
    # 检查packaging类型
    local packaging=$(grep -E "<packaging>.*</packaging>" "$pom_path" | head -1 | sed 's/<packaging>\(.*\)<\/packaging>/\1/' | tr -d '[:space:]')
    
    if [ "$packaging" = "jar" ]; then
        return 0
    fi
    
    # 检查是否存在resources目录
    local resources_path="$project_path/src/main/resources"
    if [ ! -d "$resources_path" ]; then
        return 0
    fi
    
    return 1
}

# 检查Java项目配置文件目录
check_java_config_directories() {
    local project_path=$1
    local module_errors=0
    local module_warnings=0
    
    echo "[配置文件检查]"
    
    local resources_path="$project_path/src/main/resources"
    
    # 检查resources目录是否存在
    if [ ! -d "$resources_path" ]; then
        echo -e "${RED}❌ src/main/resources 目录不存在: $resources_path${RESET}"
        module_errors=1
        total_errors=$((total_errors + module_errors))
        total_warnings=$((total_warnings + module_warnings))
        return 1
    fi
    
    echo -e "${GREEN}✅ src/main/resources 存在${RESET}"
    
    # 必须存在的配置目录
    local required_configs=("config_online" "config_offline" "config_sandbox" "config_stable")
    
    for config_name in "${required_configs[@]}"; do
        local config_path="$resources_path/$config_name"
        
        if [ ! -d "$config_path" ]; then
            echo -e "${RED}❌ $config_name 目录缺失${RESET}"
            module_errors=$((module_errors + 1))
            continue
        fi
        
        # 检查目录是否为空
        if [ -z "$(ls -A "$config_path")" ]; then
            echo -e "${YELLOW}⚠️  $config_name 存在但为空${RESET}"
            module_warnings=$((module_warnings + 1))
        else
            echo -e "${GREEN}✅ $config_name 存在${RESET}"
        fi
    done
    
    total_errors=$((total_errors + module_errors))
    total_warnings=$((total_warnings + module_warnings))
    echo
    return $module_errors
}

# 检查Java项目POM依赖
check_java_pom_dependencies() {
    local project_path=$1
    local module_warnings=0
    
    echo "[POM依赖检查]"
    
    local pom_path="$project_path/pom.xml"
    
    if [ ! -f "$pom_path" ]; then
        echo -e "${RED}❌ pom.xml 不存在${RESET}"
        total_errors=$((total_errors + 1))
        echo
        return
    fi
    
    # 提取properties部分的属性定义
    local properties_section=$(awk '/<properties>/,/<\/properties>/' "$pom_path")
    
    # 只检查dependencies部分的SNAPSHOT依赖
    # 提取dependencies标签之间的内容
    local dependencies_section=$(awk '/<dependencies>/,/<\/dependencies>/' "$pom_path")
    
    if [ -z "$dependencies_section" ]; then
        echo -e "${GREEN}✅ 未发现dependencies部分${RESET}"
        echo
        return
    fi
    
    # 查找所有依赖项
    local dependencies=$(echo "$dependencies_section" | grep -B3 -A3 "<dependency>")
    local group_id=""
    local artifact_id=""
    local version=""
    local found_snapshot=false
    
    echo "$dependencies" | while IFS= read -r line; do
        if [[ $line == *"<groupId>"*"</groupId>"* ]]; then
            group_id=$(echo "$line" | sed 's/<groupId>\(.*\)<\/groupId>/\1/' | tr -d '[:space:]')
        elif [[ $line == *"<artifactId>"*"</artifactId>"* ]]; then
            artifact_id=$(echo "$line" | sed 's/<artifactId>\(.*\)<\/artifactId>/\1/' | tr -d '[:space:]')
        elif [[ $line == *"<version>"*"</version>"* ]]; then
            version=$(echo "$line" | sed 's/<version>\(.*\)<\/version>/\1/' | tr -d '[:space:]')
            
            # 检查直接指定的SNAPSHOT版本
            if [[ $version == *"SNAPSHOT"* ]]; then
                if [ ! $found_snapshot ]; then
                    echo -e "${YELLOW}⚠️  发现SNAPSHOT依赖:${RESET}"
                    found_snapshot=true
                fi
                echo -e "${YELLOW}⚠️    - $group_id:$artifact_id:$version${RESET}"
                module_warnings=$((module_warnings + 1))
            # 检查通过属性引用的SNAPSHOT版本
            elif [[ $version == \${*\} ]]; then
                # 提取属性名
                local property_name=$(echo "$version" | sed 's/\${\(.*\)}/\1/')
                # 在properties部分查找属性值
                local property_value=$(echo "$properties_section" | grep -A1 "<$property_name>" | tail -1 | sed 's/<\/'"$property_name"'>//' | tr -d '[:space:]')
                if [[ $property_value == *"SNAPSHOT"* ]]; then
                    if [ ! $found_snapshot ]; then
                        echo -e "${YELLOW}⚠️  发现SNAPSHOT依赖:${RESET}"
                        found_snapshot=true
                    fi
                    echo -e "${YELLOW}⚠️    - $group_id:$artifact_id:$version ($property_value)${RESET}"
                    module_warnings=$((module_warnings + 1))
                fi
            fi
            
            group_id=""
            artifact_id=""
            version=""
        fi
    done
    
    if [ ! $found_snapshot ]; then
        echo -e "${GREEN}✅ 未发现SNAPSHOT依赖${RESET}"
    fi
    
    total_warnings=$((total_warnings + module_warnings))
    echo
}

# 检查Java项目生产环境debug配置
check_java_debug_config() {
    local project_path=$1
    local module_errors=0
    
    echo "[生产配置安全检查]"
    
    local config_online_path="$project_path/src/main/resources/config_online"
    
    if [ ! -d "$config_online_path" ]; then
        echo -e "${YELLOW}⚠️  config_online 不存在，跳过生产配置检查${RESET}"
        total_warnings=$((total_warnings + 1))
        echo
        return
    fi
    
    # 定义debug相关的危险模式
    local dangerous_patterns=(
        "jdwp"
        "Xrunjdwp"
        "agentlib:jdwp"
        "debug\.port\s*="
        "jdwp\.port\s*="
        "scf\.server\.debug\.port"
        "jdwp\.enabled\s*=\s*true"
        "address=.*:\d{4,5}"
        "suspend=[yn]"
    )
    
    local found_issues=0
    
    # 遍历所有配置文件
    for config_file in "$config_online_path"/*; do
        if [ -f "$config_file" ]; then
            local file_name=$(basename "$config_file")
            
            for pattern in "${dangerous_patterns[@]}"; do
                if grep -q -i "$pattern" "$config_file"; then
                    local matches=$(grep -n -i "$pattern" "$config_file")
                    while IFS= read -r line; do
                        echo -e "${RED}❌ config_online/$file_name 中发现debug配置 (${line%%:*}行): ${line#*:}${RESET}"
                        module_errors=$((module_errors + 1))
                        found_issues=1
                    done <<< "$matches"
                fi
            done
        fi
    done
    
    if [ $found_issues -eq 0 ]; then
        echo -e "${GREEN}✅ config_online 中未发现debug配置${RESET}"
    fi
    
    total_errors=$((total_errors + module_errors))
    echo
}

# 检查PHP项目
check_php_project_structure() {
    local project_path=$1
    
    # 检查phpapps目录
    local phpapps_path="$project_path/phpapps"
    if [ ! -d "$phpapps_path" ]; then
        echo -e "${RED}❌ phpapps 目录不存在${RESET}"
        total_errors=$((total_errors + 1))
        return
    fi
    
    echo -e "${GREEN}✅ phpapps 目录存在${RESET}"
    
    # 检查子项目
    local subprojects=$(find "$phpapps_path" -type d -mindepth 1 -maxdepth 1)
    if [ -z "$subprojects" ]; then
        echo -e "${YELLOW}⚠️  phpapps 目录为空，未发现子项目${RESET}"
        total_warnings=$((total_warnings + 1))
        return
    fi
    
    # 必须存在的配置目录
    local required_configs=("config_online" "config_offline" "config_sandbox" "config_stable")
    
    for subproject in $subprojects; do
        local subproject_name=$(basename "$subproject")
        echo -n "检查子项目 $subproject_name: "
        
        local all_configs_exist=true
        for config_name in "${required_configs[@]}"; do
            local config_path="$subproject/$config_name"
            if [ ! -d "$config_path" ]; then
                all_configs_exist=false
                break
            fi
        done
        
        if [ "$all_configs_exist" = true ]; then
            echo -e "${GREEN}✅ 包含所有配置目录${RESET}"
        else
            echo -e "${RED}❌ 缺少配置目录${RESET}"
            total_errors=$((total_errors + 1))
        fi
    done
}

# 检查Go项目
check_go_project() {
    local project_path=$1
    
    # 检查vendor目录
    local vendor_path="$project_path/vendor"
    if [ ! -d "$vendor_path" ]; then
        echo -e "${RED}❌ vendor 目录不存在${RESET}"
        total_errors=$((total_errors + 1))
    else
        echo -e "${GREEN}✅ vendor 目录存在${RESET}"
    fi
    
    # 检查配置文件目录
    echo "[配置文件检查]"
    local required_configs=("config_online" "config_offline" "config_sandbox" "config_stable")
    
    for config_name in "${required_configs[@]}"; do
        local config_path="$project_path/$config_name"
        if [ ! -d "$config_path" ]; then
            echo -e "${RED}❌ $config_name 目录缺失${RESET}"
            total_errors=$((total_errors + 1))
        else
            echo -e "${GREEN}✅ $config_name 存在${RESET}"
        fi
    done
}

# 检查WF项目
check_wf_project() {
    local project_path=$1
    
    # 检查wfconfig目录
    local wfconfig_path="$project_path/wfconfig"
    if [ ! -d "$wfconfig_path" ]; then
        echo -e "${RED}❌ wfconfig 目录不存在${RESET}"
        total_errors=$((total_errors + 1))
        return
    fi
    
    echo -e "${GREEN}✅ wfconfig 目录存在${RESET}"
    
    # 检查四套配置文件夹
    echo "[配置文件目录检查]"
    local required_configs=("offline" "sandbox" "stable" "online")
    
    for config_name in "${required_configs[@]}"; do
        local config_path="$wfconfig_path/$config_name"
        if [ ! -d "$config_path" ]; then
            echo -e "${RED}❌ $config_name 目录缺失${RESET}"
            total_errors=$((total_errors + 1))
        else
            echo -e "${GREEN}✅ $config_name 存在${RESET}"
            
            # 检查每套配置文件夹下是否只有一个namespace目录
            echo -n "  检查 $config_name 目录结构: "
            local subdirs=$(find "$config_path" -type d -mindepth 1 -maxdepth 1 | wc -l)
            if [ $subdirs -ne 1 ]; then
                echo -e "${RED}❌ 目录下必须只有一个namespace目录${RESET}"
                total_errors=$((total_errors + 1))
            else
                local namespace_dir=$(find "$config_path" -type d -mindepth 1 -maxdepth 1)
                local namespace_name=$(basename "$namespace_dir")
                echo -e "${GREEN}✅ 只有一个namespace目录: $namespace_name${RESET}"
                
                # 检查namespace目录下是否有具体配置文件
                echo -n "  检查 $namespace_name 目录配置文件: "
                local config_files=$(find "$namespace_dir" -type f | wc -l)
                if [ $config_files -eq 0 ]; then
                    echo -e "${RED}❌ namespace目录下无配置文件${RESET}"
                    total_errors=$((total_errors + 1))
                else
                    echo -e "${GREEN}✅ 包含 $config_files 个配置文件${RESET}"
                fi
            fi
        fi
    done
}

# 检查单个Java模块
check_java_module() {
    local module_path=$1
    local module_name=$(basename "$module_path")
    
    # 检查是否为jar模块，如果是则跳过
    if is_jar_module "$module_path"; then
        echo "跳过jar模块: $module_name"
        return
    fi
    
    print_module_header "$module_name"
    
    # 执行检查，三项都是独立的检查项
    check_java_config_directories "$module_path"
    check_java_pom_dependencies "$module_path"
    check_java_debug_config "$module_path"
}

# 检查项目是否为Java项目
is_java_project() {
    local project_path=$1
    
    # 检查是否存在pom.xml文件
    local pom_path="$project_path/pom.xml"
    if [ -f "$pom_path" ]; then
        return 0
    fi
    
    # 检查是否存在src/main/java目录
    local java_src_path="$project_path/src/main/java"
    if [ -d "$java_src_path" ]; then
        return 0
    fi
    
    # 检查是否存在.java文件
    local java_files=$(find "$project_path" -name "*.java" | head -1)
    if [ -n "$java_files" ]; then
        return 0
    fi
    
    return 1
}

# 检查项目是否为PHP项目
is_php_project() {
    local project_path=$1
    
    # 检查是否存在phpapps目录
    local phpapps_path="$project_path/phpapps"
    if [ -d "$phpapps_path" ]; then
        return 0
    fi
    
    # 检查是否存在.php文件
    local php_files=$(find "$project_path" -name "*.php" | head -1)
    if [ -n "$php_files" ]; then
        return 0
    fi
    
    return 1
}

# 检查项目是否为Go项目
is_go_project() {
    local project_path=$1
    
    # 检查是否存在.go文件
    local go_files=$(find "$project_path" -name "*.go" | head -1)
    if [ -n "$go_files" ]; then
        return 0
    fi
    
    # 检查是否存在go.mod文件
    local go_mod_path="$project_path/go.mod"
    if [ -f "$go_mod_path" ]; then
        return 0
    fi
    
    return 1
}

# 检查项目是否为WF项目
is_wf_project() {
    local project_path=$1
    
    # 检查是否存在wfconfig目录
    local wfconfig_path="$project_path/wfconfig"
    if [ -d "$wfconfig_path" ]; then
        return 0
    fi
    
    return 1
}

# 检查Java项目及其子模块
check_java_project() {
    local project_path=$1
    
    # 检查是否为父子工程
    local pom_path="$project_path/pom.xml"
    if [ -f "$pom_path" ]; then
        local packaging=$(grep -E "<packaging>.*</packaging>" "$pom_path" | head -1 | sed 's/<packaging>\(.*\)<\/packaging>/\1/' | tr -d '[:space:]')
        
        if [ "$packaging" = "pom" ]; then
            # 父子工程，检查子模块
            local modules_file=$(mktemp)
            grep -E "<module>" "$pom_path" > "$modules_file"
            
            if [ -s "$modules_file" ]; then
                echo "发现父子工程，检查子模块..."
                echo
                
                # 逐行处理模块
                while IFS= read -r line; do
                    if [ -n "$line" ]; then
                        local module=$(echo "$line" | sed 's/<module>\(.*\)<\/module>/\1/' | tr -d '[:space:]')
                        if [ -n "$module" ]; then
                            local module_path="$project_path/$module"
                            echo "检查模块: $module ($module_path)"
                            if [ -d "$module_path" ]; then
                                check_java_module "$module_path"
                            else
                                echo "模块路径不存在: $module_path"
                            fi
                        fi
                    fi
                done < "$modules_file"
                
                rm "$modules_file"
                return
            fi
            
            rm "$modules_file"
        fi
    fi
    
    # 单个模块，直接检查
    check_java_module "$project_path"
}

# 检查项目
check_project() {
    local project_path=$1
    
    # 检查项目类型
    if is_wf_project "$project_path"; then
        print_header "$project_path" "WF"
        echo "[项目结构检查]"
        check_wf_project "$project_path"
    elif is_java_project "$project_path"; then
        print_header "$project_path" "Java"
        check_java_project "$project_path"
    elif is_php_project "$project_path"; then
        print_header "$project_path" "PHP"
        echo "[代码结构检查]"
        check_php_project_structure "$project_path"
    elif is_go_project "$project_path"; then
        print_header "$project_path" "Go"
        echo "[依赖目录检查]"
        check_go_project "$project_path"
    else
        echo "该项目不是Java、PHP、Go或WF语言工程，不进行检查。"
        echo "请参考各工程类型开发规范文档进行调整: https://ishare.58corp.com/articleDetail?id=1761"
        return
    fi
}

# 主函数
main() {
    if [ $# -lt 1 ]; then
        echo "用法: bash yunxiao-project-standerd-check.sh <项目路径>"
        exit 1
    fi
    
    local project_path=$1
    
    # 验证路径
    if [ ! -d "$project_path" ]; then
        echo "错误: 路径不存在或不是目录: $project_path"
        exit 1
    fi
    
    # 转换为绝对路径
    project_path=$(cd "$project_path" && pwd)
    
    # 执行项目检查
    check_project "$project_path"
    
    # 打印总结
    print_summary
    
    # 返回退出码
    if [ $total_errors -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# 执行主函数
main "$@"
