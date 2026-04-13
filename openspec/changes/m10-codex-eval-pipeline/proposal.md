## Why

当前 Summarizer / QualityJudge / ContentCritic 三个 agent + 滑窗一致性校验通过 Claude Code `Task(subagent_type=..., model="opus")` 调度。单章评估管线（Sum + QJ + CC）消耗约 42-58K tokens（Opus 计费），占整章 pipeline token 预算的 ~45%。滑窗校验（10 章原文 + 契约 + 大纲）每次触发额外消耗 ~80-120K tokens。这些组件均为纯分析任务。

Codex CLI 是与 Claude Code 同级的本地 agent，具备完整的文件读写、Bash 执行、自主推理能力：
- **性能更强**：推理和结构化输出质量高于 Opus
- **成本更低**：token 单价显著低于 Opus API
- **无系统提示词污染**：与 API Writer 同理，绕过 Claude Code 工程向系统提示词
- **能力同构**：可直接读写文件、执行 lint 脚本、写入 staging/——与现有 Opus agent 行为模式完全一致

写作环节不动：CW 需要 Claude Code 的 Edit 工具做定向修改，SR 需要 Grep/Edit 做黑名单扫描替换，API Writer 已经是外部模型调用。

### 确定性原则

Codex 的 task content 中显式指定需要读取的文件路径，与现有 Opus agent 通过 manifest paths 接收文件路径的模式同构。保持 context-assembly.md 的核心保证：

> 同一章 + 同一项目文件输入 → 组装结果唯一

## What Changes

### 1. eval_backend 配置项

在 `.checkpoint.json` 顶层新增配置字段：

```json
{
  "eval_backend": "codex"
}
```

- `"codex"`：Summarizer / QJ / CC / 滑窗校验走 Codex 路径（codeagent-wrapper）
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

与 `api-writer-system.md` 同模式：纯分析指令，去掉 YAML frontmatter 和 Claude Code 特定引用（如 Read/Write tool 提示）。

**Codex 与 Opus agent 的行为同构**：Codex 是完整的本地 agent（有文件读写、Bash 执行能力），所以 prompt 中保留"读取以下路径的文件"和"将输出写入 staging/ 对应路径"的指令——Codex 自行执行，与 Opus agent 用 Read/Write 工具读写文件行为一致。

**关键指令**：
- 文件读写路径基于 working_dir（项目根目录）
- lint 脚本由 Codex 自行执行（`lint-meta-leak.sh`、`lint-format.sh` 等，与现有 QJ agent 行为一致）
- 所有写入限于 `staging/` 目录
- Summarizer 直接写入 7 个 staging 文件（summary.md + delta.json + crossref.json + memory.md 等）

### 3. 调用链：codex-eval.py + codeagent-wrapper

**调用链**：`SKILL.md 编排器 → codex-eval.py（组装 task content） → codeagent-wrapper（Codex 执行） → codex-eval.py --validate（校验 staging 输出）`

`codeagent-wrapper` 是已安装的 CLI 工具，封装 Codex/Claude/Gemini 多后端的进程管理、超时、输出捕获。**必须通过 codeagent-wrapper 调用 Codex**。

#### Step A: codex-eval.py 组装 task content

```
scripts/codex-eval.py <manifest.json> --agent summarizer|quality-judge|content-critic|sliding-window --project <path>
```

职责**仅限组装**，不调用任何外部模型：
- 读取 manifest JSON
- 生成 task content 文件到 `staging/prompts/chapter-{C:03d}-{agent}.md`，包含：
  - 评估规范 prompt 路径引用（告诉 Codex 读取 `prompts/codex-{agent}.md`）
  - manifest `paths` 中的文件路径列表（告诉 Codex 读取这些文件）
  - manifest inline 值直接内联（chapter_num、hard_rules_list 等）
  - recheck_mode / patch_mode 等 M9.2 字段（如存在）
  - 输出路径指令（告诉 Codex 写入 `staging/` 对应路径）
- 输出 task content 文件路径到 stdout
- 退出码：0 = 组装成功，1 = manifest 缺必要字段或文件不存在

