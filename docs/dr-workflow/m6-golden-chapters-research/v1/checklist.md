# Checklist v1

| # | Type | Suspicious Point | Research Direction |
|---|------|------------------|--------------------|
| 1 | data | §3.3 各平台黄金三章公式内容为空——三个平台的公式段落只有标题没有实际内容，DR-002 中有详细公式但未被引入 | 从 DR-002 §二/三/四 提取各平台三章公式补入 |
| 2 | methodology | §4.4 权重表使用的 8 维度（pacing/characterization/emotional_impact/prose_quality/world_building/plot_logic/originality/immersion）与现有 QualityJudge 的 8 维度（plot_logic/character/immersion/style_naturalness/foreshadowing/pacing/emotional_impact/storyline_coherence）不一致，缺乏明确的映射和转换逻辑 | 确认是否需要重新定义维度集，还是做映射适配；§4.5 的映射表需要验证合理性 |
| 3 | methodology | §4.5 维度映射存在逻辑问题：foreshadowing → originality（伏笔回收 ≠ 创意）、storyline_coherence → world_building（多线一致性 ≠ 世界观深度），这两个映射缺乏论证 | 重新审视映射关系，或论证为何这种近似可接受 |
| 4 | data | §5.1「情感词密度 > 15 次/千字」目标阈值无来源引用；「对话/叙述比 40-55%」范围来自 Lin & Hsieh (2019) 的 40-60% 但被缩窄且未解释原因，且应按类型差异化（科幻 30-40%、都市 >50%）而非统一值 | 补充阈值来源或标注为经验估计；按类型设定差异化目标范围 |
| 5 | feasibility | §6.1 番茄硬门「主角必须在第 1 章 300 字内登场」——DR-002 实际提到番茄的标准是「开篇 200 字内设置核心冲突」，300 字是通用建议而非番茄特定要求，数据混淆 | 回查 DR-002 §2.5 确认番茄的精确字数要求，区分「主角登场」和「核心冲突」 |
| 6 | architecture | §6.2 excitement_type 推荐值（power_reveal/underdog_rise/world_shock 等 10 个新枚举）与 M5 spec 已定义的 8 个枚举（face_slap/power_up/mystery_reveal 等）完全不同，未说明是替换还是扩展 | 对齐 M5 已有枚举，明确哪些是新增、哪些映射到已有值 |
| 7 | data | §6.3 加权公式段落为空（lines 376-377），只有标题没有实际公式内容 | 补入 overall_audience = Σ(dimension_score[i] × weight[i]) 的完整公式 |
| 8 | data | §3.1 起点中文网的日活/月活数据缺失，只写「付费用户为主」，与番茄的 1.2 亿和晋江的 535 万无法形成有效对比 | 补充起点的可比用户量数据 |
| 9 | methodology | 文档将类型（genre）和平台（platform）作为两个独立维度处理，但实际存在强交互——晋江几乎没有硬核玄幻、番茄几乎没有纯爱 BL。§6.4 L3 acceptance_criteria 只按类型设定未考虑平台 × 类型组合 | 讨论类型×平台交互效应，至少标注哪些组合是无效的 |
| 10 | data | §一「2023 年阅文数据显示：前 300 字跳出率 78%，前 3 章留存率不足 5%」——这个关键数据在 DR 子报告中引用自多个二手来源但未找到阅文官方原始出处，可靠性存疑 | 尝试定位原始数据来源（阅文年报/创作学堂/编辑分享），如无法核实则标注为业界广泛引用的估计值 |
| 11 | architecture | DR-002 和 DR-003 分别提出了不同的权重矩阵（DR-002 用 8 维度但维度名称不同，DR-003 也用 8 维度但又是另一套），主文档 §4.4 声称「取加权平均」但未展示计算过程，最终权重的来源不透明 | 展示两份报告权重的对齐过程，或明确选择一份作为基础并说明理由 |
