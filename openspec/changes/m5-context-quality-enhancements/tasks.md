# Tasks: 上下文质量增强

## 1. Canon Status（M5.1）

- [ ] 1.1 扩展 `world/rules.json` schema：增加 `canon_status` 字段（`established` / `planned`），默认 `established`
- [ ] 1.2 扩展 `characters/active/*.json` schema：在 `abilities`、`known_facts`、`relationships` 中支持 `canon_status`
- [ ] 1.3 修改 `/novel:continue` manifest 组装逻辑：`hard_rules_list` 仅包含 `canon_status == "established"` 的规则
- [ ] 1.4 修改 `agents/chapter-writer.md`：明确指示仅引用 established 内容
- [ ] 1.5 修改 `agents/summarizer.md`：增加 `canon_upgrade` state_op 类型
- [ ] 1.6 修改 `agents/quality-judge.md`：L1 合规检查增加 planned 引用 WARNING
- [ ] 1.7 修改 `agents/world-builder.md`：创建 rule 时初始化 `canon_status: "planned"`
- [ ] 1.8 更新 `eval/schema/` 中相关 JSON schema

## 2. Platform Guide（M5.2）

- [ ] 2.1 创建 `templates/platforms/fanqie.md`（番茄小说写作指南模板）
- [ ] 2.2 扩展 `templates/style-profile-template.json`：增加 `platform` 字段
- [ ] 2.3 修改 `/novel:continue` manifest 组装：条件加载 `paths.platform_guide`
- [ ] 2.4 修改 `agents/chapter-writer.md`：输入定义增加可选 `platform_guide`
- [ ] 2.5 修改 `/novel:start` 快速启动流程：Step B 中采集平台偏好
- [ ] 2.6 创建空模板 `templates/platforms/qidian.md`、`jinjiang.md`（占位，标注 TODO）

## 3. Excitement Type（M5.3）

- [ ] 3.1 定义 `excitement_type` 枚举集合（8 种）并更新 L3 chapter contract schema
- [ ] 3.2 修改 `agents/plot-architect.md`：生成 L3 contract 时自动填充 `excitement_type`
- [ ] 3.3 修改 `agents/quality-judge.md`："节奏控制" 维度增加爽点落地评估逻辑
- [ ] 3.4 修改 `agents/chapter-writer.md`：读取 `excitement_type` 作为写作指引
- [ ] 3.5 更新 `skills/novel-writing/references/quality-rubric.md`：补充爽点评估标准
- [ ] 3.6 更新 `eval/schema/` 中 chapter contract JSON schema

## 4. 文档与测试

- [ ] 4.1 更新 `docs/user/spec-system.md`：补充 canon_status、platform、excitement_type 说明
- [ ] 4.2 更新 `skills/continue/references/context-contracts.md`：manifest 新增字段文档
- [ ] 4.3 补充 `eval/fixtures/` 中的 smoke test 用例
