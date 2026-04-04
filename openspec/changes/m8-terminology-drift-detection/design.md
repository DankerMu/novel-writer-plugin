## Context

当前有两个确定性 lint 脚本（lint-blacklist.sh 压 AI 感、lint-meta-leak.sh 压元信息泄漏），但术语一致性完全依赖 agent 的记忆和判断力。随着章节增加，agent 上下文窗口中能装载的历史章节递减（滑窗），术语漂移的风险递增。

博文将这类问题归入**语义熵**：一个业务概念有多少叫法，一个状态模型有没有单一真相。对于小说项目，"业务概念"就是世界观术语、角色名、地名、功法名。

## Goals / Non-Goals

**Goals:**
- 从 L1/L2 spec 文件自动提取权威术语表（canonical terms）
- 脚本扫描章节正文，检测与权威术语的偏差（变体、别名未注册、前后不一致）
- 输出 JSON 报告，格式与 lint-blacklist/lint-meta-leak 对齐
- 集成到 CW Phase 2（清洗）和 QJ（校验），severity 默认 warning

**Non-Goals:**
- 不做语义相似度匹配（M8 仅用确定性规则：正则 + 编辑距离）
- 不自动修复术语变体（输出报告，由 CW Phase 2 或用户决定修改）
- 不处理对话中角色故意使用的口语变体（术语表可配置 allow_variants）

## Decisions

1. **术语表结构**
   - 自动生成：`scripts/extract-terminology.sh` 从 `world/rules.json`（术语定义）+ `characters/active/*.json`（角色名、能力名）提取
   - 输出：`world/terminology.json`
   - 格式：`[{"canonical": "萧炎", "category": "character", "source": "characters/active/xiao-yan.json", "allow_variants": ["萧兄"]}, ...]`
   - 支持手动补充条目（`"source": "manual"`）

2. **检测策略**
   - 第一层：精确匹配——正文中出现的术语是否在术语表中
   - 第二层：变体检测——对术语表中每个 canonical term，检查编辑距离 ≤ 2 的近似出现（排除 allow_variants）
   - 第三层：一致性检查——同一章内对同一实体使用了多种称呼且均未注册为 allow_variants

3. **输出格式**
   - 与 lint-meta-leak.sh 对齐：`{"total_hits": N, "errors": 0, "warnings": N, "hits": [...]}`
   - 术语漂移默认 severity=warning（不做硬门控），chapter-writer/quality-judge 按上下文判断是否需要修复
   - 未来可升级为 error（如核心角色名拼写错误）

4. **管道集成**
   - CW Phase 2：运行 lint-terminology.sh，warning 级别命中逐条检查，确认为漂移则修复
   - QJ 契约校验：运行 lint-terminology.sh，命中结果输出到 `contract_verification.terminology_checks`
   - 触发前提：`world/terminology.json` 存在；不存在时 graceful skip

## Risks / Trade-offs

- [Risk] 编辑距离误报率高（如"萧炎"和"肖严"编辑距离=2 但完全无关）→ Mitigation：仅对 category=character/location 的核心术语启用编辑距离；其余类别仅精确匹配
- [Risk] 术语表维护负担 → Mitigation：自动提取为主，手动补充为辅；extract-terminology.sh 在 /novel:start 的 worldbuilding 阶段自动运行
- [Trade-off] 不覆盖对话中的口语变体 → 接受，通过 allow_variants 白名单处理；过度检测对话会产生大量误报

## References

- 博文 §三.2 语义熵
- 博文 §八 Invariant Layer
- `scripts/lint-blacklist.sh`（lint 模式参考）
- `scripts/lint-meta-leak.sh`（lint 模式参考）
- `world/rules.json`（L1 术语来源）
- `characters/active/*.json`（L2 术语来源）
