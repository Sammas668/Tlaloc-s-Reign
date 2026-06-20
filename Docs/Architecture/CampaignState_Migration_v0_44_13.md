# CampaignState Migration v0.44.13 — Warband / Flower War State Bridge

## Purpose

This patch continues the CampaignState migration by adding a safe bridge for warband roster state and Flower War report state.

It does not make CampaignState fully authoritative for warbands yet. TRGameState still owns most warband mutation paths and remains the public UI API.

## Added to CampaignState

CampaignState now exposes helpers for:

- reading and replacing the warband roster
- reading and setting individual warbands
- reading and setting the last Flower War report
- reading, replacing, appending and clearing the Flower War report archive
- mirroring warband / Flower War report state back to TRGameState compatibility fields

## Added to TRGameState

TRGameState now has bridge helpers for:

- `_ensure_campaign_state_warband_flower_war_bridge()`
- `_mirror_warband_flower_war_compatibility_from_campaign_state()`

The standard CampaignState sync path now also mirrors this domain after sync.

## Routed reads

The following public reads now go through the CampaignState bridge:

- `get_last_flower_war_report()`
- `get_flower_war_report_archive(...)`

Flower War archive writes now append through CampaignState and then mirror back to TRGameState compatibility fields.

## Migration status

CampaignState has now bridged these major data domains:

- project/start data
- stockpiles
- calendar/report state
- prestige state
- palace state
- population/buildings/housing/labour state
- warband / Flower War report state

## Not changed

- No Flower War formula changes.
- No warband XP or injury formula changes.
- No UI call changes.
- TRGameState remains the public API.

## Next recommended step

`v0.44.14 — CampaignState Authority Audit`

Before moving more data ownership, audit which CampaignState domains are now bridged and which TRGameState mutation paths still write directly to compatibility dictionaries.
