# M10 Codex 化评估管线

## Status: Proposed

## Summary

将 Summarizer / QualityJudge / ContentCritic / 滑窗一致性校验从 Claude Code Task(opus) 迁移至 Codex CLI（通过 `codeagent-wrapper --backend codex` 调用）。Codex 是与 Claude Code 同级的本地 agent，有文件读写和 Bash 执行能力——行为与现有 Opus agent 完全同构，只是换了执行器。

## Design Principles

- **行为同构**：Codex 自己读文件、跑 lint 脚本、写 staging/，与 Opus agent 用 Read/Write/Bash 工具的行为一致
- **确定性**：task content 显式指定文件路径，Codex 按指令读取
- **不降级混用**：`eval_backend` 全局二选一（codex / opus），不在运行时切换
- **滑窗拆分**：Codex 分析出报告 JSON，编排器 Edit 修复（非 staging 写入走 Claude Code 审计）
- **codeagent-wrapper 是唯一调用入口**

## Architecture

```
eval_backend = "codex":

  Step A: codex-eval.py --agent     manifest → task content 文件
  Step B: codeagent-wrapper         Codex 读文件 + 跑 lint + 写 staging/
  Step C: codex-eval.py --validate  验证 staging/ 输出文件存在且 schema 合法

  单章管线:
    [A→B→C](summarizer) → [A+A](QJ+CC prompt) → [B+B](两个独立 wrapper 并行) → [C+C] 各自校验
  
  滑窗校验:
    [A→B→C](sliding-window report) → 编排器 Edit 修复 auto_fixable issues

eval_backend = "opus" (default):
  现有 Task(opus) 路径不变
```

## Invocation Pattern

```bash
# Codex 执行（stdin 管道，working_dir = 项目根目录）
codeagent-wrapper --backend codex - <project_root> < staging/prompts/chapter-048-quality-judge.md

# QJ + CC 并行：编排器发两个独立 Bash tool call
# (不使用 --parallel 模式，每个返回独立结果，校验更简单)
```

## Key Files

- `openspec/changes/m10-codex-eval-pipeline/proposal.md` — 完整提案
- `scripts/codex-eval.py` — 双模式：--agent 组装 / --validate 校验（待实现）
- `prompts/codex-summarizer.md` — Codex Summarizer prompt（待实现）
- `prompts/codex-quality-judge.md` — Codex QJ prompt（待实现）
- `prompts/codex-content-critic.md` — Codex CC prompt（待实现）
- `prompts/codex-sliding-window.md` — Codex 滑窗分析 prompt（待实现）
