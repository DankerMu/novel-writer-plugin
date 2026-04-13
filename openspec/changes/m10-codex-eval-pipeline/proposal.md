## Why

当前 Summarizer / QualityJudge / ContentCritic 三个 agent + 滑窗一致性校验通过 Claude Code `Task(subagent_type=..., model="opus")` 调度。单章评估管线（Sum + QJ + CC）消耗约 42-58K tokens（Opus 计费），占整章 pipeline token 预算的 ~45%。滑窗校验（10 章原文 + 契约 + 大纲）每次触发额外消耗 ~80-120K tokens。这些组件均为纯分析任务，无一需要 Claude Code 的 Edit/Grep 工具集成能力。

Codex CLI 作为本地 agent：
- **性能更强**：推理和结构化输出质量高于 Opus
- **成本更低**：token 单价显著低于 Opus API
- **无系统提示词污染**：与 API Writer 同理，绕过 Claude Code 工程向系统提示词
- **大 context 优势**：滑窗校验需一次性吃下 10 章全文（~30K 字），Codex 的长 context 处理更适合

写作环节不动：CW 需要 Edit 工具做定向修改，SR 需要 Grep/Edit 做黑名单扫描替换，API Writer 已经是外部模型调用。

### 确定性原则

Codex 严格只读 manifest 指定的文件，与现有 Opus agent 看到完全相同的输入。不引入自主探索 / `read_scope` / 不可控上下文。保持 context-assembly.md 的核心保证：

> 同一章 + 同一项目文件输入 → 组装结果唯一

## What Changes

### 1. eval_backend 配置项

在 `.checkpoint.json` 顶层新增配置字段：

```json
{
  "eval_backend": "codex"
}
```

- `"codex"`：Summarizer / QJ / CC / 滑窗校验走 Codex CLI 路径
- `"opus"`：走现有 Task(opus) 路径（默认值，缺失时等同 opus）
- **不存在运行时降级**——同一项目始终用同一后端，避免分数分布不兼容。切换前需重跑 M3 校准
- 编排器在 Step 1 读取此字段，全局生效

### 2. 新增 Codex prompt 文件

将现有 agent spec 转化为 Codex 可直接消费的 prompt 文件：

```
prompts/
├── codex-summarizer.md          # 基于 agents/summarizer.md
├── codex-quality-judge.md       # 基于 agents/quality-judge.md
├── codex-content-critic.md      # 基于 agents/content-critic.md
└── codex-sliding-window.md      # 基于 SKILL.md Step 8 滑窗校验流程
```

与 `api-writer-system.md` 同模式：纯分析指令，去掉 YAML frontmatter、Claude Code 工具引用、Read/Write 指令。替换为"你会收到以下文件内容"的被动输入模式。

**关键差异**：Codex prompt 中硬约束"仅使用 user message 中提供的文件内容，不自行读取其他文件"。

### 3. 调用链：codex-eval.py + codeagent skill

**调用链**：`SKILL.md 编排器 → codex-eval.py（组装） → codeagent skill（执行） → 编排器（校验 + 写入）`

`codeagent` 是已安装的外部 skill，支持 Codex/Claude/Gemini 多后端 + @file 引用 + 结构化输出。**必须通过 codeagent 调用 Codex**，不直接调 Codex CLI——codeagent 封装了进程管理、超时、输出捕获等基础设施。

#### Step A: codex-eval.py 组装 prompt（Bash 调用）

```
scripts/codex-eval.py <manifest.json> --agent summarizer|quality-judge|content-critic|sliding-window --project <path>
```

职责**仅限组装**，不调用任何外部模型：
- 读取 manifest JSON，将 `paths` 中的文件路径解析为绝对路径
- 读取各路径的文件内容，按 section 拼接（与 api-writer.py 的 `assemble_user_message()` 同模式）
- 组装完整 prompt 文件写入 `staging/prompts/chapter-{C:03d}-{agent}.md`（system prompt 内容 + user message 内容合并为一个 prompt 文件，codeagent 消费）
- 输出 prompt 文件路径到 stdout（供编排器捕获）
- 退出码：0 = 组装成功，1 = manifest 缺必要字段或文件不存在

