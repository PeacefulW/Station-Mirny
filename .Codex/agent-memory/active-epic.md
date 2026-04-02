# Epic: Agent Skill Pack

**Spec**: docs/02_system_specs/meta/agent_skill_pack.md
**Started**: 2026-04-02
**Current iteration**: 4
**Total iterations**: 6

## Documentation debt

Track required documentation updates from the spec's "Required contract and API updates" section.

- [ ] AGENTS.md / AI_PLAYBOOK.md skill path and router mention review
- [ ] DATA_CONTRACTS.md grep proof recorded at final implementation iteration
- [ ] PUBLIC_API.md grep proof recorded at final implementation iteration
- **Deadline**: after iteration 6
- **Status**: pending

## Iterations

### Iteration 1 - Router and governance foundation
**Status**: completed
**Started**: 2026-04-02
**Completed**: 2026-04-02

#### Acceptance tests
- [x] `mirny-task-router` exists in `.agents/skills/` and mirrored `.claude/skills/` - verified by reading both files and matching file hashes
- [x] router `description` explicitly mentions performance, lore, UI, balance, and workflow triggers - verified by `Select-String` for trigger phrases in `.agents/skills/mirny-task-router/SKILL.md`
- [x] the router body instructs the agent to load all relevant companion skills for mixed requests - verified by `Select-String` for routing rules and mixed-request rule
- [x] the composition matrix is represented in repo documentation or references - verified by `Select-String` in `docs/02_system_specs/meta/agent_skill_pack.md`

#### Doc check
- [x] Grep DATA_CONTRACTS.md for changed names - `mirny-task-router|brainstorming|persistent-tasks|verification-before-completion` -> 0 matches
- [x] Grep PUBLIC_API.md for changed names - `mirny-task-router|brainstorming|persistent-tasks|verification-before-completion` -> 0 matches
- [x] Documentation debt section reviewed - still pending, not due until iteration 6

#### Files touched
- [.agents/skills/mirny-task-router/SKILL.md] - created broad Station Mirny routing skill with multi-skill composition rules
- [.claude/skills/mirny-task-router/SKILL.md] - created compatibility mirror of the routing skill
- [.agents/skills/brainstorming/SKILL.md] - updated description to compose cleanly with the router
- [.claude/skills/brainstorming/SKILL.md] - mirrored router-aware description update
- [.agents/skills/persistent-tasks/SKILL.md] - updated description to mention router-driven multi-iteration use
- [.claude/skills/persistent-tasks/SKILL.md] - mirrored router-aware description update
- [.agents/skills/verification-before-completion/SKILL.md] - updated description to mention router-driven closeout use
- [.claude/skills/verification-before-completion/SKILL.md] - mirrored router-aware description update

#### Closure report
## Closure Report

### Implemented
- Created `mirny-task-router` in `.agents/skills/` and mirrored it in `.claude/skills/`.
- Encoded broad trigger phrases for performance, lore, UI, balance, workflow, POI, and prompt-shaping requests in router metadata.
- Added explicit multi-skill composition guidance in the router body.
- Tightened the descriptions of `brainstorming`, `persistent-tasks`, and `verification-before-completion` so they compose cleanly with router-driven classification.

### Root cause
- The project had narrow governance skills but no broad Station Mirny router that could classify mixed requests and proactively combine the right project skills.

### Files changed
- `.agents/skills/mirny-task-router/SKILL.md` - new router skill.
- `.claude/skills/mirny-task-router/SKILL.md` - compatibility mirror.
- Existing project governance skill files in `.agents/skills/` and `.claude/skills/` - router-aware description updates.

### Acceptance tests
- [x] Router exists in both skill roots - verified by file reads and matching file hashes.
- [x] Router description mentions performance, lore, UI, balance, and workflow triggers - verified by `Select-String`.
- [x] Router body tells the agent to load all relevant companion skills for mixed requests - verified by `Select-String`.
- [x] Composition matrix exists in repo docs - verified by `Select-String` in `docs/02_system_specs/meta/agent_skill_pack.md`.

