## ADDED Requirements

### Requirement: `/novel:start` SHALL route user intent based on project state
`/novel:start` SHALL:
- Detect whether `.checkpoint.json` exists in the current directory
- Parse `orchestrator_state`, `current_volume`, `last_completed_chapter` when present
- Present 2-4 AskUserQuestion options with a single `(Recommended)` option based on state

#### Scenario: New user without checkpoint
- **WHEN** the user runs `/novel:start` in a directory without `.checkpoint.json`
- **THEN** the system offers “创建新项目 (Recommended)” and at least one help option

### Requirement: `/novel:start` SHALL initialize a minimal runnable project
When creating a new project, `/novel:start` SHALL create the project directory structure and initialize at minimum:
- `brief.md` (from `${CLAUDE_PLUGIN_ROOT}/templates/brief-template.md`)
- `.checkpoint.json`
- `state/current-state.json`
- `foreshadowing/global.json`
- `storylines/storyline-spec.json`
and project-root seed assets copied from plugin templates (at minimum `ai-blacklist.json` from `${CLAUDE_PLUGIN_ROOT}/templates/ai-blacklist.json`),
and required empty output directories (`chapters/`, `summaries/`, `evaluations/`, `logs/`, `staging/**`).

#### Scenario: Project initialization produces required files
- **WHEN** the user chooses “创建新项目”
- **THEN** the minimal file set and directories exist so that downstream Agents can read them without failure

### Requirement: AskUserQuestion SHALL be limited to the main entry skill
AskUserQuestion SHALL only be invoked inside `/novel:start`. Sub-agents (Task) and all Agents SHALL NOT directly prompt the user.

#### Scenario: Agent returns decision payload instead of prompting
- **WHEN** an Agent needs user confirmation (e.g., outline approval)
- **THEN** it returns a structured JSON decision payload and `/novel:start` presents the options via AskUserQuestion

### Requirement: `/novel:continue` SHALL enforce WRITING state and support `[N]`
`/novel:continue [N]` SHALL:
- Read `.checkpoint.json`
- Refuse to proceed unless `orchestrator_state == "WRITING"` (with a user-visible guidance message)
- Default `N` to 1 when omitted
- Cap recommended `N` (e.g., ≤5) to avoid runaway cost/time

#### Scenario: Continue invoked while not in WRITING state
- **WHEN** the user runs `/novel:continue` while `orchestrator_state != "WRITING"`
- **THEN** the command stops and instructs the user to run `/novel:start` to complete initialization or volume planning

### Requirement: `/novel:dashboard` SHALL be read-only and summarize key metrics
`/novel:dashboard` SHALL only use read-only tools and SHALL display, at minimum:
- Progress (volume/chapter)
- Score aggregates (overall mean + recent trend)
- Foreshadowing counts (active/resolved/overdue where applicable)
- Basic cost/time aggregates from `logs/` when available (null-safe)

#### Scenario: Status runs without mutating project
- **WHEN** the user runs `/novel:dashboard`
- **THEN** the command reads required files and produces a formatted report without writing any files

### Requirement: File-to-agent injection SHALL use `<DATA>` delimiter
When any entry skill passes external file contents to an Agent via Task `prompt` parameter (samples/research/chapters/profiles), it SHALL wrap the content using the `<DATA>` delimiter contract (type/source/readonly).

#### Scenario: Injected chapter text is treated as data not instructions
- **WHEN** a chapter markdown is injected into Summarizer or QualityJudge
- **THEN** it is wrapped in `<DATA ...>` and the agent prompt explicitly treats it as reference data

## References

- `docs/dr-workflow/novel-writer-tool/final/spec/02-skills.md`
- `docs/dr-workflow/novel-writer-tool/final/prd/08-orchestrator.md`
- `docs/dr-workflow/novel-writer-tool/final/prd/10-protocols.md`
- `docs/dr-workflow/novel-writer-tool/final/prd/09-data.md`