#### Step B: codeagent skill 执行（Skill 调用）

编排器捕获 Step A 的 prompt 路径后，调用：

```
Skill("codeagent", args="--backend codex @staging/prompts/chapter-048-quality-judge.md")
```

codeagent 负责：
- 调用 Codex CLI，传入 @file 引用的 prompt
- 管理进程生命周期（超时、异常退出）
- 捕获 Codex 的结构化输出并返回

#### Step C: 编排器校验 + 写入

编排器从 codeagent 返回结果中提取 JSON，执行 schema 校验：
- **JSON 提取**：从 codeagent 输出中提取 JSON 块（```json ``` 围栏或裸 JSON 对象）
- **Schema 校验**：调用 `codex-eval.py --validate <json_file> --schema quality-judge` 检查必填字段、枚举值、数值范围
- 校验通过 → 写入 `staging/` 对应路径
- 校验失败 → 按 Step 1.6 重试一次

`codex-eval.py --validate` 模式：
```
scripts/codex-eval.py --validate <output.json> --schema summarizer|quality-judge|content-critic|sliding-window
```
- 退出码：0 = pass，1 = fail（stderr 输出具体缺失/违规字段列表）

### 4. 修改 continue/SKILL.md 调度方式

**单章管线（Step 2/3）**：

```python
if eval_backend == "codex":
    # Step 2: Summarizer
    #   A. 组装 prompt
    prompt_path = Bash("python3 ${PLUGIN_ROOT}/scripts/codex-eval.py manifest.json --agent summarizer --project <root>").stdout.strip()
    #   B. codeagent 执行
    result = Skill("codeagent", args=f"--backend codex @{prompt_path}")
    #   C. 提取 JSON + 校验 + 写入 staging/
    Write(staging_path, extracted_json)
    Bash(f"python3 ${{PLUGIN_ROOT}}/scripts/codex-eval.py --validate {staging_path} --schema summarizer")

    # Step 3: QJ + CC 并行（两个 Skill 调用并行发起）
    #   A. 组装两个 prompt（并行 Bash）
    qj_prompt = Bash("... --agent quality-judge ...").stdout.strip()
    cc_prompt = Bash("... --agent content-critic ...").stdout.strip()
    #   B. 并行 codeagent 调用
    qj_result = Skill("codeagent", args=f"--backend codex @{qj_prompt}")   # 并行 ┐
    cc_result = Skill("codeagent", args=f"--backend codex @{cc_prompt}")   # 并行 ┘
    #   C. 各自校验 + 写入 staging/

else:  # eval_backend == "opus" 或缺失
    # 现有 Task 路径不变
    Task(subagent_type="summarizer", model="opus")
    Task(subagent_type="quality-judge", model="opus")   # 并行
    Task(subagent_type="content-critic", model="opus")  # 并行
```

**滑窗一致性校验（Step 8）**：

```python
if eval_backend == "codex":
    # 1. 组装滑窗 prompt（窗口内 10 章原文 + 契约 + 大纲 + 世界规则 + 角色档案）
    sw_prompt = Bash("python3 ${PLUGIN_ROOT}/scripts/codex-eval.py sliding-window-manifest.json --agent sliding-window --project <root>").stdout.strip()
    # 2. codeagent 执行分析
    sw_result = Skill("codeagent", args=f"--backend codex @{sw_prompt}")
    # 3. 提取报告 JSON + 校验
    Bash(f"python3 ${{PLUGIN_ROOT}}/scripts/codex-eval.py --validate {report_path} --schema sliding-window")
    # 4. 编排器读取报告，对 auto_fixable issues 使用 Edit 工具修复章节原文
    # 5. 不可自动修复的问题列出并提示用户
else:
    # 现有 agent 驱动流程不变（编排器内联执行）
```