### Contract/API documentation check
- Grep DATA_CONTRACTS.md for `mirny-task-router|brainstorming|persistent-tasks|verification-before-completion`: 0 matches.
- Grep PUBLIC_API.md for `mirny-task-router|brainstorming|persistent-tasks|verification-before-completion`: 0 matches.
- Spec "Required contract and API updates" section: exists - deferred to iteration 6 as documented debt.

### Out-of-scope observations
- `init_skill.py` could not be executed in this environment because the Python launcher is misconfigured, so the new skill was created manually.

### Remaining blockers
- Iteration 2 specialist performance skills are not implemented yet.

### DATA_CONTRACTS.md updated
- Not required for iteration 1 - grep confirmed 0 matches for changed skill names.

### PUBLIC_API.md updated
- Not required for iteration 1 - grep confirmed 0 matches for changed skill names.

#### Blockers
- none

---

### Iteration 2 - Performance and stability bundle
**Status**: completed
**Started**: 2026-04-02
**Completed**: 2026-04-02

#### Acceptance tests
- [x] `world-perf-doctor`, `loading-lag-hunter`, `frame-budget-guardian`, and `save-load-regression-guard` exist in `.agents/skills/` and mirrored `.claude/skills/` - verified by `Get-FileHash` parity for each `.agents`/`.claude` pair
- [x] each performance skill description contains concrete Russian and English trigger phrases - verified by `Select-String` matches for phrases including `лагает`, `долгая загрузка`, `пересчитать всё сразу`, `после загрузки сломалось`, `interactive world hitch`, `boot too slow`, `frame spike`, and `save/load regression`
- [x] each skill references `PERFORMANCE_CONTRACTS.md` or the relevant Station Mirny contract documents - verified by `Select-String` for `PERFORMANCE_CONTRACTS.md`, `DATA_CONTRACTS.md`, and `PUBLIC_API.md`
- [x] the skills remain narrow and do not duplicate each other - verified by file reads confirming distinct ownership/boundary statements for interactive world hitch, loading/streaming, budget-law review, and save/load regression scopes

#### Doc check
- [x] Grep DATA_CONTRACTS.md for changed names — `world-perf-doctor|loading-lag-hunter|frame-budget-guardian|save-load-regression-guard` -> 0 matches
- [x] Grep PUBLIC_API.md for changed names — `world-perf-doctor|loading-lag-hunter|frame-budget-guardian|save-load-regression-guard` -> 0 matches
- [x] Documentation debt section reviewed — still pending, not due until iteration 6

#### Files touched
- `.agents/skills/world-perf-doctor/SKILL.md` - created interactive world-performance diagnosis skill
- `.claude/skills/world-perf-doctor/SKILL.md` - created compatibility mirror
- `.agents/skills/loading-lag-hunter/SKILL.md` - created boot/load/streaming performance diagnosis skill
- `.claude/skills/loading-lag-hunter/SKILL.md` - created compatibility mirror
- `.agents/skills/frame-budget-guardian/SKILL.md` - created budget-discipline reviewer skill
- `.claude/skills/frame-budget-guardian/SKILL.md` - created compatibility mirror
- `.agents/skills/save-load-regression-guard/SKILL.md` - created save/load boundary and runtime-diff regression skill
- `.claude/skills/save-load-regression-guard/SKILL.md` - created compatibility mirror

#### Closure report
## Closure Report

### Implemented
- Created `world-perf-doctor` in `.agents/skills/` and mirrored it in `.claude/skills/`.
- Created `loading-lag-hunter` in `.agents/skills/` and mirrored it in `.claude/skills/`.
- Created `frame-budget-guardian` in `.agents/skills/` and mirrored it in `.claude/skills/`.
- Created `save-load-regression-guard` in `.agents/skills/` and mirrored it in `.claude/skills/`.
- Scoped each skill narrowly so the router can compose them without role overlap.

### Root cause
- Iteration 1 added only the broad router layer. The project still lacked concrete performance/stability specialist skills, so Station Mirny performance complaints could still route into generic advice instead of project-specific performance law and persistence boundaries.

