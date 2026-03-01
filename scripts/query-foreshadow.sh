#!/usr/bin/env bash
#
# Deterministic foreshadowing query (M3+ extension point).
#
# Usage:
#   query-foreshadow.sh <chapter_num>
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
# - Designed to be called from the novel project root (cwd contains .checkpoint.json).
# - Returns only a small subset of relevant foreshadowing items for the target chapter.

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: query-foreshadow.sh <chapter_num>" >&2
  exit 1
fi

chapter_num_raw="$1"

if ! [[ "$chapter_num_raw" =~ ^[0-9]+$ ]]; then
  echo "query-foreshadow.sh: chapter_num must be a positive integer (got: $chapter_num_raw)" >&2
  exit 1
fi

chapter_num="$chapter_num_raw"

if [ "$chapter_num" -le 0 ]; then
  echo "query-foreshadow.sh: chapter_num must be >= 1 (got: $chapter_num)" >&2
  exit 1
fi

checkpoint_path=".checkpoint.json"
if [ ! -f "$checkpoint_path" ]; then
  echo "query-foreshadow.sh: .checkpoint.json not found in cwd; run from the novel project root" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_VENV_PY="${SCRIPT_DIR}/../.venv/bin/python3"
if [ -x "$_VENV_PY" ]; then
  PYTHON="$_VENV_PY"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
else
  echo "query-foreshadow.sh: python3 not found (run: python3 -m venv .venv in plugin root)" >&2
  exit 2
fi

"$PYTHON" - "$chapter_num" <<'PY'
import json
import sys
from typing import Any, Dict, List, Optional, Set, Tuple


def _die(msg: str, exit_code: int = 1) -> None:
    sys.stderr.write(msg.rstrip() + "\n")
    raise SystemExit(exit_code)


def _load_json(path: str) -> Any:
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return None
    except Exception as e:
        _die(f"query-foreshadow.sh: invalid JSON at {path}: {e}", 1)


def _extract_items(data: Any, path: str) -> List[Dict[str, Any]]:
    if data is None:
        return []
    if isinstance(data, list):
        raw_items = data
    elif isinstance(data, dict) and isinstance(data.get("foreshadowing"), list):
        raw_items = data["foreshadowing"]
    else:
        _die(f"query-foreshadow.sh: unsupported schema at {path} (expected list or object.foreshadowing[])", 1)

    items: List[Dict[str, Any]] = []
    for it in raw_items:
        if not isinstance(it, dict):
            continue
        foreshadow_id = it.get("id")
        if not isinstance(foreshadow_id, str) or not foreshadow_id.strip():
            continue
        items.append(it)
    return items


def _as_range(value: Any) -> Optional[Tuple[int, int]]:
    if not isinstance(value, list) or len(value) != 2:
        return None
    a, b = value[0], value[1]
    if not isinstance(a, int) or not isinstance(b, int):
        return None
    if a > b:
        return None
    if a < 1:
        return None
    return (a, b)


def _range_contains(r: Optional[Tuple[int, int]], chapter: int) -> bool:
    if r is None:
        return False
    return r[0] <= chapter <= r[1]


def _is_overdue_short(item: Dict[str, Any], chapter: int) -> bool:
    if item.get("scope") != "short":
        return False
    if item.get("status") == "resolved":
        return False
    r = _as_range(item.get("target_resolve_range"))
    if r is None:
        return False
    return chapter > r[1]


def _is_relevant_from_plan(item: Dict[str, Any], chapter: int) -> bool:
    planted_chapter = item.get("planted_chapter")
    if isinstance(planted_chapter, int) and planted_chapter == chapter:
        return True
    return _range_contains(_as_range(item.get("target_resolve_range")), chapter)


def _is_relevant_from_global(item: Dict[str, Any], chapter: int) -> bool:
    if _range_contains(_as_range(item.get("target_resolve_range")), chapter):
        return True
    return _is_overdue_short(item, chapter)


