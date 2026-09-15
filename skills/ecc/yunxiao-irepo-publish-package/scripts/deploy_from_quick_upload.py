#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import time
import uuid
from pathlib import Path
from typing import Any, Dict, Optional
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET


API_BASE = "http://ee-api.58dns.org/skill/api-yunxiao-irepo/api"


def _http_post_json(
    url: str,
    payload: Dict[str, Any],
    timeout: int = 30,
    token: Optional[str] = None,
) -> Dict[str, Any]:
    print(f"访问接口: {url}")
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = Request(url=url, data=body, method="POST")
    req.add_header("Content-Type", "application/json;charset=UTF-8")
    req.add_header("Accept", "application/json")
    if token:
        req.add_header("token", token)
    try:
        with urlopen(req, timeout=timeout) as resp:
            text = resp.read().decode("utf-8", errors="replace")
    except HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")
        print(f"接口返回: {detail}")
        raise RuntimeError(f"HTTP {e.code} calling {url}: {detail}") from e
    except URLError as e:
        raise RuntimeError(f"Network error calling {url}: {e}") from e

    print(f"接口返回: {text}")
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        raise RuntimeError(f"Invalid JSON from {url}: {text}") from e


def _find_upwards(start: Path, filename: str, max_hops: int = 8) -> Optional[Path]:
    current = start.resolve()
    for _ in range(max_hops):
        candidate = current / filename
        if candidate.is_file():
            return candidate
        if current.parent == current:
            break
        current = current.parent
    return None


def _manifest_filename(fmt: str) -> str:
    if fmt == "maven2":
        return "pom.xml"
    if fmt == "composer":
        return "composer.json"
    if fmt == "npm":
        return "package.json"
    raise ValueError(f"Unsupported format: {fmt}")


def _discover_projects(fmt: str) -> list[Path]:
    filename = _manifest_filename(fmt)
    roots = [Path.home() / "IdeaProjects", Path.home() / "trae"]
    result: list[Path] = []
    seen: set[str] = set()
    for root in roots:
        if not root.is_dir():
            continue
        for child in root.iterdir():
            if not child.is_dir():
                continue
            if (child / filename).is_file():
                key = str(child.resolve())
                if key not in seen:
                    seen.add(key)
                    result.append(child.resolve())
    return sorted(result, key=lambda p: p.name.lower())


def _print_project_selection_table(fmt: str, projects: list[Path]) -> None:
    print("当前工程未识别到可发布配置，请先选择工程：")
    print("| 选项 | 工程名 | 路径 |")
    print("| --- | --- | --- |")
    for i, p in enumerate(projects, 1):
        print(f"| {i} | {p.name} | {p} |")
    type_alias = {"maven2": "jar", "composer": "php", "npm": "npm"}[fmt]
    print("")
    print("点击工程后可直接继续，或使用命令指定：")
    print(f"python3 scripts/deploy_from_quick_upload.py {type_alias} --cwd <上面路径>")


