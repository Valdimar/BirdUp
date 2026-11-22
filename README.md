# BirdUp

A Windower 4 addon for Final Fantasy XI that automates chocobo digging and tracks everything about it: fatigue, free digs, inventory space, and every item you find. It combines the auto-dig behavior of [Velner/chocodig](https://github.com/Velner/chocodig) with dig tracking, all shown on one draggable HUD.

**Author:** Valdimar @ Phoenix  **Version:** 5.2  **Commands:** `//birdup` or `//bup`

---

## Features

- **City prices:** vendor prices are kept per city (fame changes what vendors pay), and you're told when you sell somewhere that pays less.
- **Auto-dig:** digs as fast as the game allows. It faces the next heading, sends `/dig` while standing still, and starts running the moment the game has the dig. The dig animation stops the chocobo about a second later, usually 2 to 5 yalms on, and the next dig goes from right there as soon as the result is in. No extra move, no extra stop. It waits until the chocobo has fully stopped before each dig, so a dig is never wasted while it's still sliding. It turns when stuck. Digs are 5 yalms apart (`distance`), and never closer than 2 (`mindist`). If it runs into a wall before it's gone far enough, it digs right there and then turns away, as long as that's at least 2 yalms from the last dig. Otherwise it just turns away. After each dig finishes it either carries on the same way or turns to a random new heading (50/50 by default), while staying within an area around where you started. On ground that can't be dug, it turns roughly around, moves a few yalms and tries again.
- **Wing Skill:** reads your Wing Skill from chat and sets the dig cooldown to match (never digs faster than the game allows).
- **Start / Stop buttons:** click them right on the panel.
- **Daily history:** one log per Japan day, with every session that day added together.
- **Zone delay:** waits out your Wing rank's area delay after zoning before the first dig (5 seconds during a Hyper Campaign).
- **Early warnings:** the panel header flashes when you're low on greens or bag space, before auto-dig has to stop.
- **Digging rewards by zone:** a REWARDS window lists everything each zone can give, grouped by rarity (from BG-Wiki), and marks what you've already dug there.
- **Zone stats + sharing:** finds and drop rates per zone and Wing rank, in an optional window beside the panel, exportable as a report and CSV you can share, and importable from other players.
- **Self-tuning waits:** measures how fast dig results really arrive and sets the "no result" wait to match.
- **Compact mode and lock:** show only the key rows, collapse the item list, and lock the panel in place.
- **Records of Eminence:** shows your chocobo digging objective's progress and the sparks earned from completing it.
- **Debug log:** `//bup debug on` records dig chat lines to a dated file, to help pin down the game's exact wording.
- **Fatigue tracker:** a bar and counter for today's fatigue-counting digs against your cap, per character, reset at midnight JST.
- **Discernment counter:** counts the times your chocobo refuses the greens (session, today and lifetime).
- **Hyper Campaign check:** tests for a Hyper Chocobo Digging Campaign each time auto-dig starts and digs faster if one is running.
- **Free dig detection:** spots "found this item with ease" digs and keeps them out of your fatigue count.
- **Inventory tracking:** used and max slots with a free count, plus auto-stop when space runs low.
- **Currency totals:** lifetime and session totals for the conquest points (and Imperial Standing, allied notes and bayld) that dig rewards pay out.
- **Price learning:** when you sell a dug-up item to an NPC vendor, BirdUp records the gil gained and uses that price for the item from then on, giving an estimated value for your finds.
- **Item list:** every item type you've found, with counts, for this session or for your lifetime.
- **Session stats:** attempts, hits, misses, hit rate, finds per hour and session time.
- **Per-character profiles:** settings, HUD position and lifetime stats are saved separately for each character.
- **Safety stops:** stops on zoning, logout, no greens, low inventory space, fatigue cap, find target, or when you dismount.

---

## Install

1. Extract the zip into your Windower folder so you have:
   ```
   Windower/addons/birdup/birdup.lua
   Windower/addons/birdup/birdup_zones.lua
   Windower/addons/birdup/birdup_roe.lua
   Windower/addons/birdup/birdup_rewards.lua
   Windower/addons/birdup/update_check.lua
   ```
   All five files are needed (BirdUp is split into several files).
2. In game, load it:
   ```
   //lua load birdup
   ```
3. Optional, to load automatically: add this line to your Windower `init.txt` (or a per-character script):
   ```
   lua load birdup
   ```

## Update check

A few seconds after you log in, BirdUp checks GitHub once and always reports the result in chat:

```
[BirdUp] Up to date (version 4.0).
[BirdUp] UPDATE AVAILABLE: version X.Y is out (you have 4.0). Get it from github.com/Valdimar/BirdUp
[BirdUp] Version 4.0 is newer than GitHub (3.9), so it hasn't been released yet.
[BirdUp] Couldn't check for updates (GitHub didn't answer). Try again with a reload.
```

- **Up to date:** you have the latest version.
- **UPDATE AVAILABLE:** a newer version is on GitHub. This line is shown in a different color so it stands out.
- **Newer than GitHub:** your copy is ahead of the released version (for example, a test build).
- **Couldn't check:** GitHub couldn't be reached, or HTTPS isn't available in your Windower. Reload BirdUp (`//bup reload`) to try again.
The game can pause for a moment while it checks (at most 3 seconds, usually much less).

## Quick start

1. Mount your chocobo and carry Gysahl Greens.
2. Set your daily cap if it isn't 100 (see [Fatigue](#fatigue-and-free-digs)): `//bup set cap 200`
3. Click **START** on the panel (or type `//bup start`).
4. Click **STOP** (or `//bup stop`) any time. `//bup pause` pauses; the START button then reads **RESUME**.

The HUD appears automatically when you get on a chocobo (rental or your own; other mounts from the Mounts menu don't count, since they can't dig) and hides when you get off (turn this off with `//bup set autohide off`). Tracking runs in the background either way, so manual `/dig` use is still counted.

---

## The HUD

| Area | What it shows |
|------|---------------|
| Title and top bar | Today's fatigue digs against your cap. The bar is green, turns amber at 70% and red at 90%. |
| ZONES | Header button that shows or hides the zone stats window. It's lit while the window is open. |
| REWARDS | Header button that shows or hides the digging rewards window (see below). |
| START / STOP | Buttons that start and stop auto-digging. The one that does something right now is bright. |
| Warning | Appears at the top when greens or free bag slots are low (`warngreens` / `warnslots`, default 10 greens / 5 slots). The header strip flashes amber while it's showing, and chat gets one line when it first appears. |
| State | IDLE, DIGGING, MOVING or PAUSED. While auto-digging, also how far you are from the center of the digging area. |
| Wing | Your Wing Skill, its rank, and the cooldown between digs at that rank. Shows `?` until it's seen in chat or set with `//bup wing <level>`. |
| Fatigue | Fatigue digs used, the cap, how many are left, and roughly how long they'll take at today's pace (for example `81 left  ~16m`). |
| Free digs | Free digs today and what percentage of successful digs were free. |
| Discern | Discernment procs (*"Your chocobo refuses to partake of the bunch of gysahl greens."*) this session, with today's and lifetime totals. |
| Hyper | Shows `testing...` while the campaign check runs and `ACTIVE` if a campaign was found. Hidden otherwise. |
| Attempts | Digs this session that got a result (an item, a reward or "find nothing"), with hits and misses. A `/dig` the game rejects, for example on cooldown, isn't counted. |
| Hit rate | Successful digs as a percentage of attempts. |
| Greens | Gysahl Greens in your inventory (red under 10). |
| Inventory | Used / max slots and free count. Amber at 8 or fewer free, red at your auto-stop threshold. |
| Next dig | Seconds until the next dig, and distance moved against the required distance. Shows `zone wait Ns` while the area delay after zoning runs. |
| Session | Session time and finds per hour. |
| Today | Finds and digs since midnight JST, and how many sessions that covers. Only digs that got a result count. |
| RoE | Your Records of Eminence chocobo digging objective, for example `Chocobo Digs 21/30`, plus completions and sparks earned this session. Appears after your first successful dig. |
| Lifetime | Total finds for this character. |
| Sold | Gil you've earned selling dug-up items to vendors (lifetime, plus today). |
| Bought | Gil you've spent buying Gysahl Greens from shops, how many you've bought (lifetime), and gil spent today. |
| Est. val | Estimated gil value of your finds at the prices BirdUp has learned (lifetime, plus today). |
| Conquest | Lifetime conquest points earned from digging, with this session's gain. Imperial, Allied and Bayld rows appear once you've earned any. |
| Items found | Click the **ITEMS FOUND** header to collapse or expand the list (`[+]` / `[-]`). Every item type found today (since midnight JST) or in your lifetime, most common first, with counts and `@price` each where known. Prices up to 9,999 are shown in full (`@1,234`); higher ones are rounded to the nearest half thousand or half million (`@30.5k` for 30,251, `@250k`, `@1.5m`). `//bup prices` always shows the full number. Today's list survives reloads and logouts and only clears at the JST day change. The panel grows to fit. |

The panel widens automatically to fit its longest line. Drag the panel (anywhere except the buttons) to move it. The text moves with the box, and the position is saved per character when you let go.

Item names are shown plainly (for example `Insect Wing`, not `Insect wing.1`). Names saved by older versions are cleaned up and merged automatically. Use `//bup set spacing <pixels>` to change the gap between lines (default 18).

---

## Commands

Use `//bup` (or `//birdup`) followed by a command. `//bup help` shows a short overview; `//bup help dig`, `help info`, `help share`, `help panel` and `help set` show the details in game.

### Digging

| Command | Does |
|---------|------|
| `start` / `stop` / `pause` | Start, stop or pause auto-digging (same as the panel buttons). While paused, START reads RESUME. |
| `anchor` | Center the digging area on where you're standing. |
| `fatigue [n \| reset]` | Show, set or reset today's fatigue count. |
| `wing [level]` | Show or set your Wing Skill. Skill-ups in chat keep it updated. |
| `hyper` | Show the Hyper Campaign status. |
| `hyper Oct16-Nov9` | Save campaign dates (also `Oct 16th - Nov 9th`, `10/16-11/9`). `hyper dates` shows them, `hyper dates clear` removes them. |
| `hyper on \| off \| auto` | Force the campaign on or off until you reload, or go back to testing on each start. |
| `tune` | Show measured dig-result times and the current no-result wait. |

### Information

| Command | Does |
|---------|------|
| `status` | One-line summary of this session. |
| `finds` | Every item in the panel's list, in chat. |
| `history [days \| date \| today]` | Daily log: `history` (7 days), `history 14`, `history 20261110`, `history today`. |
| `zone` / `zone all` | Drop rates here (or in every zone) at your Wing rank. |
| `prices` | Vendor prices, with each city's price. |
| `price <item> <gil>` | Set a price by hand (0 clears it). |
| `prices clean` | Remove prices for items no character has dug. |
| `currency` | Conquest points, Imperial Standing, allied notes and bayld from digging. |

### Sharing and troubleshooting

| Command | Does |
|---------|------|
| `export` | Write your zone drop stats to a shareable `.csv` + `.txt` in `data/export/`. |
| `import [file]` | Import other players' exports from `data/import/` (all of them, or one file). |
| `import list` / `import clear` | List or remove imported players. |
| `debug on \| off` | Record dig chat to a dated file in `data/debug/`. It ends with a list of lines BirdUp didn't recognize. |

### The panel

Each of these takes `on` or `off`; without one, it switches between the two.

| Command | Does |
|---------|------|
| `hud` | Show or hide the panel. |
| `compact` | Show only the key rows. |
| `items` | Collapse the item list (same as clicking ITEMS FOUND). |
| `lock` | Stop the panel being dragged. |
| `zones` | The zone stats window (same as the ZONES button). Also `zone window on\|off`. |
| `rewards` | The digging rewards window (same as the REWARDS button). |
| `rewards <zone>` | Show another zone's rewards, by full or partial name (`rewards gusta`, `rewards grauberg (S)`). |
| `rewards here` | Back to the zone you're in. |
| `rewards list` | Every zone with digging data. |
| `view today \| lifetime` | Which totals the item list shows. |

### Settings: `//bup set`

`//bup set` lists every setting with its current value. `//bup set <name>` shows one, and `//bup set <name> <value>` changes it. On/off settings switch if you leave out the value. Settings are saved per character.

| Name | Default | What it does |
|------|---------|--------------|
| **Auto-dig** | | |
| `distance` | 5 | Yalms to travel between digs. |
| `mindist` | 2 | Never dig closer than this to the last dig, even after hitting a wall or a refused dig. |
| `area` | 20 | Stay within this many yalms of where auto-dig started (0 = no limit). |
| `turnchance` | 50 | % chance to turn after a dig instead of carrying on. |
| `turn` | 3 | Yalms to move after undiggable ground. |
| `rundig` | on | Run during each dig (fast). Off = wait for each result, then move and stop before the next dig. |
| `settle` | 0.3 | With `rundig` off: seconds after a dig result before turning and moving. |
| `timer` | 0 | Extra seconds on top of the dig cooldown. |
| `humanize` | 0 | Up to this many random extra seconds per dig (0 = dig right on the cooldown). `jitter` still works as another name for it. |
| `tune` | on | Self-tuning no-result wait. |
| **Stopping** | | |
| `max` | 100 | Stop after this many finds **today** (0 = never). Resets at midnight in Japan and carries over reloads; START won't begin once it's reached. |
| `cap` | 100 | Your daily fatigue cap (100 rental; up to ~200 raised). |
| `stopfatigue` | on | Stop when the fatigue cap is reached. |
| `slots` | 2 | Stop at this many free bag slots (0 = off). |
| `badlimit` | 7 | Stop and alert after this many failed digs in a row (0 = never). |
| `stopecho` | (a chocobo pun) | Extra line echoed with that alert. `off` = none. |
| `mount` | on | Stop when you're not on a chocobo. |
| **Panel** | | |
| `autohide` | on | Only show the panel while on a chocobo. |
| `warngreens` | 10 | Flash the panel at this many greens (0 = off). |
| `warnslots` | 5 | Flash the panel at this many free slots (0 = off). |
| `spacing` | 18 | Pixels between panel lines. |

**Older commands still work:** the one-word forms from before 3.6 (`//bup distance 6`, `//bup cap 150`, `//bup warn 8 3`, `//bup zones`, `//bup profile`…) do the same as the new ones, so existing macros keep working.

### Housekeeping

| Command | Does |
|---------|------|
| `reload` | Save everything and reload BirdUp. |
| `reset` | Reset this session's stats (today's items and fatigue are kept). |
| `saveall` | Copy this character's settings to all characters. |

