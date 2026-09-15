#!/usr/bin/env python3
import argparse
from pathlib import Path
from typing import Optional
from urllib.parse import urlencode
import xml.etree.ElementTree as ET


PUBLISH_TABLE_BASE = "https://ee.58corp.com/base2/irepo/publishTable"


def _build_url(*, group_id: Optional[str], artifact_id: str, fmt: str) -> str:
    params: list[tuple[str, str]] = []
    if group_id:
        params.append(("groupId", group_id))
    params.append(("artifactId", artifact_id))
    params.append(("format", fmt))
    return f"{PUBLISH_TABLE_BASE}?{urlencode(params, safe='')}"


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


def _locate_skill_market_root() -> Optional[Path]:
    home = Path.home()
    candidates = [
        home / "IdeaProjects" / "skill-market-service",
        home / "trae" / "skill-market-service",
    ]
    for c in candidates:
        if c.is_dir():
            return c
    return None


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Shortcut: locate local skill-market project and output one-line publishTable link.",
    )
    parser.add_argument(
        "project",
        help='Project keyword. Currently supports: "skill-market".',
        choices=["skill-market"],
    )
    args = parser.parse_args()

    if args.project == "skill-market":
        root = _locate_skill_market_root()
        if not root:
            raise SystemExit("未找到工程目录：~/IdeaProjects/skill-market-service 或 ~/trae/skill-market-service")
        pom = root / "arch-wcloud-skill-market-api" / "pom.xml"
        if not pom.is_file():
            raise SystemExit(f"未找到模块 POM：{pom}")
        group_id, artifact_id = _parse_pom_coordinates(pom)
        if not group_id or not artifact_id:
            raise SystemExit(f"无法从 POM 解析 groupId/artifactId：{pom}")
        url = _build_url(group_id=group_id, artifact_id=artifact_id, fmt="maven2")
        print(f"点击链接去发包：{url}")
        return 0

    raise AssertionError("unreachable")


if __name__ == "__main__":
    raise SystemExit(main())
