# Genre → excitement_type 默认推荐映射

本文档为 PlotArchitect 生成 L3 章节契约时提供 genre→excitement_type 的默认推荐组合。

## 使用方式

PlotArchitect 在生成每章 L3 契约的 `excitement_type` 时：
1. 从 `brief.md` 或 `style-profile.json` 获取项目 genre
2. 查本表获取该 genre 的推荐枚举组合
3. 根据每章具体剧情从推荐列表中选取 1-2 个最匹配的值
4. 若推荐枚举无法精确描述，用 `excitement_note` 文本补充

> 本表为**默认推荐**，PlotArchitect 可根据具体章节内容偏离推荐——表中未列出的枚举值同样可用。

## 映射表

| Genre | 推荐 excitement_type | 典型场景 | 建议新增（M7+） |
|-------|---------------------|---------|----------------|
| 玄幻/仙侠 | `power_up` + `confrontation` | 突破境界、斗法对决、获得神器 | — |
| 都市 | `reversal` + `emotional_peak` | 逆袭打脸、情感爆发、身份揭露 | `underdog_rise` |
| 科幻 | `worldbuilding_wow` + `mystery_reveal` | 新文明接触、科技原理揭秘、宇宙尺度震撼 | — |
| 历史 | `worldbuilding_wow` / `setup`* | 历史事件再现、权谋布局、伏笔密集铺设 | — |
| 悬疑/推理 | `cliffhanger` + `mystery_reveal` | 关键线索、真相反转、悬念断崖 | `tension_build` |
| 言情/甜宠 | `emotional_peak` + `reversal` | 告白、误会解除、感情升温、身份反转 | `chemistry_spark` |

## M5 枚举完整列表（8 种）

| 值 | 含义 |
|----|------|
| `power_up` | 主角实力提升/获得新能力 |
| `reversal` | 局势反转/打脸 |
| `cliffhanger` | 悬念高峰/断崖式结尾 |
| `emotional_peak` | 情感爆发/催泪/燃点 |
| `mystery_reveal` | 谜团揭示/真相大白 |
| `confrontation` | 正面对决/高手过招 |
| `worldbuilding_wow` | 世界观震撼展示/新设定揭幕 |
| `setup` | 铺垫章（蓄力/布局/伏笔密集埋设） |

## 跨类型通用规则

- **setup 互斥**：`setup` 不与其他枚举共存（铺垫章独立标注）。上表中 `*` 标记的组合为备选关系（按章节实际内容择一），非同章共存
- **每章 1-2 个**：超过 2 个说明章节焦点不集中
- **铺垫章比例**：建议每 3-5 章出现 1 章 `setup`，避免连续 2 章以上 setup
- **卷首卷尾**：卷首章优先 `worldbuilding_wow` 或推荐枚举中的强钩子类型；卷末章优先 `cliffhanger`

## 未来枚举扩展（M7+）

以下枚举已提议但尚未纳入 M5 schema，当前用 `excitement_note` 文本兜底：

| 提议枚举 | 适用 Genre | excitement_note 示例 |
|---------|-----------|---------------------|
| `underdog_rise` | 都市 | `"逆袭翻盘，从底层一步步崛起"` |
| `tension_build` | 悬疑/推理 | `"层层递进的紧张感，线索逐步收拢"` |
| `chemistry_spark` | 言情/甜宠 | `"双方化学反应升温，暧昧张力拉满"` |

在这些枚举正式落地前，PlotArchitect 应选择最接近的 M5 枚举 + `excitement_note` 补充描述。