### Files changed
- `.agents/skills/world-perf-doctor/SKILL.md` - new interactive world-performance skill.
- `.claude/skills/world-perf-doctor/SKILL.md` - compatibility mirror.
- `.agents/skills/loading-lag-hunter/SKILL.md` - new loading/boot/streaming skill.
- `.claude/skills/loading-lag-hunter/SKILL.md` - compatibility mirror.
- `.agents/skills/frame-budget-guardian/SKILL.md` - new budget-discipline skill.
- `.claude/skills/frame-budget-guardian/SKILL.md` - compatibility mirror.
- `.agents/skills/save-load-regression-guard/SKILL.md` - new save/load regression skill.
- `.claude/skills/save-load-regression-guard/SKILL.md` - compatibility mirror.

### Acceptance tests
- [x] `world-perf-doctor`, `loading-lag-hunter`, `frame-budget-guardian`, and `save-load-regression-guard` exist in `.agents/skills/` and mirrored `.claude/skills/` — passed (`Get-FileHash` shows each mirror pair has matching SHA256)
- [x] each performance skill description contains concrete Russian and English trigger phrases — passed (`Select-String` found `лагает` + `interactive world hitch`, `долгая загрузка` + `boot too slow`, `пересчитать всё сразу` + `frame spike`, `после загрузки сломалось` + `save/load regression`)
- [x] each skill references `PERFORMANCE_CONTRACTS.md` or the relevant Station Mirny contract documents — passed (`Select-String` found contract doc references in each file)
- [x] the skills remain narrow and do not duplicate each other — passed (file reads confirm distinct ownership and explicit boundary lines for world hitch, loading/streaming, budget-law review, and save/load regression scopes)

### Contract/API documentation check
- Grep DATA_CONTRACTS.md for `world-perf-doctor`: 0 matches — not referenced
- Grep DATA_CONTRACTS.md for `loading-lag-hunter`: 0 matches — not referenced
- Grep DATA_CONTRACTS.md for `frame-budget-guardian`: 0 matches — not referenced
- Grep DATA_CONTRACTS.md for `save-load-regression-guard`: 0 matches — not referenced
- Grep PUBLIC_API.md for `world-perf-doctor`: 0 matches — not referenced
- Grep PUBLIC_API.md for `loading-lag-hunter`: 0 matches — not referenced
- Grep PUBLIC_API.md for `frame-budget-guardian`: 0 matches — not referenced
- Grep PUBLIC_API.md for `save-load-regression-guard`: 0 matches — not referenced
- Spec "Required contract and API updates" section: exists — deferred to iteration 6 as documented debt

### Out-of-scope observations
- `rg.exe` is not runnable in this environment because the packaged binary returns access denied, so verification used PowerShell `Select-String`, `Test-Path`, and `Get-FileHash` instead.

### Remaining blockers
- Iteration 3 lore and narrative skills are not implemented yet.

### DATA_CONTRACTS.md updated
- Not required for iteration 2 — grep confirmed 0 matches for all changed skill names.

### PUBLIC_API.md updated
- Not required for iteration 2 — grep confirmed 0 matches for all changed skill names.

#### Blockers
- none

### Iteration 3 - Lore and narrative bundle
**Status**: completed
**Started**: 2026-04-02
**Completed**: 2026-04-02

#### Acceptance tests
- [x] `lore-bible-architect`, `faction-voice-keeper`, and `poi-story-seeder` exist in `.agents/skills/` and mirrored `.claude/skills/` - verified by `Get-FileHash` parity across each `.agents`/`.claude` pair
- [x] lore skills reference `docs/03_content_bible/lore/canon.md` - verified by `Select-String` matches in all three `.agents` skill files
- [x] lore skills distinguish locked canon from open expansion space - verified by `Select-String` matches for `locked canon`, `open expansion`, and `open questions`
- [x] at least one skill handles place-based storytelling rather than only abstract lore essays - verified by `Select-String` matches for `place-based`, `environmental storytelling`, and `specific place` in `poi-story-seeder`

#### Doc check
- [x] Grep DATA_CONTRACTS.md for changed names - `lore-bible-architect|faction-voice-keeper|poi-story-seeder` -> 0 matches
- [x] Grep PUBLIC_API.md for changed names - `lore-bible-architect|faction-voice-keeper|poi-story-seeder` -> 0 matches
- [x] Documentation debt section reviewed - still pending, not due until iteration 6

