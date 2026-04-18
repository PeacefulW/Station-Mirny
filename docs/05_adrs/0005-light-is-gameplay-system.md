---
title: ADR-0005 Light Is a Gameplay-Support System
doc_type: adr
status: approved
owner: design+engineering
source_of_truth: true
version: 1.0
last_updated: 2026-03-26
related_docs:
  - ../01_product/GAME_VISION_GDD.md
  - ../01_product/NON_NEGOTIABLE_EXPERIENCE.md
---

# ADR-0005 Light Is a Gameplay-Support System

## Context

The core fantasy is "inside = safe, outside = hostile." Light is the primary carrier of this contrast. If light is only cosmetic, the contrast collapses.

## Decision

Light is a gameplay system, not decoration:
- **Light = safety.** A lit room is safe. A lit perimeter is defended. A torch reveals threats.
- **Darkness = pressure.** Night without light = reduced visibility = increased danger. Underground without power = blind. Storm = darkness even during day.
- **Gameplay must read light state explicitly.** Systems (fauna AI, visibility, player stress) query a light/visibility authority, not the renderer. If the renderer says "bright" but the authority says "dark", gameplay trusts the authority.
- **Light sources have gameplay cost.** Lamps need power. Torches need fuel. Campfires attract fauna via noise/light. No free infinite light.

Categories of light context:
1. Warm interior (powered base) — sanctuary
2. Daytime exterior — manageable exposure
3. Night exterior — dangerous exposure
4. Severe weather — darkness even in day
5. Underground — absolute dark without player light
6. Emergency/power loss — sanctuary collapses to exposure

## Consequences

- Every light source must be a gameplay entity with power/fuel cost, not a free visual effect.
- Visibility state must be an authoritative gameplay value, not scraped from the renderer.
- Fauna and threat systems use visibility state for behavior decisions.
- Underground spaces are dark by default — light is earned, not given.
