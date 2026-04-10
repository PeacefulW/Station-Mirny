---
name: verification-before-completion
description: >
  Enforces proof-based task completion for Station Mirny. Prevents the agent from
  writing "passed" in a closure report without actually running a verification command.
  This skill activates whenever you are about to write a closure report, finish an
  iteration, claim a task is done, or mark acceptance tests as passed. It also activates
  when you say phrases like "всё готово", "задача выполнена", "acceptance tests пройдены",
  "closure report", or are wrapping up any code change. Also use when
  `mirny-task-router` is active on implementation work that is approaching closure.
  Use this skill even for small fixes - every change deserves proof.
---

# Verification Before Completion

You are working on Station Mirny, a Godot 4 project with strict governance.
The project has a rule: every task ends with a closure report containing acceptance tests
marked passed or failed. This skill exists because agents tend to write "passed" based on
confidence rather than evidence. Confidence is not proof.

## The core problem this skill solves

When an agent writes code, it mentally simulates the result and feels confident it works.
That confidence gets written as `- [x] test — passed` in the closure report. But the code
was never actually executed. The agent never saw real output. "Passed" means "I think it
should pass" — not "I verified it passes."

This is the single most common failure mode in agent-assisted development. It erodes trust
because the human eventually discovers that "passed" was a guess, not a fact.

## The rule

Before writing ANY acceptance test result as "passed" in a closure report, you must have
executed a concrete verification command and seen its output in this session.
The closure report is user-facing: write it in Russian, add the canonical English term in
parentheses for every key section, and introduce important technical terms on first mention
as `русский термин (english term)`. The wording should be understandable to a human without
deep technical background.
User-facing reports are written in Russian with canonical English terms in parentheses.

"Verification command" means one of:

1. **A validation script** from `tools/` that checks the relevant invariant
2. **A grep/search command** that proves the code change exists and has the expected shape
3. **A file read** that shows the final state of the changed code matches the spec
4. **A parse check** — loading a `.tres` resource file and confirming its fields are correct
5. **A static analysis command** — checking for syntax errors, missing types, broken references

What does NOT count as verification:

