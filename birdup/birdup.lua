_addon.name     = 'birdup'
_addon.author   = 'Valdimar @ Phoenix' -- auto-dig based on Velner/chocodig
_addon.version  = '4.9'
_addon.commands = {'birdup', 'bup'}

-- Says in chat when a newer version is on GitHub (once per load; see update_check.lua)
require('update_check').start({
    name    = 'BirdUp',
    version = _addon.version,
    url     = 'https://raw.githubusercontent.com/Valdimar/BirdUp/main/birdup/birdup.lua',
    page    = 'github.com/Valdimar/BirdUp',
})

--[[
BirdUp: chocobo digging tracker and auto-digger for Windower 4.

Files:
  birdup.lua        this file: panel, auto-dig, dig tracking, prices, history, commands
  birdup_zones.lua  per-zone drop stats, import/export sharing
  birdup_roe.lua    Records of Eminence progress

How it fits together:
  * Chat lines (incoming text) tell BirdUp what each dig produced. A dig is
    "waiting" from the moment /dig or the dig packet goes out until its result
    line arrives (results come about 4 seconds later, at the end of the dig
    animation).
  * Every frame (prerender) checks the date, counts greens, redraws the panel,
    and runs tick(), the auto-dig step: wait for the result, move to the next
    spot, wait out the cooldown, dig again.
  * Everything per character is saved under data/ (settings.xml, lifetime_,
    history_, zones_ files); prices, imports and the sharing id are shared.

Sections, in order: Settings, State, Helpers, Debug log, Lifetime stats,
Daily history, Item prices, Wing Skill / Hyper Campaign, Panel (HUD),
Movement, Result tracking, Sale detection, Main loop, Per-character support,
Mouse, Commands.

Note: Windower runs LuaJIT, which allows at most 200 local variables at the
top of a file and 60 outside variables per function. That's why constants
live in the K table, related helpers are grouped into tables (SETTINGS,
debug_unknown), and each //bup command is its own small function.
]]

-- Windower libraries: on-screen text, images, saved settings, game data
local texts  = require('texts')
local images = require('images')
local config = require('config')
local res    = require('resources')

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
package.path = windower.addon_path .. '?.lua;' .. package.path -- find birdup_*.lua next to this file
local K = {} -- constants (kept in one table: Lua allows only 200 top-level locals)

