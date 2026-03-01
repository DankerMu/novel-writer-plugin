## ADDED Requirements

### Requirement: The system SHALL provide a 30-minute quick start flow
The system SHALL provide a quick start flow that can produce 3 chapters within ~30 minutes, starting from minimal user input (genre + protagonist concept + core conflict), and create a usable project directory with required baseline files.

#### Scenario: New project quick start completes
- **WHEN** the user runs `/novel:start` in an empty directory and chooses “create new project”
- **THEN** the system creates the project structure and guides the user through quick start to produce 3 chapters

### Requirement: Quick start SHALL generate minimal L1 and storylines artifacts
During quick start, the system SHALL:
- generate lightweight L1 world rules (≤3 core rules)
- initialize `storylines/storylines.json` with a single `main_arc` storyline by default

#### Scenario: Minimal storylines initialized
- **WHEN** quick start completes
- **THEN** `storylines/storylines.json` exists and contains exactly one main storyline unless user explicitly adds more

### Requirement: Quick start SHALL support no-sample downgrade paths
If the user cannot provide original style samples, the system SHALL support a downgrade path:
- reference-author mode, or
- template mode, or
- write-then-extract mode,
and SHALL record the chosen mode in `style-profile.json.source_type`.

#### Scenario: Template mode used
- **WHEN** the user selects a template style during quick start
- **THEN** `style-profile.json.source_type="template"` and writing proceeds

### Requirement: The system SHALL provide user-facing documentation for core operations
The repository SHALL include user documentation covering:
- quick start
- common operations
- Spec system overview (L1/L2/L3/LS and gating)
- multi-thread storyline usage

#### Scenario: Docs cover quick start and core commands
- **WHEN** a new user reads the docs
- **THEN** they can run `/novel:start`, `/novel:continue`, and `/novel:dashboard` successfully and understand the next-step flow

## References

- `docs/dr-workflow/novel-writer-tool/final/milestones.md`
- `docs/dr-workflow/novel-writer-tool/final/prd/01-product.md`
- `docs/dr-workflow/novel-writer-tool/final/prd/04-workflow.md`

