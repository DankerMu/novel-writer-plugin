#!/usr/bin/env bash
#
# Deterministic meta-information leak detector for novel chapters.
#
# Usage:
#   lint-meta-leak.sh <chapter.md>
#
# Output:
#   stdout JSON (exit 0 on success)
#
# Exit codes:
#   0 = success (valid JSON emitted to stdout)
#   1 = validation failure (bad args, missing files)
#   2 = script exception (unexpected runtime error)
#
# Detects structural metadata that should never appear in novel prose:
#   - Foreshadowing/rule/storyline codes (F-001, W-003, SL-MAIN-01)
#   - Technical field names (pipeline_stage, slug_id, etc.)
#   - JSON blocks, file paths, Markdown artifacts
#   - Volume/chapter structural references (卷五, 第三卷, 第48章)
#   - Agent names, score patterns, system prompt tags

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: lint-meta-leak.sh <chapter.md>" >&2
  exit 1
fi

chapter_path="$1"

if [ ! -f "$chapter_path" ]; then
  echo "lint-meta-leak.sh: chapter file not found: $chapter_path" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_VENV_PY="${SCRIPT_DIR}/../.venv/bin/python3"
if [ -x "$_VENV_PY" ]; then
  PYTHON="$_VENV_PY"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
else
  echo "lint-meta-leak.sh: python3 not found (run: python3 -m venv .venv in plugin root)" >&2
  exit 2
fi

"$PYTHON" - "$chapter_path" <<'PY'
import json
import re
import sys
from typing import Any, Dict, List, Tuple

CN_NUMS = r"[一二三四五六七八九十百千万零]"

CATEGORIES: List[Dict[str, Any]] = [
    {
        "id": "meta_code",
        "description": "伏笔/规则/故事线/角色代号",
        "severity": "error",
        "patterns": [
            (r"F-\d{3}", "伏笔代号 (F-XXX)"),
            (r"W-\d{3}", "世界规则代号 (W-XXX)"),
            (r"SL-[A-Z]+-\d+", "故事线 ID"),
            (r"C-[A-Z]+-\d+", "角色契约 ID"),
            (r"OBJ-\d+-\d+", "目标 ID"),
            (r"LS-\d{3}", "故事线规范 ID"),
        ],
    },
    {
        "id": "tech_field",
        "description": "技术字段名",
        "severity": "error",
        "patterns": [
            (
                r"(?:pipeline_stage|orchestrator_state|inflight_chapter|slug_id"
                r"|storyline_id|schema_version|last_completed_chapter|current_volume"
                r"|pov_character|gate_decision|excitement_type|canon_status"
                r"|constraint_type|hook_event|tool_input|tool_name"
                r"|permissionDecision|acceptance_criteria|postconditions"
                r"|preconditions|narration_only|hits_per_kchars)",
                "snake_case/camelCase 技术字段",
            ),
        ],
    },
    {
        "id": "json_block",
        "description": "JSON 结构泄漏",
        "severity": "error",
        "patterns": [
            (r'\{\s*"[a-z_]+"\s*:', "JSON 对象片段"),
        ],
    },
    {
        "id": "file_path",
        "description": "文件路径/系统路径",
        "severity": "error",
        "patterns": [
            (r"chapter-\d{3}", "章节文件名格式"),
            (r"vol-\d{2}", "卷目录格式"),
            (r"\.checkpoint\.json", "checkpoint 文件名"),
            (r"staging/", "staging 路径"),
            (r"chapter-contracts/", "契约目录路径"),
            (r"storylines\.json", "故事线文件名"),
            (r"rules\.json", "规则文件名"),
            (r"ai-blacklist\.json", "黑名单文件名"),
            (r"style-profile\.json", "风格配置文件名"),
        ],
    },
    {
        "id": "markdown_artifact",
        "description": "Markdown 格式泄漏",
        "severity": "error",
        "patterns": [
            (r"\|[-:]+\|", "Markdown 表格分隔线"),
            (
                r"^###?\s*(?:验收标准|局势变化|冲突与抉择|钩子|基本信息"
                r"|事件中自然流露|事件中自然推进|世界规则约束|前章衔接)",
                "契约段落标题",
            ),
        ],
    },
    {
        "id": "layer_ref",
        "description": "四层规范引用",
        "severity": "error",
        "patterns": [
            (r"L[123S]\s*(?:规则|契约|合约|层|spec|check|世界|角色|章节|故事线)", "层级规范引用"),
        ],
    },
    {
        "id": "agent_name",
        "description": "Agent 名称泄漏",
        "severity": "error",
        "patterns": [
            (
                r"(?:PlotArchitect|ChapterWriter|QualityJudge|Summarizer|WorldBuilder"
                r"|StyleRefiner|AudienceEval|CharacterWeaver|StyleAnalyzer)",
                "Agent 名称",
            ),
        ],
    },
    {
        "id": "score_pattern",
        "description": "评分/打分结构",
        "severity": "error",
        "patterns": [
            (r"(?:评分|得分|打分|score)[：:]\s*[\d.]+", "评分数值"),
            (r"[\d.]+\s*/\s*5(?:\.0)?(?:\s*分)?", "X/5 评分格式"),
        ],
    },
    {
        "id": "system_tag",
        "description": "系统/模型标签",
        "severity": "error",
        "patterns": [
            (r"</?(?:system|user|assistant|thinking|reflection|output|answer)>", "系统标签"),
            (r"```(?:json|python|bash|markdown)", "代码块标记"),
        ],
    },
    {
        "id": "volume_ref",
        "description": "卷号结构引用",
        "severity": "warning",
        "patterns": [
            (rf"第{CN_NUMS}+卷", "中文序数卷号（第X卷）"),
            (rf"卷{CN_NUMS}+", "中文卷号（卷X）"),
            (r"第\d+卷", "数字序数卷号"),
            (r"卷\d+", "数字卷号"),
        ],
    },
    {
        "id": "chapter_ref",
        "description": "章号结构引用（非标题位置）",
        "severity": "warning",
        "patterns": [
            # Only match chapter refs NOT at the beginning of a line (skip titles)
            (rf"(?<=.)第{CN_NUMS}+章", "中文章号引用"),
            (r"(?<=.)第\d+章", "数字章号引用"),
        ],
    },
    {
        "id": "meta_narration",
        "description": "元叙述（打破第四面墙）",
        "severity": "warning",
        "patterns": [
            (r"(?:上一章|下一章|本章|前文|后文)(?:提到|所述|中|里|说过|讲过)", "章节自引用"),
        ],
    },
]


