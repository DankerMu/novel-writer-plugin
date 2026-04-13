# Codex 评估管线故障排查 Runbook

## 常见故障

### 1. codeagent-wrapper 超时

**症状**：Bash 调用 codeagent-wrapper 超过 CODEX_TIMEOUT 被 kill

**排查**：
- 检查 `CODEX_TIMEOUT` 设置（默认 3600s，滑窗 7200s）
- 查看 codeagent-wrapper 日志（SESSION_ID 记录在 `logs/chapter-{C:03d}-log.json`）
- 确认 Codex CLI 本地已安装且可用

**处理**：
- 增大 `CODEX_TIMEOUT`（`export CODEX_TIMEOUT=7200`）
- 编排器自动重试一次（Step 1.6）
- 重试仍失败 → `orchestrator_state = "ERROR_RETRY"`，暂停等用户决策
- **不得 kill 正在运行的 codeagent-wrapper 进程**（浪费 API 成本且丢失进度）

### 2. codex-eval.py --validate 校验失败

**症状**：`[codex-eval] FAIL: missing: xxx` 或 `[codex-eval] FAIL: xxx out of range`

**排查**：
- 检查 staging 目录下对应文件是否存在
- 检查 JSON 格式是否正确（`python3 -m json.tool staging/evaluations/chapter-XXX-eval-raw.json`）
- 对照 Codex prompt（`prompts/codex-{agent}.md`）的 Format 段落确认输出结构

**处理**：
- 校验失败 → 编排器从 codeagent-wrapper 重跑（task content 文件已在磁盘）
- 反复失败 → 检查 Codex prompt 是否完整迁移了输出格式要求
- 若 Codex 输出结构一致性低 → 建议切回 `eval_backend: "opus"` 并调整 prompt

### 3. eval_backend 切换

**从 opus 切到 codex**：
1. 先运行校准：`bash scripts/run-codex-calibration.sh --project <dir> --labels <labels.jsonl> --out eval/calibration/codex-calibration-report.json`
2. 确认校准通过（`threshold_decision.decision == "keep"`）
3. 修改 `.checkpoint.json`：`"eval_backend": "codex"`
4. 建议跑 5 章验证流水线无阻断

**从 codex 切回 opus**：
1. 修改 `.checkpoint.json`：`"eval_backend": "opus"` 或删除该字段
2. 清空 `staging/prompts/` 下的 Codex task content 文件（可选）
3. 下次续写即走 opus 路径

### 4. Summarizer Codex 输出缺失字段

**症状**：`codex-eval.py --validate --schema summarizer` 报 `missing: delta: canon_hints`

**排查**：
- 检查 `prompts/codex-summarizer.md` 中 Format 段落是否明确要求 `canon_hints` 为必须输出字段
- 检查 task content（`staging/prompts/chapter-XXX-summarizer.md`）是否包含伏笔任务数据

**处理**：
- 校验失败自动重试
- 反复缺失 → 在 Codex prompt 中加强 `canon_hints` 输出要求的措辞

### 5. QJ + CC 并行执行冲突

**症状**：两个 codeagent-wrapper 进程同时写入 staging/ 导致文件损坏

**排查**：
- QJ 写入 `staging/evaluations/chapter-{C:03d}-eval-raw.json`
- CC 写入 `staging/evaluations/chapter-{C:03d}-content-eval-raw.json`
- 路径不同，正常不应冲突

**处理**：
- 确认 Codex prompt 中输出路径指令正确
- 若发现路径冲突 → 检查 codex-eval.py 生成的 task content 输出路径段落

## eval_backend 缺失兼容性

- checkpoint 无 `eval_backend` 字段 → 等同 `"opus"`
- 旧 checkpoint 不受影响，现有流程完全不变
- 新项目通过 `/novel:start` Quick Start 默认写入 `eval_backend: "codex"`
