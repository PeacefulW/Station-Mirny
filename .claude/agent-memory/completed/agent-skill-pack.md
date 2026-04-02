# Epic: Agent Skill Pack

**Spec**: docs/02_system_specs/meta/agent_skill_pack.md
**Started**: 2026-04-02
**Current iteration**: 6
**Total iterations**: 6

## Documentation debt

- [x] `AGENTS.md` — canonical project skill path now points to `.agents/skills/`, keeps `.claude/skills/` as compatibility mirror, and no longer hardcodes a stale workstation-specific Codex skill path
- [x] `docs/00_governance/AI_PLAYBOOK.md` — now mentions `Agent Skill Pack`, the canonical `.agents/skills/` location, and the router + specialist model
- [x] `docs/02_system_specs/world/DATA_CONTRACTS.md` — no update required; grep proof recorded in Iteration 6 doc check
- [x] `docs/00_governance/PUBLIC_API.md` — no update required; grep proof recorded in Iteration 6 doc check
- **Deadline**: by the end of Iteration 6
- **Status**: done

## Iterations

### Iteration 1 - Router and governance foundation
**Status**: completed
**Started**: before 2026-04-02
**Completed**: before 2026-04-02

#### Acceptance tests
- [x] `mirny-task-router` exists in `.agents/skills/` and mirrored `.claude/skills/`
- [x] router `description` explicitly mentions performance, lore, UI, balance, and workflow triggers
- [x] the router body instructs the agent to load all relevant companion skills for mixed requests
- [x] the composition matrix is represented in repo documentation or references

#### Doc check
- [x] Pre-tracker repository state reviewed during Iteration 4 start

#### Files touched
- `.agents/skills/mirny-task-router/SKILL.md`
- `.claude/skills/mirny-task-router/SKILL.md`
- `docs/02_system_specs/meta/agent_skill_pack.md`

#### Closure report
- Completed before the active tracker was refreshed on 2026-04-02.

#### Blockers
- none

---

### Iteration 2 - Performance and stability bundle
**Status**: completed
**Started**: before 2026-04-02
**Completed**: before 2026-04-02

#### Acceptance tests
- [x] each performance skill description contains concrete Russian and English trigger phrases
- [x] each skill references `PERFORMANCE_CONTRACTS.md` or the relevant Station Mirny contract documents
- [x] the skills remain narrow and do not duplicate each other

#### Doc check
- [x] Pre-tracker repository state reviewed during Iteration 4 start

#### Files touched
- `.agents/skills/world-perf-doctor/SKILL.md`
- `.agents/skills/loading-lag-hunter/SKILL.md`
- `.agents/skills/frame-budget-guardian/SKILL.md`
- `.agents/skills/save-load-regression-guard/SKILL.md`
- mirrored `.claude/skills/**`

#### Closure report
- Completed before the active tracker was refreshed on 2026-04-02.

#### Blockers
- none

---

### Iteration 3 - Lore and narrative bundle
**Status**: completed
**Started**: before 2026-04-02
**Completed**: before 2026-04-02

#### Acceptance tests
- [x] lore skills reference `docs/03_content_bible/lore/canon.md`
- [x] lore skills distinguish locked canon from open expansion space
- [x] at least one skill handles place-based storytelling rather than only abstract lore essays

#### Doc check
- [x] Pre-tracker repository state reviewed during Iteration 4 start

#### Files touched
- `.agents/skills/lore-bible-architect/SKILL.md`
- `.agents/skills/faction-voice-keeper/SKILL.md`
- `.agents/skills/poi-story-seeder/SKILL.md`
- mirrored `.claude/skills/**`

#### Closure report
- Completed before the active tracker was refreshed on 2026-04-02.

#### Blockers
- none

---

### Iteration 4 - UI and player-facing presentation bundle
**Status**: completed
**Started**: 2026-04-02
**Completed**: 2026-04-02

#### Acceptance tests
- [x] UI skills reference `GAME_VISION_GDD.md` and `NON_NEGOTIABLE_EXPERIENCE.md` — verified with `Select-String` in all three `.agents/skills/*/SKILL.md` files
- [x] at least one UI skill explicitly protects the inside-safe / outside-hostile contrast — verified with `Select-String` hits in `sanctuary-contrast-guardian/SKILL.md`
- [x] wording and localization concerns are separated from visual composition concerns — verified with `Select-String` hits showing `ui-experience-composer` owns composition and `ui-copy-tone-keeper` owns copy/localization concerns

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for new UI skill names — 0 matches for `ui-experience-composer`, `sanctuary-contrast-guardian`, `ui-copy-tone-keeper`
- [x] Grep `PUBLIC_API.md` for new UI skill names — 0 matches for `ui-experience-composer`, `sanctuary-contrast-guardian`, `ui-copy-tone-keeper`
- [x] Documentation debt section reviewed — required updates remain deferred until Iteration 6 per spec section `Required contract and API updates`

