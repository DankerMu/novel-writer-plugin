"""Codex calibration: compare Codex QJ/CC scores vs human labels and Opus scores.

Follows the pattern of calibrate_quality_judge.py.
Shared helpers imported from _common.py (same directory).

CLI: calibrate_codex.py <project_dir> <labels_path> [out_path]
"""

import json
import math
import os
import re
import sys
from datetime import datetime, timezone
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

import _common

_SCRIPT = "run-codex-calibration.sh"


def _die(msg: str, exit_code: int = 1) -> None:
    _common.die(f"{_SCRIPT}: {msg}", exit_code)


def _load_json(path: str) -> Any:
    try:
        return _common.load_json(path)
    except Exception as e:
        _die(f"invalid JSON at {path}: {e}", 1)


def _load_json_optional(path: str) -> Any:
    """Load JSON, return None if file does not exist."""
    return _common.load_json(path, missing_ok=True)


def _iter_jsonl(path: str) -> Iterable[Tuple[int, Dict[str, Any]]]:
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line_no, raw in enumerate(f, start=1):
                line = raw.strip()
                if not line:
                    continue
                if line.startswith("#"):
                    continue
                try:
                    obj = json.loads(line)
                except Exception as e:
                    _die(f"invalid JSONL at {path}:{line_no}: {e}", 1)
                if not isinstance(obj, dict):
                    _die(f"JSONL record must be an object at {path}:{line_no}", 1)
                yield line_no, obj
    except FileNotFoundError:
        _die(f"labels file not found: {path}", 1)
    except SystemExit:
        raise
    except Exception as e:
        _die(f"failed to read labels file {path}: {e}", 1)


# ---------------------------------------------------------------------------
# Statistics
# ---------------------------------------------------------------------------

def _pearson(x: Sequence[float], y: Sequence[float]) -> Optional[float]:
    if len(x) != len(y) or len(x) < 2:
        return None
    mean_x = sum(x) / len(x)
    mean_y = sum(y) / len(y)
    num = 0.0
    den_x = 0.0
    den_y = 0.0
    for a, b in zip(x, y):
        dx = a - mean_x
        dy = b - mean_y
        num += dx * dy
        den_x += dx * dx
        den_y += dy * dy
    if den_x <= 0.0 or den_y <= 0.0:
        return None
    return num / math.sqrt(den_x * den_y)


def _mae(errors: Sequence[float]) -> float:
    return sum(abs(e) for e in errors) / len(errors) if errors else 0.0


def _rmse(errors: Sequence[float]) -> float:
    return math.sqrt(sum(e * e for e in errors) / len(errors)) if errors else 0.0


def _bias(errors: Sequence[float]) -> float:
    return sum(errors) / len(errors) if errors else 0.0


def _safe_round(v: Optional[float], ndigits: int = 4) -> Optional[float]:
    if v is None:
        return None
    return round(float(v), ndigits)


def _compute_stats(
    pred: List[float], truth: List[float]
) -> Dict[str, Any]:
    """Compute Pearson r, MAE, RMSE, bias for pred vs truth."""
    n = len(pred)
    if n < 2:
        return {"n": n, "pearson_r": None, "mae": None, "rmse": None, "bias": None}
    errors = [p - t for p, t in zip(pred, truth)]
    return {
        "n": n,
        "pearson_r": _safe_round(_pearson(pred, truth)),
        "mae": _safe_round(_mae(errors)),
        "rmse": _safe_round(_rmse(errors)),
        "bias": _safe_round(_bias(errors)),
    }


# ---------------------------------------------------------------------------
# Score extraction from Codex raw eval files
# ---------------------------------------------------------------------------

def _extract_codex_qj_scores(
    eval_obj: Dict[str, Any],
) -> Tuple[Optional[float], Dict[str, float]]:
    """Extract overall + per-dimension scores from Codex QJ raw eval.

    Codex QJ writes to staging/evaluations/chapter-NNN-eval-raw.json.
    Structure mirrors the agent output: scores.{dim}.score, overall, overall_raw.
    """
    overall = _common.as_float(eval_obj.get("overall"))
    if overall is None:
        overall = _common.as_float(eval_obj.get("overall_raw"))

    dims: Dict[str, float] = {}
    scores = eval_obj.get("scores")
    if isinstance(scores, dict):
        for key, item in scores.items():
            if isinstance(item, dict):
                v = _common.as_float(item.get("score"))
                if v is not None:
                    dims[str(key)] = float(v)
            else:
                v = _common.as_float(item)
                if v is not None:
                    dims[str(key)] = float(v)
    return overall, dims


