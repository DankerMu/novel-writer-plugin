## 8. Orchestrator 设计

### 8.1 核心原则：无状态冷启动

Orchestrator 不依赖会话历史。每次启动（新 session 或 context 压缩后）：
1. 读 `.checkpoint.json` → 当前位置（Vol N, Chapter M, 状态 X）
2. 读 `state/current-state.json` → 世界/角色/伏笔当前状态
3. 读近 3 章 `summaries/` → 近期剧情
4. 读 `volumes/vol-N/outline.md` → 当前卷计划
5. 无需读任何章节全文

### 8.2 状态机

```
INIT → QUICK_START → VOL_PLANNING → WRITING ⟲ (每章：写→摘要→润色→门控→[修订])
                                      ↓ (卷末)
                                  VOL_REVIEW → VOL_PLANNING (下一卷)
```

**状态转移规则**：

| 当前状态 | 触发条件 | 目标状态 | 动作 |
|---------|---------|---------|------|
| INIT | `/novel:start create` | QUICK_START | 创建项目目录 |
| QUICK_START | 用户提供设定 | QUICK_START | WorldBuilder(轻量) + CharacterWeaver(主角) |
| QUICK_START | 风格样本提交 | QUICK_START | StyleAnalyzer 提取 profile |
| QUICK_START | 试写确认 | VOL_PLANNING | 标记试写为 Vol 1 前 3 章 |
| VOL_PLANNING | 大纲确认 | WRITING | 保存大纲，准备续写 |
| WRITING | 续写请求 | WRITING | ChapterWriter → Summarizer → StyleRefiner → QualityJudge → 门控 |
| WRITING | 门控通过（≥ 4.0 且无 violation） | WRITING | 提交章节，更新 checkpoint |
| WRITING | 门控润色（3.5-3.9 且无 violation） | WRITING | StyleRefiner 二次润色后提交 |
| WRITING | 门控修订（3.0-3.4 或有 high-confidence violation） | CHAPTER_REWRITE | ChapterWriter(Opus) 修订（最多 2 次） |
| WRITING | 门控失败（2.0-2.9） | WRITING(暂停) | 通知用户，人工审核决定重写范围 |
| WRITING | 门控失败（< 2.0） | WRITING(暂停) | 强制全章重写 |
| WRITING | 每 5 章（last_completed % 5 == 0） | WRITING | 输出质量简报（均分+问题章节），用户可选择继续/回看/调整 |
| CHAPTER_REWRITE | 修订完成 | WRITING | 重新走门控（最多 2 次修订；仍 ≥ 3.0 则强制通过并标记 `force_passed`；仍 < 3.0 则通知用户暂停） |
| WRITING | 本卷最后一章 | VOL_REVIEW | 全卷检查 |
| VOL_REVIEW | 完成 | VOL_PLANNING | 下卷规划 |
| 任意 | 错误 | ERROR_RETRY | 重试 1 次，失败则保存 checkpoint 暂停 |

**Skill → 状态映射**：

| Skill | 负责状态 | 说明 |
|-------|---------|------|
| `/novel:start` | INIT → QUICK_START, VOL_PLANNING, VOL_REVIEW | 状态感知交互入口：通过 AskUserQuestion 识别用户意图后派发对应 agent |
| `/novel:continue` | WRITING（含内嵌门控 + 修订循环） | 核心续写循环：每章流水线含 QualityJudge 门控，不通过则自动修订（高频快捷命令） |
| `/novel:dashboard` | 任意（只读） | 读取 checkpoint 展示状态，不触发转移 |

### 8.3 Context 组装规则

