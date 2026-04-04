# 滑窗校验修复

## Trigger

`check-sliding-window.sh` 注册在两个 hook 事件上，构成**触发 + 门控**双阶段机制：

- **PostToolUse（触发）**：监听 Write/Edit 到 `.checkpoint.json`。当 `pipeline_stage == "committed"` 且 `last_completed_chapter >= 10` 且 `% 5 == 0` 时，创建 `logs/.sliding-window-pending` 标记，通过 `additionalContext` 注入校验指令
- **PreToolUse（门控）**：标记存在期间，阻断 `staging/` 写入和 Bash mv/cp 章节 commit 操作，直到校验完成（`logs/continuity/latest.json` 比标记更新）

窗口范围：`[max(1, ch-9), ch]`，形成 ch1-10, ch6-15, ch11-20... 的重叠滑窗。

## Diagnosis

### 数据读取策略

- **读原文**（非摘要）：`chapters/chapter-{C:03d}.md`（窗口内全部章节）
- **读契约**：`volumes/vol-{V:02d}/chapter-contracts/chapter-{C:03d}.md`
- **读大纲**：`volumes/vol-{V:02d}/outline.md` 中 `### 第 N 章` 区块
- **读伏笔**：`foreshadowing/global.json` 查状态与 `target_resolve_range`
- **可选辅助**：`scripts/run-ner.sh` 执行 NER 实体抽取（脚本优先，LLM fallback）

### 校验维度

1. **正文↔契约/大纲对齐**：事件完整性、冲突落地、局势变化状态、验收标准、Storyline/POV/Location 匹配、Foreshadowing 动作体现
2. **时间线一致性（LS-001）**：跨章事件时间序列、并发故事线时间矛盾
3. **角色位置/状态一致性**：角色在前章末尾与后章开头的位置、状态是否连续
4. **伏笔追踪**：planted 伏笔是否在后续章节 advanced/resolved，状态推进是否与 `global.json` 一致
5. **NER 实体一致性**：人名/地名/组织名跨章是否出现别名冲突或拼写不一致

## Actions

### 时间线矛盾

- 定位冲突章节，对比前后事件时间标记
- 可修复（时间描述用词冲突）：直接编辑正文中的时间表述
- 不可修复（因果链矛盾需调整剧情）：列出并提示用户

### 角色错位

- 检查角色末态（前章结尾位置/状态）与初态（后章开头）是否一致
- 可修复（位置/状态描述缺失或矛盾）：补充或修正过渡描写
- 不可修复（角色行为逻辑矛盾）：列出并提示用户

### 伏笔遗漏

- 对比 `global.json` 中 `target_resolve_range` 覆盖窗口的条目
- 缺失推进（planted 但窗口内无 advanced）：在合适章节补充暗示段落
- 状态不一致（正文已回收但 `global.json` 仍为 planted）：更新 `global.json`

### 正文偏离契约/大纲

- 核心事件缺失：补充或扩展相关段落
- 验收标准未满足：针对性修改正文

## Acceptance

1. 修复后由 agent 复核修复结果，确认无遗漏
2. 报告落盘：`logs/continuity/continuity-report-vol-{V:02d}-ch{start:03d}-ch{end:03d}.json`
3. 覆盖写入 `logs/continuity/latest.json`（hook 以 `latest.json` 时间戳判定校验完成）
4. `logs/.sliding-window-pending` 标记被 PreToolUse hook 自动清除
5. 章节号写入 `logs/.sliding-window-last-checked` 防止重复触发

## Rollback

- **自动修复失败**：输出未修复问题清单（severity + 章节号 + 具体描述），提示用户手动处理
- **阻断性问题**：若存在 LS-001 high-confidence 时间线矛盾且无法自动修复，暂停流水线并建议用户审查契约/大纲
- **hook 卡死**：若 `logs/.sliding-window-pending` 存在但校验无法推进，手动删除标记 + 写入空 `latest.json` 可解除阻断（应同时记录跳过原因到日志）
