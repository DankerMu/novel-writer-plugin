# 插件修改方案：语域微注入 + 去 AI 均匀化（v2）

> **核心问题**：ChapterWriter 产出语域均匀，缺乏星界使徒式"一句话跳"的语域微注入。
> **核心洞察**：语域切换不是场景级节拍切换，是句子级微注入——"韭菜移植"4 个字、"龟龟，这也太孝了"一句话就跳。教声音，不教规则。
>
> 插件根目录：`~/.claude/plugins/cache/cc-novel-writer/novel/2.3.0/`（下文用 `$PLUGIN` 指代）
> 项目目录：`~/Desktop/novel/novel-11/`（下文用 `$PROJECT` 指代）

---

## 修改总览

| # | 决策 | 涉及文件 | 操作 | 优先级 |
|---|------|---------|------|--------|
| 1 | CW 拆分为 Creative + Refiner（纯机械合规） | `$PLUGIN/agents/chapter-writer.md`（改）、`$PLUGIN/agents/style-refiner.md`（新建）、`$PLUGIN/skills/continue/SKILL.md`（改）、`$PLUGIN/skills/continue/references/context-assembly.md`（改）、`$PLUGIN/skills/continue/references/gate-decision.md`（改） | 架构级 | P0 |
| 2 | style-samples 补语域微注入样本 | `$PROJECT/style-samples.md`（改） | 内容 | P0 |
| 3 | 黑名单移除白名单词 | `$PROJECT/ai-blacklist.json`（改）、`$PROJECT/style-profile.json`（改） | 数据 | P0 |
| 4 | QJ 加 tonal_variance 维度 | `$PLUGIN/agents/quality-judge.md`（改）、`$PLUGIN/skills/novel-writing/references/quality-rubric.md`（改）、`$PLUGIN/skills/continue/references/gate-decision.md`（改） | 评估 | P1 |

> **已移除**：~~决策 2c（章节契约加节拍语域表）~~——语域切换是句子级微注入（"韭菜移植"4 个字就跳），PlotArchitect 规划不了也不该规划这个粒度。契约保持剧情导向，不侵入写作微操。
>
> **已移除**：~~决策 2b（正向频率硬规则）~~——"闻言 ≥ 2 次/章"这类硬性下限会导致机械凑数，与砍掉"四字词组密度上限"是同一个陷阱的镜像。改为 CW prompt 中的定性声音引导 + QJ tonal_variance 事后检测。

---

## 决策 1：CW 拆分 — Creative Writer + Style Refiner

### 核心理由

CW 当前 prompt 同时包含创作指令和去 AI 化规则（黑名单、句式禁止等）。模型在创作阶段会隐性回避黑名单近义词和相关表达模式，导致输出趋于"安全均匀"。拆分后 CW 完全看不到黑名单和合规规则，释放创作自由度；Refiner 只做机械合规，不碰创意。

### 1.1 改：`$PLUGIN/agents/chapter-writer.md`

**原文**：254 行，Phase 1（创作）+ Phase 2（润色）合体。

**改后目标**：~120-140 行，只负责 Phase 1 创作 + 语域微注入声音引导。

#### 删除的部分

- 整个 `## Phase 2: 润色（去 AI 化）` section（原 L112-176）
- `### Phase 2 约束` section（原 L141-157）
- `### Phase 2 额外输出` section（原 L158-176）
- Constraints 中所有润色相关条目（移入 Refiner）：
  - #13 破折号禁止
  - #16 句长方差意识
  - #17 叙述连接词零容忍
  - #19 AI 句式原型约束（CW 仅保留"不是A是B"零容忍提醒）
  - #20 比喻密度约束
- 输入说明中的 `polish_only` 相关逻辑（移入 Refiner）
- 输入说明中的 `paths.ai_blacklist`（**关键**：CW 不再看到黑名单）
- 输入说明中的 `paths.style_guide`（合规方法论移入 Refiner）
- 输入说明中的 `ai_blacklist_top10`（**关键**：消除隐性回避）
- Edge Cases 中的 polish_only / 二次润色 / 黑名单零命中等条目

