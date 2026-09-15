@echo off

REM 云效工程规范检查脚本 (Windows 版本)
REM 检查项：
REM 1. Java项目：src/main/resources下是否存在config_online/offline/sandbox/stable四套配置文件，pom.xml是否直接依赖快照包，config_online中是否配置了远程debug端口
REM 2. PHP项目：是否存在phpapps目录，子项目是否包含四套配置文件
REM 3. Go项目：是否存在vendor目录，是否包含四套配置文件
REM 4. WF项目：是否存在wfconfig目录，是否包含offline/sandbox/stable/online四套配置文件夹

setlocal enabledelayedexpansion

REM 检查结果计数器
set total_errors=0
set total_warnings=0

REM 打印报告头
:print_header
set project_path=%1
set project_type=%2
echo ==================================================
echo %project_type%项目规范检查报告
echo 项目路径: %project_path%
echo 检查时间: %date% %time%
echo ==================================================
echo.
goto :eof

REM 打印模块报告头
:print_module_header
set module_name=%1
echo.
echo --------------------------------------------------
echo 模块: %module_name%
echo --------------------------------------------------
echo.
goto :eof

REM 打印总结
:print_summary
echo.
echo ==================================================
echo Debug info: total_errors=%total_errors%, total_warnings=%total_warnings%

if %total_errors%==0 if %total_warnings%==0 (
    echo ✅ All checks passed!
) else (
    if %total_errors% gtr 0 (
        echo ❌ Summary: %total_errors% errors, %total_warnings% warnings
    ) else (
        echo ⚠️  Summary: %total_errors% errors, %total_warnings% warnings
    )
)
echo ==================================================
goto :eof

REM 检查项目是否为WF项目
:is_wf_project
set project_path=%1
if exist "%project_path%\wfconfig" (
    exit /b 0
) else (
    exit /b 1
)
goto :eof

REM 检查项目是否为Java项目
:is_java_project
set project_path=%1
if exist "%project_path%\pom.xml" (
    exit /b 0
) else if exist "%project_path%\src\main\java" (
    exit /b 0
) else (
    for /r "%project_path%" %%f in (*.java) do (
        if exist "%%f" (
            exit /b 0
        )
    )
    exit /b 1
)
goto :eof

REM 检查项目是否为PHP项目
:is_php_project
set project_path=%1
if exist "%project_path%\phpapps" (
    exit /b 0
) else (
    for /r "%project_path%" %%f in (*.php) do (
        if exist "%%f" (
            exit /b 0
        )
    )
    exit /b 1
)
goto :eof

REM 检查项目是否为Go项目
:is_go_project
set project_path=%1
for /r "%project_path%" %%f in (*.go) do (
    if exist "%%f" (
        exit /b 0
    )
)
if exist "%project_path%\go.mod" (
    exit /b 0
) else (
    exit /b 1
)
goto :eof

REM 检查WF项目
:check_wf_project
set project_path=%1

REM 检查wfconfig目录
if not exist "%project_path%\wfconfig" (
    echo ❌ wfconfig 目录不存在
    set /a total_errors+=1
    goto :eof
)

echo ✅ wfconfig 目录存在

echo [配置文件目录检查]
set required_configs=offline sandbox stable online

for %%c in (%required_configs%) do (
    set config_path=%project_path%\wfconfig\%%c
    if not exist "!config_path!" (
        echo ❌ %%c 目录缺失
        set /a total_errors+=1
    ) else (
        echo ✅ %%c 存在
        
        REM 检查每套配置文件夹下是否只有一个namespace目录
        set subdir_count=0
        for /d %%d in ("!config_path!\*") do (
            set /a subdir_count+=1
            set namespace_dir=%%d
        )
        
        if !subdir_count! neq 1 (
            echo   检查 %%c 目录结构: ❌ 目录下必须只有一个namespace目录
            set /a total_errors+=1
        ) else (
            for %%d in ("!config_path!\*") do (
                set namespace_name=%%~nxd
                echo   检查 %%c 目录结构: ✅ 只有一个namespace目录: !namespace_name!
                
                REM 检查namespace目录下是否有具体配置文件
                set file_count=0
                for %%f in ("%%d\*") do (
                    if exist "%%f" (
                        set /a file_count+=1
                    )
                )
                
                if !file_count! equ 0 (
                    echo   检查 !namespace_name! 目录配置文件: ❌ namespace目录下无配置文件
                    set /a total_errors+=1
                ) else (
                    echo   检查 !namespace_name! 目录配置文件: ✅ 包含 !file_count! 个配置文件
                )
            )
        )
    )
)
goto :eof