#### Files touched
- `.agents/skills/ui-experience-composer/SKILL.md`
- `.agents/skills/sanctuary-contrast-guardian/SKILL.md`
- `.agents/skills/ui-copy-tone-keeper/SKILL.md`
- `.claude/skills/ui-experience-composer/SKILL.md`
- `.claude/skills/sanctuary-contrast-guardian/SKILL.md`
- `.claude/skills/ui-copy-tone-keeper/SKILL.md`
- `.claude/agent-memory/active-epic.md`

#### Closure report
- Iteration 4 added `ui-experience-composer`, `sanctuary-contrast-guardian`, and `ui-copy-tone-keeper` in both `.agents/skills/` and `.claude/skills/`. Each skill now references the canonical product docs, the contrast guard explicitly protects the inside-safe / outside-hostile pillar, copy/localization responsibility is separated from visual composition, and mirror parity was verified by matching file hashes.

#### Blockers
- none

---

### Iteration 5 - Content and workflow bundle
**Status**: completed
**Started**: 2026-04-02
**Completed**: 2026-04-02

#### Acceptance tests
- [x] content workflow skills reference the correct Station Mirny governance and content docs — verified with `Select-String 'docs/'` across all five new `.agents/skills/*/SKILL.md` files, including `AI_PLAYBOOK.md`, `ENGINEERING_STANDARDS.md`, `SYSTEM_INVENTORY.md`, `modding_extension_contracts.md`, `localization_pipeline.md`, `GAME_VISION_GDD.md`, and `NON_NEGOTIABLE_EXPERIENCE.md`
- [x] `bugfix-prompt-smith` outputs prompts aligned with `WORKFLOW.md` — verified with `Select-String` hits for `WORKFLOW.md`, the prompt template sections, `Closure report`, and `grep-check`
- [x] `localization-pipeline-keeper` references `localization_pipeline.md` — verified with `Select-String` hits for `docs/02_system_specs/meta/localization_pipeline.md` plus `message_key` / `message_args` guidance

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for new Iteration 5 skill names — 0 matches for `content-pipeline-author`, `localization-pipeline-keeper`, `balance-simulator`, `bugfix-prompt-smith`, `playtest-triage`
- [x] Grep `PUBLIC_API.md` for new Iteration 5 skill names — 0 matches for `content-pipeline-author`, `localization-pipeline-keeper`, `balance-simulator`, `bugfix-prompt-smith`, `playtest-triage`
- [x] Documentation debt section reviewed — required contract/API updates remain deferred until Iteration 6 per spec section `Required contract and API updates`

#### Files touched
- `.agents/skills/content-pipeline-author/SKILL.md`
- `.agents/skills/localization-pipeline-keeper/SKILL.md`
- `.agents/skills/balance-simulator/SKILL.md`
- `.agents/skills/bugfix-prompt-smith/SKILL.md`
- `.agents/skills/playtest-triage/SKILL.md`
- `.claude/skills/content-pipeline-author/SKILL.md`
- `.claude/skills/localization-pipeline-keeper/SKILL.md`
- `.claude/skills/balance-simulator/SKILL.md`
- `.claude/skills/bugfix-prompt-smith/SKILL.md`
- `.claude/skills/playtest-triage/SKILL.md`
- `.claude/agent-memory/active-epic.md`

#### Closure report
- Iteration 5 added `content-pipeline-author`, `localization-pipeline-keeper`, `balance-simulator`, `bugfix-prompt-smith`, and `playtest-triage` in both `.agents/skills/` and `.claude/skills/`. The new skills now cover content wiring, localization discipline, balance reasoning, bugfix-prompt shaping, and playtest-note triage with Station Mirny-specific doc references and trigger phrasing. Mirror parity was verified by matching file hashes, and contract/API grep checks confirmed no required `DATA_CONTRACTS.md` or `PUBLIC_API.md` updates at this iteration.

#### Blockers
- none

### Iteration 6 - Validation, mirror sync, and cleanup
**Status**: completed
**Started**: 2026-04-02
**Completed**: 2026-04-02

#### Acceptance tests
- [x] all new project skills pass the skill validation command — verified by running `C:\codex-data\skills\.system\skill-creator\scripts\quick_validate.py` through `C:\Users\peaceful\AppData\Local\Programs\Python\Python314\python.exe` across all 19 `.agents/skills/*` folders and all 19 `.claude/skills/*` mirrors; every run returned `Skill is valid!`
- [x] `.agents/skills/` and `.claude/skills/` stay in sync for the implemented pack — verified by SHA256 parity check showing `Match=True` for all 19 mirrored `SKILL.md` files after syncing `persistent-tasks`
- [x] no project skill depends on undocumented repo-specific assumptions — verified with `Select-String` returning `0` matches for `\.Codex`, `C:\\Users\\`, and `C:\\Users\\progi\\\.codex` across `.agents/skills/*/SKILL.md`