#### 新增 Section：`## 语域微注入（Register Micro-Injection）`

位置：插在 `# Process` 之后、`# Constraints` 之前。

```markdown
## 语域微注入（Register Micro-Injection）

星界使徒式写作的核心 DNA 不是"场景切换时变语气"，是**随时一句话就跳**。

### 什么是微注入

在任何语域的连续段落中，用一句话、一个词、一个比喻突然切到反向语域，
不需要换场景，不需要过渡句，不需要"然而气氛却……"。

实际样本（详见 `style-samples.md § 语域微注入`）：
- 正经世界观叙述 → "韭菜移植……星际移民制度确立了"（4 个字跳）
- 全家严肃对峙 → "就算我挺帅的，也别一直看啊"（一句话跳）
- 千字设定段 → "不是这么霉吧……"（6 个字回到个人）
- 沉重家庭抉择 → "龟龟，这也太孝了"（5 个字变黑色幽默）
- 战略正统叙述 → "更是心里哔了狗"（半句话跳）

### 何时微注入

不设字数规则。按直觉：当你写了一段连续同调的内容，感觉"该换换了"，
就在下一个自然断点插入主角（或叙述者）的反向语域反应：

- 写完一段紧张/血腥 → 主角内心一句口语吐槽（"得，又来""好家伙"）
- 写完一段日常/搞笑 → 一句冷硬短句判断（"不对劲。""记下来了。"）
- 写完一段信息/设定 → 一个身体动作或感官反应替代认知总结
- 角色说了一段正经话 → 主角内心翻白眼或自嘲一句

### 禁忌

- 禁止用旁白解释语域切换（"虽然刚才很紧张，但他很快恢复了轻松"）
- 禁止"不是X，是Y"式心理注释——直接写动作/反应，信任读者
- 禁止所有角色都"正常说话"——至少有一个角色带夸张/互怼/批话表达
```

#### 新增 Section：`## 正向风格引导（Voice Direction）`

位置：紧接语域微注入之后。

```markdown
## 正向风格引导（Voice Direction）

以下是这个声音的自然表达习惯，不是配额，不用数数。
写的时候让它们自然出现，风格自检时确认没有系统性缺失。

### 对话标签体系
- 偏好"XX道"变体（沉声道、随口道、好奇道、无奈道、赶紧道）而非裸的"说""说道"
- "闻言""见状"是自然的反应起手式，不必刻意回避也不必刻意凑
- 比喻首选"好似"，其次"犹如""宛如"

### 主角内心声音
基调是**贱嗖嗖的乐观实用主义**：
- 遇到危险 → 不是恐惧分析，是"得，又来"
- 发现新情况 → 不是理性推演，是"好家伙"然后直接行动
- 别人装逼/说教 → 内心翻白眼，表面配合
- 取得进展 → 不是感悟人生，是"行吧，能用"

### 节奏加速词
"顿时""赶紧""不禁""登时""连忙"等是这个声音的自然节奏标记，
写到需要加速的地方自然用，不需要计数。

### 自检方法
完成正文后通读一遍，问自己：
1. 这章有没有让我笑出来或嘴角上扬的地方？（微注入是否存在）
2. 对话读起来是不是所有人都在"正常交流"？（是否缺少互怼/吐槽/批话）
3. 主角内心是在"分析局势"还是在"活人反应"？（是否过于理性化）
如果三个答案都是否/是/分析，回去补微注入。
```

#### 修改 Process 步骤

原步骤 9（风格自检）改为：

```markdown
9. **风格自检（双向）**：完成正文后执行两项检查：
   a. 抽取 3 个段落与 `style-samples.md` 中对应场景类型的样本对比——
      节奏感、用词密度或句式结构明显偏离则定向修改
   b. 通读全文执行「正向风格引导」的三问自检——
      缺少微注入的地方定向补入
```

删除原步骤 10 中 Phase 2 相关提示。

#### 修改 Constraints

保留的约束（重新编号）：

