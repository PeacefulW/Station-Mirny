---
title: Automation and Logistics
doc_type: system_spec
status: approved
owner: design+engineering
source_of_truth: true
version: 1.0
last_updated: 2026-03-25
related_docs:
  - engineering_networks.md
  - building_and_rooms.md
  - ../survival/survival_core.md
---

# Automation and Logistics

## Purpose

Automation exists to remove repetitive extraction and processing chores while preserving the identity of the engineer as the final assembler.

## Core rule

Automate the pipeline up to intermediate products.
Final assembly remains personal.

## Scope

This spec owns:
- what may be automated
- what intentionally remains manual
- logistic movement between base and outposts
- scheduling and priority intent

## Automation philosophy

The game should not become a pure factory sim.

The player should automate:
- extraction
- filtration
- pumping
- smelting
- delivery
- climate support

The player should still perform:
- final craft assembly
- critical repairs
- important build decisions
- research/decryption initiation

## Automatable processes

Examples of intended automation:
- ore extraction through powered drills
- water pumping from sources
- air compression and filtration
- water purification
- ore to ingot smelting
- inter-base shipping
- climate regulation

## Intentionally manual processes

Examples:
- ammunition and precision item assembly
- complex modules and weapons
- final station-to-station assembly
- emergency repairs

## Logistics

Long-term logistics are based on route-based transport between the main base and outposts.

Desired knobs:
- routes
- priorities
- thresholds / schedule rules
- vulnerability of the route

## Noise coupling

Automation is not purely positive.

More machinery means:
- more throughput
- more power demand
- more sound/vibration
- more threat pressure

This must remain one of the main balancing levers of the whole game.

## Acceptance criteria

- automation removes repetitive clicks, not meaningful authorship
- logistics makes outposts useful
- more industry creates more strategic vulnerability
- manual final assembly still feels intentional rather than annoying

## Failure signs

- the optimal play is full unattended factory play
- or the opposite: nothing important can be automated
- logistics adds UI complexity without strategic value
