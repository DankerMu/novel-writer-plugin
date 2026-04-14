#!/usr/bin/env python3
"""
assemble-manifests.py — 确定性 context manifest 组装。

替代 LLM Task agent 手工拼 JSON，用 json.dumps 保证序列化正确。
对应 context-assembly.md Step 2.0-2.7。

用法:
  python scripts/assemble-manifests.py -c 12 -v 1 -p /path/to/novel
  python scripts/assemble-manifests.py -c 12 -v 1 -p /path/to/novel \\
    --revision '{"revision_scope":"targeted","failed_dimensions":["plot_logic"],...}'
"""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, NoReturn, Optional, Tuple

PLUGIN_ROOT = Path(__file__).resolve().parent.parent


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def die(msg: str, code: int = 1) -> NoReturn:
    print(f"[assemble] FATAL: {msg}", file=sys.stderr)
    raise SystemExit(code)


def warn(msg: str) -> None:
    print(f"[assemble] WARN: {msg}", file=sys.stderr)


def info(msg: str) -> None:
    print(f"[assemble] {msg}", file=sys.stderr)


def load_json(path: Path, *, required: bool = False) -> Optional[Any]:
    if not path.exists():
        if required:
            die(f"必需文件不存在: {path}")
        return None
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        if required:
            die(f"JSON 解析失败: {path}: {e}")
        warn(f"JSON 解析失败，跳过: {path}: {e}")
        return None


def read_text(path: Path, *, required: bool = False) -> Optional[str]:
    if not path.exists():
        if required:
            die(f"必需文件不存在: {path}")
        return None
    return path.read_text(encoding="utf-8")


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")


def rel(path: Path, root: Path) -> str:
    """Project-relative path string."""
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def path_if_exists(root: Path, relpath: str) -> Optional[str]:
    """Return relpath if the file exists under root, else None."""
    return relpath if (root / relpath).exists() else None


# ---------------------------------------------------------------------------
# Markdown section extraction
# ---------------------------------------------------------------------------

def extract_md_section(text: str, heading: str) -> str:
    """Extract content under a ### heading until next ### / ## or EOF."""
    lines = text.splitlines()
    in_section = False
    buf: list[str] = []
    for line in lines:
        if in_section:
            if re.match(r"^#{2,3} ", line):
                break
            buf.append(line)
        elif re.match(rf"^### {re.escape(heading)}", line):
            in_section = True
    return "\n".join(buf).strip()


# ---------------------------------------------------------------------------
# Step 2.1: outline extraction
# ---------------------------------------------------------------------------

def _scan_outline_field(text: str, field: str) -> Dict[int, str]:
    """Build {chapter_num: field_value} by scanning outline key-value lines."""
    lines = text.splitlines()
    cur_ch: Optional[int] = None
    result: Dict[int, str] = {}
    pat = re.compile(rf"^- \*\*{re.escape(field)}\*\*[:：]\s*(.+)")
    for line in lines:
        m = re.match(r"^### 第 (\d+) 章", line)
        if m:
            cur_ch = int(m.group(1))
            continue
        if cur_ch is not None:
            m2 = pat.match(line)
            if m2:
                result[cur_ch] = m2.group(1).strip()
                cur_ch = None
    return result


def extract_chapter_outline(root: Path, volume: int, chapter: int) -> dict:
    """Step 2.1: Extract chapter outline block + metadata.

    Returns:
        chapter_outline_block, outline_storyline_id, chapter_start, chapter_end,
        outline_keys, all_chapters, outline_text, outline_storylines,
        outline_state_changes
    """
    outline_path = root / f"volumes/vol-{volume:02d}/outline.md"
    text = read_text(outline_path, required=True)

    # Locate chapter heading
    pattern = rf"^### 第 {chapter} 章(?:[:：].*)?$"
    lines = text.splitlines()
    start_idx = None
    for i, line in enumerate(lines):
        if re.match(pattern, line):
            start_idx = i
            break

    if start_idx is None:
        die(f"无法定位第 {chapter} 章区块。期望格式: ### 第 {chapter} 章: 章名\n"
            f"请回到 /novel:start → \"规划本卷\" 修复 outline。")

    # Block until next ### or EOF
    end_idx = len(lines)
    for i in range(start_idx + 1, len(lines)):
        if re.match(r"^### ", lines[i]):
            end_idx = i
            break
    block = "\n".join(lines[start_idx:end_idx]).strip()

    # Parse key-value lines: - **Key**: value
    keys: Dict[str, str] = {}
    for line in lines[start_idx:end_idx]:
        m = re.match(r"^- \*\*(\w+)\*\*[:：]\s*(.*)$", line)
        if m:
            keys[m.group(1)] = m.group(2).strip()

    storyline_id = keys.get("Storyline", "").strip()
    if not storyline_id:
        die(f"outline 第 {chapter} 章缺少 Storyline 字段。")

    # Chapter boundaries
    all_chapters = sorted(
        int(m.group(1))
        for line in lines
        if (m := re.match(r"^### 第 (\d+) 章", line))
    )
    if not all_chapters:
        die("outline 中未找到任何章节标题。")

    return {
        "chapter_outline_block": block,
        "outline_storyline_id": storyline_id,
        "chapter_start": min(all_chapters),
        "chapter_end": max(all_chapters),
        "outline_keys": keys,
        "all_chapters": all_chapters,
        "outline_text": text,
        "outline_storylines": _scan_outline_field(text, "Storyline"),
        "outline_state_changes": _scan_outline_field(text, "StateChanges"),
    }