1. 字数：2500-3500
2. 情节推进
3. 角色一致
4. 衔接自然
5. 视角一致
6. 故事线边界
7. 角色注册制
8. 切线过渡
9. 风格样本锚定（保留，创作核心）
10. 角色区分
11. 反直觉细节
12. 场景描写精简
13. 对话格式（中文双引号）
14. **新增**：语域微注入——引用上面的 section，定性引导，非字数规则
15. **新增**："不是A是B"零容忍——动作/情绪后禁止追加否定-肯定式心理注释，直接写动作，信任读者

删除移入 Refiner 的约束：破折号禁止、句长方差、叙述连接词、AI 句式原型（完整版）、比喻密度、人性化技法自然融入、禁止分隔线

#### 修改 Format

删除 Phase 2 额外输出，CW 只输出：

1. 章节正文 → `staging/chapters/chapter-{C:03d}.md`
2. 可选状态变更提示 JSON

---

### 1.2 新建：`$PLUGIN/agents/style-refiner.md`

**定位**：纯机械合规层 Agent。接收 CW 初稿，执行去 AI 化清洗。不碰创意，不做语域审计，不插入内容。

**模型**：`sonnet`（纯机械操作不需要 Opus 创意能力；若验证阶段发现不够再升级）

**颜色**：`green`（与 CW 共享——两者严格顺序执行，永远不会并发；概念上 Refiner 是 CW 的"后处理"阶段）

**Frontmatter**：

```yaml
---
name: style-refiner
description: |
  去 AI 化合规 Agent — 接收 ChapterWriter 初稿，执行黑名单扫描、AI 句式清除、
  格式统一等机械合规润色，输出终稿。不改变情节、角色行为和语域节奏。
model: sonnet
color: green
tools: ["Read", "Write", "Edit", "Glob", "Grep"]
---
```

**输入**：

- `paths.chapter_draft` → CW 产出的初稿（`staging/chapters/chapter-{C:03d}.md`）
- `paths.style_samples` → 风格样本（替换时参照目标风格方向）
- `paths.style_profile` → 风格指纹 JSON
- `paths.ai_blacklist` → AI 黑名单 JSON
- `paths.style_guide` → 去 AI 化方法论
- `paths.style_drift` → 风格漂移纠偏（可选）
- `style_drift_directives` → inline 纠偏指令（可选）

**Process（从原 CW Phase 2 提取，仅保留机械操作）**：

**P0 前置清洗（无条件执行）**：

- 模型 artifact 清除（`<thinking>` 等 XML 标签）
- 元信息泄漏清除（F-XXX、W-XXX、snake_case 字段等）
- 术语一致性检查（若 `world/terminology.json` 存在）
- 引号格式统一（→ 中文双引号）
- 格式规则检查（`scripts/lint-format.sh`）

**合规步骤**：

1. **风格参照建立**：回顾 `style-samples.md`，建立替换方向感知
2. **漂移纠偏**（若有 `style_drift_directives`）
3. **黑名单扫描替换**：全文标记命中（忽略 exemptions），逐个替换为风格相符表达
4. **标点频率修正**：破折号零容忍全部替换；省略号 ≤ 2/千字
5. **叙述连接词清除**：叙述段落（引号外）中的 narration_connector 类词条替换为动作衔接/视角切换/段落断裂
6. **AI 句式原型扫描替换**：5 类 AI 句式（作者代理理解/模板化转折/抽象判断/书面腔入侵/否定-肯定伪深度）
7. **比喻密度扫描**：每段 ≤ 1 个，每千字 ≤ 3 个
8. **重复句式检查**：相邻 5 句内无重复句式模式
9. **修饰词去重**（轻量版）：3 句内同一修饰词完全重复时替换
10. **分隔线删除**：`---` / `***` / `* * *` → 空行
11. **通读确认**：语义未变、角色语癖未改、**语域微注入未被磨平**

**精简掉的步骤（过度微操，收益低，干扰大）**：

