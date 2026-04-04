#!/usr/bin/env bash
#
# Terminology drift detector for novel chapters.
#
# Usage:
#   lint-terminology.sh <chapter.md> [terminology.json]
#
# Output:
#   stdout JSON (exit 0 on success)
#
# Exit codes:
#   0 = success (valid JSON emitted to stdout)
#   1 = validation failure (bad args, missing files)
#   2 = script exception (unexpected runtime error)
#
# Detects:
#   - Edit-distance variants of character/location terms
#   - Intra-chapter inconsistent references for same entity
#   - All hits are severity=warning (no hard gate)

set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: lint-terminology.sh <chapter.md> [terminology.json]" >&2
  exit 1
fi

chapter_path="$1"
terminology_path="${2:-world/terminology.json}"

if [ ! -f "$chapter_path" ]; then
  echo "lint-terminology.sh: chapter file not found: $chapter_path" >&2
  exit 1
fi

# Graceful skip if terminology.json does not exist
if [ ! -f "$terminology_path" ]; then
  cat <<EOF
{"chapter_path":"$chapter_path","chars":0,"total_hits":0,"errors":0,"warnings":0,"hits":[]}
EOF
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_VENV_PY="${SCRIPT_DIR}/../.venv/bin/python3"
if [ -x "$_VENV_PY" ]; then
  PYTHON="$_VENV_PY"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
else
  echo "lint-terminology.sh: python3 not found (run: python3 -m venv .venv in plugin root)" >&2
  exit 2
fi

"$PYTHON" - "$chapter_path" "$terminology_path" <<'PY'
import json
import re
import sys
from typing import Any, Dict, List, Optional, Set, Tuple


def levenshtein(s1: str, s2: str) -> int:
    """Compute Levenshtein edit distance between two strings (character-level)."""
    if len(s1) < len(s2):
        return levenshtein(s2, s1)
    if len(s2) == 0:
        return len(s1)

    prev_row = list(range(len(s2) + 1))
    for i, c1 in enumerate(s1):
        curr_row = [i + 1]
        for j, c2 in enumerate(s2):
            # Insertions, deletions, substitutions
            insertions = prev_row[j + 1] + 1
            deletions = curr_row[j] + 1
            substitutions = prev_row[j] + (0 if c1 == c2 else 1)
            curr_row.append(min(insertions, deletions, substitutions))
        prev_row = curr_row

    return prev_row[-1]


def extract_cn_ngrams(text: str, min_len: int, max_len: int) -> Dict[str, int]:
    """Extract Chinese n-grams by sliding window over continuous Chinese runs.

    For each run of consecutive Chinese characters, generate all substrings
    of length min_len..max_len. Returns {ngram: count}.
    """
    counts: Dict[str, int] = {}
    for m in re.finditer(r'[\u4e00-\u9fff]+', text):
        run = m.group()
        for n in range(min_len, max_len + 1):
            if n > len(run):
                break
            for i in range(len(run) - n + 1):
                gram = run[i:i + n]
                counts[gram] = counts.get(gram, 0) + 1
    return counts


def collect_matches(lines: List[str], target: str, max_matches: int = 5) -> List[Dict[str, Any]]:
    """Collect line numbers and snippets for a target string in text lines."""
    matches: List[Dict[str, Any]] = []
    for idx, line in enumerate(lines, start=1):
        if target in line:
            snippet = line.strip()
            if len(snippet) > 160:
                snippet = snippet[:160] + "\u2026"
            matches.append({"text": target, "line": idx, "snippet": snippet})
            if len(matches) >= max_matches:
                break
    return matches


def max_edit_distance(term_len: int) -> int:
    """Adaptive max edit distance: short terms (2-3 chars) allow only 1, longer allow 2."""
    if term_len <= 3:
        return 1
    return 2


def is_trivial_extension(gram: str, canonical: str) -> bool:
    """Check if gram contains canonical as a substring — word boundary artifact, not variant."""
    if canonical in gram and gram != canonical:
        return True
    return False


def is_substring_of_term(gram: str, all_canonicals: Set[str]) -> bool:
    """Check if gram is a proper substring of any registered term."""
    for canonical in all_canonicals:
        if gram != canonical and gram in canonical:
            return True
    return False


