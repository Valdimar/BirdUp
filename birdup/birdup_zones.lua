-- BirdUp: per-zone drop stats and sharing (import / export ids).
-- Loaded by birdup.lua; kept in its own file so the main file stays under
-- Lua's limits. ctx gives: char_name(), rank_name(), commas(n).
local res = require('resources')

return function(ctx)
---------------------------------------------------------------------------
-- Per-zone drop stats, split by Wing rank (drop tables differ by rank).
-- Each character keeps data/zones_<name>.txt; //bup export combines every
-- character's file into one shareable report + CSV.
---------------------------------------------------------------------------
local zstats = {} -- zone id -> rank name -> {digs, finds, miss, discern, items = {}}

-- data/zones_<name>.txt for a character (default: the current one)
local function zones_path(who)
    who = (who or ctx.char_name() or 'unknown'):lower():gsub('[^%w_-]', '')
    return windower.addon_path .. 'data/zones_' .. who .. '.txt'
end

-- the zone id you're in
local function current_zone()
    local info = windower.ffxi.get_info()
    return info and info.zone or nil
end

-- zone id -> its English name
local function zone_name(id)
    local z = id and res.zones and res.zones[id]
    return z and z.en or ('Zone ' .. tostring(id))
end

-- empty stats for one zone at one Wing rank
local function new_zone_entry() return {digs = 0, finds = 0, miss = 0, discern = 0, items = {}} end

-- add one zone stats file into a table (used for your file, exports and imports)
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

-- read the current character's zone stats
local function load_zone_stats()
    zstats = {}
    read_zone_file(zones_path(), zstats)
end

-- write the current character's zone stats
local function save_zone_stats()
    if not ctx.char_name() then return end
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
    local rank = ctx.rank_name()
    zstats[zid] = zstats[zid] or {}
    zstats[zid][rank] = zstats[zid][rank] or new_zone_entry()
    return zstats[zid][rank]
end

---------------------------------------------------------------------------
-- Sharing: each install has a random id that goes into its exports, so an
-- import can tell players apart. Every imported player is kept in its own
-- file (data/community/<id>.txt); importing a newer export from the same
-- player replaces the old one instead of adding to it. Your own export is
-- never imported. "All players" = your stats + everyone imported.
---------------------------------------------------------------------------
local my_id = nil
local cstats = {} -- imported players combined: zone id -> rank -> entry

