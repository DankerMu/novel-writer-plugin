## Why

ChapterWriter 和 API Writer 的提示词里把"星界使徒"式的声音 DNA 硬编码了：说书人 Role、"贱嗖嗖的乐观实用主义"主角内心基调、"韭菜移植 / 龟龟 / 哔了狗 / 好家伙 / 得又来"这些具体词汇样本，以及"XX道 / 闻言见状 / 好似犹如 / 顿时赶紧"这套默认对话与节奏词汇。

后果是无论项目题材（玄幻 / 都市 / 悬疑 / 言情），生成的每本小说都会带着同一个说书人的语气和同一个贱嗖嗖主角的内心 OS。`style-profile.json.override_constraints` 只能关 `anti_intuitive_detail` 和 `max_scene_sentences`——**碰不到 voice 层**。

这违反写作工具的中立性：工具应该放大用户选择的风格，而不是把某一本参考小说的 DNA 注射给所有项目。

| 问题 | 当前位置 | 影响 |
|------|----------|------|
| 说书人 Role 硬编码 | `prompts/api-writer-system.md:3` + `agents/chapter-writer.md:34` | 所有项目都是"冷嘲热讽的说书人" |
| 微注入样本硬编码 | `api-writer-system.md:77-82` + `chapter-writer.md:131-136` | "韭菜移植 / 龟龟 / 哔了狗"直接污染模型输出 |
| 主角内心基调硬编码 | `api-writer-system.md:108-113` + `chapter-writer.md:164-169` | "得，又来 / 好家伙 / 行吧，能用"成为所有主角默认 OS |
| 对话标签 / 比喻 / 节奏词硬编码 | `api-writer-system.md:103-116` + `chapter-writer.md:159-173` | "XX道 / 好似 / 顿时"成为固定模板 |
| StyleRefiner 保护逻辑耦合 | `agents/style-refiner.md:73` | 保护项列了"贱嗖嗖内心独白" |
| 评分样例耦合 | `skills/novel-writing/references/quality-rubric.md:149` | 用"好家伙/得嘞"作为打分示例 |

## What Changes

### 1. `style-profile.json` 新增 `voice_persona` 对象

```jsonc
{
  "voice_persona": {
    "narrator_role": "有态度的说书人，自带观点、冷嘲热讽，用不正经比喻消化严肃信息",
    "protagonist_voice_tone": "贱嗖嗖的乐观实用主义——遇危险说'得，又来'，发现新情况说'好家伙'，取得进展说'行吧，能用'",
    "dialogue_tag_preferences": ["沉声道", "随口道", "好奇道", "无奈道", "赶紧道"],
    "rhetoric_preferences_voice": ["好似", "犹如", "宛如"],
    "rhythm_accelerators": ["顿时", "赶紧", "不禁", "登时", "连忙"],
    "voice_lock": false
  }
}
```

- 所有字段**可空**。`voice_lock: false`（默认）时，缺省字段沿用插件内置 fallback（即当前星界使徒默认值），保证老项目不破
- `voice_lock: true` 时，提示词严格遵从 voice_persona，缺省字段视为"无偏好，由模型从样本自行感受"

### 2. `style-samples.md` 新增 `主角内心声音` 和 `叙述者态度` 子节

现有 7 个场景分类保留。新增两节专门承载 voice 样本：
- `## 主角内心声音` — 放主角的吐槽 / 自嘲 / 反应原句
- `## 叙述者态度` — 放叙述者切入叙事的代表性段落

`## 语域微注入` 已存在，继续使用，但**移除**模板里任何偏向特定 voice 的默认提示文案。

### 3. `prompts/api-writer-system.md` + `agents/chapter-writer.md` 改造

两份文件做**对称修改**（它们是镜像）：

