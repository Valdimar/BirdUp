-- BirdUp: Records of Eminence progress for chocobo digging objectives.
-- The game prints, after each successful dig:
--   Records of Eminence: Total Suc. Chocobo Digs.
--   Progress: 21/30.
-- and when the objective is done:
--   You have completed the following Records of Eminence objective: Total Suc. Chocobo Digs.
--   You receive 1000 sparks of eminence, and now possess a total of 12345.
--   You receive 100 Unity accolades for a total of 6789!
-- ctx gives: log(msg), commas(n), today() (today's history entry).

return function(ctx)
    local R = {
        name = nil,      -- objective currently being reported
        cur = nil,       -- progress, e.g. 21
        max = nil,       -- e.g. 30
        done = 0,        -- completions this session
        sparks = 0,      -- sparks from completions this session
        accolades = 0,   -- Unity accolades this session
    }
    local pending = nil          -- objective name waiting for its "Progress:" line
    local just_completed = false -- rewards that follow a dig objective count toward it

    -- is this RoE objective about chocobo digging?
    local function is_dig_objective(name)
        name = (name or ''):lower()
        return name:find('chocobo dig', 1, true) or name:find('digging', 1, true)
    end

    -- shorter label for the panel: "Total Suc. Chocobo Digs" -> "Chocobo Digs"
    function R.short_name()
        local n = R.name or 'Chocobo Digs'
        return (n:gsub('^Total Suc%.%s*', ''):gsub('^Total Successful%s*', ''))
    end

    -- returns true when the line was an RoE line (so nothing else needs to look at it)
    function R.handle(clean)
        local obj = clean:match('^Records of Eminence: (.-)%.?%s*$')
        if obj then
            pending = is_dig_objective(obj) and obj or nil
            return true
        end
        local a, b = clean:match('^Progress: (%d+)/(%d+)')
        if a then
            if pending then
                R.name, R.cur, R.max = pending, tonumber(a), tonumber(b)
                pending = nil
            end
            return true
        end
        local comp = clean:match('^You have completed the following Records of Eminence objective: (.-)%.?%s*$')
        if comp then
            if is_dig_objective(comp) then
                R.done = R.done + 1
                local td = ctx.today()
                td.roe = (td.roe or 0) + 1
                R.name, R.cur = comp, 0
                just_completed = true
                ctx.log(('Records of Eminence complete: %s (%d this session, %d today).'):format(comp, R.done, td.roe))
            else
                just_completed = false
            end
            return true
        end
        local sp = clean:match('^You receive ([%d,]+) sparks of eminence')
        if sp then
            if just_completed then R.sparks = R.sparks + (tonumber((sp:gsub(',', ''))) or 0) end
            return true
        end
        local ac = clean:match('^You receive ([%d,]+) Unity accolades')
        if ac then
            if just_completed then R.accolades = R.accolades + (tonumber((ac:gsub(',', ''))) or 0) end
            just_completed = false -- accolades come last
            return true
        end
        if clean:find('This objective may be repeated', 1, true) then return true end
        return false
    end

    -- text for the panel row, or nil when there's nothing to show yet
    function R.row_text()
        if not R.cur then return nil end
        local extra = ''
        if R.done > 0 then
            extra = ('  (%d done, +%s sparks)'):format(R.done, ctx.commas(R.sparks))
        end
        return ('%s %d/%d'):format(R.short_name(), R.cur, R.max), extra
    end

    return R
end
