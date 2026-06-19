# Tlaloc's Reign — Development Roadmap

Last updated: 2026-06-19  
Current milestone: v0.42 — Repository Baseline & Cleanup

This roadmap defines the development order from the current systems prototype toward Prototype 0 Vertical Slice. It is intended to keep future coding work focused, prevent scope drift, and stop old or removed mechanics from being accidentally reintroduced.

## 1. Current strategic read

Tlaloc's Reign is no longer just a screen mock-up. It is now a systems prototype with:

- a live market and barter trade interface
- estate and market stockpiles
- building and production data
- housing and labour systems
- palace tabs and dedication-route hooks
- prestige ledger and Palace -> Prestige tab
- Flower Wars reports and prestige logic
- shrine/religion hooks
- rival identities and procurement design
- a large active gameplay wrapper over the base game screen

The main risk is not lack of systems. The main risk is that more systems are being added before the project has enough structure, player feedback and source-of-truth documentation.

## 2. Roadmap principles

### Build readability before more complexity

The player must understand what changed, why it changed and what pressure is coming next.

### Keep systems connected

Market, prestige, palace, Flower Wars, religion, rivals, population and estate development should not become separate test panels.

### Avoid reviving removed mechanics

Do not reintroduce:

- abstract Wealth as a normal MVP currency
- generic local stability as an unfocused meter
- old artisan/ritual rival identities
- tactical battlefield combat
- new gods beyond the four-god model

### Extract architecture gradually

Do not attempt a huge rewrite. Split systems out of `TRGameState.gd` and `GameScreenMarketOverviewPatch.gd` only when those systems are being actively touched.

## 3. Version roadmap overview

| Version | Milestone | Main goal |
|---|---|---|
| v0.42 | Repository Baseline & Cleanup | Make the repo's current truth explicit. |
| v0.43 | Structured Veintena Results Summary | Explain end-turn changes clearly. |
| v0.44 | Rival Prototype 1 | Make rivals visible economic competitors. |
| v0.45 | Palace Route Effects Pass | Make palace dedication strategically meaningful. |
| v0.46 | Flower Wars / Warband Progression Connection | Connect warbands, XP, injuries and skill web effects to outcomes. |
| v0.47 | Religion / Shrine Loop Consolidation | Make offerings, favour and shrine upkeep a real loop. |
| v0.48 | One Full Ritual Year Playable | Allow 18 Veintenas + Nemontemi to play coherently. |
| v0.49 | Balance and Readability Pass | Tune economy, prestige, rivals and UI feedback. |
| v0.50 | Prototype 0 Vertical Slice | Deliver a coherent playable prototype year. |

## 4. v0.42 — Repository Baseline & Cleanup

### Goal

Create a clean foundation before adding more gameplay systems.

### Completed

- Remove `Scenes/Main/GameScreen.tscn2577238696.tmp`.
- Add `CURRENT_BASELINE.md`.
- Add `ROADMAP.md`.

### Remaining / optional

- Add `CHANGELOG.md`.
- Confirm that the active scene path and wrapper are correct.
- Confirm whether the formal autoload setup should remain as-is for now or explicitly include `TRGameState`.
- Record any known Godot editor warnings that are still accepted for the current prototype.

### Success criteria

v0.42 is complete when future chats and coding passes can answer:

- What is the active gameplay scene?
- Which script is the active screen wrapper?
- Which state file is the practical runtime source of truth?
- Which mechanics have been removed or rejected?
- What is the next milestone?

## 5. v0.43 — Structured Veintena Results Summary

### Goal

After the player advances a Veintena, show a readable report explaining what changed and why.

### Why this comes next

The game already changes many hidden values:

- production
- stockpiles
- upkeep
- housing state
- market values
- prestige
- palace state
- Flower War results
- religion/favour hooks
- rival placeholders

Without a structured summary, the player cannot understand the simulation.

### Required feature

Create a Veintena Results Summary overlay/panel after pressing Advance Veintena.

It should include sections such as:

- Production
- Upkeep
- Buildings
- Market
- Prestige
- Palace
- Rivals
- Warnings

### Structured event model

Move away from only loose strings like:

```gdscript
last_report.append("Something happened.")
```

Toward structured turn events like:

```gdscript
{
    "type": "prestige",
    "source": "savvy_trade",
    "amount": 3.5,
    "title": "Savvy Trade",
    "detail": "Sold cacao above base value.",
    "severity": "positive"
}
```

### Success criteria

- The player sees a summary after advancing a Veintena.
- Prestige gains/losses are explained.
- Major stockpile changes are explained.
- Blocked buildings or failed upkeep are visible.
- Rival movement can be added later without rebuilding the UI.

## 6. v0.44 — Rival Prototype 1

### Goal

Make the three rival houses visible economic actors.

### Why this comes after v0.43

Rivals will change markets, prestige and pressure. The player needs turn-summary feedback before rivals start acting more strongly.

### Required rival identities

| Rival | Patron god | Design role |
|---|---|---|
| War Rival | Huitzilopochtli | Weapons, obsidian, warrior capacity, captives and martial prestige. |
| Cunning Rival | Tezcatlipoca | Market leverage, tools, cloth, cacao pressure and future sabotage. |
| Diplomatic Rival | Quetzalcoatl | Fine textiles, cacao, tribute goods, palace influence and legitimacy. |

### Required mechanics

- Rival stockpiles.
- Fixed build orders.
- Procurement caps.
- Personality hoards.
- True-surplus selling.
- Minor support steps when blocked.
- Rival prestige changes with readable reasons.
- Rival reports in Veintena Summary.