# ---------------------------------------------------------------------------
# Step 2.2: hard rules
# ---------------------------------------------------------------------------

def build_hard_rules(root: Path,
                     introducing_ids: List[str]) -> Tuple[List[str], List[str]]:
    """Build hard_rules_list and planned_rule_ids from world/rules.json."""
    data = load_json(root / "world/rules.json")
    if data is None:
        return [], []

    rules = data if isinstance(data, list) else data.get("rules", [])
    introducing = set(introducing_ids)
    hard_rules: list[str] = []
    planned_ids: list[str] = []

    for r in sorted(rules, key=lambda x: x.get("id", "")):
        if r.get("constraint_type") != "hard":
            continue
        rid = r.get("id", "")
        canon = r.get("canon_status", "established")
        cat = r.get("category", "")
        desc = r.get("description", "")
        exc = r.get("exceptions", "")
        exc_str = f"（exceptions: {exc}）" if exc else ""

        if canon == "planned":
            planned_ids.append(rid)
            if rid in introducing:
                hard_rules.append(f"[INTRODUCING][{rid}][{cat}] {desc}{exc_str}")
        else:
            hard_rules.append(f"[{rid}][{cat}] {desc}{exc_str}")

    return hard_rules, planned_ids


# ---------------------------------------------------------------------------
# Step 2.3: entity_id_map
# ---------------------------------------------------------------------------

def build_entity_map(root: Path) -> Tuple[Dict[str, str], Dict[str, str]]:
    """Build {slug: display_name} and reverse map from characters/active/*.json."""
    char_dir = root / "characters/active"
    if not char_dir.exists():
        return {}, {}

    fwd: Dict[str, str] = {}
    rev: Dict[str, str] = {}
    for p in sorted(char_dir.glob("*.json")):
        data = load_json(p)
        if not isinstance(data, dict):
            continue
        slug = p.stem
        name = data.get("display_name", slug)
        fwd[slug] = name
        rev[name] = slug
    return fwd, rev


# ---------------------------------------------------------------------------
# Step 2.4: chapter contract + character trimming
# ---------------------------------------------------------------------------

