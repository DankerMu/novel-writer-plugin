## 1. 术语表基础设施

- [ ] 1.1 定义 `world/terminology.json` schema（canonical/category/source/allow_variants）
- [ ] 1.2 新增 `scripts/extract-terminology.sh`：从 rules.json + active characters 自动提取术语表
- [ ] 1.3 `/novel:start` worldbuilding 阶段集成：自动运行 extract-terminology.sh

## 2. Lint 脚本

- [ ] 2.1 新增 `scripts/lint-terminology.sh`：术语漂移检测主脚本
- [ ] 2.2 实现精确匹配层：正文术语 vs 术语表
- [ ] 2.3 实现编辑距离变体检测（仅 character/location 类别，距离 ≤ 2）
- [ ] 2.4 实现章内一致性检查：同实体多称呼检测
- [ ] 2.5 输出格式对齐 lint-meta-leak.sh（JSON，severity 分级）

## 3. 管道集成

- [ ] 3.1 ChapterWriter Phase 2 增加术语一致性检查步骤
- [ ] 3.2 QualityJudge 契约校验增加 `contract_verification.terminology_checks`
- [ ] 3.3 `scripts/README.md` 增加 lint-terminology.sh 文档

## References

- 博文 §三.2 语义熵 / §八 Invariant Layer
- `scripts/lint-blacklist.sh` 和 `scripts/lint-meta-leak.sh`（模式参考）
- `world/rules.json`、`characters/active/*.json`
