# Agent Context Manifest 字段契约

## 概述

入口 Skill 为每个 Agent 组装一份 **context manifest**，包含两类字段：

- **inline**（内联）：由编排器确定性计算，直接写入 Task prompt——适用于需要预处理/裁剪/跨文件聚合的数据
- **paths**（文件路径）：指向项目目录下的文件，由 subagent 用 Read 工具自行读取——适用于大段原文内容

设计原则：
- 同一输入 + 同一项目文件 = 同一 manifest（确定性）
- paths 中的文件均为项目目录下的相对路径
- 可选字段缺失时不出现在 manifest 中（非 null）
- subagent 读取的文件内容不再需要 `<DATA>` 标签包裹（由 agent frontmatter 中的安全约束处理）

---

## ChapterWriter manifest

```
chapter_writer_manifest = {
  # ── inline（编排器计算） ──
  chapter: int,
  volume: int,
  storyline_id: str,
  chapter_outline_block: str,           # 从 outline.md 提取的本章区块文本
  storyline_context: {                  # 从 chapter_contract/schedule 解析
    last_chapter_summary: str,
    chapters_since_last: int,
    line_arc_progress: str,
  },
  concurrent_state: {str: str},         # 其他活跃线一句话状态
  transition_hint: obj | null,          # 切线过渡
  hard_rules_list: [str],              # L1 禁止项列表（已格式化；仅 established + INTRODUCING 标记的 planned）
  foreshadowing_tasks: [obj],          # 本章伏笔任务子集
  ai_blacklist_top10: [str],           # 有效黑名单前 10 词
  style_drift_directives: [str] | null, # 漂移纠偏指令（active 时注入）

  # ── paths（subagent 自读） ──
  paths: {
    style_profile: "style-profile.json",                              # 必读（含 style_exemplars + writing_directives）
    style_drift: "style-drift.json",                                  # 可选
    chapter_contract: "volumes/vol-{V:02d}/chapter-contracts/chapter-{C:03d}.json",
    volume_outline: "volumes/vol-{V:02d}/outline.md",
    current_state: "state/current-state.json",
    world_rules: "world/rules.json",                                  # 可选
    recent_summaries: ["summaries/chapter-{C-1:03d}-summary.md", ...], # 近 3 章
    storyline_memory: "storylines/{storyline_id}/memory.md",           # 可选
    adjacent_memories: ["storylines/{adj_id}/memory.md", ...],         # 可选
    character_contracts: ["staging/context/characters/{slug}.json", ...], # canon_status 预过滤后的 staging 副本
    platform_guide: "templates/platforms/{platform}.md",                  # 可选（M5.2；style-profile.platform 非空且文件存在时加载）
    project_brief: "brief.md",
    writing_methodology: "skills/novel-writing/references/style-guide.md",  # 可选
  }
}
```

### 修订模式追加字段

```
chapter_writer_revision_manifest = chapter_writer_manifest + {
  # ── inline 追加 ──
  required_fixes: [{target: str, instruction: str}],  # QualityJudge 最小修订指令（与 eval 输出格式一致）
  high_confidence_violations: [obj],    # confidence="high" 的违约条目

  # ── paths 追加 ──
  paths += {
    chapter_draft: "staging/chapters/chapter-{C:03d}.md",  # 待修订的现有正文
  }
}
```

---

## Summarizer manifest

```
summarizer_manifest = {
  # ── inline ──
  chapter: int,
  volume: int,
  storyline_id: str,
  foreshadowing_tasks: [obj],
  entity_id_map: {slug_id: display_name},
  hints: [str] | null,                 # ChapterWriter 输出的 hints JSON（编排器从 ChapterWriter 输出末尾的 ```json{"chapter":N,"hints":[...]}``` 块解析；解析失败则为 null）

  # ── paths ──
  paths: {
    chapter_draft: "staging/chapters/chapter-{C:03d}.md",
    current_state: "state/current-state.json",
  }
}
```

> **canon_hints 输出**：Summarizer 在 delta.json 顶层输出 `canon_hints` 字段（`[{type, hint, confidence, evidence}]`），供编排器 commit 阶段做 canon_status 升级。缺失时视为空数组。

---

## StyleRefiner manifest

```
style_refiner_manifest = {
  # ── inline ──
  chapter: int,
  style_drift_directives: [str] | null,

  # ── paths ──
  paths: {
    chapter_draft: "staging/chapters/chapter-{C:03d}.md",
    style_profile: "style-profile.json",         # 必读（含 style_exemplars）
    style_drift: "style-drift.json",             # 可选
    ai_blacklist: "ai-blacklist.json",
    style_guide: "skills/novel-writing/references/style-guide.md",
    previous_change_log: "staging/logs/style-refiner-chapter-{C:03d}-changes.json",  # 仅二次润色时出现；首次润色不含此字段
  }
}
```

---

## QualityJudge manifest

```
quality_judge_manifest = {
  # ── inline ──
  chapter: int,
  volume: int,
  chapter_outline_block: str,
  hard_rules_list: [str],
  planned_rule_ids: [str],                    # 所有 canon_status=="planned" 的规则 ID（供 planned 引用检测）
  blacklist_lint: obj | null,                    # scripts/lint-blacklist.sh 输出
  ner_entities: obj | null,                      # scripts/run-ner.sh 输出
  continuity_report_summary: obj | null,         # logs/continuity/latest.json 裁剪

  # ── paths ──
  paths: {
    chapter_draft: "staging/chapters/chapter-{C:03d}.md",
    style_profile: "style-profile.json",
    ai_blacklist: "ai-blacklist.json",
    chapter_contract: "volumes/vol-{V:02d}/chapter-contracts/chapter-{C:03d}.json",
    world_rules: "world/rules.json",                                  # 可选
    prev_summary: "summaries/chapter-{C-1:03d}-summary.md",           # 可选（首章无）
    recent_summaries: ["summaries/chapter-{C-2:03d}-summary.md", ...], # 可选（章节 ≤ 003 且 platform_guide 存在时注入，供平台硬门回溯判定；按可用性降级：Ch001 为空数组，Ch002 仅含 Ch001，Ch003 含 Ch001+002；路径不存在时跳过该条目）
    character_profiles: ["characters/active/{slug}.md", ...],          # 裁剪后选取（叙述档案）
    character_contracts: ["staging/context/characters/{slug}.json", ...], # canon_status 预过滤后的 staging 副本（L2 结构化契约）
    storyline_spec: "storylines/storyline-spec.json",                  # 可选
    storyline_schedule: "volumes/vol-{V:02d}/storyline-schedule.json", # 可选
    cross_references: "staging/state/chapter-{C:03d}-crossref.json",
    quality_rubric: "skills/novel-writing/references/quality-rubric.md",
    platform_guide: "templates/platforms/{platform}.md",                 # 可选（M5.2 注入路径；M6.2 启用加权评分逻辑）
  }
}
```

---

另见：`continuity-checks.md`（NER schema + 一致性报告 schema + LS-001 结构化输入约定）。
