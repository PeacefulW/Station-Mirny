---
title: UI and UX Foundation
doc_type: system_spec
status: approved
owner: design+engineering
source_of_truth: true
version: 1.4
last_updated: 2026-08-03
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

## HUD presentation contract

The always-on HUD is composed of three clusters, never of free-floating labels:
- top-left survival cluster: oxygen, health, shelter state, build context;
- top-right environment cluster: time and phase, wind, weather, quiet navigation;
- bottom-center action bar: the inputs that are meaningful right now.

Presentation rules for those clusters:
- clusters sit on translucent glass plates - rounded, semi-transparent, thin
  warm edge, soft shadow; the world must stay visible through the interface and
  opaque panels or hard black backing plates are not allowed;
- one display-weight value per cluster (oxygen percentage, clock); everything
  else is small tracked caps, and navigation readouts are the quietest tier;
- pictograms are vector glyphs drawn in code and recolored by state, so a new
  indicator never requires a second raster icon pipeline;
- oxygen is the only permanently visible meter; health appears only when the
  player is damaged, so the appearance of a bar is itself a signal;
- meters are segmented rather than smooth, and only a critical meter is allowed
  to animate;
- state is carried by color, by the segmented meter, and by a screen-edge alarm;
  the alarm is the single "urgent" channel and stays reserved for critical
  oxygen and for shelter without life support;
- inside a powered shelter the environment cluster dims: the interface calms
  down together with the player and reinforces the inside/outside contrast;
- the weather row groups localized weather state, cloud cover, signed Celsius
  air temperature, and humidity on the same quiet instrument line; temperature
  and humidity do not create a new card or claim the critical alarm channel;
- the action bar is contextual, not a permanent cheat sheet: it is shown at
  session start and while a mode is active, then fades out;
- key caps and captions are localization keys, never literals in widget code.

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