def parse_md_contract(text: str) -> dict:
    """Parse Markdown chapter contract into structured fields."""
    result: Dict[str, Any] = {"_format": "md"}

    # 基本信息
    info_sec = extract_md_section(text, "基本信息")
    for line in info_sec.splitlines():
        if m := re.match(r"^- \*\*章号\*\*[:：]\s*(\d+)", line):
            result["chapter_num"] = int(m.group(1))
        if m := re.match(r"^- \*\*故事线\*\*[:：]\s*(.+)", line):
            result["storyline_id"] = m.group(1).strip()

    # 事件
    result["events"] = extract_md_section(text, "事件（本章发生了什么）")

    # 涉及角色
    traits = extract_md_section(text, "事件中自然流露的角色特质")
    result["involved_characters"] = [
        m.group(1).strip()
        for line in traits.splitlines()
        if (m := re.match(r"^- (.+?)[:：]", line))
    ]

    # 世界规则 ID
    rules_sec = extract_md_section(text, "世界规则约束")
    result["world_rules"] = re.findall(r"(W-\d+)", rules_sec)

    # 钩子 → excitement_type
    hooks = extract_md_section(text, "钩子")
    for line in hooks.splitlines():
        if m := re.match(r"^- \*\*类型\*\*[:：]\s*(.+)", line):
            result["excitement_type"] = [
                t.strip() for t in re.split(r"[,，/、]", m.group(1)) if t.strip()
            ]

    # 伏笔
    fs = extract_md_section(text, "事件中自然推进的伏笔")
    result["foreshadowing"] = [
        {"id": m.group(1), "action": m.group(2).strip()}
        for line in fs.splitlines()
        if (m := re.match(r"^- (F-\d+)[:：]\s*(.+)", line))
    ]

    # 前章衔接
    result["previous_connection"] = extract_md_section(text, "前章衔接")

    # 验收标准
    crit = extract_md_section(text, "验收标准")
    result["acceptance_criteria"] = [
        m.group(1).strip()
        for line in crit.splitlines()
        if (m := re.match(r"^\d+\.\s*(.+)", line))
    ]

    # Warn on critical empty sections (heading typo detection)
    if not result.get("acceptance_criteria"):
        warn("契约「验收标准」section 为空——检查标题是否有排版差异")
    if not info_sec:
        warn("契约「基本信息」section 为空——检查标题是否有排版差异")

    return result


def load_chapter_contract(root: Path, volume: int,
                          chapter: int) -> Tuple[dict, Path, str]:
    """Load chapter contract (Markdown preferred, JSON fallback).

    Returns (parsed_fields, path, "md"|"json").
    """
    md = root / f"volumes/vol-{volume:02d}/chapter-contracts/chapter-{chapter:03d}.md"
    js = root / f"volumes/vol-{volume:02d}/chapter-contracts/chapter-{chapter:03d}.json"

    if md.exists():
        text = read_text(md, required=True)
        return parse_md_contract(text), md, "md"
    if js.exists():
        data = load_json(js, required=True)
        return data, js, "json"

    die(f"章节契约不存在: {md} 或 {js}\n"
        f"请回到 /novel:start → \"规划本卷\" 补齐。")


def compute_last_seen(root: Path, entity_map: Dict[str, str],
                      chapter: int) -> Dict[str, int]:
    """Scan recent 10 summaries for character mentions → {slug: last_chapter}."""
    last_seen: Dict[str, int] = {}
    for c in range(chapter - 1, max(chapter - 11, 0), -1):
        sp = root / f"summaries/chapter-{c:03d}-summary.md"
        if not sp.exists():
            continue
        text = sp.read_text(encoding="utf-8")
        for slug, display_name in entity_map.items():
            if slug not in last_seen and display_name in text:
                last_seen[slug] = c
    return last_seen


def trim_characters(
    root: Path, contract: dict, contract_fmt: str,
    entity_map: Dict[str, str], reverse_map: Dict[str, str],
    chapter: int,
) -> Tuple[List[str], List[str]]:
    """Determine character set, canon-filter, write staging copies.

    Returns (contract_rel_paths, profile_rel_paths).
    """
    staging = root / "staging/context/characters"
    staging.mkdir(parents=True, exist_ok=True)

    # Determine slugs
    if contract_fmt == "md":
        involved = contract.get("involved_characters", [])
    else:
        involved = contract.get("characters", [])

    if involved:
        slugs = []
        for name in involved:
            slug = reverse_map.get(name)
            if slug:
                slugs.append(slug)
            else:
                warn(f"角色 '{name}' 在 entity_id_map 中未找到，跳过")
    else:
        last_seen = compute_last_seen(root, entity_map, chapter)
        ranked = sorted(entity_map.keys(),
                        key=lambda s: (-last_seen.get(s, 0), s))
        slugs = ranked[:15]

    # Canon-status pre-filtering
    preconditions = contract.get("preconditions", {}) if contract_fmt == "json" else {}
    char_states = preconditions.get("character_states", [])

    contract_paths: list[str] = []
    profile_paths: list[str] = []

    for slug in slugs:
        src = root / f"characters/active/{slug}.json"
        if not src.exists():
            warn(f"角色文件不存在: characters/active/{slug}.json")
            continue
        data = load_json(src)
        if not isinstance(data, dict):
            continue

        for arr_key in ("abilities", "known_facts", "relationships"):
            arr = data.get(arr_key)
            if not isinstance(arr, list):
                continue
            filtered = []
            for item in arr:
                if not isinstance(item, dict):
                    filtered.append(item)
                    continue
                if item.get("canon_status") == "planned":
                    # Check introducing via fuzzy match
                    is_intro = any(
                        isinstance(cs, dict) and (
                            item.get("name", "") in str(cs) or
                            item.get("fact", "") in str(cs) or
                            item.get("target", "") in str(cs))
                        for cs in char_states
                    )
                    if is_intro:
                        item["introducing"] = True
                        filtered.append(item)
                else:
                    filtered.append(item)
            data[arr_key] = filtered

        dst = staging / f"{slug}.json"
        write_json(dst, data)
        contract_paths.append(rel(dst, root))

        profile = root / f"characters/active/{slug}.md"
        if profile.exists():
            profile_paths.append(rel(profile, root))

    return contract_paths, profile_paths


