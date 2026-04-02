---
title: Agent Skill Pack
doc_type: system_spec
status: draft
owner: engineering+design
source_of_truth: true
version: 0.1
last_updated: 2026-04-02
related_docs:
  - ../../00_governance/AI_PLAYBOOK.md
  - ../../00_governance/WORKFLOW.md
  - ../../00_governance/ENGINEERING_STANDARDS.md
  - ../../00_governance/PERFORMANCE_CONTRACTS.md
  - ../../00_governance/SYSTEM_INVENTORY.md
  - ../../01_product/GAME_VISION_GDD.md
  - ../../01_product/NON_NEGOTIABLE_EXPERIENCE.md
  - ../../03_content_bible/lore/canon.md
---

# Agent Skill Pack

This document defines the canonical project-specific skill pack for Station Mirny.

It exists to solve a practical problem:

- skills should not be created once and then forgotten
- agents should not rely on user hand-holding to remember which skill to use
- broad Station Mirny requests should route into the correct combination of project skills
- performance, lore, UI, and production tasks should be handled with project-aware heuristics rather than generic advice

## Purpose

This spec owns:

- the Station Mirny project skill pack
- the split between project skills and global/system skills
- the trigger architecture that makes relevant skills activate reliably
- the multi-skill composition rules for common task categories
- the iteration plan for implementing and validating the pack

This spec does not own:

- generic Codex system skills outside this repository
- runtime gameplay architecture
- public gameplay APIs
- lore canon itself
- performance law itself

Those remain owned by the canonical governance, product, and content documents listed above.

## Design intent

The desired behavior is:

- when the user reports long boot, loading hitch, or chunk streaming pain, the agent should apply both routing logic and the relevant performance skills
- when the user asks to expand, rewrite, or deepen lore, the agent should apply both routing logic and the relevant lore skills
- when the user asks to make UI prettier or more atmospheric, the agent should apply both routing logic and the relevant UI/experience skills
- when the user asks for new content, bugfix prompts, balance tuning, or playtest triage, the agent should proactively load the relevant project workflow skills

The skill pack should make that behavior the default path rather than a lucky accident.

## Core problem statement

The repository already has project skills, but the current pack is too narrow:

- it helps when the task obviously matches `brainstorming`, `persistent-tasks`, or `verification-before-completion`
- it does not yet provide a broad Station Mirny task router
- it does not yet encode the most common multi-skill combinations
- it does not yet separate project-specific behavior from global reusable skills clearly enough

As a result, an agent can still answer correctly but too generically.
That is not enough for this project.

## Architectural statement

Station Mirny uses a **router + specialist** skill model.

Canonical rule:

- one broad project router skill is responsible for recognizing common Station Mirny task families
- specialist skills own narrow, reusable workflows for one domain
- a single user request may and often should activate multiple project skills
- the router does not replace existing skills such as `brainstorming`, `persistent-tasks`, or `verification-before-completion`; it composes with them

## Skill placement model

### Project-specific skills

Project-specific skills belong in:

- `.agents/skills/`

These are skills that:

- reference Station Mirny docs directly
- encode Station Mirny product pillars or lore canon
- rely on Station Mirny governance and workflow
- reference Station Mirny file paths, systems, or performance expectations

### Compatibility mirror

Until legacy tooling that still expects `.claude/skills/` is retired, every project skill should have a mirrored copy in:

- `.claude/skills/`

Canonical authoring target for new work is still:

- `.agents/skills/`

The mirror exists for compatibility, not as a second source of truth.

### Global/system skills

Global reusable skills belong outside the repository in the Codex skill home such as:

- `$CODEX_HOME/skills`

These are skills that:

- do not reference Station Mirny docs
- are useful across unrelated repositories
- are generic tooling or product-integration helpers

Examples already fitting this category:

- `skill-creator`
- `skill-installer`
- `plugin-creator`
- `imagegen`
- `openai-docs`

Canonical rule:

If a skill contains Station Mirny-specific paths, lore rules, product pillars, or governance references, it is not a global skill.

## Required trigger design rules

To make skills activate reliably, every project skill must follow these metadata rules:

### Rule 1: Put all trigger logic in YAML `description`

The description must state:

- what the skill does
- concrete user intents
- symptom words and scenario phrases that should trigger it

### Rule 2: Include user-language patterns

Descriptions should explicitly include phrasing patterns such as:

- `долгая загрузка`
- `долгий запуск`
- `лагает`
- `фризит`
- `как расширить лор`
- `переписать лор`
- `сделать интерфейс красивее`
- `улучшить атмосферу`
- `придумай POI`
- `составь промпт для фикса`

