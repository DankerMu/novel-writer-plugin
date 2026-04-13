#!/usr/bin/env python3
"""
codex-eval.py — Codex 评估管线双模式工具。

Agent 模式（组装 task content）:
  python3 scripts/codex-eval.py <manifest.json> --agent summarizer|quality-judge|content-critic|sliding-window --project <path>

Validate 模式（校验 staging 输出）:
  python3 scripts/codex-eval.py --validate --schema summarizer|quality-judge|content-critic|sliding-window --project <path> --chapter <N>

Agent 模式读取 manifest JSON，组装 Codex 可消费的 task content markdown 文件。
Validate 模式检查 Codex 写入 staging/ 的输出文件是否存在且符合预期 schema。
"""

import argparse
import glob as globmod
import json
import sys
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parent.parent

AGENTS = ("summarizer", "quality-judge", "content-critic", "sliding-window")

QJ_SCORE_KEYS = (
    "plot_logic", "character", "immersion", "foreshadowing", "pacing",
    "style_naturalness", "emotional_impact", "storyline_coherence", "tonal_variance",
)

QJ_RECOMMENDATIONS = ("pass", "polish", "revise", "review", "rewrite")

DELTA_OPS = ("set", "inc", "add", "remove", "foreshadow")

QJ_LINT_SCRIPTS = (
    "lint-meta-leak.sh",
    "lint-terminology.sh",
    "lint-format.sh",
)

# --- Agent mode: path labels per agent ---

SUMMARIZER_PATHS = {
    "chapter_draft": "章节全文",
    "current_state": "当前状态",
    "previous_summary": "前章摘要（patch_mode）",
    "previous_delta": "前章 delta（patch_mode）",
    "revision_diff": "修订 diff（patch_mode）",
}

QJ_PATHS = {
    "chapter_draft": "章节全文",
    "style_profile": "风格指纹",
    "ai_blacklist": "AI 黑名单",
    "chapter_contract": "章节契约",
    "world_rules": "世界规则",
    "prev_summary": "前章摘要",
    "character_profiles": "角色简档",
    "character_contracts": "角色契约",
    "storyline_spec": "故事线规格",
    "storyline_schedule": "故事线调度",
    "cross_references": "交叉引用",
    "platform_guide": "平台指南",
    "recent_summaries": "近章摘要",
    "quality_rubric": "评分标准",
    "previous_eval": "上次评估（recheck）",
    "revision_diff": "修订 diff（recheck）",
}

CC_PATHS = {
    "chapter_draft": "章节全文",
    "chapter_contract": "章节契约",
    "prev_summary": "前章摘要",
    "recent_summaries": "近章摘要",
    "style_profile": "风格指纹",
    "platform_guide": "平台指南",
    "quality_rubric": "评分标准",
    "previous_eval": "上次评估（recheck）",
    "revision_diff": "修订 diff（recheck）",
}

SW_PATHS = {
    "chapters": "章节文件",
    "contracts": "章节契约",
    "outline_path": "卷大纲",
}

# --- Agent mode: inline fields per agent ---

SUMMARIZER_INLINE = (
    "chapter", "volume", "storyline_id", "foreshadowing_tasks",
    "entity_id_map", "hints", "patch_mode", "modified_paragraphs",
)

QJ_INLINE = (
    "chapter", "volume", "chapter_outline_block", "hard_rules_list",
    "blacklist_lint", "ner_entities", "continuity_report_summary",
    "platform", "excitement_type", "narrative_phase", "is_golden_chapter",
    "recheck_mode", "failed_dimensions", "failed_tracks",
)

CC_INLINE = (
    "chapter", "volume", "chapter_outline_block", "platform",
    "excitement_type", "is_golden_chapter", "track3_mode", "mode",
    "recheck_mode", "failed_tracks",
)

SW_INLINE = ("window",)

AGENT_PATH_LABELS = {
    "summarizer": SUMMARIZER_PATHS,
    "quality-judge": QJ_PATHS,
    "content-critic": CC_PATHS,
    "sliding-window": SW_PATHS,
}

AGENT_INLINE_FIELDS = {
    "summarizer": SUMMARIZER_INLINE,
    "quality-judge": QJ_INLINE,
    "content-critic": CC_INLINE,
    "sliding-window": SW_INLINE,
}


