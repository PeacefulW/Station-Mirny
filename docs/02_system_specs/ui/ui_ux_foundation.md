---
title: UI and UX Foundation
doc_type: system_spec
status: approved
owner: design+engineering
source_of_truth: true
version: 1.2
last_updated: 2026-07-23
related_docs:
  - ../../01_product/GAME_VISION_GDD.md
---

# UI and UX Foundation

## Purpose

UI must support a hostile-world survival fantasy while keeping the screen readable and the base understandable.

## Core statement

The game should favor:
- minimal always-on HUD
- context-rich PDA-style deep interfaces
- clear build and overlay modes

## HUD philosophy

Always-on UI should stay minimal and high-signal:
- oxygen
- suit battery
- heading/base reference
- quiet navigation readouts such as the current tile coordinates
- only urgent state warnings

## PDA / deep interface

The wrist-device style interface can own:
- map
- inventory
- stats/skills
- decryption tree
- journal/logs
- production and logistics configuration

## Build UX

The building experience should use:
- explicit build mode
- ghost placement
- engineering overlays
- strong readability of invalid vs valid placement

## World loading surface

The world loading screen is a full-viewport, input-blocking boot/load surface.
It is shown before a new world scene can expose its viewport and is recreated
for an in-place world reload.

- progress and stage copy are driven only by
  `WorldStreamer.get_initial_loading_state()`;
- the bar represents completed authoritative per-chunk readiness stages, not
  elapsed time or an animation;
- no timeout may dismiss the screen;
- the screen remains visible until the maximum zoom-out envelope and movement
  reserve are complete, then performs only a short visual fade;
- player processing remains disabled through the first unobscured world frame;
- stage labels and count text use localization keys in every supported locale;
- detailed performance numbers remain probe/closure evidence rather than noisy
  player-facing boot UI.

## Acceptance criteria

- players can read danger at a glance
- deeper systems do not pollute the main screen
- build mode feels precise rather than noisy