# ---------------------------------------------------------------------------
# Step 2.5: storyline context, memory paths, foreshadowing
# ---------------------------------------------------------------------------

def build_storyline_context(
    contract: dict, contract_fmt: str, outline_keys: dict,
    chapter: int, storyline_id: str,
    outline_storylines: Dict[int, str],
    all_chapters: List[int],
) -> dict:
    """Build storyline_context for CW manifest."""
    if contract_fmt == "json":
        sc = contract.get("storyline_context")
        if isinstance(sc, dict):
            return sc

    # Markdown: build from 前章衔接 + outline Arc
    previous = contract.get("previous_connection", "")
    arc = outline_keys.get("Arc", "")

    # Compute chapters_since_last from outline
    prev_same = [c for c in all_chapters
                 if c < chapter and outline_storylines.get(c) == storyline_id]
    csl = (chapter - max(prev_same)) if prev_same else 1

    return {
        "last_chapter_summary": previous,
        "chapters_since_last": csl,
        "line_arc_progress": arc,
    }


def build_concurrent_state(
    root: Path, volume: int, chapter: int,
    current_storyline: str,
    outline_storylines: Dict[int, str],
    outline_state_changes: Dict[int, str],
    all_chapters: List[int],
) -> Dict[str, str]:
    """Build concurrent_state from schedule + memory/outline."""
    schedule = load_json(root / f"volumes/vol-{volume:02d}/storyline-schedule.json")
    if schedule is None:
        return {}

    raw_active = schedule.get("active_storylines", [])
    active = [
        e["storyline_id"] if isinstance(e, dict) else e
        for e in raw_active
    ]
    dormant = set(schedule.get("dormant_storylines", []))
    state: Dict[str, str] = {}

    for sid in active:
        if sid == current_storyline or sid in dormant:
            continue
        # Try memory.md first line
        mem = root / f"storylines/{sid}/memory.md"
        if mem.exists():
            first = mem.read_text(encoding="utf-8").split("\n", 1)[0].strip()
            if first:
                state[sid] = first[:50]
                continue
        # Fallback: last chapter of this storyline in outline → StateChanges
        prev = [c for c in all_chapters
                if c < chapter and outline_storylines.get(c) == sid]
        if prev:
            sc = outline_state_changes.get(max(prev), "")
            state[sid] = sc[:50] if sc else ""
        else:
            state[sid] = ""

    return state


def build_transition_hint(contract: dict, contract_fmt: str,
                          outline_keys: dict) -> Optional[dict]:
    if contract_fmt == "json":
        return contract.get("transition_hint")

    hint = outline_keys.get("TransitionHint", "").strip()
    if not hint or hint in ("无", "null", "None", "-", ""):
        return None

    result: dict = {"text": hint}
    if m := re.search(r"next_storyline[=:：]\s*(\S+)", hint, re.IGNORECASE):
        result["next_storyline"] = m.group(1).strip().rstrip(",，")
    return result


