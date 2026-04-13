# M3 周期性维护

## AI 黑名单动态维护（不阻断）

- 若 `eval_used.anti_ai.blacklist_update_suggestions[]` 存在且非空，读取新增候选（必须包含：phrase + count_in_chapter + examples）；若字段缺失或为 null，跳过本章黑名单维护（不报错）
- 增长上限检查：若 `words[]` 长度 >= 120，跳过自动追加，仅记录到 `update_log[]`（source="auto_skipped_cap"），并在 `/novel:start` 质量回顾中提示用户审核黑名单规模
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
  - `sentence_dev > 0.20` -> drift=true（句长为硬指标）
  - `dialogue_dev > 0.15` -> 仅记录 `dialogue_drift_note`（对话比例因章节类型自然浮动，不触发漂移警告；叙事章可低至 ~15%，互动密集章可达 ~50%）
  - 回归判定：`sentence_dev < 0.10` -> recovered=true（仅基于句长判定回归）
- drift=true：
  - 写入/更新 `style-drift.json`（按文件协议；active=true）
  - drifts[].directive 生成规则（最多 2 条，短句可执行）：
    - 句长偏长：强调短句/动作推进/拆句
    - 句长偏短：允许适度长句与节奏变化（但仍以 style-profile 为准）
    - 注：对话比例不参与漂移触发，其偏移仅记录为 `dialogue_drift_note`（供人工参考）
- recovered=true：
  - 清除纠偏：删除 `style-drift.json` 或标记 `active=false`，并写入 `cleared_at/cleared_reason="metrics_recovered"`
- 超时清除：若当前章 - `style-drift.json.detected_chapter` > 15（即纠偏指令已注入超过 15 章仍未回归），自动标记 `active=false`，`cleared_reason="stale_timeout"`
- 其余情况：保持现状（不新增、不清除），避免频繁抖动

## 人性化技法跨章追踪（每 5 章触发）

- 触发条件：与风格漂移检测同步（last_completed_chapter % 5 == 0）
- 读取近 5 章 eval JSON 的 `eval_used.anti_ai.detected_humanize_techniques[]`
- 前置检查：若窗口内 ≥ 3 章 eval 缺失 `eval_used.anti_ai.detected_humanize_techniques` 字段（null 或不存在），跳过本周期 humanize_drought 判定（记录日志 "humanize data unavailable for majority of window, skipping"）
- 统计 5 章内 unique technique tag 数量
- 判定：
  - unique == 0（连续 5 章零技法）→ 输出 risk_flag `humanize_drought` WARNING
  - unique > 0 → 正常，不做干预
- humanize_drought 处理：
  - 写入 `style-drift.json`：追加 `drifts[]` 条目 `{"type": "humanize_drought", "detected_chapter": C, "directive": "近 5 章未使用任何人性化技法（style-guide §2.9），在合适场景中自然融入"}`，设 `active=true`（如已有 drift 条目则保持，仅追加 drought 条目）
  - 编排器 Step 2.6 组装 manifest 时，已从 `style-drift.json` 读取 `style_drift_directives`（SKILL.md:225），drought directive 自然被注入下章
  - 仅注入一次：下个 5 章周期重新评估——若 drought 解除（unique > 0），从 `style-drift.json.drifts[]` 移除 `type=="humanize_drought"` 的条目（若 drifts 为空则 `active=false`）
- 注意：不设最低配额——humanize_drought 仅为温和提醒，不阻断流水线
