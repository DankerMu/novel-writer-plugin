## 9. 数据结构

### 9.1 项目目录结构

```
novel-project/
├── .checkpoint.json                # Orchestrator 恢复点
├── .novel.lock/                    # 并发锁目录（运行时创建/删除，见 §10.7）
├── brief.md                        # 创作纲领（精简，≤1000 字）
├── style-profile.json              # 用户风格指纹
├── ai-blacklist.json               # AI 用语黑名单
├── style-drift.json                # 风格漂移纠偏指令（每 5 章检测生成，回归基线后清除）
├── research/                       # 背景研究资料（doc-workflow 导入或手动放入）
│   └── *.md                        # 每个主题一个文件，WorldBuilder/CharacterWeaver 自动读取
├── world/                          # 世界观（活文档）
│   ├── geography.md
│   ├── history.md
│   ├── rules.md
│   ├── rules.json                  # L1 结构化规则表（WorldBuilder 产出）
│   └── changelog.md
├── characters/
│   ├── active/                     # 当前活跃角色
│   ├── retired/                    # 已退场角色
│   ├── relationships.json
│   └── changelog.md
├── storylines/                     # 多线叙事管理
│   ├── storylines.json             # 全局故事线定义
│   ├── storyline-spec.json         # LS 故事线规范
│   └── {storyline-id}/
│       └── memory.md               # 故事线独立记忆（≤500 字关键事实，Summarizer 每章更新）
├── volumes/                        # 卷制结构
│   ├── vol-01/
│   │   ├── outline.md
│   │   ├── storyline-schedule.json # 本卷故事线调度
│   │   ├── foreshadowing.json
│   │   ├── chapter-contracts/      # L3 章节契约（PlotArchitect 生成）
│   │   │   ├── chapter-001.json
│   │   │   └── ...
│   │   └── review.md
│   └── vol-02/ ...
├── chapters/
│   ├── chapter-001.md
│   └── ...
├── staging/                        # 暂存区（事务语义：写作流水线 + 卷规划）
│   ├── chapters/                   # draft → refined 章节
│   ├── summaries/                  # 章节摘要（Summarizer 产出，commit 时移入 summaries/）
│   ├── state/                      # state delta（Summarizer 产出）
│   ├── storylines/                 # 故事线记忆更新（Summarizer 产出，commit 时覆盖 storylines/*/memory.md）
│   ├── evaluations/                # 评估结果
│   ├── volumes/                    # 卷规划产物（PlotArchitect 产出，用户批准后 commit 至 volumes/）
│   └── foreshadowing/              # 预留：伏笔相关中间产物/报告（global.json 由每章 commit 阶段从 foreshadow ops 更新）
├── summaries/                      # 章节摘要（context 压缩核心）
│   ├── chapter-001-summary.md
│   └── ...
├── state/
│   ├── current-state.json          # 当前全局状态（含 schema_version + state_version）
│   ├── changelog.jsonl             # 状态变更审计日志（每行一条 ops 记录）
│   └── history/                    # 每卷存档
│       └── vol-01-final-state.json
├── foreshadowing/
│   └── global.json                 # 跨卷伏笔
├── evaluations/
│   ├── chapter-001-eval.json
│   └── ...
└── logs/                          # 流水线日志 + 分析报告
    ├── chapter-001-log.json
    ├── unknown-entities.jsonl
    ├── continuity/                 # 一致性检查报告（NER）
    │   ├── latest.json
    │   └── continuity-report-vol-01-ch001-ch010.json
    ├── foreshadowing/              # 伏笔盘点报告
    │   ├── latest.json
    │   └── foreshadowing-check-vol-01-ch001-ch010.json
    └── storylines/                 # 故事线分析报告
        ├── rhythm-latest.json
        ├── rhythm-vol-01-ch001-ch010.json
        ├── broken-bridges-latest.json
        └── broken-bridges-vol-01-ch001-ch010.json
```

> **chapter_id 命名规范**：全局统一使用 3 位零填充格式 `chapter-{C:03d}`（如 `chapter-001`、`chapter-048`、`chapter-150`）。适用于所有章节相关文件：`chapters/chapter-{C:03d}.md`、`summaries/chapter-{C:03d}-summary.md`、`evaluations/chapter-{C:03d}-eval.json`、`staging/` 下对应文件、`logs/chapter-{C:03d}-log.json`、`chapter-contracts/chapter-{C:03d}.json`。hook 脚本使用 `printf '%03d'` 格式化。
> **实体 ID 命名规范**：角色、故事线等实体使用稳定的 **slug ID**（小写英文/拼音 + 连字符，如 `zhang-san`、`main-arc`），而非中文显示名。ops path 统一使用 ID：`characters.zhang-san.location`（非 `characters.张三.location`）。角色档案文件名即为 ID（`characters/active/zhang-san.md` + `characters/active/zhang-san.json`），其中 `.md` 为叙述性档案，`.json` 为结构化数据（至少包含 `display_name` 与 `contracts[]`）。`storyline_id` 同理（`storylines/main-arc/memory.md`）。关系映射也使用 ID：`relationships: {"li-si": 50}`。