**滑窗拆分设计**：当前滑窗是"分析 + 自动修复"一体化。Codex 化后拆分为：
- **Codex**：纯分析，输出报告 JSON（issues 列表，每条含 `auto_fixable: bool`、`chapter`、`location`、`current_text`、`suggested_fix`）
- **编排器**：读取报告，对 `auto_fixable == true` 的条目使用 Edit 工具修改 `chapters/chapter-{C:03d}.md`

这是唯一正确的拆分方式——Codex 不应直接写入非 staging 目录的已提交章节文件。

### 5. 滑窗报告 JSON Schema

```json
{
  "window": {"start": 1, "end": 10, "volume": 1},
  "alignment_checks": [
    {
      "chapter": 3,
      "check_type": "contract_event_missing | contract_conflict_missing | outline_mismatch | acceptance_criteria_fail | foreshadow_missing",
      "detail": "契约事件「与师兄对峙」未在正文中呈现",
      "severity": "high | medium",
      "auto_fixable": false
    }
  ],
  "continuity_issues": [
    {
      "chapter_range": [5, 7],
      "issue_type": "character_position | timeline_contradiction | world_rule_violation | foreshadow_inconsistency | cross_line_leak",
      "detail": "第 5 章末主角在山顶，第 7 章开头出现在城中，无过渡",
      "severity": "high | medium",
      "auto_fixable": true,
      "current_text": "陈渊走进城门...",
      "suggested_fix": "陈渊从山道下来，穿过密林，终于在日落前赶到了城门。他走进城门...",
      "fix_chapter": 7,
      "fix_location": "paragraph_1"
    }
  ],
  "ner_entities": [...],
  "summary": {
    "issues_total": 5,
    "auto_fixable_count": 3,
    "high_severity_unfixed": 1
  }
}
```

### 6. Schema 校验逻辑（内嵌 codex-eval.py）

不单独新建 `validate-eval-schema.py`（过度设计），直接在 `codex-eval.py` 中实现各 agent 的校验函数：

```python
def validate_summarizer(data: dict) -> list[str]:
    """Return list of error messages. Empty = pass."""
    errors = []
    if "ops" not in data: errors.append("missing: ops")
    if "canon_hints" not in data: errors.append("missing: canon_hints (mandatory)")
    for op in data.get("ops", []):
        if op.get("op") not in ("set", "inc", "add", "remove", "foreshadow"):
            errors.append(f"invalid op: {op.get('op')}")
    return errors

def validate_quality_judge(data: dict) -> list[str]: ...
def validate_content_critic(data: dict) -> list[str]: ...
def validate_sliding_window(data: dict) -> list[str]: ...
```

校验粒度：必填字段存在性 + 枚举值合法性 + 数值范围（scores 1-5）。不做深层语义校验（那是 gate decision engine 的职责）。

### 7. 并行执行

QJ + CC 的 prompt 组装（Step A）通过两个并行 Bash 完成，codeagent 调用（Step B）通过两个并行 Skill 调用完成：

```
# Step A: 并行组装 prompt
Bash("... --agent quality-judge ...")  # tool call 1 ┐
Bash("... --agent content-critic ...") # tool call 2 ┘ 并行

# Step B: 并行 codeagent 调用
Skill("codeagent", args="--backend codex @qj-prompt.md")  # tool call 1 ┐
Skill("codeagent", args="--backend codex @cc-prompt.md")   # tool call 2 ┘ 并行
```

与当前两个并行 Task 同构——Claude Code 原生支持同一消息中多个 tool call 并行执行。

### 8. 错误处理

与现有 Step 1.6 对齐：
- **codeagent 调用失败**（Codex 超时 / 返回非 JSON）→ 编排器自动重试一次（重新调用 Skill("codeagent")，不重新组装 prompt）
- **schema 校验失败**（codex-eval.py --validate 退出码 1）→ 编排器自动重试一次（从 Step B 重跑 codeagent）
- 重试仍失败 → `orchestrator_state = "ERROR_RETRY"`，暂停等用户决策
- **不做运行时降级到 Opus**——eval_backend 是全局配置，不在单次失败时切换（分数分布不兼容）
- 用户可手动在 `.checkpoint.json` 中将 `eval_backend` 改回 `"opus"` 后重试

