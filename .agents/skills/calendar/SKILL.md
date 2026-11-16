---
name: calendar
description: Use when choosing a release date, planning launch and seasonal discounts, picking a Steam Next Fest, themed fest or game jam, scheduling marketing beats, or asking what comparable games sell for and how deep they are discounted.
---

# Marketing calendar

`calendar` lists the dated events a game's marketing plans around and sets them against `plan.json`'s `release` block.
Dates come from the stores' own pages at run time, never from memory: Valve moves and adds events every year.

```powershell
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hyperdot.ps1 calendar -Json                            # every source, the next 365 days
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hyperdot.ps1 calendar -Source steam -Days 120 -Json    # one source, a shorter window
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hyperdot.ps1 calendar -Comparable hades-ii,dead-cells -Json   # LootRadar slugs (lootradar.gg/game/<slug>)
pwsh ${CLAUDE_PLUGIN_ROOT}/ci/godot/hyperdot.ps1 calendar -Offline -Json                   # the cache only, no network
```

It writes `calendar-results/calendar.ics` (every event, the plan's deadlines and discounts as all-day events; stable UIDs,
so importing it again updates instead of duplicating). Pages are cached in `.godot/hyperdot-calendar` for 6 hours. A
source that fails is a warning; only all of them failing is `calendar-unavailable`.

## 1. Sources

| Source | What it gives | How far to trust it |
|---|---|---|
| `steam` | Valve's Upcoming Steam Events: the four seasonal sales, Next Fest editions, themed fests with eligibility and registration links, the Black Friday discount hub | Valve's own page; the source of truth for dates. "TBD" sales have no dates yet |
| `itch` | The most-joined itch.io jams in the window, with dates and how many joined | itch.io's own calendar data; times are read as UTC |
| `epic` | Epic's free games now and upcoming, and windows where the feed shows other games discounted | An undocumented feed; Epic's sale calendar is only in its developer portal |
| `lootradar` | Per comparable game: base price, Steam price now, lowest price seen and the deepest discount it makes, 12 weeks of price range, honesty score, live players | LootRadar's public API; 12 weeks of history, so "deepest" means recent. Attribute "LootRadar (lootradar.gg)" wherever the numbers are shown publicly |

## 2. What goes in plan.json

```json
"release": {
  "date": "2027-04-20",
  "nextFest": "2027-02-22",
  "launchDiscount": { "percent": 10, "days": 7 },
  "discounts": [
    { "name": "Summer Sale", "start": "2027-06-24", "end": "2027-07-08", "percent": 20, "seasonal": true }
  ],
  "comparables": ["hades-ii", "dead-cells"]
}
```

`plan` and `status` check the discounts against the rules below on every run, with no network; `calendar` adds the checks that
need the events: which seasonal sales the game can join, whether `nextFest` is an edition Valve lists, and what falls on release day.

## 3. Steam's discount rules (Steamworks "Discounting", read 2026-11-16)

| Rule | Value |
|---|---|
| After release (Early Access and full release alike) | no discount for 30 days, except the launch discount |
| Launch discount | optional, set up before release; 10 to 40%, 7 to 14 days. Valve suggests about 10 to 15% |
| Any other discount | 10 to 95%, 1 to 14 days; 30 days from the end of one to the start of the next (fests, weeklong deals and daily deals included) |
| Seasonal sales (spring, summer, autumn, winter) | exempt from the 30 days between discounts, both ways; not from the 30 days after release or after a price increase. A game still in that cooldown joins part-way, once it ends |
| Price increase | starts its own 30 days without discounts |
| Black Friday | a themed hub on the Discounts & Events page, not a seasonal sale: the 30 days between discounts apply |

Valve's advice: ease into discounts (33%, 50%, 66%, 75% over a year or more), and discount the base game, editions and DLC
together. A deep discount weeks after launch tells the people who paid full price they were wrong to.

## 4. Choosing dates

- **Release day:** check `calendar.release.seasonalSales`. Released 30 days or more before a seasonal sale, the game joins it from
  the first day (Valve's own example: an Early Access launch on November 15 with a 7-day launch discount, then the Winter Sale
  on December 17). Released inside a sale, the game cannot discount in it and shares the front page with every discount on Steam.
- **Next Fest:** one per game, the last one before launch (`store-page` section 4 has Zukowski's wishlist numbers). With no
  `release.nextFest`, `calendar` names the last edition before release and its demo deadline (3 weeks before; 5 for the press
  preview). Register from the event's `registration` link.
- **Themed fests:** read each fest's `notes` (Valve's eligibility text) against the GDD's genre and features; propose only the ones
  the game plainly fits. Games in Coming Soon and games with demos may take part; discounted games are prioritised, and a fest
  discount starts the 30 days before the next one.
- **Jams** (a jam game, `plan -Do init -Profile jam`, or a prototype): pick from `itch` by dates and size; read the jam's own page for
  its rules, theme and whether a game made before the jam may be entered.
- **Epic giveaways** in launch week: if one is in the same genre, it competes for the same players' evenings; say so, do not move
  a release for it alone.

## 5. Price and discounts from comparables

- Pick 3 to 5 games a player of this game would also buy (`game-design` section 4 has the teardown); their slugs go in
  `release.comparables`. `comparableSummary` gives the median base price and the median deepest discount.
- Use official-store prices only (keyshop prices are left out on purpose). A high `deepestDiscountPercent` within 12 weeks of a
  recent release is a game in trouble or in a sale, not a target.
- Never present LootRadar's verdicts as advice to the user's own players; they are price history for shoppers.

## 6. Turn it into the plan

1. Set `release.date`, `release.nextFest`, `release.launchDiscount` and the planned `release.discounts`; run `plan -Json` and fix
   every discount warning before anything else.
2. Add a task per marketing beat with `plan -Do add` (the beats and their order are in `store-page` sections 6 and 7: the page
   live months ahead, the announcement, the Next Fest demo, review keys about a month before, the launch email).
3. Import `calendar.ics` into the user's calendar app; run `calendar` again when Valve announces new dates (it caches for 6 hours).

What it cannot know: the stores' partner-portal calendars (Epic, GOG, itch.io), public holidays, and events not yet announced.
Valve's days end at 10 am Pacific; plan on the day before when the hour matters. If `steam` warns that the page "held no events",
the page changed: read it at https://partner.steamgames.com/doc/marketing/upcoming_events and report it as a kit problem.
