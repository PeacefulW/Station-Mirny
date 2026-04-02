---
name: sanctuary-contrast-guardian
description: >
  Enforce the non-negotiable Station Mirny contrast between inside-safe and
  outside-hostile, light as safety and darkness as pressure. Use when the user
  asks "сделай базу уютнее", "снаружи слишком комфортно", "пропал контраст",
  "нужно сильнее ощущение убежища", discusses atmosphere, base readability,
  HUD/state cues for safety vs exposure, or any visual proposal that risks
  flattening the contrast defined in `docs/01_product/GAME_VISION_GDD.md` and
  `docs/01_product/NON_NEGOTIABLE_EXPERIENCE.md`.
---

# Sanctuary Contrast Guardian

Use this skill to protect Station Mirny's strongest product contrast.

This skill owns the experiential guardrail that the base must read as shelter
and the outside must read as exposure. It is the filter for UI, presentation,
and atmosphere work that could accidentally make every state feel equally safe,
equally noisy, or equally dim.

## Read first

- `docs/01_product/GAME_VISION_GDD.md`
- `docs/01_product/NON_NEGOTIABLE_EXPERIENCE.md`

## What this skill does

1. Test proposals against the core rule: inside feels safe, outside feels hostile.
2. Protect light as comfort, navigation, and authored control rather than mere decoration.
3. Preserve darkness, distance, and uncertainty as real emotional pressure.
4. Strengthen the transition states between safety, preparation, exposure, and return.

## Default workflow

1. Identify which parts of the experience are meant to signal sanctuary,
   exposure, transition, or failure of safety.
2. Check whether palette, brightness, spacing, and state cues make the interior
   feel warm, ordered, and readable without making the exterior emotionally flat.
3. Check whether the outside still communicates cost, uncertainty, and pressure
   even when combat is absent.
4. Recommend stronger visual separation where danger and safety have drifted too
   close together, but keep both readable enough for gameplay.
5. If the request also changes copy or labels, compose with `ui-copy-tone-keeper`
   so wording reinforces the same contrast without replacing it.

## Typical smells

- interior and exterior share the same comfort level, palette, or emotional temperature
- darkness is merely lower brightness instead of incomplete information and risk
- warnings are always screaming, so actual danger no longer feels special
- base screens feel cold and abstract instead of sheltered and authored
- a presentation change makes outside exploration feel casual for too long

## Compose with other skills

- Load `ui-experience-composer` when the request also changes layout, hierarchy,
  interaction feel, or broader UI composition.
- Load `ui-copy-tone-keeper` when safety, alert, tutorial, or menu wording must
  reinforce the same experiential contrast.

## Boundaries

- Do not use this as the main skill for generic UI cleanup that does not affect
  sanctuary versus exposure.
- Do not solve balance, damage, or survival tuning here unless the human explicitly
  asks for design-level contrast work that crosses into those systems.
- Do not let convenience polish erase the world's hostility, darkness, or need for preparation.