- ~~四字词组密度控制~~（正常中文自然使用四字词组，硬性上限导致刻意回避成语）
- ~~形容词/副词密度控制~~（导致描写干瘪）
- ~~感叹号频率控制~~（战斗/惊讶场景自然需要感叹号，硬性上限适得其反）
- ~~语域审计~~（语域是 CW 的创作责任 + QJ 的评估责任，Refiner 不碰创意层面）

**关键约束**：

- **不插入内容**：Refiner 只替换/删除，不新增句子或段落
- **保护微注入**：CW 插入的口语吐槽、网络梗、贱嗖嗖内心独白即使不够"文学"也**不得修改**——这是有意为之的语域切换，不是 AI 错误
- **语义不变**：严禁改变情节、对话内容、角色行为、伏笔暗示
- **状态保留**：保留所有状态变更细节，确保 Summarizer 基于初稿产出的 state ops 与终稿一致
- **对话保护**：角色对话中的语癖和口头禅不可修改

**输出**：

1. 润色后正文 → 覆写 `staging/chapters/chapter-{C:03d}.md`
2. 修改日志 → `staging/logs/style-refiner-chapter-{C:03d}-changes.json`（格式与现有一致）

---

### 1.3 改：`$PLUGIN/skills/continue/SKILL.md`

**核心改动**：流水线从 `CW → Summarizer → QJ+CC` 变为 `CW → StyleRefiner → Summarizer → QJ+CC`。

#### Step 3 流水线修改

原来：

```
1. ChapterWriter Agent → 生成初稿 + 润色（Phase 1 + Phase 2）
```

改为：

```
1. ChapterWriter Agent → 生成初稿（Phase 1 纯创作 + 微注入，无合规润色）
   输入: chapter_writer_manifest（不含 ai_blacklist / style_guide / ai_blacklist_top10）
   输出: staging/chapters/chapter-{C:03d}.md（+ 可选 hints）

1.5. StyleRefiner Agent → 机械合规润色
   输入: style_refiner_manifest（paths: chapter_draft + style_samples + style_profile + ai_blacklist + style_guide + style_drift；inline: style_drift_directives）
   输出: staging/chapters/chapter-{C:03d}.md（覆写）+ staging/logs/style-refiner-chapter-{C:03d}-changes.json
```

#### pipeline_stage 枚举更新

新增 `refining` / `refined` 阶段：

| stage | 含义 | 恢复策略 |
|-------|------|----------|
| `null` / `committed` | 无中断 | 从 `last_completed_chapter + 1` 开始 |
| `drafting` | CW 执行中 | 检查 staging 文件决定恢复点 |
| `refining` | StyleRefiner 执行中 | 从 StyleRefiner 重启 |
| `refined` | StyleRefiner 完成 | 从 Summarizer 恢复 |
| `drafted` | Summarizer 完成 | 从 QJ+CC 恢复 |
| `judged` | QJ+CC 完成 | 执行门控+commit |
| `revising` | CW 修订中 | 从 CW 重启 |

#### 中断恢复逻辑更新（Step 1.5）

新增 `refining` 恢复：

- `pipeline_stage == "refining"`：
  - 若 `staging/logs/style-refiner-chapter-{C:03d}-changes.json` 不存在 → 从 StyleRefiner 重启
  - 若已存在 → 从 Summarizer 恢复

#### checkpoint 更新时机

- CW 完成后：`pipeline_stage = "refining"`
- StyleRefiner 完成后：`pipeline_stage = "refined"`
- Summarizer 完成后：`pipeline_stage = "drafted"`（不变）

#### 门控修订循环

gate_decision="revise" 时：

```
ChapterWriter(revision) → StyleRefiner → [QJ + CC 并行] → 门控 → Summarizer（pass/polish only）
```

gate_decision="polish" 时：

```
StyleRefiner(polish_only) → commit（不再重复 QJ/CC）
```

> polish_only 逻辑从 CW 移入 StyleRefiner。

---

### 1.4 改：`$PLUGIN/skills/continue/references/context-assembly.md`

#### 新增 StyleRefiner manifest 组装