### 9.2 关键数据格式

**Checkpoint** (`.checkpoint.json`):
```json
{
  "last_completed_chapter": 47,
  "current_volume": 2,
  "orchestrator_state": "WRITING",
  "pipeline_stage": "committed",
  "inflight_chapter": null,
  "revision_count": 0,
  "pending_actions": [],
  "last_checkpoint_time": "2026-02-21T15:30:00"
}
```

`orchestrator_state` 取值（详见 PRD §8.2 状态机）：`QUICK_START`、`VOL_PLANNING`、`WRITING`、`CHAPTER_REWRITE`、`VOL_REVIEW`、`ERROR_RETRY`。（无 `.checkpoint.json` 视为 `INIT`。）

`pipeline_stage` 取值：`null`（空闲）→ `drafting`（初稿生成中）→ `drafted`（初稿 + 摘要 + delta 已生成）→ `refined`（润色完成）→ `judged`（评估完成）→ `revising`（门控触发的修订/二次润色循环中）→ `committed`（已提交到正式目录）。

- `inflight_chapter` 记录当前正在处理的章节号
- `revision_count` 记录当前 `inflight_chapter` 的修订次数（用于限制修订循环；commit 后重置为 0）

冷启动恢复时：若 `pipeline_stage != committed && inflight_chapter != null`，检查 `staging/` 子目录并从对应阶段恢复：
- `drafting` 且 `staging/chapters/` 无对应文件 → 重启整章
- `drafting` 且 `staging/chapters/` 有初稿但 `staging/summaries/` 无摘要 → 从 Summarizer 恢复
- `drafted` → 跳过 ChapterWriter 和 Summarizer，从 StyleRefiner 恢复
- `refined` → 从 QualityJudge 恢复
- `judged` → 执行 commit 阶段
- `revising` → 从 ChapterWriter 重启（保留 `revision_count`，防止无限循环）
```

**角色状态** (`state/current-state.json`):
```json
{
  "schema_version": 1,
  "state_version": 47,
  "last_updated_chapter": 47,
  "characters": {
    "lin-feng": {
      "display_name": "林枫",
      "location": "魔都",
      "emotional_state": "决意",
      "relationships": {"chen-lao": 50, "zhao-ming": -30},
      "inventory": ["破碎魔杖", "密信"]
    }
  },
  "world_state": {
    "ongoing_events": ["王国内战"],
    "time_marker": "第三年冬"
  },
  "active_foreshadowing": ["ancient_prophecy", "betrayal_hint"]
}
```

**状态变更 Patch**（Summarizer 权威输出格式，ChapterWriter 仅输出自然语言 hints）：
```json
{
  "chapter": 48,
  "base_state_version": 47,
  "storyline_id": "main-arc",
  "ops": [
    {"op": "set", "path": "characters.lin-feng.location", "value": "幽暗森林"},
    {"op": "set", "path": "characters.lin-feng.emotional_state", "value": "警觉"},
    {"op": "inc", "path": "characters.lin-feng.relationships.chen-lao", "value": 10},
    {"op": "add", "path": "characters.lin-feng.inventory", "value": "密信"},
    {"op": "remove", "path": "characters.lin-feng.inventory", "value": "破碎魔杖"},
    {"op": "set", "path": "world_state.time_marker", "value": "第三年冬末"},
    {"op": "foreshadow", "path": "ancient_prophecy", "value": "advanced", "detail": "主角梦见预言碎片"}
  ]
}
```

操作类型：`set`（覆盖字段）、`add`（追加到数组）、`remove`（从数组移除）、`inc`（数值增减）、`foreshadow`（伏笔状态变更：planted/advanced/resolved）。合并器在写入前校验 `base_state_version` 匹配当前 `state_version`，应用后 `state_version += 1`，变更记录追加到 `state/changelog.jsonl`。

**伏笔追踪** (`foreshadowing/global.json`):
```json
{
  "foreshadowing": [
    {
      "id": "ancient_prophecy",
      "description": "远古预言暗示主角命运",
      "scope": "long",
      "status": "advanced",
      "planted_chapter": 3,
      "planted_storyline": "main-arc",
      "target_resolve_range": [10, 20],
      "last_updated_chapter": 48,
      "history": [
        {"chapter": 3, "action": "planted", "detail": "老者口中提及预言碎片"},
        {"chapter": 15, "action": "advanced", "detail": "主角在密室发现预言石板"},
        {"chapter": 48, "action": "advanced", "detail": "主角梦见预言碎片"}
      ]
    }
  ]
}
```

> 伏笔状态：`planted`（埋设）→ `advanced`（推进，可多次）→ `resolved`（回收）。`scope` 标记伏笔层级：`short`（卷内，3-10 章回收）、`medium`（跨 1-3 卷回收）、`long`（全书级，无固定回收期限，每 1-2 卷至少 advanced 一次保持活性）。`target_resolve_range` 为建议回收章节范围，`short` scope 超过上限未回收的伏笔在 `/novel:dashboard` 中标记为"超期"，`long` scope 伏笔不触发超期警告。commit 阶段从 foreshadow ops 提取更新：`planted` → 新增条目，`advanced` → 追加 history + 更新 status/last_updated_chapter，`resolved` → 更新 status。

**风格指纹** (`style-profile.json`):
```json
{
  "avg_sentence_length": 18,
  "dialogue_ratio": 0.4,
  "rhetoric_preferences": ["短句切换", "少用比喻"],
  "forbidden_words": ["莫名的", "不禁", "嘴角微微上扬"],
  "character_speech_patterns": {
    "protagonist": "喜欢用反问句，口头禅'有意思'",
    "mentor": "文言腔，爱说'善'"
  }
}
```

**质量评估** (`evaluations/chapter-N-eval.json`):
```json
{
  "chapter": 47,
  "contract_verification": {"l1_checks": [], "l2_checks": [], "l3_checks": [], "ls_checks": [], "has_violations": false},
  "scores": {
    "plot_logic": {"score": 4, "weight": 0.18, "reason": "...", "evidence": "原文引用"},
    "character": {"score": 4, "weight": 0.18, "reason": "...", "evidence": "原文引用"},
    "immersion": {"score": 4, "weight": 0.15, "reason": "...", "evidence": "原文引用"},
    "foreshadowing": {"score": 3, "weight": 0.10, "reason": "...", "evidence": "原文引用"},
    "pacing": {"score": 4, "weight": 0.08, "reason": "...", "evidence": "原文引用"},
    "style_naturalness": {"score": 4, "weight": 0.15, "reason": "AI 黑名单命中 1 次/千字", "evidence": "原文引用"},
    "emotional_impact": {"score": 3, "weight": 0.08, "reason": "...", "evidence": "原文引用"},
    "storyline_coherence": {"score": 4, "weight": 0.08, "reason": "...", "evidence": "原文引用"}
  },
  "overall": 3.78,
  "recommendation": "pass",
  "risk_flags": [],
  "required_fixes": [],
  "issues": [],
  "strengths": ["情节节奏张弛得当"]
}
```

**Pipeline Log** (`logs/chapter-N-log.json`):
```json
{
  "chapter": 47,
  "storyline_id": "main-quest",
  "started_at": "2026-03-15T14:30:00+08:00",
  "stages": [
    {"name": "draft", "model": "sonnet", "duration_ms": 45000, "input_tokens": null, "output_tokens": null},
    {"name": "summarize", "model": "sonnet", "duration_ms": 8000, "input_tokens": null, "output_tokens": null},
    {"name": "refine", "model": "opus", "duration_ms": 42000, "input_tokens": null, "output_tokens": null},
    {"name": "judge", "model": "sonnet", "duration_ms": 15000, "input_tokens": null, "output_tokens": null}
  ],
  "gate_decision": "pass",
  "revisions": 0,
  "force_passed": false,
  "judges": {
    "primary": {"model": "sonnet", "overall": 4.2},
    "used": "primary",
    "overall_final": 4.2
  },
  "total_duration_ms": 110000,
  "total_cost_usd": null
}
```

> `judges` 字段（M3 新增）：记录门控裁判详情。关键章（卷首/卷尾/交汇事件章）额外包含 `secondary` 子对象（`{"model": "opus", "overall": 3.8}`），`overall_final = min(primary.overall, secondary.overall)`，`used` 标记实际采用的裁判。普通章仅含 `primary`。`force_passed`（M3 新增）：修订次数耗尽后强制通过时为 `true`。
>
> 每章流水线完成后由入口 Skill 写入 `logs/chapter-N-log.json`。用于调试（定位哪个阶段耗时异常）、质量回顾（门控决策 + 修订次数统计）。`/novel:dashboard` 可读取汇总展示。
>
> **降级说明**：Claude Code Task 工具不暴露 token 用量和成本。`input_tokens`、`output_tokens`、`total_cost_usd` 字段当无法获取时写入 `null`。`model` 和 `duration_ms`（通过计时差值计算）始终可用。未来若 Claude Code 开放 token 用量 API，可无缝填充这些字段。
