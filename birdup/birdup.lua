_addon.name     = 'birdup'
_addon.author   = 'Valdimar @ Phoenix' -- auto-dig based on Velner/chocodig
_addon.version  = '2.7'
_addon.commands = {'birdup', 'bup'}

local texts  = require('texts')
local images = require('images')
local config = require('config')
local res    = require('resources')

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local defaults = {
    dig_interval      = 4,     -- seconds between digs
    jitter            = 0.6,   -- +/- random seconds added to the interval
    required_distance = 5,     -- yalms (2D) to travel between digs
    move_timeout      = 8,
    turn_distance     = 3,     -- yalms to move after turning away from undiggable ground
    dig_settle        = 2.5,   -- seconds to let the dig animation finish before turning and moving
    turn_chance       = 50,    -- % chance to turn after a dig (otherwise keep going the same way)
    roam_radius       = 20,    -- stay within this many yalms of where auto-dig started (0 = no limit)
    result_timeout    = 5,
    warn_greens       = 10,    -- flash the panel when greens are at or below this (0 = off)
    warn_slots        = 5,     -- flash the panel when free inventory slots are at or below this (0 = off)
    blocked_progress  = 1.0,   -- yalms a second below which the chocobo counts as blocked (walls)
    bad_ground_limit  = 7,     -- stop and alert after this many "can't dig here" in a row (0 = never)
    stop_echo         = 'Kweh! This ground is all wark and no dig. Find me a better spot!', -- extra echo with the alert     -- seconds to wait for a dig result before treating the spot as undiggable
    stuck_check_time  = 1.0,
    stuck_epsilon     = 0.2,
    max_success       = 100,   -- 0 = never auto-stop on count
    require_mount     = true,
    hud_visible       = true,
    auto_hide         = true,
    zone_window       = false, -- zone stats window beside the main panel (ZONES button / //bup zonewin)  -- only show the HUD while on a chocobo (or auto-digging)
    line_spacing      = 18,    -- pixels from one HUD line to the next
    finds_view        = 'today',   -- 'today' (since midnight JST, survives reloads) or 'lifetime'
    fatigue_cap       = 100,   -- daily fatigue-counting digs (rental 100; raised/silks up to ~200)
    stop_at_fatigue   = true,
    min_free_slots    = 2,     -- auto-stop when free inventory slots <= this (0 = off)
    pos               = {x = 1100, y = 200},
}
local settings = config.load(defaults)

local GREENS_ID   = 4545
-- player.status while riding: 5 = chocobo (rental/whistle), 85 = mount system
local MOUNT_STATUSES = {[5] = true, [85] = true}

local function is_mounted()
    local p = windower.ffxi.get_player()
    return p and MOUNT_STATUSES[p.status] or false
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local S = {
    running = false, paused = false,
    attempts = 0, successes = 0, fails = 0, free = 0, discern = 0, cur = {}, gil = 0,
    drops = {},               -- item name -> count (this session)
    first_dig = nil,          -- os.time() of first attempt this session
    pending = nil,            -- os.clock() of last /dig, awaiting a result
}
local life = {attempts = 0, successes = 0, drops = {}, fatigue = 0, free = 0, day = 0, cur = {}, gil = 0, wing = nil, wing_approx = false, discern = 0}
local life_dirty, life_saved = false, 0

local next_dig, last_dig_pos = 0, nil
local anchor = nil -- {x, y}: centre of the area auto-dig stays in
local settle_until = 0 -- don't turn or move before this (dig animation still playing)
local turn_until = 0   -- after turning, wait this long before starting to run
local moving, move_start_time, move_start_pos = false, 0, nil
local prog_time, prog_pos = 0, nil
local greens, greens_time = nil, 0
local inv_used, inv_max = nil, nil

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Debug log: //bup debug on writes to data/debug/debug_<date>_<time>.txt
-- (a new file each time, so several can be kept and sent)
---------------------------------------------------------------------------
local debug_f, debug_path = nil, nil

-- show control bytes as <XX> so the game's hidden codes are visible
local function escape(str)
    return (tostring(str):gsub('[%z\1-\31\127-\255]', function(c) return ('<%02X>'):format(c:byte()) end))
end

local function dbg(kind, msg)
    if not debug_f then return end
    local t = os.clock()
    debug_f:write(('%s.%03d  %-6s %s\n'):format(os.date('%H:%M:%S'), math.floor((t % 1) * 1000), kind, escape(msg)))
    debug_f:flush()
end

local function log(msg)
    windower.add_to_chat(207, ('[BirdUp] %s'):format(msg))
    dbg('BIRDUP', msg)
end

local function commas(n)
    local s = tostring(math.floor(n))
    local k
    repeat s, k = s:gsub('^(-?%d+)(%d%d%d)', '%1,%2') until k == 0
    return s
end

-- Short price for the item list: full up to 4 digits (1,234), then
-- thousands or millions rounded to the nearest half (30,251 -> 30.5k)
local function short_price(n)
    n = math.floor(n)
    if n < 10000 then return commas(n) end
    local function half(v) -- round to nearest .5, drop a trailing .0
        local r = math.floor(v * 2 + 0.5) / 2
        local whole = math.floor(r)
        return commas(whole) .. (r > whole and '.5' or '')
    end
    local k = math.floor(n / 1000 * 2 + 0.5) / 2
    if k < 1000 then return half(n / 1000) .. 'k' end
    return half(n / 1000000) .. 'm'
end

local function fmt_time(sec)
    sec = math.max(0, math.floor(sec))
    return ('%02d:%02d:%02d'):format(math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60)
end

-- short duration: 45s, 18m, 1h05m
local function fmt_short(sec)
    sec = math.max(0, math.floor(sec))
    if sec < 60 then return sec .. 's' end
    if sec < 3600 then return math.floor(sec / 60 + 0.5) .. 'm' end
    return ('%dh%02dm'):format(math.floor(sec / 3600), math.floor(sec / 60) % 60)
end

local function get_me() return windower.ffxi.get_mob_by_target('me') end

local function get_pos()
    local me = get_me()
    return me and {x = me.x, y = me.y} or nil
end

local function dist2d(a, b)
    if not a or not b then return 0 end
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function refresh_greens(now)
    if now - greens_time < 1 then return end
    greens_time = now
    local items = windower.ffxi.get_items()
    if not items or not items.inventory then greens = nil inv_used, inv_max = nil, nil return end
    inv_used, inv_max = items.inventory.count, items.inventory.max
    local n = 0
    for i = 1, (items.inventory.max or 80) do
        local e = items.inventory[i]
        if e and e.id == GREENS_ID then n = n + (e.count or 0) end
    end
    greens = n
end

---------------------------------------------------------------------------
-- Lifetime stats (simple tab-separated file)
---------------------------------------------------------------------------
local char_name = nil -- set by switch_character() below
local clean_name      -- defined in the prices section below
local save_history    -- defined just below
local save_zone_stats -- defined after the Wing Skill section

---------------------------------------------------------------------------
-- Daily history: one entry per Japan day (fatigue resets at midnight JST).
-- Every session dug that day is added into the same entry.
-- Saved as data/history_<name>.txt, one line per day.
---------------------------------------------------------------------------
local history = {} -- yyyymmdd (JST) -> entry

local function new_day_entry()
    return {attempts = 0, finds = 0, fails = 0, fatigue = 0, free = 0, sessions = 0,
            secs = 0, gil = 0, wing = nil, discern = 0, cur = {}, drops = {}}
end

local function history_path()
    local who = (char_name or 'unknown'):lower():gsub('[^%w_-]', '')
    return windower.addon_path .. 'data/history_' .. who .. '.txt'
end

local function load_history()
    history = {}
    local f = io.open(history_path(), 'r')
    if not f then return end
    for line in f:lines() do
        local p = {}
        for field in (line .. '\t'):gmatch('(.-)\t') do p[#p + 1] = field end
        local d = tonumber(p[1])
        if d then
            local e = new_day_entry()
            e.attempts, e.finds, e.fails = tonumber(p[2]) or 0, tonumber(p[3]) or 0, tonumber(p[4]) or 0
            e.fatigue, e.free, e.sessions = tonumber(p[5]) or 0, tonumber(p[6]) or 0, tonumber(p[7]) or 0
            e.secs, e.gil, e.wing = tonumber(p[8]) or 0, tonumber(p[9]) or 0, tonumber(p[10])
            for k, n in (p[11] or ''):gmatch('([^=|]+)=(%d+)') do e.cur[k] = tonumber(n) end
            for k, n in (p[12] or ''):gmatch('([^=|]+)=(%d+)') do e.drops[k] = tonumber(n) end
            e.discern = tonumber(p[13]) or 0
            history[d] = e
        end
    end
    f:close()
end

save_history = function()
    windower.create_dir(windower.addon_path .. 'data')
    local f = io.open(history_path(), 'w')
    if not f then return end
    local days = {}
    for d in pairs(history) do days[#days + 1] = d end
    table.sort(days)
    for _, d in ipairs(days) do
        local e = history[d]
        local cur, drops = {}, {}
        for k, n in pairs(e.cur) do cur[#cur + 1] = k .. '=' .. n end
        for k, n in pairs(e.drops) do drops[#drops + 1] = k .. '=' .. n end
        f:write(('%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%s\t%s\t%s\t%d\n'):format(
            d, e.attempts, e.finds, e.fails, e.fatigue, e.free, e.sessions, e.secs, e.gil,
            e.wing and tostring(e.wing) or '', table.concat(cur, '|'), table.concat(drops, '|'), e.discern or 0))
    end
    f:close()
end

local function life_path()
    local who = (char_name or 'unknown'):lower():gsub('[^%w_-]', '')
    return windower.addon_path .. 'data/lifetime_' .. who .. '.txt'
end

local function load_life()
    life = {attempts = 0, successes = 0, drops = {}, fatigue = 0, free = 0, day = 0, cur = {}, gil = 0,
            wing = nil, wing_approx = false, discern = 0}
    life_dirty = false
    local f = io.open(life_path(), 'r')
    if not f then return end
    for line in f:lines() do
        local k, v = line:match('^(.-)\t(%d+)$')
        if k then
            if k == '#attempts' then life.attempts = tonumber(v)
            elseif k == '#successes' then life.successes = tonumber(v)
            elseif k == '#fatigue' then life.fatigue = tonumber(v)
            elseif k == '#free' then life.free = tonumber(v)
            elseif k == '#day' then life.day = tonumber(v)
            elseif k:match('^#cur_') then life.cur[k:sub(6)] = tonumber(v)
            elseif k == '#gil' then life.gil = tonumber(v)
            elseif k == '#wing' then life.wing = tonumber(v)
            elseif k == '#discern' then life.discern = tonumber(v)
            elseif k == '#wing_approx' then life.wing_approx = tonumber(v) == 1
            else
                -- merge names saved by older versions ("Pebble.<code>1") into the plain name
                local name = clean_name(k) or k
                if name ~= k then life_dirty = true end
                life.drops[name] = (life.drops[name] or 0) + tonumber(v)
            end
        end
    end
    f:close()
end

local function save_life(force)
    if not life_dirty then return end
    if not force and os.clock() - life_saved < 30 then return end
    windower.create_dir(windower.addon_path .. 'data')
    local f = io.open(life_path(), 'w')
    if not f then return end
    f:write(('#attempts\t%d\n#successes\t%d\n#fatigue\t%d\n#free\t%d\n#day\t%d\n'):format(
        life.attempts, life.successes, life.fatigue, life.free, life.day))
    for key, n in pairs(life.cur) do f:write(('#cur_%s\t%d\n'):format(key, n)) end
    f:write(('#gil\t%d\n#discern\t%d\n'):format(life.gil, life.discern))
    if life.wing then
        f:write(('#wing\t%d\n#wing_approx\t%d\n'):format(life.wing, life.wing_approx and 1 or 0))
    end
    for name, n in pairs(life.drops) do f:write(('%s\t%d\n'):format(name, n)) end
    f:close()
    save_history()
    if save_zone_stats then save_zone_stats() end
    life_dirty, life_saved = false, os.clock()
end

---------------------------------------------------------------------------
-- HUD
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Item prices (shared by all characters, learned from your own sales)
---------------------------------------------------------------------------
local prices = {}                       -- item name -> gil each
local prices_path = windower.addon_path .. 'data/prices.txt'
local name_to_id, dug_by_id = nil, {}   -- dug_by_id: item id -> name (items you've dug up)

local function item_id_for(name)
    if not name_to_id then -- built once, on first use
        name_to_id = {}
        for id, v in pairs(res.items) do
            if v.en then
                local k = v.en:lower()
                if not name_to_id[k] then name_to_id[k] = id end
            end
        end
        for id, v in pairs(res.items) do -- long names as a fallback
            if v.enl then
                local k = v.enl:lower()
                if not name_to_id[k] then name_to_id[k] = id end
            end
        end
    end
    return name_to_id[(name or ''):lower()]
end

-- Turn a raw chat item name such as "Insect wing.<code>1" into the plain
-- item name ("Insect Wing"): strips FFXI inline codes, control bytes and
-- the trailing period/number, then uses the game's own spelling when known.
function clean_name(s) -- assigns the local declared above
    if not s then return nil end
    s = s:gsub(string.char(0x7F) .. '.', '')       -- FFXI inline codes
    s = s:gsub('[%z\1-\31\127-\255]', '')          -- any leftover non-printables
    s = s:gsub('^%s+', ''):gsub('%s+$', '')
    s = s:gsub('%.[^%a]*$', '')                    -- trailing ".1", "." etc.
    s = s:gsub('%s+$', '')
    if s == '' then return nil end
    local id = item_id_for(s)
    if id and res.items[id] and res.items[id].en then return res.items[id].en end
    return s
end

local function save_prices()
    windower.create_dir(windower.addon_path .. 'data')
    local f = io.open(prices_path, 'w')
    if not f then return end
    for name, n in pairs(prices) do f:write(('%s\t%d\n'):format(name, n)) end
    f:close()
end

local function load_prices()
    prices = {}
    local changed = false
    local f = io.open(prices_path, 'r')
    if not f then return end
    for line in f:lines() do
        local k, v = line:match('^(.-)\t(%d+)$')
        if k then
            local name = clean_name(k) or k
            if name ~= k then changed = true end
            prices[name] = tonumber(v)
        end
    end
    f:close()
    if changed then save_prices() end -- tidy names saved by older versions
end

local function register_dug(name)
    local id = item_id_for(name)
    if id then dug_by_id[id] = name end
end

-- Every item any of your characters has dug up (from all lifetime files),
-- so a sale on any character can update the shared price list.
local function all_dug_names()
    local dug = {}
    for name in pairs(life.drops) do dug[name] = true end
    local dir = windower.addon_path .. 'data/'
    for _, file in ipairs(windower.get_dir(dir) or {}) do
        if file:match('^lifetime_.+%.txt$') then
            local f = io.open(dir .. file, 'r')
            if f then
                for line in f:lines() do
                    local k = line:match('^(.-)\t%d+$')
                    if k and k:sub(1, 1) ~= '#' then dug[clean_name(k) or k] = true end
                end
                f:close()
            end
        end
    end
    return dug
end

local function value_of(drops)
    local total = 0
    for name, n in pairs(drops) do
        if prices[name] then total = total + prices[name] * n end
    end
    return total
end

load_prices()

-- Fatigue resets at midnight JST (UTC+9)
local function roll_day()
    local d = tonumber(os.date('!%Y%m%d', os.time() + 9 * 3600))
    if life.day ~= d then
        local was_set = life.day and life.day > 0
        life.day, life.fatigue, life.free = d, 0, 0
        life_dirty = true
        if was_set and char_name then log('New day in Japan: daily fatigue reset to 0.') end
    end
end

-- Today's history entry (created on first use each JST day)
local function today()
    roll_day()
    local e = history[life.day]
    if not e then
        e = new_day_entry()
        e.wing = life.wing
        history[life.day] = e
    end
    return e
end

---------------------------------------------------------------------------
-- Wing Skill (chocobo digging skill, March 2026 update) -> dig cooldown
-- Source: BG-Wiki "Wing Skill" / "Chocobo Digging"
---------------------------------------------------------------------------
local WING_RANKS = { -- {name, min skill, area delay after zoning, dig delay}
    {'Amateur',     0, 60, 15}, {'Recruit',   10, 55, 10}, {'Initiate',  20, 50, 5},
    {'Novice',     30, 45,  3}, {'Apprentice', 40, 40, 3}, {'Journeyman', 50, 35, 3},
    {'Craftsman',  60, 30,  3}, {'Artisan',   70, 25,  3}, {'Adept',     80, 20, 3},
    {'Veteran',    90, 15,  3}, {'Expert',   100, 10,  3},
}

local function wing_rank(skill)
    if not skill then return nil end
    local r = WING_RANKS[1]
    for _, w in ipairs(WING_RANKS) do if skill >= w[2] then r = w end end
    return r
end

-- seconds the game makes you wait between digs at your Wing Skill (nil = unknown)
local function wing_delay()
    local r = wing_rank(life.wing)
    return r and r[4] or nil
end

---------------------------------------------------------------------------
-- Per-zone drop stats, split by Wing rank (drop tables differ by rank).
-- Each character keeps data/zones_<name>.txt; //bup export combines every
-- character's file into one shareable report + CSV.
---------------------------------------------------------------------------
local zstats = {} -- zone id -> rank name -> {digs, finds, miss, discern, items = {}}

local function zones_path(who)
    who = (who or char_name or 'unknown'):lower():gsub('[^%w_-]', '')
    return windower.addon_path .. 'data/zones_' .. who .. '.txt'
end

local function current_zone()
    local info = windower.ffxi.get_info()
    return info and info.zone or nil
end

local function zone_name(id)
    local z = id and res.zones and res.zones[id]
    return z and z.en or ('Zone ' .. tostring(id))
end

local function new_zone_entry() return {digs = 0, finds = 0, miss = 0, discern = 0, items = {}} end

local function read_zone_file(path, into)
    local f = io.open(path, 'r')
    if not f then return end
    for line in f:lines() do
        local zid, rank, key, n = line:match('^(%d+)\t([^\t]+)\t([^\t]+)\t(%d+)$')
        if zid then
            zid, n = tonumber(zid), tonumber(n)
            into[zid] = into[zid] or {}
            local e = into[zid][rank] or new_zone_entry()
            into[zid][rank] = e
            if key == '#digs' then e.digs = e.digs + n
            elseif key == '#finds' then e.finds = e.finds + n
            elseif key == '#miss' then e.miss = e.miss + n
            elseif key == '#discern' then e.discern = e.discern + n
            else e.items[key] = (e.items[key] or 0) + n end
        end
    end
    f:close()
end

local function load_zone_stats()
    zstats = {}
    read_zone_file(zones_path(), zstats)
end

save_zone_stats = function()
    if not char_name then return end
    windower.create_dir(windower.addon_path .. 'data')
    local f = io.open(zones_path(), 'w')
    if not f then return end
    for zid, ranks in pairs(zstats) do
        for rank, e in pairs(ranks) do
            f:write(('%d\t%s\t#digs\t%d\n%d\t%s\t#finds\t%d\n%d\t%s\t#miss\t%d\n%d\t%s\t#discern\t%d\n'):format(
                zid, rank, e.digs, zid, rank, e.finds, zid, rank, e.miss, zid, rank, e.discern))
            for item, n in pairs(e.items) do f:write(('%d\t%s\t%s\t%d\n'):format(zid, rank, item, n)) end
        end
    end
    f:close()
end

-- entry for where you are now, at your current Wing rank
local function zone_entry()
    local zid = current_zone()
    if not zid then return nil end
    local r = wing_rank(life.wing)
    local rank = r and r[1] or 'Unknown'
    zstats[zid] = zstats[zid] or {}
    zstats[zid][rank] = zstats[zid][rank] or new_zone_entry()
    return zstats[zid][rank]
end

-- Hyper Chocobo Digging Campaign: every rank digs every 3s while it runs.
-- S.hyper: nil = not tested, true = active, false = not active
-- hyper_test: nil, 'need_base' (waiting for a normal dig to land),
--             'probe_next' (next dig is the test), 'probing' (test dig sent)
local HYPER_DELAY = 3
local HYPER_AREA_DELAY = 5
local hyper_test = nil
local hyper_mode = 'auto' -- 'auto' = test on each start; 'on'/'off' = set by //bup hyper (until reload)
local zoned_at = nil      -- os.clock() of the last zone-in

-- seconds before the first dig after zoning is allowed (0 = none)
local function zone_wait_left()
    if not zoned_at then return 0 end
    local r = wing_rank(life.wing)
    local delay = S.hyper and HYPER_AREA_DELAY or (r and r[3] or 60) -- unknown skill: slowest
    return math.max(0, zoned_at + delay - os.clock())
end

-- seconds between digs auto-dig should use right now
local function dig_delay()
    local wd = wing_delay() or 15 -- unknown Wing Skill: assume the slowest rank to be safe
    if S.hyper then wd = math.min(wd, HYPER_DELAY) end
    return wd
end

local function set_wing(n, approx, quiet)
    n = math.max(0, math.min(100, math.floor(n)))
    local old = life.wing
    life.wing, life.wing_approx, life_dirty = n, approx or false, true
    today().wing = n
    if quiet or (old == n and not approx) then return end
    local r = wing_rank(n)
    log(('Wing Skill %s%d (%s): %ds between digs, %ds after zoning.'):format(
        approx and '~' or '', n, r[1], r[4], r[3]))
end

local W_MIN, H = 280, 252
local W = W_MIN -- panel width; grows/shrinks to fit the longest line
local C = {
    dim  = '\\cs(140,148,165)', val = '\\cs(235,238,245)',
    good = '\\cs(110,220,150)', warn = '\\cs(255,200,90)',
    bad  = '\\cs(255,110,110)', acc  = '\\cs(120,190,255)', r = '\\cr',
}

local function solid(w, h, a, r, g, b, draggable)
    return images.new({
        pos = {x = settings.pos.x, y = settings.pos.y},
        color = {alpha = a, red = r, green = g, blue = b},
        size = {width = w, height = h},
        draggable = draggable or false,
    })
end

local function mk_text(size)
    return texts.new('', {
        pos = {x = settings.pos.x, y = settings.pos.y},
        bg = {alpha = 0},
        flags = {draggable = false, bold = false},
        text = {font = 'Consolas', size = size or 10, alpha = 255,
                red = 235, green = 238, blue = 245},
        padding = 0,
    })
end

-- Panel position. The panel is moved by our own mouse handler, which
-- repositions every piece in the same event, so text never trails the box.
local px, py = settings.pos.x, settings.pos.y
local panel_h = H

local hud = {
    bg     = solid(W, H, 215, 18, 20, 28),
    header = solid(W, 26, 255, 38, 52, 84),
    bar_bg = solid(W - 20, 10, 255, 40, 44, 58),
    bar    = solid(W - 20, 10, 255, 255, 200, 90),
    b_start = solid(1, 1, 255, 46, 110, 70),
    b_stop  = solid(1, 1, 255, 120, 50, 50),
    title  = mk_text(11),
    l_start = mk_text(10),
    l_stop  = mk_text(10),
    b_zones = solid(56, 18, 255, 60, 75, 110), -- header button: show/hide the zone window
    l_zones = mk_text(9),
}
hud.l_zones:text('ZONES')
local ZBTN_W, ZBTN_H = 56, 18

-- Zone stats window, docked to the right of the main panel
local ZW_MIN, ZW_GAP = 230, 6
local zwin = {
    bg     = solid(ZW_MIN, 100, 215, 18, 20, 28),
    header = solid(ZW_MIN, 26, 255, 38, 52, 84),
    title  = mk_text(11),
}
local zw_pool, zw_ry, zw_used, zw_w, zw_on = {}, {}, 0, ZW_MIN, false

-- Buttons, relative to the panel's top-left corner
local BTN_Y, BTN_H = 50, 22
local BTN_W = math.floor((W - 30) / 2)
local buttons = {
    start = {rx = 10,              img = hud.b_start, lbl = hud.l_start, text = 'START'},
    stop  = {rx = 20 + BTN_W,      img = hud.b_stop,  lbl = hud.l_stop,  text = 'STOP'},
}
for _, b in pairs(buttons) do
    b.img:size(BTN_W, BTN_H)
    b.lbl:text(b.text)
end
local ROWS_Y = BTN_Y + BTN_H + 10 -- first stat row

-- One text object per HUD line, so line spacing can be set exactly
-- (offsets live in their own table: Windower text objects don't keep extra fields)
local lines_pool, lines_ry, lines_used = {}, {}, 0
local hud_on = false
local hud_last = 0

-- visible width of a line: Windower's own measurement when it has one,
-- otherwise an estimate from the character count (color codes removed)
local function text_width(t, str, char_w)
    local plain = str:gsub('\\cs%(%d+,%d+,%d+%)', ''):gsub('\\cr', '')
    local est = #plain * char_w
    local ok, w = pcall(function() return (t:extents()) end)
    if ok and type(w) == 'number' and w > est then return w end
    return est
end

local layout -- defined below
local draw_zone_window -- defined below
local title_str = ''
local warned = {greens = false, slots = false}

local function set_width(w)
    if w == W then return end
    W = w
    hud.header:size(W, 26)
    hud.bar_bg:size(W - 20, 10)
    BTN_W = math.floor((W - 30) / 2)
    buttons.stop.rx = 20 + BTN_W
    for _, b in pairs(buttons) do b.img:size(BTN_W, BTN_H) end
    layout()
end

-- put every piece of the panel where it belongs for the current px, py
layout = function()
    hud.bg:pos(px, py)
    hud.header:pos(px, py)
    hud.title:pos(px + 10, py + 5)
    hud.bar_bg:pos(px + 10, py + 34)
    hud.bar:pos(px + 10, py + 34)
    for _, b in pairs(buttons) do
        b.img:pos(px + b.rx, py + BTN_Y)
        -- Consolas 10 is about 7.5 px per character
        b.lbl:pos(px + b.rx + math.floor((BTN_W - #b.text * 7.5) / 2), py + BTN_Y + 3)
    end
    for i = 1, lines_used do
        local t = lines_pool[i]
        t:pos(px + 10, py + (lines_ry[i] or 0))
    end
    hud.b_zones:pos(px + W - ZBTN_W - 6, py + 4)
    hud.l_zones:pos(px + W - ZBTN_W - 6 + 9, py + 5)
    -- zone window sits just right of the main panel
    local zx = px + W + ZW_GAP
    zwin.bg:pos(zx, py)
    zwin.header:pos(zx, py)
    zwin.title:pos(zx + 10, py + 5)
    for i = 1, zw_used do zw_pool[i]:pos(zx + 10, py + (zw_ry[i] or 0)) end
end

local function zwin_show(on)
    zw_on = on
    for _, e in pairs(zwin) do if on then e:show() else e:hide() end end
    if not on then for _, t in ipairs(zw_pool) do t:hide() end end
end

local function hud_show(on)
    for _, e in pairs(hud) do if on then e:show() else e:hide() end end
    if not on then
        for _, t in ipairs(lines_pool) do t:hide() end
        zwin_show(false)
    end
end

local function want_hud()
    if not settings.hud_visible then return false end
    if not settings.auto_hide then return true end
    return S.running or is_mounted()
end

local function refresh_visibility(force)
    local w = want_hud() and true or false
    if w ~= hud_on or force then
        hud_on = w
        hud_show(w)
        if w then layout() end
    end
end

-- list: { {text, y_offset}, ... }
local function draw_lines(list)
    for i, l in ipairs(list) do
        local t = lines_pool[i]
        if not t then t = mk_text(10); lines_pool[i] = t end
        t:text(l[1])
        lines_ry[i] = l[2]
        t:pos(px + 10, py + l[2])
        t:show()
    end
    for i = #list + 1, #lines_pool do lines_pool[i]:hide() end
    lines_used = #list
end

-- Zone stats window: this zone at your current Wing rank
draw_zone_window = function(sp)
    if not settings.zone_window then
        if zw_on then zwin_show(false) end
        return
    end
    if not zw_on then zwin_show(true) end
    local zid = current_zone()
    local wr = wing_rank(life.wing)
    local rank = wr and wr[1] or 'Unknown'
    local e = zid and zstats[zid] and zstats[zid][rank]
    local title = C.acc .. 'ZONE STATS' .. C.r
    zwin.title:text(title)

    local out, y = {}, 34
    local function add(text) out[#out + 1] = {text, y}; y = y + sp end
    add(C.val .. zone_name(zid) .. C.r)
    add(C.dim .. 'Wing rank  ' .. C.r .. rank)
    if e and e.digs > 0 then
        add(C.dim .. 'Digs       ' .. C.r .. ('%d  %s(%d finds, %d%%)%s'):format(e.digs, C.dim, e.finds,
            math.floor(e.finds / e.digs * 100 + 0.5), C.r))
        add(C.dim .. 'Miss       ' .. C.r .. ('%d  %s(discern %d)%s'):format(e.miss, C.dim, e.discern, C.r))
        y = y + 8
        add(C.acc .. 'ITEMS' .. C.r .. C.dim .. ' (rate per dig)' .. C.r)
        local list = {}
        for item, n in pairs(e.items) do list[#list + 1] = {item, n} end
        table.sort(list, function(x, yy) return x[2] > yy[2] end)
        for i = 1, math.min(#list, 15) do
            local nm = list[i][1]
            if #nm > 18 then nm = nm:sub(1, 17) .. '.' end
            add(('%-18s %s%4d%s %5.1f%%'):format(nm, C.good, list[i][2], C.r, list[i][2] / e.digs * 100))
        end
        if #list > 15 then add(C.dim .. ('+%d more: //bup zone'):format(#list - 15) .. C.r) end
    else
        add(C.dim .. 'No digs here yet at this rank.' .. C.r)
    end
    y = y + 6
    add(C.dim .. '//bup export to share' .. C.r)

    for i, l in ipairs(out) do
        local t = zw_pool[i]
        if not t then t = mk_text(10); zw_pool[i] = t end
        t:text(l[1])
        zw_ry[i] = l[2]
        t:show()
    end
    for i = #out + 1, #zw_pool do zw_pool[i]:hide() end
    zw_used = #out

    local widest = text_width(zwin.title, title, 8.3)
    for i, l in ipairs(out) do widest = math.max(widest, text_width(zw_pool[i], l[1], 7.5)) end
    zw_w = math.max(ZW_MIN, math.ceil(widest) + 22)
    zwin.header:size(zw_w, 26)
    zwin.bg:size(zw_w, y + 6)
    layout()
end

local function state_text()
    if not S.running then return C.dim .. 'IDLE' .. C.r end
    if S.paused then return C.warn .. 'PAUSED' .. C.r end
    if moving then return C.acc .. 'MOVING' .. C.r end
    return C.good .. 'DIGGING' .. C.r
end

local function row(label, value)
    -- labels padded to 12 so the values sit a few spaces clear of them
    return C.dim .. ('%-12s'):format(label) .. C.r .. C.val .. value .. C.r
end

local function update_hud(now)
    if not hud_on then return end

    roll_day()

    -- buttons: the one that does something right now is bright, the other dimmed
    hud.b_start:color(S.running and not S.paused and 30 or 46, S.running and not S.paused and 60 or 120, S.running and not S.paused and 42 or 76)
    hud.b_stop:color(S.running and 140 or 60, S.running and 55 or 40, S.running and 55 or 44)
    local start_text = (S.running and S.paused) and 'RESUME' or 'START'
    if buttons.start.text ~= start_text then
        buttons.start.text = start_text
        hud.l_start:text(start_text)
        layout()
    end

    -- fatigue bar (daily fatigue-counting digs vs cap)
    local cap = settings.fatigue_cap
    local ffrac = cap > 0 and math.min(1, life.fatigue / cap) or 0
    if ffrac > 0 then
        hud.bar:size(math.max(2, math.floor((W - 20) * ffrac)), 10)
        if ffrac >= 0.9 then hud.bar:color(255, 110, 110)
        elseif ffrac >= 0.7 then hud.bar:color(255, 200, 90)
        else hud.bar:color(110, 220, 150) end
        hud.bar:show()
    else
        hud.bar:hide()
    end

    local f_col = ffrac >= 0.9 and C.bad or (ffrac >= 0.7 and C.warn or C.good)
    title_str = ('%sBIRDUP%s  %sFATIGUE%s %s%d / %s%s'):format(
        C.acc, C.r, C.dim, C.r, f_col, life.fatigue, cap > 0 and tostring(cap) or '∞', C.r)
    hud.title:text(title_str)

    -- stats
    local rate = S.attempts > 0 and (S.successes / S.attempts * 100) or 0
    local elapsed = S.first_dig and (os.time() - S.first_dig) or 0
    local per_hr = elapsed > 30 and (S.successes / elapsed * 3600) or 0
    local g_col = (greens and greens < 10) and C.bad or C.val
    local inv_text = C.dim .. '?' .. C.r
    if inv_used and inv_max then
        local free = inv_max - inv_used
        local ic = free <= settings.min_free_slots and C.bad or (free <= 8 and C.warn or C.val)
        inv_text = ('%s%d / %d%s  %s(%d free)%s'):format(ic, inv_used, inv_max, C.r, C.dim, free, C.r)
    end
    local pos = get_pos()
    local d = (pos and last_dig_pos) and dist2d(pos, last_dig_pos) or 0
    local countdown = S.running and math.max(0, math.ceil(next_dig - now)) or 0

    -- early warnings: low greens / inventory almost full -> flash the header
    local warns = {}
    local low_greens = settings.warn_greens > 0 and greens and greens > 0 and greens <= settings.warn_greens
    local free_slots = (inv_used and inv_max) and (inv_max - inv_used) or nil
    local low_slots = settings.warn_slots > 0 and free_slots and free_slots <= settings.warn_slots
    if low_greens then warns[#warns + 1] = ('LOW GREENS (%d)'):format(greens) end
    if low_slots then warns[#warns + 1] = ('BAGS %d FREE'):format(free_slots) end
    if #warns > 0 and math.floor(now * 2) % 2 == 0 then
        hud.header:color(150, 70, 30)   -- flash: amber-red
    else
        hud.header:color(38, 52, 84)    -- normal
    end
    -- one chat line when a warning first appears
    if low_greens and not warned.greens then
        warned.greens = true
        log(('Low on Gysahl Greens: %d left.'):format(greens))
    elseif not low_greens then warned.greens = false end
    if low_slots and not warned.slots then
        warned.slots = true
        log(('Inventory almost full: %d free slot%s.'):format(free_slots, free_slots == 1 and '' or 's'))
    elseif not low_slots then warned.slots = false end

    -- time left to use up today's fatigue at today's pace
    local td0 = today()
    local eta = ''
    if cap > 0 and life.fatigue < cap and td0.fatigue >= 3 and td0.secs >= 60 then
        local per_sec = td0.fatigue / td0.secs
        eta = '  ~' .. fmt_short((cap - life.fatigue) / per_sec)
    end

    -- area delay after zoning
    local zw = zone_wait_left()

    local rows = {
        row('State', state_text() .. ((S.running and anchor and settings.roam_radius > 0 and pos)
            and (C.dim .. ('  %d/%dy from centre'):format(math.floor(dist2d(pos, anchor)), math.floor(settings.roam_radius)) .. C.r) or '')),
        row('Fatigue', f_col .. life.fatigue .. C.r .. C.dim .. (cap > 0 and (' / ' .. cap .. '  (' .. math.max(0, cap - life.fatigue) .. ' left' .. eta .. ')') or '') .. C.r),
        row('Free digs', C.good .. life.free .. C.r .. C.dim .. (' (' .. ((life.fatigue + life.free) > 0 and math.floor(life.free / (life.fatigue + life.free) * 100) or 0) .. '% today)') .. C.r),
        row('Attempts', ('%d  %s(%d hit / %d miss)%s'):format(S.attempts, C.dim, S.successes, S.fails, C.r)),
        row('Discern', ('%d  %s(%d today, %s lifetime)%s'):format(S.discern, C.dim,
            today().discern or 0, commas(life.discern), C.r)),
        row('Hit rate', ('%.1f%%'):format(rate)),
        row('Greens', g_col .. (greens and tostring(greens) or '?') .. C.r),
        row('Inventory', inv_text),
        row('Next dig', (S.running and zw > 0) and (C.warn .. ('zone wait %ds'):format(math.ceil(zw)) .. C.r)
            or (S.running and (countdown .. 's') or '-')) ..
            '  ' .. C.dim .. ('%.1f/%.1fy'):format(d, settings.required_distance) .. C.r,
        row('Session', fmt_time(elapsed) .. '  ' .. C.dim .. ('%d/hr'):format(math.floor(per_hr + 0.5)) .. C.r),
        row('Lifetime', commas(life.successes) .. C.dim .. ' finds' .. C.r),
    }

    if #warns > 0 then
        table.insert(rows, 1, row('Warning', C.bad .. table.concat(warns, '  ') .. C.r))
    end

    -- Wing Skill and the dig cooldown that goes with it
    local wr = wing_rank(life.wing)
    if wr then
        table.insert(rows, 2, row('Wing', ('%s%d %s  %s%ds cooldown%s'):format(
            life.wing_approx and '~' or '', life.wing, wr[1], C.dim, wr[4], C.r)))
    else
        table.insert(rows, 2, row('Wing', C.dim .. '? (//bup wing <level>)' .. C.r))
    end

    -- Hyper Chocobo Digging Campaign status (only shown when it matters)
    if S.hyper then
        table.insert(rows, 3, row('Hyper', C.good .. 'ACTIVE' .. C.r .. C.dim .. (' (%ds cooldown)'):format(HYPER_DELAY) .. C.r))
    elseif hyper_test and S.running then
        table.insert(rows, 3, row('Hyper', C.warn .. 'testing...' .. C.r))
    end

    -- today's totals (every session since midnight JST)
    local td = today()
    table.insert(rows, #rows, row('Today', ('%d finds  %s(%d digs, %d session%s)%s'):format(
        td.finds, C.dim, td.attempts, td.sessions, td.sessions == 1 and '' or 's', C.r)))

    rows[#rows + 1] = row('Sold', C.good .. commas(life.gil) .. C.r .. C.dim .. ' gil (+' .. commas(td.gil) .. ' today)' .. C.r)
    rows[#rows + 1] = row('Est. val', commas(value_of(life.drops)) .. C.dim .. ' gil (+' .. commas(value_of(td.drops)) .. ' today)' .. C.r)

    local function cur_row(label, key)
        return row(label, C.good .. commas(life.cur[key] or 0) .. C.r ..
            C.dim .. ' (+' .. commas(td.cur[key] or 0) .. ' today)' .. C.r)
    end
    rows[#rows + 1] = cur_row('Conquest', 'cp')
    if (life.cur.imperial or 0) > 0 then rows[#rows + 1] = cur_row('Imperial', 'imperial') end
    if (life.cur.allied or 0) > 0 then rows[#rows + 1] = cur_row('Allied', 'allied') end
    if (life.cur.bayld or 0) > 0 then rows[#rows + 1] = cur_row('Bayld', 'bayld') end
    local sp = math.max(10, settings.line_spacing)
    local out = {}
    for i, r in ipairs(rows) do out[#out + 1] = {r, ROWS_Y + (i - 1) * sp} end
    local fy = ROWS_Y + #rows * sp + 8 -- items list starts below however many rows there are

    -- every item found (session or lifetime), most common first
    -- "today" comes from the saved daily history, so it survives reloads and
    -- only clears when the JST day rolls over
    local source = settings.finds_view == 'lifetime' and life.drops or td.drops
    local list = {}
    for name, n in pairs(source) do list[#list + 1] = {name, n} end
    table.sort(list, function(a, b)
        if a[2] ~= b[2] then return a[2] > b[2] end
        return a[1] < b[1]
    end)
    local lines = {('%sITEMS FOUND%s %s(%s, %d types)%s'):format(
        C.acc, C.r, C.dim, settings.finds_view == 'lifetime' and 'lifetime' or 'today', #list, C.r)}
    if #list == 0 then
        lines[#lines + 1] = C.dim .. 'Nothing yet' .. C.r
    else
        for _, e in ipairs(list) do
            local pr = prices[e[1]]
            lines[#lines + 1] = ('%s%-17s%s %s%4d%s %s%8s%s'):format(
                C.val, e[1]:sub(1, 17), C.r, C.good, e[2], C.r,
                C.dim, pr and ('@' .. short_price(pr)) or '', C.r)
        end
    end
    for j, l in ipairs(lines) do out[#out + 1] = {l, fy + (j - 1) * sp} end
    draw_lines(out)

    -- size the box to the longest line (Consolas 10 is ~7.5 px a character, 11 is ~8.3)
    local widest = text_width(hud.title, title_str, 8.3) + ZBTN_W + 12 -- room for the ZONES button
    for i, l in ipairs(out) do
        widest = math.max(widest, text_width(lines_pool[i], l[1], 7.5))
    end
    set_width(math.max(W_MIN, math.ceil(widest) + 22))

    panel_h = fy + #lines * sp + 8
    hud.bg:size(W, panel_h) -- panel grows with the list

    -- ZONES button looks pressed while the window is open
    if settings.zone_window then hud.b_zones:color(80, 120, 170) else hud.b_zones:color(60, 75, 110) end
    draw_zone_window(sp)
end

---------------------------------------------------------------------------
-- Movement
---------------------------------------------------------------------------
local function stop_moving()
    if moving then windower.ffxi.run(false) end
    moving, move_start_time, move_start_pos = false, 0, nil
    prog_time, prog_pos = 0, nil
    turn_until = 0
end

local function turn_by(rad)
    local me = get_me()
    if me and me.facing then
        windower.ffxi.turn((me.facing + rad) % (2 * math.pi))
    end
end

local move_target = 0 -- yalms this move should cover
local need_spin = false -- spin to a new heading before the next move

-- FFXI facing: moving at facing f changes x by cos(f) and y by -sin(f)
local function heading_to(from, to)
    return -math.atan2(to.y - from.y, to.x - from.x)
end

-- New heading after a dig: random, unless the next spot would leave the area,
-- in which case head back toward the centre (give or take 45 degrees).
-- returns a heading, or nil to keep going the way you're facing
local function roam_heading(pos)
    local r = settings.roam_radius
    local function rnd() return math.random() * 2 * math.pi end
    local step = settings.required_distance + 1
    local function fits(f)
        if not anchor or r <= 0 then return true end
        local nx, ny = pos.x + math.cos(f) * step, pos.y - math.sin(f) * step
        return dist2d({x = nx, y = ny}, anchor) <= r
    end
    -- turn_chance % of the time pick a new heading; otherwise carry on,
    -- unless carrying on would leave the area
    local me = get_me()
    if me and me.facing and math.random() * 100 >= settings.turn_chance and fits(me.facing) then
        return nil
    end
    if not anchor or r <= 0 then return rnd() end
    for _ = 1, 8 do -- try a few random headings that keep the next spot inside
        local f = rnd()
        local nx, ny = pos.x + math.cos(f) * step, pos.y - math.sin(f) * step
        if dist2d({x = nx, y = ny}, anchor) <= r then return f end
    end
    return heading_to(pos, anchor) + (math.random() * 2 - 1) * math.pi / 4
end

-- mode: false/nil = keep heading, true = stuck (turn 90-180 degrees),
-- 'reverse' = rough 180 (plus or minus 30 degrees) away from undiggable ground
local function start_moving(mode, dist)
    local pos = get_pos()
    if not pos then return end
    if mode == 'away' then -- turn away from a wall: 120-240 degrees
        turn_by(math.pi + (math.random() * 2 - 1) * math.pi / 3)
        turn_until = os.clock() + 0.4
    elseif mode == 'roam' then
        local f = roam_heading(pos)
        if f then
            windower.ffxi.turn(f % (2 * math.pi))
            turn_until = os.clock() + 0.4 -- finish turning before running
        end
    elseif mode == 'reverse' then
        turn_by(math.pi + (math.random() * 2 - 1) * math.pi / 6)
    elseif mode then
        local sign = math.random() < 0.5 and -1 or 1
        turn_by(sign * (math.pi / 2 + math.random() * math.pi / 2))
    end
    move_target = dist or settings.required_distance
    move_start_pos, move_start_time = pos, os.clock()
    prog_pos, prog_time = pos, os.clock()
    moving = true
    if os.clock() >= turn_until then windower.ffxi.run(true) end
end

local retry_here = false   -- after turning off bad ground: dig again without the full distance
local blocked_count = 0    -- wall hits since the last good move
local wall_hit = false     -- last stop was a wall: turn away after the next dig
local prev_dig_pos = nil   -- where the last real dig happened (restored after bad ground)
local auto_wait = nil      -- os.clock() of our own /dig, until the game answers
local bad_ground_log = 0

local function can_dig_here()
    if retry_here or not last_dig_pos then return true end
    local pos = get_pos()
    return pos and dist2d(pos, last_dig_pos) >= settings.required_distance
end

local function stop_addon(reason)
    S.running, S.paused = false, false
    auto_wait, retry_here = nil, false
    stop_moving()
    save_life(true)
    log(('Stopped%s Finds this session: %d'):format(reason and (': ' .. reason) or '.', S.successes))
end

local function start_addon()
    if S.running and S.paused then
        S.paused = false
        log('Resumed.')
        return
    end
    if S.running then return end
    roll_day()
    S.running, S.paused, next_dig = true, false, 0
    anchor, need_spin = get_pos(), false -- stay around where you started
    bad_streak, blocked_count, wall_hit = 0, 0, false
    local wd = wing_delay()
    hyper_test = nil
    if hyper_mode == 'on' then S.hyper = true
    elseif hyper_mode == 'off' then S.hyper = false
    else
        S.hyper = nil
        if (wd or 15) > HYPER_DELAY then hyper_test = 'need_base' end -- campaign would speed us up: test it
    end
    log('Started. Be mounted on your chocobo.' ..
        (wd and (' Wing Skill cooldown %ds.'):format(wd)
            or ' Wing Skill unknown, so using the slowest cooldown (15s). Set it with //bup wing <level>.') ..
        (hyper_test and ' Checking for a Hyper Chocobo Digging Campaign on the second dig.' or '') ..
        (S.hyper and ' Hyper Campaign set on.' or ''))
    local zw = zone_wait_left()
    if zw > 0 then
        log(('Just zoned: waiting %ds before the first dig (area delay for your Wing rank). If a Hyper Campaign is on, //bup hyper on.'):format(math.ceil(zw)))
    end
end

-- The ground here can't be dug (the game refused, or never answered):
-- turn roughly around, go a short way, and dig again there.
local last_ok_t = 0 -- os.clock() when the last dig that got a result was sent
local bad_streak = 0 -- "can't dig here" in a row, reset by any real dig result

-- the test dig at campaign speed got no answer: no campaign. Dig again here
-- once the normal cooldown since the last real dig has passed.
local function hyper_failed()
    S.hyper, hyper_test = false, nil
    auto_wait = nil
    last_dig_pos = prev_dig_pos
    retry_here = true
    next_dig = last_ok_t + math.max(settings.dig_interval, dig_delay() + 0.5)
    log(('No Hyper Chocobo Digging Campaign detected. Digging every %ds.'):format(dig_delay()))
end

local gave_up_spot = nil -- where we gave up waiting; used if the result turns up late

local function bad_ground(why)
    if hyper_test == 'probing' then hyper_failed() return end
    -- stop waiting, but keep S.pending: a result that turns up late
    -- (within 12s of the dig) is still recorded
    auto_wait = nil
    gave_up_spot = last_dig_pos
    bad_streak = bad_streak + 1
    if settings.bad_ground_limit > 0 and bad_streak >= settings.bad_ground_limit then
        local n = bad_streak
        bad_streak = 0
        stop_addon(('couldn\'t dig %d times in a row. Move somewhere else and press START.'):format(n))
        -- loud alert only you see/hear: a chat call sound plus an echo line
        windower.send_command('input /echo [BirdUp] Auto-dig stopped: ' .. n .. ' failed digs in a row. <call14>')
        if settings.stop_echo and settings.stop_echo ~= '' then
            windower.send_command('input /echo ' .. settings.stop_echo)
        end
        return
    end
    last_dig_pos = prev_dig_pos -- that spot wasn't a real dig
    retry_here = true
    do
        log(('Can\'t dig here (%s). Turning around and trying a few yalms away. (%d/%d)'):format(
            why, bad_streak, settings.bad_ground_limit))
    end
    start_moving('reverse', settings.turn_distance)
end

local function attempt_dig()
    stop_moving()
    prev_dig_pos, last_dig_pos = last_dig_pos, get_pos()
    retry_here = false
    need_spin = true
    gave_up_spot = nil
    auto_wait = os.clock()
    if hyper_test == 'probe_next' then hyper_test = 'probing' end
    -- never faster than the cooldown (Wing Skill, or the campaign's), plus a little slack
    local wd = dig_delay()
    local wait = math.max(settings.dig_interval, wd + 0.5) + (math.random() * 2 - 1) * settings.jitter
    next_dig = os.clock() + math.max(wd + 0.3, wait)
    windower.send_command('input /dig')
end

---------------------------------------------------------------------------
-- Result tracking
---------------------------------------------------------------------------
local last_find = nil -- {t = os.clock(), free = bool}: the most recent successful dig

local function add_currency(cur)
    if not cur then return end
    life.cur[cur[1]] = (life.cur[cur[1]] or 0) + cur[2]
    S.cur[cur[1]] = (S.cur[cur[1]] or 0) + cur[2]
    local td = today()
    td.cur[cur[1]] = (td.cur[cur[1]] or 0) + cur[2]
    life_dirty = true
end

local function add_item(item, cur)
    register_dug(item)
    S.drops[item] = (S.drops[item] or 0) + 1
    life.drops[item] = (life.drops[item] or 0) + 1
    local td = today()
    td.drops[item] = (td.drops[item] or 0) + 1
    add_currency(cur)
    life_dirty = true
end

-- one real dig: the game answered with an item, a reward, or "find nothing"
local function count_dig()
    S.attempts = S.attempts + 1
    life.attempts = life.attempts + 1
    local td, now_t = today(), os.time()
    td.attempts = td.attempts + 1
    -- digging time: count the gap since the last dig unless it was a long break
    if S.last_dig_t and now_t - S.last_dig_t < 120 then td.secs = td.secs + (now_t - S.last_dig_t) end
    if not S.first_dig then td.sessions = td.sessions + 1 end -- first dig of this session
    S.last_dig_t = now_t
    S.first_dig = S.first_dig or now_t
end

-- the game answered our dig: update the campaign test
local function dig_answered()
    if auto_wait then
        last_ok_t = auto_wait
    elseif gave_up_spot then
        -- late result for a dig we'd given up on: it was a real dig after all
        log('That dig worked after all (the result was slow). Recorded it.')
        last_dig_pos, retry_here = gave_up_spot, false
        last_ok_t = S.pending or os.clock()
    end
    gave_up_spot = nil
    bad_streak = 0
    blocked_count = 0
    settle_until = os.clock() + settings.dig_settle -- let the dig finish
    S.pending, auto_wait = nil, nil
    if hyper_test == 'need_base' then
        hyper_test = 'probe_next' -- try the next dig at campaign speed
        next_dig = last_ok_t + math.max(settings.dig_interval, HYPER_DELAY + 0.5)
    elseif hyper_test == 'probing' then
        S.hyper, hyper_test = true, nil
        next_dig = last_ok_t + math.max(settings.dig_interval, HYPER_DELAY + 0.5)
        log(('Hyper Chocobo Digging Campaign detected! Digging every %ds instead of %ds.'):format(
            dig_delay(), wing_delay() or 15))
    end
end

-- Discernment: the chocobo refused the greens but still digs. The game prints
--   "Your chocobo refuses to partake of the bunch of gysahl greens."
--   "Obtained: <item>"
--   "It appears your chocobo found this item with ease."
-- so this only counts the proc; the Obtained line that follows is the dig's result.
local function record_discern()
    roll_day()
    local z = zone_entry()
    if z then z.discern = z.discern + 1 end
    dbg('RESULT', 'discernment proc')
    S.discern = S.discern + 1
    life.discern = life.discern + 1
    local td = today()
    td.discern = (td.discern or 0) + 1
    life_dirty = true
    save_life(false)
end

local function record(item, cur)
    roll_day()
    dig_answered()
    count_dig()
    local z = zone_entry()
    if z then
        z.digs = z.digs + 1
        if item then
            z.finds = z.finds + 1
            z.items[item] = (z.items[item] or 0) + 1
        else
            z.miss = z.miss + 1
        end
    end
    dbg('RESULT', item and ('find: ' .. item) or 'miss')
    if item then
        S.successes = S.successes + 1
        life.successes = life.successes + 1
        life.fatigue = life.fatigue + 1      -- assume it counts until told otherwise
        local td = today()
        td.finds, td.fatigue = td.finds + 1, td.fatigue + 1
        add_item(item, cur)
        last_find = {t = os.clock(), free = false}
    else
        S.fails = S.fails + 1
        local td = today()
        td.fails = td.fails + 1
    end
    life_dirty = true
    save_life(false)
    if S.running and settings.max_success > 0 and S.successes >= settings.max_success then
        stop_addon(('reached %d finds.'):format(settings.max_success))
    end
end

-- The game prints "It appears your chocobo found this item with ease." on the
-- line AFTER the item line when a dig is free, so we undo the fatigue we just added.
local function mark_free()
    if not last_find or last_find.free or os.clock() - last_find.t > 3 then return end
    roll_day()
    last_find.free = true
    life.fatigue = math.max(0, life.fatigue - 1)
    life.free = life.free + 1
    S.free = S.free + 1
    local td = today()
    td.fatigue, td.free = math.max(0, td.fatigue - 1), td.free + 1
    life_dirty = true
end

windower.register_event('outgoing text', function(original)
    if original and original:lower():match('^/dig') then
        dbg('OUT', original)
        -- only remember that a dig was asked for; it's counted once the game
        -- answers with a result (spammed or rejected /digs don't count)
        S.pending = os.clock()
    end
end)

local STOP_PATTERNS = { -- best-effort; verify wording on your server and extend as needed
    'you do not have any gysahl', "you don't have any gysahl",
    'cannot carry any more', 'inventory is full',
}

-- ground that can't be dug: turn around instead of stopping
-- (best guesses at the wording; if no result arrives at all, that counts too)
local BAD_GROUND_PATTERNS = {
    'unable to dig', 'cannot dig here', "can't dig here", 'you cannot dig',
    'cannot use that command', "can't use that command", 'cannot use the command',
}

windower.register_event('incoming text', function(original, modified, mode)
    if not original then return end
    -- debug: every line while auto-digging, or within 20s of a dig
    if debug_f and (S.running or (S.pending and os.clock() - S.pending < 20)) then
        dbg('IN', ('[mode %s] %s'):format(tostring(mode), original))
    end
    local clean = original:gsub(string.char(0x1E) .. '.', ''):gsub(string.char(0x1F) .. '.', '')
                          :gsub(string.char(0x7F) .. '.', '')
    local lower = clean:lower()
    if clean:find('[BirdUp]', 1, true) then return end -- our own chat lines

    -- Wing Skill. Confirmed in game: "Your wing skill improved to 15!"
    -- Other wordings are matched loosely in case NPCs phrase it differently:
    --   "...reaches level 31", "...rises to 31", "...is 31", "...rises 1 point", rank names
    if lower:find('wing skill', 1, true) then
        local lvl = lower:match('wing skill improved to (%d+)')
                 or lower:match('wing skill reaches level (%d+)') or lower:match('wing skill rises to (%d+)')
                 or lower:match('wing skill is (%d+)') or lower:match('wing skill.-level (%d+)')
                 or lower:match('wing skill.- to (%d+)')
        local gain = lower:match('wing skill rises (%d+) point')
        if lvl then
            set_wing(tonumber(lvl))
        elseif gain and life.wing then
            set_wing(life.wing + tonumber(gain), life.wing_approx)
        elseif gain then
            log('Wing Skill went up, but the current level is unknown. Set it with //bup wing <level>.')
        else
            for i = #WING_RANKS, 1, -1 do -- a rank name with no number: use the rank's lowest level
                local w = WING_RANKS[i]
                if lower:find(w[1]:lower(), 1, true) then
                    if not life.wing or wing_rank(life.wing)[1] ~= w[1] then set_wing(w[2], true) end
                    break
                end
            end
        end
    end

    if S.running and auto_wait then
        for _, p in ipairs(BAD_GROUND_PATTERNS) do
            if lower:find(p, 1, true) then bad_ground('game said no') return end -- (a refused test dig = no campaign)
        end
    end

    if S.running then
        for _, p in ipairs(STOP_PATTERNS) do
            if lower:find(p, 1, true) then stop_addon(clean) return end
        end
    end

    if lower:find('found this item with ease', 1, true) then
        mark_free()
        return
    end

    local pending_ok = S.pending and os.clock() - S.pending <= 12

    -- Discernment proc (counted whenever seen; the item line comes next)
    if lower:find('refuses to partake of the', 1, true) then
        record_discern()
        return
    end

    if lower:find('you dig and you dig', 1, true) and lower:find('find nothing', 1, true) then
        if pending_ok then record(nil) end
        return
    end

    -- Reward wording (BG-Wiki / FFXIAH DigTracker thread):
    --   "...cache of beastman resources and receive N conquest points!"
    --   "...cache of beastman resources and receive N Imperial Standing!"
    --   "...cache of beastman confederate resources and receive N allied notes!"
    --   "You receive N bayld!"
    local found, cur
    local function amt(pat)
        local n = lower:match(pat)
        return n and tonumber((n:gsub(',', ''))) or nil
    end
    local n
    if amt('cache of beastman resources and receive ([%d,]+) conquest points') then
        n = amt('cache of beastman resources and receive ([%d,]+) conquest points')
        found, cur = 'Conquest Points', {'cp', n}
    elseif amt('cache of beastman resources and receive ([%d,]+) imperial standing') then
        n = amt('cache of beastman resources and receive ([%d,]+) imperial standing')
        found, cur = 'Imperial Standing', {'imperial', n}
    elseif amt('cache of beastman confederate resources and receive ([%d,]+) allied notes') then
        n = amt('cache of beastman confederate resources and receive ([%d,]+) allied notes')
        found, cur = 'Allied Notes', {'allied', n}
    elseif amt('^you receive ([%d,]+) bayld') then
        n = amt('^you receive ([%d,]+) bayld')
        found, cur = 'Bayld', {'bayld', n}
    elseif lower:find('discover a cache of beastman', 1, true) then
        found = 'Beastman Cache' -- amount not recognized
    else
        found = clean_name(clean:match('^Obtained: (.-)%s*$'))
    end
    if not found then return end

    -- a dig gives at most one item, so only the result of a pending dig counts
    if pending_ok then record(found, cur) end
end)

---------------------------------------------------------------------------
-- Sale detection: NPC vendors only, dug-up items only
-- Selling to a vendor sends two packets: 0x084 (which item, how many) when
-- you pick the item, then 0x085 when you confirm. After the confirm we wait
-- for the gil to arrive; gil gained / quantity is saved as the item's price.
-- Items you haven't dug up are ignored, so they never reach prices.txt.
-- Bazaar, trades and auction house sales are ignored too.
---------------------------------------------------------------------------
local sell_req = nil     -- {id, count, t}: item picked at the vendor
local sale_pending = nil -- {name, count, gil0, t}: confirmed, waiting for gil
local sale_check_t = 0

local function u16(data, i) return data:byte(i) + data:byte(i + 1) * 256 end
local function u32(data, i) return u16(data, i) + u16(data, i + 2) * 65536 end

local function record_sale(name, qty, gil)
    if qty <= 0 or gil <= 0 then return end
    local unit = math.floor(gil / qty + 0.5)
    local old = prices[name]
    if old ~= unit then -- same price as before: nothing to update
        prices[name] = unit
        save_prices()
    end
    life.gil = life.gil + gil
    S.gil = S.gil + gil
    local td = today()
    td.gil = td.gil + gil
    life_dirty = true
    save_life(true)
    -- echo only when the price list changes; a sale at the known price is silent
    if not old then
        log(('Price history: %s added at %s gil each (sold %d for %s gil).'):format(
            name, commas(unit), qty, commas(gil)))
    elseif old ~= unit then
        log(('Price history: %s updated %s -> %s gil each (sold %d for %s gil).'):format(
            name, commas(old), commas(unit), qty, commas(gil)))
    end
end

windower.register_event('outgoing chunk', function(id, data)
    -- 0x01A action packet, category 0x11 = chocobo dig. Sent for typed /dig
    -- AND for Dig picked from the menu, so menu digs are tracked too.
    if id == 0x01A and #data >= 12 and u16(data, 11) == 0x11 then
        dbg('PKT', 'dig action sent')
        S.pending = os.clock()
        return
    end
    if id == 0x084 and #data >= 11 then        -- vendor: item picked to sell
        sell_req = {count = u32(data, 5), id = u16(data, 9), t = os.clock()}
    elseif id == 0x085 and sell_req then        -- vendor: sale confirmed
        local name = dug_by_id[sell_req.id]
        if name and os.clock() - sell_req.t < 120 then
            local gil = windower.ffxi.get_items('gil')
            if type(gil) == 'number' then
                sale_pending = {name = name, count = math.max(1, sell_req.count), gil0 = gil, t = os.clock()}
            end
        end
        sell_req = nil
    end
end)

local function check_sales(now)
    if not sale_pending or now - sale_check_t < 0.2 then return end
    sale_check_t = now
    local gil = windower.ffxi.get_items('gil')
    if type(gil) == 'number' and gil > sale_pending.gil0 then
        record_sale(sale_pending.name, sale_pending.count, gil - sale_pending.gil0)
        sale_pending = nil
    elseif now - sale_pending.t > 5 then
        sale_pending = nil -- gil never arrived (sale cancelled or refused)
    end
end

---------------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------------
local function tick(now)
    roll_day() -- the fatigue check below must see today's count, not yesterday's
    if greens and greens <= 0 then stop_addon('out of Gysahl Greens.') return end

    if settings.min_free_slots > 0 and inv_used and inv_max
       and (inv_max - inv_used) <= settings.min_free_slots then
        stop_addon(('inventory nearly full (%d free).'):format(inv_max - inv_used))
        return
    end

    if settings.stop_at_fatigue and settings.fatigue_cap > 0 and life.fatigue >= settings.fatigue_cap
       and (not last_find or now - last_find.t > 3) then -- wait out a pending "with ease" line
        stop_addon(('daily fatigue cap reached (%d).'):format(settings.fatigue_cap))
        return
    end

    if settings.require_mount then
        if windower.ffxi.get_player() and not is_mounted() then stop_addon('not mounted.') return end
    end

    if moving and turn_until > 0 then
        if now < turn_until then return end
        turn_until = 0
        windower.ffxi.run(true) -- turned; now go
        move_start_time = now
        prog_pos, prog_time = get_pos(), now
    end

    if moving then
        local pos = get_pos()
        -- blocked (a wall, or sliding along one): dig right here, then turn
        -- away. If it's blocked again straight after, turn away without digging.
        local function blocked(why)
            stop_moving()
            blocked_count = blocked_count + 1
            dbg('MOVE', ('blocked (%s), count %d'):format(why, blocked_count))
            if blocked_count == 1 then
                retry_here, wall_hit = true, true -- dig where it stopped
            else
                wall_hit = false
                start_moving('away', settings.required_distance)
            end
        end
        local min_prog = math.max(settings.stuck_epsilon, settings.blocked_progress * settings.stuck_check_time)
        if pos and move_start_pos and dist2d(pos, move_start_pos) >= move_target then
            stop_moving()
            blocked_count = 0
        elseif pos and prog_pos and now - prog_time >= settings.stuck_check_time then
            if dist2d(pos, prog_pos) < min_prog then
                blocked('no progress')
            else
                prog_time, prog_pos = now, pos
            end
        elseif now - move_start_time >= settings.move_timeout then
            blocked('took too long')
        end
        return
    end

    -- our /dig is out: wait for the game's answer before moving on
    if auto_wait then
        if now - auto_wait < settings.result_timeout then return end
        bad_ground('no result') -- nothing came back: treat the spot as undiggable
        return
    end

    -- let the dig animation finish before turning and moving off
    if now < settle_until then return end

    -- first move after each dig: spin to a new heading that stays in the area
    local function go()
        if need_spin then
            need_spin = false
            if wall_hit then wall_hit = false; start_moving('away') else start_moving('roam') end
        else
            start_moving(false)
        end
    end

    if now < next_dig then
        if not can_dig_here() then go() end
        return
    end

    if can_dig_here() then
        if zone_wait_left() > 0 then return end -- area delay after zoning
        attempt_dig()
    else
        go()
    end
end

local day_check = 0

windower.register_event('prerender', function()
    local now = os.clock()
    -- check for the JST day change on its own, even while the panel is hidden
    if now - day_check >= 5 then day_check = now; roll_day() end
    refresh_greens(now)
    check_sales(now)
    if S.running and not S.paused then tick(now) end
    if now - hud_last >= 0.2 then
        hud_last = now
        refresh_visibility()
        update_hud(now)
    end
end)

windower.register_event('zone change', function()
    zoned_at = os.clock()
    dbg('ZONE', zone_name(current_zone()))
    if S.running then stop_addon('zone change.') end
end)
windower.register_event('logout', function()
    if S.running then stop_addon('logout.') end
    save_life(true)
end)
windower.register_event('unload', function()
    stop_moving(); save_life(true); hud_show(false)
    if debug_f then dbg('END', 'addon unloaded'); debug_f:close(); debug_f = nil end
end)
---------------------------------------------------------------------------
-- Per-character support
-- Windower's config library keeps a separate settings section per character
-- and reloads it on login; //bup saveall copies the current values to every
-- character. Lifetime stats live in data/lifetime_<name>.txt.
---------------------------------------------------------------------------
local function apply_settings()
    px, py = settings.pos.x, settings.pos.y
    layout()
    refresh_visibility(true)
end

---------------------------------------------------------------------------
-- Mouse: drag the panel, click the START / STOP buttons
-- Mouse event types: 0 = move, 1 = left down, 2 = left up
---------------------------------------------------------------------------
local drag, pressed = nil, nil -- drag = {dx, dy}

local function inside(mx, my, x, y, w, h)
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

local function button_at(mx, my)
    if inside(mx, my, px + W - ZBTN_W - 6, py + 4, ZBTN_W, ZBTN_H) then return 'zones' end
    for key, b in pairs(buttons) do
        if inside(mx, my, px + b.rx, py + BTN_Y, BTN_W, BTN_H) then return key end
    end
end

windower.register_event('mouse', function(type, mx, my, delta, blocked)
    if not hud_on then drag, pressed = nil, nil return end
    if type == 0 then
        if drag then
            px, py = mx - drag.dx, my - drag.dy
            layout() -- everything moves together, in this same event
            return true
        end
    elseif type == 1 then
        if blocked or not inside(mx, my, px, py, W, panel_h) then return end
        pressed = button_at(mx, my)
        if not pressed then drag = {dx = mx - px, dy = my - py} end
        return true
    elseif type == 2 then
        if drag then
            drag = nil
            settings.pos.x, settings.pos.y = px, py
            config.save(settings)
            return true
        end
        if pressed then
            local key = pressed
            pressed = nil
            if button_at(mx, my) == key then -- released over the same button
                if key == 'zones' then
                    settings.zone_window = not settings.zone_window
                    config.save(settings)
                elseif key == 'start' then start_addon() else
                    if S.running then stop_addon(nil) else log('Auto-dig is not running.') end
                end
                hud_last = 0 -- redraw right away
            end
            return true
        end
    end
end)

local function switch_character()
    local p = windower.ffxi.get_player()
    local name = p and p.name or nil
    if not name or name == char_name then return end

    if S.running then stop_addon('character changed.') end
    save_life(true)                       -- flush previous character first

    char_name = name
    S.attempts, S.successes, S.fails, S.free, S.drops, S.first_dig, S.cur, S.gil = 0, 0, 0, 0, {}, nil, {}, 0
    S.discern = 0
    S.pending, S.last_dig_t, last_find = nil, nil, nil
    load_life()
    load_history()
    load_zone_stats()
    for name in pairs(all_dug_names()) do register_dug(name) end -- any character's digs
    roll_day()
    apply_settings()
    log(('Loaded profile for %s.'):format(char_name))
end

config.register(settings, function(new_settings)
    settings = new_settings or settings
    switch_character()
    apply_settings()
end)

windower.register_event('login', function()
    coroutine.schedule(switch_character, 3) -- player data isn't ready instantly
end)

windower.register_event('load', function()
    log(('Author: %s, Version %s'):format('Valdimar @ Phoenix', _addon.version))
    switch_character()
    if not char_name then refresh_visibility(true) end
end)

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
local function help()
    for _, l in ipairs({
        'start | stop | pause   - control auto-digging (tracker always runs)',
        'reset                  - reset session stats',
        'status                 - print summary to chat',
        'distance <yalms>       - distance required between digs',
        'turn <yalms>           - distance to move after turning off undiggable ground',
        'settle <seconds>       - wait after each dig before turning and moving (default 2.5)',
        'badlimit <n>           - stop and alert after n failed digs in a row (default 7, 0 = never)',
        'stopecho <text>        - extra line echoed with that alert (stopecho off = none)',
        'turnchance <0-100>     - % chance to turn after a dig instead of carrying on (default 50)',
        'area <yalms>           - stay within this distance of where auto-dig started (0 = no limit)',
        'anchor                 - make your current spot the centre of the digging area',
        'timer <seconds>        - base seconds between digs',
        'jitter <seconds>       - random +/- added to timer',
        'max <count>            - auto-stop after N finds (0 = off)',
        'cap <count>            - your daily fatigue cap (100 rental; up to ~200 raised)',
        'fatigue [n|reset]      - show / set / reset today\'s fatigue count',
        'stopfatigue on|off     - auto-stop when the cap is reached',
        'slots <n>              - auto-stop at n free inventory slots or fewer (0 = off)',
        'mount on|off           - require being mounted',
        'wing [level]           - show / set your Wing Skill (skill-ups in chat keep it updated)',
        'hyper on|off|test      - set or re-test the Hyper Chocobo Digging Campaign (tested on every start)',
        'history [days|date]    - daily dig log (e.g. history 14, history 20261101)',
        'prices clean           - remove prices for items no character has dug up',
        'zonewin [on|off]       - show/hide the zone stats window (or click ZONES)',
        'zone [all]             - drop stats for this zone (or every zone) at your Wing rank',
        'export                 - write all characters\' zone drop stats to a shareable report + CSV',
        'debug on|off           - log dig chat + BirdUp decisions to a new dated file',
        'warn <greens> <slots>  - flash the panel at this many greens / free slots (default 10 5)',
        'hud                    - show/hide the display',
        'reload                 - save everything and reload BirdUp',
        'autohide on|off        - only show the display while on a chocobo',
        'spacing <pixels>       - space from one display line to the next',
        'view today|lifetime    - which item totals the HUD list shows',
        'finds                  - print the full item list to chat',
        'currency               - lifetime/today conquest points, Imperial Standing, allied notes, bayld',
        'price <item> <gil>     - set an item\'s price by hand (0 clears)',
        'prices                 - list known prices and gil earned from sales',
        'profile                - show this character\'s saved settings',
        'saveall                - copy current settings to all characters',
        '(settings and lifetime stats are saved per character)',
    }) do log(l) end
end

local function set_num(key, arg, label)
    local n = tonumber(arg)
    if not n or n < 0 then log('Usage: //bup ' .. label .. ' <number>') return end
    settings[key] = n
    config.save(settings)
    log(('%s set to %s'):format(label, n))
end

windower.register_event('addon command', function(cmd, ...)
    cmd = cmd and cmd:lower() or 'help'
    local a = {...}

    if cmd == 'reload' then
        if S.running then stop_addon('reloading.') end
        save_life(true)          -- lifetime + today's history
        save_prices()
        config.save(settings)
        log('Reloading...')
        windower.send_command('lua reload ' .. _addon.name)
        return
    elseif cmd == 'start' then
        start_addon()
    elseif cmd == 'stop' then
        stop_addon(nil)
    elseif cmd == 'pause' then
        if not S.running then log('Not running.') return end
        S.paused = not S.paused
        stop_moving()
        auto_wait = nil
        if hyper_test == 'probing' then hyper_test = 'probe_next' end
        log(S.paused and 'Paused.' or 'Resumed.')
    elseif cmd == 'reset' then
        S.attempts, S.successes, S.fails, S.free, S.drops, S.first_dig, S.cur, S.gil = 0, 0, 0, 0, {}, nil, {}, 0
    S.discern = 0
        log('Session stats reset. (Today\'s items and daily fatigue are kept; they clear at midnight JST.)')
    elseif cmd == 'status' then
        log(('running=%s attempts=%d finds=%d misses=%d discern=%d hyper=%s greens=%s inventory=%s/%s'):format(
            tostring(S.running), S.attempts, S.successes, S.fails, S.discern, tostring(S.hyper), tostring(greens),
            tostring(inv_used), tostring(inv_max)))
    elseif cmd == 'distance' then set_num('required_distance', a[1], 'distance')
    elseif cmd == 'turn'     then set_num('turn_distance', a[1], 'turn')
    elseif cmd == 'settle'   then set_num('dig_settle', a[1], 'settle')
    elseif cmd == 'badlimit' then set_num('bad_ground_limit', a[1], 'badlimit')
    elseif cmd == 'warn' then
        local g, sl = tonumber(a[1] or ''), tonumber(a[2] or '')
        if g then settings.warn_greens = math.max(0, math.floor(g)) end
        if sl then settings.warn_slots = math.max(0, math.floor(sl)) end
        config.save(settings)
        log(('Panel warnings at %d greens and %d free slots (0 = off).'):format(settings.warn_greens, settings.warn_slots))
    elseif cmd == 'stopecho' then
        local text = table.concat(a, ' ')
        if text == '' then log('Alert echo: ' .. (settings.stop_echo ~= '' and settings.stop_echo or '(none)')) return end
        settings.stop_echo = text:lower() == 'off' and '' or text
        config.save(settings)
        log('Alert echo: ' .. (settings.stop_echo ~= '' and settings.stop_echo or '(none)'))
    elseif cmd == 'turnchance' then
        local n = tonumber(a[1])
        if not n or n < 0 or n > 100 then log('Usage: //bup turnchance <0-100>') return end
        settings.turn_chance = n
        config.save(settings)
        log(('Turn chance after each dig: %d%%.'):format(n))
    elseif cmd == 'area'     then set_num('roam_radius', a[1], 'area')
    elseif cmd == 'anchor' then
        anchor = get_pos()
        log(anchor and ('Digging area centred here (%d yalm radius).'):format(settings.roam_radius) or 'Position unknown.')
    elseif cmd == 'timer'    then set_num('dig_interval', a[1], 'timer')
    elseif cmd == 'jitter'   then set_num('jitter', a[1], 'jitter')
    elseif cmd == 'max'      then set_num('max_success', a[1], 'max')
    elseif cmd == 'cap'      then set_num('fatigue_cap', a[1], 'cap')
    elseif cmd == 'slots'    then set_num('min_free_slots', a[1], 'slots')
    elseif cmd == 'mount' then
        settings.require_mount = (a[1] or ''):lower() ~= 'off'
        config.save(settings)
        log('Require mount: ' .. tostring(settings.require_mount))
    elseif cmd == 'hud' then
        settings.hud_visible = not settings.hud_visible
        config.save(settings)
        refresh_visibility(true)
        log('Display ' .. (settings.hud_visible and ('on' .. (settings.auto_hide and ' (shows while on a chocobo)' or '')) or 'off') .. '.')
    elseif cmd == 'autohide' then
        settings.auto_hide = (a[1] or ''):lower() ~= 'off'
        config.save(settings)
        refresh_visibility(true)
        log('Auto-hide: ' .. (settings.auto_hide and 'on (display shows only while on a chocobo)' or 'off (display always shown)'))
    elseif cmd == 'spacing' then
        set_num('line_spacing', a[1], 'spacing')
    elseif cmd == 'fatigue' then
        roll_day()
        if a[1] and a[1]:lower() == 'reset' then
            life.fatigue, life.free, life_dirty = 0, 0, true
            local td = today()
            td.fatigue, td.free = 0, 0
            save_life(true)
            log('Daily fatigue and free-dig counters reset.')
        elseif a[1] and tonumber(a[1]) then
            life.fatigue, life_dirty = math.max(0, math.floor(tonumber(a[1]))), true
            today().fatigue = life.fatigue
            save_life(true)
            log(('Daily fatigue set to %d.'):format(life.fatigue))
        else
            log(('Fatigue today: %d / %d (%d free digs). Resets at midnight JST.'):format(
                life.fatigue, settings.fatigue_cap, life.free))
        end
    elseif cmd == 'stopfatigue' then
        settings.stop_at_fatigue = (a[1] or ''):lower() ~= 'off'
        config.save(settings)
        log('Auto-stop at fatigue cap: ' .. tostring(settings.stop_at_fatigue))
    elseif cmd == 'price' then
        local n = tonumber(a[#a])
        if #a < 2 or not n or n < 0 then log('Usage: //bup price <item name> <gil each>  (0 clears it)') return end
        local id = item_id_for(table.concat(a, ' ', 1, #a - 1))
        local canon = id and res.items[id] and res.items[id].en
        if not canon then log('Unknown item name.') return end
        local old = prices[canon]
        prices[canon] = n > 0 and math.floor(n) or nil
        save_prices()
        if n <= 0 then
            log(('Price history: %s cleared.'):format(canon))
        elseif old then
            log(('Price history: %s updated %s -> %s gil each.'):format(canon, commas(old), commas(n)))
        else
            log(('Price history: %s added at %s gil each.'):format(canon, commas(n)))
        end
    elseif cmd == 'prices' and (a[1] or ''):lower() == 'clean' then
        local dug = all_dug_names() -- items any character has dug up
        local removed = {}
        for name in pairs(prices) do if not dug[name] then removed[#removed + 1] = name end end
        for _, name in ipairs(removed) do prices[name] = nil end
        save_prices()
        log(('Removed %d price%s for items nobody has dug up%s'):format(#removed, #removed == 1 and '' or 's',
            #removed > 0 and (': ' .. table.concat(removed, ', ')) or '.'))
    elseif cmd == 'debug' then
        local v = (a[1] or ''):lower()
        if v == 'on' then
            if debug_f then log('Debug log already on: ' .. debug_path) return end
            windower.create_dir(windower.addon_path .. 'data')
            windower.create_dir(windower.addon_path .. 'data/debug')
            debug_path = 'data/debug/debug_' .. os.date('%Y%m%d_%H%M%S') .. '.txt'
            debug_f = io.open(windower.addon_path .. debug_path, 'w')
            if not debug_f then log('Could not create the debug file.') return end
            debug_f:write(('BirdUp %s debug log, started %s\n'):format(_addon.version, os.date('%Y-%m-%d %H:%M:%S')))
            debug_f:write(('Zone: %s | Wing Skill: %s | Hyper: %s\n\n'):format(
                zone_name(current_zone()), tostring(life.wing), tostring(S.hyper)))
            debug_f:flush()
            log('Debug log on: addons/birdup/' .. debug_path .. ' (chat while auto-digging or near a dig, plus BirdUp\'s decisions).')
        elseif v == 'off' then
            if not debug_f then log('Debug log is off.') return end
            dbg('END', 'debug off')
            debug_f:close()
            debug_f = nil
            log('Debug log saved: addons/birdup/' .. debug_path)
        else
            log(debug_f and ('Debug log on: addons/birdup/' .. debug_path) or 'Debug log off. //bup debug on to start one.')
        end
    elseif cmd == 'zonewin' then
        local v = (a[1] or ''):lower()
        if v == 'on' then settings.zone_window = true
        elseif v == 'off' then settings.zone_window = false
        else settings.zone_window = not settings.zone_window end
        config.save(settings)
        hud_last = 0
        log('Zone stats window ' .. (settings.zone_window and 'shown.' or 'hidden.'))
    elseif cmd == 'zone' then
        local function summary(zid, ranks)
            for rank, e in pairs(ranks) do
                if e.digs > 0 then
                    log(('%s (%s): %d digs, %d finds (%d%%), %d miss, %d discern'):format(zone_name(zid), rank,
                        e.digs, e.finds, math.floor(e.finds / e.digs * 100 + 0.5), e.miss, e.discern))
                    local list = {}
                    for item, n in pairs(e.items) do list[#list + 1] = {item, n} end
                    table.sort(list, function(x, y) return x[2] > y[2] end)
                    for i = 1, math.min(#list, (a[1] or '') == 'all' and 5 or 12) do
                        log(('  %-24s %5d  %5.1f%%'):format(list[i][1], list[i][2], list[i][2] / e.digs * 100))
                    end
                end
            end
        end
        if (a[1] or ''):lower() == 'all' then
            local n = 0
            for zid, ranks in pairs(zstats) do summary(zid, ranks); n = n + 1 end
            if n == 0 then log('No zone stats yet.') end
        else
            local zid = current_zone()
            if not zid or not zstats[zid] then log('No digs recorded in this zone yet.') return end
            summary(zid, zstats[zid])
        end
    elseif cmd == 'export' then
        -- combine every character's zone stats into one shareable report + CSV
        save_life(true)
        local all, chars = {}, 0
        local dir = windower.addon_path .. 'data/'
        for _, file in ipairs(windower.get_dir(dir) or {}) do
            if file:match('^zones_.+%.txt$') then read_zone_file(dir .. file, all); chars = chars + 1 end
        end
        local rows_out, total_digs, zones_n = {}, 0, 0
        local rank_order = {}
        for i, w in ipairs(WING_RANKS) do rank_order[w[1]] = i end
        local zids = {}
        for zid in pairs(all) do zids[#zids + 1] = zid end
        table.sort(zids, function(x, y) return zone_name(x) < zone_name(y) end)
        if #zids == 0 then log('Nothing to export yet: dig somewhere first.') return end
        windower.create_dir(dir .. 'export')
        local stamp = os.date('%Y%m%d_%H%M%S')
        local csv_rel, txt_rel = 'data/export/birdup_drops_' .. stamp .. '.csv', 'data/export/birdup_drops_' .. stamp .. '.txt'
        local csv = io.open(windower.addon_path .. csv_rel, 'w')
        local txt = io.open(windower.addon_path .. txt_rel, 'w')
        if not csv or not txt then log('Could not write the export files.') return end
        local function q(v) v = tostring(v); return v:find('[,"]') and ('"' .. v:gsub('"', '""') .. '"') or v end
        csv:write('zone,wing_rank,zone_digs,zone_finds,zone_miss,zone_discern,item,count,percent_of_digs,vendor_price\n')
        local lines = {}
        for _, zid in ipairs(zids) do
            zones_n = zones_n + 1
            local ranks = {}
            for rank in pairs(all[zid]) do ranks[#ranks + 1] = rank end
            table.sort(ranks, function(x, y) return (rank_order[x] or 99) < (rank_order[y] or 99) end)
            for _, rank in ipairs(ranks) do
                local e = all[zid][rank]
                if e.digs > 0 then
                    total_digs = total_digs + e.digs
                    lines[#lines + 1] = ('%s  |  Wing rank: %s  |  %d digs, %d finds (%.1f%%), %d miss, %d discern'):format(
                        zone_name(zid), rank, e.digs, e.finds, e.finds / e.digs * 100, e.miss, e.discern)
                    local list = {}
                    for item, n in pairs(e.items) do list[#list + 1] = {item, n} end
                    table.sort(list, function(x, y) return x[2] > y[2] end)
                    for _, it in ipairs(list) do
                        local pct = it[2] / e.digs * 100
                        csv:write(('%s,%s,%d,%d,%d,%d,%s,%d,%.2f,%s\n'):format(q(zone_name(zid)), q(rank), e.digs, e.finds,
                            e.miss, e.discern, q(it[1]), it[2], pct, prices[it[1]] and tostring(prices[it[1]]) or ''))
                        lines[#lines + 1] = ('    %-28s %6d   %6.2f%%%s'):format(it[1], it[2], pct,
                            prices[it[1]] and ('   ~' .. commas(prices[it[1]]) .. ' gil') or '')
                    end
                    lines[#lines + 1] = ''
                end
            end
        end
        txt:write(('BirdUp chocobo digging drop data\nExported %s with BirdUp %s (by Valdimar @ Phoenix)\n'):format(
            os.date('%Y-%m-%d %H:%M'), _addon.version))
        txt:write(('%d digs across %d zone%s, from %d character%s.\n'):format(total_digs, zones_n,
            zones_n == 1 and '' or 's', chars, chars == 1 and '' or 's'))
        txt:write('Rates are per dig at that Wing rank. Prices are vendor prices learned in game.\n\n')
        txt:write(table.concat(lines, '\n') .. '\n')
        csv:close(); txt:close()
        log(('Exported %d digs across %d zone%s to addons/birdup/%s and .txt'):format(
            total_digs, zones_n, zones_n == 1 and '' or 's', csv_rel))
    elseif cmd == 'hyper' then
        local v = (a[1] or ''):lower()
        if v == 'on' then S.hyper, hyper_test, hyper_mode = true, nil, 'on'
        elseif v == 'off' then S.hyper, hyper_test, hyper_mode = false, nil, 'off'
        elseif v == 'test' or v == 'auto' then S.hyper, hyper_test, hyper_mode = nil, 'need_base', 'auto'
        end
        log(('Hyper Chocobo Digging Campaign: %s. Digging every %ds.'):format(
            hyper_test and 'will test on the next digs' or (S.hyper and 'active' or (S.hyper == false and 'not active' or 'not tested')),
            dig_delay()))
    elseif cmd == 'wing' then
        local n = tonumber(a[1] or '')
        if n then
            if n < 0 or n > 100 then log('Wing Skill goes from 0 to 100.') return end
            set_wing(n, false, true)
            save_life(true)
            local r = wing_rank(life.wing)
            log(('Wing Skill set to %d (%s): %ds between digs. Skill-ups seen in chat will keep it updated.'):format(
                life.wing, r[1], r[4]))
        elseif life.wing then
            local r = wing_rank(life.wing)
            log(('Wing Skill %s%d (%s): %ds between digs, %ds after zoning.'):format(
                life.wing_approx and '~' or '', life.wing, r[1], r[4], r[3]))
        else
            log('Wing Skill not seen yet. It updates when a skill-up shows in chat, or set it with //bup wing <level>.')
        end
    elseif cmd == 'history' then
        today()
        local function day_str(d)
            d = tostring(d)
            return d:sub(1, 4) .. '-' .. d:sub(5, 6) .. '-' .. d:sub(7, 8)
        end
        local arg = (a[1] or ''):gsub('-', '')
        local one = (arg:lower() == 'today' and life.day) or (#arg == 8 and tonumber(arg)) or nil
        if one then
            local e = history[one]
            if not e then log('No digs logged on ' .. day_str(one) .. ' (JST).') return end
            log(('%s (JST): %d finds from %d digs, %d miss, %d discern, %d fatigue + %d free, %d session%s, %s digging, %s gil sold%s'):format(
                day_str(one), e.finds, e.attempts, e.fails, e.discern or 0, e.fatigue, e.free, e.sessions,
                e.sessions == 1 and '' or 's', fmt_time(e.secs), commas(e.gil),
                e.wing and (', Wing Skill ' .. e.wing) or ''))
            for k, n in pairs(e.cur) do log(('  %-18s %s'):format(k == 'cp' and 'conquest points' or k, commas(n))) end
            local list = {}
            for name, n in pairs(e.drops) do list[#list + 1] = {name, n} end
            table.sort(list, function(x, y) return x[2] > y[2] end)
            for _, it in ipairs(list) do log(('  %-28s %5d'):format(it[1], it[2])) end
        else
            local n = tonumber(arg) or 7
            local days = {}
            for d in pairs(history) do days[#days + 1] = d end
            table.sort(days, function(x, y) return x > y end)
            log(('Dig history, last %d day%s (JST days). //bup history <yyyymmdd> for items.'):format(
                math.min(n, #days), math.min(n, #days) == 1 and '' or 's'))
            for i = 1, math.min(n, #days) do
                local e = history[days[i]]
                log(('  %s  %4d finds / %4d digs  %3d fatigue  %3d free  %s gil%s'):format(
                    day_str(days[i]), e.finds, e.attempts, e.fatigue, e.free, commas(e.gil),
                    days[i] == life.day and '  (today)' or ''))
            end
        end
    elseif cmd == 'prices' then
        local list = {}
        for name, pr in pairs(prices) do list[#list + 1] = {name, pr} end
        table.sort(list, function(x, y) return x[2] > y[2] end)
        log(('Known prices (%d). Gil from sales: %s lifetime, %s today.'):format(
            #list, commas(life.gil), commas(today().gil)))
        for _, e in ipairs(list) do log(('  %-28s %s gil'):format(e[1], commas(e[2]))) end
    elseif cmd == 'currency' then
        local names = {cp = 'Conquest points', imperial = 'Imperial Standing', allied = 'Allied notes', bayld = 'Bayld'}
        for _, key in ipairs({'cp', 'imperial', 'allied', 'bayld'}) do
            log(('  %-18s lifetime %s, today %s'):format(names[key],
                commas(life.cur[key] or 0), commas(today().cur[key] or 0)))
        end
    elseif cmd == 'view' then
        settings.finds_view = (a[1] or ''):lower() == 'lifetime' and 'lifetime' or 'today'
        config.save(settings)
        log('Item list now shows: ' .. settings.finds_view)
    elseif cmd == 'finds' then
        local src = settings.finds_view == 'lifetime' and life.drops or today().drops
        local list = {}
        for name, n in pairs(src) do list[#list + 1] = {name, n} end
        table.sort(list, function(x, y) return x[2] > y[2] end)
        log(('Items found (%s): %d types'):format(settings.finds_view, #list))
        for _, e in ipairs(list) do
            log(('  %-28s %5d%s'):format(e[1], e[2], prices[e[1]] and ('  @' .. short_price(prices[e[1]])) or ''))
        end
    elseif cmd == 'saveall' then
        config.save(settings, 'all')
        log('Current settings copied to all characters.')
    elseif cmd == 'profile' then
        log(('Character: %s | timer %.1fs, jitter %.1fs, distance %.1fy, max %d, mount check %s'):format(
            char_name or '?', settings.dig_interval, settings.jitter,
            settings.required_distance, settings.max_success, tostring(settings.require_mount)))
    else
        help()
    end
end)
