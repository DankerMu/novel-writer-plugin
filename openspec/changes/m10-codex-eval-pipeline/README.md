# M10 Codex 化评估管线

## Status: Proposed

## Summary

将 Summarizer / QualityJudge / ContentCritic / 滑窗一致性校验从 Claude Code Task(opus) 迁移至 Codex CLI（通过 `codeagent-wrapper --backend codex` 调用）。性能更强、成本更低。写作环节（API Writer / CW / SR）不动。

## Design Principles

- **确定性**：Codex 只读 manifest 指定的文件（通过 @file 引用，由 codeagent-wrapper 解析），不自主探索
- **不降级混用**：`eval_backend` 全局二选一（codex / opus），不在运行时切换
- **滑窗拆分**：Codex 纯分析出报告，编排器根据报告执行 Edit 修复
- **codeagent-wrapper 是唯一调用入口**：不直接调 Codex CLI
- **lint 前置**：QJ 依赖的 lint 脚本（meta-leak/terminology/format）提升到编排器预执行，结果注入 manifest
- **Summarizer combined JSON**：Codex 输出单一 JSON，codex-eval.py --split 拆分写入 7 个 staging 文件

## Architecture

```
eval_backend = "codex":

  Step A: codex-eval.py --agent 组装 task content（manifest → @file 引用 + inline 值）
  Step B: codeagent-wrapper --backend codex - <root> < task-content.md
  Step C: codex-eval.py --validate / --split 校验输出（Summarizer 额外拆分多文件）
  Step D: 编排器写入 staging/

  单章管线:
    lint 预处理 → [A→B→C→D](summarizer) → [A+A 并行](QJ+CC prompt) → [B+B 并行](两个独立 codeagent-wrapper) → [C→D] 各自校验
  
  滑窗校验:
    [A→B→C](sliding-window) → 编排器 Edit 修复 auto_fixable issues

eval_backend = "opus" (default):
  现有 Task(opus) 路径不变
```

## Invocation Pattern

```bash
# 单任务（stdin 管道）
codeagent-wrapper --backend codex - <project_root> < staging/prompts/chapter-048-summarizer.md

# QJ + CC 并行：两个独立调用（不使用 --parallel，避免 HEREDOC/输出解析问题）
# tool call 1
codeagent-wrapper --backend codex - <root> < staging/prompts/chapter-048-quality-judge.md
# tool call 2（并行）
codeagent-wrapper --backend codex - <root> < staging/prompts/chapter-048-content-critic.md
```

## Key Files

- `openspec/changes/m10-codex-eval-pipeline/proposal.md` — 完整提案
- `scripts/codex-eval.py` — 三模式：--agent 组装 / --validate 校验 / --split 拆分（待实现）
- `prompts/codex-summarizer.md` — Codex Summarizer prompt（待实现）
- `prompts/codex-quality-judge.md` — Codex QJ prompt（待实现）
- `prompts/codex-content-critic.md` — Codex CC prompt（待实现）
- `prompts/codex-sliding-window.md` — Codex 滑窗分析 prompt（待实现）