-- Default settings. Saved per character in data/settings.xml; change them
-- with //bup set (see SETTINGS further down).
local defaults = {
    dig_interval      = 4,     -- (no longer used: the Wing Skill cooldown sets the pace)
    extra_wait        = 0,     -- extra seconds on top of the dig cooldown (//bup timer)
    jitter            = 0.6,   -- (no longer used: see humanize)
    humanize          = 0,     -- up to this many random extra seconds per dig (0 = dig right on the cooldown)
    required_distance = 5,     -- yalms (2D) to travel between digs
    min_distance      = 2,     -- never dig closer than this to the last dig, even at a wall (//bup set mindist)
    move_timeout      = 8,
    turn_distance     = 3,     -- yalms to move after turning away from undiggable ground
    dig_settle        = 2.5,   -- (no longer used: the dig result means the dig has finished)
    result_buffer     = 0.3,   -- seconds after a dig result before turning and moving (//bup settle)
    turn_chance       = 50,    -- % chance to turn after a dig (otherwise keep going the same way)
    roam_radius       = 20,    -- stay within this many yalms of where auto-dig started (0 = no limit)
    move_during_dig   = false, -- no longer used (see run_during_dig)
    run_during_dig    = true,  -- start running once the dig is sent; next dig right after the result (//bup set rundig)
    stop_settle       = 0.4,   -- seconds the chocobo must be standing still before a dig
    result_timeout    = 5,     -- used until auto_tune has enough measurements
    auto_tune         = true,  -- set the no-result wait from how fast results really arrive
    warn_greens       = 10,    -- flash the panel when greens are at or below this (0 = off)
    warn_slots        = 5,     -- flash the panel when free inventory slots are at or below this (0 = off)
    blocked_progress  = 1.0,   -- yalms a second below which the chocobo always counts as blocked (walls)
    bad_ground_limit  = 7,     -- stop and alert after this many "can't dig here" in a row (0 = never)
    stop_echo         = 'Kweh! This ground is all wark and no dig. Find me a better spot!', -- extra echo with the alert
    stuck_check_time  = 1.0,
    stuck_epsilon     = 0.2,
    max_success       = 100,   -- stop after this many finds today (0 = never)
    require_mount     = true,
    hud_visible       = true,
    auto_hide         = true,
    compact           = false, -- show only the key rows
    collapse_items    = false, -- hide the ITEMS FOUND list (click its header)
    locked            = false, -- panel can't be dragged
    zone_window       = false,
    rewards_window    = false, -- digging rewards window (REWARDS button / //bup rewards)
    hyper_start       = 0,     -- Hyper Campaign dates (JST, yyyymmdd); 0 = none set
    hyper_end         = 0, -- zone stats window beside the main panel (ZONES button / //bup zonewin)  -- only show the HUD while on a chocobo (or auto-digging)
    line_spacing      = 18,    -- pixels from one HUD line to the next
    finds_view        = 'today',   -- 'today' (since midnight JST, survives reloads) or 'lifetime'
    fatigue_cap       = 100,   -- daily fatigue-counting digs (rental 100; raised/silks up to ~200)
    stop_at_fatigue   = true,
    min_free_slots    = 2,     -- auto-stop when free inventory slots <= this (0 = off)
    pos               = {x = 1100, y = 200},
}
-- the current character's settings (reloaded on character change)
local settings = config.load(defaults)

K.GREENS_ID   = 4545
-- player.status while riding: 5 = chocobo (rental/whistle), 85 = mount system
K.MOUNT_STATUSES = {[5] = true, [85] = true}

-- true while riding a chocobo (or any mount: the game can't tell them apart)
local function is_mounted()
    local p = windower.ffxi.get_player()
    return p and K.MOUNT_STATUSES[p.status] or false
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
-- this character's lifetime totals plus today's fatigue (data/lifetime_<name>.txt)
local life = {attempts = 0, successes = 0, drops = {}, fatigue = 0, free = 0, day = 0, cur = {}, gil = 0, wing = nil, wing_approx = false, discern = 0}
-- unsaved changes? / when lifetime was last saved
local life_dirty, life_saved = false, 0

-- earliest time for the next dig / where the last dig was
local next_dig, last_dig_pos = 0, nil
local anchor = nil -- {x, y}: center of the area auto-dig stays in
local settle_until = 0 -- don't turn or move before this (dig animation still playing)
local turn_until = 0   -- after turning, wait this long before starting to run
-- auto-dig movement: running?, when and where this move started
local moving, move_start_time, move_start_pos = false, 0, nil
-- last progress check (for spotting walls)
local prog_time, prog_pos = 0, nil
-- Gysahl Greens in your bag / when last counted
local greens, greens_time = nil, 0
-- inventory slots used / total
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

-- write one timestamped line to the debug log (does nothing while debug is off)
local function dbg(kind, msg)
    if not debug_f then return end
    local t = os.clock()
    debug_f:write(('%s.%03d  %-6s %s\n'):format(os.date('%H:%M:%S'), math.floor((t % 1) * 1000), kind, escape(msg)))
    debug_f:flush()
end

-- BirdUp's chat line ([BirdUp] ...), also copied to the debug log
local function log(msg)
    windower.add_to_chat(207, ('[BirdUp] %s'):format(msg))
    dbg('BIRDUP', msg)
end

-- Game lines seen near digs that BirdUp has no rule for, listed at the end of
-- each debug log so new messages are easy to spot.
local debug_unknown = {
    lines = {},
    known = {'obtained:', 'find nothing', 'refuses to partake', 'with ease', 'wing skill',
             'cannot dig here', 'wait longer to perform', 'cache of beastman', 'records of eminence',
             'progress:', 'sparks of eminence', 'unity accolades', 'limit points', 'experience points',
             'objective may be repeated', 'bayld', 'imperial standing', 'allied notes', 'conquest points',
             'inventory is full', 'cannot carry any more'},
    -- player chat (say, shout, tell, party, linkshells, unity...) isn't the game talking
    player_modes = {[1]=1, [2]=1, [3]=1, [4]=1, [5]=1, [6]=1, [7]=1, [8]=1, [9]=1, [10]=1, [11]=1,
                    [12]=1, [13]=1, [14]=1, [15]=1, [211]=1, [212]=1, [213]=1, [214]=1, [220]=1},
}
-- remember a game line near a dig that matches none of BirdUp's rules
function debug_unknown.note(clean, mode)
    if debug_unknown.player_modes[mode] then return end
    local lower = clean:lower()
    for _, k in ipairs(debug_unknown.known) do if lower:find(k, 1, true) then return end end
    local shape = clean:gsub('%d+', '#'):gsub('%s+$', '')
    if shape == '' or shape:find('[BirdUp]', 1, true) then return end
    debug_unknown.lines[shape] = (debug_unknown.lines[shape] or 0) + 1
end
-- close the debug log, ending it with the unrecognized-lines list;
-- returns how many unrecognized lines there were
function debug_unknown.close(why)
    if not debug_f then return end
    local list = {}
    for line, n in pairs(debug_unknown.lines) do list[#list + 1] = {line, n} end
    table.sort(list, function(x, y) return x[2] > y[2] end)
    debug_f:write('\n---- Lines near digs BirdUp has no rule for (numbers shown as #) ----\n')
    if #list == 0 then debug_f:write('(none)\n') end
    for _, e in ipairs(list) do debug_f:write(('%5dx  %s\n'):format(e[2], escape(e[1]))) end
    dbg('END', why)
    debug_f:close()
    debug_f = nil
    debug_unknown.lines = {}
    return #list
end

-- 1234567 -> '1,234,567'
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

-- seconds -> 'hh:mm:ss' (session timer, history)
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

-- your own character as Windower sees it (position, facing...)
local function get_me() return windower.ffxi.get_mob_by_target('me') end

-- your current x/y position, or nil before you've logged in
local function get_pos()
    local me = get_me()
    return me and {x = me.x, y = me.y} or nil
end

-- flat distance in yalms between two positions (height ignored)
local function dist2d(a, b)
    if not a or not b then return 0 end
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

-- count Gysahl Greens and used/max inventory slots (at most once a second)
local function refresh_greens(now)
    if now - greens_time < 1 then return end
    greens_time = now
    local items = windower.ffxi.get_items()
    if not items or not items.inventory then greens = nil inv_used, inv_max = nil, nil return end
    inv_used, inv_max = items.inventory.count, items.inventory.max
    local n = 0
    for i = 1, (items.inventory.max or 80) do
        local e = items.inventory[i]
        if e and e.id == K.GREENS_ID then n = n + (e.count or 0) end
    end
    greens = n
end

---------------------------------------------------------------------------
-- Lifetime stats (simple tab-separated file)
---------------------------------------------------------------------------
local char_name = nil -- set by switch_character() below
local clean_name      -- defined in the prices section below
local save_history    -- defined just below
local Z               -- zone stats + sharing module (birdup_zones.lua)
local ROE             -- Records of Eminence module (birdup_roe.lua)
local REW             -- digging rewards by zone + REWARDS window (birdup_rewards.lua)

---------------------------------------------------------------------------
-- Daily history: one entry per Japan day (fatigue resets at midnight JST).
-- Every session dug that day is added into the same entry.
-- Saved as data/history_<name>.txt, one line per day.
---------------------------------------------------------------------------
local history = {} -- yyyymmdd (JST) -> entry

-- an empty daily-history entry
local function new_day_entry()
    return {attempts = 0, finds = 0, fails = 0, fatigue = 0, free = 0, sessions = 0,
            secs = 0, gil = 0, wing = nil, discern = 0, roe = 0, cur = {}, drops = {}}
end

-- data/history_<name>.txt for the current character
local function history_path()
    local who = (char_name or 'unknown'):lower():gsub('[^%w_-]', '')
    return windower.addon_path .. 'data/history_' .. who .. '.txt'
end

-- read this character's daily history (one tab-separated line per JST day)
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
            e.roe = tonumber(p[14]) or 0
            history[d] = e
        end
    end
    f:close()
end

-- write the whole daily history back, oldest day first
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
        f:write(('%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%d\t%s\t%s\t%s\t%d\t%d\n'):format(
            d, e.attempts, e.finds, e.fails, e.fatigue, e.free, e.sessions, e.secs, e.gil,
            e.wing and tostring(e.wing) or '', table.concat(cur, '|'), table.concat(drops, '|'), e.discern or 0, e.roe or 0))
    end
    f:close()
end

-- data/lifetime_<name>.txt for the current character
local function life_path()
    local who = (char_name or 'unknown'):lower():gsub('[^%w_-]', '')
    return windower.addon_path .. 'data/lifetime_' .. who .. '.txt'
end

-- read this character's lifetime totals: '#key' lines are counters, the rest
-- are item counts. Item names saved by older versions are cleaned up here.
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

-- save lifetime totals (and history + zone stats with them). Without force it
-- only saves when something changed and 30 seconds have passed.
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
    if Z then Z.save() end
    life_dirty, life_saved = false, os.clock()
end

---------------------------------------------------------------------------
-- HUD
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Item prices (shared by all characters, learned from your own sales)
---------------------------------------------------------------------------
local prices = {}                       -- item name -> gil each (best known city price)
local cprices = {}                      -- item name -> city -> gil each (latest sale there)
-- best known vendor price per item, shared by all characters
local prices_path = windower.addon_path .. 'data/prices.txt'
local name_to_id, dug_by_id = nil, {}   -- dug_by_id: item id -> name (items you've dug up)

-- item id for an item name (case-insensitive), using the game's short names
-- first and long names as a fallback. The lookup table is built on first use.
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

-- write prices.txt (best price per item) and city_prices.txt (per city)
local function save_prices()
    windower.create_dir(windower.addon_path .. 'data')
    local f = io.open(prices_path, 'w')
    if not f then return end
    for name, n in pairs(prices) do f:write(('%s\t%d\n'):format(name, n)) end
    f:close()
    f = io.open((windower.addon_path .. 'data/city_prices.txt'), 'w')
    if not f then return end
    for name, cities in pairs(cprices) do
        for city, n in pairs(cities) do f:write(('%s\t%s\t%d\n'):format(name, city, n)) end
    end
    f:close()
end

-- read both price files, cleaning up names saved by older versions
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
    cprices = {}
    local cf = io.open((windower.addon_path .. 'data/city_prices.txt'), 'r')
    if cf then
        for line in cf:lines() do
            local k, city, v = line:match('^(.-)\t(.-)\t(%d+)$')
            if k then
                local name = clean_name(k) or k
                cprices[name] = cprices[name] or {}
                cprices[name][city] = tonumber(v)
            end
        end
        cf:close()
    end
    if changed then save_prices() end -- tidy names saved by older versions
end

-- remember an item's id as 'dug up', so vendor sales of it are recognized
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

-- gil value of a set of items at the best known prices (Est. val)
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
        if was_set and char_name then
            -- a new day also starts a new session: attempts, hit rate, the
            -- session timer and finds-per-hour start over (auto-dig keeps running)
            S.attempts, S.successes, S.fails, S.free, S.discern = 0, 0, 0, 0, 0
            S.drops, S.cur, S.gil, S.first_dig, S.last_dig_t = {}, {}, 0, nil, nil
            log('New day in Japan: daily fatigue and today\'s finds reset to 0, new session started.')
        end
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
K.WING_RANKS = { -- {name, min skill, area delay after zoning, dig delay}
    {'Amateur',     0, 60, 15}, {'Recruit',   10, 55, 10}, {'Initiate',  20, 50, 5},
    {'Novice',     30, 45,  3}, {'Apprentice', 40, 40, 3}, {'Journeyman', 50, 35, 3},
    {'Craftsman',  60, 30,  3}, {'Artisan',   70, 25,  3}, {'Adept',     80, 20, 3},
    {'Veteran',    90, 15,  3}, {'Expert',   100, 10,  3},
}

-- the rank row for a Wing Skill level: {name, min level, area delay, dig delay}
local function wing_rank(skill)
    if not skill then return nil end
    local r = K.WING_RANKS[1]
    for _, w in ipairs(K.WING_RANKS) do if skill >= w[2] then r = w end end
    return r
end

-- seconds the game makes you wait between digs at your Wing Skill (nil = unknown)
local function wing_delay()
    local r = wing_rank(life.wing)
    return r and r[4] or nil
end

---------------------------------------------------------------------------
-- The two helper files. Each gets a small table of what it needs from here;
-- they're wrapped in functions so the files always see the current values.
---------------------------------------------------------------------------
-- Records of Eminence (birdup_roe.lua): needs chat output, number formatting,
-- and today's history entry (to count completions per day)
ROE = require('birdup_roe')({
    log = function(m) log(m) end,
    commas = function(n) return commas(n) end,
    today = function() return today() end,
})

-- Zone stats and sharing (birdup_zones.lua): needs the character name (for
-- file names), the current Wing rank name (stats are split by rank), and
-- number formatting
Z = require('birdup_zones')({
    char_name = function() return char_name end,
    rank_name = function() local r = wing_rank(life.wing) return r and r[1] or 'Unknown' end,
    commas = function(n) return commas(n) end,
})

-- Hyper Chocobo Digging Campaign: every rank digs every 3s while it runs.
-- S.hyper: nil = not tested, true = active, false = not active
-- hyper_test: nil, 'need_base' (waiting for a normal dig to land),
--             'probe_next' (next dig is the test), 'probing' (test dig sent)
K.HYPER_DELAY = 3
K.HYPER_AREA_DELAY = 5
-- campaign test progress: nil, 'need_base', 'probe_next' or 'probing'
local hyper_test = nil
local hyper_mode = 'auto' -- 'auto' = test on each start; 'on'/'off' = set by //bup hyper (until reload)
local zoned_at = nil      -- os.clock() of the last zone-in

-- Hyper Campaign dates entered with //bup hyper Oct16-Nov9 (checked against the Japan date)
K.MONTHS = {'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'}

-- today's date in Japan as yyyymmdd (fatigue and campaigns follow Japan time)
local function jst_today() return tonumber(os.date('!%Y%m%d', os.time() + 9 * 3600)) end

-- 20261109 -> 'Nov 9'
local function fmt_md(d) return ('%s %d'):format(K.MONTHS[math.floor(d / 100) % 100] or '?', d % 100) end

-- true while today falls inside the saved Hyper Campaign dates
local function campaign_now()
    local t = jst_today()
    return settings.hyper_start > 0 and t >= settings.hyper_start and t <= settings.hyper_end
end

-- is the faster campaign timing in use right now?
local function hyper_on()
    if hyper_mode == 'off' then return false end
    if hyper_mode == 'on' then return true end
    return S.hyper == true or campaign_now()
end

-- "Oct16-Nov9", "Oct 16th - Nov 9th", "10/16-11/9", "16oct-9nov" -> yyyymmdd, yyyymmdd
local function parse_campaign(text)
    local str = text:lower():gsub('%s+', ''):gsub('(%d)st', '%1'):gsub('(%d)nd', '%1'):gsub('(%d)rd', '%1'):gsub('(%d)th', '%1')
    str = str:gsub('to', '-')
    local a, b = str:match('^([^-]+)%-([^-]+)$')
    if not a then return nil end
    -- one date: 'oct16', '16oct' or '10/16' -> month * 100 + day
    local function one(x)
        local mon, day = x:match('^(%a+)%.?(%d+)$')
        if not mon then day, mon = x:match('^(%d+)(%a+)$') end
        local m
        if mon then
            for i, n in ipairs(K.MONTHS) do if mon:sub(1, 3) == n:lower() then m = i end end
        else
            local mm, dd = x:match('^(%d+)/(%d+)$')
            m, day = tonumber(mm), dd
        end
        day = tonumber(day)
        if not m or not day or m < 1 or m > 12 or day < 1 or day > 31 then return nil end
        return m * 100 + day
    end
    local s1, e1 = one(a), one(b)
    if not s1 or not e1 then return nil end
    -- pick the year: the range that includes today, else the next one coming up,
    -- else (all in the past) the most recent one
    local today = jst_today()
    local y = math.floor(today / 10000)
    local best_st, best_en, recent_st, recent_en
    for yy = y - 1, y + 1 do
        local st, en = yy * 10000 + s1, yy * 10000 + e1
        if en < st then en = en + 10000 end -- runs over New Year (Dec-Jan)
        if today >= st and today <= en then return st, en end
        if st > today and (not best_st or st < best_st) then best_st, best_en = st, en end
        if en < today and (not recent_en or en > recent_en) then recent_st, recent_en = st, en end
    end
    if recent_en and jst_today() - recent_en < 100 then return recent_st, recent_en end -- just ended
    return best_st or recent_st, best_en or recent_en
end

-- seconds before the first dig after zoning is allowed (0 = none)
local function zone_wait_left()
    if not zoned_at then return 0 end
    local r = wing_rank(life.wing)
    local delay = hyper_on() and K.HYPER_AREA_DELAY or (r and r[3] or 60) -- unknown skill: slowest
    return math.max(0, zoned_at + delay - os.clock())
end

-- seconds between digs auto-dig should use right now
local function dig_delay()
    local wd = wing_delay() or 15 -- unknown Wing Skill: assume the slowest rank to be safe
    if hyper_on() then wd = math.min(wd, K.HYPER_DELAY) end
    return wd
end

-- store a new Wing Skill level (approx = only the rank was known) and announce it
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

K.W_MIN = 280
-- starting panel height (it grows to fit the rows)
local H = 252
local W = K.W_MIN -- panel width; grows/shrinks to fit the longest line
-- text colors for the panel (Windower color codes)
local C = {
    dim  = '\\cs(140,148,165)', val = '\\cs(235,238,245)',
    good = '\\cs(110,220,150)', warn = '\\cs(255,200,90)',
    bad  = '\\cs(255,110,110)', acc  = '\\cs(120,190,255)', r = '\\cr',
}

-- a plain colored rectangle (panel backgrounds, bars, buttons)
local function solid(w, h, a, r, g, b, draggable)
    return images.new({
        pos = {x = settings.pos.x, y = settings.pos.y},
        color = {alpha = a, red = r, green = g, blue = b},
        size = {width = w, height = h},
        draggable = draggable or false,
    })
end

-- a transparent Consolas text object for the panel
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
-- current panel height, for mouse hit-testing
local panel_h = H

-- the main panel's pieces: background, header, fatigue bar, buttons, labels
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
K.ZBTN_W, K.ZBTN_H = 56, 18
-- REWARDS header button, just left of ZONES
hud.b_rew = solid(70, 18, 255, 60, 75, 110)
hud.l_rew = mk_text(9)
hud.l_rew:text('REWARDS')
K.RBTN_W = 70

-- Zone stats window, docked to the right of the main panel
K.ZW_MIN, K.ZW_GAP = 230, 6
-- the zone stats window's pieces
local zwin = {
    bg     = solid(K.ZW_MIN, 100, 215, 18, 20, 28),
    header = solid(K.ZW_MIN, 26, 255, 38, 52, 84),
    title  = mk_text(11),
}
-- zone window lines, their offsets, how many are in use, its width, shown?
local zw_pool, zw_ry, zw_used, zw_w, zw_on = {}, {}, 0, K.ZW_MIN, false

-- Digging rewards by zone (birdup_rewards.lua): needs the panel's drawing
-- helpers and colors, and what you've dug in a zone (all Wing ranks together)
REW = require('birdup_rewards')({
    solid = solid,
    mk_text = mk_text,
    C = C,
    log = function(m) log(m) end,
    found = function(zone_name)
        local zid = Z.zone_id_for((zone_name or ''):gsub('%(S%)', '[S]'))
        local got = {}
        for _, e in pairs((zid and Z.stats()[zid]) or {}) do
            for item, n in pairs(e.items) do got[item] = (got[item] or 0) + n end
        end
        return got
    end,
})

-- Buttons, relative to the panel's top-left corner
K.BTN_Y, K.BTN_H = 50, 22
-- width of each START / STOP button (they share the panel width)
local BTN_W = math.floor((W - 30) / 2)
-- START and STOP: position inside the panel, image, label
local buttons = {
    start = {rx = 10,              img = hud.b_start, lbl = hud.l_start, text = 'START'},
    stop  = {rx = 20 + BTN_W,      img = hud.b_stop,  lbl = hud.l_stop,  text = 'STOP'},
}
for _, b in pairs(buttons) do
    b.img:size(BTN_W, K.BTN_H)
    b.lbl:text(b.text)
end
K.ROWS_Y = K.BTN_Y + K.BTN_H + 10 -- first stat row

-- One text object per HUD line, so line spacing can be set exactly
-- (offsets live in their own table: Windower text objects don't keep extra fields)
local lines_pool, lines_ry, lines_used = {}, {}, 0
-- is the panel on screen?
local hud_on = false
-- when the panel was last redrawn (0 = redraw now)
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
local draw_rewards_window -- defined below
-- the header text, kept for measuring the panel width
local title_str = ''
-- low greens / low bag space already announced in chat?
local warned = {greens = false, slots = false}
local items_hdr_y, items_hdr_h = -100, 0 -- ITEMS FOUND header row, for clicks

-- resize the panel and everything that stretches with it (header, bar, buttons)
local function set_width(w)
    if w == W then return end
    W = w
    hud.header:size(W, 26)
    hud.bar_bg:size(W - 20, 10)
    BTN_W = math.floor((W - 30) / 2)
    buttons.stop.rx = 20 + BTN_W
    for _, b in pairs(buttons) do b.img:size(BTN_W, K.BTN_H) end
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
        b.img:pos(px + b.rx, py + K.BTN_Y)
        -- Consolas 10 is about 7.5 px per character
        b.lbl:pos(px + b.rx + math.floor((BTN_W - #b.text * 7.5) / 2), py + K.BTN_Y + 3)
    end
    for i = 1, lines_used do
        local t = lines_pool[i]
        t:pos(px + 10, py + (lines_ry[i] or 0))
    end
    hud.b_zones:pos(px + W - K.ZBTN_W - 6, py + 4)
    hud.l_zones:pos(px + W - K.ZBTN_W - 6 + 9, py + 5)
    hud.b_rew:pos(px + W - K.ZBTN_W - K.RBTN_W - 12, py + 4)
    hud.l_rew:pos(px + W - K.ZBTN_W - K.RBTN_W - 12 + 7, py + 5)
    -- rewards window: right of the zone window when that's open, else right of the panel
    REW.move(px + W + K.ZW_GAP + (zw_on and (zw_w + K.ZW_GAP) or 0), py)
    -- zone window sits just right of the main panel
    local zx = px + W + K.ZW_GAP
    zwin.bg:pos(zx, py)
    zwin.header:pos(zx, py)
    zwin.title:pos(zx + 10, py + 5)
    for i = 1, zw_used do zw_pool[i]:pos(zx + 10, py + (zw_ry[i] or 0)) end
end

-- show or hide the zone stats window
local function zwin_show(on)
    zw_on = on
    for _, e in pairs(zwin) do if on then e:show() else e:hide() end end
    if not on then for _, t in ipairs(zw_pool) do t:hide() end end
end

-- show or hide the main panel (hiding it hides the zone window too)
local function hud_show(on)
    for _, e in pairs(hud) do if on then e:show() else e:hide() end end
    if not on then
        for _, t in ipairs(lines_pool) do t:hide() end
        zwin_show(false)
        REW.hide()
    end
end

-- should the panel be on screen right now? (setting, auto-hide, mounted, running)
local function want_hud()
    if not settings.hud_visible then return false end
    if not settings.auto_hide then return true end
    return S.running or is_mounted()
end

-- show/hide the panel when want_hud() changes (force = re-apply anyway)
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
    local zid = Z.current_zone()
    local wr = wing_rank(life.wing)
    local rank = wr and wr[1] or 'Unknown'
    local e = zid and Z.stats()[zid] and Z.stats()[zid][rank]
    local title = C.acc .. 'ZONE STATS' .. C.r
    zwin.title:text(title)

    local out, y = {}, 34
    -- add one line to the window at the next row
    local function add(text) out[#out + 1] = {text, y}; y = y + sp end
    add(C.val .. Z.zone_name(zid) .. C.r)
    add(C.dim .. 'Wing rank  ' .. C.r .. rank)
    local all = zid and Z.combined(zid, rank)
    if all and all.digs > 0 then
        add(C.dim .. 'All players' .. C.r .. (' %s digs  %s(%d%% hit)%s'):format(commas(all.digs), C.dim,
            math.floor(all.finds / all.digs * 100 + 0.5), C.r))
    end
    if e and e.digs > 0 then
        add(C.dim .. 'Digs       ' .. C.r .. ('%d  %s(%d finds, %d%%)%s'):format(e.digs, C.dim, e.finds,
            math.floor(e.finds / e.digs * 100 + 0.5), C.r))
        add(C.dim .. 'Miss       ' .. C.r .. ('%d  %s(discern %d)%s'):format(e.miss, C.dim, e.discern, C.r))
        y = y + 8
        add(C.acc .. 'ITEMS' .. C.r .. C.dim .. (all and ' (you / all players, per dig)' or ' (rate per dig)') .. C.r)
        local list = {}
        for item, n in pairs(e.items) do list[#list + 1] = {item, n} end
        if all then -- items only other players have found here
            for item in pairs(all.items) do if not e.items[item] then list[#list + 1] = {item, 0} end end
        end
        table.sort(list, function(x, yy)
            if x[2] ~= yy[2] then return x[2] > yy[2] end
            return (all and (all.items[x[1]] or 0) or 0) > (all and (all.items[yy[1]] or 0) or 0)
        end)
        for i = 1, math.min(#list, 15) do
            local nm = list[i][1]
            if #nm > 18 then nm = nm:sub(1, 17) .. '.' end
            local mine_pct = list[i][2] / e.digs * 100
            if all then
                add(('%-18s %s%4d%s %5.1f%% %s%5.1f%%%s'):format(nm, C.good, list[i][2], C.r, mine_pct,
                    C.dim, (all.items[list[i][1]] or 0) / all.digs * 100, C.r))
            else
                add(('%-18s %s%4d%s %5.1f%%'):format(nm, C.good, list[i][2], C.r, mine_pct))
            end
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
    zw_w = math.max(K.ZW_MIN, math.ceil(widest) + 22)
    zwin.header:size(zw_w, 26)
    zwin.bg:size(zw_w, y + 6)
    layout()
end

-- the State row: IDLE / DIGGING / MOVING / PAUSED, colored
-- the REWARDS window: right of the zone window when that's open, else right
-- of the panel (kept out of update_hud to keep that function's variable count down)
draw_rewards_window = function(sp)
    if settings.rewards_window then hud.b_rew:color(80, 120, 170) else hud.b_rew:color(60, 75, 110) end
    if not settings.rewards_window then REW.hide() return end
    REW.draw(px + W + K.ZW_GAP + (zw_on and (zw_w + K.ZW_GAP) or 0), py, sp, Z.zone_name(Z.current_zone()))
end

local function state_text()
    if not S.running then return C.dim .. 'IDLE' .. C.r end
    if S.paused then return C.warn .. 'PAUSED' .. C.r end
    if moving then return C.acc .. 'MOVING' .. C.r end
    return C.good .. 'DIGGING' .. C.r
end

-- one panel row: dim label padded to 12 characters, then the value
local function row(label, value)
    -- labels padded to 12 so the values sit a few spaces clear of them
    return C.dim .. ('%-12s'):format(label) .. C.r .. C.val .. value .. C.r
end

-- redraw the whole panel (called 5 times a second while it's showing):
-- warnings, the stat rows, the item list, then size the box to fit
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
            and (C.dim .. ('  %d/%dy from center'):format(math.floor(dist2d(pos, anchor)), math.floor(settings.roam_radius)) .. C.r) or '')),
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
    if hyper_on() then
        table.insert(rows, 3, row('Hyper', C.good .. 'ACTIVE' .. C.r .. C.dim .. (' (%ds cooldown%s)'):format(K.HYPER_DELAY,
            (hyper_mode == 'auto' and campaign_now()) and (', until ' .. fmt_md(settings.hyper_end)) or '') .. C.r))
    elseif hyper_test and S.running then
        table.insert(rows, 3, row('Hyper', C.warn .. 'testing...' .. C.r))
    end

    -- today's totals (every session since midnight JST)
    local td = today()
    table.insert(rows, #rows, row('Today', ('%d finds  %s(%d digs, %d session%s)%s'):format(
        td.finds, C.dim, td.attempts, td.sessions, td.sessions == 1 and '' or 's', C.r)))
    local roe_main, roe_extra = ROE.row_text()
    if roe_main then
        table.insert(rows, #rows, row('RoE', roe_main .. C.dim .. roe_extra .. C.r))
    end

    rows[#rows + 1] = row('Sold', C.good .. commas(life.gil) .. C.r .. C.dim .. ' gil (+' .. commas(td.gil) .. ' today)' .. C.r)
    rows[#rows + 1] = row('Est. val', commas(value_of(life.drops)) .. C.dim .. ' gil (+' .. commas(value_of(td.drops)) .. ' today)' .. C.r)

    -- a currency row: lifetime total plus today's gain
    local function cur_row(label, key)
        return row(label, C.good .. commas(life.cur[key] or 0) .. C.r ..
            C.dim .. ' (+' .. commas(td.cur[key] or 0) .. ' today)' .. C.r)
    end
    rows[#rows + 1] = cur_row('Conquest', 'cp')
    if (life.cur.imperial or 0) > 0 then rows[#rows + 1] = cur_row('Imperial', 'imperial') end
    if (life.cur.allied or 0) > 0 then rows[#rows + 1] = cur_row('Allied', 'allied') end
    if (life.cur.bayld or 0) > 0 then rows[#rows + 1] = cur_row('Bayld', 'bayld') end
    -- compact mode: only the rows you need while digging
    if settings.compact then
        local keep = {Warning = 1, State = 1, Wing = 1, Hyper = 1, Fatigue = 1, Greens = 1,
                      Inventory = 1, ['Next dig'] = 1, Today = 1, RoE = 1}
        local kept = {}
        for _, r in ipairs(rows) do
            local label = r:gsub('\\cs%(%d+,%d+,%d+%)', ''):gsub('\\cr', ''):sub(1, 12):gsub('%s+$', '')
            if keep[label] then kept[#kept + 1] = r end
        end
        rows = kept
    end

    local sp = math.max(10, settings.line_spacing)
    local out = {}
    for i, r in ipairs(rows) do out[#out + 1] = {r, K.ROWS_Y + (i - 1) * sp} end
    local fy = K.ROWS_Y + #rows * sp + 8 -- items list starts below however many rows there are

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
    local lines = {('%sITEMS FOUND%s %s(%s, %d types)  %s%s'):format(
        C.acc, C.r, C.dim, settings.finds_view == 'lifetime' and 'lifetime' or 'today', #list,
        settings.collapse_items and '[+]' or '[-]', C.r)}
    items_hdr_y, items_hdr_h = fy, sp
    if settings.collapse_items then
        -- list hidden: header only (click it to open)
    elseif #list == 0 then
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
    local widest = text_width(hud.title, title_str, 8.3) + K.ZBTN_W + K.RBTN_W + 18 -- room for ZONES + REWARDS
    for i, l in ipairs(out) do
        widest = math.max(widest, text_width(lines_pool[i], l[1], 7.5))
    end
    set_width(math.max(K.W_MIN, math.ceil(widest) + 22))

    panel_h = fy + #lines * sp + 8
    hud.bg:size(W, panel_h) -- panel grows with the list

    -- ZONES button looks pressed while the window is open
    if settings.zone_window then hud.b_zones:color(80, 120, 170) else hud.b_zones:color(60, 75, 110) end
    draw_zone_window(sp)
    draw_rewards_window(sp) -- after the zone window, whose width decides where it goes
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

-- turn the character by an angle (radians), relative to where it faces now
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
-- in which case head back toward the center (give or take 45 degrees).
-- returns a heading, or nil to keep going the way you're facing
local function roam_heading(pos)
    local r = settings.roam_radius
    -- any direction
    local function rnd() return math.random() * 2 * math.pi end
    local step = settings.required_distance + 1
    -- near a wall we hit, don't head back toward it (within 70 degrees)
    local wall = S.wall
    if wall and dist2d(pos, wall.pos) > 10 then S.wall, wall = nil, nil end -- left it behind
    -- would heading f point back at the wall we just hit? (within 70 degrees)
    local function into_wall(f)
        if not wall then return false end
        local d = math.abs((f - wall.facing + math.pi) % (2 * math.pi) - math.pi)
        return d < math.rad(70)
    end
    -- is heading f allowed: not into the wall, and the next spot stays in the area?
    local function fits(f)
        if into_wall(f) then return false end
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
    for _ = 1, 12 do -- try random headings that stay inside and off the wall
        local f = rnd()
        if fits(f) then return f end
    end
    if wall then return wall.facing + math.pi + (math.random() * 2 - 1) * math.pi / 4 end
    if not anchor or r <= 0 then return rnd() end
    return heading_to(pos, anchor) + (math.random() * 2 - 1) * math.pi / 4
end

-- mode: false/nil = keep heading, true = stuck (turn 90-180 degrees),
-- 'reverse' = rough 180 (plus or minus 30 degrees) away from undiggable ground
local function start_moving(mode, dist)
    local pos = get_pos()
    if not pos then return end
    if mode == 'side' then -- turn left or right (90-120 degrees)
        local sign = math.random() < 0.5 and -1 or 1
        turn_by(sign * (math.pi / 2 + math.random() * math.pi / 6))
        turn_until = os.clock() + 0.25
    elseif mode == 'away' then -- face away from the last wall (120-240 degrees from it)
        local base = S.wall and S.wall.facing or ((get_me() or {}).facing or 0)
        windower.ffxi.turn((base + math.pi + (math.random() * 2 - 1) * math.pi / 3) % (2 * math.pi))
        turn_until = os.clock() + 0.25
    elseif mode == 'roam' then
        local f = roam_heading(pos)
        if f then
            windower.ffxi.turn(f % (2 * math.pi))
            turn_until = os.clock() + 0.25 -- finish turning before running
        end
    elseif mode == 'reverse' then
        turn_by(math.pi + (math.random() * 2 - 1) * math.pi / 6)
    elseif mode then
        local sign = math.random() < 0.5 and -1 or 1
        turn_by(sign * (math.pi / 2 + math.random() * math.pi / 2))
    end
    move_target = dist or settings.required_distance
    S.move_mode = tostring(mode)
    dbg('MOVE', ('start %s, %.0f yalms'):format(S.move_mode, move_target))
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
-- leftover from an older 15-second limit on the can't-dig-here message; no longer used
local bad_ground_log = 0

-- far enough from the last dig (or allowed to dig here after bad ground / a wall)?
local function can_dig_here()
    if not last_dig_pos then return true end
    local pos = get_pos()
    if not pos then return false end
    local d = dist2d(pos, last_dig_pos)
    -- a retry (wall, refused dig) may dig short of the full distance, but
    -- never closer than min_distance to the last dig
    if retry_here or S.ran then return d >= (settings.min_distance or 2) end
    return d >= settings.required_distance
end

-- stop auto-digging and say why
local function stop_addon(reason)
    S.running, S.paused = false, false
    auto_wait, retry_here = nil, false
    stop_moving()
    save_life(true)
    log(('Stopped%s Finds this session: %d'):format(reason and (': ' .. reason) or '.', S.successes))
end

-- start auto-digging (or resume if paused): set up the area, campaign test
-- and zone wait, and say what timing will be used
local function start_addon()
    if S.running and S.paused then
        S.paused = false
        log('Resumed.')
        return
    end
    if S.running then return end
    roll_day()
    -- already at today's find limit: don't start (and waste a dig) just to stop
    if settings.max_success > 0 and today().finds >= settings.max_success then
        log(('Already at %d finds today (limit %d). It resets at midnight in Japan; //bup set max to change it.'):format(
            today().finds, settings.max_success))
        return
    end
    S.running, S.paused, next_dig = true, false, 0
    anchor, need_spin = get_pos(), false -- stay around where you started
    bad_streak, blocked_count, wall_hit = 0, 0, false
    S.wall = nil
    local wd = wing_delay()
    hyper_test = nil
    if hyper_mode == 'on' then S.hyper = true
    elseif hyper_mode == 'off' then S.hyper = false
    elseif campaign_now() then
        S.hyper = nil -- your campaign dates cover today: no need to test
    else
        S.hyper = nil
        if (wd or 15) > K.HYPER_DELAY then hyper_test = 'need_base' end -- campaign would speed us up: test it
    end
    log('Started. Be mounted on your chocobo.' ..
        (wd and (' Wing Skill cooldown %ds.'):format(wd)
            or ' Wing Skill unknown, so using the slowest cooldown (15s). Set it with //bup wing <level>.') ..
        (hyper_test and ' Checking for a Hyper Chocobo Digging Campaign on the second dig.' or '') ..
        ((hyper_mode == 'auto' and campaign_now()) and (' Hyper Campaign on (%s - %s).'):format(
            fmt_md(settings.hyper_start), fmt_md(settings.hyper_end)) or (S.hyper and ' Hyper Campaign set on.' or '')))
    local zw = zone_wait_left()
    if zw > 0 then
        log(('Just zoned: waiting %ds before the first dig (area delay for your Wing rank). If a Hyper Campaign is on, //bup hyper on.'):format(math.ceil(zw)))
    end
end

-- The ground here can't be dug (the game refused, or never answered):
-- turn roughly around, go a short way, and dig again there.
local last_ok_t = 0 -- os.clock() when the last dig that got a result was sent

-- how long results take to arrive (seconds), last 30 digs
local latency = {}
-- record how long one dig result took (keeps the last 30)
local function add_latency(v)
    if v <= 0 or v > 30 then return end
    latency[#latency + 1] = v
    if #latency > 30 then table.remove(latency, 1) end
end

-- the no-result wait: 90th-percentile result time + 1.5s, kept between 3 and 12s
local wait_bump = 0 -- raised after each no-result, eased off as results arrive

-- how long to wait for a dig result before deciding none is coming
local function result_wait()
    if not settings.auto_tune then return settings.result_timeout end
    if #latency < 5 then return math.max(settings.result_timeout, wait_bump) end
    local sorted = {}
    for i, v in ipairs(latency) do sorted[i] = v end
    table.sort(sorted)
    local p90 = sorted[math.max(1, math.ceil(#sorted * 0.9))]
    return math.max(3, math.min(12, math.max(p90 + 1.5, wait_bump)))
end
local bad_streak = 0 -- "can't dig here" in a row, reset by any real dig result

-- the test dig at campaign speed got no answer: no campaign. Dig again here
-- once the normal cooldown since the last real dig has passed.
local function hyper_failed()
    S.hyper, hyper_test = false, nil
    auto_wait = nil
    last_dig_pos = prev_dig_pos
    retry_here = true
    next_dig = last_ok_t + dig_delay() + 0.3 + settings.extra_wait
    log(('No Hyper Chocobo Digging Campaign detected. Digging every %ds.'):format(dig_delay()))
end

local gave_up_spot = nil -- where we gave up waiting; used if the result turns up late
local gave_up_t = nil    -- when that given-up dig was sent

-- a dig failed: 'game said no' (You cannot dig here.) or 'no result'.
-- Counts toward the 7-in-a-row stop, then moves away to try somewhere else.
local function bad_ground(why)
    if hyper_test == 'probing' then
        -- no answer at all to the campaign test dig = the game wouldn't dig that
        -- soon: no campaign. But "You cannot dig here." only means bad ground,
        -- so treat it that way and run the test again on the next spot.
        if why == 'no result' then hyper_failed() return end
        hyper_test = 'probe_next'
        dbg('HYPER', 'test dig landed on bad ground; testing again on the next spot')
    end
    -- stop waiting, but keep S.pending: a result that turns up late
    -- (within 12s of the dig) is still recorded
    -- no answer in time: maybe the connection is slow. Wait 50% longer next
    -- time (up to 12s) so a slow result isn't mistaken for bad ground again.
    if settings.auto_tune and why == 'no result' then
        wait_bump = math.min(12, result_wait() * 1.5)
    end
    -- only a dig that got no answer at all can still have a result coming.
    -- A refusal ("You cannot dig here.") IS that dig's answer, so it must not
    -- be remembered as waiting, or the next real result gets pinned on it.
    if why == 'no result' then
        gave_up_t = auto_wait
        gave_up_spot = last_dig_pos
    end
    auto_wait = nil
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
    -- a refused dig ("You cannot dig here.") never happened, so it doesn't start
    -- the cooldown: the next dig can go as soon as the last real dig allows
    if why ~= 'no result' then
        if S.prev_wait then auto_wait, S.prev_wait = S.prev_wait, nil end -- the older dig is still coming
        local last_real = math.max(last_ok_t, auto_wait or 0)
        next_dig = math.max(os.clock(), last_real + dig_delay() + (S.pad or 0.15) + settings.extra_wait)
    end
    -- already moved on from that spot during the dig (movedig)? dig where we are
    local here = get_pos()
    local moved_on = here and last_dig_pos and dist2d(here, last_dig_pos) >= settings.turn_distance
    last_dig_pos = prev_dig_pos -- that spot wasn't a real dig
    retry_here = true
    if moved_on then
        log(('Can\'t dig there (%s); already moved on, digging here next. (%d/%d)'):format(
            why, bad_streak, settings.bad_ground_limit))
        return
    end
    do
        log(('Can\'t dig here (%s). Turning around and trying a few yalms away. (%d/%d)'):format(
            why, bad_streak, settings.bad_ground_limit))
    end
    -- several refusals in a row = a patch of bad ground: don't just bounce
    -- back and forth. 1st: turn around; after that: turn left or right and go
    -- 2 yalms further each time.
    local pos = get_pos()
    local dist = settings.turn_distance + (bad_streak - 1) * 2
    if S.wall and pos and dist2d(pos, S.wall.pos) < 6 then
        start_moving('away', dist) -- near a wall: away from it, not just about-face
    elseif bad_streak <= 1 then
        start_moving('reverse', dist)
    else
        start_moving('side', dist)
    end
end

-- send /dig and schedule the earliest next dig from the cooldown
local function attempt_dig()
    stop_moving()
    prev_dig_pos, last_dig_pos = last_dig_pos, get_pos()
    if last_dig_pos then
        dbg('DIG', prev_dig_pos and ('%.1f yalms from the last dig'):format(dist2d(last_dig_pos, prev_dig_pos)) or 'first dig')
    end
    retry_here = false
    S.ran = false -- no run started for this dig yet
    need_spin = true
    -- running during the dig: face the next heading NOW, while standing still
    -- (turning doesn't move the dig), so the run can start the instant the
    -- game has the dig and use all of the second before the animation stops it
    if settings.run_during_dig and last_dig_pos then
        if wall_hit then
            local base = S.wall and S.wall.facing or ((get_me() or {}).facing or 0)
            windower.ffxi.turn((base + math.pi + (math.random() * 2 - 1) * math.pi / 3) % (2 * math.pi))
            wall_hit = false
        else
            local f = roam_heading(last_dig_pos)
            if f then windower.ffxi.turn(f % (2 * math.pi)) end
        end
        need_spin = false
    end
    -- movedig: the previous dig's result may still be coming (results take ~4s,
    -- the cooldown is shorter). Remember it so its result is matched to it.
    if auto_wait then S.prev_wait = auto_wait end
    auto_wait = os.clock()
    if hyper_test == 'probe_next' then hyper_test = 'probing' end
    -- the next dig: right on the cooldown (Wing Skill or campaign) plus a small
    -- margin that BirdUp learns from "You must wait longer" (S.pad)
    S.pad = S.pad or 0.15
    local margin = 0.3
    next_dig = os.clock() + dig_delay() + margin + settings.extra_wait + math.random() * settings.humanize
    windower.send_command('input /dig')
end

---------------------------------------------------------------------------
-- Result tracking
---------------------------------------------------------------------------
local last_find = nil -- {t = os.clock(), free = bool}: the most recent successful dig

-- add a currency reward (conquest points, bayld...) to session, lifetime and today
local function add_currency(cur)
    if not cur then return end
    life.cur[cur[1]] = (life.cur[cur[1]] or 0) + cur[2]
    S.cur[cur[1]] = (S.cur[cur[1]] or 0) + cur[2]
    local td = today()
    td.cur[cur[1]] = (td.cur[cur[1]] or 0) + cur[2]
    life_dirty = true
end

-- add a found item to session, lifetime and today's lists
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
    local now = os.clock()
    -- movedig: two digs can be waiting. Results come back in the order the digs
    -- were sent, so this one belongs to the older dig, unless the newer dig has
    -- been out long enough to have answered itself.
    if S.prev_wait then
        local quickest = 2.5
        for _, v in ipairs(latency) do if v < quickest / 0.8 then quickest = v * 0.8 end end
        if now - S.prev_wait <= 12 and not (auto_wait and now - auto_wait >= quickest) then
            add_latency(now - S.prev_wait)
            last_ok_t = S.prev_wait
            S.prev_wait = nil
            bad_streak, blocked_count = 0, 0
            S.pad = math.max(0.05, (S.pad or 0.15) - 0.02) -- going fine: trim the margin
            return -- the newer dig is still waiting for its own result
        end
        S.prev_wait = nil
    end
    -- Results arrive in the order digs were sent, so if we gave up on a dig
    -- less than 12s ago, this result is that dig's: it was just slow.
    -- ...unless the newer dig has been out long enough to have answered itself
    -- (results take at least ~80% of the quickest one seen): then it's the
    -- newer dig's result, and the old one really never answered.
    if gave_up_t and auto_wait then
        local quickest = 2.5
        for _, v in ipairs(latency) do if v < quickest / 0.8 then quickest = v * 0.8 end end
        if now - auto_wait >= quickest then gave_up_t, gave_up_spot = nil, nil end
    end
    if gave_up_t and now - gave_up_t <= 12 then
        local took = now - gave_up_t
        add_latency(took)
        wait_bump = math.min(12, math.max(wait_bump, took + 1.5)) -- wait at least this long from now on
        log(('That dig worked after all (the result took %.1fs). Recorded it; waiting longer from now on.'):format(took))
        bad_streak, blocked_count = 0, 0
        last_ok_t = gave_up_t
        local spot = gave_up_spot
        gave_up_t, gave_up_spot = nil, nil
        if auto_wait then return end -- a newer dig is still waiting for its own result
        last_dig_pos, retry_here = spot, false
        settle_until = now + settings.result_buffer
        S.pending = nil
        return
    end
    gave_up_t = nil
    S.result_t = now
    if auto_wait then
        last_ok_t = auto_wait
        add_latency(now - auto_wait)
        wait_bump = wait_bump * 0.85 -- results are coming: ease the extra wait back off
        S.pad = math.max(0.05, (S.pad or 0.15) - 0.02) -- going fine: trim the margin
    end
    gave_up_spot = nil
    bad_streak = 0
    blocked_count = 0
    -- the dig animation starts when /dig is sent, so count the settle from then:
    -- the move to the next spot then happens inside the dig cooldown
    -- (dig > move > dig) instead of after it
    settle_until = os.clock() + settings.result_buffer
    S.pending, auto_wait = nil, nil
    if hyper_test == 'need_base' then
        hyper_test = 'probe_next' -- try the next dig at campaign speed
        next_dig = last_ok_t + K.HYPER_DELAY + 0.3 + settings.extra_wait
    elseif hyper_test == 'probing' then
        S.hyper, hyper_test = true, nil
        next_dig = last_ok_t + K.HYPER_DELAY + 0.3 + settings.extra_wait
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
    local z = Z.entry()
    if z then z.discern = z.discern + 1 end
    dbg('RESULT', 'discernment proc')
    S.discern = S.discern + 1
    life.discern = life.discern + 1
    local td = today()
    td.discern = (td.discern or 0) + 1
    life_dirty = true
    save_life(false)
end

-- a dig's result arrived: item = what was found, nil = a miss. Updates every
-- counter, zone stats, fatigue and the stop checks.
local function record(item, cur)
    roll_day()
    dig_answered()
    count_dig()
    local z = Z.entry()
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
    -- the find limit counts today's finds (resets at midnight in Japan, survives reloads)
    if S.running and settings.max_success > 0 and today().finds >= settings.max_success then
        stop_addon(('reached %d finds today.'):format(settings.max_success))
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

-- Typed commands: a /dig marks a dig as waiting for its result.
windower.register_event('outgoing text', function(original)
    if original and original:lower():match('^/dig') then
        dbg('OUT', original)
        -- only remember that a dig was asked for; it's counted once the game
        -- answers with a result (spammed or rejected /digs don't count)
        S.pending = os.clock()
    end
end)

K.STOP_PATTERNS = { -- best-effort; verify wording on your server and extend as needed
    'you do not have any gysahl', "you don't have any gysahl",
    'cannot carry any more', 'inventory is full',
}

-- ground that can't be dug: turn around instead of stopping
-- (best guesses at the wording; if no result arrives at all, that counts too)
K.BAD_GROUND_PATTERNS = {
    'unable to dig', 'cannot dig here', "can't dig here", 'you cannot dig',
    'cannot use that command', "can't use that command", 'cannot use the command',
}

-- Every chat line: dig results, Wing Skill, Discernment, free digs, currency,
-- Records of Eminence, refusals and stop messages are all read here.
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
    if debug_f and (S.running or (S.pending and os.clock() - S.pending < 20)) then
        debug_unknown.note(clean, mode)
    end

    -- Records of Eminence progress (birdup_roe.lua)
    if ROE.handle(clean) then return end

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
            for i = #K.WING_RANKS, 1, -1 do -- a rank name with no number: use the rank's lowest level
                local w = K.WING_RANKS[i]
                if lower:find(w[1]:lower(), 1, true) then
                    if not life.wing or wing_rank(life.wing)[1] ~= w[1] then set_wing(w[2], true) end
                    break
                end
            end
        end
    end

    -- "You must wait longer to perform that action." = dug too soon (cooldown or
    -- the last dig still playing). Not bad ground: wait a moment, dig here again.
    if S.running and auto_wait and lower:find('wait longer to perform', 1, true) then
        if hyper_test == 'probing' then hyper_failed() return end
        -- that dig never happened: go back to waiting on the one before it (if any)
        local had_prev = S.prev_wait ~= nil
        auto_wait, S.prev_wait = S.prev_wait, nil
        last_dig_pos, retry_here = prev_dig_pos, true
        if false then -- (moving during a dig is gone: see move_during_dig)
            if not had_prev then
                -- dug a little before the cooldown was up: add to the learned margin
                S.pad = math.min(1.5, (S.pad or 0.15) + 0.15)
            end
            next_dig = os.clock() + 0.25 -- and try again right away
            dbg('MOVE', ('too soon: margin %.2fs, retrying this spot'):format(S.pad))
        else
            next_dig = math.max(next_dig, os.clock() + 1)
            dbg('MOVE', 'too soon: retrying this spot in 1s')
        end
        return
    end
    if S.running and auto_wait then
        for _, p in ipairs(K.BAD_GROUND_PATTERNS) do
            if lower:find(p, 1, true) then bad_ground('game said no') return end -- (a refused test dig = no campaign)
        end
    end

    if S.running then
        for _, p in ipairs(K.STOP_PATTERNS) do
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
    -- the number in a currency line, e.g. 'You receive 50 bayld' -> 50
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
-- when the gil was last checked for a pending sale
local sale_check_t = 0

-- read 2- and 4-byte little-endian numbers from a game packet
local function u16(data, i) return data:byte(i) + data:byte(i + 1) * 256 end
local function u32(data, i) return u16(data, i) + u16(data, i + 2) * 65536 end

local record_sale -- defined in the block below (keeps its helpers out of the top level)
do
-- Which city's fame applies where you're standing. Each nation's zones are
-- grouped; anywhere else (Norg, Selbina, Rabao...) uses the zone's own name.
local CITY_PARTS = {
    {"d'Oraguille", "San d'Oria"}, {"San d'Oria", "San d'Oria"},
    {'Metalworks', 'Bastok'}, {'Bastok', 'Bastok'},
    {'Heavens Tower', 'Windurst'}, {'Windurst', 'Windurst'},
    {"Ru'Lude", 'Jeuno'}, {'Jeuno', 'Jeuno'},
    {'Aht Urhgan', 'Aht Urhgan'}, {'Al Zahbi', 'Aht Urhgan'},
    {'Adoulin', 'Adoulin'},
}
-- which city's fame applies where you're standing (each nation's zones count as one)
local function current_city()
    local zid = Z.current_zone()
    if not zid then return 'Unknown' end
    local zn = Z.zone_name(zid)
    for _, c in ipairs(CITY_PARTS) do
        if zn:find(c[1], 1, true) then return c[2] end
    end
    return zn
end

local cheaper_told = {} -- "item|city" already warned this session

-- a vendor sale of a dug item went through: save the city price, update the
-- best price, and mention it if another city pays more
record_sale = function(name, qty, gil)
    if qty <= 0 or gil <= 0 then return end
    local unit = math.floor(gil / qty + 0.5)
    local city = current_city()
    cprices[name] = cprices[name] or {}
    local old_here = cprices[name][city]
    cprices[name][city] = unit
    -- the item's main price is the best city price you know
    local best, best_city = 0, nil
    for c, n in pairs(cprices[name]) do if n > best then best, best_city = n, c end end
    local old = prices[name]
    if old ~= best then prices[name] = best end
    if old_here ~= unit or old ~= best then save_prices() end
    life.gil = life.gil + gil
    S.gil = S.gil + gil
    local td = today()
    td.gil = td.gil + gil
    life_dirty = true
    save_life(true)
    -- echo only when the price list changes; a sale at the known price is silent
    if not old_here then
        log(('Price history: %s added at %s gil each in %s (sold %d for %s gil).'):format(
            name, commas(unit), city, qty, commas(gil)))
    elseif old_here ~= unit then
        log(('Price history: %s in %s updated %s -> %s gil each (sold %d for %s gil).'):format(
            name, city, commas(old_here), commas(unit), qty, commas(gil)))
    end
    -- another city pays more (fame differs by city): say so once per item and city
    local other, other_city = 0, nil
    for c, n in pairs(cprices[name]) do if c ~= city and n > other then other, other_city = n, c end end
    if other > unit and not cheaper_told[name .. '|' .. city] then
        cheaper_told[name .. '|' .. city] = true
        log(('Heads up: %s sells for %s gil each in %s, but %s here in %s (%s less each).'):format(
            name, commas(other), other_city, commas(unit), city, commas(other - unit)))
    end
end
end -- record_sale block

-- Packets you send: the dig action (0x01A, also for Dig from the menu) and the
-- vendor sell packets (0x084 pick, 0x085 confirm).
windower.register_event('outgoing chunk', function(id, data)
    -- 0x01A action packet, category 0x11 = chocobo dig. Sent for typed /dig
    -- AND for Dig picked from the menu, so menu digs are tracked too.
    if id == 0x01A and #data >= 12 and u16(data, 11) == 0x11 then
        dbg('PKT', 'dig action sent')
        S.pending = os.clock()
        S.pkt_t = S.pending -- the game has the dig now: safe to start running
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

-- after a confirmed sale, wait (up to 5s) for the gil to arrive and record it
local function check_sales(now)
    if not sale_pending or now - sale_check_t < 0.2 then return end
    sale_check_t = now
    local gil = windower.ffxi.get_items('gil')
    if type(gil) == 'number' and gil > sale_pending.gil0 then
        record_sale(sale_pending.name, sale_pending.count, gil - sale_pending.gil0)
        sale_pending = nil
    elseif now - sale_pending.t > 5 then
        sale_pending = nil -- gil never arrived (sale canceled or refused)
    end
end

---------------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------------
local function tick(now)
    -- has the chocobo actually stopped? (it slides a little after running stops)
    do
        local pos = get_pos()
        if pos and not (S.still_pos and dist2d(pos, S.still_pos) < 0.05) then
            S.still_pos, S.still_since = pos, now -- moved: restart the clock
        end
    end
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
            -- the dig animation stops the chocobo dead about a second after the
            -- dig: that's not a wall. Wait there; the next dig goes from here.
            if auto_wait then
                dbg('MOVE', ('dig animation stopped the run, %.1f yalms from the last dig'):format(
                    (pos and last_dig_pos) and dist2d(pos, last_dig_pos) or 0))
                return
            end
            blocked_count = blocked_count + 1
            -- remember the wall: where it is and which way it faces us
            local me = get_me()
            if pos and me and me.facing then S.wall = {pos = pos, facing = me.facing} end
            dbg('MOVE', ('blocked (%s), count %d, %.1f yalms from the last dig, %.1f moved in the last %.0fs (normal speed %.1f/s)%s'):format(
                why, blocked_count, (pos and last_dig_pos) and dist2d(pos, last_dig_pos) or 0,
                (pos and prog_pos) and dist2d(pos, prog_pos) or 0, settings.stuck_check_time, S.run_speed or 0,
                auto_wait and ', dig playing' or ''))
            -- dig where it stopped, unless that's too close to the last dig
            local far = not (pos and last_dig_pos) or dist2d(pos, last_dig_pos) >= (settings.min_distance or 2)
            if blocked_count == 1 and far then
                retry_here, wall_hit = true, true -- dig where it stopped
            else
                wall_hit = false
                start_moving('away', settings.required_distance)
            end
        end
        -- blocked = less than 40% of your normal running speed (measured as you
        -- go), so grinding along a wall at a shallow angle counts too.
        -- While a dig is still playing the chocobo moves slower, so then only
        -- a real stop (under blocked_progress, 1 yalm a second) counts.
        local rel = auto_wait and 0 or 0.4 * (S.run_speed or 0) * settings.stuck_check_time
        local min_prog = math.max(settings.stuck_epsilon, settings.blocked_progress * settings.stuck_check_time, rel)
        if pos and move_start_pos and dist2d(pos, move_start_pos) >= move_target then
            stop_moving()
            blocked_count = 0
        elseif pos and prog_pos and now - prog_time >= settings.stuck_check_time then
            local moved = dist2d(pos, prog_pos)
            if moved < min_prog then
                blocked('no progress')
            else
                -- learn normal running speed (top speed seen, slowly forgotten)
                local spd = moved / (now - prog_time)
                -- normal running speed = the middle of the last 15 readings (not
                -- the fastest one): speed addons, mount changes and position jumps
                -- can give odd readings, and one fast spike made every normal
                -- second after it look like a wall
                if not auto_wait then
                    local r = S.spd_samples or {}
                    S.spd_samples = r
                    r[#r + 1] = spd
                    if #r > 15 then table.remove(r, 1) end
                    local sorted = {}
                    for i, v in ipairs(r) do sorted[i] = v end
                    table.sort(sorted)
                    S.run_speed = sorted[math.floor(#sorted / 2) + 1]
                end
                prog_time, prog_pos = now, pos
            end
        elseif now - move_start_time >= settings.move_timeout then
            blocked('took too long')
        end
        return
    end

    -- first move after each dig: spin to a new heading that stays in the area
    local function go()
        if need_spin then
            need_spin = false
            if wall_hit then wall_hit = false; start_moving('away') else start_moving('roam') end
        else
            start_moving(false)
        end
    end

    -- our /dig is out: its result arrives when the dig animation ends (~4s).
    -- With movedig on (default) nothing waits for it: BirdUp heads for the next
    -- spot and digs again the moment the cooldown is up.
    -- an older dig that never answered either: stop waiting for it
    -- (it counts as a failed dig, the same as any dig with no answer)
    if S.prev_wait and now - S.prev_wait >= result_wait() then
        local newer = auto_wait
        auto_wait, S.prev_wait = S.prev_wait, nil
        bad_ground('no result')
        if not running then return end
        auto_wait = newer
    end
    if auto_wait then
        if now - auto_wait >= result_wait() then
            S.prev_wait = nil -- nothing is coming for the older one either
            bad_ground('no result') -- nothing came back: treat the spot as undiggable
            return
        end
        -- run during the dig: the game handles the dig the moment its packet
        -- arrives (while we're still standing on the spot), so start running
        -- just after the packet has gone out. The animation stops the chocobo
        -- about a second later, usually 2-5 yalms on, and the next dig goes
        -- from there as soon as the result is in: no extra move or stop.
        if settings.run_during_dig and not S.ran and not moving then
            local sent = S.pkt_t and S.pkt_t >= auto_wait
            if (sent and now >= S.pkt_t + 0.1) or now >= auto_wait + 0.6 then
                S.ran = true
                go()
            end
        end
        return
    end

    -- a short pause after each result before moving on (not needed when the
    -- chocobo already ran during the dig)
    if now < settle_until and not S.ran then return end

    if now < next_dig then
        if not can_dig_here() then go() end
        return
    end

    if can_dig_here() then
        if zone_wait_left() > 0 then return end -- area delay after zoning
        if S.prev_wait then return end -- two digs already waiting on results
        -- one dig at a time: the game silently ignores a /dig sent while the
        -- last dig is still playing (no "wait longer", just nothing), so the
        -- next dig goes right after the last result (the move happens during it)
        if auto_wait or now < (S.result_t or 0) + 0.05 then return end
        -- only dig once the chocobo has really stopped: the game won't dig
        -- while it's still sliding, and that would look like bad ground
        if moving then stop_moving() end
        if now - (S.still_since or 0) < settings.stop_settle then return end
        attempt_dig()
    else
        go()
    end
end

-- when the Japan date was last checked
local day_check = 0

-- Every frame: day change, greens/inventory, the panel (5x a second), sale
-- checks, auto-dig, and saving.
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

-- Zoning stops auto-dig and starts the area-delay timer.
windower.register_event('zone change', function()
    zoned_at = os.clock()
    REW.view = nil -- the rewards window follows you to the new zone
    dbg('ZONE', Z.zone_name(Z.current_zone()))
    if S.running then stop_addon('zone change.') end
end)
-- Logging out: save and stop.
windower.register_event('logout', function()
    if S.running then stop_addon('logout.') end
    save_life(true)
end)
-- Unloading/reloading the addon: save, stop moving, close the debug log.
windower.register_event('unload', function()
    stop_moving(); save_life(true); hud_show(false)
    if debug_f then debug_unknown.close('addon unloaded') end
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

-- is the mouse inside this rectangle?
local function inside(mx, my, x, y, w, h)
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

-- which panel button is under the mouse ('start', 'stop', 'zones'), if any
local function button_at(mx, my)
    if inside(mx, my, px + W - K.ZBTN_W - 6, py + 4, K.ZBTN_W, K.ZBTN_H) then return 'zones' end
    if inside(mx, my, px + W - K.ZBTN_W - K.RBTN_W - 12, py + 4, K.RBTN_W, K.ZBTN_H) then return 'rewards' end
    for key, b in pairs(buttons) do
        if inside(mx, my, px + b.rx, py + K.BTN_Y, BTN_W, K.BTN_H) then return key end
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
        -- the rewards window: its < > buttons, and swallow other clicks on it
        local rh = (not blocked) and REW.hit(mx, my)
        if rh then
            pressed = (rh ~= 'window') and ('rew_' .. rh) or nil
            return true
        end
        if blocked or not inside(mx, my, px, py, W, panel_h) then return end
        pressed = button_at(mx, my)
        if not pressed and inside(mx, my, px, py + items_hdr_y - 2, W, items_hdr_h) then pressed = 'items' end
        if not pressed then
            if settings.locked then return end -- locked: clicks go to the game
            drag = {dx = mx - px, dy = my - py}
        end
        return true
    elseif type == 2 then
        if pressed == 'rew_prev' or pressed == 'rew_next' then
            local key = pressed
            pressed = nil
            if REW.hit(mx, my) == key:sub(5) then
                REW.step(key == 'rew_prev' and -1 or 1, Z.zone_name(Z.current_zone()))
                hud_last = 0
            end
            return true
        end
        if drag then
            drag = nil
            settings.pos.x, settings.pos.y = px, py
            config.save(settings)
            return true
        end
        if pressed then
            local key = pressed
            pressed = nil
            local over = button_at(mx, my)
            if not over and inside(mx, my, px, py + items_hdr_y - 2, W, items_hdr_h) then over = 'items' end
            if over == key then -- released over the same button
                if key == 'items' then
                    settings.collapse_items = not settings.collapse_items
                    config.save(settings)
                elseif key == 'zones' then
                    settings.zone_window = not settings.zone_window
                    config.save(settings)
                elseif key == 'rewards' then
                    settings.rewards_window = not settings.rewards_window
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

-- load everything for the character you're logged in as (on load, login and
-- character change): lifetime, history, zone stats, imports, settings
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
    Z.load()
    Z.load_community()
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

-- Logging in: load that character once its data is available.
windower.register_event('login', function()
    coroutine.schedule(switch_character, 3) -- player data isn't ready instantly
end)

-- The addon was just loaded: say hello and load the current character.
windower.register_event('load', function()
    log(('Author: %s, Version %s'):format('Valdimar @ Phoenix', _addon.version))
    switch_character()
    if not char_name then refresh_visibility(true) end
end)

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------

-- Every setting you can change with //bup set <name> <value>.
-- {name, settings key, kind, description, extra}; kind: num / pct / onoff / text.
-- Old one-word commands (//bup distance 6, //bup cap 150...) still work.
local SETTINGS = {
    groups = {
        {'Auto-dig', {
            {'distance',    'required_distance', 'num',   'yalms to travel between digs'},
            {'rundig',      'run_during_dig',    'onoff', 'run during each dig (much faster); off = wait for the result, then move'},
            {'mindist',     'min_distance',      'num',   'never dig closer than this to the last dig (walls, retries)'},
            {'area',        'roam_radius',       'num',   'stay within this many yalms of the start (0 = no limit)'},
            {'turnchance',  'turn_chance',       'pct',   '% chance to turn after a dig'},
            {'turn',        'turn_distance',     'num',   'yalms to move after undiggable ground'},
            {'settle',      'result_buffer',     'num',   'with movedig off: seconds after a result before moving'},
            {'timer',       'extra_wait',        'num',   'extra seconds on top of the dig cooldown'},
            {'humanize',    'humanize',          'num',   'up to this many random extra seconds per dig (0 = none)'},
            {'tune',        'auto_tune',         'onoff', 'self-tuning no-result wait'},
        }},
        {'Stopping', {
            {'max',         'max_success',       'num',   'stop after this many finds today (0 = never)'},
            {'cap',         'fatigue_cap',       'num',   'your daily fatigue cap'},
            {'stopfatigue', 'stop_at_fatigue',   'onoff', 'stop at the fatigue cap'},
            {'slots',       'min_free_slots',    'num',   'stop at this many free bag slots (0 = off)'},
            {'badlimit',    'bad_ground_limit',  'num',   'stop after this many failed digs in a row (0 = never)'},
            {'stopecho',    'stop_echo',         'text',  'extra line echoed when that happens ("off" = none)'},
            {'mount',       'require_mount',     'onoff', 'stop when not on a chocobo'},
        }},
        {'Panel', {
            {'autohide',    'auto_hide',         'onoff', 'only show the panel while on a chocobo'},
            {'warngreens',  'warn_greens',       'num',   'flash the panel at this many greens (0 = off)'},
            {'warnslots',   'warn_slots',        'num',   'flash the panel at this many free slots (0 = off)'},
            {'spacing',     'line_spacing',      'num',   'pixels between panel lines'},
        }},
    },
    by_name = {},
}
function SETTINGS.index() -- (in a function: loop variables don't count toward the top-level limit)
    for _, g in ipairs(SETTINGS.groups) do
        for _, d in ipairs(g[2]) do SETTINGS.by_name[d[1]] = d end
    end
    SETTINGS.by_name.jitter = SETTINGS.by_name.humanize -- older name
end
SETTINGS.index()

-- on / off / toggle from a word ("on", "off", "true", "1"...); nil word = toggle
function SETTINGS.bool(word, current)
    word = (word or ''):lower()
    if word == 'on' or word == 'true' or word == 'yes' or word == '1' then return true end
    if word == 'off' or word == 'false' or word == 'no' or word == '0' then return false end
    if word == '' or word == 'toggle' then return not current end
    return nil
end

-- a setting's current value as text: on/off, 50%, "text" or a number
function SETTINGS.show_value(d)
    local v = settings[d[2]]
    if d[3] == 'onoff' then return v and 'on' or 'off' end
    if d[3] == 'pct' then return tostring(v) .. '%' end
    if d[3] == 'text' then return (v and v ~= '') and ('"' .. v .. '"') or '(none)' end
    return tostring(v)
end

-- //bup set with nothing after it: every setting, grouped, with its value
function SETTINGS.show()
    log(('Settings for %s (//bup set <name> <value>):'):format(char_name or '?'))
    for _, g in ipairs(SETTINGS.groups) do
        log(g[1] .. ':')
        for _, d in ipairs(g[2]) do
            local v = SETTINGS.show_value(d)
            if #v > 24 then v = v:sub(1, 21) .. '..."' end -- long text: //bup set <name> shows it all
            log(('  %-12s %-10s %s'):format(d[1], v, d[4]))
        end
    end
end

-- //bup set <name> <value...>
function SETTINGS.set(name, args)
    local d = SETTINGS.by_name[(name or ''):lower()]
    if not d then
        if not name or name == '' then return SETTINGS.show() end
        local names = {}
        for _, g in ipairs(SETTINGS.groups) do for _, x in ipairs(g[2]) do names[#names + 1] = x[1] end end
        log(('No setting called "%s". Settings: %s. (//bup set lists them with values.)'):format(name, table.concat(names, ', ')))
        return
    end
    local raw = table.concat(args, ' ')
    if raw == '' and d[3] ~= 'onoff' then
        log(('%s is %s (%s).'):format(d[1], SETTINGS.show_value(d), d[4]))
        return
    end
    if d[3] == 'onoff' then
        local v = SETTINGS.bool(args[1], settings[d[2]])
        if v == nil then log(('Usage: //bup set %s on|off'):format(d[1])) return end
        settings[d[2]] = v
    elseif d[3] == 'text' then
        settings[d[2]] = raw:lower() == 'off' and '' or raw
    else
        local n = tonumber(args[1])
        if not n or n < 0 or (d[3] == 'pct' and n > 100) then
            log(('Usage: //bup set %s <%s>'):format(d[1], d[3] == 'pct' and '0-100' or 'number'))
            return
        end
        settings[d[2]] = n
    end
    config.save(settings)
    if d[2] == 'auto_hide' then refresh_visibility(true) end
    hud_last = 0
    log(('%s: %s'):format(d[1], SETTINGS.show_value(d)))
end

-- panel switches: //bup hud | compact | items | lock | zones [on|off]
SETTINGS.panel = {
    hud     = {'hud_visible',    'Panel'},
    compact = {'compact',        'Compact mode'},
    items   = {'collapse_items', 'Item list collapsed'},
    lock    = {'locked',         'Panel lock'},
    zones   = {'zone_window',    'Zone stats window'},
    zonewin = {'zone_window',    'Zone stats window'},   -- older name
}

-- //bup help [topic]: a short overview, details per topic
SETTINGS.help_text = {
    overview = {
        'BirdUp commands (//bup ...). For details: //bup help dig | info | share | panel | set',
        '  start / stop / pause      control auto-digging',
        '  status  finds  history  zone  prices  currency  wing    information',
        '  hyper  anchor  fatigue                                  while digging',
        '  export  import  debug                                   sharing and troubleshooting',
        '  hud  compact  items  lock  zones  rewards  view         the panel',
        '  set [name value]          see or change any setting',
        '  reload  reset  saveall                                  housekeeping',
    },
    dig = {
        'start / stop / pause    start, stop or pause auto-digging (or use the panel buttons)',
        'anchor                  center the digging area on where you are now',
        'fatigue [n | reset]     show, set or reset today\'s fatigue count',
        'wing [level]            show or set your Wing Skill (skill-ups in chat update it)',
        'hyper                   show the Hyper Campaign status',
        'hyper Oct16-Nov9        save campaign dates (hyper dates / hyper dates clear)',
        'hyper on | off | auto   force it on/off until reload, or go back to testing',
        'tune                    show measured dig-result times and the no-result wait',
    },
    info = {
        'status                  one-line summary of this session',
        'finds                   every item in the panel list, in chat',
        'history [days | date]   daily log: history, history 14, history 20261110, history today',
        'zone [all]              drop rates here (or everywhere) at your Wing rank',
        'prices                  vendor prices, per city',
        'price <item> <gil>      set a price by hand (0 clears)',
        'prices clean            drop prices for items no character has dug',
        'currency                conquest points, Imperial Standing, allied notes, bayld',
    },
    share = {
        'export                  write your zone drop stats to a shareable .csv + .txt',
        'import [file]           add other players\' exports from data/import/',
        'import list | clear     list or remove imported players',
        'debug on | off          record dig chat to a dated file (ends with unrecognized lines)',
    },
    panel = {
        'hud [on|off]            show or hide the panel',
        'compact [on|off]        only the key rows',
        'items [on|off]          collapse the item list (or click ITEMS FOUND)',
        'lock [on|off]           stop the panel being dragged',
        'zones [on|off]          the zone stats window (or click ZONES)',
        'rewards [on|off]        what each zone can give, by rarity (or click REWARDS)',
        'rewards <zone> / here   show another zone / back to the zone you\'re in',
        'rewards list            every zone with digging data',
        'view today | lifetime   which totals the item list shows',
        'Without on/off, each of these switches between the two.',
    },
}

-- //bup help [topic]
function SETTINGS.help(topic)
    topic = (topic or ''):lower()
    if topic == 'set' or topic == 'settings' then return SETTINGS.show() end
    for _, l in ipairs(SETTINGS.help_text[topic] or SETTINGS.help_text.overview) do log(l) end
end

-- //bup commands: one small function per command (keeps each under LuaJIT's
-- 60-outside-variable limit). Each entry: {matches(cmd, a), run(cmd, a)}.
local COMMANDS = {}
-- //bup help [topic]
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'help' or cmd == '?' end, function(cmd, a)
    SETTINGS.help(a[1])
end}
-- //bup set [name [value]] (also 'settings', and the old 'profile')
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'set' or cmd == 'settings' or cmd == 'profile' end, function(cmd, a)
    local name = table.remove(a, 1)
    SETTINGS.set(name, a)
end}
-- old one-word setting commands: //bup distance 6 == //bup set distance 6
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return SETTINGS.by_name[cmd] ~= nil and cmd ~= 'tune' end, function(cmd, a)
    SETTINGS.set(cmd, a)
end}
-- older two-number form: //bup warn <greens> <slots>
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'warn' end, function(cmd, a)
    if a[1] then SETTINGS.set('warngreens', {a[1]}) end
    if a[2] then SETTINGS.set('warnslots', {a[2]}) end
    if not a[1] then
        log(('Panel warnings at %d greens and %d free slots (0 = off).'):format(settings.warn_greens, settings.warn_slots))
    end
end}
-- //bup hud | compact | items | lock | zones [on|off]
-- //bup rewards [on|off | here | list | <zone>]: digging rewards by zone
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'rewards' or cmd == 'reward' end, function(cmd, a)
    local arg = table.concat(a, ' ')
    local low = arg:lower()
    if low == 'list' then
        local names = {}
        for _, z in ipairs(REW.zones) do names[#names + 1] = z.name end
        log(('Digging rewards for %d zones: %s'):format(#names, table.concat(names, ', ')))
        return
    end
    if low == 'here' then
        REW.view = nil
        settings.rewards_window = true
    elseif low == '' or low == 'on' or low == 'off' or low == 'toggle' then
        settings.rewards_window = SETTINGS.bool(low, settings.rewards_window)
    else
        local z = REW.find(arg)
        if not z then log(('No digging data for "%s". //bup rewards list shows every zone.'):format(arg)) return end
        REW.view = z
        settings.rewards_window = true
    end
    config.save(settings)
    hud_last = 0
    log('Rewards window: ' .. (settings.rewards_window and 'on' or 'off') ..
        (settings.rewards_window and REW.view and (' (' .. REW.view.name .. ')') or ''))
end}
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return SETTINGS.panel[cmd] ~= nil end, function(cmd, a)
    local t = SETTINGS.panel[cmd]
    local v = SETTINGS.bool(a[1], settings[t[1]])
    if v == nil then log(('Usage: //bup %s [on|off]'):format(cmd)) return end
    settings[t[1]] = v
    config.save(settings)
    if cmd == 'hud' then refresh_visibility(true) end
    hud_last = 0
    log(('%s: %s%s'):format(t[2], v and 'on' or 'off',
        (cmd == 'hud' and v and settings.auto_hide) and ' (shows while on a chocobo; //bup set autohide off to always show)' or ''))
end}
-- //bup reload: save everything, then reload the addon
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'reload' end, function(cmd, a)
        if S.running then stop_addon('reloading.') end
        save_life(true)          -- lifetime + today's history
        save_prices()
        config.save(settings)
        log('Reloading...')
        windower.send_command('lua reload ' .. _addon.name)
        return
end}
-- //bup start (same as the START button)
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'start' end, function(cmd, a)
        start_addon()
end}
-- //bup stop (same as the STOP button)
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'stop' end, function(cmd, a)
        stop_addon(nil)
end}
-- //bup pause: pause or resume auto-dig
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'pause' end, function(cmd, a)
        if not S.running then log('Not running.') return end
        S.paused = not S.paused
        stop_moving()
        auto_wait = nil
        if hyper_test == 'probing' then hyper_test = 'probe_next' end
        log(S.paused and 'Paused.' or 'Resumed.')
end}
-- //bup reset: clear this session's counters (today's items and fatigue stay)
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'reset' end, function(cmd, a)
        S.attempts, S.successes, S.fails, S.free, S.drops, S.first_dig, S.cur, S.gil = 0, 0, 0, 0, {}, nil, {}, 0
    S.discern = 0
        log('Session stats reset. (Today\'s items and daily fatigue are kept; they clear at midnight JST.)')
end}
-- //bup status: one-line summary
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'status' end, function(cmd, a)
        log(('running=%s attempts=%d finds=%d misses=%d discern=%d hyper=%s greens=%s inventory=%s/%s'):format(
            tostring(S.running), S.attempts, S.successes, S.fails, S.discern, tostring(S.hyper), tostring(greens),
            tostring(inv_used), tostring(inv_max)))
end}
-- //bup anchor: center the digging area here
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'anchor' end, function(cmd, a)
        anchor = get_pos()
        log(anchor and ('Digging area centered here (%d yalm radius).'):format(settings.roam_radius) or 'Position unknown.')
end}
-- //bup fatigue [n | reset]
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'fatigue' end, function(cmd, a)
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
end}
-- //bup price <item> <gil>: set a price by hand (0 clears)
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'price' end, function(cmd, a)
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
end}
-- //bup prices clean: drop prices for items no character has dug
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'prices' and (a[1] or ''):lower() == 'clean' end, function(cmd, a)
        local dug = all_dug_names() -- items any character has dug up
        local removed = {}
        for name in pairs(prices) do if not dug[name] then removed[#removed + 1] = name end end
        for _, name in ipairs(removed) do prices[name] = nil end
        for name in pairs(cprices) do if not dug[name] then cprices[name] = nil end end
        save_prices()
        log(('Removed %d price%s for items nobody has dug up%s'):format(#removed, #removed == 1 and '' or 's',
            #removed > 0 and (': ' .. table.concat(removed, ', ')) or '.'))
end}
-- //bup debug on | off
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'debug' end, function(cmd, a)
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
                Z.zone_name(Z.current_zone()), tostring(life.wing), tostring(S.hyper)))
            debug_f:flush()
            log('Debug log on: addons/birdup/' .. debug_path .. ' (chat while auto-digging or near a dig, plus BirdUp\'s decisions).')
        elseif v == 'off' then
            if not debug_f then log('Debug log is off.') return end
            local n = debug_unknown.close('debug off')
            log(('Debug log saved: addons/birdup/%s%s'):format(debug_path,
                n > 0 and (' (%d unrecognized line%s listed at the end)'):format(n, n == 1 and '' or 's') or ''))
        else
            log(debug_f and ('Debug log on: addons/birdup/' .. debug_path) or 'Debug log off. //bup debug on to start one.')
        end
end}
-- //bup tune [on|off]: measured result times and the current no-result wait
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'tune' end, function(cmd, a)
        local v = (a[1] or ''):lower()
        if v ~= '' then
            local b = SETTINGS.bool(v, settings.auto_tune)
            if b ~= nil then settings.auto_tune = b; config.save(settings) end
        end
        local avg = 0
        for _, x in ipairs(latency) do avg = avg + x end
        avg = #latency > 0 and avg / #latency or 0
        log(('Auto-tune %s. Results measured: %d (avg %.1fs). No-result wait now %.1fs%s.'):format(
            settings.auto_tune and 'on' or 'off', #latency, avg, result_wait(),
            (settings.auto_tune and #latency < 5) and ' (needs 5 digs to start tuning)' or ''))
        log(('Dig timing: every %ds cooldown + %.2fs margin (learned from "wait longer")%s.'):format(
            dig_delay(), S.pad or 0.15, settings.humanize > 0 and (' + up to %.1fs random'):format(settings.humanize) or ''))
end}
-- //bup import [file | list | clear]
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'import' end, function(cmd, a)
        local v = a[1] or ''
        local imp = windower.addon_path .. 'data/import/'
        windower.create_dir(windower.addon_path .. 'data')
        windower.create_dir(imp)
        if v:lower() == 'list' then
            local n = 0
            for _, file in ipairs(windower.get_dir(Z.community_dir()) or {}) do
                if file:match('%.txt$') then
                    local one = {}
                    Z.read_zone_file(Z.community_dir() .. file, one)
                    local digs, zones = 0, 0
                    for _, ranks in pairs(one) do zones = zones + 1; for _, e in pairs(ranks) do digs = digs + e.digs end end
                    log(('  player %s: %s digs in %d zone%s'):format(file:gsub('%.txt$', ''), commas(digs), zones, zones == 1 and '' or 's'))
                    n = n + 1
                end
            end
            if n == 0 then log('No imported players yet. Put export .csv files in addons/birdup/data/import/ and //bup import.') end
            return
        elseif v:lower() == 'clear' then
            local n = 0
            for _, file in ipairs(windower.get_dir(Z.community_dir()) or {}) do
                if file:match('%.txt$') and os.remove(Z.community_dir() .. file) then n = n + 1 end
            end
            Z.load_community()
            log(('Removed %d imported player%s. Your own stats are untouched.'):format(n, n == 1 and '' or 's'))
            return
        end
        local files = {}
        if v ~= '' then
            local name = table.concat(a, ' ')
            if not name:lower():match('%.csv$') then name = name .. '.csv' end
            files[1] = name
        else
            for _, file in ipairs(windower.get_dir(imp) or {}) do
                if file:lower():match('%.csv$') then files[#files + 1] = file end
            end
        end
        if #files == 0 then
            log('Nothing to import. Put export .csv files in addons/birdup/data/import/, then //bup import.')
            return
        end
        local ok_n = 0
        for _, file in ipairs(files) do
            local ok, msg = Z.import_file(imp .. file, file)
            log((ok and 'Imported ' or 'Skipped ') .. msg)
            if ok then ok_n = ok_n + 1 end
        end
        Z.load_community()
        hud_last = 0
        if ok_n > 0 then log('The zone window and //bup zone now show all players next to your own rates.') end
end}
-- //bup zone window [on|off]
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'zone' and ((a[1] or ''):lower() == 'window' or (a[1] or ''):lower() == 'win') end, function(cmd, a)
    local v = SETTINGS.bool(a[2], settings.zone_window)
    if v == nil then log('Usage: //bup zone window [on|off]') return end
    settings.zone_window = v
    config.save(settings)
    hud_last = 0
    log('Zone stats window: ' .. (v and 'on' or 'off'))
end}
-- //bup zone [all]: drop stats here (or everywhere) at your Wing rank
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'zone' end, function(cmd, a)
        -- print one zone's stats per Wing rank, top items with their rates
        local function summary(zid, ranks)
            for rank, e in pairs(ranks) do
                if e.digs > 0 then
                    log(('%s (%s): %d digs, %d finds (%d%%), %d miss, %d discern'):format(Z.zone_name(zid), rank,
                        e.digs, e.finds, math.floor(e.finds / e.digs * 100 + 0.5), e.miss, e.discern))
                    local all = Z.combined(zid, rank)
                    if all then
                        log(('  All players: %s digs, %d%% hit. Columns: yours, then all players.'):format(
                            commas(all.digs), math.floor(all.finds / all.digs * 100 + 0.5)))
                    end
                    local list = {}
                    for item, n in pairs(e.items) do list[#list + 1] = {item, n} end
                    table.sort(list, function(x, y) return x[2] > y[2] end)
                    for i = 1, math.min(#list, (a[1] or '') == 'all' and 5 or 12) do
                        log(('  %-24s %5d  %5.1f%%%s'):format(list[i][1], list[i][2], list[i][2] / e.digs * 100,
                            all and ('   %5.1f%%'):format((all.items[list[i][1]] or 0) / all.digs * 100) or ''))
                    end
                end
            end
        end
        if (a[1] or ''):lower() == 'all' then
            local n = 0
            for zid, ranks in pairs(Z.stats()) do summary(zid, ranks); n = n + 1 end
            if n == 0 then log('No zone stats yet.') end
        else
            local zid = Z.current_zone()
            if not zid or not Z.stats()[zid] then log('No digs recorded in this zone yet.') return end
            summary(zid, Z.stats()[zid])
        end
end}
-- //bup export: all characters' zone stats -> data/export/*.csv + *.txt
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'export' end, function(cmd, a)
        -- combine every character's zone stats into one shareable report + CSV
        save_life(true)
        local all, chars = {}, 0
        local dir = windower.addon_path .. 'data/'
        for _, file in ipairs(windower.get_dir(dir) or {}) do
            if file:match('^zones_.+%.txt$') then Z.read_zone_file(dir .. file, all); chars = chars + 1 end
        end
        local rows_out, total_digs, zones_n = {}, 0, 0
        local rank_order = {}
        for i, w in ipairs(K.WING_RANKS) do rank_order[w[1]] = i end
        local zids = {}
        for zid in pairs(all) do zids[#zids + 1] = zid end
        table.sort(zids, function(x, y) return Z.zone_name(x) < Z.zone_name(y) end)
        if #zids == 0 then log('Nothing to export yet: dig somewhere first.') return end
        windower.create_dir(dir .. 'export')
        local stamp = os.date('%Y%m%d_%H%M%S')
        local csv_rel, txt_rel = 'data/export/birdup_drops_' .. stamp .. '.csv', 'data/export/birdup_drops_' .. stamp .. '.txt'
        local csv = io.open(windower.addon_path .. csv_rel, 'w')
        local txt = io.open(windower.addon_path .. txt_rel, 'w')
        if not csv or not txt then log('Could not write the export files.') return end
        -- quote a CSV field if it contains a comma or quote
        local function q(v) v = tostring(v); return v:find('[,"]') and ('"' .. v:gsub('"', '""') .. '"') or v end
        csv:write('zone,wing_rank,zone_digs,zone_finds,zone_miss,zone_discern,item,count,percent_of_digs,vendor_price,source_id\n')
        local sid = Z.get_my_id()
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
                        Z.zone_name(zid), rank, e.digs, e.finds, e.finds / e.digs * 100, e.miss, e.discern)
                    local list = {}
                    for item, n in pairs(e.items) do list[#list + 1] = {item, n} end
                    table.sort(list, function(x, y) return x[2] > y[2] end)
                    for _, it in ipairs(list) do
                        local pct = it[2] / e.digs * 100
                        csv:write(('%s,%s,%d,%d,%d,%d,%s,%d,%.2f,%s,%s\n'):format(q(Z.zone_name(zid)), q(rank), e.digs, e.finds,
                            e.miss, e.discern, q(it[1]), it[2], pct, prices[it[1]] and tostring(prices[it[1]]) or '', sid))
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
end}
-- //bup hyper [on | off | auto | <dates> | dates [clear]]
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'hyper' end, function(cmd, a)
        local v = (a[1] or ''):lower()
        local rest = table.concat(a, ' ', v == 'dates' and 2 or 1)
        if v == 'on' then S.hyper, hyper_test, hyper_mode = true, nil, 'on'
        elseif v == 'off' then S.hyper, hyper_test, hyper_mode = false, nil, 'off'
        elseif v == 'test' or v == 'auto' then S.hyper, hyper_test, hyper_mode = nil, 'need_base', 'auto'
        elseif v == 'dates' or rest:find('%-') or rest:lower():find('to') then
            if rest == '' then
                log(settings.hyper_start > 0 and ('Hyper Campaign dates: %s - %s (Japan dates)%s.'):format(
                    fmt_md(settings.hyper_start), fmt_md(settings.hyper_end), campaign_now() and ', active today' or '')
                    or 'No Hyper Campaign dates set. Example: //bup hyper Oct16-Nov9')
                return
            elseif rest:lower() == 'clear' then
                settings.hyper_start, settings.hyper_end = 0, 0
                config.save(settings)
                log('Hyper Campaign dates cleared. Back to testing on each start.')
                return
            end
            local st, en = parse_campaign(rest)
            if not st then log('Couldn\'t read those dates. Examples: //bup hyper Oct16-Nov9, //bup hyper 10/16-11/9') return end
            settings.hyper_start, settings.hyper_end = st, en
            config.save(settings)
            hyper_mode, hyper_test = 'auto', nil
            log(('Hyper Campaign dates saved: %s - %s %d (Japan dates). %s'):format(fmt_md(st), fmt_md(en),
                math.floor(en / 10000), campaign_now() and 'Active now: digging at campaign speed.'
                or (jst_today() < st and 'Starts later; BirdUp switches on by itself.' or 'Already over.')))
            hud_last = 0
            return
        end
        log(('Hyper Chocobo Digging Campaign: %s. Digging every %ds.'):format(
            hyper_test and 'will test on the next digs' or (hyper_on() and 'active' or (S.hyper == false and 'not active' or 'not tested')),
            dig_delay()))
end}
-- //bup wing [level]
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'wing' end, function(cmd, a)
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
end}
-- //bup history [days | yyyymmdd | today]
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'history' end, function(cmd, a)
        today()
        -- 20261110 -> '2026-11-10'
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
                e.wing and (', Wing Skill ' .. e.wing) or '') ..
                ((e.roe or 0) > 0 and (', %d RoE dig objective%s done'):format(e.roe, e.roe == 1 and '' or 's') or ''))
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
end}
-- //bup prices: every known price, with each city's price
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'prices' end, function(cmd, a)
        local list = {}
        for name, pr in pairs(prices) do list[#list + 1] = {name, pr} end
        table.sort(list, function(x, y) return x[2] > y[2] end)
        log(('Known prices (%d). Gil from sales: %s lifetime, %s today.'):format(
            #list, commas(life.gil), commas(today().gil)))
        for _, e in ipairs(list) do
            local by_city = {}
            for c, n in pairs(cprices[e[1]] or {}) do by_city[#by_city + 1] = {c, n} end
            table.sort(by_city, function(x, y) return x[2] > y[2] end)
            local parts = {}
            for _, c in ipairs(by_city) do parts[#parts + 1] = c[1] .. ' ' .. commas(c[2]) end
            log(('  %-28s %s gil%s'):format(e[1], commas(e[2]),
                #parts > 0 and ('  (' .. table.concat(parts, ', ') .. ')') or ''))
        end
end}
-- //bup currency: lifetime and today's currency rewards
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'currency' end, function(cmd, a)
        local names = {cp = 'Conquest points', imperial = 'Imperial Standing', allied = 'Allied notes', bayld = 'Bayld'}
        for _, key in ipairs({'cp', 'imperial', 'allied', 'bayld'}) do
            log(('  %-18s lifetime %s, today %s'):format(names[key],
                commas(life.cur[key] or 0), commas(today().cur[key] or 0)))
        end
end}
-- //bup view today | lifetime: which totals the item list shows
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'view' end, function(cmd, a)
        settings.finds_view = (a[1] or ''):lower() == 'lifetime' and 'lifetime' or 'today'
        config.save(settings)
        log('Item list now shows: ' .. settings.finds_view)
end}
-- //bup finds: the item list in chat
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'finds' end, function(cmd, a)
        local src = settings.finds_view == 'lifetime' and life.drops or today().drops
        local list = {}
        for name, n in pairs(src) do list[#list + 1] = {name, n} end
        table.sort(list, function(x, y) return x[2] > y[2] end)
        log(('Items found (%s): %d types'):format(settings.finds_view, #list))
        for _, e in ipairs(list) do
            log(('  %-28s %5d%s'):format(e[1], e[2], prices[e[1]] and ('  @' .. short_price(prices[e[1]])) or ''))
        end
end}
-- //bup saveall: copy this character's settings to every character
COMMANDS[#COMMANDS + 1] = {function(cmd, a) return cmd == 'saveall' end, function(cmd, a)
        config.save(settings, 'all')
        log('Current settings copied to all characters.')
end}

-- //bup <command> ...: run the first matching entry in COMMANDS, else show help.
windower.register_event('addon command', function(cmd, ...)
    cmd = cmd and cmd:lower() or 'help'
    local a = {...}
    for _, c in ipairs(COMMANDS) do
        if c[1](cmd, a) then return c[2](cmd, a) end
    end
    log(('Unknown command "%s".'):format(cmd))
    SETTINGS.help()
end)