REM 检查Java项目配置文件目录
:check_java_config_directories
set project_path=%1
set module_errors=0
set module_warnings=0

echo [配置文件检查]

set resources_path=%project_path%\src\main\resources

REM 检查resources目录是否存在
if not exist "%resources_path%" (
    echo ❌ src/main/resources 目录不存在: %resources_path%
    set module_errors=1
    set /a total_errors+=module_errors
    set /a total_warnings+=module_warnings
    goto :eof
)

echo ✅ src/main/resources 存在

REM 必须存在的配置目录
set required_configs=config_online config_offline config_sandbox config_stable

for %%c in (%required_configs%) do (
    set config_path=%resources_path%\%%c
    if not exist "!config_path!" (
        echo ❌ %%c 目录缺失
        set /a module_errors+=1
    ) else (
        REM 检查目录是否为空
        set empty=true
        for %%f in ("!config_path!\*") do (
            if exist "%%f" (
                set empty=false
                goto :not_empty
            )
        )
        :not_empty
        if !empty! equ true (
            echo ⚠️  %%c 存在但为空
            set /a module_warnings+=1
        ) else (
            echo ✅ %%c 存在
        )
    )
)

set /a total_errors+=module_errors
set /a total_warnings+=module_warnings
echo.
goto :eof

REM 检查Java项目POM依赖
:check_java_pom_dependencies
set project_path=%1
set module_warnings=0

echo [POM依赖检查]

set pom_path=%project_path%\pom.xml

if not exist "%pom_path%" (
    echo ❌ pom.xml 不存在
    set /a total_errors+=1
    echo.
    goto :eof
)

REM 简化版：检查pom.xml中是否包含SNAPSHOT
findstr /i "SNAPSHOT" "%pom_path%" > nul
if %errorlevel% equ 0 (
    echo ⚠️  发现SNAPSHOT依赖
    set /a module_warnings+=1
) else (
    echo ✅ 未发现SNAPSHOT依赖
)

set /a total_warnings+=module_warnings
echo.
goto :eof

REM 检查Java项目生产环境debug配置
:check_java_debug_config
set project_path=%1
set module_errors=0

echo [生产配置安全检查]

set config_online_path=%project_path%\src\main\resources\config_online

if not exist "%config_online_path%" (
    echo ⚠️  config_online 不存在，跳过生产配置检查
    set /a total_warnings+=1
    echo.
    goto :eof
)

REM 定义debug相关的危险模式
set dangerous_patterns=jdwp Xrunjdwp agentlib:jdwp debug.port jdwp.port scf.server.debug.port jdwp.enabled= address= suspend=

set found_issues=0

REM 遍历所有配置文件
for %%f in ("%config_online_path%\*") do (
    if exist "%%f" (
        set file_name=%%~nxf
        
        for %%p in (%dangerous_patterns%) do (
            findstr /i "%%p" "%%f" > nul
            if %errorlevel% equ 0 (
                echo ❌ config_online/%%file_name% 中发现debug配置
                set /a module_errors+=1
                set found_issues=1
            )
        )
    )
)

if %found_issues% equ 0 (
    echo ✅ config_online 中未发现debug配置
)

set /a total_errors+=module_errors
echo.
goto :eof

REM 检查单个Java模块
:check_java_module
set module_path=%1
for %%f in (%module_path%) do (
    set module_name=%%~nxf
)

echo 模块: %module_name%
echo --------------------------------------------------