def scan(text: str, lines: List[str]) -> Dict[str, Any]:
    non_ws = len(re.sub(r"\s+", "", text))
    all_hits: List[Dict[str, Any]] = []
    total_errors = 0
    total_warnings = 0

    for cat in CATEGORIES:
        cat_id = cat["id"]
        severity = cat["severity"]
        for pattern_str, label in cat["patterns"]:
            flags = re.MULTILINE if pattern_str.startswith("^") else 0
            try:
                regex = re.compile(pattern_str, flags)
            except re.error:
                continue

            matches: List[Dict[str, Any]] = []
            for idx, line in enumerate(lines, start=1):
                for m in regex.finditer(line):
                    snippet = line.strip()
                    if len(snippet) > 160:
                        snippet = snippet[:160] + "\u2026"
                    matches.append({
                        "text": m.group(),
                        "line": idx,
                        "snippet": snippet,
                    })

            if not matches:
                continue

            count = len(matches)
            if severity == "error":
                total_errors += count
            else:
                total_warnings += count

            all_hits.append({
                "category": cat_id,
                "severity": severity,
                "description": label,
                "pattern": pattern_str,
                "count": count,
                "matches": matches[:10],  # cap at 10 per pattern
            })

    total = total_errors + total_warnings
    return {
        "chapter_path": sys.argv[1],
        "chars": non_ws,
        "total_hits": total,
        "errors": total_errors,
        "warnings": total_warnings,
        "hits_per_kchars": round(total / (non_ws / 1000.0), 3) if non_ws > 0 else 0.0,
        "hits": sorted(all_hits, key=lambda h: (0 if h["severity"] == "error" else 1, -h["count"])),
    }


def main() -> None:
    path = sys.argv[1]
    try:
        with open(path, "r", encoding="utf-8") as f:
            text = f.read()
    except Exception as e:
        sys.stderr.write(f"lint-meta-leak.sh: failed to read: {e}\n")
        raise SystemExit(1)

    lines = text.splitlines()
    result = scan(text, lines)
    sys.stdout.write(json.dumps(result, ensure_ascii=False) + "\n")


try:
    main()
except SystemExit:
    raise
except Exception as e:
    sys.stderr.write(f"lint-meta-leak.sh: unexpected error: {e}\n")
    raise SystemExit(2)
PY