**生成的 task content 示例**（QJ）：
```markdown
请读取以下评估规范，然后执行章节质量评估。

## 评估规范
请读取: prompts/codex-quality-judge.md

## 需要读取的文件
- 章节全文: staging/chapters/chapter-048.md
- 章节契约: volumes/vol-01/chapter-contracts/chapter-048.md
- 风格指纹: style-profile.json
- AI 黑名单: ai-blacklist.json
- 评分标准: skills/novel-writing/references/quality-rubric.md
- 前章摘要: summaries/chapter-047-summary.md
- 角色档案: characters/active/chen-yuan.md, characters/active/su-yao.md

## 需要执行的 lint 脚本
- bash scripts/lint-meta-leak.sh staging/chapters/chapter-048.md
- bash scripts/lint-terminology.sh staging/chapters/chapter-048.md
- bash scripts/lint-format.sh staging/chapters/chapter-048.md
（将 lint 结果用于 contract_verification 对应 checks）

## 内联数据
- 章节号: 48
- 卷号: 1
- platform: qidian
- is_golden_chapter: false
- hard_rules_list:
  - 修炼者突破金丹需要灵气浓度≥3级
  - 禁地不可擅入

## 输出要求
将评估结果以 JSON 写入: staging/evaluations/chapter-048-eval-raw.json
```

#### Step B: codeagent-wrapper 执行（Bash 调用）

```bash
codeagent-wrapper --backend codex - <project_root> < staging/prompts/chapter-048-quality-judge.md
```

- working_dir 设为项目根目录 → Codex 在项目目录下执行，路径自然解析
- Codex 自主读取文件、执行 lint 脚本、将结果写入 staging/（与 Opus agent 行为同构）
- codeagent-wrapper 管理进程生命周期（超时默认 2h，可通过 `CODEX_TIMEOUT` 调整）
- stdout 返回 Codex 执行摘要 + SESSION_ID（SESSION_ID 记录到 chapter log 供审计追溯）

#### Step C: codex-eval.py 校验 staging 输出

Codex 执行完毕后，编排器调用校验：

```bash
python3 ${PLUGIN_ROOT}/scripts/codex-eval.py --validate --schema quality-judge --project <root> --chapter 48
```

校验逻辑：
- 检查预期的 staging 输出文件是否存在（如 `staging/evaluations/chapter-048-eval-raw.json`）
- 解析 JSON，校验必填字段、枚举值、数值范围（scores 1-5）
- 退出码 0 = pass，退出码 1 = fail（stderr 输出具体缺失/违规字段列表）

**Summarizer 校验**额外检查 7 个文件全部存在：summary.md + delta.json（含 canon_hints）+ crossref.json + memory.md。

### 4. 修改 continue/SKILL.md 调度方式

**单章管线（Step 2/3）**：

```python
if eval_backend == "codex":
    # Step 2: Summarizer
    Bash("python3 ${PLUGIN_ROOT}/scripts/codex-eval.py manifest.json --agent summarizer --project <root>")
    Bash("codeagent-wrapper --backend codex - <root> < staging/prompts/chapter-048-summarizer.md",
         timeout=3600000)
    Bash("python3 ${PLUGIN_ROOT}/scripts/codex-eval.py --validate --schema summarizer --project <root> --chapter 48")

    # Step 3: QJ + CC 并行（两个独立 codeagent-wrapper，由编排器并行 Bash 调用）
    #   A. 组装两个 task content（并行）
    Bash("... --agent quality-judge ...")   # 并行 ┐
    Bash("... --agent content-critic ...")  # 并行 ┘
    #   B. 两个独立 codeagent-wrapper 并行执行
    Bash("codeagent-wrapper --backend codex - <root> < staging/prompts/chapter-048-quality-judge.md",
         timeout=3600000)   # 并行 ┐
    Bash("codeagent-wrapper --backend codex - <root> < staging/prompts/chapter-048-content-critic.md",
         timeout=3600000)   # 并行 ┘
    #   C. 各自校验
    Bash("... --validate --schema quality-judge ...")
    Bash("... --validate --schema content-critic ...")

else:  # eval_backend == "opus" 或缺失
    Task(subagent_type="summarizer", model="opus")
    Task(subagent_type="quality-judge", model="opus")   # 并行
    Task(subagent_type="content-critic", model="opus")  # 并行
```