```python
def assemble_context(agent_type, chapter_num, volume):
    base = {
        "project_brief": read("brief.md"),
        "style_profile": read("style-profile.json"),
        "ai_blacklist": read("ai-blacklist.json"),
    }

    if agent_type == "ChapterWriter":
        return base | {
            "volume_outline": read(f"volumes/vol-{volume:02d}/outline.md"),
            "chapter_outline": extract_chapter(volume, chapter_num),
            "storyline_context": get_storyline_context(chapter_num, volume),
            "concurrent_state": get_concurrent_storyline_states(chapter_num, volume),
            "recent_summaries": read_last_n("summaries/", n=3),
            "current_state": read("state/current-state.json"),
            "foreshadowing_tasks": get_chapter_foreshadowing(chapter_num),
        }

    elif agent_type == "QualityJudge":
        return base | {
            "chapter_content": read(f"chapters/chapter-{chapter_num:03d}.md"),
            "chapter_outline": extract_chapter(volume, chapter_num),
            "character_profiles": read("characters/active/*.md"),
            "prev_summary": read_last_n("summaries/", n=1),
            "storyline_spec": read("storylines/storyline-spec.json"),
            "storyline_schedule": read(f"volumes/vol-{volume:02d}/storyline-schedule.json"),
        }

    elif agent_type == "PlotArchitect":
        return base | {
            "world_docs": read("world/*.md"),
            "characters": read("characters/active/*.md"),
            "prev_volume_review": read(f"volumes/vol-{volume-1:02d}/review.md"),
            "global_foreshadowing": read("foreshadowing/global.json"),
            "storylines": read("storylines/storylines.json"),
        }
    # WorldBuilder/CharacterWeaver: base + existing docs + update request
```

### 8.4 Context 用量参考（按 Agent 分列，非硬上限）

> 以下为成本估算参考，不作为性能约束。各 Agent 应加载完成任务所需的全部 context，模型 context window（200K）远大于实际用量。

**ChapterWriter**（最重，含完整创作上下文）

| 组件 | Token 估算 | 说明 |
|------|-----------|------|
| Agent prompt | ~2K | 固定 |
| style-profile + ai-blacklist top10 | ~1.5K | 固定 |
| 卷大纲 + 本章大纲 | ~3.5K | 每章提取对应区块 |
| 故事线 context（memory + concurrent_state + 相邻线 memory） | ~2.5K | 交汇章更多 |
| 近 3 章摘要 | ~1.5K | 滑动窗口 |
| current-state.json | ~3-5K | 全量活跃状态 |
| 伏笔任务 | ~0.5K | 本章相关条目 |
| L1 世界规则 + L3 章节契约 | ~1K | 如存在 |
| L2 角色契约 + 角色档案 | ~3-6K | 交汇事件可达 15+ 角色 |
| **合计** | **~19-24K**（普通章） / **~24-30K**（交汇章） | |

**Summarizer**

| 组件 | Token 估算 | 说明 |
|------|-----------|------|
| Agent prompt | ~1.5K | 固定 |
| 章节全文 | ~4.5K | ~3000 字 |
| current-state.json | ~3-5K | 用于提取状态增量 |
| 伏笔任务 + entity_id_map | ~1K | |
| Writer hints（可选） | ~0.3K | |
| **合计** | **~10-12K** | |

**StyleRefiner**（最轻）

| 组件 | Token 估算 | 说明 |
|------|-----------|------|
| Agent prompt | ~1.5K | 固定 |
| 章节全文（初稿） | ~4.5K | |
| style-profile + ai-blacklist（完整） | ~2K | |
| **合计** | **~8K** | |

**QualityJudge**

| 组件 | Token 估算 | 说明 |
|------|-----------|------|
| Agent prompt | ~2K | 固定 |
| 章节全文（润色后） | ~4.5K | |
| 本章大纲 + 章节契约 + 世界规则 | ~1.5K | |
| 角色档案 + 契约 | ~3-5K | |
| style-profile + 前章摘要 | ~1.5K | |
| 故事线 spec + schedule + cross_references | ~1.5K | |
| **合计** | **~14-16K** | |

### 8.5 State 裁剪策略

**Context 裁剪**（每章执行，控制 prompt 大小）：
- 角色档案：有章节契约时加载契约指定角色（无硬上限，交汇事件可超 10 个）；无契约时加载全部活跃角色（上限 15，按最近出场排序截断）
- current-state.json：保留全部活跃角色状态（依赖 L2 裁剪控制注入量，不做数据删除）

**数据归档**（显式触发，不自动执行）：
- 角色退场 **仅由 CharacterWeaver 退场模式显式执行**，不按"N 章未出现"自动触发
- **归档保护**：以下角色不可退场——被活跃伏笔（scope 为 medium/long）引用的角色、被任意故事线（含休眠线）关联的角色、出现在未来 storyline-schedule 交汇事件中的角色
- 退场后：角色文件移至 `characters/retired/`，从 current-state.json 移除对应条目，更新 relationships.json

**定期清理**（每卷结束时）：
- 清理 current-state.json 中已退场角色的残留条目
- 清理过期物品/位置状态（无活跃伏笔或故事线引用的临时条目）
- 生成清理报告供用户确认
