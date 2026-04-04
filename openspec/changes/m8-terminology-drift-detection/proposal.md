## Why

博文六类熵中，**语义熵**对小说项目尤其致命：角色名、地名、功法/能力名、世界观术语跨章漂移。博文明确指出"语义熵不等于命名不统一，它还包括 bounded context 之间的关系是否明确"。

当前仓库依赖 Summarizer 压缩和 QJ 契约校验间接覆盖术语一致性，但没有专门的**确定性术语 lint**：
- 角色名可能出现同音异形（如"萧炎" vs "肖炎"）
- 地名/功法名可能有简称漂移（全称→简称→变体，前后不一致）
- 世界观术语可能在不同章节被不同表述
- QJ 的人工判断无法穷举检查，且依赖 agent 记忆准确性

lint-blacklist.sh 和 lint-meta-leak.sh 已证明确定性 lint 脚本对管道质量的价值。术语漂移检测是同一模式的自然延伸。

## What Changes

- 从 `world/rules.json` + `characters/active/*.json` + `world/locations.json`（如有）提取权威术语表
- 新增 `scripts/lint-terminology.sh`：扫描章节正文，检测术语变体和不一致
- 集成到 ChapterWriter Phase 2（清洗）和 QualityJudge 契约校验

## Capabilities

### New Capabilities

- `terminology-lint`: 基于权威术语表的确定性术语漂移检测，输出 JSON 报告

### Modified Capabilities

- ChapterWriter Phase 2：增加术语一致性检查步骤
- QualityJudge 契约校验：增加术语一致性检查项（warning 级别）

## Impact

- 影响范围：`scripts/lint-terminology.sh`（新增）、ChapterWriter agent prompt、QualityJudge agent prompt
- 依赖关系：依赖 `world/rules.json`、`characters/active/*.json` 中的权威术语
- 兼容性：纯增量；术语表不存在时脚本输出空报告（graceful degradation）

## Milestone Mapping

- M8.3: 术语漂移检测

## References

- 博文 §三.2 语义熵
- 博文 §八 Invariant Layer：把架构和 taste 机械化
- 当前 `scripts/lint-blacklist.sh` 和 `scripts/lint-meta-leak.sh` 的 lint 模式
- 当前 `world/rules.json` 和 `characters/active/*.json` 结构