### 9. recheck_mode（M9.2）兼容

M9.2 的 `recheck_mode` / `patch_mode` / `lite_mode` 在 Codex 路径下同样支持：
- codex-eval.py 读取 manifest 中的 `recheck_mode`、`failed_dimensions`、`previous_eval` 等字段
- 将这些字段注入 Codex user message
- Codex prompt 中包含 recheck 模式的处理指令（与现有 agent spec 中的 Recheck 模式 section 对应）

## Capabilities

### New Capabilities

- `codex-eval.py`：prompt 组装 + schema 校验工具（双模式：`--agent` 组装 manifest→prompt，`--validate` 校验输出 JSON）
- `prompts/codex-summarizer.md`：Codex Summarizer prompt
- `prompts/codex-quality-judge.md`：Codex QJ prompt
- `prompts/codex-content-critic.md`：Codex CC prompt
- `prompts/codex-sliding-window.md`：Codex 滑窗分析 prompt
- `eval_backend` 配置项：全局后端选择（codex / opus）

### Modified Capabilities

- `continue/SKILL.md` Step 2/3: 按 eval_backend 分支调度
- `continue/SKILL.md` Step 8: 滑窗校验按 eval_backend 分支，Codex 时拆分为分析 + 编排器修复

### Retained（不删除）

- `agents/summarizer.md` / `agents/quality-judge.md` / `agents/content-critic.md`：eval_backend="opus" 时使用

## Impact

- **影响范围**：`scripts/codex-eval.py`（新增）、`prompts/codex-*.md`（新增 ×4）、`skills/continue/SKILL.md`（Step 2/3/8 分支化）、`.checkpoint.json` schema（新增 `eval_backend`）
- **依赖关系**：
  - `codeagent` skill 需已安装（提供 Codex CLI 调度基础设施）
  - Codex CLI 需本地安装且可用（eval_backend="codex" 时）
- **兼容性**：
  - eval_backend 缺失 → 等同 "opus"，现有流程完全不变
  - checkpoint 增加可选字段，旧 checkpoint 无此字段时走 opus
  - eval-raw / content-eval-raw / delta JSON 输出格式不变，gate decision engine 无感知
  - 滑窗报告 JSON 是新格式（当前滑窗报告已有 `logs/continuity/` 落盘，格式扩展不破坏）
- **不兼容**：
  - eval_backend 切换时门控阈值可能需要调整（Codex 与 Opus 评分分布不同）
  - 切换前必须重跑 M3 校准数据集验证 Pearson r

## Migration Path

```
Phase 1: 基础设施
  - codex-eval.py + 4 个 prompt 文件
  - SKILL.md 增加 eval_backend 分支

Phase 2: 校准验证
  - eval_backend="codex" 跑 M3 校准数据集（30 章）
  - 对比 Codex vs 人工标注的 Pearson r
  - 若 r >= 0.85 且分数偏移 < 0.3 → 门控阈值不变
  - 若偏移 >= 0.3 → 调整门控阈值或 prompt

Phase 3: 正式启用
  - 新项目默认 eval_backend="codex"
  - 已有项目可选切换（切换后建议跑 5 章验证）

Phase 4: 文档更新
  - CLAUDE.md 架构文档
  - M3 校准基线更新
```

## Milestone Mapping

- M10.1: codex-eval.py + prompt 文件 + SKILL.md 分支化
- M10.2: M3 校准验证 + 门控阈值调整
- M10.3: 正式启用 + 文档

## References

- `scripts/api-writer.py`（同模式参考：外部模型调用 + prompt 组装）
- `eval/schema/chapter-eval.schema.json`（正式 JSON schema）
- `agents/summarizer.md` / `agents/quality-judge.md` / `agents/content-critic.md`（prompt 源）
- `skills/continue/SKILL.md` Step 8（滑窗校验流程源）
- M9.2 修订回环优化（recheck_mode 兼容）
- `skills/continue/references/context-assembly.md`（确定性原则）
