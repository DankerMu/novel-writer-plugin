# M3 周期性维护

## AI 黑名单动态维护（不阻断）

- 从 eval_used.anti_ai.blacklist_update_suggestions[] 读取新增候选（必须包含：phrase + count_in_chapter + examples）
- 增长上限检查：若 `words[]` 长度 >= 80，跳过自动追加，仅记录到 `update_log[]`（source="auto_skipped_cap"），并在 `/novel:start` 质量回顾中提示用户审核黑名单规模
- 自动追加门槛（保守，避免误伤）：
  - `confidence in {medium, high}` 且 `count_in_chapter >= 3` -> 才允许自动追加
  - 其余仅记录为"候选建议"，不自动写入（可在 `/novel:start` 质量回顾中提示用户手动处理）
  - 注意：当前门槛为单章统计；跨章高频但单章 < 3 的词不会自动追加，依赖用户在质量回顾中审核候选列表
- 更新 `ai-blacklist.json`（按文件协议；幂等、可追溯）：
  - 确保存在 `whitelist[]` 与 `update_log[]`（不存在则创建为空）
  - added：追加到 `words[]`（去重；若已存在于 words/whitelist 则跳过）
  - exempted（误伤保护，自动豁免，不作为命中/不替换）：
    - 若候选短语命中 `style-profile.json.preferred_expressions[]`（样本高频表达）或用户显式 `ai-blacklist.json.whitelist[]`：
      - 将其加入 whitelist（若未存在）
      - 记录为 exempted，并且**不得加入** words
  - 更新 `last_updated`（YYYY-MM-DD）与 `version`（若存在且为合法 semver 则 patch bump；字段缺失或不可解析时仅更新 `last_updated`，不创建 `version`）
  - 追加 `update_log[]`（append-only）：记录 timestamp/chapter/source="auto"/added/exempted + evidence（例句）
- 用户可控入口：
  - 用户可手动编辑 `ai-blacklist.json` 的 `words[]/whitelist[]`
  - 若用户删除某词但不希望未来被自动再加回，请将其加入 `whitelist[]`（系统不得自动加入 whitelist 内词条）

## 风格漂移检测与纠偏（每 5 章触发）

- 触发条件：last_completed_chapter % 5 == 0
- 窗口：读取最近 5 章 `chapters/chapter-{C-4..C}.md`
- 调用 WorldBuilder（风格漂移检测模式）提取当前 metrics（仅需 avg_sentence_length / dialogue_ratio；其余字段可忽略）
- 与 `style-profile.json` 基线对比（相对偏移，确定性公式）：
  - 前置检查：若 `base.avg_sentence_length` 为 null/0 或 `base.dialogue_ratio` 为 null/0，跳过对应维度的漂移检测（记录日志 "baseline metric unavailable, skipping drift check"）
  - `sentence_dev = abs(curr.avg_sentence_length - base.avg_sentence_length) / base.avg_sentence_length`
  - `dialogue_dev = abs(curr.dialogue_ratio - base.dialogue_ratio) / base.dialogue_ratio`
- 漂移判定：
  - `sentence_dev > 0.20` 或 `dialogue_dev > 0.15` -> drift=true
  - 回归判定：`sentence_dev < 0.10` 且 `dialogue_dev < 0.10` -> recovered=true
- drift=true：
  - 写入/更新 `style-drift.json`（按文件协议；active=true）
  - drifts[].directive 生成规则（最多 3 条，短句可执行）：
    - 句长偏长：强调短句/动作推进/拆句
    - 句长偏短：允许适度长句与节奏变化（但仍以 style-profile 为准）
    - 对话偏少：强调通过对话推进（交给 ChapterWriter；Phase 2 不得硬造新对白）
    - 对话偏多：加强叙述性承接与内心活动（不删对白，仅调整段落与叙述衔接）
- recovered=true：
  - 清除纠偏：删除 `style-drift.json` 或标记 `active=false`，并写入 `cleared_at/cleared_reason="metrics_recovered"`
- 超时清除：若当前章 - `style-drift.json.detected_chapter` > 15（即纠偏指令已注入超过 15 章仍未回归），自动标记 `active=false`，`cleared_reason="stale_timeout"`
- 其余情况：保持现状（不新增、不清除），避免频繁抖动
