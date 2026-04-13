# Checkpoint 恢复

> **权威来源**：`skills/continue/references/checkpoint-recovery.md`（含最新 pipeline_stage 枚举 + 定向修订并行恢复 + direct_fixing 阶段）。本 runbook 为简化版操作指南，不覆盖全部恢复分支。

## Trigger

`/novel:continue` 启动时检测到以下任一情况：

- `pipeline_stage` 不为 `committed` 且不为 `null`（流水线中断）
- `.checkpoint.json` 文件缺失、JSON 解析失败、或关键字段异常
- `schema_version` 缺失或 < 2（旧版 checkpoint）

## Diagnosis

### 检查 checkpoint 字段

读取 `.checkpoint.json`，验证以下字段：

| 字段 | 预期 | 异常处理 |
|------|------|---------|
| `schema_version` | `2` | 缺失/< 2 → WARNING，不阻断，首次 commit 时补写 |
| `orchestrator_state` | `WRITING` / `CHAPTER_REWRITE` | 其他值 → 提示用户先执行 `/novel:start` |
| `current_volume` | 正整数 | 缺失 → 从 `volumes/` 目录推断 |
| `last_completed_chapter` | 非负整数 | 缺失 → 从 `chapters/` 最大章节号推断 |
| `pipeline_stage` | 枚举值（见下方） | 非法值 → 视为 `drafting` 重启 |
| `inflight_chapter` | 章节号或 `null` | `pipeline_stage != committed` 但 `inflight_chapter == null` → 异常，从 staging 推断 |
| `revision_count` | 非负整数 | 缺失 → 默认 0 |

### 检查 staging 目录与锁文件

- `staging/chapters/chapter-{C:03d}.md` 存在 → CW 已完成；`staging/summaries/` 存在 → Sum 已完成；`staging/evaluations/` 存在且可解析 → QJ 已完成
- `.novel.lock/info.json` 存在且 `started` > 30 分钟 → 僵尸锁，清除后重试

## Actions

### 按 pipeline_stage 恢复

**`null` / `committed`**：正常状态，从 `last_completed_chapter + 1` 开始新章。

**`drafting`**：
- staging 章节文件不存在 → 从 ChapterWriter 重启整章
- staging 章节文件存在但摘要不存在 → 从 Summarizer 恢复
- 两者均存在 → 视为 `drafted`，从 QualityJudge 恢复

**`drafted`**（含向后兼容的 `refined`）：
- 跳过 CW + Summarizer，直接调用 QualityJudge 评估

**`judged`**：
- 读取 `staging/evaluations/chapter-{C:03d}-eval-raw.json`
- 文件存在且合法 → 直接执行门控决策 + commit
- 文件不存在或 JSON 无效 → 降级到 `drafted`，重新调用 QJ

**`revising`**：
- 保留 `revision_count`（防止无限循环）
- 从 ChapterWriter 修订重启 → Summarizer → QualityJudge 完整重跑

### Checkpoint 损坏重建

当 `.checkpoint.json` 缺失或解析失败时：扫描 `chapters/` 确定 `last_completed_chapter`，扫描 `volumes/` 确定 `current_volume`，检查 `staging/` 残留决定 `pipeline_stage`。重建最小字段集：`schema_version: 2`, `orchestrator_state: "WRITING"`, `pipeline_stage: "committed"`, `inflight_chapter: null`, `revision_count: 0`, `eval_backend: "codex"`（若项目之前使用 Codex 后端；不确定时设为 `"opus"` 最安全）。

## Acceptance

- 恢复章完成完整流水线（CW → Sum → QJ → 门控 → commit）
- `pipeline_stage` 回到 `committed`，`inflight_chapter` 清为 `null`
- `revision_count` 重置为 0
- 恢复章计入 N 章配额（`remaining_N = N - 1`）

## Rollback

- **重建后状态不一致**：若推断的 `last_completed_chapter` 与实际 `chapters/` / `summaries/` / `evaluations/` 文件不匹配，输出差异报告并暂停，等待用户确认
- **staging 残留无法匹配**：清空 `staging/` 全部文件，以 `committed` 状态从 `last_completed_chapter + 1` 全新开始
- **最小手动重建**：用户可手动创建 `.checkpoint.json`，填写上述最小字段集后执行 `/novel:continue 1` 验证