def build_memory_paths(
    root: Path, volume: int, chapter: int, storyline_id: str,
    transition_hint: Optional[dict],
) -> Tuple[Optional[str], List[str]]:
    """Determine storyline_memory and adjacent_memories paths."""
    schedule = load_json(root / f"volumes/vol-{volume:02d}/storyline-schedule.json")
    dormant: set = set()
    if schedule:
        dormant = set(schedule.get("dormant_storylines", []))

    cur_mem = root / f"storylines/{storyline_id}/memory.md"
    sl_mem = rel(cur_mem, root) if cur_mem.exists() else None

    adj_ids: set[str] = set()
    if isinstance(transition_hint, dict):
        ns = transition_hint.get("next_storyline")
        if ns and ns not in dormant and ns != storyline_id:
            adj_ids.add(ns)

    if schedule:
        for evt in schedule.get("convergence_events", []):
            cr = evt.get("chapter_range", [])
            if (isinstance(cr, list) and len(cr) == 2
                    and isinstance(cr[0], int) and isinstance(cr[1], int)
                    and cr[0] <= chapter <= cr[1]):
                for sid in evt.get("involved_storylines", []):
                    if sid != storyline_id and sid not in dormant:
                        adj_ids.add(sid)

    adj_paths = [
        rel(root / f"storylines/{sid}/memory.md", root)
        for sid in sorted(adj_ids)
        if (root / f"storylines/{sid}/memory.md").exists()
    ]

    return sl_mem, adj_paths


def build_foreshadowing_tasks(root: Path, volume: int,
                              chapter: int) -> List[dict]:
    """Build foreshadowing_tasks via script or rule-based fallback."""
    script = PLUGIN_ROOT / "scripts/query-foreshadow.sh"
    if script.exists():
        try:
            r = subprocess.run(
                ["bash", str(script), str(chapter)],
                capture_output=True, text=True, timeout=10, cwd=str(root),
            )
            if r.returncode == 0:
                data = json.loads(r.stdout)
                items = data.get("items")
                if isinstance(items, list):
                    return items
        except Exception as e:  # any failure → fallback to rule-based filtering
            warn(f"query-foreshadow.sh 失败，回退规则过滤: {e}")

    # Rule-based fallback
    g_data = load_json(root / "foreshadowing/global.json")
    p_data = load_json(root / f"volumes/vol-{volume:02d}/foreshadowing.json")

    g_items = (g_data.get("foreshadowing", [])
               if isinstance(g_data, dict) else [])
    p_items = (p_data.get("foreshadowing", [])
               if isinstance(p_data, dict) else [])

    g_by_id = {i["id"]: i for i in g_items if isinstance(i, dict) and "id" in i}
    p_by_id = {i["id"]: i for i in p_items if isinstance(i, dict) and "id" in i}

    def in_range(rng: Any, c: int) -> bool:
        return (isinstance(rng, list) and len(rng) == 2
                and isinstance(rng[0], int) and isinstance(rng[1], int)
                and rng[0] <= c <= rng[1])

    candidates: Dict[str, dict] = {}

    # Plan hits
    for fid, item in p_by_id.items():
        if item.get("status") == "resolved":
            continue
        rng = item.get("target_resolve_range")
        if item.get("planted_chapter") == chapter or in_range(rng, chapter):
            candidates[fid] = item

    # Global hits
    for fid, item in g_by_id.items():
        if item.get("status") == "resolved":
            continue
        rng = item.get("target_resolve_range")
        if in_range(rng, chapter):
            candidates[fid] = item
        elif (item.get("scope") == "short"
              and isinstance(rng, list) and len(rng) == 2
              and chapter > rng[1]):
            candidates[fid] = item  # Overdue short

    # Merge (global priority)
    result = []
    for fid in sorted(candidates):
        if fid in g_by_id:
            merged = dict(g_by_id[fid])
            plan = p_by_id.get(fid, {})
            for k in ("description", "scope", "target_resolve_range"):
                if merged.get(k) is None and k in plan:
                    merged[k] = plan[k]
            result.append(merged)
        else:
            result.append(dict(candidates[fid]))

    return result


# ---------------------------------------------------------------------------
# Step 2.6-2.7: assemble all manifests
# ---------------------------------------------------------------------------

def build_recent(root: Path, chapter: int, tpl: str, n: int) -> List[str]:
    """Recent file paths (newest first), up to n existing files."""
    return [
        tpl.format(c=c)
        for c in range(chapter - 1, max(chapter - n - 1, 0), -1)
        if (root / tpl.format(c=c)).exists()
    ]


def get_style_drift_directives(root: Path) -> Optional[List[str]]:
    data = load_json(root / "style-drift.json")
    if not isinstance(data, dict) or not data.get("active"):
        return None
    dirs = [d["directive"] for d in data.get("drifts", [])
            if isinstance(d, dict) and "directive" in d]
    return dirs or None


def get_platform(root: Path) -> str:
    sp = load_json(root / "style-profile.json", required=True)
    p = sp.get("platform") if isinstance(sp, dict) else None
    if not p:
        die("style-profile.json 缺少 platform 字段。")
    return p