#### Doc check
- [x] Grep `DATA_CONTRACTS.md` for changed names — `mirny-task-router`: 0, `persistent-tasks`: 0, `verification-before-completion`: 0, `Agent Skill Pack`: 0
- [x] Grep `PUBLIC_API.md` for changed names — `mirny-task-router`: 0, `persistent-tasks`: 0, `verification-before-completion`: 0, `Agent Skill Pack`: 0
- [x] Documentation debt section reviewed — final-iteration requirements from spec section `Required contract and API updates` completed (`AGENTS.md` and `AI_PLAYBOOK.md` verified/updated, `DATA_CONTRACTS.md` and `PUBLIC_API.md` verified as not requiring changes)

#### Files touched
- `.agents/skills/persistent-tasks/SKILL.md`
- `.claude/skills/persistent-tasks/SKILL.md`
- `AGENTS.md`
- `docs/00_governance/AI_PLAYBOOK.md`
- `.claude/agent-memory/active-epic.md`

#### Closure report
## Closure Report

### Implemented
- Synchronized `persistent-tasks` across `.agents/skills/` and `.claude/skills/`, replacing stale runtime-specific wording with shared project-memory guidance under `.claude/agent-memory/`
- Updated `AGENTS.md` so Codex uses `.agents/skills/` as the canonical Station Mirny project skill location, keeps `.claude/skills/` as compatibility mirror, and treats `$CODEX_HOME/skills/` as global/system-only guidance
- Updated `AI_PLAYBOOK.md` to include `Agent Skill Pack` in required reading and to document the canonical project skill location plus the router + specialist model
- Validated every implemented project skill with `quick_validate.py` and re-verified mirror parity across the full pack

### Root cause
- Iteration 6 started with stale skill-location governance in `AGENTS.md` and one drifted mirror pair (`persistent-tasks`) whose `.agents` copy still referenced `.Codex` paths not used by the repository

### Files changed
- `.agents/skills/persistent-tasks/SKILL.md` — replaced stale `.Codex` paths and unified wording with the compatibility mirror
- `.claude/skills/persistent-tasks/SKILL.md` — aligned wording with the canonical `.agents` copy for byte-for-byte mirror parity
- `AGENTS.md` — corrected project-skill routing to `.agents/skills/`, demoted `.claude/skills/` to compatibility mirror, and removed the stale workstation-specific Codex skill path
- `docs/00_governance/AI_PLAYBOOK.md` — added `Agent Skill Pack` as required reading for skill-authoring/routing work and documented the router + specialist model
- `.claude/agent-memory/active-epic.md` — recorded Iteration 6 verification evidence and cleared documentation debt

### Acceptance tests
- [x] all new project skills pass the skill validation command — passed (`quick_validate.py` returned `Skill is valid!` for all 19 `.agents/skills/*` folders and all 19 `.claude/skills/*` mirrors)
- [x] `.agents/skills/` and `.claude/skills/` stay in sync for the implemented pack — passed (SHA256 parity check returned `Match=True` for all 19 mirrored `SKILL.md` files)
- [x] no project skill depends on undocumented repo-specific assumptions — passed (`Select-String` returned 0 matches for `\.Codex`, `C:\\Users\\`, and `C:\\Users\\progi\\\.codex` across `.agents/skills/*/SKILL.md`)

### Contract/API documentation check
- Grep `DATA_CONTRACTS.md` for `mirny-task-router`: 0 matches
- Grep `DATA_CONTRACTS.md` for `persistent-tasks`: 0 matches
- Grep `DATA_CONTRACTS.md` for `verification-before-completion`: 0 matches
- Grep `DATA_CONTRACTS.md` for `Agent Skill Pack`: 0 matches
- Grep `PUBLIC_API.md` for `mirny-task-router`: 0 matches
- Grep `PUBLIC_API.md` for `persistent-tasks`: 0 matches
- Grep `PUBLIC_API.md` for `verification-before-completion`: 0 matches
- Grep `PUBLIC_API.md` for `Agent Skill Pack`: 0 matches
- Section `Required contract and API updates` in spec: exists — completed in this iteration (`AGENTS.md` and `AI_PLAYBOOK.md` verified/updated; `DATA_CONTRACTS.md` and `PUBLIC_API.md` verified as not requiring changes)

### Out of scope observations
- none

### Remaining blockers
- none

### DATA_CONTRACTS.md updated
- not required — grep confirmed 0 matches for `mirny-task-router`, `persistent-tasks`, `verification-before-completion`, and `Agent Skill Pack`

### PUBLIC_API.md updated
- not required — grep confirmed 0 matches for `mirny-task-router`, `persistent-tasks`, `verification-before-completion`, and `Agent Skill Pack`

#### Blockers
- none