#### Files touched
- `.Codex/agent-memory/active-epic.md` - tracked iteration 3 progress, evidence, and completion; advanced current iteration to 4
- `.agents/skills/lore-bible-architect/SKILL.md` - created canon-safe lore architecture skill
- `.claude/skills/lore-bible-architect/SKILL.md` - created compatibility mirror
- `.agents/skills/faction-voice-keeper/SKILL.md` - created faction and diegetic voice control skill
- `.claude/skills/faction-voice-keeper/SKILL.md` - created compatibility mirror
- `.agents/skills/poi-story-seeder/SKILL.md` - created place-based storytelling and POI narrative skill
- `.claude/skills/poi-story-seeder/SKILL.md` - created compatibility mirror

#### Closure report
## Closure Report

### Implemented
- Created `lore-bible-architect` in `.agents/skills/` and mirrored it in `.claude/skills/`.
- Created `faction-voice-keeper` in `.agents/skills/` and mirrored it in `.claude/skills/`.
- Created `poi-story-seeder` in `.agents/skills/` and mirrored it in `.claude/skills/`.
- Grounded all three lore skills in `docs/03_content_bible/lore/canon.md` and `open_questions.md`.
- Encoded locked-canon versus expansion-space handling so lore work does not silently rewrite canon.

### Root cause
- The skill pack had routing and performance specialists, but it still lacked lore-specific specialists. Lore requests could therefore route into generic creative help without explicit protection for locked canon, in-world voice, or place-based storytelling.

### Files changed
- `.Codex/agent-memory/active-epic.md` - iteration 3 tracking and closure evidence.
- `.agents/skills/lore-bible-architect/SKILL.md` - new canon-aware lore architecture skill.
- `.claude/skills/lore-bible-architect/SKILL.md` - compatibility mirror.
- `.agents/skills/faction-voice-keeper/SKILL.md` - new diegetic voice specialist.
- `.claude/skills/faction-voice-keeper/SKILL.md` - compatibility mirror.
- `.agents/skills/poi-story-seeder/SKILL.md` - new place-based storytelling specialist.
- `.claude/skills/poi-story-seeder/SKILL.md` - compatibility mirror.

### Acceptance tests
- [x] `lore-bible-architect`, `faction-voice-keeper`, and `poi-story-seeder` exist in `.agents/skills/` and mirrored `.claude/skills/` - passed (`Get-FileHash` shows each mirror pair has matching SHA256)
- [x] lore skills reference `docs/03_content_bible/lore/canon.md` - passed (`Select-String` found the canon path in all three `.agents` skill files)
- [x] lore skills distinguish locked canon from open expansion space - passed (`Select-String` found `locked canon`, `open expansion`, and `open questions` across the new skill files)
- [x] at least one skill handles place-based storytelling rather than only abstract lore essays - passed (`Select-String` found `place-based`, `environmental storytelling`, and `specific place` in `poi-story-seeder`)

### Contract/API documentation check
- Grep DATA_CONTRACTS.md for `lore-bible-architect`: 0 matches - not referenced
- Grep DATA_CONTRACTS.md for `faction-voice-keeper`: 0 matches - not referenced
- Grep DATA_CONTRACTS.md for `poi-story-seeder`: 0 matches - not referenced
- Grep PUBLIC_API.md for `lore-bible-architect`: 0 matches - not referenced
- Grep PUBLIC_API.md for `faction-voice-keeper`: 0 matches - not referenced
- Grep PUBLIC_API.md for `poi-story-seeder`: 0 matches - not referenced
- Spec "Required contract and API updates" section: exists - deferred to iteration 6 as documented debt

### Out-of-scope observations
- A legacy `.claude/agent-memory/active-epic.md` tracker also exists alongside `.Codex/agent-memory/active-epic.md`; if both remain in use, they may drift.

### Remaining blockers
- none

### DATA_CONTRACTS.md updated
- Not required for iteration 3 - grep confirmed 0 matches for all changed skill names.

### PUBLIC_API.md updated
- Not required for iteration 3 - grep confirmed 0 matches for all changed skill names.

#### Blockers
- none

### Iteration 4 - UI and player-facing presentation bundle
**Status**: pending

### Iteration 5 - Content and workflow bundle
**Status**: pending

### Iteration 6 - Validation, mirror sync, and cleanup
**Status**: pending