```markdown
### StyleRefiner Context Manifest

**inline 计算值**：
- chapter_num, volume_num
- style_drift_directives（可选）

**路径**：
- paths.chapter_draft → staging/chapters/chapter-{C:03d}.md（CW 初稿）
- paths.style_samples → style-samples.md（如存在）
- paths.style_profile → style-profile.json
- paths.ai_blacklist → ai-blacklist.json
- paths.style_guide → 去 AI 化方法论
- paths.style_drift → style-drift.json（如 active=true）
```

#### ChapterWriter manifest 修改

- **移除** `paths.ai_blacklist`
- **移除** `paths.style_guide`
- **移除** `ai_blacklist_top10`（inline）
- 保留其余路径不变

---

## 决策 2：style-samples 补语域微注入样本

### 改：`$PROJECT/style-samples.md`

在文件末尾新增 section：

```markdown
---

## 语域微注入（Register Micro-Injection）

> 星界使徒最核心的风格 DNA——不是"场景切换时变语气"，是**随时一句话就跳**。
> 以下样本展示的不是"某种语域的写法"，而是**跳转本身**：4 个字、一句话、
> 一个比喻，在任何语域中突然切到反向。ChapterWriter 写作时，当连续段落
> 调性趋于均匀，回忆这些样本中"跳"的手感。

### 样本 1——正经世界观叙述中的 4 字微注入

    人和韭菜具有许多的共性，生生不息、割割不绝，但前提是种下了种子。而每一个新的殖民星球需要大量人力开发、繁衍，于是在星际联合共同体的决策下，韭菜移植……星际移民制度确立了。

> **微注入点**："韭菜移植"4 个字——前面是正经的文明史叙述，
> "韭菜移植"一出来立刻变成辛辣讽刺，省略号后又回到正经。
> 不需要过渡，不需要"虽然这听起来讽刺但……"

### 样本 2——严肃家庭对峙中的自恋吐槽

    周靖笑了笑，这才扭头看向父亲母亲和两位哥哥，发现四人的神色十分严肃。

    唔，气氛怪怪的，盯着我干嘛，就算我挺帅的，也别一直看啊……

> **微注入点**：全家气氛凝重到极点 → 一句自恋式吐槽打破。
> 没有"他试图缓解紧张"，没有"故作轻松"，直接跳。

### 样本 3——千字设定段后的 6 字个人反应

    （前面 800 字星际移民制度详细说明）

    "不是这么霉吧……"

    周靖心情沉了下去。

> **微注入点**：800 字硬核设定 → "不是这么霉吧"6 个字回到个人。
> 读者注意力从宏观世界观瞬间拉回主角主观感受。

### 样本 4——沉重抉择中的现代网络梗

    拆开父母，说服他们其中一人去？龟龟，这也太孝了……

> **微注入点**："龟龟"+"太孝了"——正在被迫离开家人的场景，
> 用网络梗自嘲。痛苦和幽默同时存在，这就是这个声音。

### 样本 5——战略正统叙述中的半句粗口

    朝廷虽有心援助，可周靖行动太快，他们难以插手。

    当初参与密谋暗害谭鹏的朝廷使者，更是心里哔了狗。

> **微注入点**：前面是"朝廷虽有心援助"正统战略文，
> "哔了狗"半句话就跳。连叙述者的声音都在跳，不只是角色内心。

### 样本 6——血腥修罗场后的旁观者疑问

    周靖浑身浴血，收枪而立，面无表情，但满脸沾着血点，狰狞好似修罗。

    轻而易举屠戮大批江湖高手，此时还能闲庭信步……这真不是妖魔吗？

    人能把武功练到这种地步？！

> **微注入点**：极致暴力画面 → 旁观者日常困惑式吐槽。
> "这真不是妖魔吗？"把恐怖片变成黑色喜剧视角。

### 样本 7——官僚描述中的一个形容词

    星际移民局最喜欢的，就是他这种在当地没有稳定事业或工作的粉嫩嫩青年劳动力。

> **微注入点**："粉嫩嫩"——整句是冰冷的官僚视角，
> 一个形容词注入自嘲和无奈。
```

