# M3 风格漂移与黑名单（文件协议）

**1) `style-drift.json`（项目根目录，可选）**

- 用途：当检测到风格漂移时写入，用于后续章节对 ChapterWriter 进行"正向纠偏"注入
- 注入规则：仅当 `active=true` 时注入；`active=false` 视为历史记录，不再注入
- 注入目标：当前固定为 `["ChapterWriter"]`；若未来新增消费方，需扩展 `injected_to` 并同步 Step 2.6 context assembly

最小格式：
```json
{
  "active": true,
  "detected_chapter": 25,
  "window": [21, 25],
  "drifts": [
    {"metric": "avg_sentence_length", "baseline": 18, "current": 24, "directive": "句子过长，回归短句节奏"},
    {"metric": "dialogue_ratio", "baseline": 0.4, "current": 0.28, "directive": "对话偏少，增加角色互动"}
  ],
  "injected_to": ["ChapterWriter"],
  "created_at": "2026-02-24T05:00:00Z",
  "cleared_at": null,
  "cleared_reason": null
}
```

**2) `ai-blacklist.json`（项目根目录）**

- `words[]`：生效黑名单（生成时禁止、润色时替换、评估时计入命中率）
- `whitelist[]`（可选）：豁免词条（不替换、不计入命中率、不得自动加入 words）
- `update_log[]`（可选，append-only）：记录每次自动/手动变更（added/exempted/removed）的 evidence 与时间戳，便于审计

建议扩展（兼容模板；无则视为空）：
```json
{
  "whitelist": [],
  "update_log": [
    {
      "timestamp": "2026-02-24T05:00:00Z",
      "chapter": 47,
      "source": "auto",
      "added": [
        {"phrase": "值得一提的是", "count_in_chapter": 3, "examples": ["例句 1", "例句 2"]}
      ],
      "exempted": [
        {"phrase": "老子", "reason": "style_profile.preferred_expressions", "examples": ["例句 1"]}
      ],
      "note": "本次变更摘要"
    }
  ]
}
```

**3) `${CLAUDE_PLUGIN_ROOT}/scripts/lint-blacklist.sh`（可选）**

- 输入：`<chapter.md> <ai-blacklist.json>`
- 输出：stdout JSON（exit 0），至少包含：
  - `total_hits`、`hits_per_kchars`（次/千字）、`hits[]`（word/count/lines/snippets）
- 失败回退：脚本不存在 / 退出码非 0 / stdout 非 JSON → 不阻断，QualityJudge 改为启发式估计并标注"估计值"

**4) `${CLAUDE_PLUGIN_ROOT}/scripts/run-ner.sh`（可选）**

- 输入：`<chapter.md>`
- 输出：stdout JSON（exit 0），至少包含：schema_version、chapter_path、entities（characters/locations/time_markers/events + evidence）；完整 schema 见 `continuity-checks.md`
- 失败回退：脚本不存在 / 退出码非 0 / stdout 非 JSON → 不阻断；入口 Skill/QualityJudge 走 LLM fallback（抽取实体 + 输出 confidence）
