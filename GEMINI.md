# Gemini CLI Entry Contract

This repository is Station Mirny, a Godot 4 project.

## Source Of Truth

- `AGENTS.md` is the operational entrypoint for agent work in this repository.
- Canonical project documents override this file according to `docs/00_governance/DOCUMENT_PRECEDENCE.md`.
- If Gemini CLI loads this file without `AGENTS.md`, stop and read `AGENTS.md` before making changes.

## Required Start

Before coding, editing docs, or exploring code:

1. Read `AGENTS.md`.
2. Read the user task.
3. Read `docs/00_governance/WORKFLOW.md`.
4. Read `docs/00_governance/PUBLIC_API.md`.
5. Read the relevant feature spec, if the task has one.
6. Read the relevant subsystem contract, if the task touches a governed subsystem.
7. Only then read the exact files named by the task, spec, contract, or public API.

For world, chunk, mining, topology, reveal, fog, or presentation tasks, read `docs/02_system_specs/world/DATA_CONTRACTS.md` before code.

## Scope Discipline

- Do the requested step only.
- Prefer the smallest valid change that satisfies the task, spec, contract, and acceptance tests.
- Do not run broad repository audits or recursive context gathering just to understand the project.
- Do not implement future iterations early.
- Do not fix adjacent issues unless the user explicitly asks.
- Record out-of-scope observations in the closure report instead of expanding scope.

## Contract And API Discipline

- Do not change data-layer ownership, safe entry points, public API semantics, lifecycle semantics, save/load behavior, or boot/readiness semantics silently.
- If a task changes a contract or public API, update the canonical docs in the same task.
- Before closing, provide grep evidence for whether `DATA_CONTRACTS.md` and `PUBLIC_API.md` needed updates, following `docs/00_governance/WORKFLOW.md`.

## Gemini CLI Use

- Use `/memory show` after launching Gemini CLI if you need to confirm loaded context.
- Do not use `gemini --all-files` in this repository unless the user explicitly requests it.
- Keep Google auth, API keys, and `.env` secrets out of the repository. Use Gemini CLI login or user-level environment variables.
- Project-local settings live in `.gemini/settings.json`; generated Gemini state should stay outside versioned source unless explicitly intended.

## Required Closure

Every completed task needs a closure report in the format required by `docs/00_governance/WORKFLOW.md`, including:

- implemented changes;
- root cause, when applicable;
- files changed;
- acceptance tests with real verification commands or manual proof;
- contract/API documentation check with grep evidence;
- out-of-scope observations;
- remaining blockers.
