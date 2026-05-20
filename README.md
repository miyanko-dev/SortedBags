# SortedBags

A lightweight bag sorter for World of Warcraft Classic Era 1.15.x. Built on
the specialty-bag-aware planner from shirsig's SortBags v1.3.9 (arrows go
into quivers, soul shards into soul bags, herbs into herb bags, and so on),
now extended with **Retail-style per-bag category assignment** — right-click
a bag's portrait to designate it as a home for Gear, Consumables, Reagents,
etc.

## Installation

1. Copy the `SortedBags/` folder into:
   `World of Warcraft/_classic_era_/Interface/AddOns/`
2. Restart the game or `/reload`.
3. Enable **SortedBags** in the AddOns list.

## Usage

- Open the bags (`B`). A small sort icon sits to the left of the gear icon
  under the backpack's close button. Click it to sort, or type `/sortbags`
  (alias `/sortedbags`).
- The gear icon (or `/sb`) opens the options window.
- **Right-click any bag's portrait** (the round icon at the top-left of an
  open bag window) to open the category menu.

Settings are stored in `SortedBagsDB`, saved per account.

## Right-click portrait menu

Tick any combination of (listed in the same priority order the dropdown
uses):

- **Hearthstone** — pinned to the bag's first slot so you can grab it
  without looking
- **Mount** — pinned to the bag's next slots, immediately after the
  Hearthstone if both flags are set
- **Reagent** — class spell components (Soul Shards, Symbol of Kings, Wild
  Berries, Holy Candle, Ankhs, etc.)
- **Consumable** — food, drink, potions, scrolls
- **Gear** — weapons and armor. Weapons always sort *before* armor inside
  this bucket.
- **Trade Goods** — cloth, herbs, ore, leather, enchanting dusts/essences,
  **recipes** (classID 9 is rolled into this bucket so a profession bag
  catches them alongside the mats they craft into).
- **Quest**
- **Miscellaneous** — keys, containers, projectiles, and any other
  classID-15 items (pets, holiday tokens, …). Projectiles in a quiver /
  ammo pouch are always claimed by that bag first regardless of this flag.
- **Junk** — gray-quality items. Junk wins over class buckets, so a gray
  sword lands here rather than in Gear.

Reagent and Trade Goods are deliberately separate. Reagent is the in-game
item class for **spell components** that get consumed by abilities (Soul
Shards, Sacred Candles, …). Trade Goods is the **profession-mats** class
(cloth, leather, ore, herbs, enchanting mats, …). Enchanting dusts and
essences live under Trade Goods → Enchanting subclass, not under Reagent.

Below the categories sits an **Ignore Sorting** checkbox: tick it and the
bag is excluded entirely (nothing moves in, nothing moves out). The
portrait dims to gray.

A bag with one or more category flags shows a subtle desaturation on its
portrait so you can see at a glance which bags have an assignment.

**Reset bag categories** clears every flag and the ignore state on that
bag.

## Sort behavior

1. **Specialty bags first** — quivers, soul bags, herb bags, enchanting
   bags, and ammo pouches take their matching items before anything else.
   This isn't configurable; it's a hardware constraint from the bag itself.
2. **Per-bag fill** — each tagged bag claims its matching items. Within a
   single bag, items land in the canonical order:
   Hearthstone → Mount → Reagent → Consumable → Gear (weapons → armor)
   → Trade Goods → Quest → Miscellaneous → Junk. Hearthstone and Mount
   slots are effectively reserved whenever those flags are set on the bag
   and the matching items exist.
3. **Unassigned bags absorb everything else** — items without a matching
   tagged bag fill the remaining unassigned bags in default sort order.
4. **Spillover** — if a category bag has empty slots left after step 2,
   leftover items from any category can spill into it.

Within any single category, items sort by classID (weapons before armor in
Gear; containers → projectiles → keys → other in Misc), then sub-class,
then quality (highest first), then name. **Within every bag, items always
fill top-left → bottom-right.**

## Options window (`/sb`)

- **Sort right-to-left** — controls *which bag fills first*, not the slot
  order inside the bag. On: backpack first, then bag1 → bag4 (rightmost
  → leftmost). Off (default): bag4 first, then bag3 → backpack (leftmost
  → rightmost). Either way, each bag fills top-left → bottom-right.
- **Loot fills right-to-left** — calls
  `C_Container.SetInsertItemsLeftToRight(false)`. Uncheck to fill loot
  left-to-right (`SetInsertItemsLeftToRight(true)`).

The category-priority drag list from earlier versions is gone; assignment
is per bag now.

## What gets sorted

Bags `0..4` (backpack + four bag slots). Items in ignored bags are left
untouched in both directions: nothing moves in, nothing moves out.

## Speed

The engine batches as many moves as can run safely per frame instead of
yielding after every single swap. Per-sweep slot tracking guarantees no
slot is touched twice in one frame, so the model stays in sync with the
server. A typical full sort completes in a few frames.

## Safety

Sorting refuses to start while in combat, on the cursor, or with the
merchant, bank, trade, mail, or auction windows open.

## Files

```
SortedBags/
├── SortedBags.toc
├── Sort.lua    -- engine: flags, classifier, four-phase planner, move pipeline
├── UI.lua      -- sort button, gear button, /sb panel, portrait dropdown
└── README.md
```

## Credit

The specialty-bag planner is ported from
[shirsig's SortBags](https://github.com/shirsig/SortBags) under its
original license. SortedBags replaces the original hand-tuned sort buckets
with per-bag category flags modelled on Retail's `Enum.BagSlotFlags`,
batches moves per frame, and adds the right-click portrait menu.