-- this install's random sharing id (created once, kept in data/id.txt)
local function get_my_id()
    if my_id then return my_id end
    local path = windower.addon_path .. 'data/id.txt'
    local f = io.open(path, 'r')
    if f then my_id = (f:read('*l') or ''):match('^(%x+)$'); f:close() end
    if not my_id then
        local addr = tonumber((tostring({}):match('(%x+)$')) or '0', 16) or 0
        math.randomseed(os.time() + math.floor(os.clock() * 1000) + addr % 1000003 + #(ctx.char_name() or '') * 7919)
        my_id = ('%08x'):format(math.random(0, 0x7fffffff))
        windower.create_dir(windower.addon_path .. 'data')
        f = io.open(path, 'w')
        if f then f:write(my_id .. '\n'); f:close() end
    end
    return my_id
end

-- where imported players are kept, one file each
local function community_dir() return windower.addon_path .. 'data/community/' end

-- combine every imported player into cstats
local function load_community()
    cstats = {}
    for _, file in ipairs(windower.get_dir(community_dir()) or {}) do
        if file:match('%.txt$') then read_zone_file(community_dir() .. file, cstats) end
    end
end

-- zone name -> id lookup, built on first use
local zone_ids_by_name = nil
-- zone name (from an export) -> zone id
local function zone_id_for(name)
    if not zone_ids_by_name then
        zone_ids_by_name = {}
        for id, z in pairs(res.zones or {}) do if z.en then zone_ids_by_name[z.en:lower()] = id end end
    end
    return zone_ids_by_name[(name or ''):lower()]
end

-- split one CSV line (handles "quoted, fields" and "" escapes)
local function csv_fields(line)
    local out, i, n = {}, 1, #line
    while i <= n + 1 do
        if line:sub(i, i) == '"' then
            local val, j = '', i + 1
            while j <= n do
                local c = line:sub(j, j)
                if c == '"' then
                    if line:sub(j + 1, j + 1) == '"' then val = val .. '"'; j = j + 2
                    else j = j + 1; break end
                else val = val .. c; j = j + 1 end
            end
            out[#out + 1] = val
            i = j + 1 -- skip the comma
        else
            local k = line:find(',', i, true) or (n + 1)
            out[#out + 1] = line:sub(i, k - 1)
            i = k + 1
        end
    end
    return out
end

-- returns ok, message
local function import_file(path, label)
    local f = io.open(path, 'r')
    if not f then return false, 'could not open ' .. label end
    local data, src, rows_read, skipped = {}, nil, 0, 0
    local first = true
    for line in f:lines() do
        line = line:gsub('\r$', '')
        if first then
            first = false
            if not line:match('^zone,wing_rank') then f:close(); return false, label .. " isn't a BirdUp export" end
        elseif line ~= '' then
            local c = csv_fields(line)
            local zid = zone_id_for(c[1])
            local digs, cnt = tonumber(c[3]), tonumber(c[8])
            if zid and c[2] and digs and c[7] and cnt then
                src = src or c[11]
                data[zid] = data[zid] or {}
                local e = data[zid][c[2]]
                if not e then
                    e = new_zone_entry()
                    e.digs, e.finds = digs, tonumber(c[4]) or 0
                    e.miss, e.discern = tonumber(c[5]) or 0, tonumber(c[6]) or 0
                    data[zid][c[2]] = e
                end
                e.items[c[7]] = cnt
                rows_read = rows_read + 1
            else
                skipped = skipped + 1
            end
        end
    end
    f:close()
    if rows_read == 0 then return false, label .. ' had no drop rows' end
    if src == get_my_id() then return false, label .. ' is your own export (already in your stats)' end
    -- older exports have no id: use the file name so re-importing it replaces
    src = (src and src ~= '') and src or ('file_' .. label:gsub('[^%w_-]', '_'))
    windower.create_dir(windower.addon_path .. 'data')
    windower.create_dir(community_dir())
    local replaced = io.open(community_dir() .. src .. '.txt', 'r')
    if replaced then replaced:close() end
    local out = io.open(community_dir() .. src .. '.txt', 'w')
    if not out then return false, 'could not save ' .. label end
    local digs = 0
    for zid, ranks in pairs(data) do
        for rank, e in pairs(ranks) do
            digs = digs + e.digs
            out:write(('%d\t%s\t#digs\t%d\n%d\t%s\t#finds\t%d\n%d\t%s\t#miss\t%d\n%d\t%s\t#discern\t%d\n'):format(
                zid, rank, e.digs, zid, rank, e.finds, zid, rank, e.miss, zid, rank, e.discern))
            for item, n in pairs(e.items) do out:write(('%d\t%s\t%s\t%d\n'):format(zid, rank, item, n)) end
        end
    end
    out:close()
    return true, ('%s: %s digs from player %s%s'):format(label, ctx.commas(digs), src,
        replaced and ' (replaced their older import)' or '')
end

-- your entry plus every imported player's, for one zone and rank
local function combined_entry(zid, rank)
    local mine = zstats[zid] and zstats[zid][rank]
    local theirs = cstats[zid] and cstats[zid][rank]
    if not theirs then return nil end
    local e = new_zone_entry()
    for _, src in ipairs({mine, theirs}) do
        if src then
            e.digs, e.finds = e.digs + src.digs, e.finds + src.finds
            e.miss, e.discern = e.miss + src.miss, e.discern + src.discern
            for item, n in pairs(src.items) do e.items[item] = (e.items[item] or 0) + n end
        end
    end
    return e
end


-- what birdup.lua uses
return {
    stats = function() return zstats end,
    cstats = function() return cstats end,
    current_zone = current_zone,
    zone_name = zone_name,
    new_entry = new_zone_entry,
    read_zone_file = read_zone_file,
    load = load_zone_stats,
    save = save_zone_stats,
    entry = zone_entry,
    get_my_id = get_my_id,
    community_dir = community_dir,
    load_community = load_community,
    import_file = import_file,
    combined = combined_entry,
    zone_id_for = zone_id_for,
}
end
