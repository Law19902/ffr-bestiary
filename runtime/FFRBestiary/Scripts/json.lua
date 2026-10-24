-- Minimal JSON for the bestiary save files (objects, arrays, strings, numbers, booleans, null).
local M = {}

local function encodeString(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
        return map[c] or string.format('\\u%04x', c:byte())
    end) .. '"'
end

local function isArray(t)
    local n = 0
    for k in pairs(t) do
        if type(k) ~= 'number' then return false end
        n = n + 1
    end
    return n == #t
end

function M.encode(v, indent)
    indent = indent or ''
    local t = type(v)
    if v == nil then return 'null'
    elseif t == 'boolean' or t == 'number' then return tostring(v)
    elseif t == 'string' then return encodeString(v)
    elseif t == 'table' then
        local inner = indent .. ' '
        local parts = {}
        if next(v) == nil then return isArray(v) and '[]' or '{}' end
        if isArray(v) then
            for _, x in ipairs(v) do parts[#parts + 1] = M.encode(x, inner) end
            return '[' .. table.concat(parts, ', ') .. ']'
        end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local x = v[k]; if x == nil then x = v[tonumber(k)] end
            parts[#parts + 1] = inner .. encodeString(k) .. ': ' .. M.encode(x, inner)
        end
        return '{\n' .. table.concat(parts, ',\n') .. '\n' .. indent .. '}'
    end
    error('cannot encode ' .. t)
end

function M.decode(s)
    local pos = 1
    local function ws() pos = s:find('[^ \t\r\n]', pos) or #s + 1 end
    local value
    local function str()
        local out, i = {}, pos + 1
        while true do
            local c = s:sub(i, i)
            if c == '"' then pos = i + 1; return table.concat(out) end
            if c == '\\' then
                local e = s:sub(i + 1, i + 1)
                local map = { n = '\n', r = '\r', t = '\t', b = '\b', f = '\f' }
                if e == 'u' then out[#out + 1] = utf8.char(tonumber(s:sub(i + 2, i + 5), 16)); i = i + 6
                else out[#out + 1] = map[e] or e; i = i + 2 end
            elseif c == '' then error('unterminated string')
            else out[#out + 1] = c; i = i + 1 end
        end
    end
    function value()
        ws()
        local c = s:sub(pos, pos)
        if c == '{' then
            local obj = {}; pos = pos + 1; ws()
            if s:sub(pos, pos) == '}' then pos = pos + 1; return obj end
            while true do
                ws(); local k = str(); ws(); pos = pos + 1   -- ':'
                obj[k] = value(); ws()
                local d = s:sub(pos, pos); pos = pos + 1
                if d == '}' then return obj end
            end
        elseif c == '[' then
            local arr = {}; pos = pos + 1; ws()
            if s:sub(pos, pos) == ']' then pos = pos + 1; return arr end
            while true do
                arr[#arr + 1] = value(); ws()
                local d = s:sub(pos, pos); pos = pos + 1
                if d == ']' then return arr end
            end
        elseif c == '"' then return str()
        elseif s:sub(pos, pos + 3) == 'true' then pos = pos + 4; return true
        elseif s:sub(pos, pos + 4) == 'false' then pos = pos + 5; return false
        elseif s:sub(pos, pos + 3) == 'null' then pos = pos + 4; return nil
        else
            local num = s:match('^-?%d+%.?%d*[eE]?[-+]?%d*', pos)
            pos = pos + #num
            return tonumber(num)
        end
    end
    return value()
end

return M
