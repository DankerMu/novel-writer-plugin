# 网文质量可量化指标与评分方法论 -- 深度调研报告

> 调研日期：2026-03-01
> 目标：为 QualityJudge 8 维度评分体系的迭代提供学术与业界依据

---

## 一、文本可量化指标

### 1.1 节奏指标（Pacing Metrics）

| 指标 | 定义 | 计算方法 | 来源 |
|------|------|----------|------|
| 场景切换频率 | 每千字中 setting/location 变化次数 | NER 提取地点实体 + 变化计数 | Leon et al. (2020) |
| 对话/叙述比 | 对话段落字数 / 总字数 | 正则匹配引号内文本占比 | Lin & Hsieh (2019) |
| 转折密度 | 每千字中情感极性翻转次数 | 句级情感分析 + 极性翻转检测 | Reagan et al. (2016) |
| 段落长度变异系数 | 段落字数的 CV（标准差/均值） | 直接统计 | Leon et al. (2020) |
| 句长变化率 | 相邻句子字数差的均值 | 分词计数 + 差分 | Wang et al. (2024) |
| 动作/静态比 | 含动词的句子占比 vs 纯描写句 | POS tagging | Purdy et al. (2018) |

**学术支撑**：
- Leon et al. (2020) "Quantitative Characteristics of Human-Written Short Stories" 发现人类故事在段落长度分布、对话比例上有稳定的统计模式，可作为「像不像人写的」自动评估基线。[来源](https://link.springer.com/article/10.1007/s00354-020-00111-1)
- Wang et al. (2024) "Decoding Online Literature: A Quantitative Analysis of Language Features in Chinese Online Literature" 对中文网文做了量化语言特征分析，发现网文相比传统文学在句长、词汇丰富度、对话比上有显著差异。[来源](https://www.researchgate.net/publication/387986781_Decoding_online_literature_A_Quantitative_Analysis_of_Language_Features_in_Chinese_Online_Literature)

### 1.2 钩子指标（Hook Metrics）

| 指标 | 定义 | 计算方法 | 适用位置 |
|------|------|----------|----------|
| 章末悬念强度 | 末尾 200 字的信息缺口数量 | LLM 判定：未解答问题 / 未完成动作计数 | 章末 |
| 章首锚定速度 | 前 200 字建立冲突/疑问所需字数 | LLM 判定：首个冲突/钩子出现位置 | 章首 |
| 信息不对称度 | 读者已知 vs 角色已知信息的差集大小 | 基于摘要追踪的信息图谱 | 全章 |
| 承诺-兑现间距 | 从 setup 到 payoff 的章节跨度 | 伏笔图谱中 plant → harvest 的距离 | 跨章 |

**说明**：钩子指标中纯文本级自动化难度较高，更适合 LLM-as-Judge 半自动评估。本项目现有 `foreshadowing` 维度可扩展为定量追踪。

### 1.3 爽感指标（Gratification / "Shuang" Metrics）

这是网文特有的核心概念，学术文献较少直接量化，但可从以下代理指标间接衡量：

| 指标 | 定义 | 计算方法 | 说明 |
|------|------|----------|------|
| 主角能力提升频率 | 每 N 章出现一次能力/境界/资源增长 | 基于 L2 契约 power_level 变化追踪 | 升级流核心 |
| 冲突解决速度 | 从冲突引入到解决的字数 | L3 契约 objective 完成速度 | 爽文：短快；虐文：长慢 |
| 地位反转频率 | 每 N 章出现一次「打脸」/地位提升事件 | LLM 标注事件类型 | 都市爽文核心 |
| 期望颠覆密度 | 每千字「但是/然而/没想到」等转折词频率 | 词表匹配 | 粗粒度代理 |
| 信息优势感 | 读者知道但对手不知道的信息比例 | 基于信息图谱 | 扮猪吃虎核心 |

**业界参考**：
- Liu et al. (2025) "The Impact of Real-Time Reader Interactions on Plot Structure and Pacing in Chinese Web Novels"（暨南大学）研究了《全职高手》《放开那个女巫》等作品中读者互动对节奏的影响，发现读者最频繁正面反馈集中在「反转」「升级」「打脸」三类事件。[来源](https://www.pioneerpublisher.com/SAA/article/download/1228/1126/1287)
- 番茄小说平台创作指南公开提到：前 3 章完读率是核心留存指标，建议在 500 字内建立核心冲突。[来源](https://www.oreateai.com/blog/tomato-novel-platform-creation-guide-revenue-analysis-and-content-creation-methodology/a693454deeca4d49363c799a8ccb6059)

### 1.4 情感指标（Emotional Metrics）

| 指标 | 定义 | 计算方法 | 来源 |
|------|------|----------|------|
| 情感弧形状 | 全章情感轨迹的弧型分类 | 句级情感分析 → SVD 降维 → 6 弧型分类 | Reagan et al. (2016) |
| 情感词密度 | 每千字情感词（正/负/中）数量 | 中文情感词典匹配 | 通用 NLP |
| 情感极性翻转次数 | 全章中正→负或负→正的切换次数 | 滑动窗口情感极性检测 | Reagan et al. (2016) |
| 情感强度峰值 | 全章最强情感强度值 | 情感分析置信度最大值 | 通用 NLP |
| 情感弧与目标弧的偏差 | 实际弧与 L3 契约预定弧的 DTW 距离 | Dynamic Time Warping | 可创新 |

**关键论文 -- Reagan et al. (2016)**：
分析 Project Gutenberg 1,737 部小说，通过情感分析 + SVD 降维发现 6 种基本情感弧形状：
1. **Rags to riches** (持续上升)
2. **Riches to rags** (持续下降)
3. **Man in a hole** (下降→上升)
4. **Icarus** (上升→下降)
5. **Cinderella** (上升→下降→上升)
6. **Oedipus** (下降→上升→下降)

其中 **Cinderella**、**Oedipus** 和 **两段 Man-in-a-hole** 的组合是下载量最高的弧型。这为网文「先虐后爽」节奏提供了数据支撑。
[来源](https://arxiv.org/abs/1606.07772)

### 1.5 代入感/沉浸感指标（Immersion Metrics）

| 指标 | 定义 | 计算方法 |
|------|------|----------|
| 感官描写密度 | 每千字涉及视/听/触/嗅/味描写的句子数 | 感官词表匹配 + LLM 辅助分类 |
| 视角紧密度 | 紧密第三人称/第一人称视角保持率 | 检测视角滑移（如突然切入全知视角） |
| 内心独白比 | 角色内心活动/全文 比例 | 正则匹配心理描写标志词 |
| 细节具体度 | 专有名词、数字、具体物品 vs 抽象词的比例 | NER + 词性标注 |
| 时态连续性 | 叙述时态一致性 | 中文较弱，但可检测「了/着/过」使用一致性 |

---

## 二、AI/NLP 评估方法

### 2.1 LLM-as-Judge 在创意写作评估中的应用

#### 2.1.1 核心发现

**LLMs-as-Judges 综合调查** (Li et al., 2024, 清华大学)：
- 对 LLM 评估方法进行了系统分类：pointwise scoring、pairwise comparison、listwise ranking
- 创意写作领域 LLM 评判与人类判断的相关性中等偏上，但存在系统性偏差：
  - **冗长偏差**：倾向给更长的文本更高分
  - **位置偏差**：pairwise 比较中倾向选择第一个/最后一个
  - **自我偏好**：倾向给自己生成的文本更高分
  - **风格偏好**：偏好正式、结构化的写作风格
- [来源](https://arxiv.org/html/2412.05579v2)

**LitBench** (Fein et al., 2025, Stanford)：
- 2,480 对人工标注的故事比较，测试 LLM-as-Judge 可靠性
- 零样本 LLM 评判准确率：Claude-3.7-Sonnet 最高，达 73%
- 经过训练的 Bradley-Terry 奖励模型达 78%
- 结论：**零样本 LLM 评判对创意写作不够可靠，需要专门训练或校准**
- [来源](https://arxiv.org/abs/2507.00769)

**AHP-Powered LLM Reasoning** (Lu et al., 2024)：
- 将层次分析法 (AHP) 与 LLM 结合用于多维度开放式评估
- 流程：LLM 生成评估维度 → 各维度下 pairwise comparison → AHP 计算权重和分数
- 比单纯 pointwise scoring 更接近人类判断
- [来源](https://arxiv.org/abs/2410.01246v1)

#### 2.1.2 创意写作专用评估框架

**HANNA Benchmark** (Chhun et al., 2022, COLING)：
- 提出 6 个正交的人类评估维度：Relevance, Coherence, Empathy, Surprise, Engagement, Complexity
- 测试 72 个自动指标与人类维度的相关性
- 发现：传统词汇指标（BLEU/ROUGE）与故事质量相关性极低；LLM-based 指标（G-EVAL, BARTScore）表现显著更好
- [来源](https://aclanthology.org/2022.coling-1.509/)

**Story Evaluation 综合调查** (Yang & Jin, 2024, 人民大学)：
- 系统梳理故事评估维度层级：
  - **基础层**：Fluency, Grammaticality, Non-redundancy
  - **结构层**：Coherence (Cohesion, Consistency, Completeness)
  - **内容层**：Informativeness, Commonsense, Character Development
  - **体验层**：Interestingness, Empathy, Surprise
- 指标分类：
  - 传统方法：词汇级(BLEU/ROUGE)、嵌入级(BERTScore)、概率级(Perplexity/BARTScore)、训练级(BLEURT)
  - LLM方法：嵌入级(OpenAI embeddings)、概率级(GPTScore)、生成级(G-EVAL/ChatEval)、训练级(COHESENTIA/PERSE)
- **关键推荐**：
  1. 创意任务使用 reference-free 指标
  2. 多指标组合：词汇级测多样性 + 嵌入级测语义 + LLM级测细腻方面
  3. 面向维度的评估优于单一总分
  4. 主观维度需要个性化评估
- [来源](https://arxiv.org/html/2408.14622v1)

### 2.2 长篇故事评估

**LongStoryEval** (Yang & Jin, 2025, ACL)：
- 首个大规模长篇小说评估基准：600 本新出版书籍，平均 121K tokens
- **8 个顶层评估维度**（按读者重要性排序）：
  1. Plot and Structure
  2. Characters
  3. Writing and Language
  4. Themes
  5. World-Building and Setting
  6. Emotional Impact
  7. Enjoyment and Engagement
  8. Expectation Fulfillment
- **核心发现**：
  - 客观维度中 **Plot 和 Characters 影响力最大**，World-building 和 Writing quality 影响最小
  - 主观维度中 Emotional Impact、Enjoyment、Expectation Fulfillment 均关键
  - Themes 重要但为次要考量
- **三种 LLM 评估方法**：
  1. Aggregation-Based：逐章评估后取均值
  2. Incremental-Updated：逐章递进更新评估
  3. Summary-Based：先压缩为摘要再评估
- 结论：Aggregation 和 Summary-Based 表现最好；Incremental 较差
- [来源](https://arxiv.org/html/2512.12839v1)

**Towards A "Novel" Benchmark** (Wang et al., 2025, ACL Findings, 北大)：
- 提出 Macro/Meso/Micro 三级 10 维度评估框架（中英文双语）
- 发现 LLM 生成长篇存在 **"高开低走"现象**（开头强、结尾弱）
- 不同 LLM 适合评估不同层级，需组合使用
- [来源](https://aclanthology.org/2025.findings-acl.1114/)

### 2.3 故事质量预测的量化特征

**Purdy et al. (2018, AIIDE, Georgia Tech)**：
- 提出可自动计算的故事质量特征，与人类判断显著相关：
  - **Suspense**：基于信息论的悬念度量（角色目标达成概率的变化率）
  - **Plot coherence**：事件因果链的连贯性评分
  - **Character believability**：角色行为与既定性格的一致性
  - **Novelty**：与训练集故事的 n-gram 重叠度（越低越新颖）
- 使用这些特征训练的回归模型可作为人类评估的代理
- [来源](https://faculty.cc.gatech.edu/~riedl/pubs/purdy-aiide18.pdf)

**Ware et al. (2012)**：
- 定义叙事冲突的 4 个量化维度：
  - **Balance**：对立双方力量均衡度
  - **Directness**：冲突的直接程度
  - **Intensity**：冲突的激烈程度
  - **Resolution**：冲突解决的满足度
- 实验证明这些指标与人类读者评估一致
- [来源](https://cs.uky.edu/~sgware/reading/papers/ware2012metrics.pdf)

### 2.4 可用的 NLP 工具链

| 工具/库 | 功能 | 适用场景 |
|---------|------|----------|
| HanLP / LTP | 中文 NER、分词、POS、情感分析 | 基础文本特征提取 |
| TextBlob / VADER (英) / SnowNLP (中) | 句级情感极性 | 情感弧计算 |
| spaCy + 自定义 pipeline | 实体追踪、关系提取 | 角色一致性检测 |
| G-EVAL (OpenAI) | LLM-based 多维度评估 | 直接集成到 QualityJudge |
| BARTScore / BERTScore | 生成文本质量 | 与参考文本的语义相似度 |
| COHESENTIA | 训练式连贯性评估 | 章节间连贯性 |
| Narrative Arc toolkit (Reagan) | 情感弧提取和分类 | 全书/全卷情感弧分析 |

---

## 三、评分权重设计方法论

### 3.1 从读者行为数据反推维度权重

#### 3.1.1 可用行为信号

| 信号 | 含义 | 数据来源 |
|------|------|----------|
| 完读率 (completion rate) | 章节被读完的比例 | 平台 API / 模拟 |
| 追更率 (next-chapter rate) | 读完后点击下一章的比例 | 平台 API / 模拟 |
| 催更/互动率 | 评论/打赏/投票行为频率 | 平台 API |
| 退出位置 (drop-off point) | 读者中断阅读的具体位置 | 平台 API |
| 收藏/推荐转化 | 阅读后收藏或推荐的比例 | 平台 API |

**Wharton 研究** (Zhao, Mehta & Shi, 2023)：
- 使用中国在线图书平台数据建立连续阅读行为的结构化模型
- 发现章节释放策略显著影响留存：同时释放导致 binge 消费但降低探索；逐章释放增加平台粘性
- 关键指标：章节间转化率（chapter-to-chapter conversion）是最强的质量代理信号
- [来源](https://marketing.wharton.upenn.edu/wp-content/uploads/2023/03/Mehta-Nitin-Serial-Media.pdf)

**Chapter Chronicles 数据分析** (2025)：
- 分析 277 部 Royal Road 连载作品的读者行为数据
- 发现章节长度与读者留存无显著线性关系（挑战了「短章节更好」的传统观点）
- 真正影响留存的因素：更新一致性、钩子质量、角色发展深度
- [来源](https://www.chapterchronicles.com/blog/chapter-length-analysis/)

#### 3.1.2 权重反推方法

**方法 A：回归分析法**
1. 收集 N 章的 8 维度人工评分 + 读者行为数据（完读率/追更率）
2. 以行为数据为因变量，8 维度为自变量做多元回归
3. 标准化回归系数即为各维度的「行为解释权重」
4. 缺点：需要足够样本量（建议 n >= 100）

**方法 B：Shapley Value 分析**
1. 训练预测模型（完读率 ~ 8 维度）
2. 使用 SHAP 计算各维度对预测的边际贡献
3. Shapley value 的归一化值作为权重
4. 优点：捕捉非线性交互效应

**方法 C：偏好学习法**
1. 收集读者对章节对的偏好（A > B）
2. 训练 Bradley-Terry 模型
3. 使用可解释性方法反推各维度贡献
4. LitBench 已验证此方法的有效性

### 3.2 A/B 测试方法论在章节质量评估中的应用

**MC Gebhard 案例** (记录于 Elle Griffin, 2021)：
- 言情小说作者 MC Gebhard 在写全书之前 A/B 测试章节
- 方法：在 ReaperHouse 平台向订阅读者推送同一故事的不同版本开头
- 追踪指标：打开率、完读率、「想读更多」按钮点击率
- 结果：可在写书之前预测哪些概念最可能商业成功
- 启示：**前 3 章（黄金三章）的 A/B 测试最有价值**
- [来源](https://ellegriffin.medium.com/mc-gebhard-a-b-tests-her-novel-chapters-94e2cb8a59a2)

**应用于本项目的可能性**：
- 当 ChapterWriter 产出多个候选版本时，可向小规模读者群推送做 pairwise comparison
- 或使用 LLM-as-Judge 做模拟 A/B：同一章两个版本，让 LLM 做 pairwise preference 判断
- 结合 AHP 方法可以系统化地将 pairwise 偏好转换为维度权重

### 3.3 多维度加权评分的数学模型

#### 3.3.1 AHP（层次分析法）

**原理**：通过专家 pairwise comparison 建立判断矩阵，计算特征向量得到权重。

**应用于网文评分**：
1. 构建层级：目标层（整体质量）→ 准则层（8 维度）→ 方案层（具体章节）
2. 邀请编辑/读者对 8 维度做两两比较（如「情节逻辑 vs 角色塑造哪个更重要？重要多少？」）
3. 计算一致性比率 CR < 0.1 确保判断矩阵逻辑一致
4. 得到各维度权重

**T-SF-AHP 扩展** (IJICT, 2025)：
- 在音乐创作评估中结合 T-spherical fuzzy AHP + TOPSIS
- 专家和听众排序的 Spearman 相关性分别达 ρ=0.92 和 ρ=0.88
- 启示：fuzzy 方法可以处理评分中的模糊性和不确定性
- [来源：IJICT 2025 Vol.26 No.12]

**AHP + LLM 结合** (Lu et al., 2024)：
- 让 LLM 自动生成评估维度
- 在各维度下做 pairwise comparison
- 用 AHP 框架汇总为最终得分
- GPT-4 下该方法显著优于 4 个基线
- [来源](https://arxiv.org/abs/2410.01246v1)

#### 3.3.2 TOPSIS（理想解排序法）

**原理**：计算每个方案与「理想最优解」和「理想最劣解」的加权距离，取相对贴近度排序。

**应用场景**：
- 当有多个候选章节版本（如 ChapterWriter 多次修订）时，TOPSIS 可综合 8 维度得分选出最优版本
- 权重可来自 AHP 或回归分析

#### 3.3.3 熵权法（Entropy Weight Method）

**原理**：根据各维度得分的信息熵自动计算权重 -- 离散程度大的维度权重高（区分力强）。

**优势**：完全数据驱动，无需主观判断
**劣势**：可能与实际重要性不一致（如所有章节 pacing 都是 3 分，则 pacing 权重→0，但这不代表 pacing 不重要）

**推荐**：熵权法 + AHP 主观权重的组合（如 0.6*AHP + 0.4*熵权）可平衡主观判断与数据客观性。

#### 3.3.4 当前项目权重 vs 学术建议对比

| 维度 | 当前权重 | LongStoryEval 重要性 | 建议调整方向 |
|------|----------|---------------------|-------------|
| plot_logic | 0.18 | 最高（#1） | 维持或略增 |
| character | 0.18 | 最高（#2） | 维持 |
| immersion | 0.15 | 中（Writing #3） | 维持 |
| style_naturalness | 0.15 | 低（特殊需求） | 维持（AI写作特有） |
| foreshadowing | 0.10 | 未单独列出 | 维持（网文特有） |
| pacing | 0.08 | 含在 Plot 内 | **建议增至 0.12**（网文节奏极关键） |
| emotional_impact | 0.08 | 高（#6） | **建议增至 0.10** |
| storyline_coherence | 0.08 | 含在 Plot 内 | 维持 |

**注意**：M6 提案已规划按平台调整权重，上表为通用基线建议。

---

## 四、业界实践

### 4.1 阅文集团 / 起点中文网

公开信息有限，但可从编辑审稿流程和公开分享推断：

**编辑审稿维度**（综合公开分享）：
- 前三章「黄金三章」重点评估：钩子强度、角色辨识度、世界观切入效率
- 中后期评估：节奏稳定性、升级/爽点频率、伏笔回收
- 完本评估：主线收束满意度、角色成长完整性

**推荐算法指标**（公开技术博客推断）：
- 完读率（最核心）、追更率、互动率（评论/投票）、付费转化率
- 读者标签匹配度（协同过滤 + 内容特征）
- 新书冷启动：编辑评分 + 前 N 章机器评估

### 4.2 字节跳动 / 番茄小说

**创作者指南要点**（公开资料）：
- 前 3 章完读率是核心考核指标
- 推荐机制：分层测试（小流量 → 大流量），以完读率和追更率为核心排序依据
- 免费模式下的「读者时长」替代付费作为质量代理
- 内容审核：AI 初筛（违规/低质）+ 人工复审
- [来源](https://www.oreateai.com/blog/tomato-novel-platform-creation-guide-revenue-analysis-and-content-creation-methodology/a693454deeca4d49363c799a8ccb6059)

### 4.3 AI 辅助写作工具的评估模块

#### 4.3.1 文镜君 (wenjingjun.cn)

中文网文专用 AI 鉴评工具，4 个核心评估维度：
- **评文笔**：表达载体的质感（用词、修辞、句式）
- **立人物**：核心支撑的灵魂（人设一致性、性格弧）
- **圆世界观**：规则体系的自洽性
- **顺情节**：逻辑链条的通顺度

特点：定性分析为主，识别读者可能弃读的位置并给出原因。
[来源](https://www.wenjingjun.cn/)

#### 4.3.2 笔灵 AI (ibiling.cn)

提供「小说字词问题通用诊断」等工具，侧重：
- 字词级错误检测
- AI 痕迹检测
- 内容质量通用诊断
[来源](https://ibiling.cn/novel-pre-review/word-check)

#### 4.3.3 ContentAny

综合内容分析平台，20+ 维度检测：
- AI 内容密度检测
- 内容深度评估
- 同质化检测
- 逻辑性检测
- 限流/冷启动流量预测
[来源](https://www.aifoxs.com/fangan/wenan)

### 4.4 网文作者自我评估 Checklist

综合起点作者经验分享和写作社区讨论，高频自检维度：

**章节级 Checklist**：
1. 前 300 字是否建立了本章核心冲突/目标？
2. 章末是否留有至少一个未解决的悬念？
3. 主角是否有明确的章内行动目标？
4. 本章是否推进了至少一条主线/副线？
5. 对话是否推动剧情而非仅为水字数？
6. 是否有至少一个「爽点」或情感高潮？
7. 新角色/新设定是否在 100 字内建立了辨识度？
8. 是否有视角滑移或全知叙事泄露？

**卷/弧级 Checklist**：
1. 每 3-5 章是否有一个小高潮？
2. 每 15-20 章是否有一个大高潮/转折？
3. 副线是否在 10 章内回归过一次？
4. 主角能力曲线是否保持稳定上升（避免长期停滞）？
5. 伏笔是否在 30 章内有所推进（避免读者遗忘）？

### 4.5 连载小说质量衰减研究

**Chapter Chronicles 分析** (2025)：
- 分析 1,147 条 Reddit 评论关于 LitRPG 系列质量下降的原因
- 读者抱怨最多的质量维度（按频率排序）：
  1. **角色发展停滞**：主角不再成长，配角沦为工具人
  2. **节奏拖沓**：中后期水字数明显增加
  3. **重复套路**：同类冲突/解决模式反复出现
  4. **世界观膨胀失控**：设定越来越复杂但不自洽
  5. **主线迷失**：副线喧宾夺主，核心目标模糊
  6. **爽感递减**：升级/反转的刺激感不如早期
- 启示：QualityJudge 应关注**跨章趋势检测**（各维度是否在持续下降）
- [来源](https://www.chapterchronicles.com/blog/why-great-litrpg-series-fall-off/)

---

## 五、中文网文特有研究

### 5.1 语言特征量化

**Lin & Hsieh (2019, NTU)**："The Secret to Popular Chinese Web Novels: A Corpus-Driven Study"
- 对热门网文的语言特征做语料库分析
- 发现热门作品的共性特征：
  - 对话比例显著高于传统文学（40-60% vs 20-30%）
  - 句长较短且变异小（读者友好）
  - 高频使用口语化表达
  - 非文本信号（点击量、收藏量、评论量）与文本特征有显著交互效应
- [来源](https://drops.dagstuhl.de/storage/01oasics/oasics-vol070-ldk2019/OASIcs.LDK.2019.24/OASIcs.LDK.2019.24.pdf)

### 5.2 读者互动对叙事结构的影响

**Liu, Xu & Tang (2025, 暨南大学)**：
- 研究实时读者互动（评论、弹幕、投票、打赏）对网文情节和节奏的影响
- 案例：《全职高手》《放开那个女巫》《择天记》
- 发现：
  - 读者互动可导致叙事弧的显著调整
  - 高互动章节的节奏通常更快
  - 打赏行为集中在「反转」和「升级」场景
- 中西方连载小说的关键差异：中文网文的读者影响力远大于西方 serial fiction
- [来源](https://www.pioneerpublisher.com/SAA/article/download/1228/1126/1287)

---

## 六、对本项目 QualityJudge 的改进建议

### 6.1 短期可落地（M6 范围内）

1. **平台权重差异化**（M6.2 已规划）：
   - 番茄权重：pacing 0.15, emotional_impact 0.12, plot_logic 0.15（爽感优先）
   - 起点权重：plot_logic 0.20, character 0.20, foreshadowing 0.12（深度优先）
   - 晋江权重：character 0.22, emotional_impact 0.15, immersion 0.15（情感优先）

2. **可计算子指标注入**：在现有 5 分制定性评估基础上，为 3 个维度增加量化锚点：
   - `pacing`：对话比（目标 40-55%）、段落长度 CV（目标 0.3-0.7）、场景切换频率
   - `style_naturalness`：已有黑名单命中率 + 句式重复率，可增加句长 CV
   - `emotional_impact`：情感极性翻转次数、情感词密度

3. **章末钩子检测**：作为 `pacing` 的子指标，LLM 检查末尾 200 字是否存在至少一个未解决的悬念/信息缺口

### 6.2 中期可探索（M7+）

1. **情感弧追踪**：
   - 对每章做句级情感分析，绘制情感弧
   - 与 L3 契约预定的 `emotional_arc` 做 DTW 距离比较
   - 弧型分类对照 Reagan 六弧型，检查是否符合目标模式

2. **跨章趋势监控**：
   - 各维度得分的滑动平均线，检测持续下降趋势
   - 爽感递减预警：连续 5 章无能力提升/反转事件
   - 节奏拖沓预警：对话比 / 场景切换频率持续走低

3. **Double-Judge 校准**：
   - 使用 AHP + LLM 方法让两个 judge 的维度权重也参与 pairwise calibration
   - 参考 LitBench 的 Bradley-Terry 训练方法提升评判一致性

4. **读者模拟评估**：
   - 构建不同「读者画像」的 LLM persona（如「番茄小说重度用户」「起点老书虫」「晋江言情读者」）
   - 让不同 persona 分别评价同一章节
   - 综合多 persona 评分作为受众视角评估

### 6.3 长期研究方向

1. **人工标注集扩展**：当前 30 章标注集（M3）扩展至 200+ 章，支持回归分析反推权重
2. **行为数据闭环**：如果未来接入阅读平台数据，可用完读率/追更率做权重回归校准
3. **个性化评估**：参考 PERSE 框架，让 QualityJudge 学习特定作者/读者群的偏好模式
4. **情感弧库**：为不同网文类型（升级流/虐恋/悬疑）建立标准情感弧模板库，供 L3 契约引用

---

## 七、核心参考文献索引

### 学术论文

| 编号 | 论文 | 年份 | 核心贡献 |
|------|------|------|----------|
| [1] | Reagan et al. "The emotional arcs of stories are dominated by six basic shapes" | 2016 | 6 种情感弧型 + 与流行度的关联 |
| [2] | Purdy et al. "Predicting Generated Story Quality with Quantitative Measures" | 2018 | 可自动计算的故事质量特征 |
| [3] | Ware et al. "Four Quantitative Metrics Describing Narrative Conflict" | 2012 | 冲突的 4 维量化指标 |
| [4] | Leon et al. "Quantitative Characteristics of Human-Written Short Stories" | 2020 | 人类故事的量化统计模式 |
| [5] | Lin & Hsieh "The Secret to Popular Chinese Web Novels" | 2019 | 中文网文语言特征语料库分析 |
| [6] | Wang et al. "Decoding Online Literature" | 2024 | 中文网文量化语言特征 |
| [7] | Yang & Jin "What Makes a Good Story" (Survey) | 2024 | 故事评估方法综合调查 |
| [8] | Yang & Jin "LongStoryEval" | 2025 | 长篇小说 8 维度评估基准 |
| [9] | Wang et al. "Towards A Novel Benchmark" | 2025 | Macro/Meso/Micro 三级评估 |
| [10] | Chhun et al. "HANNA" | 2022 | 6 正交维度 + 72 自动指标测试 |
| [11] | Li et al. "LLMs-as-Judges" (Survey) | 2024 | LLM 评判方法综合调查 |
| [12] | Fein et al. "LitBench" | 2025 | 创意写作 LLM 评判可靠性基准 |
| [13] | Lu et al. "AHP-Powered LLM Reasoning" | 2024 | AHP + LLM 多维度评估 |
| [14] | Liu et al. "Real-Time Reader Interactions in Chinese Web Novels" | 2025 | 读者互动对网文结构的影响 |
| [15] | Zhao et al. "Consumption of Serial Media Products" | 2023 | 连载阅读行为建模 |
| [16] | Zedelius et al. "Beyond Subjective Judgments" | 2018 | 计算语言特征预测创意写作评估 |
| [17] | Li et al. "LLM Review: Enhancing Creative Writing via Blind Peer Review" | 2026 | LLM 盲审提升创意写作 |

### 业界工具与数据源

| 编号 | 来源 | 类型 | 关键信息 |
|------|------|------|----------|
| [A] | 文镜君 (wenjingjun.cn) | AI 网文鉴评工具 | 4 维度定性评估 |
| [B] | 笔灵 AI (ibiling.cn) | AI 写作辅助 | 字词诊断 + AI 痕迹检测 |
| [C] | ContentAny (aifoxs.com) | 内容分析平台 | 20+ 维度检测 |
| [D] | Chapter Chronicles | 数据分析博客 | 277 部连载 + 1147 条评论分析 |
| [E] | 番茄小说创作指南 | 平台文档 | 完读率核心指标 + 前 3 章考核 |
| [F] | MC Gebhard A/B 测试 | 案例研究 | 章节级 A/B 测试方法论 |