The exact list may evolve, but descriptions must contain real phrasing, not only abstract categories.

### Rule 3: Router skill should be broad but concise

The router skill must trigger on the common Station Mirny request families, but its body must stay concise.
It should classify and hand off, not become a giant replacement for every specialist skill.

### Rule 4: Specialist skills should be narrow and composable

Each specialist skill should own:

- one domain
- one reusable workflow
- one bundle of references and checks

It should not absorb adjacent domains just because they are related.

### Rule 5: Multi-skill composition is required

If a task naturally spans multiple domains, the agent should use all relevant project skills.

Examples:

- loading hitch -> router + loading/perf skill + budget/perf-contract skill
- lore expansion -> router + lore canon skill + faction/voice or POI skill
- UI polish -> router + UI composition skill + sanctuary/contrast skill

## Canonical skill pack

The following project skills define the target pack.

### Tier 0: Always-relevant project routing and governance

#### `mirny-task-router`

Role:

- broad Station Mirny task classifier
- selects which specialist skills to load
- enforces multi-skill composition for common requests

Use when:

- the user asks about Station Mirny implementation, performance, content, lore, UI, balance, or workflow
- the task is broad enough that a single specialist skill would miss adjacent needs

#### `brainstorming` (existing)

Role:

- early design exploration before a feature spec exists

#### `persistent-tasks` (existing)

Role:

- persistent memory for multi-iteration work

#### `verification-before-completion` (existing)

Role:

- proof-based closure and documentation checks

### Tier 1: Performance and stability

#### `world-perf-doctor`

Role:

- diagnose hitchy world interactions
- trace local hot paths against `PERFORMANCE_CONTRACTS.md`
- propose smallest-valid fixes that preserve data and ownership contracts

Target scenarios:

- mining hitch
- building placement hitch
- chunk seam redraw cost
- topology/reveal/shadow churn

#### `loading-lag-hunter`

Role:

- diagnose long boot, loading-screen drag, streaming spikes, and first-playable delays

Target scenarios:

- `долгая загрузка`
- `долго стартует`
- `долго загружается мир`
- `boot too slow`
- `streaming hitch`

#### `frame-budget-guardian`

Role:

- enforce background-vs-interactive budget discipline
- detect when a proposal violates dirty-queue or budget rules

Target scenarios:

- any optimization or new feature that risks full rebuilds, large loops, or sync world work

#### `save-load-regression-guard`

Role:

- check that new systems, content mutations, and refactors still respect save/load boundaries and runtime diff ownership

Target scenarios:

- changes touching persistence
- changes that add new runtime state
- fixes where the bug appears after save/load

### Tier 2: Lore and narrative content

#### `lore-bible-architect`

Role:

- expand or reorganize lore while preserving canon from `docs/03_content_bible/lore/canon.md`

Target scenarios:

- `как расширить лор`
- `переделай лор`
- `придумай глубже мифологию`
- `собери лор-библию`

#### `faction-voice-keeper`

Role:

- maintain distinct voice, ideology, terminology, and subtext for factions, archives, and diegetic text sources

Target scenarios:

- faction writing
- archive logs
- transmission tone
- text that needs a specific in-world voice

#### `poi-story-seeder`

Role:

- generate place-based story hooks, ruin history, discovery beats, and environmental storytelling

Target scenarios:

- POI ideas
- ruins
- environmental storytelling
- diaries, logs, notes, terminals tied to locations

### Tier 3: UI, atmosphere, and player-facing presentation

#### `ui-experience-composer`

Role:

- shape UI ideas as game-feel and readability work, not only layout work

Target scenarios:

- `сделай интерфейс красивее`
- `улучши HUD`
- `сделай меню атмосфернее`
- `хочу чтобы UI ощущался лучше`

#### `sanctuary-contrast-guardian`

Role:

- enforce the non-negotiable Station Mirny contrast:
  inside safe / outside hostile
  light safe / darkness threatening

Target scenarios:

- UI, lighting-facing presentation, base readability, and scene feel discussions
- any visual proposal that risks flattening the sanctuary-vs-exposure contrast

#### `ui-copy-tone-keeper`

Role:

- keep player-facing copy consistent with Station Mirny tone, localization model, and information clarity

Target scenarios:

- button text
- HUD messages
- menu labels
- tutorial and system text

### Tier 4: Production workflow and implementation support

#### `content-pipeline-author`

Role:

- add or change items, buildings, recipes, flora, POIs, and similar content through the correct registry/data/localization path

Target scenarios:

