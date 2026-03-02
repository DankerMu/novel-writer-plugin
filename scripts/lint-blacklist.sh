#!/usr/bin/env bash
#
# Deterministic AI-blacklist linter (M3+ extension point).
#
# Usage:
#   lint-blacklist.sh <chapter.md> <ai-blacklist.json>
#
# Output:
#   stdout JSON (exit 0 on success)
#
# Exit codes:
#   0 = success (valid JSON emitted to stdout)
#   1 = validation failure (bad args, missing files, invalid JSON/schema)
#   2 = script exception (unexpected runtime error)
#
# Notes:
# - Treats optional whitelist/exemptions as "do not count as hits":
#     - ai-blacklist.json.whitelist (list[str])
#     - ai-blacklist.json.whitelist.words (list[str])
#     - ai-blacklist.json.exemptions.words (list[str])
#
# - Hit rate is computed as "hits per 1000 non-whitespace characters" (次/千字).

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: lint-blacklist.sh <chapter.md> <ai-blacklist.json>" >&2
  exit 1
fi

chapter_path="$1"
blacklist_path="$2"

if [ ! -f "$chapter_path" ]; then
  echo "lint-blacklist.sh: chapter file not found: $chapter_path" >&2
  exit 1
fi

if [ ! -f "$blacklist_path" ]; then
  echo "lint-blacklist.sh: blacklist file not found: $blacklist_path" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_VENV_PY="${SCRIPT_DIR}/../.venv/bin/python3"
if [ -x "$_VENV_PY" ]; then
  PYTHON="$_VENV_PY"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
else
  echo "lint-blacklist.sh: python3 not found (run: python3 -m venv .venv in plugin root)" >&2
  exit 2
fi

"$PYTHON" - "$chapter_path" "$blacklist_path" <<'PY'
import json
import re
import sys
from typing import Any, Dict, List, Set


def _die(msg: str, exit_code: int = 1) -> None:
    sys.stderr.write(msg.rstrip() + "\n")
    raise SystemExit(exit_code)


def _load_json(path: str) -> Any:
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        _die(f"lint-blacklist.sh: invalid JSON at {path}: {e}", 1)


def _as_str_list(value: Any) -> List[str]:
    if value is None:
        return []
    if not isinstance(value, list):
        return []
    out: List[str] = []
    for item in value:
        if isinstance(item, str) and item.strip():
            out.append(item.strip())
    return out


def _get_whitelist_words(blacklist: Dict[str, Any]) -> Set[str]:
    words: List[str] = []

    whitelist = blacklist.get("whitelist")
    if isinstance(whitelist, list):
        words.extend(_as_str_list(whitelist))
    elif isinstance(whitelist, dict):
        words.extend(_as_str_list(whitelist.get("words")))

    exemptions = blacklist.get("exemptions")
    if isinstance(exemptions, dict):
        words.extend(_as_str_list(exemptions.get("words")))

    return set(words)


def _unique_preserve_order(items: List[str]) -> List[str]:
    seen: Set[str] = set()
    out: List[str] = []
    for item in items:
        if item in seen:
            continue
        seen.add(item)
        out.append(item)
    return out


