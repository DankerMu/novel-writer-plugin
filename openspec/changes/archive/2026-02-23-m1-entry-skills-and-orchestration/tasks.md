## 1. `/novel:start` (Interactive Router)

- [x] 1.1 编写 `skills/start/SKILL.md` frontmatter（allowed-tools、model、中文交互约束）
- [x] 1.2 实现 checkpoint 存在性检测与状态解析（INIT/QUICK_START/VOL_PLANNING/WRITING/VOL_REVIEW 分支）
- [x] 1.3 定义 AskUserQuestion 菜单：2-4 选项 + Recommended 标注 + 超时策略
- [x] 1.4 实现“创建新项目”流程：创建目录结构 + 复制模板 + 初始化最小文件集（`.checkpoint.json`、`state/current-state.json`、`foreshadowing/global.json`、`storylines/storyline-spec.json` 等）
- [x] 1.5 实现 quick-start 试写编排：派发 WorldBuilder/CharacterWeaver/StyleAnalyzer + 试写 3 章流水线（依赖后续 agent changes）
- [x] 1.6 实现大纲确认/质量回顾/导入研究资料/更新设定的入口路由（按 spec 先定义接口与文件契约，复杂实现由 M2/M3 changes 细化）

## 2. `/novel:continue [N]` (High-frequency Loop)

- [x] 2.1 编写 `skills/continue/SKILL.md` frontmatter（参数约定与工具权限）
- [x] 2.2 实现 checkpoint 读取与状态校验（非 WRITING 时给出提示并终止）
- [x] 2.3 实现参数 `N` 解析与边界（默认 1，建议上限 5）
- [x] 2.4 定义流水线调用顺序与 staging 输出契约（依赖 `m1-chapter-pipeline-agents`）

## 3. `/novel:dashboard` (Read-only Status)

- [x] 3.1 编写 `skills/dashboard/SKILL.md` frontmatter（只读：Read/Glob/Grep）
- [x] 3.2 定义状态汇总指标：章节数/字数估算/均分趋势/伏笔统计/成本耗时（字段缺失时的降级策略）

## 4. Cross-cutting Constraints

- [x] 4.1 落地交互边界：AskUserQuestion 仅 `/novel:start`；Agents 不可直接提问
- [x] 4.2 落地注入安全：入口 Skill 注入原文时统一使用 `<DATA>` delimiter（与后续 agent changes 联动）

## References

- `docs/dr-workflow/novel-writer-tool/final/spec/02-skills.md`
- `docs/dr-workflow/novel-writer-tool/final/prd/01-product.md`
- `docs/dr-workflow/novel-writer-tool/final/prd/10-protocols.md`
