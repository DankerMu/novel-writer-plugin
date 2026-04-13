# Codex 评估管线校准 Runbook

## 前提条件

- 项目有 >= 30 章已提交章节（`chapters/chapter-{C:03d}.md`）
- 人工标注数据集（`eval/datasets/`）
- codeagent-wrapper CLI 已安装
- `.checkpoint.json` 存在

## 校准流程

### Step 1: 准备 Manifests

确保每章有 `staging/manifests/chapter-{C:03d}-manifest.json`。
如果不存在，通过 `/novel:continue` 的 Step 2 context assembly 生成。

### Step 2: 运行批量评估

```bash
bash scripts/run-codex-calibration.sh \
  --project /path/to/novel \
  --labels eval/datasets/m2-30ch/v1/labels-YYYY-MM-DD.jsonl \
  --out eval/calibration/codex-calibration-report.json
```

可选：`--chapters 1,2,3` 只跑指定章节（调试用）。

### Step 3: 阅读校准报告

关键指标：
- `codex_vs_human.overall.pearson_r` — 目标 >= 0.85
- `codex_vs_human.overall.bias` — 目标绝对值 < 0.3
- `threshold_decision.decision` — keep/adjust/review

### Step 4: 阈值决策

| 条件 | 动作 |
|------|------|
| r >= 0.85 且 \|bias\| < 0.3 | 门控阈值不变，可切换到 codex |
| r >= 0.85 且 \|bias\| >= 0.3 | 调整阈值（见报告 suggested_thresholds）或调整 prompt |
| r < 0.85 | 回退分析：检查低相关维度，调整对应 Codex prompt 后重跑 |

### Step 5: Summarizer 验证

校准报告中 `summarizer_ops.canon_hints_coverage` < 0.8 表示 Codex Summarizer 可能遗漏关键状态提取。建议人工抽检 5 章：
- 对比 `staging/state/chapter-{C:03d}-delta.json` (Codex) 与 `state/changelog.jsonl` 对应章节 ops
- 重点关注：canon_hints 覆盖率、crossref leak_risk 判定

### Step 6: 切换或回退

- 校准通过 -> 更新 `.checkpoint.json` 中 `eval_backend: "codex"`
- 校准不通过 -> 保持 `eval_backend: "opus"`，调整 Codex prompt 后重跑

## 常见问题

- **codeagent-wrapper 超时**：增大 CODEX_TIMEOUT 环境变量（默认 3600s）
- **schema 校验失败**：检查 Codex prompt 是否正确引导输出格式
- **低相关维度**：对照 Codex prompt 与 agent spec，检查该维度的评估逻辑是否完整迁移
- **CC 维度 n=0**：人工标注数据集 v1 可能没有 CC 专属维度分数，升级标注模板后重跑