- Re-reading your own diff (you wrote it — of course it looks right to you)
- Saying "the logic is correct because..." (that's reasoning, not evidence)
- Referencing what you did earlier in the conversation (memory is not proof)
- Running a command but not showing its output

## How to apply this

### Choose the verification mode first

Use one of these three modes before you decide how to verify an acceptance test:

1. `статическая проверка (static verification)`
   - grep, file reads, parse/syntax checks, static analysis, and contract/API grep
   - mandatory for every task
   - sufficient when the acceptance test is fully statically checkable
2. `ручная проверка пользователем (manual human verification)`
   - visual/runtime/perf/world checks that require Godot, headless scenes, play sessions, profiler work, or runtime log review
   - this is the default path unless the human, task spec, or acceptance test explicitly asks you to run them yourself
   - in the closure report, use the bilingual labels `Ручная проверка пользователем (Manual human verification)` and `Рекомендованная проверка пользователем (Suggested human check)`, and explicitly say when `явный runtime-прогон агентом (explicit agent-run runtime verification)` did not run by policy
3. `явный runtime-прогон агентом (explicit agent-run runtime verification)`
   - only when the human, task spec, or acceptance test explicitly requires the agent to run Godot/headless/log tooling
   - if you run it, you must cite the exact command/harness/log output you actually saw

### Step 1: Before writing the closure report, stop

Do not start writing the closure report yet. First, list the acceptance tests from the
task spec or your task definition.

### Step 2: For each acceptance test, determine the verification method

Map each test to a concrete command:

| Acceptance test type | Verification method |
|---|---|
| "Function X exists with signature Y" | `grep -n "func X" <file>` |
| "Resource has field Z with value W" | Read the `.tres` file, show the field |
| "Signal is connected" | `grep -n "connect\|emit" <file>` for the signal name |
| "No hardcoded paths" | `grep -rn 'load("res://' <file>` should return nothing |
| "Localization key used" | `grep -n 'Localization.t' <file>` |
| "Performance: no full rebuild" | Read the function, confirm it operates on dirty region only |
| "Visual/runtime/perf result requires Godot or logs" | Default: mark `требуется ручная проверка пользователем (manual human verification required)` + give a concrete human check; run Godot/headless/logs only if explicitly requested |
| "DATA_CONTRACTS.md updated" | Read the file, show the new/changed section |
| "EventBus signal defined" | `grep -n "signal_name" core/autoloads/event_bus.gd` |

### Step 3: Run each verification command and capture output

Execute the commands. Show the output. If the output confirms the test — mark it passed.
If the output shows a problem — fix it before marking anything.

### Step 4: Verify documentation is up to date (MANDATORY)

This step is as important as verifying code. Other tasks depend on DATA_CONTRACTS.md and
PUBLIC_API.md being accurate. Stale documentation is a silent bug that breaks future work.

**4a. Collect the list of changed function names, constants, and API calls.**

Look at what you changed in code. Extract every function name, constant name, signal name,
and entrypoint that was added, removed, renamed, or had its semantics changed.

**4b. Grep DATA_CONTRACTS.md for each changed name.**

```
grep -n "function_or_constant_name" docs/02_system_specs/world/DATA_CONTRACTS.md
```

If grep returns matches — read the matching invariants. Are they still accurate after your
code change? If an invariant references old behavior (e.g., says `complete_redraw_now()` is
called when you changed it to `complete_terrain_phase_now()`), that invariant is **stale**
and must be updated **in this task**.

**4c. Grep PUBLIC_API.md for each changed name.**

```
grep -n "function_or_constant_name" docs/00_governance/PUBLIC_API.md
```

Same rule: if the description no longer matches actual behavior, update it now.

**4d. Check the spec's "Required contract and API updates" section.**

Many feature specs have a section at the end listing what documentation must be updated after
implementation. Read it. If the spec says "после всех итераций обновить DATA_CONTRACTS.md",
and this is the last iteration — the updates are part of THIS task, not a future one.

**4e. Record evidence in the closure report.**

```
### Проверка документации контрактов и API (Contract/API documentation check)
- Grep DATA_CONTRACTS.md for `changed_function`: [N matches found, lines X, Y — updated/still accurate]
- Grep PUBLIC_API.md for `changed_function`: [N matches found, lines X, Y — updated/still accurate]
- Spec "Required updates" section: [exists/not exists] — [done/not applicable/deferred to iteration N]
```

If grep returns 0 matches and the spec has no required updates section, write:
```
- Grep DATA_CONTRACTS.md for `changed_function`: 0 matches — not referenced
- Grep PUBLIC_API.md for `changed_function`: 0 matches — not referenced
- Обновления документации не требуются (No documentation updates required) — проверено grep
```

**Never write "not required" without running grep first.** "Not required" based on opinion is
the same failure mode as "passed" based on confidence. Prove it.

### Step 5: Write the closure report with evidence references

In the closure report, after each acceptance test, briefly note what verified it:
When you mention key technical terms, introduce them on first use as `русский термин (english term)`, for example `статическая проверка (static verification)`, `основной поток (main thread)`, `правка границы чанка (border_fix)`, or `фоновая догрузка чанков рядом с игроком (stream_load)`.
If you mention an internal debug marker, job name, or jargon such as `stream_load`, `seam_mining_async`, or `roof_restore`, add a plain-Russian explanation for a novice reader right next to it.

```
### Проверки приёмки (Acceptance tests)
- [x] У `BuildCommand` есть `execute()` и `undo()` — прошло (passed); проверено: grep показывает обе функции на строках 34 и 52
- [x] Нет захардкоженных путей загрузки (`load()` paths) — прошло (passed); проверено: grep вернул 0 совпадений
- [ ] Smoke test — блокировано (BLOCKED): нужен runtime редактора Godot
```

For tests that cannot be verified in the current environment (like "run the game and see X"),
mark them honestly as `блокировано (BLOCKED)` with the reason, not as passed.

## Station Mirny specific verification patterns

### For world/chunk/mining tasks
- Read `DATA_CONTRACTS.md` after your changes and confirm the invariants section matches
- If you added a new layer or writer, show the updated section
- If the task involves tile operations, verify the dirty-region pattern (no full chunk redraw)

### For building/power/O2 tasks
- Verify the command object exists with `execute()` method
- Verify EventBus signal is emitted (grep for emit call)
- Verify resource `.tres` file has correct fields

### For save/load tasks
- Show that save collector and applier handle the new data
- Verify save version compatibility note exists if format changed

### For localization tasks
- Show the `.po` file entry exists
- Verify code uses `Localization.t("KEY")` not raw strings

## What to do when runtime verification is not part of your default scope

Some acceptance tests require running the Godot editor/game, headless scenes, or reading
runtime logs. Do not auto-escalate into that work "just to be safe". Unless the human,
task spec, or acceptance test explicitly tells you to run it yourself, treat it as
`ручная проверка пользователем (manual human verification)` and hand it off honestly:

```
### Проверки приёмки (Acceptance tests)
- [x] Структура кода соответствует спецификации (spec) — прошло (passed); проверено: чтение файла подтверждает ожидаемый паттерн
- [ ] Визуальный результат корректен в игре — требуется ручная проверка пользователем (manual human verification required); рекомендованная проверка пользователем (Suggested human check): открыть нужную сцену и проверить изменённую подачу на экране (presentation)
- [ ] Runtime/perf результат подтверждён в Godot/logs — требуется ручная проверка пользователем (manual human verification required); явный runtime-прогон агентом (explicit agent-run runtime verification): не запускался в этой задаче по policy; рекомендованная проверка пользователем (Suggested human check): запустить указанный сценарий и проверить ожидаемые метки в логе (markers)
- [x] В изменённом пути выполнения (code path) нет регрессии производительности — прошло (passed); проверено: функция читает только dirty tiles, без full loop
```

The human will run the game and check visual/runtime tests when needed. Your job is to verify
everything that CAN be verified statically, and leave a concrete human handoff for the rest.
If explicit agent-run runtime verification was requested but the environment blocks it, then
mark that test as `блокировано (BLOCKED)` and explain why. `Требуется ручная проверка пользователем (manual human verification required)` is the honest
default when runtime proof was not requested; `BLOCKED` is for requested proof you could not execute.

## The contract

By using this skill, you commit to:
1. Never writing "passed" without showing evidence in the same session
2. Never marking a test as passed when it's actually pending manual human verification or blocked by environment limitations
3. Always running at least one concrete verification command before the closure report
4. If all tests are trivially passable without commands (e.g., "I created file X" — then show `ls` output confirming the file exists)
5. Always running grep on DATA_CONTRACTS.md and PUBLIC_API.md for every changed function/constant/signal before writing the closure report
6. Never writing "DATA_CONTRACTS.md updated — not required" without grep evidence showing 0 relevant matches
7. If the feature spec has a "Required contract and API updates" section, checking it and acting on it — especially on the last iteration
8. Never auto-escalating into Godot/headless/log review unless the human, task spec, or acceptance test explicitly requests it; otherwise leave a concrete manual handoff

This is not bureaucracy. This is how trust is built between the agent and the human.