## Fatigue and free digs

Chocobo digging has a daily fatigue limit based on **successful digs**, not attempts. Once you reach it, further digs find nothing until midnight JST.

- A rental chocobo's cap is **100**. A raised chocobo's cap can be 100 to 200, and Blue Race Silks can raise your effective total because some digs are free.
- A **free dig** doesn't add fatigue. The game prints *"It appears your chocobo found this item with ease."* on the line after the item line.

How BirdUp counts:

1. Every successful dig (an item, a bayld reward or a beastman cache) adds 1 fatigue.
2. If the "with ease" line follows within a few seconds, that fatigue is taken back and a free dig is recorded instead.
3. A dig that gives several items lists all of them but counts as one dig. This is an assumption; see [Known limitations](#known-limitations).
4. The counter resets at midnight JST (UTC+9).

BirdUp can only count digs it sees. If you dug earlier in the day without it loaded, set the count manually with `//bup fatigue <n>`, and set your cap with `//bup set cap <n>`.

---

## Wing Skill and dig cooldown

Since the March 2026 update, chocobo digging skill is called **Wing Skill**, and the wait between digs depends on it (from BG-Wiki):

| Rank | Wing Skill | Between digs | After zoning |
|------|-----------|--------------|--------------|
| Amateur | 0-9 | 15s | 60s |
| Recruit | 10-19 | 10s | 55s |
| Initiate | 20-29 | 5s | 50s |
| Novice to Expert | 30-100 | 3s | 45s down to 10s |

- BirdUp reads your Wing Skill from skill-up lines in chat and remembers it per character.
- The game won't take a new dig until the last one's animation has finished, which is when its result shows up (3 to 5.5 seconds after the dig). A `/dig` sent before that is silently ignored. So that, not the 3-second cooldown, sets the pace: one dig every 3.5 to 5.5 seconds.
- The game handles a dig the moment its packet arrives, while the chocobo is still standing on the spot. BirdUp starts running right after that packet goes out. About a second later the animation stops the chocobo, and the next dig goes from there once the result is in. If the chocobo got less than `mindist` (2 yalms) before it was stopped, BirdUp moves the rest of the way after the result.
- Want it to look less robotic? `//bup set humanize 0.5` adds up to half a second of random delay to each dig.
- Skill-ups are read from the game's line *"Your wing skill improved to 15!"* (confirmed in game). Other lines with "wing skill" and a level are matched too. If the number is ever wrong, set it with `//bup wing <level>`.
- A skill-up that only says it rose by a point can't be used until BirdUp knows your starting level.

### Discernment

When your chocobo's Discernment procs, the game prints three lines:

```
Your chocobo refuses to partake of the bunch of gysahl greens.
Obtained: <item>
It appears your chocobo found this item with ease.
```

BirdUp counts the proc in the Discern row (session, today and lifetime), records the item as a normal find, and counts it as a free dig, so it adds no fatigue.

### Self-tuning wait

How long a dig result takes to show up depends on your connection. With `tune` on (the default), BirdUp times every result and sets the "no result" wait to the slowest typical time (90th percentile) plus 1.5 seconds, between 3 and 12 seconds. It needs 5 digs before it starts, and uses the `result_timeout` setting (5s) until then.

If results suddenly slow down, BirdUp may give up on a dig before its result arrives. Results always come back in the order the digs were sent, so when the late one arrives it's matched to the dig BirdUp gave up on and recorded properly. You'll see *"That dig worked after all (the result took 6.5s)"*, and BirdUp waits longer from then on. `//bup tune` shows the measured times and the current wait.

Dig results arrive when the dig animation ends (about 4 seconds in), so the result itself tells BirdUp the dig is finished. It then waits only a short buffer (`settle`, 0.3s) before moving on.

### Area delay after zoning

Each Wing rank also has a wait after you zone before you can dig (60 seconds at Amateur, down to 10 at Expert, 5 during a Hyper Campaign). Auto-dig waits it out before the first dig in a new zone, showing `zone wait Ns` on the Next dig row, so those early digs don't fail and count toward the 7-in-a-row stop. If you know a Hyper Campaign is running, `//bup hyper on` before you start cuts the wait to 5 seconds and skips the campaign test.

### Hyper Chocobo Digging Campaign

While a Hyper Chocobo Digging Campaign is running, every rank digs every 3 seconds. Each time auto-dig starts and your normal cooldown is longer than that (Wing Skill under 30, or unknown):

1. The first dig goes in as normal.
2. The second dig goes in at campaign speed (about 4 seconds later). The Hyper row shows `testing...`.
3. If the game answers it, a campaign is running: BirdUp says so and digs at campaign speed for the rest of the run.
4. If there's no answer, or the game says *"You must wait longer"*, there's no campaign: BirdUp says so, waits out your normal cooldown and digs again on the same spot. This test dig isn't treated as bad ground.
5. If the test dig lands on *"You cannot dig here."*, that only means bad ground, not "no campaign". BirdUp moves on and runs the test again on the next spot.

At Wing Skill 30 and above your cooldown is already 3 seconds, so there's nothing to test.

**Campaign dates.** If you know when a campaign runs, save it once:

```
//bup hyper Oct16-Nov9
```

The dates are saved in your settings, so they last through reloads, logouts and day changes. They're checked against the Japan date and include both ends. While today falls inside them, auto-dig uses campaign timing straight away (3-second digs and a 5-second area delay after zoning) without the test dig, and the Hyper row shows `ACTIVE (3s cooldown, until Nov 9)`. When the campaign ends, BirdUp goes back to testing on its own. BirdUp works out the year for you: a range that includes today, otherwise the next one coming up (so `Dec20-Jan10` crosses into the new year).

**How long each setting lasts:** saved dates last until you clear them. `hyper on` / `hyper off` last until you reload BirdUp (or use `hyper auto`), whatever the date. Without either, BirdUp tests on every start. If you don't know your Wing Skill, auto-dig assumes the slowest cooldown (15 seconds) until you set it with `//bup wing <level>`.

---

## Digging rewards by zone

Click **REWARDS** on the panel header (or `//bup rewards`) to open a window listing everything the zone can give when digging, grouped by rarity:

| Rarity | Shown as |
|--------|----------|
| VC | Very common |
| C | Common |
| U | Uncommon |
| R | Rare (blue) |
| VR | Very rare (purple) |
| SR | Super rare (gold) |

- Items you've already dug in that zone (at any Wing rank) are marked with `*`, with a count at the bottom: `* = you've dug it here: 9 of 16`.
- Conditions are shown next to the item, for example `Ice Cluster (double weather)`.
- It follows you: it shows the zone you're in and switches when you zone.
- Use **<** and **>** in the window's header to browse every zone, or `//bup rewards <zone>` to jump to one (partial names work). The `<` button lights up while you're browsing another zone; `//bup rewards here` or zoning goes back.
- Behemoth's Dominion shows its separate Burrow and Bore tables underneath the main list.
- The window sits to the right of the panel, or to the right of the zone stats window when that's open.

The data covers 59 zones and comes from BG-Wiki's [Chocobo Digging](https://www.bg-wiki.com/ffxi/Category:Chocobo_Digging) page ("Digging Rewards by Zone", November 2026). Elemental ores, colored rocks and clusters depend on weather (and moon phase for elemental ores), which the wiki notes but doesn't list zone by zone. To update a zone, edit its line near the top of `birdup_rewards.lua`.

## Zone stats and sharing

BirdUp keeps finds, misses, Discernment procs and every item found for each zone, split by Wing rank, because drop tables differ by rank.

### Zone stats window

Hidden by default. Click **ZONES** on the panel header (or `//bup zones`) to open a second window docked to the right of the main panel. It moves with the panel when you drag it, and remembers whether it was open. It shows:

- the zone you're in and your Wing rank
- digs, finds and hit rate there at that rank, misses and Discernment procs
- up to 15 items, most common first, with counts and rate per dig (`//bup zone` lists them all)

It updates as you dig, and switches when you zone or change rank.

### Importing other players' data

Every install gets a random id (in `data/id.txt`), which goes into its exports. No character names are included. To add someone else's data:

1. Put their `birdup_drops_....csv` file(s) in `addons/birdup/data/import/`.
2. `//bup import`.

Each player is kept separately in `data/community/<id>.txt`. Importing a newer export from the same player **replaces** their old one, so nothing is counted twice. Your own export is recognized and skipped. Exports from before 2.8 have no id, so each of those files counts as its own player.

Once something is imported, the zone window shows an **All players** line (total digs and hit rate, yours included) and a second rate column per item, and it also lists items only other players have found there. `//bup zone` shows the same. Your `export` still only contains your own digs, so passing data around never doubles it.

### Files Each character has its own file, `data/zones_<name>.txt`, so two characters digging at the same time don't overwrite each other.

- `//bup zone` shows this zone at your current rank, with each item's rate per dig.
- `//bup export` combines **all** your characters' zone files and writes two files to `addons/birdup/data/export/`, named with the date and time:
  - `birdup_drops_<date>_<time>.txt`, a readable report: each zone and rank, its dig count and hit rate, then every item with its count, rate and known vendor price.
  - `birdup_drops_<date>_<time>.csv`, the same data for a spreadsheet: `zone, wing_rank, zone_digs, zone_finds, zone_miss, zone_discern, item, count, percent_of_digs, vendor_price`.

Character names aren't included, so the files are safe to post or send to other players. The more you dig, the better the rates get. Export again any time for an updated copy.

---

## Debug log

`//bup debug on` starts a new log at `addons/birdup/data/debug/debug_<date>_<time>.txt`; `//bup debug off` closes it (so does reloading). It records:

- every chat line while auto-digging, or within 20 seconds of any dig, with its chat mode and any hidden control codes shown as `<XX>`
- each `/dig` you send and each dig action the game sees
- each move auto-dig starts (`MOVE start roam`, `away`, `reverse`, `side`…) and each wall hit
- BirdUp's own decisions: results recorded, can't-dig-here, Hyper detection, walls, stops, zoning

Each run gets its own file, so you can keep several and send them over when something needs fixing.

When the log closes (`debug off`, or reloading), it ends with a list of **game lines seen near digs that BirdUp has no rule for**, with how many times each appeared (numbers shown as `#`). Player chat isn't included. That's the quickest way to spot a message that needs handling, so send that part over if anything looks unfamiliar.

---

## Daily history

Fatigue resets at midnight JST, so BirdUp keeps one log per Japan day. If you dig several times in a day, every session goes into that day's single log.

Each day records: digs, finds, misses, Discernment procs, fatigue and free digs, number of sessions, time spent digging, gil from vendor sales, currency rewards, your Wing Skill, and every item found. Use `//bup history` for a summary and `//bup history 20261101` for one day's items. The log is saved in `data/history_<name>.txt`.

---

## Selling and item prices

BirdUp learns what your dug-up items are worth from your own sales.

1. Sell an item you've dug up to an NPC vendor.
2. BirdUp sees which item and how many you confirmed selling, then the gil that arrives.
3. It works out the price per item (gil gained divided by the quantity sold). The first time, you'll see `Price history: Pebble added at 3 gil each (sold 12 for 36 gil).` If a later sale gets a different price you'll see `Price history: Pebble updated 3 -> 4 gil each (...)`. A sale at the price already recorded is silent; the gil still counts toward **Sold**.
4. From then on, every find of that item counts toward the **Est. val** row, and the item list shows its price.

Details:

- **Only dug-up items, only vendors:** an item must have been dug up by any of your characters (so an alt can sell your main's finds and still update the price). Anything else you sell is ignored, so it never gets added to the price file. Bazaar and auction house sales are ignored too.
- **Per city:** fame changes what vendors pay, so each sale is recorded against the city you sold in. Each nation's zones count as one city (San d'Oria, Bastok, Windurst, Jeuno, Aht Urhgan, Adoulin); anywhere else (Norg, Selbina, Rabao…) uses its own name. The price shown on the panel and used for Est. val is the **best** city price you know.
- **Cheaper-city warning:** if you sell an item for less than another city has paid you, you get one line, once per item and city per session: *"Heads up: Pebble sells for 7 gil each in Jeuno, but 5 here in Bastok (2 less each)."*
- **Clean-up:** older versions could save prices for items you never dug. `//bup prices clean` removes them.
- **Last sale wins:** each sale replaces the saved price, so the price follows what you most recently got.
- **Auction house prices:** set those by hand with `//bup price <item> <gil>`.
- **Greens you buy:** when you buy from a shop (a chocobo stable or any vendor) and your Gysahl Greens go up while your gil goes down, BirdUp counts the gil as spent on greens and says so in chat: `Bought 12 Gysahl Greens for 744 gil (62 each).` Buying anything else isn't counted. Greens from the Auction House, a bazaar or a trade aren't counted either. Totals are per character, lifetime and per day.
- **Shared prices:** one price list for all your characters, in `data/prices.txt`. A sale on any character updates it. The **Sold** total (gil earned) is still per character.
- **Estimates only:** NPC prices are usually far below auction prices. Use `//bup price` if you want values based on what the item really sells for.

---

## Currency rewards

Some digs pay out a currency instead of an item, depending on the zone. BirdUp adds the amount to your totals and lists each reward in the item list (for example `Conquest Points` shows how many cache digs you've had).

| Reward | Zones | Chat message |
|--------|-------|--------------|
| Conquest points | Original, Zilart and CoP areas | `...cache of beastman resources and receive N conquest points!` |
| Imperial Standing | Aht Urghan areas | `...cache of beastman resources and receive N Imperial Standing!` |
| Allied notes | Wings of the Goddess areas | `...cache of beastman confederate resources and receive N allied notes!` |
| Bayld | Seekers of Adoulin areas | `You receive N bayld!` |

These totals count only what BirdUp saw from digging, so they won't match your in-game conquest point balance, which also includes other sources and spending.

---

## Safety stops

Auto-dig stops, with a chat message saying why, when:

- you zone or log out
- you run out of Gysahl Greens
- free inventory slots reach your `slots` threshold
- you reach your fatigue cap (if `stopfatigue` is on)
- you reach your `max` find target for the session
- you are not mounted (if `mount` is on)
- the game reports a full inventory
- it couldn't dig 7 times in a row (see below; this one also plays a call sound)

It also changes direction when it detects it's stuck or hasn't moved in a while.

### Walls

If the chocobo moves at less than 40% of its normal running speed (BirdUp measures this as you go; never less than `blocked_progress`, 1 yalm a second), or a move takes too long, it's treated as blocked by a wall. That includes grinding along a wall at a shallow angle. Auto-dig stops and digs right where it is, even if it hasn't traveled the usual distance, then faces away from the wall (120 to 240 degrees from it) and carries on. If it's blocked again straight away, it turns away without digging.

BirdUp remembers the wall's position and direction until you're 10 yalms past it. Until then, no move heads back toward it (within 70 degrees), including random turns and turnarounds from bad ground.

### Staying in one area

When auto-dig starts, the spot you're standing on becomes the center of the digging area. After every dig, once its result is in, the chocobo either carries on the way it was going or turns to a random heading (`turnchance`, default a 50% chance to turn), and only then starts moving to the next spot. If carrying on, or the new heading, would take the next dig outside the area (`area`, default 20 yalms), it picks another one, or heads back toward the center if none fits. `//bup anchor` moves the center to where you are now.

The game's map grid squares (like H-8) aren't the same size in every zone, so BirdUp uses a circle around your start point instead. Set `area` to roughly the size of the grid square you want to stay in.

### Ground that can't be dug

Some patches of ground can't be dug. When auto-dig hits one, it doesn't stop:

1. The game answers *"You cannot dig here."* straight away, or no result arrives in time (results normally take about 4 seconds, the length of the dig animation). Either way, the spot counts as undiggable. If a missing result turns up late anyway (within 12 seconds), it's still recorded and the failed-dig count resets.
2. The first time, it turns roughly 180 degrees (give or take 30) and moves `turn` yalms (default 3). If the next spot is bad too, it turns left or right instead and goes 2 yalms further each time, so it gets clear of a patch of bad ground instead of bouncing between two spots. Near a wall, it always heads away from the wall.
3. It digs again straight away, without needing the usual full distance.
4. A chat line says it happened, with a count (for example `(3/7)`).
5. After 7 failed digs in a row (`badlimit`), auto-dig stops and alerts you with a chat line, a call sound and a chocobo-flavored echo (change it with `//bup set stopecho`), so you can move somewhere better and press **START**. Any dig that gets a result resets the count.

That spot isn't counted as a dig.

*"You must wait longer to perform that action."* means a dig went in too soon (the last dig was still playing, or the cooldown hadn't finished). That's not bad ground: auto-dig waits a second and digs the same spot again.

---

## Per-character data

Everything is stored under `Windower/addons/birdup/data/`:

| File | Contents |
|------|----------|
| `settings.xml` | Settings and HUD position, with a separate section per character. |
| `prices.txt` | Item prices (best city), shared by all characters. |
| `city_prices.txt` | Price per item per city, shared by all characters. |
| `history_<name>.txt` | That character's daily dig log, one line per JST day (including RoE dig objectives completed). |
| `zones_<name>.txt` | That character's per-zone, per-Wing-rank dig stats (used by `zone` and `export`). |
| `debug/` | Debug logs, one file per `debug on`. |
| `export/` | Shareable drop reports from `export`. |
| `import/` | Put other players' export `.csv` files here for `import`. |
| `community/` | Imported players, one file each. |
| `id.txt` | This install's random sharing id. |
| `lifetime_<name>.txt` | That character's lifetime totals, gil from sales, currency totals, daily fatigue and free-dig counts, and lifetime item list. |

When you log in as a different character, BirdUp loads that character's profile and resets the session stats. New characters start from the defaults. Use `//bup saveall` on a configured character to copy its settings to everyone.

### Settings reference

These are in `settings.xml` and can be changed with the commands above.

| Setting | Default | Meaning |
|---------|---------|---------|
| `dig_interval` | 4 | No longer used (the Wing Skill cooldown sets the pace). |
| `extra_wait` | 0 | Extra seconds on top of the dig cooldown. |
| `move_during_dig` | false | No longer used (see `run_during_dig`). |
| `run_during_dig` | true | Run during each dig; next dig right after the result (`rundig`). |
| `humanize` | 0 | Up to this many random extra seconds per dig. |
| `jitter` | 0.6 | No longer used (see `humanize`). |
| `required_distance` | 5 | Yalms (2D) to travel between digs. |
| `min_distance` | 2 | Never dig closer than this to the last dig (`mindist`). |
| `move_timeout` | 8 | Seconds before a movement attempt is abandoned and it turns. |
| `result_buffer` | 0.3 | Seconds after a dig result before turning and moving. |
| `dig_settle` | 2.5 | No longer used (the dig result means the dig has finished). |
| `turn_chance` | 50 | % chance to turn after a dig. |
| `bad_ground_limit` | 7 | Failed digs in a row before auto-dig stops and alerts you. |
| `roam_radius` | 20 | Yalms auto-dig stays within, around where it started (0 = no limit). |
| `turn_distance` | 3 | Yalms to move after turning away from undiggable ground. |
| `stop_settle` | 0.4 | Seconds the chocobo must be standing still before a dig (it slides a little after running stops). |
| `result_timeout` | 5 | Seconds to wait for a dig result before treating the spot as undiggable (until self-tuning has 5 measurements, or always if `auto_tune` is off). |
| `auto_tune` | true | Set the no-result wait from measured result times. |
| `stuck_check_time` | 1.0 | How often it checks whether you're moving. |
| `stuck_epsilon` | 0.2 | Minimum yalms moved per check before you count as stuck. |
| `blocked_progress` | 1.0 | Yalms per second below which the chocobo always counts as blocked by a wall (it also counts as blocked below 40% of its measured running speed). |
| `warn_greens` | 10 | Panel warning at this many greens or fewer (0 = off). |
| `warn_slots` | 5 | Panel warning at this many free slots or fewer (0 = off). |
| `max_success` | 100 | Stop after this many finds today (0 = off). |
| `fatigue_cap` | 100 | Daily fatigue cap. |
| `stop_at_fatigue` | true | Stop at the cap. |
| `min_free_slots` | 2 | Stop at this many free slots or fewer (0 = off). |
| `require_mount` | true | Stop if you're not mounted. |
| `hud_visible` | true | Show the HUD. |
| `auto_hide` | true | Show the HUD only while on a chocobo or auto-digging. |
| `line_spacing` | 18 | Pixels from one HUD line to the next. |
| `compact` | false | Show only the key rows. |
| `collapse_items` | false | Hide the item list. |
| `locked` | false | Panel can't be dragged. |
| `zone_window` | false | Show the zone stats window. |
| `hyper_start` / `hyper_end` | 0 | Saved campaign dates (Japan, yyyymmdd); 0 = none. |
| `finds_view` | today | Item list shows `today` or `lifetime`. |
| `pos` | x=1100, y=200 | HUD position. |

---

## Known limitations

- **Untested in game:** the movement calls (`windower.ffxi.run` and `turn`), the mount check (status 5 = riding a chocobo; status 85, other mounts, doesn't count), and the HUD's `images` rectangles haven't been confirmed on a live client.
- **Multi-item digs:** whether a dig that returns more than one item (such as Bore or Burrow) adds one fatigue or several is unconfirmed. BirdUp assumes one.
- **Game messages:** *"You cannot dig here."* and *"You must wait longer to perform that action."* are confirmed from a debug log. The "inventory full" wording is still a best guess.
- **Sale detection:** reads the vendor sell packets (0x084 pick, 0x085 confirm), then the gil that arrives within 5 seconds. If a price looks wrong, correct it with `//bup price`.
- **Currency wording:** the reward messages come from BG-Wiki and an FFXIAH thread, not from a live client. If a total stays at zero after a cache dig, send me the exact chat line.
- **Main inventory only:** only the main inventory is tracked, not the satchel, sack or case.
- **English client:** result messages are matched in English.
- **Daily reset:** the JST day change (10:00 AM Eastern standard time, 11:00 AM daylight time) is checked every few seconds, even while the panel is hidden. It resets fatigue and today's finds (the `max` limit), and starts a new session (attempts, hit rate and the session timer start over). You get a chat line when it happens. You don't need to reload or relog.
- **Dig tracking:** digs are spotted from the game's dig action, so both typed `/dig` and Dig from the menu are tracked. A dig gives at most one item; `Obtained:` lines that aren't the result of a dig are ignored.
- **Text layout:** if lines overlap or look too far apart at your font size, adjust with `//bup set spacing <pixels>`.

## Troubleshooting

| Problem | Try |
|---------|-----|
| Nothing appears | It only shows on a chocobo by default; `//bup set autohide off` to always show it. Otherwise `//lua load birdup`, check the console for errors, and make sure `//bup hud` isn't hiding it. |
| Panel is blank or text floats | The `images` rectangles may not render on your setup. Report it with a screenshot. |
| Stops saying "not mounted" while mounted | `//bup set mount off`. |
| Fatigue count is off | `//bup fatigue <n>` to correct it. |
| Free digs never register | Check the exact chat text of a free dig against the message above. |
| Stuck against walls | It should dig and turn away on its own now. If it still grinds along a wall, raise `blocked_progress` in settings.xml (for example 2.0). |
| A message isn't recognized | `//bup debug on`, reproduce it, `//bup debug off`, and send the file from `data/debug/`. |
| Wrong profile after switching characters | `//lua reload birdup`. |

## Notes on use

Automating movement and actions may go against the game's terms of service or your server's rules. Check them yourself and use this at your own risk.

## Code layout

| File | What's in it |
|------|--------------|
| `birdup.lua` | The panel, auto-dig, dig tracking, prices, history and commands. |
| `birdup_zones.lua` | Per-zone drop stats, and the import/export sharing. |
| `birdup_roe.lua` | Records of Eminence progress. |
| `birdup_rewards.lua` | Digging rewards by zone (BG-Wiki data) and the REWARDS window. |
| `update_check.lua` | Reports in chat on load whether a newer version is on GitHub. |

Windower runs LuaJIT, which limits how many variables one file and one function can use. Splitting BirdUp up keeps it well inside those limits, so new features can keep being added safely.

## Credits

- Auto-dig logic based on [Velner/chocodig](https://github.com/Velner/chocodig).
- The "with ease" free-dig message was identified from the DigTracker addon thread on FFXIAH and the BG-Wiki chocobo digging pages.
