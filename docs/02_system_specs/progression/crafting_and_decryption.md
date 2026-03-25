---
title: Crafting and Decryption
doc_type: system_spec
status: approved
owner: design+engineering
source_of_truth: true
version: 1.0
last_updated: 2026-03-25
related_docs:
  - resource_progression.md
  - character_progression.md
  - ../base/automation_and_logistics.md
---

# Crafting and Decryption

## Purpose

The game's tech progression should feel like reconstructing lost civilization through material chains and damaged archives, not instantly unlocking abstract tiers.

## Core statement

Crafting is material realism.
Technology is decryption, not invention from nothing.

## Scope

This spec owns:
- multi-step craft pipeline
- workstation ladder
- decryption tree framing
- branch divergence into Terraformer vs Adaptation

## Crafting chain

The core production pattern is:

`raw resource -> refined material -> component -> final assembly`

This is the expected backbone for tools, weapons, modules and infrastructure.

## Workstations

The intended workstation ladder includes:
- primitive workbench
- forge
- electric furnace
- mechanical bench
- assembly bench
- electronics station
- chemistry station
- branch-specific late stations

## Decryption system

### Lore rule

The engineer is recovering damaged knowledge from Ark archives rather than researching from zero.

### Gameplay rule

Technologies consume:
- time / compute
- energy
- infrastructure

Server capacity accelerates decryption but increases energy demand.

## Tree structure

The broad structure runs from:
- basic survival
- electronics / materials / chemistry
- equipment / transport / medicine
- then diverges toward Terraformer and Adaptation

## Acceptance criteria

- crafting chains feel grounded and satisfying
- decryption feels like infrastructure-dependent progress
- branch split matters in both capabilities and fantasy

## Failure signs

- recipes become flat and forgettable
- decryption is just another passive timer
- branch split is cosmetic rather than structural