def main() -> None:
    chapter_path = sys.argv[1]
    blacklist_path = sys.argv[2]

    blacklist = _load_json(blacklist_path)
    if not isinstance(blacklist, dict):
        _die("lint-blacklist.sh: ai-blacklist.json must be a JSON object", 1)

    words = blacklist.get("words")
    if not isinstance(words, list) or not all(isinstance(w, str) for w in words):
        _die("lint-blacklist.sh: ai-blacklist.json.words must be a list of strings", 1)

    whitelist = _get_whitelist_words(blacklist)

    # Extract narration_only words from categories
    narration_only_words: Set[str] = set()
    categories = blacklist.get("categories", {})
    for _cat_key, cat_val in categories.items():
        if isinstance(cat_val, dict) and cat_val.get("narration_only"):
            for w in _as_str_list(cat_val.get("words", [])):
                narration_only_words.add(w)

    effective_words = [w.strip() for w in words if isinstance(w, str) and w.strip() and w.strip() not in whitelist]
    effective_words = list(dict.fromkeys(effective_words))  # dedup preserving order

    # Sort by length descending to match longest phrases first
    effective_words.sort(key=lambda w: -len(w))

    try:
        with open(chapter_path, "r", encoding="utf-8") as f:
            text = f.read()
    except Exception as e:
        _die(f"lint-blacklist.sh: failed to read chapter: {e}", 1)

    lines = text.splitlines()
    non_ws_chars = len(re.sub(r"\s+", "", text))

    # Use a working copy for masking matched phrases
    masked_text = text

    hits: List[Dict[str, Any]] = []
    total_hits = 0

    for word in effective_words:
        count = masked_text.count(word)
        if count <= 0:
            continue
        total_hits += count

        # Collect line numbers and snippets from ORIGINAL text
        line_numbers: List[int] = []
        snippets: List[str] = []
        for idx, line in enumerate(lines, start=1):
            if word in line:
                line_numbers.append(idx)
                if len(snippets) < 5:
                    snippet = line.strip()
                    if len(snippet) > 160:
                        snippet = snippet[:160] + "…"
                    snippets.append(snippet)

        hits.append(
            {
                "word": word,
                "count": count,
                "lines": line_numbers[:20],
                "snippets": snippets,
            }
        )

        # Mask matched word in working copy to prevent substring double-counting
        masked_text = masked_text.replace(word, "\x00" * len(word))

    hits.sort(key=lambda x: (-int(x["count"]), str(x["word"])))

    # --- narration_only stats: check if hits are inside quotes ---
    # Use masked_lines to avoid counting substrings already consumed by longer phrases
    masked_lines = masked_text.splitlines()
    narration_only_narration_hits = 0
    narration_only_dialogue_skipped = 0
    narration_only_details: List[Dict[str, Any]] = []

    for hit_entry in hits:
        w = hit_entry["word"]
        if w not in narration_only_words:
            continue
        for idx, (mline, oline) in enumerate(zip(masked_lines, lines), start=1):
            if w not in mline:
                continue
            # Chinese double-quote parity: count \u201c before each occurrence in original line
            pos = 0
            while True:
                found = mline.find(w, pos)
                if found == -1:
                    break
                prefix = oline[:found]
                open_quotes = prefix.count("\u201c")
                close_quotes = prefix.count("\u201d")
                in_dialogue = (open_quotes > close_quotes)
                if in_dialogue:
                    narration_only_dialogue_skipped += 1
                else:
                    narration_only_narration_hits += 1
                    if len(narration_only_details) < 10:
                        snippet = oline.strip()
                        if len(snippet) > 160:
                            snippet = snippet[:160] + "\u2026"
                        narration_only_details.append(
                            {"word": w, "line": idx, "in_dialogue": in_dialogue, "snippet": snippet}
                        )
                pos = found + len(w)

    narration_only_stats: Dict[str, Any] = {
        "narration_only_narration_hits": narration_only_narration_hits,
        "narration_only_dialogue_skipped": narration_only_dialogue_skipped,
        "narration_only_per_kchars": round(narration_only_narration_hits / (non_ws_chars / 1000.0), 3) if non_ws_chars > 0 else 0.0,
        "details": narration_only_details,
    }

    hits_per_kchars = 0.0
    if non_ws_chars > 0:
        hits_per_kchars = total_hits / (non_ws_chars / 1000.0)

    out: Dict[str, Any] = {
        "chapter_path": chapter_path,
        "blacklist_path": blacklist_path,
        "chars": non_ws_chars,
        "blacklist_words_count": len(words),
        "whitelist_words_count": len(whitelist),
        "effective_words_count": len(effective_words),
        "total_hits": total_hits,
        "hits_per_kchars": round(hits_per_kchars, 3),
        "hits": hits,
        "narration_only_stats": narration_only_stats,
    }

    sys.stdout.write(json.dumps(out, ensure_ascii=False) + "\n")


try:
    main()
except SystemExit:
    raise
except Exception as e:
    sys.stderr.write(f"lint-blacklist.sh: unexpected error: {e}\n")
    raise SystemExit(2)
PY
