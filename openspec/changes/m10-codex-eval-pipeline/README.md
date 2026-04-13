# M10 Codex 化评估管线

## Status: Proposed

## Summary

将 Summarizer / QualityJudge / ContentCritic / 滑窗一致性校验从 Claude Code Task(opus) 迁移至 Codex CLI。性能更强、成本更低。写作环节（API Writer / CW / SR）不动。

## Design Principles

- **确定性**：Codex 只读 manifest 指定的文件，不自主探索，保证同输入同结果
- **不降级混用**：`eval_backend` 全局二选一（codex / opus），不在运行时切换，避免分数分布不兼容
- **滑窗拆分**：Codex 纯分析出报告，编排器根据报告执行 Edit 修复（Codex 不写非 staging 文件）

## Architecture

```
eval_backend = "codex":
  Step A: Bash(codex-eval.py --agent X)           → 组装 prompt 文件
  Step B: Skill("codeagent", args="--backend codex @prompt")  → Codex 执行
  Step C: codex-eval.py --validate                → schema 校验
  Step D: Write → staging/                        → 写入输出

  单章管线:
    [A→B→C→D](summarizer) → [A→B→C→D](QJ) + [A→B→C→D](CC) 并行
  滑窗校验:
    [A→B→C→D](sliding-window) → 编排器 Edit 修复 auto_fixable issues

eval_backend = "opus" (default):
  现有 Task(opus) 路径不变
```

## Key Files

- `openspec/changes/m10-codex-eval-pipeline/proposal.md` — 完整提案
- `scripts/codex-eval.py` — Codex 调度 + prompt 组装 + schema 校验（待实现）
- `prompts/codex-summarizer.md` — Codex Summarizer prompt（待实现）
- `prompts/codex-quality-judge.md` — Codex QJ prompt（待实现）
- `prompts/codex-content-critic.md` — Codex CC prompt（待实现）
- `prompts/codex-sliding-window.md` — Codex 滑窗分析 prompt（待实现）
