# LibramSwap Aljeron

Automatically swaps relic-slot items (Librams, Idols, Totems) before casting spells for Paladin, Druid, and Shaman. Just put them in your bag and cast!

Supports casts via action bar, macros, spellbook, and addons.

## Setup

1. Select your class ruleset: `/ls class paladin`, `/ls class druid`, or `/ls class shaman`
2. Put your relics in your bags
3. Cast spells normally - swaps happen automatically

## Commands

All commands support: `/libramswap`, `/lswap`, or `/ls`

### Basic Commands

- `/ls` - Toggle on/off
- `/ls on` / `/ls off` - Enable/Disable
- `/ls spam` - Toggle swap messages
- `/ls status` - Show current settings
- `/ls class <paladin|druid|shaman>` - Select class ruleset

## Paladin

### Configurable Spells

- `/ls consecration [faithful / farraki]`
- `/ls holystrike [eternal / radiance]`

### Supported Spells & Librams

| Spell | Libram |
| --- | --- |
| Consecration | Libram of the Faithful / Farraki Zealot |
| Holy Shield | Libram of the Dreamguard |
| Holy Light | Libram of Radiance |
| Flash of Light | Libram of Light (fallback: Divinity) |
| Cleanse | Libram of Grace |
| Hammer of Justice | Libram of the Justicar |
| Hand of Freedom | Libram of the Resolute |
| Crusader Strike | Libram of the Eternal Tower |
| Holy Strike | Libram of the Eternal Tower / Radiance |
| Judgement | Libram of Final Judgement (only at <=35% target HP) |
| Seals | Libram of Hope / Fervor |
| Devotion Aura | Libram of Truth (auto-equips after 1.5s idle) |
| All Blessings | Libram of Veracity |

## Druid

### Configurable Spells

- `/ls rip [emerald / laceration / savagery]`
- `/ls bite [emerald / laceration]`
- `/ls rake [ferocity / savagery]`
- `/ls healingtouch [health / longevity]`
- `/ls moonfire [moonfang / moon]`

### Supported Spells & Idols

| Spell | Idol |
| --- | --- |
| Rip | Idol of the Emerald Rot / Laceration / Savagery |
| Ferocious Bite | Idol of the Emerald Rot / Laceration |
| Rake | Idol of Ferocity / Savagery |
| Healing Touch | Idol of Health / Longevity |
| Moonfire | Idol of the Moonfang / Moon |
| Starfire | Idol of Ebb and Flow |
| Regrowth | Idol of the Forgotten Wilds |
| Savage Bite / Shred | Idol of the Moonfang |
| Claw | Idol of Ferocity |
| Form Shifting | Idol of the Wildshifter |
| Aquatic Form | Idol of Fluidity |
| Maul / Swipe | Idol of Brutality |
| Thorns | Idol of Evergrowth |
| Insect Swarm | Idol of Propagation |
| Rejuvenation | Idol of Rejuvenation |
| Demoralizing Roar | Idol of the Apex Predator |
| Entangling Roots | Idol of the Thorned Grove |

## Shaman

### Configurable Spells

- `/ls earthshock [broken / stone / rage / rotten]`
- `/ls frostshock [stone / rage]`
- `/ls flameshock [stone / rage / flicker]`
- `/ls lightningbolt [crackling / static / storm]`
- `/ls lesserheal [life / sustaining / corrupted]`
- `/ls watershield [tides / calming]`
- `/ls lightningstrike [crackling / tides / calming]`

### Supported Spells & Totems

| Spell | Totem |
| --- | --- |
| Earth Shock | Totem of Broken Earth / Stone Breaker / Rage / Rotten Roots |
| Frost Shock | Totem of the Stone Breaker / Rage |
| Flame Shock | Totem of the Stone Breaker / Rage / Endless Flicker |
| Lightning Bolt | Totem of Crackling Thunder / Static Charge / Storm |
| Lesser Healing Wave | Totem of Life / Sustaining / Corrupted Current |
| Water Shield | Totem of Tides / Calming River |
| Lightning Strike | Totem of Crackling Thunder / Tides / Calming River |
| Chain Lightning | Totem of the Storm |
| Strength of Earth / Grace of Air | Totem of Earthstorm |
| Molten Blast | Totem of Eruption |
| Hex | Totem of Bad Mojo |

### Special: Reincarnation

When HP <= 5% and Reincarnation is ready, automatically equips **Totem of Rebirth**.

## Notes

- `/ls` may conflict with LazyScript - use `/lswap` instead if needed
- Swaps are blocked during vendor/bank/trade interactions
- Judgement swap only triggers at <=35% target HP