- new content definitions
- content expansion
- content wiring tasks spanning data and UI exposure

#### `localization-pipeline-keeper`

Role:

- enforce the localization pipeline when new user-facing content or UI text is introduced

Target scenarios:

- any task adding player-visible strings
- lore text shipping through UI or data resources

#### `balance-simulator`

Role:

- reason about progression pacing, resource pressure, expedition cost, power/O2 economy, and strategic tradeoffs

Target scenarios:

- balance discussion
- progression tuning
- cost/reward loops
- expedition and return-home rhythm

#### `bugfix-prompt-smith`

Role:

- turn a vague bug report into a narrow, contract-aware implementation prompt that follows `WORKFLOW.md`

Target scenarios:

- `составь промпт на фикс`
- `преврати это в задачу для агента`
- ambiguous bug reports that need proper scope fences

#### `playtest-triage`

Role:

- convert raw playtest notes into prioritized actionable tasks with likely root cause and acceptance checks

Target scenarios:

- playtest feedback
- bug list cleanup
- balancing feedback synthesis

## Canonical composition matrix

This matrix defines the expected skill stacks for common Station Mirny requests.

### Long load / boot / streaming hitch

Required stack:

- `mirny-task-router`
- `loading-lag-hunter`
- `frame-budget-guardian`

Add if persistence is involved:

- `save-load-regression-guard`

### Interactive world hitch

Required stack:

- `mirny-task-router`
- `world-perf-doctor`
- `frame-budget-guardian`

### Lore expansion or rewrite

Required stack:

- `mirny-task-router`
- `lore-bible-architect`

Add depending on scope:

- `faction-voice-keeper`
- `poi-story-seeder`

### UI polish / atmosphere / readability

Required stack:

- `mirny-task-router`
- `ui-experience-composer`
- `sanctuary-contrast-guardian`

Add if wording is affected:

- `ui-copy-tone-keeper`
- `localization-pipeline-keeper`

### New content or content wiring

Required stack:

- `mirny-task-router`
- `content-pipeline-author`

Add depending on scope:

- `localization-pipeline-keeper`
- `balance-simulator`
- `save-load-regression-guard`

### Bugfix prompt generation

Required stack:

- `mirny-task-router`
- `bugfix-prompt-smith`

Add depending on area:

- relevant specialist skill for the affected domain

## Files and ownership

### Files to be created or maintained in implementation iterations

- `.agents/skills/<skill-name>/SKILL.md`
- optional `.agents/skills/<skill-name>/agents/openai.yaml`
- optional `.agents/skills/<skill-name>/references/*`
- optional `.agents/skills/<skill-name>/scripts/*`
- mirrored copies under `.claude/skills/<skill-name>/...` while compatibility is required

### Files explicitly out of scope for this skill-pack effort

- gameplay runtime code unrelated to skill docs
- public gameplay API files unless a task later explicitly updates them
- unrelated system specs

## Iterations

### Iteration 1 - Router and governance foundation

Goal:

- establish the routing architecture and project-vs-system split

What is done:

- create `mirny-task-router`
- align or tighten descriptions of existing project governance skills where needed
- document the composition matrix
- document `.agents/skills/` as canonical authoring path and `.claude/skills/` as compatibility mirror

Acceptance tests:

- [ ] `mirny-task-router` exists in `.agents/skills/` and mirrored `.claude/skills/`
- [ ] router `description` explicitly mentions performance, lore, UI, balance, and workflow triggers
- [ ] the router body instructs the agent to load all relevant companion skills for mixed requests
- [ ] the composition matrix is represented in repo documentation or references

Files that may be touched:

- `.agents/skills/mirny-task-router/**`
- `.claude/skills/mirny-task-router/**`
- existing project skill `SKILL.md` files if descriptions need routing-compatible wording
- this spec

Files that must not be touched:

- gameplay runtime files

### Iteration 2 - Performance and stability bundle

Goal:

- make performance-related requests reliably activate the correct specialist skills

What is done:

- create `world-perf-doctor`
- create `loading-lag-hunter`
- create `frame-budget-guardian`
- create `save-load-regression-guard`

Acceptance tests:

- [ ] each performance skill description contains concrete Russian and English trigger phrases
- [ ] each skill references `PERFORMANCE_CONTRACTS.md` or the relevant Station Mirny contract documents
- [ ] the skills remain narrow and do not duplicate each other

Files that may be touched:

- `.agents/skills/world-perf-doctor/**`
- `.agents/skills/loading-lag-hunter/**`
- `.agents/skills/frame-budget-guardian/**`
- `.agents/skills/save-load-regression-guard/**`
- mirrored `.claude/skills/**`