### Rival build orders

War Rival:

1. Weapon Yard
2. Warrior House
3. Captive Holding Pen
4. Huitzilopochtli Shrine Support

Cunning Rival:

1. Storehouse / Market Storage
2. Advanced Tool Workshop
3. Cloth Workshop
4. Cacao Garden / Cacao Access

Diplomatic Rival:

1. Fine Textile House
2. Noble Residence
3. Cacao Garden / Cacao Expansion
4. Quetzalcoatl Shrine Support

### Success criteria

- The player can infer rival intentions from market behaviour.
- Rivals buy missing goods using caps.
- Rivals sell only true surplus.
- Each rival gains prestige from actions that match its identity.
- The Veintena Summary reports rival movement.

## 7. v0.45 — Palace Route Effects Pass

### Goal

Make Palace dedication feel like a strategic route choice.

### Current route baseline

| God | Palace power |
|---|---|
| Tlaloc | Upgraded calendar / natural event forecast information. |
| Huitzilopochtli | Flower Wars authority / war route. |
| Tezcatlipoca | Scarcity, intrigue and market-pressure authority. |
| Quetzalcoatl | Legitimacy, recognition and palace-performance authority. |

### Implementation order

1. Huitzilopochtli route, because Flower Wars already exist.
2. Tlaloc route, because forecast/calendar information is readable and thematic.
3. Quetzalcoatl route, because Prestige and recognition are now central.
4. Tezcatlipoca route, because sabotage/intrigue needs rivals to be more real first.

### Success criteria

- Palace dedication is clearly visible.
- Palace route effects are shown in Palace UI.
- Route effects appear in turn summaries when relevant.
- Huitzilopochtli meaningfully affects Flower Wars access or authority.
- Tlaloc meaningfully improves future natural-event/calendar information.

## 8. v0.46 — Flower Wars / Warband Progression Connection

### Goal

Make persistent warbands matter mechanically and emotionally.

### Current issue

Warband skill web UI exists, but skill effects are not fully connected to Flower War resolution.

### Required work

- Warband XP gain after Flower Wars.
- Rank thresholds.
- Injury and recovery logic.
- Skill web node effects applied to combat/rewards.
- Veteran value.
- Loss reports that make warrior death/injury feel meaningful.
- Replacement warriors and recovery pressure.

### Success criteria

- A warband that survives and gains experience becomes more valuable.
- Skill web choices affect Flower War outcomes.
- Injuries and losses are shown clearly in reports.
- War is tempting but costly.

## 9. v0.47 — Religion / Shrine Loop Consolidation

### Goal

Make offerings, favour and shrine upkeep into a real recurring loop.

### Required work

- Clear favour display per god.
- Predictable favour decay.
- Shrine upgrades modifying favour decay/output.
- Major ritual choice per relevant Veintena.
- Sacrifice UI polish.
- Ritual prestige/favour reporting.
- Religion entries in Veintena Summary.

### Design guardrails

- Four gods only.
- No separate large ritual minigame.
- Offerings must cost real goods/captives.
- Captives should remain strategically valuable, not ordinary workers.

### Success criteria

- The player understands which god is being honoured.
- The player understands the cost.
- The player understands the likely pressure: rain, war, power or legitimacy.
- Neglect produces readable risk, not mysterious punishment.

## 10. v0.48 — One Full Ritual Year Playable

### Goal

Make 18 Veintenas and Nemontemi playable from start to finish.

### Required work

- Turn loop runs reliably for a full year.
- At least one palace demand cycle.
- At least one Flower War opportunity.
- Rival movement across the year.
- Prestige race updates.
- Nemontemi annual review.
- Carry-forward pressure into next year.

### Success criteria

- Player can play a full first Ritual Year without hitting a dead-end.
- The year has a beginning, middle and reckoning.
- The game can summarize the year meaningfully.
- Rivals feel like competitors, not static score labels.

## 11. v0.49 — Balance and Readability Pass

### Goal

Tune the first-year economy, prestige and pressure after the main loop is visible.

### Required tests

- Can the player pursue a war route in Year 1?
- Can the player pursue a palace/diplomatic route in Year 1?
- Can the player pursue a religion/shrine route in Year 1?
- Is Savvy Trade useful but not dominant?
- Do rivals pressure the market without making it unreadable?
- Do shortages feel meaningful rather than random?
- Are goods values and scarcity multipliers readable?

### Success criteria

- No single obvious route dominates.
- The player understands why they are struggling.
- Market prices respond in ways that feel sensible.
- Prestige rewards match cost and risk.

## 12. v0.50 — Prototype 0 Vertical Slice

### Goal

Deliver a coherent playable prototype year.

### Prototype 0 should prove

- Estate production works.
- Market trade matters.
- Prestige is readable.
- Palace route matters.
- Rivals visibly compete.
- Flower Wars are usable.
- Religion creates real pressure.
- Veintena results explain what happened.
- The game feels like one connected noble-house strategy game, not separate test systems.

### Success criteria

By v0.50, the player should be able to play one full first Ritual Year and understand:

- what they produced
- what they consumed
- what they traded
- what they offered
- what they won or lost in war
- what rivals did
- why prestige changed
- why the palace matters
- what they should prepare for next

## 13. Post-v0.50 direction

Only after v0.50 should the project consider larger expansions such as:

- richer event libraries
- deeper rival plots
- fuller Tezcatlipoca sabotage
- more palace demand variety
- expanded shrine trees
- deeper warband traits
- richer art/audio polish
- save/load hardening
- tutorial/onboarding

The priority before then is not more content. It is making the existing loop coherent, readable and playable.