def _extract_codex_cc_scores(
    eval_obj: Dict[str, Any],
) -> Dict[str, Optional[float]]:
    """Extract CC scores from Codex content-eval-raw.json.

    Returns dict with keys: overall_engagement, content_substance_overall,
    information_density, plot_progression, dialogue_efficiency.
    """
    out: Dict[str, Optional[float]] = {
        "overall_engagement": None,
        "content_substance_overall": None,
        "information_density": None,
        "plot_progression": None,
        "dialogue_efficiency": None,
    }

    re_val = eval_obj.get("reader_evaluation")
    if isinstance(re_val, dict):
        out["overall_engagement"] = _common.as_float(re_val.get("overall_engagement"))

    cs = eval_obj.get("content_substance")
    if isinstance(cs, dict):
        out["content_substance_overall"] = _common.as_float(
            cs.get("content_substance_overall")
        )
        for dim_key in ("information_density", "plot_progression", "dialogue_efficiency"):
            dim_obj = cs.get(dim_key)
            if isinstance(dim_obj, dict):
                out[dim_key] = _common.as_float(dim_obj.get("score"))
            else:
                out[dim_key] = _common.as_float(dim_obj)

    return out


# ---------------------------------------------------------------------------
# Summarizer ops comparison
# ---------------------------------------------------------------------------

def _load_changelog_ops(changelog_path: str) -> Dict[int, List[Dict[str, Any]]]:
    """Parse state/changelog.jsonl → {chapter: [ops]}."""
    result: Dict[int, List[Dict[str, Any]]] = {}
    if not os.path.isfile(changelog_path):
        return result
    try:
        with open(changelog_path, "r", encoding="utf-8") as f:
            for raw in f:
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                ch = obj.get("chapter")
                if not isinstance(ch, int):
                    continue
                ops = obj.get("ops", [])
                if isinstance(ops, list):
                    result.setdefault(ch, []).extend(ops)
    except Exception:
        pass
    return result


def _compare_summarizer_ops(
    project_dir: str, chapters: List[int]
) -> Dict[str, Any]:
    """Compare Codex Summarizer delta.json vs Opus changelog.jsonl."""
    changelog_path = os.path.join(project_dir, "state", "changelog.jsonl")
    opus_ops = _load_changelog_ops(changelog_path)

    codex_ops_counts: List[int] = []
    opus_ops_counts: List[int] = []
    canon_hits = 0
    canon_total = 0
    compared = 0

    for ch in chapters:
        ch_pad = f"{ch:03d}"
        delta_path = os.path.join(
            project_dir, "staging", "state", f"chapter-{ch_pad}-delta.json"
        )
        delta = _load_json_optional(delta_path)
        if delta is None or not isinstance(delta, dict):
            continue

        codex_ch_ops = delta.get("ops", [])
        if not isinstance(codex_ch_ops, list):
            codex_ch_ops = []
        codex_ops_counts.append(len(codex_ch_ops))

        opus_ch_ops = opus_ops.get(ch, [])
        opus_ops_counts.append(len(opus_ch_ops))

        # canon_hints coverage
        codex_hints = delta.get("canon_hints", [])
        if isinstance(codex_hints, list):
            canon_total += max(len(codex_hints), len(opus_ch_ops))
            canon_hits += len(codex_hints)

        compared += 1

    mean_codex = (
        round(sum(codex_ops_counts) / len(codex_ops_counts), 1)
        if codex_ops_counts
        else 0.0
    )
    mean_opus = (
        round(sum(opus_ops_counts) / len(opus_ops_counts), 1)
        if opus_ops_counts
        else 0.0
    )
    coverage = round(canon_hits / canon_total, 2) if canon_total > 0 else None

    return {
        "chapters_compared": compared,
        "mean_ops_count_codex": mean_codex,
        "mean_ops_count_opus": mean_opus,
        "canon_hints_coverage": coverage,
    }