REM 执行检查，三项都是独立的检查项
call :check_java_config_directories %module_path%
call :check_java_pom_dependencies %module_path%
call :check_java_debug_config %module_path%
goto :eof

REM 检查Java项目及其子模块
:check_java_project
set project_path=%1

REM 检查是否为父子工程
set pom_path=%project_path%\pom.xml
if exist "%pom_path%" (
    REM 简化版：假设不是父子工程
    call :check_java_module %project_path%
) else (
    call :check_java_module %project_path%
)
goto :eof

REM 检查PHP项目
:check_php_project_structure
set project_path=%1

REM 检查phpapps目录
set phpapps_path=%project_path%\phpapps
if not exist "%phpapps_path%" (
    echo ❌ phpapps 目录不存在
    set /a total_errors+=1
    goto :eof
)

echo ✅ phpapps 目录存在

REM 检查子项目
set subproject_count=0
for /d %%d in ("%phpapps_path%\*") do (
    set /a subproject_count+=1
    set subproject=%%d
    for %%f in (%%d) do (
        set subproject_name=%%~nxf
    )
    
    echo 检查子项目 %subproject_name%: 
    
    REM 必须存在的配置目录
    set all_configs_exist=true
    set required_configs=config_online config_offline config_sandbox config_stable
    
    for %%c in (%required_configs%) do (
        if not exist "%subproject%\%%c" (
            set all_configs_exist=false
        )
    )
    
    if !all_configs_exist! equ true (
        echo ✅ 包含所有配置目录
    ) else (
        echo ❌ 缺少配置目录
        set /a total_errors+=1
    )
)

if %subproject_count% equ 0 (
    echo ⚠️  phpapps 目录为空，未发现子项目
    set /a total_warnings+=1
)
goto :eof

REM 检查Go项目
:check_go_project
set project_path=%1

REM 检查vendor目录
set vendor_path=%project_path%\vendor
if not exist "%vendor_path%" (
    echo ❌ vendor 目录不存在
    set /a total_errors+=1
) else (
    echo ✅ vendor 目录存在
)

REM 检查配置文件目录
echo [配置文件检查]
set required_configs=config_online config_offline config_sandbox config_stable

for %%c in (%required_configs%) do (
    set config_path=%project_path%\%%c
    if not exist "!config_path!" (
        echo ❌ %%c 目录缺失
        set /a total_errors+=1
    ) else (
        echo ✅ %%c 存在
    )
)
goto :eof

REM 检查项目
:check_project
set project_path=%1

REM 检查项目类型
call :is_wf_project %project_path%
if %errorlevel% equ 0 (
    call :print_header %project_path% "WF"
    echo [项目结构检查]
    call :check_wf_project %project_path%
) else (
    call :is_java_project %project_path%
    if %errorlevel% equ 0 (
        call :print_header %project_path% "Java"
        call :check_java_project %project_path%
    ) else (
        call :is_php_project %project_path%
        if %errorlevel% equ 0 (
            call :print_header %project_path% "PHP"
            echo [代码结构检查]
            call :check_php_project_structure %project_path%
        ) else (
            call :is_go_project %project_path%
            if %errorlevel% equ 0 (
                call :print_header %project_path% "Go"
                echo [依赖目录检查]
                call :check_go_project %project_path%
            ) else (
                echo 该项目不是Java、PHP、Go或WF语言工程，不进行检查。
                echo 请参考各工程类型开发规范文档进行调整: https://ishare.58corp.com/articleDetail?id=1761
            )
        )
    )
)
goto :eof

REM 主函数
if %~1.==.
    echo 用法: yunxiao-project-standerd-check.bat ^<项目路径^
exit /b 1
)

set project_path=%~1

REM 验证路径
if not exist "%project_path%" (
    echo 错误: 路径不存在或不是目录: %project_path%
exit /b 1
)

REM 执行项目检查
call :check_project %project_path%

REM 打印总结
call :print_summary

REM 返回退出码
if %total_errors% gtr 0 (
    exit /b 1
) else (
    exit /b 0
)
