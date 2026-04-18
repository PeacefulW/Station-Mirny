---
name: balance-simulator
description: >
  Reason about Station Mirny balance, progression pacing, resource pressure,
  expedition cost, and strategic tradeoffs. Use when the user asks "сбалансируй",
  "слишком легко", "слишком сложно", "дорого", "дешево", "balance",
  "progression tuning", or wants to discuss economy, power/O2 pressure, reward
  loops, or dominant strategies.
---

# Balance Simulator

Use this skill for Station Mirny tuning and progression analysis.

This skill helps the agent reason about whether a change preserves the game's
survival pressure, decision-making texture, and return-to-sanctuary rhythm
instead of treating balance as isolated number tweaking.

## Read first

- `AGENTS.md`
- `docs/01_product/GAME_VISION_GDD.md`
- `docs/01_product/NON_NEGOTIABLE_EXPERIENCE.md`
- the relevant system spec or data surface for the affected economy loop

## What this skill does

1. Translate vague balance discomfort into concrete pressure, pacing, or reward
   problems.
2. Separate pure tuning changes from structural design issues that need a spec.
3. Evaluate whether a proposal strengthens or weakens Station Mirny's expedition
   risk, shelter value, and resource-planning tension.
4. Prefer the smallest tuning set that changes player decisions in the intended
   direction.

## Default workflow

1. Identify which loop is under discussion: resource acquisition, crafting,
   building unlocks, power/O2 upkeep, expedition risk, inventory pressure, or
   return-home timing.
2. Restate the player problem in gameplay terms: too much safety, too little
   scarcity, flat reward, dominant strategy, dead content, or overloaded grind.
3. Compare the complaint against product intent and non-negotiable experience
   rather than tuning in a vacuum.
4. Propose the narrowest change set that shifts the decision landscape.
5. If implementation is requested, keep it in data/config/content lanes unless a
   real system rule must change.

## Typical smells

- one resource or strategy trivializes the rest of the survival loop
- costs are raised blindly and only create grind instead of meaningful tradeoff
- a balance fix removes the outside-hostile / inside-safe contrast
- new content invalidates earlier progression with no compensating pressure
- a complaint that sounds like balance is actually a copy, onboarding, or UX issue

## Compose with other skills

- Load `content-pipeline-author` when balance changes are implemented through
  items, recipes, buildings, flora, or POI content.
- Load `playtest-triage` when the input is a messy pile of player notes rather
  than a clean tuning request.
- Load `sanctuary-contrast-guardian` when the proposal affects perceived safety,
  darkness pressure, or the emotional role of the base.

## Boundaries

- Do not use this as the main skill for content plumbing or localization.
- Do not hide a structural design rewrite inside a "small balance tweak".
- Do not optimize for spreadsheet neatness over Station Mirny's intended feel.
