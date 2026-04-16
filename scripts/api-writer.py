#!/usr/bin/env python3
"""
api-writer.py — 通过 API 直接调用模型写作，绕过 Claude Code 内置系统提示词。

用法:
  # 正式调用
  python scripts/api-writer.py manifest.json

  # 干跑模式（只组装提示词，不调 API）
  python scripts/api-writer.py manifest.json --dry-run

  # 指定模型和温度
  python scripts/api-writer.py manifest.json --model gemini-3.1-pro-preview --temperature 0.9

API key 从环境变量 DMXAPI_KEY 读取，或从项目根目录 .env 文件解析。
"""

import argparse
import json
import os
import sys
import ssl
import urllib.request
import urllib.error
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SYSTEM_PROMPT = PLUGIN_ROOT / "prompts" / "api-writer-system.md"
API_BASE = "https://www.dmxapi.cn/v1/chat/completions"

# Will be set from --project arg or manifest directory
PROJECT_ROOT: Path = PLUGIN_ROOT
SUPPORTED_TASK = "chapter-writer"


def load_manifest(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


MAX_INPUT_TOKENS = 200_000
MAX_OUTPUT_TOKENS = 65536


def read_file(rel_path: str) -> str | None:
    """Read a project-relative file. Returns None if missing (logs warning)."""
    full = PROJECT_ROOT / rel_path
    if full.exists():
        return full.read_text(encoding="utf-8")
    print(f"[api-writer] WARN: 文件不存在，跳过: {rel_path}", file=sys.stderr)
    return None


def read_section(rel_path: str, label: str) -> str | None:
    """Read a file and wrap it with a section header."""
    content = read_file(rel_path)
    if content:
        return f"## {label}\n\n{content}"
    return None


def detect_manifest_task(manifest: dict, manifest_path: str) -> str:
    """Detect manifest task, with compatibility for old manifests without task."""
    if isinstance(manifest.get("task"), str) and manifest["task"].strip():
        return manifest["task"].strip()

    stem = Path(manifest_path).stem
    for suffix in (
        "chapter-writer",
        "style-refiner",
        "summarizer",
        "quality-judge",
        "content-critic",
    ):
        if stem.endswith(f"-{suffix}"):
            return suffix

    if "chapter_outline_block" in manifest or "storyline_id" in manifest:
        return "chapter-writer"

    return "unknown"


def extract_style_directives(profile_path: str) -> list[str]:
    """Extract quantitative writing directives from style-profile.json."""
    content = read_file(profile_path)
    if not content:
        return []
    try:
        sp = json.loads(content)
    except json.JSONDecodeError:
        return []
    directives = []
    # Inner monologue density from tonal_variance expectations
    rm = sp.get("register_mixing")
    if rm in ("high", "medium"):
        directives.append(
            "主角内心独白（含吐槽/自嘲）每 200-300 字至少出现 1 处，不可连续 500 字纯叙述无内心反应"
        )
    # Sentence length guidance
    asl = sp.get("avg_sentence_length")
    slr = sp.get("sentence_length_range")
    if asl and isinstance(asl, (int, float)):
        directives.append(f"平均句长目标: ~{int(asl)} 字，长短句交替制造节奏感")
    if (slr and isinstance(slr, list) and len(slr) == 2
            and all(isinstance(x, (int, float)) for x in slr)):
        directives.append(f"句长范围: {slr[0]}-{slr[1]} 字，避免全文句长趋同")
    # Scene description constraint
    oc = sp.get("override_constraints") or {}
    max_scene = oc.get("max_scene_sentences") if isinstance(oc, dict) else None
    if max_scene and isinstance(max_scene, int):
        directives.append(f"场景描写 ≤ {max_scene} 句，优先用动作推进")
    return directives


def tail_paragraphs(text: str, max_paragraphs: int = 3, max_chars: int = 900) -> str:
    """Keep the last few non-empty paragraphs as a boundary handoff excerpt."""
    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
    if not paragraphs:
        return text[-max_chars:].strip()
    excerpt = "\n\n".join(paragraphs[-max_paragraphs:]).strip()
    if len(excerpt) > max_chars:
        excerpt = excerpt[-max_chars:].strip()
    return excerpt


def build_storyline_context_section(sc: dict) -> str | None:
    """Format non-boundary storyline context and avoid repeating handoff facts."""
    lines: list[str] = []
    if sc.get("line_arc_progress"):
        lines.append(f"- 当前线推进目标：{sc['line_arc_progress']}")
    if sc.get("chapters_since_last") is not None:
        lines.append(f"- 距离该线上一章：{sc['chapters_since_last']} 章")
    if not lines:
        return None
    return "## 故事线上下文\n\n" + "\n".join(lines)


def assemble_user_message(m: dict) -> str:
    """Turn manifest + files into a single user message."""
    core_parts: list[str] = []
    boundary_parts: list[str] = []
    support_parts: list[str] = []
    paths = m.get("paths", {})
    style_directives: list[str] = []
    previous_chapter_tail: str | None = None
    ch = m.get("chapter", "?")
    vol = m.get("volume", "?")
    sl = m.get("storyline_id", "?")

    core_parts.append(
        "## 任务卡\n\n"
        f"- 任务：续写第 {ch} 章（第 {vol} 卷，故事线 {sl}）\n"
        "- 目标：写出可直接进入正文的完整章节，不解释过程，不复述上下文\n"
        "- 优先级：硬规则/章节契约 > 章节边界衔接 > 本章大纲 > 风格样本与近章正文\n"
        "- 成功标准：开头承接上章余波，中段完成本章主事件，结尾制造下一章驱动力"
    )

    # --- File-backed sections (by read priority) ---

    # 1. Style samples (highest priority)
    if p := paths.get("style_samples"):
        if s := read_section(p, "风格样本"):
            core_parts.append(s)

    # 2. Style profile
    if p := paths.get("style_profile"):
        if s := read_section(p, "风格指纹"):
            core_parts.append(s)
        style_directives = extract_style_directives(p)

    # 3. Style drift (optional)
    if p := paths.get("style_drift"):
        if s := read_section(p, "风格漂移纠偏"):
            support_parts.append(s)

    # 4. Chapter contract
    if p := paths.get("chapter_contract"):
        if s := read_section(p, "章节契约"):
            core_parts.append(s)

    # 5. Recent chapters (full text for style continuity; fallback to summaries)
    if ps := paths.get("recent_chapters"):
        ps = ps if isinstance(ps, list) else [ps]
        chapter_payloads = [(p, c) for p in ps if (c := read_file(p))]
        texts = [f"--- {p} ---\n{c}" for p, c in chapter_payloads]
        if texts:
            core_parts.append("## 近章正文\n\n" + "\n\n".join(texts))
        if chapter_payloads:
            previous_chapter_tail = tail_paragraphs(chapter_payloads[0][1])

    # 6. Volume outline
    if p := paths.get("volume_outline"):
        if s := read_section(p, "卷大纲"):
            support_parts.append(s)

    # 7. Character contracts
    if ps := paths.get("character_contracts"):
        ps = ps if isinstance(ps, list) else [ps]
        texts = [f"--- {p} ---\n{c}" for p in ps if (c := read_file(p))]
        if texts:
            support_parts.append("## 角色档案\n\n" + "\n\n".join(texts))

    # 8. Current state
    if p := paths.get("current_state"):
        if s := read_section(p, "当前状态"):
            support_parts.append(s)

    # 9. World rules
    if p := paths.get("world_rules"):
        if s := read_section(p, "世界规则"):
            support_parts.append(s)

    # 10. Storyline memory
    if p := paths.get("storyline_memory"):
        if s := read_section(p, "故事线记忆"):
            support_parts.append(s)

    # 11. Adjacent memories
    if ps := paths.get("adjacent_memories"):
        ps = ps if isinstance(ps, list) else [ps]
        texts = [f"--- {p} ---\n{c}" for p in ps if (c := read_file(p))]
        if texts:
            support_parts.append("## 相邻线记忆\n\n" + "\n\n".join(texts))

    # 12. Platform guide
    if p := paths.get("platform_guide"):
        if s := read_section(p, "平台指南"):
            support_parts.append(s)

    # 13. Project brief
    if p := paths.get("project_brief"):
        if s := read_section(p, "项目简介"):
            support_parts.append(s)

    # --- Inline sections ---

    if v := m.get("chapter_outline_block"):
        core_parts.append(f"## 本章大纲\n\n{v}")

    if v := m.get("hard_rules_list"):
        core_parts.append("## 硬规则禁止项\n\n" + "\n".join(f"- {r}" for r in v))

    if v := m.get("foreshadowing_tasks"):
        support_parts.append(f"## 伏笔任务\n\n```json\n{json.dumps(v, ensure_ascii=False, indent=2)}\n```")

    if v := m.get("concurrent_state"):
        support_parts.append("## 其他线并发状态\n\n" + "\n".join(f"- {k}: {s}" for k, s in v.items()))

    if v := m.get("transition_hint"):
        support_parts.append(f"## 切线过渡提示\n\n```json\n{json.dumps(v, ensure_ascii=False, indent=2)}\n```")

    boundary_notes: list[str] = []
    if isinstance(m.get("storyline_context"), dict):
        sc = m["storyline_context"]
        if section := build_storyline_context_section(sc):
            support_parts.append(section)
        if sc.get("last_chapter_summary"):
            boundary_notes.append(f"### 必须承接的前章后果/悬念\n\n{sc['last_chapter_summary']}")
    if previous_chapter_tail:
        boundary_notes.append("### 上一章结尾原文（开头 1-3 段必须接上）\n\n" + previous_chapter_tail)
    if boundary_notes:
        boundary_parts.append("## 章节边界衔接\n\n" + "\n\n".join(boundary_notes))

    if v := m.get("style_drift_directives"):
        support_parts.append("## 风格漂移纠偏指令\n\n" + "\n".join(f"- {d}" for d in v))

    # --- Writing instruction ---

    reqs = [
        "字数 2500-3500 字",
        "完成章节契约中所有 required objectives",
        f"输出格式：`# 第 {ch} 章 章名` + 正文",
        "只输出章节正文，不要输出其他内容",
        "先在心里锁定四件事：章首接什么、章中主冲突怎么推进、章末发生什么不可逆变化、下一章为什么必须继续看",
        "开头 1-3 段必须承接“章节边界衔接”中的前章后果/悬念，不要重新起一个无关开场",
        "中段围绕本章大纲和章节契约推进，不要把契约、设定原样复述成正文",
        "结尾必须完成本章不可逆变化，并留下明确的下一章驱动力，不能软塌塌收尾",
        "若近章正文与契约有表述重叠，提炼后再写，不要重复叙述同一信息",
        "质感锚点是素材池，不是打卡清单；全章择要吸收 1-3 个最有效的细节即可",
        "细节必须服务动作、冲突、情绪或关系推进；不能连续堆叠多个并列细节让剧情停住",
    ]
    reqs.extend(style_directives)

    core_parts.append(
        f"## 写作指令\n\n"
        f"请续写第 {ch} 章（第 {vol} 卷，故事线 {sl}）。\n\n"
        f"要求：\n" + "\n".join(f"- {r}" for r in reqs)
    )

    parts: list[str] = []
    parts.append("## 核心任务包\n\n以下内容定义本章必须完成的任务、风格锚点与主事件。")
    parts.extend(core_parts)
    if boundary_parts:
        parts.append("## 章节边界包\n\n以下内容只决定章首承接与章末钩子，优先级高于普通支撑上下文。")
        parts.extend(boundary_parts)
    if support_parts:
        parts.append("## 支撑上下文\n\n以下内容是主控裁剪后的相关片段，只在推动正文时按需吸收，不要逐条复述。")
        parts.extend(support_parts)

    return "\n\n---\n\n".join(parts)


def get_api_key() -> str | None:
    """Read API key from env or .env file (check both plugin and project dirs)."""
    if key := os.environ.get("DMXAPI_KEY"):
        return key
    for root in [PLUGIN_ROOT, PROJECT_ROOT]:
        env_file = root / ".env"
        if env_file.exists():
            for line in env_file.read_text().splitlines():
                line = line.strip()
                if line.startswith("DMXAPI_KEY="):
                    return line.split("=", 1)[1].strip().strip("\"'")
    return None


def call_api(system_prompt: str, user_message: str,
             api_key: str, model: str, temperature: float) -> dict:
    """POST to API, return parsed JSON response."""
    payload = json.dumps({
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_message},
        ],
        "temperature": temperature,
        "max_tokens": MAX_OUTPUT_TOKENS,
    }, ensure_ascii=False).encode("utf-8")

    req = urllib.request.Request(
        API_BASE,
        data=payload,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json; charset=utf-8",
        },
        method="POST",
    )
    ctx = ssl.create_default_context()  # uses system cert store on macOS/Linux
    with urllib.request.urlopen(req, timeout=600, context=ctx) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main():
    ap = argparse.ArgumentParser(description="API Writer — 纯净环境章节写作")
    ap.add_argument("manifest", help="Context manifest JSON 路径")
    ap.add_argument("--project", help="小说项目根目录（manifest 中的路径相对于此目录）")
    ap.add_argument("--model", default="gemini-3.1-pro-preview",
                     help="模型名称 (default: gemini-3.1-pro-preview)")
    ap.add_argument("--temperature", type=float, default=0.85,
                     help="温度 (default: 0.85)")
    ap.add_argument("--system-prompt",
                     help=f"System prompt 文件 (default: prompts/api-writer-system.md)")
    ap.add_argument("--output", help="输出路径 (default: <project>/staging/chapters/chapter-{N}.md)")
    ap.add_argument("--dry-run", action="store_true",
                     help="只组装提示词写入 staging/dry-run/，不调 API")
    args = ap.parse_args()

    # Resolve project root (novel project, not plugin)
    global PROJECT_ROOT
    if args.project:
        PROJECT_ROOT = Path(args.project).resolve()
    else:
        PROJECT_ROOT = Path(args.manifest).resolve().parent
    print(f"[api-writer] Project: {PROJECT_ROOT}")

    # Load manifest
    manifest = load_manifest(args.manifest)
    task = detect_manifest_task(manifest, args.manifest)
    if task != SUPPORTED_TASK:
        print(
            "[api-writer] Error: 当前 manifest 任务类型为 "
            f"{task!r}，但 api-writer.py 只支持 {SUPPORTED_TASK!r} 初稿写作。"
            " style-refiner / summarizer / quality-judge / content-critic"
            " 必须走各自 agent 或专用脚本。",
            file=sys.stderr,
        )
        sys.exit(1)
    chapter = manifest.get("chapter", 0)

    # Load system prompt
    sp_path = Path(args.system_prompt) if args.system_prompt else DEFAULT_SYSTEM_PROMPT
    if not sp_path.exists():
        print(f"[api-writer] Error: system prompt not found: {sp_path}", file=sys.stderr)
        sys.exit(1)
    system_prompt = sp_path.read_text(encoding="utf-8")

    # Assemble user message
    user_message = assemble_user_message(manifest)

    # Stats
    sys_chars = len(system_prompt)
    usr_chars = len(user_message)
    est_tokens = int((sys_chars + usr_chars) * 1.5)
    print(f"[api-writer] Task: {task}")
    print(f"[api-writer] System: {sys_chars} 字 | User: {usr_chars} 字 | ~{est_tokens} tokens")
    print(f"[api-writer] Model: {args.model} | Temperature: {args.temperature}")

    if est_tokens > MAX_INPUT_TOKENS:
        print(f"[api-writer] Error: 估算 {est_tokens} tokens 超过上限 {MAX_INPUT_TOKENS}，"
              f"请裁剪 context 或调整 MAX_INPUT_TOKENS", file=sys.stderr)
        sys.exit(1)

    # Dry run — write prompts for inspection
    if args.dry_run:
        dry_dir = PROJECT_ROOT / "staging" / "dry-run"
        dry_dir.mkdir(parents=True, exist_ok=True)
        (dry_dir / "system.md").write_text(system_prompt, encoding="utf-8")
        (dry_dir / "user.md").write_text(user_message, encoding="utf-8")
        print(f"[api-writer] Dry run → {dry_dir}/")
        return

    # API key
    api_key = get_api_key()
    if not api_key:
        print("[api-writer] Error: DMXAPI_KEY 未设置（环境变量或 .env）", file=sys.stderr)
        sys.exit(1)

    # Call
    print("[api-writer] Calling API...")
    retries = 0
    data = None
    while retries <= 1:
        try:
            data = call_api(system_prompt, user_message, api_key, args.model, args.temperature)
            break
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")
            if e.code in (429, 502, 503) and retries == 0:
                retries += 1
                import time
                wait = 5
                print(f"[api-writer] HTTP {e.code}，{wait}s 后重试...", file=sys.stderr)
                time.sleep(wait)
                continue
            print(f"[api-writer] HTTP {e.code}: {body}", file=sys.stderr)
            sys.exit(1)
        except Exception as e:
            print(f"[api-writer] Error: {e}", file=sys.stderr)
            sys.exit(1)

    # Extract result (reasoning models put thinking in reasoning_content)
    try:
        choice = data["choices"][0]["message"]
    except (KeyError, IndexError, TypeError) as e:
        print(f"[api-writer] Error: API 返回结构异常: {e}", file=sys.stderr)
        print(f"[api-writer] Raw: {json.dumps(data, ensure_ascii=False)[:500]}", file=sys.stderr)
        sys.exit(1)
    text = choice.get("content") or ""
    reasoning = choice.get("reasoning_content") or ""
    if not text and reasoning:
        print("[api-writer] Warning: content 为空，模型可能 token 不足（reasoning 用完了额度）",
              file=sys.stderr)
        sys.exit(1)
    usage = data.get("usage", {})
    prompt_tok = usage.get("prompt_tokens", "?")
    comp_tok = usage.get("completion_tokens", "?")

    # Write output
    out_path = Path(args.output) if args.output else PROJECT_ROOT / "staging" / "chapters" / f"chapter-{chapter:03d}.md"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(text, encoding="utf-8")

    print(f"[api-writer] Done — {len(text)} 字 → {out_path}")
    print(f"[api-writer] Tokens: prompt={prompt_tok} completion={comp_tok}")
    if reasoning:
        print(f"[api-writer] Reasoning: {len(reasoning)} 字")


if __name__ == "__main__":
    main()
