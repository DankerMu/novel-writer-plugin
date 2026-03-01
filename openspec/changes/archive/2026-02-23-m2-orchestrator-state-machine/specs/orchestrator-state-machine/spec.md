## ADDED Requirements

### Requirement: The system SHALL implement the Orchestrator state machine
The system SHALL implement the following states at minimum:
`INIT`, `QUICK_START`, `VOL_PLANNING`, `WRITING`, `CHAPTER_REWRITE`, `VOL_REVIEW`, `ERROR_RETRY`.
State SHALL be persisted in `.checkpoint.json.orchestrator_state`.

#### Scenario: State persisted to checkpoint
- **WHEN** the system transitions from one state to another
- **THEN** `.checkpoint.json.orchestrator_state` is updated to the new state

### Requirement: Skills SHALL map to states as defined
The system SHALL route work based on the Skill entrypoint:
- `/novel:start` SHALL handle state-aware routing for `INIT`, `QUICK_START`, `VOL_PLANNING`, `VOL_REVIEW`
- `/novel:continue` SHALL handle `WRITING` and `CHAPTER_REWRITE` (including gate + revision loop)
- `/novel:dashboard` SHALL be read-only and SHALL NOT trigger state transitions

#### Scenario: Continue blocked outside WRITING
- **WHEN** the user runs `/novel:continue` while `orchestrator_state` is neither `"WRITING"` nor `"CHAPTER_REWRITE"`
- **THEN** the command refuses and points the user to `/novel:start`

### Requirement: Cold-start recovery SHALL not depend on session history
On a new session, the system SHALL recover using files only, including:
`.checkpoint.json`, `state/current-state.json`, recent `summaries/`, and `volumes/vol-{V:02d}/outline.md` when available.
It SHALL NOT require prior conversation context.

#### Scenario: Recover context after session restart
- **WHEN** the user starts a new session in an existing project directory
- **THEN** `/novel:start` can recommend next steps based purely on file state

### Requirement: Chapter progress SHALL only advance on committed boundary
`last_completed_chapter` SHALL only be incremented after staging→commit completes successfully for the chapter.

#### Scenario: Interrupted pipeline does not advance chapter counter
- **WHEN** a session ends with `pipeline_stage != "committed"` for `inflight_chapter=C`
- **THEN** `last_completed_chapter` remains unchanged and recovery resumes or restarts chapter C

### Requirement: Volume lifecycle SHALL be enforced
The system SHALL transition to `VOL_REVIEW` at the configured “last chapter of volume” boundary, and after completing review it SHALL transition back to `VOL_PLANNING` for the next volume.

#### Scenario: End-of-volume triggers review
- **WHEN** the user commits the last chapter of the current volume
- **THEN** the next recommended action is `/novel:start` to run volume review (VOL_REVIEW)

### Requirement: Errors SHALL follow an explicit retry policy
On pipeline errors, the system SHALL enter `ERROR_RETRY`, retry at most once, and on repeated failure SHALL persist checkpoint and pause.

#### Scenario: Single retry on transient error
- **WHEN** an API timeout occurs during drafting
- **THEN** the system retries once before pausing and informing the user

## References

- `docs/dr-workflow/novel-writer-tool/final/prd/08-orchestrator.md`
- `docs/dr-workflow/novel-writer-tool/final/spec/02-skills.md`
- `docs/dr-workflow/novel-writer-tool/final/prd/09-data.md`