### Iteration 3 - Lore and narrative bundle

Goal:

- make lore-related requests reliably route into canon-aware creative support

What is done:

- create `lore-bible-architect`
- create `faction-voice-keeper`
- create `poi-story-seeder`

Acceptance tests:

- [ ] lore skills reference `docs/03_content_bible/lore/canon.md`
- [ ] lore skills distinguish locked canon from open expansion space
- [ ] at least one skill handles place-based storytelling rather than only abstract lore essays

Files that may be touched:

- `.agents/skills/lore-bible-architect/**`
- `.agents/skills/faction-voice-keeper/**`
- `.agents/skills/poi-story-seeder/**`
- mirrored `.claude/skills/**`

### Iteration 4 - UI and player-facing presentation bundle

Goal:

- make UI and feel requests route into product-aware presentation work instead of generic interface polish

What is done:

- create `ui-experience-composer`
- create `sanctuary-contrast-guardian`
- create `ui-copy-tone-keeper`

Acceptance tests:

- [ ] UI skills reference `GAME_VISION_GDD.md` and `NON_NEGOTIABLE_EXPERIENCE.md`
- [ ] at least one UI skill explicitly protects the inside-safe / outside-hostile contrast
- [ ] wording and localization concerns are separated from visual composition concerns

Files that may be touched:

- `.agents/skills/ui-experience-composer/**`
- `.agents/skills/sanctuary-contrast-guardian/**`
- `.agents/skills/ui-copy-tone-keeper/**`
- mirrored `.claude/skills/**`

### Iteration 5 - Content and workflow bundle

Goal:

- make content, balance, prompt-shaping, and playtest cleanup requests route into reusable workflows

What is done:

- create `content-pipeline-author`
- create `localization-pipeline-keeper`
- create `balance-simulator`
- create `bugfix-prompt-smith`
- create `playtest-triage`

Acceptance tests:

- [ ] content workflow skills reference the correct Station Mirny governance and content docs
- [ ] `bugfix-prompt-smith` outputs prompts aligned with `WORKFLOW.md`
- [ ] `localization-pipeline-keeper` references `localization_pipeline.md`

Files that may be touched:

- `.agents/skills/content-pipeline-author/**`
- `.agents/skills/localization-pipeline-keeper/**`
- `.agents/skills/balance-simulator/**`
- `.agents/skills/bugfix-prompt-smith/**`
- `.agents/skills/playtest-triage/**`
- mirrored `.claude/skills/**`

### Iteration 6 - Validation, mirror sync, and cleanup

Goal:

- validate the whole pack, remove ambiguity, and ensure compatibility copies are aligned

What is done:

- run skill validation on all project skills
- verify mirror parity between `.agents/skills/` and `.claude/skills/`
- tighten stale descriptions or duplicated guidance
- update any governance docs that still point to the wrong canonical skill location

Acceptance tests:

- [ ] all new project skills pass the skill validation command
- [ ] `.agents/skills/` and `.claude/skills/` stay in sync for the implemented pack
- [ ] no project skill depends on undocumented repo-specific assumptions

Files that may be touched:

- implemented project skill folders
- `AGENTS.md`
- `docs/00_governance/AI_PLAYBOOK.md`
- this spec

## Required contract and API updates

This effort is expected to touch agent workflow documentation, not gameplay APIs or world data contracts.

Expected documentation review at final implementation iteration:

- verify whether `AGENTS.md` still points at the correct project skill path
- verify whether `AI_PLAYBOOK.md` should mention the canonical project skill location or router model
- verify that no update is required in `DATA_CONTRACTS.md`
- verify that no update is required in `PUBLIC_API.md`

Canonical rule:

The final implementation iteration must include grep proof for any claim that `DATA_CONTRACTS.md` or `PUBLIC_API.md` updates are not required.

## Failure signs

The skill pack is wrong if:

- the router is so vague that it never reliably triggers
- the router is so huge that specialist skills become redundant
- performance complaints still route into generic advice instead of Station Mirny performance law
- lore work ignores locked canon
- UI work ignores the sanctuary-vs-exposure contrast
- skill descriptions lack concrete trigger wording
- `.agents/skills/` and `.claude/skills/` drift apart silently

## Final principle

The goal is not to create more files.

The goal is to create a Station Mirny skill pack that actually changes agent behavior:

- the right skills trigger
- multiple relevant skills compose together
- project-specific product, lore, and performance knowledge is applied by default
- the user does not need to babysit the routing decision