---

## 决策 3：黑名单移除白名单词

### 改：`$PROJECT/ai-blacklist.json`

从顶层 `words[]` 数组中移除 `style-profile.json` 的 `override_constraints.whitelist_from_blacklist` 中列出的所有词（约 22 个）：

```
移除列表：
- "不禁"、"莫名"、"好似"、"顿时"、"一时间"
- "沉声道"、"深吸一口气"、"与此同时"
- "犹如"、"宛如"、"宛若"
- "点了点头"、"摇了摇头"、"眉头微皱"
- "不由自主"、"微微一笑"、"心中涌起"
- "然而"、"因此"（仅从 words[] 移除；narration_connector 分类中保留，叙述文中仍应避免）
- "——"（保留！破折号零容忍不变）
```

同时从对应 `categories` 中移除：

- `simile_cliche`: 移除 "好似"、"犹如"、"宛如"、"宛若"
- `emotion_cliche`: 移除 "不禁"、"莫名"
- `action_cliche`: 移除 "深吸一口气"、"沉声道"、"微微一笑"、"点了点头"、"摇了摇头"、"眉头微皱"、"不由自主"
- `time_cliche`: 移除 "顿时"、"一时间"
- `transition_cliche`: 移除 "与此同时"

> `narration_connector` 分类中的 "然而"、"因此" **保留**（叙述文中仍禁止通过 Refiner 处理）。

### 改：`$PROJECT/style-profile.json`

删除 `override_constraints.whitelist_from_blacklist` 字段（不再需要，词已从黑名单移除）。

---

## 决策 4：QJ 加 tonal_variance 维度

### 改：`$PLUGIN/agents/quality-judge.md`

#### Track 2 从 8 维度变为 9 维度

| 维度 | 原权重 | 新权重 | 评估要点 |
|------|--------|--------|---------|
| plot_logic | 0.18 | 0.16 | 不变 |
| character | 0.18 | 0.16 | 不变 |
| immersion | 0.15 | 0.13 | 不变 |
| foreshadowing | 0.10 | 0.09 | 不变 |
| pacing | 0.08 | 0.08 | 不变 |
| style_naturalness | 0.15 | 0.12 | 保留核心子指标，精简掉过度微操的 3 个 |
| emotional_impact | 0.08 | 0.08 | 不变 |
| storyline_coherence | 0.08 | 0.08 | 不变 |
| **tonal_variance** | — | **0.10** | 语域微注入密度、内心独白口语度、连续同调最大长度、对话活力 |

#### tonal_variance 评分标准

```markdown
**5 分**：微注入自然且频繁——全章无超过 800 字的连续同调段；
内心独白以口语/吐槽/自嘲为主（非分析性语言）；
对话中至少有一组角色间互怼/批话/夸张表达

**4 分**：微注入存在但偶有间隔——有 1 处超过 800 字的连续同调段；
内心独白大部分口语化，偶有书面分析；
对话基本有角色区分但互怼感不强

**3 分**：微注入稀疏——有 2+ 处超过 800 字的连续同调段，或
全章内心独白偏书面化（"他意识到……""他明白……"多于"好家伙""得嘞"）；
对话趋于"所有人都在正常交流"

**2 分**：全章基本单一调性——>80% 段落为同一语域；
内心独白近乎不存在或全为理性分析；
无任何互怼/吐槽/自嘲

**1 分**：完全没有语域变化——通篇读起来像报告或百科
```

#### tonal_variance 评估方法

```markdown
1. **微注入密度**：通读全文，标记每处语域跳转（一句话、一个词、一个比喻
   实现的调性突变）。全章 ≥ 5 处为正常，< 3 处为稀疏
2. **内心独白口语度**：统计非对话心理段中口语/网络梗/吐槽/自嘲的比例
   vs 书面分析（"他意识到""他判断"）的比例
3. **连续同调最大长度**：找出全文最长的连续同一语域段（估算字数），
   > 1000 字为明显问题
4. **对话活力**：是否存在角色间互怼、批话、夸张表达，还是所有人都在
   "信息传递式"对话
```

