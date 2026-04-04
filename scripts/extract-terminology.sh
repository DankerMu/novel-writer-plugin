#!/usr/bin/env bash
#
# Authority terminology extractor from L1/L2 spec files.
#
# Usage:
#   extract-terminology.sh [project_dir]
#
# Output:
#   Writes world/terminology.json in project_dir
#
# Exit codes:
#   0 = success (terminology.json written)
#   1 = validation failure (bad args)
#   2 = script exception (unexpected runtime error)
#
# Sources:
#   - world/rules.json (L1): rule names, domains, categories, proper nouns
#   - characters/active/*.json (L2): names, abilities, relationships, known_facts

set -euo pipefail

project_dir="${1:-.}"

if [ ! -d "$project_dir" ]; then
  echo "extract-terminology.sh: project directory not found: $project_dir" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_VENV_PY="${SCRIPT_DIR}/../.venv/bin/python3"
if [ -x "$_VENV_PY" ]; then
  PYTHON="$_VENV_PY"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
else
  echo "extract-terminology.sh: python3 not found (run: python3 -m venv .venv in plugin root)" >&2
  exit 2
fi

mkdir -p "$project_dir/world"

"$PYTHON" - "$project_dir" <<'PY'
import json
import os
import re
import sys
from datetime import datetime, timezone
from typing import Any, Dict, List, Set

# Common Chinese words to exclude from proper noun extraction
# (high-frequency function words, pronouns, common verbs/adjectives)
COMMON_WORDS: Set[str] = {
    "这个", "那个", "什么", "怎么", "可以", "没有", "不是", "已经",
    "因为", "所以", "如果", "虽然", "但是", "而且", "或者", "就是",
    "可能", "应该", "知道", "觉得", "认为", "希望", "需要", "喜欢",
    "自己", "我们", "他们", "她们", "你们", "大家", "别人", "对方",
    "时候", "地方", "东西", "事情", "问题", "方面", "情况", "关系",
    "一个", "一些", "一样", "一起", "一直", "一定", "一切", "一般",
    "非常", "特别", "真的", "其实", "终于", "突然", "忽然", "渐渐",
    "不过", "然而", "只是", "于是", "之后", "之前", "现在", "当时",
    "开始", "继续", "发现", "出现", "进入", "离开", "回到", "来到",
    "看到", "听到", "感到", "想到", "说道", "问道", "答道", "笑道",
    "心中", "眼中", "身上", "手中", "脸上", "面前", "身边", "周围",
    "世界", "天下", "江湖", "武林",
    "力量", "速度", "身体", "精神", "意识", "生命", "灵魂", "命运",
    "修炼", "突破", "提升", "强大", "厉害",
    "的确", "确实", "毕竟", "不禁", "只能", "只好", "果然", "居然",
    "一声", "一步", "一刻", "一瞬", "一番", "同时", "此时", "顿时",
}

# Punctuation pattern for Chinese text segmentation
CN_PUNCT = re.compile('[，。！？、；：\u201c\u201d\u2018\u2019【】《》（）\\s\\d\\w,.!?\\-\\[\\](){}:;\'"]+')


def extract_proper_nouns(text: str) -> List[str]:
    """Extract potential proper nouns (2-6 char Chinese sequences not in common words)."""
    if not text:
        return []
    # Split on punctuation and whitespace
    segments = CN_PUNCT.split(text)
    nouns: List[str] = []
    for seg in segments:
        # Extract 2-6 char Chinese-only sequences
        for m in re.finditer(r'[\u4e00-\u9fff]{2,6}', seg):
            word = m.group()
            if word not in COMMON_WORDS and len(word) >= 2:
                nouns.append(word)
    return nouns


