#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
from typing import Optional
from urllib.parse import urlencode
import xml.etree.ElementTree as ET


BASE = "https://ee.58corp.com/base2/irepo/publishTable"


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


def _parse_json_name(path: Path) -> Optional[str]:
    try:
        obj = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None
    name = obj.get("name")
    if not isinstance(name, str):
        return None
    name = name.strip()
    return name or None


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
        v = elem.text.strip()
        return v or None

    artifact_id = text(root.find(q("artifactId")))
    group_id = text(root.find(q("groupId")))
    if not group_id:
        parent = root.find(q("parent"))
        if parent is not None:
            group_id = text(parent.find(q("groupId")))
    return group_id, artifact_id


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


def build_url(*, group_id: Optional[str], artifact_id: str, fmt: str) -> str:
    params = []
    if group_id:
        params.append(("groupId", group_id))
    params.append(("artifactId", artifact_id))
    params.append(("format", fmt))
    return f"{BASE}?{urlencode(params, safe='')}"


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate iRepo publishTable confirmation links only.")
    parser.add_argument(
        "--cwd",
        default=None,
        help="Directory to start auto-detection (defaults to current working directory).",
    )
    parser.add_argument(
        "--print-md",
        action="store_true",
        help="Also print a Markdown clickable link line before the raw URL.",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    php = sub.add_parser("php", help="PHP Composer confirmation link (format=composer)")
    php.add_argument("--groupId", required=False)
    php.add_argument("--artifactId", required=False)
    php.add_argument("--composer", default=None, help="Path to composer.json (optional for auto-detection)")

    jar = sub.add_parser("jar", help="Maven2 JAR confirmation link (format=maven2)")
    jar.add_argument("--groupId", required=False)
    jar.add_argument("--artifactId", required=False)
    jar.add_argument("--pom", default=None, help="Path to pom.xml (optional for auto-detection)")
    jar.add_argument("--module", default=None, help="Maven module name (relative path) to publish when multi-module")

    npm = sub.add_parser("npm", help="npm confirmation link (format=npm)")
    npm.add_argument("--artifactId", required=False)
    npm.add_argument("--groupId", default=None, help="Optional groupId (can be empty)")
    npm.add_argument("--package-json", default=None, help="Path to package.json (optional for auto-detection)")

    args = parser.parse_args()
    start_dir = Path(args.cwd).expanduser() if args.cwd else Path.cwd()

    if args.cmd == "php":
        group_id = args.groupId
        artifact_id = args.artifactId
        if not group_id or not artifact_id:
            composer_path = Path(args.composer).expanduser() if args.composer else _find_upwards(start_dir, "composer.json")
            if composer_path:
                name = _parse_json_name(composer_path)
                if name and "/" in name:
                    vendor, pkg = name.split("/", 1)
                    group_id = group_id or vendor
                    artifact_id = artifact_id or pkg
        if not group_id or not artifact_id:
            raise SystemExit("php needs --groupId and --artifactId (or a composer.json with name=vendor/name).")
        url = build_url(group_id=group_id, artifact_id=artifact_id, fmt="composer")
        if args.print_md:
            print(f"[打开 iRepo 确认页]({url})")
        print(url)
        return 0

    if args.cmd == "jar":
        group_id = args.groupId
        artifact_id = args.artifactId
        pom_path = Path(args.pom).expanduser() if args.pom else _find_upwards(start_dir, "pom.xml")

        if pom_path:
            if args.module:
                module_pom = (pom_path.parent / args.module / "pom.xml").resolve()
                if not module_pom.is_file():
                    raise SystemExit(f"module pom not found: {module_pom}")
                g, a = _parse_pom_coordinates(module_pom)
                group_id = group_id or g
                artifact_id = artifact_id or a
            else:
                if not group_id or not artifact_id:
                    modules = _parse_pom_modules(pom_path)
                    if modules:
                        print("有以下模块：" + ", ".join(modules))
                        print("请指定要发包的模块名称，或者告诉我发parent包。")
                        preferred = None
                        for m in modules:
                            if "api" in m.lower():
                                preferred = m
                                break
                        if not preferred:
                            for m in modules:
                                if "contract" in m.lower():
                                    preferred = m
                                    break
                        if not preferred:
                            preferred = modules[0]
                        module_pom = (pom_path.parent / preferred / "pom.xml").resolve()
                        g, a = _parse_pom_coordinates(module_pom)
                        if g and a:
                            url = build_url(group_id=g, artifact_id=a, fmt="maven2")
                            print(f"推荐模块链接（{preferred}），点击去发包：{url}")
                        return 0
                g, a = _parse_pom_coordinates(pom_path)
                group_id = group_id or g
                artifact_id = artifact_id or a

        if not group_id or not artifact_id:
            raise SystemExit("jar needs --groupId and --artifactId (or a parseable pom.xml).")
        url = build_url(group_id=group_id, artifact_id=artifact_id, fmt="maven2")
        if args.print_md:
            print(f"[打开 iRepo 确认页]({url})")
        print(url)
        return 0

    if args.cmd == "npm":
        group_id = args.groupId
        artifact_id = args.artifactId
        if not artifact_id:
            pkg_path = Path(args.package_json).expanduser() if args.package_json else _find_upwards(start_dir, "package.json")
            if pkg_path:
                name = _parse_json_name(pkg_path)
                if name:
                    # @scope/name -> groupId=scope, artifactId=name
                    if name.startswith("@") and "/" in name:
                        scope, pkg = name.split("/", 1)
                        group_id = group_id or scope.lstrip("@")
                        artifact_id = pkg
                    else:
                        artifact_id = name
        if not artifact_id:
            raise SystemExit("npm needs --artifactId (or a package.json with name).")
        url = build_url(group_id=group_id, artifact_id=artifact_id, fmt="npm")
        if args.print_md:
            print(f"[打开 iRepo 确认页]({url})")
        print(url)
        return 0

    raise AssertionError("unreachable")


if __name__ == "__main__":
    raise SystemExit(main())