**滑窗一致性校验（Step 8）**：

```python
if eval_backend == "codex":
    # 1. 组装滑窗 task content
    Bash("python3 ${PLUGIN_ROOT}/scripts/codex-eval.py sliding-window-manifest.json --agent sliding-window --project <root>")
    # 2. codeagent-wrapper 执行（Codex 读取 10 章原文 + 契约 + 大纲，输出报告 JSON）
    Bash("codeagent-wrapper --backend codex - <root> < staging/prompts/sliding-window.md",
         timeout=7200000)  # 复杂任务 2h
    # 3. 校验报告
    Bash("python3 ${PLUGIN_ROOT}/scripts/codex-eval.py --validate --schema sliding-window --project <root>")
    # 4. 编排器读取报告，对 auto_fixable issues 使用 Edit 工具修复章节原文
    # 5. 不可自动修复的问题列出并提示用户
else:
    # 现有 agent 驱动流程不变
```

**滑窗拆分设计**：当前滑窗是"分析 + 自动修复"一体化。Codex 化后拆分为：
- **Codex**：分析 + 输出报告 JSON 到 `staging/logs/continuity/`（issues 列表，每条含 `auto_fixable`、`fix_chapter`、`current_text`、`suggested_fix`）
- **编排器**：读取报告，对 `auto_fixable == true` 的条目使用 Edit 工具修改 `chapters/chapter-{C:03d}.md`

为什么不让 Codex 直接修复？Codex 在项目目录下有写入能力，但已提交章节文件（`chapters/`）不在 staging 保护范围内。拆分为分析 + 编排器修复，确保修复操作走 Claude Code 的 Edit 工具（受 hooks.json 管控、有 diff 审计）。

### 5. 滑窗报告 JSON Schema

Codex 将报告写入 `staging/logs/continuity/continuity-report-vol-{V:02d}-ch{start:03d}-ch{end:03d}.json`：

```json
{
  "window": {"start": 1, "end": 10, "volume": 1},
  "alignment_checks": [
    {
      "chapter": 3,
      "check_type": "contract_event_missing | contract_conflict_missing | outline_mismatch | acceptance_criteria_fail | foreshadow_missing",
      "detail": "契约事件「与师兄对峙」未在正文中完整呈现",
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
  "summary": {
    "issues_total": 5,
    "auto_fixable_count": 3,
    "high_severity_unfixed": 1
  }
}
```

### 6. Schema 校验逻辑（内嵌 codex-eval.py）

`codex-eval.py --validate` 模式内嵌各 agent 的校验函数：

```python
def validate_summarizer(project_root: Path, chapter: int) -> list[str]:
    """Check all 7 staging files exist and delta.json is valid."""
    errors = []
    # 文件存在性
    for path in [f"staging/summaries/chapter-{chapter:03d}-summary.md",
                 f"staging/state/chapter-{chapter:03d}-delta.json",
                 f"staging/state/chapter-{chapter:03d}-crossref.json"]:
        if not (project_root / path).exists():
            errors.append(f"missing: {path}")
    # delta.json schema
    delta = json.loads((project_root / f"staging/state/chapter-{chapter:03d}-delta.json").read_text())
    if "ops" not in delta: errors.append("delta: missing ops")
    if "canon_hints" not in delta: errors.append("delta: missing canon_hints (mandatory)")
    for op in delta.get("ops", []):
        if op.get("op") not in ("set", "inc", "add", "remove", "foreshadow"):
            errors.append(f"delta: invalid op '{op.get('op')}'")
    return errors

def validate_quality_judge(project_root: Path, chapter: int) -> list[str]: ...
def validate_content_critic(project_root: Path, chapter: int) -> list[str]: ...
def validate_sliding_window(project_root: Path) -> list[str]: ...
```

校验粒度：文件存在性 + 必填字段 + 枚举值 + 数值范围（scores 1-5）。不做深层语义校验。

### 7. 并行执行

QJ + CC 使用两个独立的 `codeagent-wrapper` 调用，由编排器通过两个并行 Bash tool call 实现：