def _run_cmd(args: list[str], cwd: Optional[Path] = None) -> str:
    result = subprocess.run(
        args,
        cwd=str(cwd) if cwd else None,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return ""
    return (result.stdout or "").strip()


def _find_git_root(cwd: Path) -> Optional[Path]:
    out = _run_cmd(["git", "rev-parse", "--show-toplevel"], cwd=cwd)
    if not out:
        return None
    root = Path(out).expanduser().resolve()
    return root if root.exists() else None


def _current_git_branch(cwd: Path) -> str:
    return _run_cmd(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=cwd)


def _guess_git_path(cwd: Path) -> str:
    remote = _run_cmd(["git", "config", "--get", "remote.origin.url"], cwd=cwd)
    if remote:
        candidate = remote
        if candidate.endswith(".git"):
            candidate = candidate[:-4]
        if "://" in candidate and "/" in candidate:
            candidate = candidate.split("://", 1)[1]
            candidate = candidate.split("/", 1)[1] if "/" in candidate else candidate
        if ":" in candidate and "/" in candidate and "@" in candidate.split(":", 1)[0]:
            candidate = candidate.split(":", 1)[1]
        return candidate.strip("/")
    return cwd.name


def _parse_json_name(path: Path) -> Optional[str]:
    try:
        obj = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None
    name = obj.get("name")
    if isinstance(name, str) and name.strip():
        return name.strip()
    return None


def _parse_pom_coordinates(pom_path: Path) -> tuple[Optional[str], Optional[str]]:
    try:
        tree = ET.parse(str(pom_path))
        root = tree.getroot()
    except Exception:
        return None, None

    ns = ""
    if root.tag.startswith("{") and "}" in root.tag:
        ns = root.tag.split("}")[0].strip("{")

    def q(tag: str) -> str:
        return f"{{{ns}}}{tag}" if ns else tag

    def text(elem: Optional[ET.Element]) -> Optional[str]:
        if elem is None or elem.text is None:
            return None
        value = elem.text.strip()
        return value or None

    artifact_id = text(root.find(q("artifactId")))
    group_id = text(root.find(q("groupId")))
    if not group_id:
        parent = root.find(q("parent"))
        if parent is not None:
            group_id = text(parent.find(q("groupId")))
    return group_id, artifact_id


def _parse_pom_version(pom_path: Path) -> Optional[str]:
    try:
        tree = ET.parse(str(pom_path))
        root = tree.getroot()
    except Exception:
        return None

    ns = ""
    if root.tag.startswith("{") and "}" in root.tag:
        ns = root.tag.split("}")[0].strip("{")

    def q(tag: str) -> str:
        return f"{{{ns}}}{tag}" if ns else tag

    def text(elem: Optional[ET.Element]) -> Optional[str]:
        if elem is None or elem.text is None:
            return None
        value = elem.text.strip()
        return value or None

    version = text(root.find(q("version")))
    if version:
        return version
    parent = root.find(q("parent"))
    if parent is not None:
        return text(parent.find(q("version")))
    return None


def _parse_pom_modules(pom_path: Path) -> list[str]:
    try:
        tree = ET.parse(str(pom_path))
        root = tree.getroot()
    except Exception:
        return []

    ns = ""
    if root.tag.startswith("{") and "}" in root.tag:
        ns = root.tag.split("}")[0].strip("{")

    def q(tag: str) -> str:
        return f"{{{ns}}}{tag}" if ns else tag

    modules_elem = root.find(q("modules"))
    if modules_elem is None:
        return []

    modules: list[str] = []
    for m in modules_elem.findall(q("module")):
        if m is None or m.text is None:
            continue
        name = m.text.strip()
        if name:
            modules.append(name)
    return modules


def _collect_from_project(kind: str, cwd: Path) -> tuple[Optional[str], Optional[str]]:
    if kind == "composer":
        f = _find_upwards(cwd, "composer.json")
        if not f:
            return None, None
        name = _parse_json_name(f)
        if not name or "/" not in name:
            return None, None
        group_id, artifact_id = name.split("/", 1)
        return group_id, artifact_id

    if kind == "maven2":
        f = _find_upwards(cwd, "pom.xml")
        if not f:
            return None, None
        return _parse_pom_coordinates(f)

    if kind == "npm":
        f = _find_upwards(cwd, "package.json")
        if not f:
            return None, None
        name = _parse_json_name(f)
        if not name:
            return None, None
        if name.startswith("@") and "/" in name:
            scope, pkg = name.split("/", 1)
            return scope.lstrip("@"), pkg
        return None, name

    raise ValueError(f"Unsupported kind: {kind}")


def _build_local_quick_data(fmt: str, cwd: Path, branch: str) -> Dict[str, Any]:
    git_root = _find_git_root(cwd) or cwd
    git_path = _guess_git_path(git_root)
    data: Dict[str, Any] = {
        "gitUrl": git_path,
        "gitBranch": branch,
        "gitPath": git_path,
        "jdkVersion": "3",
        "mavenType": 3,
        "deployPom": "",
        "compilePom": "",
        "buildCommand": None,
        "buildTool": "npm",
        "publishParam": None,
    }

    if fmt == "maven2":
        pom = _find_upwards(cwd, "pom.xml")
        if pom:
            data["realPomLocation"] = str(pom.resolve().relative_to(git_root.resolve()))
            version = _parse_pom_version(pom)
            if version:
                data["version"] = version
        return data

    if fmt == "npm":
        pkg = _find_upwards(cwd, "package.json")
        if pkg:
            data["realPomLocation"] = str(pkg.resolve().relative_to(git_root.resolve()))
            try:
                obj = json.loads(pkg.read_text(encoding="utf-8"))
                data["version"] = obj.get("version")
                scripts = obj.get("scripts") if isinstance(obj.get("scripts"), dict) else {}
                if isinstance(scripts, dict):
                    data["buildCommand"] = scripts.get("build")
                data["buildTool"] = "npm"
            except Exception:
                pass
        return data

    if fmt == "composer":
        comp = _find_upwards(cwd, "composer.json")
        if comp:
            data["realPomLocation"] = str(comp.resolve().relative_to(git_root.resolve()))
            try:
                obj = json.loads(comp.read_text(encoding="utf-8"))
                data["version"] = obj.get("version")
            except Exception:
                pass
        return data

    raise ValueError(f"Unsupported format: {fmt}")


def _int_value(data: Dict[str, Any], key: str, default: int = 0) -> int:
    value = data.get(key, default)
    try:
        return int(value)
    except Exception:
        return default


def _build_release_description(data: Dict[str, Any]) -> str:
    version = (str(data.get("version") or "")).strip()
    if version:
        return f"自动发包版本：{version}"
    existing = (str(data.get("releaseDescription") or "")).strip()
    if existing:
        return existing
    return "自动发包"


def _build_deploy_payload(fmt: str, data: Dict[str, Any]) -> Dict[str, Any]:
    git_url = data.get("gitUrl")
    git_branch = data.get("gitBranch")
    real_pom = data.get("realPomLocation")
    release_desc = _build_release_description(data)

    if fmt == "composer":
        return {
            "repositoryType": "3",
            "judgeType": "0",
            "location": git_url,
            "branch": git_branch,
            "pomPath": real_pom,
            "version": data.get("version"),
            "releaseDescription": release_desc,
        }

    if fmt == "maven2":
        return {
            "repositoryType": "1",
            "deployType": "1",
            "versionType": "",
            "location": git_url,
            "compileVersion": _int_value(data, "jdkVersion", 0),
            "deployPom": data.get("deployPom") or "",
            "compilePom": data.get("compilePom") or "",
            "pomPath": real_pom,
            "branch": git_branch,
            "advancedOptions": False,
            "scanOptions": False,
            "releaseDescription": release_desc,
            "snapshotConfirm": False,
            "scanOpen": "1",
            "mavenType": _int_value(data, "mavenType", 1),
            "requestUUID": str(uuid.uuid4()),
            "groupId": "",
            "artifactId": "",
            "version": "",
            "projectId": "",
            "checkAccess": 0,
            "workSpaceUUID": "",
            "commitId": "",
            "compileIp": "",
        }

    if fmt == "npm":
        return {
            "location": git_url,
            "branch": git_branch,
            "releaseDescription": release_desc,
            "pomPath": real_pom,
            "compileVersion": _int_value(data, "jdkVersion", 0),
            "buildCommand": data.get("buildCommand"),
            "buildTool": data.get("buildTool") or "npm",
            "publishParam": data.get("publishParam"),
            "advancedOptions": False,
        }

    raise ValueError(f"Unsupported format: {fmt}")


def _target_deploy_endpoint(fmt: str) -> str:
    if fmt == "composer":
        return f"{API_BASE}/deployPhpForSkill"
    if fmt == "maven2":
        return f"{API_BASE}/deployJarForSkill"
    if fmt == "npm":
        return f"{API_BASE}/deployNpmForSkill"
    raise ValueError(f"Unsupported format: {fmt}")


def _resolve_skill_token() -> str:
    token = (os.environ.get("YUNXIAO_SKILL_TOKEN") or "").strip()
    if token:
        return token

    # Fallback: source ~/.zshrc then read env again.
    try:
        result = subprocess.run(
            ["zsh", "-lc", "source ~/.zshrc >/dev/null 2>&1; printenv YUNXIAO_SKILL_TOKEN"],
            check=False,
            capture_output=True,
            text=True,
        )
        token = (result.stdout or "").strip()
        if token:
            os.environ["YUNXIAO_SKILL_TOKEN"] = token
            return token
    except Exception:
        pass

    raise SystemExit(
        "未获取到 YUNXIAO_SKILL_TOKEN。请先提供 token；若没有 token，请前往 "
        "https://ee.58corp.com/base2/t/apply/common/addToken 申请。"
    )


def _humanize_deploy_response(resp: Dict[str, Any]) -> str:
    status = resp.get("status")
    msg = resp.get("msg") or resp.get("message") or ""
    err_code = resp.get("errCode")
    data = resp.get("data")

    lines = []
    if status == 0:
        lines.append("发布结果：成功")
    else:
        lines.append("发布结果：失败")

    if msg:
        lines.append(f"平台提示：{msg}")

    if err_code not in (None, "", 0, "0"):
        lines.append(f"错误码：{err_code}")

    if isinstance(data, dict) and data:
        preferred_keys = [
            "taskId",
            "jobId",
            "pipelineId",
            "releaseId",
            "id",
            "status",
            "url",
            "link",
            "detail",
        ]
        detail_parts = []
        for k in preferred_keys:
            v = data.get(k)
            if v not in (None, ""):
                detail_parts.append(f"{k}={v}")
        if detail_parts:
            lines.append("关键返回：" + "，".join(detail_parts))
        else:
            compact = json.dumps(data, ensure_ascii=False)
            lines.append(f"返回详情：{compact}")
    elif isinstance(data, list) and data:
        lines.append(f"返回详情：列表数据，共 {len(data)} 项")
    elif data not in (None, ""):
        lines.append(f"返回详情：{data}")

    if status != 0 and not msg:
        lines.append("建议检查 groupId/artifactId、分支、pomPath 以及发布权限。")

    return "\n".join(lines)


def _extract_workspace_uuid(resp: Dict[str, Any]) -> Optional[str]:
    data = resp.get("data")
    if isinstance(data, dict):
        value = data.get("workSpaceUUID") or data.get("workspaceUUID")
        if isinstance(value, str) and value.strip():
            return value.strip()
    value = resp.get("workSpaceUUID") or resp.get("workspaceUUID")
    if isinstance(value, str) and value.strip():
        return value.strip()
    return None


def _extract_result_status(resp: Dict[str, Any]) -> Optional[int]:
    value = resp.get("status")
    if value is None and isinstance(resp.get("data"), dict):
        value = resp["data"].get("status")
    try:
        return int(value) if value is not None else None
    except Exception:
        return None


def _extract_version_from_text(text: str) -> Optional[str]:
    if not text:
        return None
    marker = "version:"
    idx = text.find(marker)
    if idx < 0:
        return None
    start = idx + len(marker)
    end = len(text)
    for sep in (" ", "#", ",", "，", "\n", "\r", "\t"):
        pos = text.find(sep, start)
        if pos >= 0:
            end = min(end, pos)
    version = text[start:end].strip()
    return version or None


def _resolve_location_from_path(git_path: str, token: str) -> Optional[int]:
    if not git_path:
        return None
    url = f"{API_BASE}/getIdByPath"
    payload = {"gitPath": git_path, "token": token}
    resp = _http_post_json(url, payload, token=token)
    if resp.get("status") != 0:
        return None
    data = resp.get("data")
    if not isinstance(data, dict):
        return None
    obj = data.get("obj")
    try:
        return int(obj)
    except Exception:
        return None


def _remind_if_version_mismatch(local_version: Optional[str], result_resp: Dict[str, Any]) -> None:
    local = (local_version or "").strip()
    if not local:
        return
    msg = (result_resp.get("msg") or result_resp.get("message") or "").strip()
    remote = _extract_version_from_text(msg)
    if not remote:
        return
    if local != remote:
        print(
            f"版本不一致提醒：本地版本是 {local}，发布返回版本是 {remote}。"
            "请确认是否已经将最新代码提交到 git。"
        )


def _package_scope_desc(fmt: str, artifact_id: str, deploy_payload: Dict[str, Any]) -> str:
    if fmt == "maven2":
        module_path = (
            (deploy_payload.get("compilePom") or "").strip()
            or (deploy_payload.get("deployPom") or "").strip()
            or (deploy_payload.get("pomPath") or "").strip()
        )
        if module_path and module_path not in ("pom.xml", "./pom.xml"):
            return f"{artifact_id}包的模块包（{module_path}）"
        return f"{artifact_id}包的全量包"

    if fmt == "composer":
        path = (deploy_payload.get("pomPath") or "").strip()
        if path and path not in ("composer.json", "./composer.json"):
            return f"{artifact_id}包的模块包（{path}）"
        return f"{artifact_id}包的全量包"

    if fmt == "npm":
        path = (deploy_payload.get("pomPath") or "").strip()
        if path and path not in ("package.json", "./package.json"):
            return f"{artifact_id}包的模块包（{path}）"
        return f"{artifact_id}包的全量包"

    return f"{artifact_id}包"


def _final_status_message(result_resp: Dict[str, Any]) -> str:
    msg = (result_resp.get("msg") or result_resp.get("message") or "").strip()
    if msg:
        return msg
    data = result_resp.get("data")
    if isinstance(data, dict):
        version = (str(data.get("version") or "")).strip()
        record_id = data.get("id")
        project_id = data.get("projectId")
        if version and record_id not in (None, "") and project_id not in (None, ""):
            return f"版本{version} 发布成功"
        inner_status = data.get("status")
        if inner_status == 1:
            return "发布成功"
        if inner_status == 0:
            return "处理中"
    if result_resp.get("status") == 0:
        return "发布成功"
    return "未知状态"


def _build_snapshot_override_payload(
    base_payload: Dict[str, Any],
    result_resp: Dict[str, Any],
) -> Optional[Dict[str, Any]]:
    data = result_resp.get("data")
    if not isinstance(data, dict):
        return None
    required_keys = ["groupId", "artifactId", "version", "projectId", "commitId"]
    if any(data.get(k) in (None, "") for k in required_keys):
        return None

    payload = dict(base_payload)
    payload["snapshotConfirm"] = True
    payload["checkAccess"] = 1
    payload["groupId"] = data.get("groupId")
    payload["artifactId"] = data.get("artifactId")
    payload["version"] = data.get("version")
    payload["projectId"] = data.get("projectId")
    payload["commitId"] = data.get("commitId")
    payload["workSpaceUUID"] = data.get("workSpaceUUID") or ""
    payload["requestUUID"] = str(uuid.uuid4())
    return payload


def _poll_publish_result(workspace_uuid: str, token: str, max_attempts: int = 5) -> Dict[str, Any]:
    result_url = f"{API_BASE}/getResultForSkill"
    payload = {"workSpaceUUID": workspace_uuid, "token": token}
    last_resp: Dict[str, Any] = {}
    for attempt in range(1, max_attempts + 1):
        result_resp = _http_post_json(result_url, payload, token=token)
        last_resp = result_resp
        status = _extract_result_status(result_resp)
        if status is None or status != 4:
            return result_resp
        if attempt < max_attempts:
            time.sleep(2)
    return last_resp


def _print_param_source_options(
    quick_deploy_payload: Dict[str, Any],
    local_deploy_payload: Dict[str, Any],
    quick_data: Dict[str, Any],
    local_data: Dict[str, Any],
) -> None:
    quick_branch = quick_deploy_payload.get("branch") or quick_data.get("gitBranch") or ""
    quick_version = quick_data.get("version") or ""
    local_branch = local_deploy_payload.get("branch") or local_data.get("gitBranch") or ""
    local_version = local_data.get("version") or ""

    quick_preview = json.dumps(
        {
            "location": quick_deploy_payload.get("location"),
            "branch": quick_deploy_payload.get("branch"),
            "pomPath": quick_deploy_payload.get("pomPath"),
            "releaseDescription": quick_deploy_payload.get("releaseDescription"),
        },
        ensure_ascii=False,
    )
    local_preview = json.dumps(
        {
            "location": local_deploy_payload.get("location"),
            "branch": local_deploy_payload.get("branch"),
            "pomPath": local_deploy_payload.get("pomPath"),
            "releaseDescription": local_deploy_payload.get("releaseDescription"),
        },
        ensure_ascii=False,
    )
    print(f"选项 1（上次发布）：branch={quick_branch}，版本 {quick_version}")
    print(f"选项 2（本地参数）：branch={local_branch}，版本 {local_version}")
    print("")
    print("检测到发包请求，请先选择参数来源：")
    print("| 选项 | 参数来源 | 说明 | 参数预览 |")
    print("| --- | --- | --- | --- |")
    print(f"| 1 | 上次发布参数（quickUpload） | 使用 quickUpload 返回参数发布 | `{quick_preview}` |")
    print(f"| 2 | 本地参数 | 使用本地代码解析参数发布 | `{local_preview}` |")
    print("")
    print("选项1（quickUpload）参数：")
    print(json.dumps(quick_deploy_payload, ensure_ascii=False))
    print("")
    print("选项2（本地参数）参数：")
    print(json.dumps(local_deploy_payload, ensure_ascii=False))
    print("")
    print("请选择：")
    print("- 使用上次发布参数：追加 --param-source quick")
    print("- 使用本地参数：追加 --param-source local")


def _print_module_selection_table(modules: list[str]) -> None:
    print("我找到以下模块，请选择发布目标：")
    print("| 选项 | 发布目标 | 说明 |")
    print("| --- | --- | --- |")
    for i, module in enumerate(modules, 1):
        print(f"| {i} | {module} | 发布该模块 |")
    print(f"| {len(modules) + 1} | 全发 | 发布父工程全量包 |")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Publish package by quickUpload + deploy*ForSkill, then print human-friendly deploy result.",
    )
    parser.add_argument("--cwd", default=None, help="Directory to start auto parameter detection.")
    parser.add_argument("--groupId", default=None, help="Package groupId. npm can be empty.")
    parser.add_argument("--artifactId", default=None, help="Package artifactId.")
    parser.add_argument(
        "--branch",
        default=None,
        help="When provided, skip quickUpload and build deploy parameters from local project code.",
    )
    parser.add_argument(
        "--param-source",
        choices=["quick", "local"],
        default=None,
        help="Parameter source for deploy payload. quick=quickUpload, local=local project parsing.",
    )
    parser.add_argument(
        "--confirm-snapshot",
        action="store_true",
        help="When getResultForSkill returns snapshot overwrite confirmation(status=2), auto send override deploy request.",
    )
    parser.add_argument(
        "--module",
        default=None,
        help="For multi-module Maven project: publish a specific module by module directory name.",
    )
    parser.add_argument(
        "--all-modules",
        action="store_true",
        help="For multi-module Maven project: publish parent/all package directly.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Only run quickUpload and print derived deploy payload without calling deploy endpoint.",
    )
    parser.add_argument(
        "type",
        choices=["php", "jar", "npm"],
        help="Package type: php(composer), jar(maven2), npm(npm).",
    )
    args = parser.parse_args()

    fmt = {"php": "composer", "jar": "maven2", "npm": "npm"}[args.type]
    token = _resolve_skill_token()
    cwd = Path(args.cwd).expanduser() if args.cwd else Path.cwd()

    current_manifest = _find_upwards(cwd, _manifest_filename(fmt))
    if current_manifest is None and args.artifactId is None:
        projects = _discover_projects(fmt)
        if projects:
            _print_project_selection_table(fmt, projects)
            return 0

    if fmt == "maven2":
        parent_pom = _find_upwards(cwd, "pom.xml")
        if parent_pom and (not args.module) and (not args.all_modules):
            modules = _parse_pom_modules(parent_pom)
            if modules:
                _print_module_selection_table(modules)
                return 0
        if args.module:
            if not parent_pom:
                raise SystemExit("未找到父工程 pom.xml，无法按模块发布。")
            module_pom = (parent_pom.parent / args.module / "pom.xml").resolve()
            if not module_pom.is_file():
                raise SystemExit(f"未找到模块 pom.xml: {module_pom}")
            cwd = module_pom.parent

    group_id = args.groupId
    artifact_id = args.artifactId
    if not artifact_id:
        auto_group, auto_artifact = _collect_from_project(fmt, cwd)
        group_id = group_id if group_id is not None else auto_group
        artifact_id = auto_artifact
    if not artifact_id:
        raise SystemExit("未获取到 artifactId，请通过 --artifactId 传入或在工程目录执行。")
    if fmt in ("composer", "maven2") and not group_id:
        raise SystemExit("当前类型需要 groupId，请通过 --groupId 传入或在工程目录执行。")

    search_payload = {
        "groupId": group_id if group_id else None,
        "artifactId": artifact_id,
        "format": fmt,
        "token": token,
    }
    current_branch = _current_git_branch(cwd)
    wanted_branch = (args.branch or current_branch or "").strip()
    if args.branch:
        if not current_branch:
            raise SystemExit("未检测到当前工程 git 分支。指定分支发包仅支持在已打开分支的工作区执行。")
        if current_branch != wanted_branch:
            raise SystemExit(
                f"你指定的分支是 {wanted_branch}，当前分支是 {current_branch}。"
                "指定分支只能是当前打开分支，skill 不负责切换分支拿参数。"
            )

    quick_upload_url = f"{API_BASE}/quickUpload"
    quick_resp = _http_post_json(quick_upload_url, search_payload, token=token)
    if quick_resp.get("status") != 0:
        raise SystemExit(f"quickUpload 失败: {json.dumps(quick_resp, ensure_ascii=False)}")
    quick_data = quick_resp.get("data")
    if not isinstance(quick_data, dict):
        raise SystemExit(f"quickUpload 返回 data 为空或格式异常: {json.dumps(quick_resp, ensure_ascii=False)}")

    quick_location = quick_data.get("gitUrl")
    if quick_location in (None, ""):
        fallback_git_path = (quick_data.get("gitPath") or "").strip() or _guess_git_path(cwd)
        fallback_location = _resolve_location_from_path(fallback_git_path, token)
        if fallback_location is not None:
            quick_data["gitUrl"] = fallback_location
            print(f"quickUpload 未返回 gitUrl，已通过 getIdByPath 获取 location={fallback_location}")
        else:
            print("quickUpload 未返回 gitUrl，且 getIdByPath 兜底未获取到 location")

    local_data = _build_local_quick_data(fmt, cwd, wanted_branch or "master")
    local_data["groupId"] = group_id
    local_data["artifactId"] = artifact_id
    location = quick_data.get("gitUrl")
    if location not in (None, ""):
        # local 参数分支仍使用 quickUpload 的 location，保证服务端需要的 numeric id 有效。
        local_data["gitUrl"] = location

    quick_deploy_payload = _build_deploy_payload(fmt, quick_data)
    local_deploy_payload = _build_deploy_payload(fmt, local_data)

    if args.param_source is None:
        _print_param_source_options(quick_deploy_payload, local_deploy_payload, quick_data, local_data)
        return 0

    if args.param_source == "quick":
        data = quick_data
    else:
        if args.branch:
            print(f"检测到分支参数：{wanted_branch}，使用本地参数分支发布。")
        else:
            print("使用本地参数分支发布。")
        data = local_data

    deploy_payload = _build_deploy_payload(fmt, data)
    deploy_payload["token"] = token
    deploy_url = _target_deploy_endpoint(fmt)

    if args.dry_run:
        if args.param_source == "local":
            print("dry-run 模式：已完成本地构参（location 来自 quickUpload），未调用 deploy 接口。")
        elif args.param_source == "quick":
            print("dry-run 模式：已完成 quickUpload 参数构建，未调用 deploy 接口。")
        else:
            print("dry-run 模式：已展示参数选项，未调用 deploy 接口。")
    else:
        deploy_resp = _http_post_json(deploy_url, deploy_payload, token=token)
        print("deploy 接口人性化结果:")
        print(_humanize_deploy_response(deploy_resp))
        print("deploy 接口原始返回:")
        print(json.dumps(deploy_resp, ensure_ascii=False))
        workspace_uuid = _extract_workspace_uuid(deploy_resp)
        if not workspace_uuid:
            print("未从 deploy 返回中获取到 workSpaceUUID，跳过 getResultForSkill 轮询。")
            return 0
        print(f"开始轮询 getResultForSkill，workSpaceUUID={workspace_uuid}，每 2 秒查询一次，最多 5 次...")
        result_resp = _poll_publish_result(workspace_uuid, token, max_attempts=5)
        print("getResultForSkill 最终返回:")
        print(json.dumps(result_resp, ensure_ascii=False))
        final_status = _extract_result_status(result_resp)
        if final_status == 4:
            print("轮询已达到 5 次上限，当前任务仍在进行中。")
        _remind_if_version_mismatch(data.get("version"), result_resp)
        final_msg = _final_status_message(result_resp)
        scope_desc = _package_scope_desc(fmt, artifact_id, deploy_payload)
        print(f"{scope_desc}发布结束，状态为{final_msg}。")
        if fmt == "maven2" and _extract_result_status(result_resp) == 2:
            should_override = False
            if args.confirm_snapshot:
                should_override = True
            else:
                print("检测到 status=2（需要确认覆盖）。")
                print("如需继续覆盖发布，请输入：需要覆盖（或 是）；其他输入将取消。")
                try:
                    answer = input("是否覆盖发布: ").strip()
                except EOFError:
                    answer = ""
                if answer in ("需要覆盖", "是", "yes", "y", "Y", "YES"):
                    should_override = True
                else:
                    print("已取消覆盖发布。")
            if should_override:
                override_payload = _build_snapshot_override_payload(deploy_payload, result_resp)
                if override_payload is None:
                    print("检测到覆盖发布确认，但返回数据不足，无法自动构建覆盖参数。")
                    return 0
                override_payload["token"] = token
                print("已选择覆盖发布，开始构建覆盖参数并二次调用 deployJarForSkill...")
                print("覆盖发布参数:")
                print(json.dumps(override_payload, ensure_ascii=False))
                override_resp = _http_post_json(deploy_url, override_payload, token=token)
                print("覆盖发布 deploy 接口返回:")
                print(json.dumps(override_resp, ensure_ascii=False))
                override_workspace_uuid = _extract_workspace_uuid(override_resp)
                if not override_workspace_uuid:
                    print("覆盖发布未返回 workSpaceUUID，流程结束。")
                    return 0
                print(f"开始轮询覆盖发布结果，workSpaceUUID={override_workspace_uuid}，每 2 秒查询一次，最多 5 次...")
                override_result = _poll_publish_result(override_workspace_uuid, token, max_attempts=5)
                print("覆盖发布 getResultForSkill 最终返回:")
                print(json.dumps(override_result, ensure_ascii=False))
                override_msg = _final_status_message(override_result)
                print(f"{scope_desc}覆盖发布结束，状态为{override_msg}。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
