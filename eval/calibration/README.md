# Codex Calibration Reports

本目录存放 Codex 评估管线校准报告。

## 文件命名

`codex-calibration-report.json` — 最新校准报告（由 `run-codex-calibration.sh` 生成）

## 报告 Schema

- `schema_version: 1`
- 包含 Codex vs Human / Codex vs Opus / CC Track / Summarizer ops 四维对比
- `threshold_decision` 字段给出阈值建议（keep/adjust/review）

## 使用

```bash
bash scripts/run-codex-calibration.sh \
  --project /path/to/novel \
  --labels eval/datasets/m2-30ch/v1/labels-YYYY-MM-DD.jsonl \
  --out eval/calibration/codex-calibration-report.json
```

详见 `docs/runbooks/codex-calibration.md`
