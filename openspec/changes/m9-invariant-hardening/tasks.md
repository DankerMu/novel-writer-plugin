## 1. lint-format.sh

- [x] 1.1 新增 `scripts/lint-format.sh`：检测破折号/引号/分隔线/字数（bash + inline python heredoc）
- [x] 1.2 破折号检测：中文破折号 (——, U+2014×2) + 英文 em-dash (—, U+2014) → severity=error
- [x] 1.3 引号检测：非中文双引号 → severity=error（排除英文字母间的引号）
- [x] 1.4 分隔线检测：`---` / `***` / `* * *` 行首匹配 → severity=error
- [x] 1.5 字数检测：非空白字符计数，< 2500 或 > 3500 → severity=warning
- [x] 1.6 输出格式对齐 lint-meta-leak.sh（JSON: total_hits/errors/warnings/checks）
- [x] 1.7 `chmod +x`，venv 优先 python3

## 2. 管道集成

- [x] 2.1 CW Phase 2 前置清洗增加格式规则检查步骤
- [x] 2.2 QJ Track 1 增加 format_checks（Step 6，后续编号顺延）
- [x] 2.3 `eval/schema/chapter-eval.schema.json` 增加 format_checks 定义
- [x] 2.4 `scripts/README.md` 增加 lint-format.sh 文档

## 3. 死规则清理

- [x] 3.1 CW Phase 2 删除修改量 ≤ 15% 自检步骤（§9）
- [x] 3.2 CW Phase 2 约束删除修改量控制条款
- [x] 3.3 CW Phase 2 预算分配改为纯优先级描述（不量化百分比）
- [x] 3.4 style-guide.md 清除 15% 残留引用（review S2）

## References

- `scripts/lint-meta-leak.sh`（模式参考）
- `agents/chapter-writer.md` Phase 2
- `agents/quality-judge.md` Track 1