# ---------------------------------------------------------------------------
# Find Codex raw eval files
# ---------------------------------------------------------------------------

def _find_codex_eval_files(
    staging_eval_dir: str,
) -> Tuple[Dict[int, str], Dict[int, str]]:
    """Find chapter-NNN-eval-raw.json and chapter-NNN-content-eval-raw.json.

    Returns (qj_files, cc_files) as {chapter: path}.
    """
    qj: Dict[int, str] = {}
    cc: Dict[int, str] = {}
    if not os.path.isdir(staging_eval_dir):
        return qj, cc
    for name in os.listdir(staging_eval_dir):
        m = re.match(r"^chapter-(\d+)-eval-raw\.json$", name)
        if m:
            qj[int(m.group(1))] = os.path.join(staging_eval_dir, name)
            continue
        m = re.match(r"^chapter-(\d+)-content-eval-raw\.json$", name)
        if m:
            cc[int(m.group(1))] = os.path.join(staging_eval_dir, name)
    return qj, cc


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    if len(sys.argv) < 3:
        _die("usage: calibrate_codex.py <project_dir> <labels_path> [out_path]", 1)

    project_dir = sys.argv[1]
    labels_path = sys.argv[2]
    out_path = sys.argv[3].strip() if len(sys.argv) > 3 else ""

    # 1. Load labels
    label_records: Dict[int, Dict[str, Any]] = {}
    label_line_by_chapter: Dict[int, int] = {}

    for line_no, obj in _iter_jsonl(labels_path):
        chapter = obj.get("chapter")
        if not isinstance(chapter, int) or chapter < 1:
            _die(f"labels record missing valid chapter at {labels_path}:{line_no}", 1)
        schema_version = obj.get("schema_version")
        if schema_version != 1:
            _die(
                f"unsupported schema_version at {labels_path}:{line_no} "
                f"(expected 1, got {schema_version})",
                1,
            )
        human_scores = obj.get("human_scores")
        if not isinstance(human_scores, dict) or _common.as_float(
            human_scores.get("overall")
        ) is None:
            _die(
                f"labels record missing human_scores.overall at {labels_path}:{line_no}",
                1,
            )
        if chapter in label_records:
            _die(
                f"duplicate chapter {chapter} in labels "
                f"(lines {label_line_by_chapter[chapter]} and {line_no})",
                1,
            )
        label_records[chapter] = obj
        label_line_by_chapter[chapter] = line_no

    if not label_records:
        _die("labels file has no records", 1)

    # 2. Find eval files
    staging_eval_dir = os.path.join(project_dir, "staging", "evaluations")
    codex_qj_files, codex_cc_files = _find_codex_eval_files(staging_eval_dir)

    eval_dir = os.path.join(project_dir, "evaluations")
    opus_eval_list = _common.find_eval_files(eval_dir) if os.path.isdir(eval_dir) else []
    opus_eval_files: Dict[int, str] = {ch: path for ch, path in opus_eval_list}

    # 3. Collect scores
    codex_matched: List[int] = []
    opus_matched: List[int] = []
    missing_codex: List[int] = []
    missing_opus: List[int] = []
    failed_chapters: List[int] = []

    codex_overall: List[float] = []
    human_overall: List[float] = []
    codex_dim_pairs: Dict[str, Tuple[List[float], List[float]]] = {}

    opus_overall: List[float] = []
    opus_human_overall: List[float] = []
    codex_for_opus: List[float] = []  # codex scores aligned with opus
    opus_for_codex: List[float] = []  # opus scores aligned with codex
    opus_dim_pairs: Dict[str, Tuple[List[float], List[float]]] = {}

    # CC scores
    cc_engagement_codex: List[float] = []
    cc_engagement_human: List[float] = []
    cc_substance_codex: List[float] = []
    cc_substance_human: List[float] = []
    cc_substance_dim_pairs: Dict[str, Tuple[List[float], List[float]]] = {}

    for chapter in sorted(label_records.keys()):
        human_scores = label_records[chapter]["human_scores"]
        human_ov = _common.as_float(human_scores["overall"])
        if human_ov is None:
            continue

        # --- Codex QJ ---
        codex_qj_path = codex_qj_files.get(chapter)
        if codex_qj_path:
            codex_obj = _load_json_optional(codex_qj_path)
            if codex_obj is None or not isinstance(codex_obj, dict):
                failed_chapters.append(chapter)
                missing_codex.append(chapter)
            else:
                c_ov, c_dims = _extract_codex_qj_scores(codex_obj)
                if c_ov is not None:
                    codex_matched.append(chapter)
                    codex_overall.append(float(c_ov))
                    human_overall.append(float(human_ov))

                    # Per-dimension pairs
                    for dim_key, dim_score in c_dims.items():
                        h_dim = _common.as_float(human_scores.get(dim_key))
                        if h_dim is not None:
                            xs, ys = codex_dim_pairs.setdefault(dim_key, ([], []))
                            xs.append(float(dim_score))
                            ys.append(float(h_dim))
                else:
                    failed_chapters.append(chapter)
                    missing_codex.append(chapter)
        else:
            missing_codex.append(chapter)

        # --- Opus eval ---
        opus_path = opus_eval_files.get(chapter)
        if opus_path:
            opus_obj = _load_json_optional(opus_path)
            if opus_obj is not None and isinstance(opus_obj, dict):
                o_ov = _common.extract_overall(opus_obj)
                if o_ov is not None:
                    opus_matched.append(chapter)
                    opus_overall.append(float(o_ov))
                    opus_human_overall.append(float(human_ov))

                    # Codex vs Opus alignment
                    if chapter in codex_qj_files:
                        c_obj2 = _load_json_optional(codex_qj_files[chapter])
                        if c_obj2 and isinstance(c_obj2, dict):
                            c_ov2, c_dims2 = _extract_codex_qj_scores(c_obj2)
                            if c_ov2 is not None:
                                codex_for_opus.append(float(c_ov2))
                                opus_for_codex.append(float(o_ov))

                                o_dims = _common.extract_dimension_scores(opus_obj)
                                for dk, cv in c_dims2.items():
                                    ov = o_dims.get(dk)
                                    if ov is not None:
                                        cxs, cys = opus_dim_pairs.setdefault(dk, ([], []))
                                        cxs.append(float(cv))
                                        cys.append(float(ov))
                else:
                    missing_opus.append(chapter)
            else:
                missing_opus.append(chapter)
        else:
            missing_opus.append(chapter)

        # --- Codex CC ---
        codex_cc_path = codex_cc_files.get(chapter)
        if codex_cc_path:
            cc_obj = _load_json_optional(codex_cc_path)
            if cc_obj is not None and isinstance(cc_obj, dict):
                cc_scores = _extract_codex_cc_scores(cc_obj)

                # Engagement
                cc_eng = cc_scores.get("overall_engagement")
                h_eng = _common.as_float(human_scores.get("overall_engagement"))
                if cc_eng is not None and h_eng is not None:
                    cc_engagement_codex.append(float(cc_eng))
                    cc_engagement_human.append(float(h_eng))

                # Substance overall
                cc_sub = cc_scores.get("content_substance_overall")
                h_sub = _common.as_float(human_scores.get("content_substance_overall"))
                if cc_sub is not None and h_sub is not None:
                    cc_substance_codex.append(float(cc_sub))
                    cc_substance_human.append(float(h_sub))

                # Substance dimensions
                for sd in ("information_density", "plot_progression", "dialogue_efficiency"):
                    cc_sd = cc_scores.get(sd)
                    h_sd = _common.as_float(human_scores.get(sd))
                    if cc_sd is not None and h_sd is not None:
                        sxs, sys_ = cc_substance_dim_pairs.setdefault(sd, ([], []))
                        sxs.append(float(cc_sd))
                        sys_.append(float(h_sd))

    # 4. Compute statistics

    # Codex vs Human
    codex_vs_human_overall = _compute_stats(codex_overall, human_overall)
    codex_vs_human_dims: Dict[str, Any] = {}
    for dim_key in sorted(codex_dim_pairs.keys()):
        xs, ys = codex_dim_pairs[dim_key]
        codex_vs_human_dims[dim_key] = {
            "n": len(xs),
            "pearson_r": _safe_round(_pearson(xs, ys)),
        }

    # Codex CC vs Human
    cc_eng_stats = _compute_stats(cc_engagement_codex, cc_engagement_human)
    cc_sub_stats = _compute_stats(cc_substance_codex, cc_substance_human)
    cc_sub_dim_report: Dict[str, Any] = {}
    for sd_key in sorted(cc_substance_dim_pairs.keys()):
        sxs, sys_ = cc_substance_dim_pairs[sd_key]
        cc_sub_dim_report[sd_key] = _compute_stats(sxs, sys_)

    # Codex vs Opus
    codex_vs_opus_overall = _compute_stats(codex_for_opus, opus_for_codex)
    codex_vs_opus_dims: Dict[str, Any] = {}
    for dim_key in sorted(opus_dim_pairs.keys()):
        cxs, cys = opus_dim_pairs[dim_key]
        codex_vs_opus_dims[dim_key] = {
            "n": len(cxs),
            "pearson_r": _safe_round(_pearson(cxs, cys)),
        }

    # Summarizer ops
    all_chapters = sorted(
        set(codex_matched) | set(opus_matched)
    )
    summarizer_ops = _compare_summarizer_ops(project_dir, all_chapters)

    # 5. Gate threshold decision
    r_val = codex_vs_human_overall.get("pearson_r")
    bias_val = codex_vs_human_overall.get("bias")
    bias_abs = abs(bias_val) if bias_val is not None else None

    if r_val is not None and bias_abs is not None:
        if r_val >= 0.85 and bias_abs < 0.3:
            decision = "keep"
            rationale = "r >= 0.85 且偏移 < 0.3，门控阈值不变"
            suggested = None
        elif r_val >= 0.85 and bias_abs >= 0.3:
            decision = "adjust"
            default_thresholds = {
                "pass": 4.0, "polish": 3.5, "revise": 3.0, "pause_for_user": 2.0,
            }
            offset = bias_val if bias_val is not None else 0.0
            suggested = {
                k: _safe_round(max(1.0, min(5.0, v + offset)), 3)
                for k, v in default_thresholds.items()
            }
            rationale = f"r >= 0.85 但偏移 >= 0.3 (bias={_safe_round(bias_val)})，建议调整阈值或调整 prompt"
        else:
            decision = "review"
            rationale = f"r < 0.85 (r={_safe_round(r_val)})，需要检查低相关维度并调整 Codex prompt"
            suggested = None
    else:
        decision = "review"
        rationale = "样本不足，无法计算相关性"
        suggested = None

    threshold_decision = {
        "decision": decision,
        "pearson_r": _safe_round(r_val),
        "bias_abs": _safe_round(bias_abs),
        "rationale": rationale,
        "suggested_thresholds": suggested,
    }

    # 6. Assemble report
    now = _common.iso_utc_now()
    report: Dict[str, Any] = {
        "schema_version": 1,
        "generated_at": now,
        "eval_backend": "codex",
        "labels": {
            "path": os.path.abspath(labels_path),
            "records": len(label_records),
        },
        "alignment": {
            "codex_matched": codex_matched,
            "opus_matched": opus_matched,
            "missing_codex": missing_codex,
            "missing_opus": missing_opus,
            "failed_chapters": sorted(set(failed_chapters)),
        },
        "codex_vs_human": {
            "overall": codex_vs_human_overall,
            "dimensions": codex_vs_human_dims,
        },
        "codex_cc_vs_human": {
            "overall_engagement": cc_eng_stats,
            "content_substance_overall": cc_sub_stats,
            "substance_dimensions": cc_sub_dim_report,
        },
        "codex_vs_opus": {
            "overall": codex_vs_opus_overall,
            "dimensions": codex_vs_opus_dims,
        },
        "summarizer_ops": summarizer_ops,
        "threshold_decision": threshold_decision,
    }

    # 7. Output
    report_json = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    sys.stdout.write(report_json)

    if out_path:
        out_dir = os.path.dirname(os.path.abspath(out_path))
        if out_dir and not os.path.isdir(out_dir):
            os.makedirs(out_dir, exist_ok=True)
        try:
            with open(out_path, "w", encoding="utf-8") as f:
                f.write(report_json)
        except Exception as e:
            _die(f"failed to write report to {out_path}: {e}", 1)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:
        sys.stderr.write(f"{_SCRIPT}: unexpected error: {e}\n")
        raise SystemExit(2)
