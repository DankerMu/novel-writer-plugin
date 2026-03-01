# 伏笔追踪（事实索引 + 卷内计划）

> 本文用于约束 `/novel:continue` 的 **foreshadowing_tasks 注入** 与 **commit 阶段 global.json 合并**。
> 源头定义：`docs/dr-workflow/novel-writer-tool/final/prd/09-data.md`（schema 示例）与 `docs/dr-workflow/novel-writer-tool/final/spec/06-extensions.md`（query-foreshadow.sh 扩展点）。

## 1) `foreshadowing/global.json`（事实层，跨卷）

最小格式（JSON object）：

```json
{
  "foreshadowing": []
}
```

条目 schema（每个 item）：

```json
{
  "id": "ancient_prophecy",
  "description": "远古预言暗示主角命运",
  "scope": "short | medium | long",
  "status": "planted | advanced | resolved",
  "planted_chapter": 3,
  "planted_storyline": "main-arc",
  "target_resolve_range": [10, 20],
  "last_updated_chapter": 48,
  "history": [
    {"chapter": 3, "action": "planted", "detail": "…"},
    {"chapter": 15, "action": "advanced", "detail": "…"},
    {"chapter": 48, "action": "advanced", "detail": "…"}
  ]
}
```

语义规则：

- `status` 仅允许：`planted` → `advanced`（可多次）→ `resolved`。
- `scope` 分层语义（用于风险提示，而不是强制门控）：
  - `short`：卷内（约 3-10 章）应回收；**超期**规则见 §4。
  - `medium`：跨 1-3 卷回收。
  - `long`：全书级，无固定回收期限（**不触发超期警告**）。
- `target_resolve_range`：
  - 可缺失（表示未设定明确回收窗口）。
  - 若存在，必须是 `[start, end]` 且 `start/end` 为整数、`start <= end`。
- `history[]`：
  - `action` ∈ `{"planted","advanced","resolved"}`。
  - 允许多次 `advanced`（不同 chapter）。
  - 建议按 `chapter` 升序；commit 阶段追加即可（无需重排）。

## 2) `volumes/vol-{V:02d}/foreshadowing.json`（计划层，本卷）

用途：
- 提供本卷“新增 + 延续”的伏笔计划基线，用于：
  1) 组装 `foreshadowing_tasks`（章节写作注入）
  2) 卷末回顾对照（计划 vs 事实）

建议格式（JSON object；`volume` 可选）：

```json
{
  "volume": 2,
  "foreshadowing": [
    {
      "id": "ancient_prophecy",
      "description": "远古预言暗示主角命运",
      "scope": "long",
      "status": "advanced",
      "planted_chapter": 3,
      "target_resolve_range": [40, 55],
      "history": []
    }
  ]
}
```

说明：
- 计划层条目字段允许与 global 结构一致（便于复用与对照），但它不是事实源：
  - 对“本卷新增伏笔”，`planted_chapter/target_resolve_range` 表示**计划章范围**；
  - 对“上卷延续伏笔”，`planted_chapter/status` 应与 global 事实一致，`target_resolve_range` 可被 PlotArchitect 调整为本卷计划窗口。

## 3) Commit 阶段：从 `staging/state/chapter-{C:03d}-delta.json` 合并 foreshadow ops → `foreshadowing/global.json`

输入：`staging/state/chapter-{C:03d}-delta.json.ops[]` 中 `op == "foreshadow"` 的记录：

```json
{"op":"foreshadow","path":"ancient_prophecy","value":"advanced","detail":"主角梦见预言碎片"}
```

合并策略（幂等、去重、不中断写作）：

1. 读取 `foreshadowing/global.json`；若不存在则初始化为 `{"foreshadowing":[]}`。
2. 读取（可选）本卷计划 `volumes/vol-{V:02d}/foreshadowing.json`，用于在 global 缺条目/缺元数据时补齐 `description/scope/target_resolve_range`（**仅在缺失时回填，不覆盖已有事实字段**）。
3. 对每条 `foreshadow` op（按 ops 顺序处理）：
   - `id = path`，`action = value`，`detail = detail || ""`
   - 找到对应 item（按 `id` 精确匹配）；若不存在则创建：
     - `id`: op.path
     - `description/scope/target_resolve_range`: 优先从本卷计划同 ID 条目回填；否则写入占位（`description = id`，`scope = "medium"`，`target_resolve_range = null`）
     - `planted_chapter`: 若 `action=="planted"` 则写入 `C`，否则留空
     - `planted_storyline`: 从 delta 顶层 `storyline_id` 回填（如存在）
     - `status`: 先设为 `action`
     - `last_updated_chapter = C`
     - `history = []`
   - `history` 去重（保证重复 commit 不重复追加）：
     - 若已存在 `{chapter: C, action: action}` 的记录 → 跳过追加
     - 否则追加 `{chapter: C, action: action, detail: detail}`
   - 字段更新：
     - `last_updated_chapter = max(existing, C)`
     - `planted_chapter`：若 `action=="planted"` 且为空 → 设为 `C`（不回退更早 planted）
     - `planted_storyline`：若为空且 delta.storyline_id 存在 → 设为该值
     - `status`：只允许单调推进：
       - 若 `action=="resolved"` → 设为 `resolved`
       - 若 `action=="advanced"` 且当前非 `resolved` → 设为 `advanced`
       - 若 `action=="planted"` 且当前为空/`planted` → 设为 `planted`（不得把 `advanced/resolved` 降级为 `planted`）
4. 写回 `foreshadowing/global.json`（JSON，UTF-8）。
5. 若遇到异常数据（例如 action 非法、JSON 解析失败、global.json 结构不是 object/foreshadowing 不是 list）：
   - 不要悄悄吞掉：输出明确错误与修复建议；
   - 但**尽量避免阻断整章 commit**：可降级为“跳过本章 foreshadow 合并并写入 warning”，保证章节与 state 合并仍可完成。

## 4) Overdue（超期）判定（用于 `/novel:dashboard` 与回顾报告）

- 仅对 `scope == "short"` 且 `status != "resolved"` 的条目做超期提示。
- 若存在 `target_resolve_range = [start, end]` 且 `last_completed_chapter > end`：标记为 **超期**。
- `scope == "long"`：不做超期提示。

## 5) `${CLAUDE_PLUGIN_ROOT}/scripts/query-foreshadow.sh`（可选确定性扩展点）

- 输入：`<chapter_num>`
- 输出：stdout JSON（exit 0），其中 `.items` 为“本章相关伏笔条目子集”（list of objects，字段建议与 global 条目一致：`id/description/scope/status/target_resolve_range/...`）
- 失败回退：脚本不存在 / 退出码非 0 / stdout 非 JSON / JSON 缺 `.items` → 不阻断流水线，入口 Skill 必须回退规则过滤（见 `skills/continue/SKILL.md` Step 2.5 第 6 项）