def convergence_chapters(root: Path, volume: int) -> set:
    schedule = load_json(root / f"volumes/vol-{volume:02d}/storyline-schedule.json")
    if not schedule:
        return set()
    chs: set[int] = set()
    for evt in schedule.get("convergence_events", []):
        cr = evt.get("chapter_range", [])
        if (isinstance(cr, list) and len(cr) == 2
                and isinstance(cr[0], int) and isinstance(cr[1], int)):
            chs.update(range(cr[0], cr[1] + 1))
    return chs


def assemble_all(
    root: Path, volume: int, chapter: int,
    eval_backend: str = "codex",
    revision: Optional[dict] = None,
) -> Dict[str, dict]:
    """Core assembly — returns {agent_name: manifest}."""
    info(f"vol={volume} ch={chapter} backend={eval_backend}"
         + (f" revision={revision.get('revision_scope','?')}" if revision else ""))

    # --- Step 2.1 ---
    out = extract_chapter_outline(root, volume, chapter)
    ol_keys       = out["outline_keys"]
    storyline_id  = out["outline_storyline_id"]
    ch_start      = out["chapter_start"]
    ch_end        = out["chapter_end"]
    all_chs       = out["all_chapters"]
    ol_storylines = out["outline_storylines"]
    ol_sc         = out["outline_state_changes"]
    ol_block      = out["chapter_outline_block"]

    # --- Step 2.4 (need contract before 2.2 for introducing rules) ---
    contract, contract_path, cfmt = load_chapter_contract(root, volume, chapter)
    contract_rel = rel(contract_path, root)

    # Consistency checks (Step 2.5.3)
    c_sid = contract.get("storyline_id", contract.get("storyline", ""))
    c_ch  = contract.get("chapter_num", contract.get("chapter"))
    if c_ch is not None and c_ch != chapter:
        die(f"契约章号 ({c_ch}) != 当前章 ({chapter})。")
    if c_sid and c_sid != storyline_id:
        die(f"契约 storyline ({c_sid}) != outline storyline ({storyline_id})。")
    if cfmt == "md":
        if not contract.get("events", "").strip():
            die("章节契约「事件」section 为空。")
    else:
        objs = contract.get("objectives", [])
        if not any(o.get("required") for o in objs if isinstance(o, dict)):
            die("章节契约缺少 required objective。")

    # --- Step 2.2 ---
    intro_rules = (contract.get("world_rules", []) if cfmt == "md"
                   else (contract.get("preconditions", {})
                         .get("required_world_rules", [])))
    hard_rules, planned_ids = build_hard_rules(root, intro_rules)

    # --- Step 2.3 ---
    entity_map, reverse_map = build_entity_map(root)

    # --- Step 2.4 (character trimming) ---
    char_contracts, char_profiles = trim_characters(
        root, contract, cfmt, entity_map, reverse_map, chapter)

    # --- Step 2.5 ---
    sl_ctx = build_storyline_context(
        contract, cfmt, ol_keys, chapter, storyline_id, ol_storylines, all_chs)
    transition = build_transition_hint(contract, cfmt, ol_keys)
    concurrent = build_concurrent_state(
        root, volume, chapter, storyline_id, ol_storylines, ol_sc, all_chs)
    sl_mem, adj_mems = build_memory_paths(
        root, volume, chapter, storyline_id, transition)
    fs_tasks = build_foreshadowing_tasks(root, volume, chapter)

    # --- Step 2.7 ---
    drift_dirs = get_style_drift_directives(root)

    # --- Derived flags ---
    platform = get_platform(root)
    pg_path: Optional[str] = None
    if platform != "general":
        candidate = f"templates/platforms/{platform}.md"
        if (root / candidate).exists():
            pg_path = candidate
        else:
            warn(f"平台指南不存在: {candidate}")

    is_golden = chapter <= 3 and pg_path is not None
    conv_chs = convergence_chapters(root, volume)
    has_convergence = bool(conv_chs)
    is_critical = (chapter in (ch_start, ch_end)
                   or chapter in conv_chs
                   or (not has_convergence
                       and chapter % 10 == 1
                       and chapter != ch_start))
    t3_mode = "full" if (is_golden or chapter == ch_end or is_critical) else "lite"

    excitement = contract.get("excitement_type")
    phase = ol_keys.get("Phase", "").strip() or None
    if phase and phase not in ("期待", "试探", "受挫", "噩梦", "爆发", "收束"):
        phase = None

    recent_ch = build_recent(root, chapter, "chapters/chapter-{c:03d}.md", 3)
    recent_sum = build_recent(root, chapter, "summaries/chapter-{c:03d}-summary.md", 3)
    recent_sum2 = recent_sum[:2]
    drift_path = "style-drift.json" if drift_dirs else None
    samples_path = path_if_exists(root, "style-samples.md")
    brief_path = path_if_exists(root, "brief.md")
    rules_path = path_if_exists(root, "world/rules.json")
    sched_rel = f"volumes/vol-{volume:02d}/storyline-schedule.json"
    sspec_path = path_if_exists(root, "storylines/storyline-spec.json")
    prev_sum_rel = f"summaries/chapter-{chapter-1:03d}-summary.md"
    has_prev_sum = (root / prev_sum_rel).exists()

    # Helper: add optional key only when value is present
    # (None, empty list, empty string → omit; 0 and False are preserved)
    def opt(d: dict, k: str, v: Any) -> None:
        if v is not None and v != [] and v != "":
            d[k] = v

    # ============================================================
    # ChapterWriter manifest
    # ============================================================
    cw: dict = {
        "chapter": chapter,
        "volume": volume,
        "storyline_id": storyline_id,
        "chapter_outline_block": ol_block,
        "storyline_context": sl_ctx,
        "concurrent_state": concurrent,
        "hard_rules_list": hard_rules,
        "foreshadowing_tasks": fs_tasks,
        "paths": {
            "style_profile": "style-profile.json",
            "chapter_contract": contract_rel,
            "volume_outline": f"volumes/vol-{volume:02d}/outline.md",
            "current_state": "state/current-state.json",
        },
    }
    opt(cw, "transition_hint", transition)
    opt(cw, "style_drift_directives", drift_dirs)
    opt(cw, "narrative_phase", phase)
    opt(cw["paths"], "style_samples", samples_path)
    opt(cw["paths"], "style_drift", drift_path)
    opt(cw["paths"], "world_rules", rules_path)
    opt(cw["paths"], "recent_summaries", recent_sum)
    opt(cw["paths"], "recent_chapters", recent_ch)
    opt(cw["paths"], "storyline_memory", sl_mem)
    opt(cw["paths"], "adjacent_memories", adj_mems)
    opt(cw["paths"], "character_contracts", char_contracts)
    opt(cw["paths"], "platform_guide", pg_path)
    opt(cw["paths"], "project_brief", brief_path)
    # Revision
    if revision:
        scope = revision.get("revision_scope", "full")
        cw["revision_scope"] = scope
        if scope == "targeted":
            cw["required_fixes"] = revision.get("required_fixes", [])
            cw["failed_dimensions"] = revision.get("failed_dimensions", [])
            opt(cw, "high_confidence_violations",
                revision.get("high_confidence_violations"))
        cw["paths"]["chapter_draft"] = f"staging/chapters/chapter-{chapter:03d}.md"

    # ============================================================
    # StyleRefiner manifest
    # ============================================================
    sr: dict = {
        "chapter": chapter,
        "volume": volume,
        "paths": {
            "chapter_draft": f"staging/chapters/chapter-{chapter:03d}.md",
            "style_profile": "style-profile.json",
            "ai_blacklist": "ai-blacklist.json",
            "style_guide": "skills/novel-writing/references/style-guide.md",
        },
    }
    opt(sr, "style_drift_directives", drift_dirs)
    opt(sr["paths"], "style_samples", samples_path)
    opt(sr["paths"], "style_drift", drift_path)
    if revision and revision.get("revision_scope") == "targeted":
        sr["lite_mode"] = True

    # ============================================================
    # Summarizer manifest
    # ============================================================
    sm: dict = {
        "chapter": chapter,
        "volume": volume,
        "storyline_id": storyline_id,
        "foreshadowing_tasks": fs_tasks,
        "entity_id_map": entity_map,
        "hints": None,  # patched post-CW by orchestrator
        "paths": {
            "chapter_draft": f"staging/chapters/chapter-{chapter:03d}.md",
            "current_state": "state/current-state.json",
        },
    }
    if revision and revision.get("revision_scope") == "targeted":
        sm["patch_mode"] = True

    # ============================================================
    # QualityJudge manifest
    # ============================================================
    qj: dict = {
        "chapter": chapter,
        "volume": volume,
        "chapter_outline_block": ol_block,
        "hard_rules_list": hard_rules,
        "planned_rule_ids": planned_ids,
        "blacklist_lint": None,             # patched post-SR
        "ner_entities": None,               # patched post-SR
        "continuity_report_summary": None,  # patched post-SR
        "narration_only_lint": None,        # patched post-SR
        "platform": platform,
        "is_golden_chapter": is_golden,
        "paths": {
            "chapter_draft": f"staging/chapters/chapter-{chapter:03d}.md",
            "style_profile": "style-profile.json",
            "ai_blacklist": "ai-blacklist.json",
            "chapter_contract": contract_rel,
            "quality_rubric": "skills/novel-writing/references/quality-rubric.md",
            "cross_references": f"staging/state/chapter-{chapter:03d}-crossref.json",
        },
    }
    opt(qj, "excitement_type", excitement)
    opt(qj, "narrative_phase", phase)
    opt(qj["paths"], "world_rules", rules_path)
    if has_prev_sum:
        qj["paths"]["prev_summary"] = prev_sum_rel
    if is_golden and pg_path and recent_sum2:
        qj["paths"]["recent_summaries"] = recent_sum2
    opt(qj["paths"], "character_profiles", char_profiles)
    opt(qj["paths"], "character_contracts", char_contracts)
    opt(qj["paths"], "storyline_spec", sspec_path)
    if (root / sched_rel).exists():
        qj["paths"]["storyline_schedule"] = sched_rel
    opt(qj["paths"], "platform_guide", pg_path)
    if revision and revision.get("revision_scope") == "targeted":
        qj["recheck_mode"] = True

    # ============================================================
    # ContentCritic manifest
    # ============================================================
    cc: dict = {
        "chapter": chapter,
        "volume": volume,
        "chapter_outline_block": ol_block,
        "platform": platform,
        "is_golden_chapter": is_golden,
        "track3_mode": t3_mode,
        "mode": None,
        "paths": {
            "chapter_draft": f"staging/chapters/chapter-{chapter:03d}.md",
            "chapter_contract": contract_rel,
            "style_profile": "style-profile.json",
            "quality_rubric": "skills/novel-writing/references/quality-rubric.md",
        },
    }
    opt(cc, "excitement_type", excitement)
    if has_prev_sum:
        cc["paths"]["prev_summary"] = prev_sum_rel
    if is_golden and pg_path and recent_sum2:
        cc["paths"]["recent_summaries"] = recent_sum2
    opt(cc["paths"], "platform_guide", pg_path)
    opt(cc["paths"], "character_contracts", char_contracts)
    opt(cc["paths"], "recent_chapters", recent_ch)
    if revision and revision.get("revision_scope") == "targeted":
        cc["recheck_mode"] = True

    return {
        "chapter-writer": cw,
        "style-refiner": sr,
        "summarizer": sm,
        "quality-judge": qj,
        "content-critic": cc,
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    ap = argparse.ArgumentParser(
        description="确定性 context manifest 组装（替代 LLM Task agent）")
    ap.add_argument("-c", "--chapter", type=int, required=True)
    ap.add_argument("-v", "--volume", type=int, required=True)
    ap.add_argument("-p", "--project", required=True,
                    help="小说项目根目录")
    ap.add_argument("--eval-backend", default="codex",
                    choices=["codex", "opus"])
    ap.add_argument("--revision", default=None,
                    help="修订状态 JSON 字符串")
    ap.add_argument("--output-dir", default=None,
                    help="输出目录 (default: <project>/staging/manifests)")
    args = ap.parse_args()

    root = Path(args.project).resolve()
    if not root.is_dir():
        die(f"项目目录不存在: {root}")

    rev = None
    if args.revision:
        try:
            rev = json.loads(args.revision)
        except json.JSONDecodeError as e:
            die(f"--revision JSON 解析失败: {e}")

    manifests = assemble_all(root, args.volume, args.chapter,
                             args.eval_backend, rev)

    out = Path(args.output_dir) if args.output_dir else root / "staging/manifests"
    out.mkdir(parents=True, exist_ok=True)

    for agent, data in manifests.items():
        p = out / f"chapter-{args.chapter:03d}-{agent}.json"
        write_json(p, data)
        info(f"  {p.name}")

    info(f"完成: {len(manifests)} 个 manifest → {out}")


if __name__ == "__main__":
    main()
