# M5 迁移指南

本文档帮助已有项目升级到 M5（上下文质量增强）。所有新增字段均向后兼容，旧项目无需修改即可正常运行，但建议按以下步骤逐步启用新功能。

## M5.1: Canon Status（正典/预案区分）

### 自动兼容（无需操作）

- `world/rules.json` 中 `canon_status` 缺失时默认视为 `established`
- `characters/active/*.json` 中 `abilities`/`known_facts`/`relationships` 缺失时视为空数组
- 编排器预过滤和 commit 升级逻辑对旧数据无副作用

### 建议操作（可选）

1. **审查现有规则**：检查 `world/rules.json`，为尚未在正文中展现的规则手动添加 `"canon_status": "planned"`
2. **丰富角色数据**：为 `characters/active/*.json` 补充 `abilities[]`、`known_facts[]`、`relationships[]` 数组（每项可标注 `canon_status`）
3. **验证**：运行 `/novel:continue 1` 确认流水线正常（无报错即兼容）

## M5.2: Platform Guide（平台写作指南）

### 自动兼容（无需操作）

- `style-profile.json` 中 `platform` 缺失或为 `null` 时跳过平台指南加载
- 流水线行为与 M5 之前完全一致

### 建议操作（可选）

1. **设置平台**：在 `style-profile.json` 中添加 `"platform": "fanqie"` (或 `"qidian"` / `"jinjiang"`)
2. **验证模板存在**：确认 `templates/platforms/{platform}.md` 文件存在（插件自带 fanqie/qidian/jinjiang 三个模板）
3. **自定义平台**：如使用其他平台，复制现有模板并修改参数，保存为 `templates/platforms/{platform_id}.md`

## M5.3: Excitement Type（爽点类型标注）

### 自动兼容（无需操作）

- `excitement_type` 缺失时 ChapterWriter 按大纲自由发挥，QualityJudge 跳过爽点评估
- 旧 L3 章节契约无需修改

### 建议操作（可选）

1. **回填已有契约**：为 `volumes/vol-XX/chapter-contracts/chapter-XXX.json` 补充 `excitement_type` 数组（从 8 种枚举选 1-2 个）
2. **枚举值参考**：
   - `power_up` — 实力提升
   - `reversal` — 局势反转
   - `cliffhanger` — 悬念高峰
   - `emotional_peak` — 情感爆发
   - `mystery_reveal` — 谜团揭示
   - `confrontation` — 正面对决
   - `worldbuilding_wow` — 世界观震撼
   - `setup` — 铺垫章（与其他类型互斥）
3. **新卷规划**：PlotArchitect 在新建契约时会自动填充 `excitement_type`，无需手动操作

## 验证清单

- [ ] `/novel:continue 1` 正常执行（无报错）
- [ ] QualityJudge 评估输出含 `has_warnings` 字段（M5.1 新增）
- [ ] 若设置了 platform，ChapterWriter manifest 含 `platform_guide` 路径
- [ ] 若 L3 契约含 `excitement_type`，QualityJudge pacing 评分反映爽点落地情况