```bash
# tool call 1（并行）
codeagent-wrapper --backend codex - <project_root> < staging/prompts/chapter-048-quality-judge.md

# tool call 2（并行）
codeagent-wrapper --backend codex - <project_root> < staging/prompts/chapter-048-content-critic.md
```

- Codex 各自在项目目录下读文件、跑 lint、写 staging/，互不干扰（写入路径不同）
- Claude Code 原生支持同一消息中多个 Bash tool call 并行执行，性能无差异

### 8. 错误处理

与现有 Step 1.6 对齐：
- **codeagent-wrapper 失败**（Codex 超时 / 进程崩溃）→ 编排器自动重试一次（重新 Bash 调用，task content 文件已在磁盘上不需重新组装）
- **schema 校验失败**（codex-eval.py --validate 退出码 1）→ 编排器自动重试一次（从 Step B 重跑 codeagent-wrapper）
- 重试仍失败 → `orchestrator_state = "ERROR_RETRY"`，暂停等用户决策
- **不做运行时降级到 Opus**——eval_backend 是全局配置，不在单次失败时切换
- 用户可手动在 `.checkpoint.json` 中将 `eval_backend` 改回 `"opus"` 后重试
- **超时设置**：`CODEX_TIMEOUT` 按任务复杂度配置——Summarizer/QJ/CC 各 3600000ms (1h)，滑窗 7200000ms (2h)
- **关键**：不得 kill codeagent-wrapper 进程（长时间运行是正常的，强杀浪费 API 成本且丢失进度）
- **SESSION_ID**：codeagent-wrapper 返回的 SESSION_ID 记录到 `logs/chapter-{C:03d}-log.json`，供失败时手动 resume 使用

### 9. recheck_mode（M9.2）兼容

M9.2 的 `recheck_mode` / `patch_mode` / `lite_mode` 在 Codex 路径下同样支持：
- codex-eval.py 读取 manifest 中的 `recheck_mode`、`failed_dimensions`、`failed_tracks`、`previous_eval` 路径、`revision_diff` 路径
- 将这些字段注入 task content
- Codex prompt 中包含 recheck 模式的处理指令（与现有 agent spec 中的 Recheck 模式 section 内容一致）
- Codex 自行读取 previous_eval 文件沿用通过维度分数

## Capabilities

### New Capabilities

- `codex-eval.py`：双模式工具——`--agent` 组装 manifest→task content，`--validate` 校验 staging 输出文件
- `prompts/codex-summarizer.md`：Codex Summarizer prompt
- `prompts/codex-quality-judge.md`：Codex QJ prompt
- `prompts/codex-content-critic.md`：Codex CC prompt
- `prompts/codex-sliding-window.md`：Codex 滑窗分析 prompt
- `eval_backend` 配置项：全局后端选择（codex / opus）

### Modified Capabilities

- `continue/SKILL.md` Step 2/3: 按 eval_backend 分支调度
- `continue/SKILL.md` Step 8: 滑窗校验按 eval_backend 分支，Codex 时拆分为分析 + 编排器 Edit 修复

### Retained（不删除）

- `agents/summarizer.md` / `agents/quality-judge.md` / `agents/content-critic.md`：eval_backend="opus" 时使用

## Impact

- **影响范围**：`scripts/codex-eval.py`（新增）、`prompts/codex-*.md`（新增 ×4）、`skills/continue/SKILL.md`（Step 2/3/8 分支化）、`.checkpoint.json` schema（新增 `eval_backend`）
- **依赖关系**：
  - `codeagent-wrapper` CLI 需已安装
  - Codex CLI 需本地安装且可用（eval_backend="codex" 时）
- **兼容性**：
  - eval_backend 缺失 → 等同 "opus"，现有流程完全不变
  - checkpoint 增加可选字段，旧 checkpoint 无此字段时走 opus
  - eval-raw / content-eval-raw / delta JSON 输出格式不变，gate decision engine 无感知
  - Codex 行为与 Opus agent 同构：读同样的文件、跑同样的 lint、写同样的 staging 路径
  - 滑窗报告 JSON 是新格式（当前滑窗由 agent 内联执行，无独立报告 schema）
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
- `codeagent-wrapper` skill（调用格式参考）
