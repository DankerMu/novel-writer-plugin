# Voice Persona 预置包

每份 JSON 定义一套"声音基调"——叙述者态度 + 主角内心语气 + 对话标签 / 比喻 / 节奏词默认偏好。`/novel:start` 初始化时可选一套作为起点，或选 `custom` 走 WorldBuilder Mode 7 从样本自动提取。

## 4 套预置

| 预置 | 适合题材 | 叙述者 | 主角基调 |
|------|----------|--------|----------|
| [snarky-storyteller](snarky-storyteller.json) | 都市异能、轻科幻、穿越日常、带吐槽属性的玄幻 | 有态度的说书人，自带冷嘲热讽 | 贱嗖嗖的乐观实用主义 |
| [austere-narrator](austere-narrator.json) | 仙侠、悬疑、硬派玄幻、传统修真、冷色调末世 | 冷峻克制的观察者 | 沉静内敛的理性审视 |
| [empathetic-observer](empathetic-observer.json) | 都市言情、青春校园、家庭伦理、轻治愈、年代文 | 温情的共情旁白者 | 细腻共情的内省 |
| [epic-chronicler](epic-chronicler.json) | 宏大玄幻、洪荒、仙侠史诗、传统东方奇幻 | 史诗叙事者 | 宿命感浓重的自觉 |

## 如何使用

### 方式 A：`/novel:start` 交互选择

在平台选择之后的 Step B 会询问"选择声音基调"，5 个选项（4 预置 + custom）。选预置后自动合并到 `style-profile.json.voice_persona`。

### 方式 B：手动合并

1. 打开选中的预置 JSON，复制 `voice_persona` 对象
2. 粘贴到项目 `style-profile.json` 里，覆盖同名字段
3. 预置里的 `_preset_name` / `_description` / `_how_to_use` 等下划线开头字段是说明，不需要复制到 style-profile.json

### 方式 C：custom 模式

1. 把 `style-profile.json.voice_persona.voice_lock` 设为 `true`
2. 将你想要模仿的作者样本放到 `style-samples-raw/` 目录
3. 跑 WorldBuilder Mode 7，自动提取 voice_persona 各字段 + 填充 `style-samples.md`

## voice_lock 开关行为

| voice_lock | 字段行为 |
|------------|---------|
| `false`（默认） | 缺省字段 fallback 到 `snarky-storyteller` 的插件内置默认值——保证老项目不破 |
| `true` | 缺省字段视为"无偏好，由模型从 style-samples 自行感受"——适合走 custom 路线的新项目 |

## 自定义预置

想做自己的预置？照 4 份预置的字段结构写一个 JSON，放到本目录或项目的 `.voice-personas/` 都可以。预置只是方便复用，本质是 `voice_persona` 对象的初始化数据。