- **Role 段**：改写为"你的叙述者态度由 `style-profile.voice_persona.narrator_role` 和 `style-samples.md § 叙述者态度` 定义。以下为通用写作原则……"
- **语域微注入 section**：保留"什么是微注入 / 何时微注入 / 禁忌"三段通用方法论，**删除** 4 条具体样本，改为"见 `style-samples.md § 语域微注入`"
- **正向风格引导 section**：
  - 对话标签：改为"优先使用 `style-profile.voice_persona.dialogue_tag_preferences` 列出的变体，其次参考 style-samples 中的标签用法"
  - 主角内心声音：改为"基调由 `style-profile.voice_persona.protagonist_voice_tone` 定义；具体语气参考 `style-samples.md § 主角内心声音`"
  - 节奏词：改为"使用 `style-profile.voice_persona.rhythm_accelerators` 列出的节奏词，不强求密度"
  - 比喻：改为"优先使用 `style-profile.voice_persona.rhetoric_preferences_voice`"

### 4. Fallback 策略（不破旧项目）

`scripts/api-writer.py` 的 `extract_style_directives()` 扩展：
- 读取 `voice_persona`；若字段为空且 `voice_lock: false`，注入当前硬编码默认值（星界使徒套装）到用户消息的 voice 段，而非系统提示
- 若 `voice_lock: true`，只注入用户填写的字段，缺省字段不 fallback

等价于：**老项目不做任何改动，继续跑；新项目只要设 `voice_lock: true` 就脱离星界使徒**。

### 5. WorldBuilder Mode 7 扩展

`agents/world-builder.md` Mode 7（风格提取）新增产出：
- 从用户样本自动提取 `voice_persona` 各字段（narrator_role / protagonist_voice_tone 从叙述段落和主角心理段总结；dialogue_tag_preferences / rhetoric_preferences_voice / rhythm_accelerators 从词频统计）
- 同步填充 `style-samples.md` 的「主角内心声音」「叙述者态度」两个新子节

### 6. StyleRefiner 保护项解耦

`agents/style-refiner.md:73` 的"贱嗖嗖内心独白"改为"`voice_persona.protagonist_voice_tone` 定义的内心独白风格（或 style-samples § 主角内心声音 中的样本对应风格）"。

### 7. 评分样例解耦

`skills/novel-writing/references/quality-rubric.md:149` 的"好家伙/得嘞"改为"符合 voice_persona 的口语化内心表达"，加脚注引用 voice_persona 示例。

### 8. 预置 Voice Persona 模板（可选增强，不阻塞主线）

`templates/voice-personas/` 新增：
- `snarky-storyteller.json` — 当前星界使徒套装（供喜欢这个风格的用户一键套用）
- `austere-narrator.json` — 冷峻克制（悬疑 / 仙侠）
- `empathetic-observer.json` — 温情抒情（都市 / 言情）
- `epic-chronicler.json` — 史诗叙事（玄幻宏大）

`/novel:start` 初始化时询问用户选择哪个预置，或 `custom`（走 WorldBuilder 提取）。

## Non-Goals

- 不改 Summarizer / QJ / CC 评分维度（tonal_variance 继续存在，但不再依赖硬编码样本作为评分锚点）
- 不改 `ai-blacklist.json`（黑名单本身是中立的 AI 特征词）
- 不动 codex-*.md 评估提示词（探索确认这些文件不含硬编码 voice DNA）

## Migration

- 旧项目：`voice_persona` 字段缺失 → fallback 注入星界使徒默认值 → 行为与改造前一致
- 新项目：`/novel:start` 第一轮询问时选预置或 custom，`style-profile.json` 初始化即带上 `voice_persona`

## Success Criteria

1. 将 `voice_persona` 改为 `epic-chronicler` 后写的章节，QJ 评分中 tonal_variance ≥ 4.0 仍可达成，且正文不含"好家伙 / 得又来 / 哔了狗 / 龟龟"等星界使徒特征词
2. 老项目（无 voice_persona 字段）生成的章节 diff 与改造前 < 5%（fallback 路径等价）
3. 全插件 grep "星界使徒 / 韭菜移植 / 龟龟" 只在 `templates/voice-personas/snarky-storyteller.json` 的示例字段中出现（或在 plugin-patch-plan.md 历史文档中），不再出现在任何运行时提示词 / agent 定义 / skill 文档里

## Out of Scope / Future Work

- Voice persona 跨卷演化（主角成长导致 voice tone 变化）不在此 PR 范围，留到未来作为 M-future 处理
- 多 POV 时每个 POV 角色独立 voice_persona 暂不支持，v1 只支持项目级单一 voice_persona