# ============================================================
# Agent mode — assemble task content
# ============================================================

def load_manifest(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def format_inline(key: str, value) -> str:
    """Format a single inline field as markdown list item or block."""
    if value is None:
        return ""
    if isinstance(value, (dict, list)):
        dumped = json.dumps(value, ensure_ascii=False, indent=2)
        return f"- {key}:\n```json\n{dumped}\n```"
    if isinstance(value, bool):
        return f"- {key}: {'true' if value else 'false'}"
    return f"- {key}: {value}"


def format_paths_section(manifest_paths: dict, label_map: dict) -> str:
    """Build the file-list section from manifest paths and agent label map."""
    lines = []
    for key, label in label_map.items():
        val = manifest_paths.get(key)
        if val is None:
            continue
        if isinstance(val, list):
            paths_str = ", ".join(str(p) for p in val)
            lines.append(f"- {label}: {paths_str}")
        else:
            lines.append(f"- {label}: {val}")
    return "\n".join(lines)


def build_output_section(agent: str, manifest: dict) -> str:
    """Build the output-path instructions section."""
    ch = manifest.get("chapter", 0)
    lines = []

    if agent == "summarizer":
        sid = manifest.get("storyline_id", "main")
        lines.append(f"- staging/summaries/chapter-{ch:03d}-summary.md")
        lines.append(f"- staging/state/chapter-{ch:03d}-delta.json")
        lines.append(f"- staging/state/chapter-{ch:03d}-crossref.json")
        lines.append(f"- staging/storylines/{sid}/memory.md")
    elif agent == "quality-judge":
        lines.append(f"- staging/evaluations/chapter-{ch:03d}-eval-raw.json")
    elif agent == "content-critic":
        lines.append(f"- staging/evaluations/chapter-{ch:03d}-content-eval-raw.json")
    elif agent == "sliding-window":
        w = manifest.get("window", {})
        vol = w.get("volume", 1)
        start = w.get("start", 1)
        end = w.get("end", 10)
        lines.append(
            f"- staging/logs/continuity/continuity-report-vol-{vol:02d}"
            f"-ch{start:03d}-ch{end:03d}.json"
        )
    return "\n".join(lines)


def assemble_task_content(agent: str, manifest: dict) -> str:
    """Assemble full task content markdown for a given agent."""
    parts: list[str] = []

    # Header
    agent_cn = {
        "summarizer": "章节摘要",
        "quality-judge": "章节质量评估",
        "content-critic": "内容实质性评估",
        "sliding-window": "滑窗一致性校验",
    }
    parts.append(f"请读取以下评估规范，然后执行{agent_cn[agent]}。")

    # Section 1: prompt reference
    parts.append(f"## 评估规范\n请读取: prompts/codex-{agent}.md")

    # Section 2: file paths
    paths = manifest.get("paths", {})
    label_map = AGENT_PATH_LABELS[agent]
    paths_text = format_paths_section(paths, label_map)
    if paths_text:
        parts.append(f"## 需要读取的文件\n{paths_text}")

    # Section 3: lint scripts (QJ only)
    if agent == "quality-judge":
        draft = paths.get("chapter_draft", "staging/chapters/chapter-???.md")
        lint_lines = [f"- bash scripts/{s} {draft}" for s in QJ_LINT_SCRIPTS]
        lint_lines.append("（将 lint 结果用于 contract_verification 对应 checks）")
        parts.append(f"## 需要执行的 lint 脚本\n" + "\n".join(lint_lines))

    # Section 4: inline data
    inline_keys = AGENT_INLINE_FIELDS[agent]
    inline_lines = []
    for key in inline_keys:
        val = manifest.get(key)
        if val is None:
            continue
        line = format_inline(key, val)
        if line:
            inline_lines.append(line)
    if inline_lines:
        parts.append(f"## 内联数据\n" + "\n".join(inline_lines))

    # Section 5: output paths
    output_text = build_output_section(agent, manifest)
    if output_text:
        fmt = "JSON" if agent != "summarizer" else "对应格式"
        parts.append(f"## 输出要求\n将结果以{fmt}写入:\n{output_text}")

    return "\n\n".join(parts)


def agent_mode(args):
    """Agent mode entry: assemble task content from manifest."""
    manifest = load_manifest(args.manifest)
    agent = args.agent

    project_root = Path(args.project).resolve() if args.project else Path(args.manifest).resolve().parent

    # Determine output path
    if agent == "sliding-window":
        out_name = "sliding-window.md"
    else:
        ch = manifest.get("chapter")
        if ch is None:
            print("[codex-eval] Error: manifest 缺少 chapter 字段", file=sys.stderr)
            sys.exit(1)
        out_name = f"chapter-{ch:03d}-{agent}.md"

    out_dir = project_root / "staging" / "prompts"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / out_name

    # Assemble and write
    content = assemble_task_content(agent, manifest)
    out_path.write_text(content, encoding="utf-8")

    # Print path to stdout (for orchestrator consumption)
    print(str(out_path))


# ============================================================
# Validate mode — check staging outputs
# ============================================================

def _load_json(path: Path) -> tuple[dict | None, str | None]:
    """Load and parse JSON, returning (data, error)."""
    if not path.exists():
        return None, f"missing: {path.relative_to(path.parents[2]) if len(path.parents) > 2 else path}"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        return None, f"invalid JSON in {path.name}: {e}"
    if not isinstance(data, dict):
        return None, f"{path.name}: expected object, got {type(data).__name__}"
    return data, None


def _check_score(data: dict, key_path: str, min_val=1, max_val=5) -> list[str]:
    """Walk dotted key_path into data, check numeric range."""
    errors = []
    keys = key_path.split(".")
    obj = data
    for k in keys:
        if not isinstance(obj, dict) or k not in obj:
            errors.append(f"missing: {key_path}")
            return errors
        obj = obj[k]
    if not isinstance(obj, (int, float)):
        errors.append(f"{key_path}: expected number, got {type(obj).__name__}")
    elif not (min_val <= obj <= max_val):
        errors.append(f"{key_path}: {obj} out of range [{min_val}, {max_val}]")
    return errors


def validate_summarizer(project_root: Path, chapter: int) -> list[str]:
    """Validate Summarizer staging outputs."""
    errors = []
    base = project_root / "staging"

    # File existence
    required = [
        base / "summaries" / f"chapter-{chapter:03d}-summary.md",
        base / "state" / f"chapter-{chapter:03d}-delta.json",
        base / "state" / f"chapter-{chapter:03d}-crossref.json",
    ]
    for p in required:
        if not p.exists():
            errors.append(f"missing: {p.relative_to(project_root)}")

    # delta.json validation
    delta_path = base / "state" / f"chapter-{chapter:03d}-delta.json"
    if delta_path.exists():
        delta, err = _load_json(delta_path)
        if err:
            errors.append(err)
        elif delta is not None:
            if "ops" not in delta:
                errors.append("delta: missing ops")
            else:
                for i, op in enumerate(delta["ops"]):
                    op_val = op.get("op") if isinstance(op, dict) else None
                    if op_val not in DELTA_OPS:
                        errors.append(f"delta: ops[{i}] invalid op '{op_val}'")
            if "canon_hints" not in delta:
                errors.append("delta: missing canon_hints")

            # Check storyline memory if storyline_id present
            sid = delta.get("storyline_id")
            if sid:
                mem_path = base / "storylines" / sid / "memory.md"
                if not mem_path.exists():
                    errors.append(f"missing: {mem_path.relative_to(project_root)}")

    return errors


def validate_quality_judge(project_root: Path, chapter: int) -> list[str]:
    """Validate QualityJudge staging output."""
    errors = []
    eval_path = project_root / "staging" / "evaluations" / f"chapter-{chapter:03d}-eval-raw.json"

    data, err = _load_json(eval_path)
    if err:
        return [err]

    # Required top-level fields
    if "chapter" not in data:
        errors.append("missing: chapter")

    # contract_verification
    cv = data.get("contract_verification")
    if cv is None:
        errors.append("missing: contract_verification")
    elif isinstance(cv, dict):
        if "has_violations" not in cv:
            errors.append("missing: contract_verification.has_violations")
        elif not isinstance(cv["has_violations"], bool):
            errors.append("contract_verification.has_violations: expected bool")
        if "has_warnings" not in cv:
            errors.append("missing: contract_verification.has_warnings")
        elif not isinstance(cv["has_warnings"], bool):
            errors.append("contract_verification.has_warnings: expected bool")

    # scores
    scores = data.get("scores")
    if scores is None:
        errors.append("missing: scores")
    elif isinstance(scores, dict):
        for key in QJ_SCORE_KEYS:
            if key not in scores:
                errors.append(f"missing: scores.{key}")
            elif isinstance(scores[key], dict):
                s_errs = _check_score(scores[key], "score")
                for e in s_errs:
                    errors.append(f"scores.{key}.{e}")
            elif isinstance(scores[key], (int, float)):
                if not (1 <= scores[key] <= 5):
                    errors.append(f"scores.{key}: {scores[key]} out of range [1, 5]")
            else:
                errors.append(f"scores.{key}: expected object or number")
    else:
        errors.append("scores: expected object")

    # overall_raw
    errors.extend(_check_score(data, "overall_raw"))

    # overall
    errors.extend(_check_score(data, "overall"))

    # recommendation
    rec = data.get("recommendation")
    if rec is None:
        errors.append("missing: recommendation")
    elif rec not in QJ_RECOMMENDATIONS:
        errors.append(f"recommendation: '{rec}' not in {QJ_RECOMMENDATIONS}")

    # anti_ai
    anti_ai = data.get("anti_ai")
    if anti_ai is None:
        errors.append("missing: anti_ai")
    elif isinstance(anti_ai, dict):
        if "detected_humanize_techniques" not in anti_ai:
            errors.append("missing: anti_ai.detected_humanize_techniques")
        elif not isinstance(anti_ai["detected_humanize_techniques"], list):
            errors.append("anti_ai.detected_humanize_techniques: expected array")

    return errors


def validate_content_critic(project_root: Path, chapter: int) -> list[str]:
    """Validate ContentCritic staging output."""
    errors = []
    eval_path = project_root / "staging" / "evaluations" / f"chapter-{chapter:03d}-content-eval-raw.json"

    data, err = _load_json(eval_path)
    if err:
        return [err]

    if "chapter" not in data:
        errors.append("missing: chapter")

    # reader_evaluation (object or null)
    re_val = data.get("reader_evaluation")
    if "reader_evaluation" not in data:
        errors.append("missing: reader_evaluation")
    elif re_val is not None:
        if not isinstance(re_val, dict):
            errors.append("reader_evaluation: expected object or null")
        else:
            oe_errs = _check_score(re_val, "overall_engagement")
            for e in oe_errs:
                errors.append(f"reader_evaluation.{e}")

    # content_substance (object or null)
    cs = data.get("content_substance")
    if "content_substance" not in data:
        errors.append("missing: content_substance")
    elif cs is not None:
        if not isinstance(cs, dict):
            errors.append("content_substance: expected object or null")
        else:
            # information_density.score
            id_obj = cs.get("information_density")
            if id_obj is None:
                errors.append("missing: content_substance.information_density")
            elif isinstance(id_obj, dict):
                s_errs = _check_score(id_obj, "score")
                for e in s_errs:
                    errors.append(f"content_substance.information_density.{e}" if ":" in e
                                  else f"missing: content_substance.information_density.score")
            else:
                errors.append("content_substance.information_density: expected object")

            # plot_progression.score
            pp_obj = cs.get("plot_progression")
            if pp_obj is None:
                errors.append("missing: content_substance.plot_progression")
            elif isinstance(pp_obj, dict):
                s_errs = _check_score(pp_obj, "score")
                for e in s_errs:
                    errors.append(f"content_substance.plot_progression.{e}" if ":" in e
                                  else f"missing: content_substance.plot_progression.score")
            else:
                errors.append("content_substance.plot_progression: expected object")

            # dialogue_efficiency.score
            de_obj = cs.get("dialogue_efficiency")
            if de_obj is None:
                errors.append("missing: content_substance.dialogue_efficiency")
            elif isinstance(de_obj, dict):
                s_errs = _check_score(de_obj, "score")
                for e in s_errs:
                    errors.append(f"content_substance.dialogue_efficiency.{e}" if ":" in e
                                  else f"missing: content_substance.dialogue_efficiency.score")
            else:
                errors.append("content_substance.dialogue_efficiency: expected object")

            # content_substance_overall
            cso = cs.get("content_substance_overall")
            if cso is None:
                errors.append("missing: content_substance.content_substance_overall")
            elif not isinstance(cso, (int, float)):
                errors.append("content_substance.content_substance_overall: expected number")
            elif not (1 <= cso <= 5):
                errors.append(f"content_substance.content_substance_overall: {cso} out of range [1, 5]")

            # has_substance_violation
            hsv = cs.get("has_substance_violation")
            if hsv is None:
                errors.append("missing: content_substance.has_substance_violation")
            elif not isinstance(hsv, bool):
                errors.append("content_substance.has_substance_violation: expected bool")

    return errors


def validate_sliding_window(project_root: Path) -> list[str]:
    """Validate sliding-window continuity report."""
    errors = []
    report_dir = project_root / "staging" / "logs" / "continuity"

    # Find newest report
    pattern = str(report_dir / "continuity-report-*.json")
    matches = sorted(globmod.glob(pattern), key=lambda p: Path(p).stat().st_mtime, reverse=True)
    if not matches:
        return [f"no continuity report found in {report_dir.relative_to(project_root)}"]

    report_path = Path(matches[0])
    data, err = _load_json(report_path)
    if err:
        return [err]

    # window
    w = data.get("window")
    if w is None:
        errors.append("missing: window")
    elif isinstance(w, dict):
        for k in ("start", "end", "volume"):
            if k not in w:
                errors.append(f"missing: window.{k}")
    else:
        errors.append("window: expected object")

    # alignment_checks
    ac = data.get("alignment_checks")
    if ac is None:
        errors.append("missing: alignment_checks")
    elif not isinstance(ac, list):
        errors.append("alignment_checks: expected array")

    # continuity_issues
    ci = data.get("continuity_issues")
    if ci is None:
        errors.append("missing: continuity_issues")
    elif not isinstance(ci, list):
        errors.append("continuity_issues: expected array")

    # summary
    s = data.get("summary")
    if s is None:
        errors.append("missing: summary")
    elif isinstance(s, dict):
        for k in ("issues_total", "auto_fixable_count", "high_severity_unfixed"):
            v = s.get(k)
            if v is None:
                errors.append(f"missing: summary.{k}")
            elif not isinstance(v, int):
                errors.append(f"summary.{k}: expected int, got {type(v).__name__}")
    else:
        errors.append("summary: expected object")

    return errors


def validate_mode(args):
    """Validate mode entry: check staging outputs."""
    project_root = Path(args.project).resolve() if args.project else Path.cwd()
    schema = args.schema
    chapter = args.chapter

    if schema == "sliding-window":
        errors = validate_sliding_window(project_root)
    else:
        if chapter is None:
            print("[codex-eval] Error: --chapter required for non-sliding-window schemas",
                  file=sys.stderr)
            sys.exit(1)
        if schema == "summarizer":
            errors = validate_summarizer(project_root, chapter)
        elif schema == "quality-judge":
            errors = validate_quality_judge(project_root, chapter)
        elif schema == "content-critic":
            errors = validate_content_critic(project_root, chapter)
        else:
            print(f"[codex-eval] Error: unknown schema '{schema}'", file=sys.stderr)
            sys.exit(1)

    if errors:
        for e in errors:
            print(f"[codex-eval] FAIL: {e}", file=sys.stderr)
        sys.exit(1)
    # Exit 0 silently on success


# ============================================================
# CLI entry
# ============================================================

def main():
    ap = argparse.ArgumentParser(
        description="Codex 评估管线 — task content 组装 + staging 输出校验"
    )

    # Agent mode (positional manifest)
    ap.add_argument("manifest", nargs="?", default=None,
                     help="Context manifest JSON 路径（agent 模式）")
    ap.add_argument("--agent", choices=AGENTS,
                     help="目标 agent（agent 模式必需）")
    ap.add_argument("--project", help="小说项目根目录")

    # Validate mode
    ap.add_argument("--validate", action="store_true",
                     help="校验模式：检查 staging 输出")
    ap.add_argument("--schema", choices=AGENTS,
                     help="校验目标 schema（validate 模式必需）")
    ap.add_argument("--chapter", type=int,
                     help="章节号（validate 模式，sliding-window 除外）")

    args = ap.parse_args()

    if args.validate:
        if not args.schema:
            ap.error("--validate requires --schema")
        validate_mode(args)
    elif args.manifest and args.agent:
        agent_mode(args)
    else:
        ap.error("需要 <manifest> --agent 或 --validate --schema")


if __name__ == "__main__":
    main()