def scan_variants(text: str, lines: List[str], terms: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Detect edit-distance variants for character/location terms via n-gram sliding window."""
    hits: List[Dict[str, Any]] = []

    check_terms = [
        t for t in terms
        if t.get("category") in ("character", "location")
    ]
    if not check_terms:
        return hits

    all_canonicals: Set[str] = {t["canonical"] for t in terms if t.get("canonical")}

    # Determine n-gram size range: for each term, only generate grams of
    # length within its adaptive edit distance range
    term_lengths = {len(t["canonical"]) for t in check_terms if t.get("canonical")}
    global_min = max(2, min(term_lengths) - 1) if term_lengths else 2
    global_max = max(term_lengths) + 2 if term_lengths else 8

    ngrams = extract_cn_ngrams(text, global_min, global_max)

    for term in check_terms:
        canonical = term.get("canonical", "")
        if not canonical:
            continue

        allow_variants = set(term.get("allow_variants", []))
        clen = len(canonical)
        max_dist = max_edit_distance(clen)

        for gram, count in ngrams.items():
            if gram == canonical:
                continue
            if gram in allow_variants:
                continue
            # Only consider grams within adaptive distance of canonical length
            if abs(len(gram) - clen) > max_dist:
                continue
            # For same-length grams, require at least one shared character
            # to filter out completely unrelated n-grams
            if len(gram) == clen and not (set(gram) & set(canonical)):
                continue
            # Skip trivial extensions (canonical + common particle)
            if is_trivial_extension(gram, canonical):
                continue
            # Skip substrings of registered terms
            if is_substring_of_term(gram, all_canonicals):
                continue

            dist = levenshtein(canonical, gram)
            if 0 < dist <= max_dist:
                matches = collect_matches(lines, gram)
                if matches:
                    hits.append({
                        "category": "variant_detected",
                        "severity": "warning",
                        "description": "\u53ef\u80fd\u7684\u672f\u8bed\u53d8\u4f53",
                        "canonical": canonical,
                        "variant": gram,
                        "edit_distance": dist,
                        "count": count,
                        "matches": matches,
                    })

    return hits


def scan_inconsistent_refs(text: str, lines: List[str], terms: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Detect intra-chapter inconsistent references for same entity."""
    hits: List[Dict[str, Any]] = []

    char_terms = [
        t for t in terms
        if t.get("category") in ("character", "location")
    ]
    if not char_terms:
        return hits

    all_canonicals: Set[str] = {t["canonical"] for t in terms if t.get("canonical")}

    # Determine n-gram range
    term_lengths = {len(t["canonical"]) for t in char_terms if t.get("canonical")}
    global_min = max(2, min(term_lengths) - 1) if term_lengths else 2
    global_max = max(term_lengths) + 2 if term_lengths else 8

    ngrams = extract_cn_ngrams(text, global_min, global_max)

    for term in char_terms:
        canonical = term.get("canonical", "")
        if not canonical:
            continue
        allow_variants = set(term.get("allow_variants", []))
        all_allowed = {canonical} | allow_variants

        # Check if canonical appears in text
        if canonical not in ngrams:
            continue

        # Find unregistered near-variants present in text
        unregistered: List[str] = []
        clen = len(canonical)
        max_dist = max_edit_distance(clen)
        for gram in ngrams:
            if gram in all_allowed:
                continue
            if abs(len(gram) - clen) > max_dist:
                continue
            if len(gram) == clen and not (set(gram) & set(canonical)):
                continue
            if is_trivial_extension(gram, canonical):
                continue
            if is_substring_of_term(gram, all_canonicals):
                continue
            dist = levenshtein(canonical, gram)
            if 0 < dist <= max_dist:
                unregistered.append(gram)

        for variant in unregistered:
            matches = collect_matches(lines, variant)
            if matches:
                used_in_text = sorted(
                    {n for n in all_allowed if n in ngrams} | {variant}
                )
                hits.append({
                    "category": "inconsistent_reference",
                    "severity": "warning",
                    "description": "\u7ae0\u5185\u79f0\u547c\u4e0d\u4e00\u81f4",
                    "canonical": canonical,
                    "variants_used": used_in_text,
                    "count": len(matches),
                    "matches": matches,
                })

    return hits


def main() -> None:
    chapter_path = sys.argv[1]
    terminology_path = sys.argv[2]

    # Load chapter
    try:
        with open(chapter_path, "r", encoding="utf-8") as f:
            text = f.read()
    except Exception as e:
        sys.stderr.write(f"lint-terminology.sh: failed to read chapter: {e}\n")
        raise SystemExit(1)

    # Load terminology
    try:
        with open(terminology_path, "r", encoding="utf-8") as f:
            terminology = json.load(f)
    except Exception as e:
        sys.stderr.write(f"lint-terminology.sh: failed to read terminology: {e}\n")
        raise SystemExit(1)

    if not isinstance(terminology, dict):
        sys.stderr.write("lint-terminology.sh: terminology.json must be a JSON object\n")
        raise SystemExit(1)

    terms = terminology.get("terms", [])
    if not isinstance(terms, list):
        terms = []

    lines = text.splitlines()
    non_ws = len(re.sub(r"\s+", "", text))

    all_hits: List[Dict[str, Any]] = []

    # 1. Edit-distance variant detection
    all_hits.extend(scan_variants(text, lines, terms))

    # 2. Intra-chapter inconsistency detection
    # Deduplicate: if a variant is already flagged by variant_detected, skip in inconsistent
    flagged_variants: Set[Tuple[str, str]] = set()
    for hit in all_hits:
        if hit["category"] == "variant_detected":
            flagged_variants.add((hit["canonical"], hit["variant"]))

    inconsistent_hits = scan_inconsistent_refs(text, lines, terms)
    for hit in inconsistent_hits:
        # Skip if all variants are already covered by variant_detected
        canonical = hit["canonical"]
        new_variants = [
            v for v in hit.get("variants_used", [])
            if v != canonical and (canonical, v) not in flagged_variants
        ]
        if new_variants:
            all_hits.append(hit)

    total_warnings = sum(h.get("count", 0) for h in all_hits)

    result = {
        "chapter_path": chapter_path,
        "chars": non_ws,
        "total_hits": total_warnings,
        "errors": 0,
        "warnings": total_warnings,
        "hits": sorted(all_hits, key=lambda h: -h.get("count", 0)),
    }

    sys.stdout.write(json.dumps(result, ensure_ascii=False) + "\n")


try:
    main()
except SystemExit:
    raise
except Exception as e:
    sys.stderr.write(f"lint-terminology.sh: unexpected error: {e}\n")
    raise SystemExit(2)
PY
