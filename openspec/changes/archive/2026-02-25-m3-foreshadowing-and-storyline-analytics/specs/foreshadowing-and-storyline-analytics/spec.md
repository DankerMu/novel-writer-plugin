## ADDED Requirements

### Requirement: The system SHALL maintain a global foreshadowing index
The system SHALL maintain `foreshadowing/global.json` as the cross-volume source of truth for foreshadowing items, including:
- Stable `id`
- `scope` in {`short`, `medium`, `long`}
- `status` in {`planted`, `advanced`, `resolved`}
- `planted_chapter`, `planted_storyline`
- `target_resolve_range` (when applicable)
- `last_updated_chapter`
- `history[]` with `{chapter, action, detail}`

#### Scenario: A `foreshadow` op updates global index
- **WHEN** a committed chapter delta contains `{"op":"foreshadow","path":"ancient_prophecy","value":"advanced","detail":"..." }`
- **THEN** `foreshadowing/global.json` is updated with a new history entry and `last_updated_chapter` advances

### Requirement: The system SHALL derive per-chapter foreshadowing tasks from plans and global state
The system SHALL provide `foreshadowing_tasks` for ChapterWriter/Summarizer context assembly based on:
- `volumes/vol-{V:02d}/foreshadowing.json` (plan)
- `foreshadowing/global.json` (facts)
and SHALL only include tasks relevant to the target chapter.

#### Scenario: Chapter context receives only relevant tasks
- **WHEN** the system assembles context for chapter C
- **THEN** `foreshadowing_tasks` contains only unresolved items scheduled for C (or near-range guidance), not the full global index

### Requirement: Cross-storyline shared foreshadowing bridges SHALL be traceable
For each `storylines/storylines.json.relationships[].bridges.shared_foreshadowing[]` item, the system SHALL be able to trace it to:
- an existing entry in `foreshadowing/global.json`, or
- a planned entry in the current volume `volumes/vol-{V:02d}/foreshadowing.json`,
otherwise it SHALL report it as a broken bridge reference.

#### Scenario: Broken shared_foreshadowing reference reported
- **WHEN** a relationship bridge references a foreshadowing ID that does not exist in global index and is not planned for the volume
- **THEN** the bridge check report includes the missing ID and the relationship context (from/to storylines)

### Requirement: The system SHALL generate periodic foreshadowing status reports
The system SHALL generate a foreshadowing status report:
- every 10 chapters, and
- during volume review,
including unresolved items, their scope/status, and risk flags (e.g., overdue short-scope beyond `target_resolve_range` upper bound).

#### Scenario: Overdue short-scope items are highlighted
- **WHEN** a `short` scope item passes its `target_resolve_range[1]` without being `resolved`
- **THEN** the report marks it as overdue and surfaces it in `/novel:dashboard` or review output

### Requirement: The system SHALL provide storyline rhythm analytics
The system SHALL compute storyline rhythm analytics using `summaries/*` storyline_id and `storyline-schedule.json`, including:
- appearance count per storyline within a volume
- chapters since last appearance (dormancy length)
- convergence event attainment within planned chapter ranges (approximate alignment)

#### Scenario: Dormant storyline flagged against schedule expectation
- **WHEN** a secondary storyline has not appeared for more than the configured window (e.g., every 8 chapters)
- **THEN** the rhythm report flags the storyline as dormant and suggests scheduling adjustment

### Requirement: Deterministic foreshadow query script SHALL be used when available
If `scripts/query-foreshadow.sh` exists, the system SHALL prefer it to query relevant foreshadowing items for a chapter; otherwise it SHALL fall back to a rule-based JSON filtering path.

#### Scenario: Script path preferred
- **WHEN** `scripts/query-foreshadow.sh 48` exists and outputs valid JSON
- **THEN** the system uses it to build `foreshadowing_tasks` rather than scanning the full global file

## References

- `docs/dr-workflow/novel-writer-tool/final/prd/09-data.md`
- `docs/dr-workflow/novel-writer-tool/final/prd/06-storylines.md`
- `docs/dr-workflow/novel-writer-tool/final/spec/06-extensions.md`
- `docs/dr-workflow/novel-writer-tool/final/milestones.md`