def load_json_safe(path: str) -> Any:
    """Load JSON file, return None if not found or invalid."""
    if not os.path.isfile(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return None


def extract_from_rules(rules_path: str) -> List[Dict[str, Any]]:
    """Extract terms from world/rules.json (L1)."""
    data = load_json_safe(rules_path)
    if not data or not isinstance(data, dict):
        return []

    terms: List[Dict[str, Any]] = []
    seen: Set[str] = set()

    def add_term(canonical: str, category: str) -> None:
        if canonical and canonical not in seen:
            seen.add(canonical)
            terms.append({
                "canonical": canonical,
                "category": category,
                "source": "world/rules.json",
                "allow_variants": [],
            })

    # Extract from domains/categories arrays
    for field in ("domains", "categories", "systems", "factions", "locations"):
        items = data.get(field)
        if isinstance(items, list):
            for item in items:
                if isinstance(item, str) and item.strip():
                    add_term(item.strip(), "lore")
                elif isinstance(item, dict):
                    for key in ("name", "label", "title"):
                        val = item.get(key)
                        if isinstance(val, str) and val.strip():
                            add_term(val.strip(), "lore")

    # Extract from rules array
    rules = data.get("rules")
    if isinstance(rules, list):
        for rule in rules:
            if not isinstance(rule, dict):
                continue
            # Rule name/id as term
            for key in ("name", "title", "label"):
                val = rule.get(key)
                if isinstance(val, str) and val.strip():
                    add_term(val.strip(), "rule")
            # Extract proper nouns from rule text
            rule_text = rule.get("rule", "")
            if isinstance(rule_text, str):
                for noun in extract_proper_nouns(rule_text):
                    add_term(noun, "lore")

    return terms


def extract_from_characters(characters_dir: str) -> List[Dict[str, Any]]:
    """Extract terms from characters/active/*.json (L2)."""
    if not os.path.isdir(characters_dir):
        return []

    terms: List[Dict[str, Any]] = []
    seen: Set[str] = set()

    def add_term(canonical: str, category: str, source: str) -> None:
        if canonical and canonical not in seen:
            seen.add(canonical)
            terms.append({
                "canonical": canonical,
                "category": category,
                "source": source,
                "allow_variants": [],
            })

    json_files = sorted(
        f for f in os.listdir(characters_dir)
        if f.endswith(".json")
    )

    for fname in json_files:
        fpath = os.path.join(characters_dir, fname)
        rel_path = f"characters/active/{fname}"
        data = load_json_safe(fpath)
        if not data or not isinstance(data, dict):
            continue

        # Character name
        name = data.get("name")
        if isinstance(name, str) and name.strip():
            add_term(name.strip(), "character", rel_path)

        # Abilities
        abilities = data.get("abilities")
        if isinstance(abilities, list):
            for ab in abilities:
                if isinstance(ab, dict):
                    ab_name = ab.get("name")
                    if isinstance(ab_name, str) and ab_name.strip():
                        add_term(ab_name.strip(), "ability", rel_path)
                elif isinstance(ab, str) and ab.strip():
                    add_term(ab.strip(), "ability", rel_path)

        # Relationships
        relationships = data.get("relationships")
        if isinstance(relationships, list):
            for rel in relationships:
                if isinstance(rel, dict):
                    target = rel.get("target")
                    if isinstance(target, str) and target.strip():
                        add_term(target.strip(), "character", rel_path)

        # Known facts
        known_facts = data.get("known_facts")
        if isinstance(known_facts, list):
            for fact_entry in known_facts:
                fact_text = None
                if isinstance(fact_entry, dict):
                    fact_text = fact_entry.get("fact", "")
                elif isinstance(fact_entry, str):
                    fact_text = fact_entry
                if isinstance(fact_text, str):
                    for noun in extract_proper_nouns(fact_text):
                        add_term(noun, "lore", rel_path)

    return terms


def merge_with_existing(new_terms: List[Dict[str, Any]], existing_path: str) -> List[Dict[str, Any]]:
    """Merge new terms with existing terminology.json, preserving manual entries."""
    existing = load_json_safe(existing_path)
    if not existing or not isinstance(existing, dict):
        return new_terms

    existing_terms = existing.get("terms", [])
    if not isinstance(existing_terms, list):
        return new_terms

    # Preserve manual entries
    manual_terms = [
        t for t in existing_terms
        if isinstance(t, dict) and t.get("source") == "manual"
    ]

    # Preserve allow_variants from existing auto-generated entries
    existing_variants: Dict[str, List[str]] = {}
    for t in existing_terms:
        if isinstance(t, dict):
            canonical = t.get("canonical", "")
            variants = t.get("allow_variants", [])
            if canonical and isinstance(variants, list) and variants:
                existing_variants[canonical] = variants

    # Apply preserved variants to new terms
    for t in new_terms:
        canonical = t.get("canonical", "")
        if canonical in existing_variants:
            # Merge: keep new + add any existing variants not already present
            current = set(t.get("allow_variants", []))
            for v in existing_variants[canonical]:
                current.add(v)
            t["allow_variants"] = sorted(current)

    # Combine: new auto-generated + manual (dedup by canonical)
    seen_canonicals = {t["canonical"] for t in new_terms}
    merged = list(new_terms)
    for mt in manual_terms:
        if mt.get("canonical") not in seen_canonicals:
            merged.append(mt)
            seen_canonicals.add(mt.get("canonical", ""))

    return merged


def main() -> None:
    project_dir = sys.argv[1]

    rules_path = os.path.join(project_dir, "world", "rules.json")
    characters_dir = os.path.join(project_dir, "characters", "active")
    output_path = os.path.join(project_dir, "world", "terminology.json")

    all_terms: List[Dict[str, Any]] = []

    # L1 extraction
    if os.path.isfile(rules_path):
        all_terms.extend(extract_from_rules(rules_path))

    # L2 extraction
    if os.path.isdir(characters_dir):
        all_terms.extend(extract_from_characters(characters_dir))

    # Merge with existing (preserve manual entries and allow_variants)
    all_terms = merge_with_existing(all_terms, output_path)

    result = {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "terms": all_terms,
    }

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
        f.write("\n")

    sys.stderr.write(f"extract-terminology.sh: wrote {len(all_terms)} terms to {output_path}\n")


try:
    main()
except SystemExit:
    raise
except Exception as e:
    sys.stderr.write(f"extract-terminology.sh: unexpected error: {e}\n")
    raise SystemExit(2)
PY
