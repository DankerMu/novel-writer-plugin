# M10 Codex 化评估管线

## Status: Proposed

## Summary

将 Summarizer / QualityJudge / ContentCritic / 滑窗一致性校验从 Claude Code Task(opus) 迁移至 Codex CLI（通过 `codeagent-wrapper --backend codex` 调用）。性能更强、成本更低。写作环节（API Writer / CW / SR）不动。

## Design Principles

- **确定性**：Codex 只读 manifest 指定的文件（通过 @file 引用），不自主探索
- **不降级混用**：`eval_backend` 全局二选一（codex / opus），不在运行时切换
- **滑窗拆分**：Codex 纯分析出报告，编排器根据报告执行 Edit 修复
- **codeagent-wrapper 是唯一调用入口**：不直接调 Codex CLI

## Architecture

```
eval_backend = "codex":

  Step A: codex-eval.py 组装 task content（manifest → @file 引用 + inline 值）
  Step B: codeagent-wrapper --backend codex 执行（Bash HEREDOC / stdin）
  Step C: codex-eval.py --validate 校验输出 JSON
  Step D: 编排器写入 staging/

  单章管线:
    [A→B→C→D](summarizer) → [A + parallel B](QJ+CC via --parallel) → [C→D] 各自校验
  
  滑窗校验:
    [A→B→C](sliding-window) → 编排器 Edit 修复 auto_fixable issues

eval_backend = "opus" (default):
  现有 Task(opus) 路径不变
```

## Invocation Pattern

```bash
# 单任务
codeagent-wrapper --backend codex - <project_root> < staging/prompts/chapter-048-summarizer.md

# QJ + CC 并行
codeagent-wrapper --parallel --backend codex <<'EOF'
---TASK---
id: qj
workdir: <project_root>
---CONTENT---
$(cat staging/prompts/chapter-048-quality-judge.md)
---TASK---
id: cc
workdir: <project_root>
---CONTENT---
$(cat staging/prompts/chapter-048-content-critic.md)
EOF
```

## Key Files

- `openspec/changes/m10-codex-eval-pipeline/proposal.md` — 完整提案
- `scripts/codex-eval.py` — manifest→task content 组装 + 输出 schema 校验（待实现）
- `prompts/codex-summarizer.md` — Codex Summarizer prompt（待实现）
- `prompts/codex-quality-judge.md` — Codex QJ prompt（待实现）
- `prompts/codex-content-critic.md` — Codex CC prompt（待实现）
- `prompts/codex-sliding-window.md` — Codex 滑窗分析 prompt（待实现）