def _merge_missing(base: Dict[str, Any], fallback: Dict[str, Any], keys: List[str]) -> Dict[str, Any]:
    out = dict(base)
    for k in keys:
        if k not in out or out.get(k) in (None, "", []):
            if k in fallback and fallback.get(k) not in (None, "", []):
                out[k] = fallback.get(k)
    return out


def _normalize_item(item: Dict[str, Any]) -> Dict[str, Any]:
    # Keep a stable subset of fields; pass through unknown fields is intentionally avoided
    # to keep output small and regression-friendly.
    out: Dict[str, Any] = {"id": item.get("id")}
    for k in [
        "description",
        "scope",
        "status",
        "planted_chapter",
        "planted_storyline",
        "target_resolve_range",
        "last_updated_chapter",
        "history",
    ]:
        if k in item:
            out[k] = item.get(k)
    return out


def main() -> None:
    chapter = int(sys.argv[1])

    checkpoint = _load_json(".checkpoint.json")
    if not isinstance(checkpoint, dict):
        _die("query-foreshadow.sh: .checkpoint.json must be a JSON object", 1)
    volume = checkpoint.get("current_volume")
    if not isinstance(volume, int) or volume < 0:
        _die("query-foreshadow.sh: .checkpoint.json.current_volume must be an int >= 0", 1)

    global_path = "foreshadowing/global.json"
    plan_path = f"volumes/vol-{volume:02d}/foreshadowing.json"

    global_items_raw = _extract_items(_load_json(global_path), global_path)
    plan_items_raw = _extract_items(_load_json(plan_path), plan_path)

    global_by_id: Dict[str, Dict[str, Any]] = {str(it["id"]): it for it in global_items_raw}
    plan_by_id: Dict[str, Dict[str, Any]] = {str(it["id"]): it for it in plan_items_raw}

    relevant_ids: List[str] = []
    relevant_from_plan = 0
    relevant_from_global = 0
    overdue_short = 0

    seen: Set[str] = set()

    for foreshadow_id, it in plan_by_id.items():
        if it.get("status") == "resolved":
            continue
        if _is_relevant_from_plan(it, chapter):
            if foreshadow_id not in seen:
                seen.add(foreshadow_id)
                relevant_ids.append(foreshadow_id)
            relevant_from_plan += 1

    for foreshadow_id, it in global_by_id.items():
        if it.get("status") == "resolved":
            continue
        if _is_relevant_from_global(it, chapter):
            if foreshadow_id not in seen:
                seen.add(foreshadow_id)
                relevant_ids.append(foreshadow_id)
            relevant_from_global += 1
            if _is_overdue_short(it, chapter):
                overdue_short += 1

    items: List[Dict[str, Any]] = []
    for foreshadow_id in sorted(relevant_ids):
        base = global_by_id.get(foreshadow_id) or plan_by_id.get(foreshadow_id) or {}
        if not base:
            continue
        merged = base
        if foreshadow_id in global_by_id and foreshadow_id in plan_by_id:
            merged = _merge_missing(global_by_id[foreshadow_id], plan_by_id[foreshadow_id], ["description", "scope", "target_resolve_range"])
        items.append(_normalize_item(merged))

    out: Dict[str, Any] = {
        "schema_version": 1,
        "chapter": chapter,
        "volume": volume,
        "items": items,  # sorted by id ascending (deterministic)
        # stats.relevant_from_plan + stats.relevant_from_global may exceed stats.items
        # because a single item can match relevance criteria from both sources.
        "stats": {
            "items": len(items),
            "relevant_from_plan": relevant_from_plan,
            "relevant_from_global": relevant_from_global,
            "overdue_short": overdue_short,
        },
        "sources": {
            "checkpoint": ".checkpoint.json",
            "global": global_path,
            "volume_plan": plan_path,
        },
    }

    sys.stdout.write(json.dumps(out, ensure_ascii=False) + "\n")


try:
    main()
except SystemExit:
    raise
except Exception as e:
    sys.stderr.write(f"query-foreshadow.sh: unexpected error: {e}\n")
    raise SystemExit(2)
PY

