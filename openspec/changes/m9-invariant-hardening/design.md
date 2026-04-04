## Context

当前 4 个 lint 脚本覆盖：AI 黑名单（lint-blacklist）、元信息泄漏（lint-meta-leak）、术语漂移（lint-terminology）、NER 实体（run-ner）。格式规则是最后一块未机械化的"硬声明"区域。

同时 CW Phase 2 的"修改量 ≤ 15%"约束从未被 enforce——agent 无法精确计算编辑距离，这条规则实际退化为"尽量少改"的模糊指导。其真实目的（防止过度润色导致风格漂移）已被 M3 的 style-drift 检测机制覆盖。保留它只增加 agent 的认知负担。

## Goals / Non-Goals

**Goals:**
- `lint-format.sh` 检测 4 项格式规则：破折号（error）、非中文引号（error）、分隔线（error）、字数越界（warning）
- 输出格式与 lint-meta-leak.sh 对齐（JSON, severity 分级）
- CW Phase 2 前置清洗阶段运行 lint-format，error 级别命中必须修复
- QJ contract_verification 增加 format_checks 字段
- 删除 CW Phase 2 中修改量 ≤ 15% 的约束文本和自检步骤

**Non-Goals:**
- 不改变 QJ 的 em_dash_count 等统计指标（保留作为 anti_ai 维度的统计参考）
- 不改变门控阈值或 gate 逻辑
- 不自动修复格式问题（lint 只检测，CW 自行修复）

## Decisions

1. **lint-format.sh 检测项与 severity**

   | 检测项 | 正则/逻辑 | severity | 说明 |
   |--------|----------|----------|------|
   | 破折号 (——) | `——` 或 `—` | error | 零容忍，CW §13 |
   | 非中文引号 | `["'\u2018\u2019\u300c\u300d]`（英文直引号/单引号/弯单引号/直角引号） | error | CW §14，排除中文标准双引号 \u201c\u201d |
   | 分隔线 | `^---$\|^\*\*\*$\|^\* \* \*$` | error | CW §15 |
   | 字数 < 2500 | `non_whitespace_chars < 2500` | warning | 偏短提醒 |
   | 字数 > 3500 | `non_whitespace_chars > 3500` | warning | 偏长提醒 |

   - error 级别：CW Phase 2 必须修复，QJ `has_violations` 计入
   - warning 级别：记录但不 gate

2. **CW Phase 2 集成位置**

   在现有前置清洗段（模型 artifact → 元信息泄漏 → 术语一致性 → 引号统一）之后追加：
   ```
   - **格式规则检查**：运行 `scripts/lint-format.sh` 扫描正文。error 级别命中（破折号、非中文引号、分隔线）必须修复；warning 级别（字数越界）记录但不阻断
   ```

   同时删除 Phase 2 §9 的"修改量自检"步骤和 Phase 2 约束中的"修改量控制：单次修改量 ≤ 原文 15%"。

3. **QJ 集成**

   在 Track 1 中 terminology_checks 之后（现为 Step 5），新增 Step 6（后续编号顺延）：
   ```
   6. **格式规则检查**：运行 `scripts/lint-format.sh`
      - error 命中 → status: "violation", confidence=high
      - warning 命中 → status: "warning"
      - 输出至 contract_verification.format_checks
      - **硬门槛**：errors > 0 时 has_violations = true
   ```

4. **Schema 更新**

   `eval/schema/chapter-eval.schema.json` 的 `contract_verification.properties` 增加：
   ```json
   "format_checks": {
     "type": "array",
     "items": {
       "type": "object",
       "properties": {
         "category": {"type": "string"},
         "severity": {"enum": ["error", "warning"]},
         "status": {"enum": ["violation", "warning", "pass"]},
         "count": {"type": "integer"},
         "detail": {"type": "string"}
       }
     }
   }
   ```

5. **修改量约束删除范围**

   从 `agents/chapter-writer.md` 删除：
   - Phase 2 §9："**修改量自检**：确认修改量 ≤ 15%..."
   - Phase 2 约束中："**修改量控制**：单次修改量 ≤ 原文 15%"
   - Phase 2 约束中 P0 预算分配的百分比说明（改为"P0 必做 > P1 优先 > P2 条件触发"的优先级描述，不再量化百分比）

## Risks / Trade-offs

- [Risk] 破折号 lint 误报：中文破折号 (——) 和英文 em-dash (—) 的 Unicode 编码不同 → Mitigation：两种都检测，确保零遗漏
- [Risk] 引号 lint 误报：正文中引用英文原文时可能包含英文引号 → Mitigation：仅检测独立出现的非中文引号（不在英文字母间的）；或标注为 warning 让 CW 人工判断
- [Trade-off] 删除修改量约束降低了 Phase 2 的显式约束 → 接受，style-drift 检测是更可靠的漂移防线

## References

- 博文 §八 Invariant Layer
- `scripts/lint-meta-leak.sh`（输出格式参考）
- `agents/chapter-writer.md` Phase 2 约束段落
- `agents/quality-judge.md` Track 1 步骤编号
- `eval/schema/chapter-eval.schema.json`
