# BirdUp

A Windower 4 addon for Final Fantasy XI that automates chocobo digging and tracks everything about it: fatigue, free digs, inventory space, and every item you find. It combines the auto-dig behavior of [Velner/chocodig](https://github.com/Velner/chocodig) with dig tracking, all shown on one draggable HUD.

**Author:** Valdimar @ Phoenix  **Version:** 1.6  **Commands:** `//birdup` or `//bup`

> Status: untested release. Run short sessions first and watch the Windower console for Lua errors.

---

## Features

- **Auto-dig:** walks around the zone, digs on a timer once it has moved far enough, and turns when stuck. On ground that can't be dug, it turns roughly around, moves a few yalms and tries again.
- **Wing Skill:** reads your Wing Skill from chat and sets the dig cooldown to match (never digs faster than the game allows).
- **Start / Stop buttons:** click them right on the panel.
- **Daily history:** one log per Japan day, with every session that day added together.
- **Fatigue tracker:** a bar and counter for today's fatigue-counting digs against your cap, per character, reset at midnight JST.
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
   ```
2. In game, load it:
   ```
   //lua load birdup
   ```
3. Optional, to load automatically: add this line to your Windower `init.txt` (or a per-character script):
   ```
   lua load birdup
   ```

## Quick start

1. Mount your chocobo and carry Gysahl Greens.
2. Set your daily cap if it isn't 100 (see [Fatigue](#fatigue-and-free-digs)): `//bup cap 200`
3. Click **START** on the panel (or type `//bup start`).
4. Click **STOP** (or `//bup stop`) any time. `//bup pause` pauses; the START button then reads **RESUME**.

The HUD appears automatically when you get on a chocobo and hides when you get off (turn this off with `//bup autohide off`). Tracking runs in the background either way, so manual `/dig` use is still counted.

---

## The HUD

| Area | What it shows |
|------|---------------|
| Title and top bar | Today's fatigue digs against your cap. The bar is green, turns amber at 70% and red at 90%. |
| START / STOP | Buttons that start and stop auto-digging. The one that does something right now is bright. |
| State | IDLE, DIGGING, MOVING or PAUSED. |
| Wing | Your Wing Skill, its rank, and the cooldown between digs at that rank. Shows `?` until it's seen in chat or set with `//bup wing <level>`. |
| Fatigue | Fatigue digs used, the cap, and how many are left. |
| Free digs | Free digs today and what percentage of successful digs were free. |
| Attempts | Digs this session that got a result (an item, a reward or "find nothing"), with hits and misses. A `/dig` the game rejects, for example on cooldown, isn't counted. |
| Hit rate | Successful digs as a percentage of attempts. |
| Greens | Gysahl Greens in your inventory (red under 10). |
| Inventory | Used / max slots and free count. Amber at 8 or fewer free, red at your auto-stop threshold. |
| Next dig | Seconds until the next dig, and distance moved against the required distance. |
| Session | Session time and finds per hour. |
| Today | Finds and digs since midnight JST, and how many sessions that covers. Only digs that got a result count. |
| Lifetime | Total finds for this character. |
| Sold | Gil you've earned selling dug-up items to vendors (lifetime, plus today). |
| Est. val | Estimated gil value of your finds at the prices BirdUp has learned (lifetime, plus today). |
| Conquest | Lifetime conquest points earned from digging, with this session's gain. Imperial, Allied and Bayld rows appear once you've earned any. |
| Items found | Every item type found today (since midnight JST) or in your lifetime, most common first, with counts and `@price` each where known. Prices up to 9,999 are shown in full (`@1,234`); higher ones are rounded to the nearest half thousand or half million (`@30.5k` for 30,251, `@250k`, `@1.5m`). `//bup prices` always shows the full number. Today's list survives reloads and logouts and only clears at the JST day change. The panel grows to fit. |

The panel widens automatically to fit its longest line. Drag the panel (anywhere except the buttons) to move it. The text moves with the box, and the position is saved per character when you let go.

Item names are shown plainly (for example `Insect Wing`, not `Insect wing.1`). Names saved by older versions are cleaned up and merged automatically. Use `//bup spacing <pixels>` to change the gap between lines (default 18).

---

## Commands

Use `//bup` (or `//birdup`) followed by:

| Command | What it does |
|---------|--------------|
| `start` | Begin auto-digging. |
| `stop` | Stop auto-digging (the tracker keeps running). |
| `pause` | Pause or resume. |
| `reset` | Reset session stats (attempts, session timer). Today's items and daily fatigue are kept. |
| `status` | Print a summary to chat. |
| `distance <yalms>` | Distance to travel between digs. |
| `turn <yalms>` | How far to move after turning away from ground that can't be dug (default 3). |
| `timer <seconds>` | Base time between digs. |
| `jitter <seconds>` | Random plus or minus added to the timer, so digs aren't evenly spaced. |
| `max <count>` | Auto-stop after this many finds this session (0 = off). |
| `cap <count>` | Your daily fatigue cap. |
| `fatigue` | Show today's fatigue count. |
| `fatigue <n>` | Set today's fatigue count (to sync after digging without the addon). |
| `fatigue reset` | Zero today's fatigue and free-dig counters. |
| `stopfatigue on\|off` | Auto-stop when the cap is reached (default on). |
| `slots <n>` | Auto-stop when free inventory slots are at or below n (default 2, 0 = off). |
| `mount on\|off` | Require being mounted to run. |
| `wing` | Show your Wing Skill and dig cooldown. |
| `wing <level>` | Set your Wing Skill by hand (for example after checking it with an NPC). Skill-ups seen in chat keep raising it from there. |
| `history` | Daily log for the last 7 days. `history 14` for 14 days. |
| `history <yyyymmdd>` | One day in full, with every item found. `history today` works too. |
| `prices clean` | Remove saved prices for items that no character has dug up. |
| `hud` | Show or hide the display. |
| `autohide on\|off` | Only show the display while on a chocobo (default on). |
| `spacing <pixels>` | Distance from one display line to the next (default 18). |
| `view today\|lifetime` | Which totals the item list shows. |
| `finds` | Print the full item list to chat. |
| `price <item> <gil>` | Set an item's price by hand, per unit. `0` clears it. |
| `prices` | List known prices and the gil earned from sales. |
| `currency` | Print lifetime and session conquest points, Imperial Standing, allied notes and bayld. |
| `profile` | Show this character's saved settings. |
| `saveall` | Copy the current settings to every character. |
| `help` | List commands in game. |

---

## Fatigue and free digs

Chocobo digging has a daily fatigue limit based on **successful digs**, not attempts. Once you reach it, further digs find nothing until midnight JST.

- A rental chocobo's cap is **100**. A raised chocobo's cap can be 100 to 200, and Blue Race Silks can raise your effective total because some digs are free.
- A **free dig** doesn't add fatigue. The game prints *"It appears your chocobo found this item with ease."* on the line after the item line.

How BirdUp counts:

1. Every successful dig (an item, a bayld reward or a beastman cache) adds 1 fatigue.
2. If the "with ease" line follows within a few seconds, that fatigue is taken back and a free dig is recorded instead.
3. A dig that gives several items lists all of them but counts as one dig. This is an assumption; see [Known limitations](#known-limitations).
4. The counter resets at midnight JST (UTC+9).

BirdUp can only count digs it sees. If you dug earlier in the day without it loaded, set the count manually with `//bup fatigue <n>`, and set your cap with `//bup cap <n>`.

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
- Auto-dig waits at least that cooldown (plus half a second) between digs, or your `timer` setting if that's longer.
- Skill-ups are read from the game's line *"Your wing skill improved to 15!"* (confirmed in game). Other lines with "wing skill" and a level are matched too. If the number is ever wrong, set it with `//bup wing <level>`.
- A skill-up that only says it rose by a point can't be used until BirdUp knows your starting level.

---

## Daily history

Fatigue resets at midnight JST, so BirdUp keeps one log per Japan day. If you dig several times in a day, every session goes into that day's single log.

Each day records: digs, finds, misses, fatigue and free digs, number of sessions, time spent digging, gil from vendor sales, currency rewards, your Wing Skill, and every item found. Use `//bup history` for a summary and `//bup history 20261101` for one day's items. The log is saved in `data/history_<name>.txt`.

---

## Selling and item prices

BirdUp learns what your dug-up items are worth from your own sales.

1. Sell an item you've dug up to an NPC vendor.
2. BirdUp sees which item and how many you confirmed selling, then the gil that arrives.
3. It works out the price per item (gil gained divided by the quantity sold). The first time, you'll see `Price history: Pebble added at 3 gil each (sold 12 for 36 gil).` If a later sale gets a different price you'll see `Price history: Pebble updated 3 -> 4 gil each (...)`. A sale at the price already recorded is silent; the gil still counts toward **Sold**.
4. From then on, every find of that item counts toward the **Est. val** row, and the item list shows its price.

Details:

- **Only dug-up items, only vendors:** an item must have been dug up by any of your characters (so an alt can sell your main's finds and still update the price). Anything else you sell is ignored, so it never gets added to the price file. Bazaar and auction house sales are ignored too.
- **Clean-up:** older versions could save prices for items you never dug. `//bup prices clean` removes them.
- **Last sale wins:** each sale replaces the saved price, so the price follows what you most recently got.
- **Auction house prices:** set those by hand with `//bup price <item> <gil>`.
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

It also changes direction when it detects it's stuck or hasn't moved in a while.

### Ground that can't be dug

Some patches of ground can't be dug. When auto-dig hits one, it doesn't stop:

1. It waits up to 5 seconds for the dig result. If the game refuses the dig, or no result arrives, it treats the spot as undiggable.
2. It turns roughly 180 degrees (give or take 30), moves `turn` yalms (default 3) and digs again straight away, without needing the usual full distance.
3. A chat line says it happened, at most once every 15 seconds.

That spot isn't counted as a dig.

---

## Per-character data

Everything is stored under `Windower/addons/birdup/data/`:

| File | Contents |
|------|----------|
| `settings.xml` | Settings and HUD position, with a separate section per character. |
| `prices.txt` | Item prices, shared by all characters. |
| `history_<name>.txt` | That character's daily dig log, one line per JST day. |
| `lifetime_<name>.txt` | That character's lifetime totals, gil from sales, currency totals, daily fatigue and free-dig counts, and lifetime item list. |

When you log in as a different character, BirdUp loads that character's profile and resets the session stats. New characters start from the defaults. Use `//bup saveall` on a configured character to copy its settings to everyone.

### Settings reference

These are in `settings.xml` and can be changed with the commands above.

| Setting | Default | Meaning |
|---------|---------|---------|
| `dig_interval` | 4 | Seconds between digs. |
| `jitter` | 0.6 | Random plus or minus seconds on the interval. |
| `required_distance` | 5 | Yalms (2D) to travel between digs. |
| `move_timeout` | 8 | Seconds before a movement attempt is abandoned and it turns. |
| `turn_distance` | 3 | Yalms to move after turning away from undiggable ground. |
| `result_timeout` | 5 | Seconds to wait for a dig result before treating the spot as undiggable. |
| `stuck_check_time` | 1.0 | How often it checks whether you're moving. |
| `stuck_epsilon` | 0.2 | Minimum yalms moved per check before you count as stuck. |
| `max_success` | 100 | Session find target (0 = off). |
| `fatigue_cap` | 100 | Daily fatigue cap. |
| `stop_at_fatigue` | true | Stop at the cap. |
| `min_free_slots` | 2 | Stop at this many free slots or fewer (0 = off). |
| `require_mount` | true | Stop if you're not mounted. |
| `hud_visible` | true | Show the HUD. |
| `auto_hide` | true | Show the HUD only while on a chocobo or auto-digging. |
| `line_spacing` | 18 | Pixels from one HUD line to the next. |
| `finds_view` | today | Item list shows `today` or `lifetime`. |
| `pos` | x=1100, y=200 | HUD position. |

---

## Known limitations

- **Untested in game:** the movement calls (`windower.ffxi.run` and `turn`), the mount check (status 5 for chocobo, 85 for the mount system; other mounts also count as mounted), and the HUD's `images` rectangles haven't been confirmed on a live client.
- **Multi-item digs:** whether a dig that returns more than one item (such as Bore or Burrow) adds one fatigue or several is unconfirmed. BirdUp assumes one.
- **Stop messages:** the "inventory full" and "can't dig here" patterns are best guesses at the game's wording. Undiggable ground is also caught when no result arrives, so the wording isn't required for the turnaround to work.
- **Sale detection:** reads the vendor sell packets (0x084 pick, 0x085 confirm), then the gil that arrives within 5 seconds. If a price looks wrong, correct it with `//bup price`.
- **Currency wording:** the reward messages come from BG-Wiki and an FFXIAH thread, not from a live client. If a total stays at zero after a cache dig, send me the exact chat line.
- **Main inventory only:** only the main inventory is tracked, not the satchel, sack or case.
- **English client:** result messages are matched in English.
- **Text layout:** if lines overlap or look too far apart at your font size, adjust with `//bup spacing`.

## Troubleshooting

| Problem | Try |
|---------|-----|
| Nothing appears | It only shows on a chocobo by default; `//bup autohide off` to always show it. Otherwise `//lua load birdup`, check the console for errors, and make sure `//bup hud` isn't hiding it. |
| Panel is blank or text floats | The `images` rectangles may not render on your setup. Report it with a screenshot. |
| Stops saying "not mounted" while mounted | `//bup mount off`. |
| Fatigue count is off | `//bup fatigue <n>` to correct it. |
| Free digs never register | Check the exact chat text of a free dig against the message above. |
| Stuck against walls | Raise `distance`, or try `//bup timer` slightly higher. |
| Wrong profile after switching characters | `//lua reload birdup`. |

## Notes on use

Automating movement and actions may go against the game's terms of service or your server's rules. Check them yourself and use this at your own risk.

## Credits

- Auto-dig logic based on [Velner/chocodig](https://github.com/Velner/chocodig).
- The "with ease" free-dig message was identified from the DigTracker addon thread on FFXIAH and the BG-Wiki chocobo digging pages.