#### style_naturalness 精简

删除的子指标（过度微操，与 Refiner 精简对齐）：

- ~~四字词组密度~~
- ~~形容词密度~~
- ~~感叹号频率~~

保留核心子指标：黑名单命中率、句式重复率、句长标准差、段落长度 CV、叙述连接词密度、比喻密度、AI 句式原型计数、style-profile 综合匹配、对话区分度

#### 门控硬门新增

在 `gate-decision.md` 中新增：

```markdown
# Step A 补充：tonal_variance 硬门
if scores.tonal_variance.score < 3.0:
    qj_decision = max_severity(qj_decision, "revise")
```

语域方差低于 3.0 直接触发修订——"写得均匀"的章节不可能通过门控。

#### 输出 JSON 格式更新

scores 对象新增 tonal_variance：

```json
"tonal_variance": {
  "score": 3,
  "weight": 0.10,
  "reason": "全章 80% 段落为 restrained 语域，内心独白偏分析性",
  "evidence": "最长连续同调段约 1000 字（L50-L110），仅 2 处微注入",
  "sub_metrics": {
    "micro_injection_count": 2,
    "inner_monologue_casual_ratio": 0.3,
    "max_same_register_length_approx": "~1000字",
    "dialogue_has_banter": false
  }
}
```

### 改：`$PLUGIN/skills/novel-writing/references/quality-rubric.md`

追加 tonal_variance 评分细则（如上述评分标准），与现有维度同级新增。

---

## 实施顺序

```
阶段 1（最小可验证，不改架构，1 章验证）：
  ├─ 2. style-samples.md 补语域微注入样本
  ├─ 3. ai-blacklist.json 移除白名单词 + style-profile.json 删 whitelist
  └─ 验证：用当前 CW（未拆分）重写第 4 章，对比效果

阶段 2（架构改动）：
  ├─ 1.1 chapter-writer.md 重写（砍 Phase 2，加微注入引导 + 正向风格引导）
  ├─ 1.2 style-refiner.md 新建（纯机械合规）
  ├─ 1.3 SKILL.md 流水线更新
  ├─ 1.4 context-assembly.md 更新
  └─ 验证：用新流水线写第 6 章，对比效果

阶段 3（评估校准）：
  ├─ 4. quality-judge.md 加 tonal_variance 维度
  ├─    quality-rubric.md 追加评分细则
  ├─    gate-decision.md 追加硬门
  └─ 验证：QJ 重评第 4-6 章，确认评分校准

阶段 4（已有章节修订）：
  └─ 用新流水线修订第 4、5 章
```

---

## 风险与缓解

| 风险 | 缓解 |
|------|------|
| StyleRefiner 磨平 CW 的语域微注入 | Refiner 约束明确"保护微注入"——口语吐槽、网络梗、贱嗖嗖内心独白不得修改；通读确认步骤专项检查 |
| CW 微注入引导导致堆砌网络梗 | 引导是定性的"声音方向"不是配额；三问自检兜底；QJ tonal_variance 会识别"刻意凑数"（切换不自然扣分） |
| QJ tonal_variance 评估主观性大 | 给出可观测子指标（微注入计数/同调最大长度/独白口语比/对话活力），减少主观判断空间 |
| 黑名单移除白名单词后 AI 痕迹回升 | 移除的是原作者高频词（闻言/顿时/好似等），回升的是"人味"不是"AI味"；真 AI 词（油然而生/瞳孔骤缩/心中不禁涌起等）仍在黑名单 |
| Sonnet 做 Refiner 质量不够 | Refiner 是纯机械操作（替换/删除），不需要创作能力；验证阶段如发现黑名单替换质量差再升 Opus |
| Pipeline 新增阶段增加延迟和成本 | Refiner 用 Sonnet（成本约 Opus 的 1/5）；阶段 1 先验证"仅补样本+清黑名单"的效果，确认值得再做架构拆分 |
