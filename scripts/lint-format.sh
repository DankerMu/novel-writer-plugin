#!/usr/bin/env bash
#
# Deterministic format rule linter for novel chapters.
#
# Usage:
#   lint-format.sh <chapter.md>
#
# Output:
#   stdout JSON (exit 0 on success)
#
# Exit codes:
#   0 = success (valid JSON emitted to stdout)
#   1 = validation failure (bad args, missing files)
#   2 = script exception (unexpected runtime error)
#
# Checks:
#   - Em-dash (—— / —) → severity=error
#   - Non-corner-bracket quotes ("" '' "" "") → severity=error
#   - Horizontal rules (--- / *** / * * *) → severity=error
#   - Char count < 2500 or > 3500 → severity=warning

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: lint-format.sh <chapter.md>" >&2
  exit 1
fi

chapter_path="$1"

if [ ! -f "$chapter_path" ]; then
  echo "lint-format.sh: chapter file not found: $chapter_path" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_VENV_PY="${SCRIPT_DIR}/../.venv/bin/python3"
if [ -x "$_VENV_PY" ]; then
  PYTHON="$_VENV_PY"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
else
  echo "lint-format.sh: python3 not found (run: python3 -m venv .venv in plugin root)" >&2
  exit 2
fi

"$PYTHON" - "$chapter_path" <<'PY'
import json
import re
import sys
from typing import Any, Dict, List


def scan(text: str, lines: List[str]) -> Dict[str, Any]:
    non_ws = len(re.sub(r"\s+", "", text))
    checks: List[Dict[str, Any]] = []

    # --- 1. Em-dash detection (error) ---
    em_dash_matches: List[Dict[str, Any]] = []
    for idx, line in enumerate(lines, start=1):
        for m in re.finditer(r"\u2014{1,2}", line):
            snippet = line.strip()
            if len(snippet) > 160:
                snippet = snippet[:160] + "\u2026"
            em_dash_matches.append({
                "text": m.group(),
                "line": idx,
                "snippet": snippet,
            })
    em_count = len(em_dash_matches)
    checks.append({
        "category": "em_dash",
        "severity": "error",
        "status": "violation" if em_count > 0 else "pass",
        "count": em_count,
        "detail": f"破折号（——/—）出现 {em_count} 处" if em_count else "无破折号",
        "matches": em_dash_matches[:10],
    })

    # --- 2. Non-corner-bracket quote detection (error) ---
    # Corner brackets: \u300c \u300d (「」, used as standard)
    # Detect: straight double " (U+0022), Chinese double "" (U+201c/U+201d),
    #         curly single '' (U+2018/U+2019), straight single ' (U+0027)
    quote_pattern = re.compile(r'["\u201c\u201d\u2018\u2019\']')
    quote_matches: List[Dict[str, Any]] = []
    for idx, line in enumerate(lines, start=1):
        for m in quote_pattern.finditer(line):
            snippet = line.strip()
            if len(snippet) > 160:
                snippet = snippet[:160] + "\u2026"
            quote_matches.append({
                "text": m.group(),
                "line": idx,
                "snippet": snippet,
            })
    quote_count = len(quote_matches)
    checks.append({
        "category": "non_cn_quote",
        "severity": "error",
        "status": "violation" if quote_count > 0 else "pass",
        "count": quote_count,
        "detail": f"非直角引号出现 {quote_count} 处" if quote_count else "引号格式正确",
        "matches": quote_matches[:10],
    })

    # --- 3. Horizontal rule detection (error) ---
    hr_pattern = re.compile(r"^(?:---+|\*\*\*+|\* \* \*)\s*$")
    hr_matches: List[Dict[str, Any]] = []
    for idx, line in enumerate(lines, start=1):
        if hr_pattern.match(line.strip()):
            hr_matches.append({
                "text": line.strip(),
                "line": idx,
                "snippet": line.strip(),
            })
    hr_count = len(hr_matches)
    checks.append({
        "category": "horizontal_rule",
        "severity": "error",
        "status": "violation" if hr_count > 0 else "pass",
        "count": hr_count,
        "detail": f"分隔线出现 {hr_count} 处" if hr_count else "无分隔线",
        "matches": hr_matches[:10],
    })

    # --- 4. Char count check (warning) ---
    char_status = "pass"
    char_detail = f"字数 {non_ws}"
    if non_ws < 2500:
        char_status = "warning"
        char_detail = f"字数偏短：{non_ws}（下限 2500）"
    elif non_ws > 3500:
        char_status = "warning"
        char_detail = f"字数偏长：{non_ws}（上限 3500）"
    checks.append({
        "category": "char_count",
        "severity": "warning",
        "status": char_status,
        "count": 0 if char_status == "pass" else 1,
        "detail": char_detail,
    })

    # --- Aggregate ---
    total_errors = sum(c["count"] for c in checks if c["severity"] == "error")
    total_warnings = sum(c["count"] for c in checks if c["severity"] == "warning" and c["status"] != "pass")

    return {
        "chapter_path": sys.argv[1],
        "chars": non_ws,
        "total_hits": total_errors + total_warnings,
        "errors": total_errors,
        "warnings": total_warnings,
        "checks": [c for c in checks],
    }


def main() -> None:
    path = sys.argv[1]
    try:
        with open(path, "r", encoding="utf-8") as f:
            text = f.read()
    except Exception as e:
        sys.stderr.write(f"lint-format.sh: failed to read: {e}\n")
        raise SystemExit(1)

    lines = text.splitlines()
    result = scan(text, lines)
    sys.stdout.write(json.dumps(result, ensure_ascii=False) + "\n")


try:
    main()
except SystemExit:
    raise
except Exception as e:
    sys.stderr.write(f"lint-format.sh: unexpected error: {e}\n")
    raise SystemExit(2)
PY
