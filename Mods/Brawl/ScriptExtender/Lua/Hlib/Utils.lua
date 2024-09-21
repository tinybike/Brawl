---@type Mod
local Mod = Require("Hlib/Mod")

---@class Utils
local M = {}

-------------------------------------------------------------------------------------------------
--                                                                                             --
--                                           Generic                                           --
--                                                                                             --
-------------------------------------------------------------------------------------------------

---@param v1 any
---@param v2 any
---@param ignoreMT boolean|nil ignore metatables
function M.Equals(v1, v2, ignoreMT)
    if v1 == v2 then
        return true
    end

    local v1Type = type(v1)
    local v2Type = type(v2)
    if v1Type ~= v2Type then
        return false
    end
    if v1Type ~= "table" then
        return false
    end

    if not ignoreMT then
        local mt1 = getmetatable(v1)
        if mt1 and mt1.__eq then
            --compare using built in method
            return v1 == v2
        end
    end

    return Ext.DumpExport(v1) == Ext.DumpExport(v2)
end

---@param struct userdata|table|any
---@param property string
---@param default any|nil
---@return any
function M.GetProperty(struct, property, default)
    local ok, value = pcall(function()
        return struct[property]
    end)
    if ok then
        return value
    end
    return default
end

---@param prefix string|nil
---@param input table|nil
---@return string
function M.RandomId(prefix, input)
    local id
    if type(input) == "table" then
        id = M.Table.ToStringRaw(input)
    else
        id = tostring({})
    end
    id = id:gsub("table: ", prefix or "")

    return id
end

function M.Random(...)
    local iter = math.floor(tostring(tonumber(tostring({}):gsub("table: ", ""), 16) / 0xFFFFFFF):sub(-3))
    for i = 1, iter do
        Ext.Math.Random()
    end
    return Ext.Math.Random(...)
end

---@param code string x, y -> x + y
---@vararg any injected arguments: x
---@return fun(...): any @function(y) return x + y end
function M.Lambda(code, ...)
    local argString, evalString = table.unpack(M.String.Split(code, "->"))
    assert(evalString, "Lambda code must contain '->'")

    local args = M.Table.Map(M.String.Split(argString, ","), M.String.Trim)

    code = "return " .. M.String.Trim(evalString)

    local env = {}
    setmetatable(env, { __index = _G })

    -- Add vararg values to env with keys from args
    -- Remove from args those that are injected via vararg
    for i, arg in ipairs(M.Table.Values(args)) do
        if select("#", ...) == 0 then
            break
        end

        env[arg] = select(i, ...)
        if select("#", ...) < i then
            table.remove(args, 1)
        end
    end

    return function(...)
        for i, arg in ipairs(args) do
            env[arg] = select(i, ...)
        end

        local ok, res = pcall(Ext.Utils.LoadString(code, env))
        if not ok then
            error('\n[Lambda]: "' .. code .. '"\n' .. res)
        end

        return res
    end
end

---@param filter string[]|nil
---@return string
function M.CallStack(filter)
    local stack = debug.traceback()
    return M.String.Trim(M.Table.Find(M.String.Split(stack, "\n"), function(line)
        return not M.String.Contains(
            line,
            M.Table.Extend({
                "stack traceback:",
                "Hlib/Utils.lua",
                "(...tail calls...)",
                "[C++ Code]",
                "...",
                "builtin://",
            }, filter or {}),
            false,
            true
        )
    end) or "")
end

---@param func function
---@vararg any
---@return function
function M.Bind(func, ...)
    local args = { ... }
    return function()
        return func(table.unpack(args))
    end
end

---@param func function
---@return fun(...): any
function M.Once(func)
    local called = false
    local result = {}
    return function(...)
        if not called then
            called = true
            result = { func(...) }
        end

        return table.unpack(result)
    end
end

-------------------------------------------------------------------------------------------------
--                                                                                             --
--                                           Table                                             --
--                                                                                             --
-------------------------------------------------------------------------------------------------

M.Table = {}

---@param t1 table
---@vararg table
---@return table<string, any> t1
function M.Table.Merge(t1, ...)
    for _, t2 in ipairs({ ... }) do
        for k, v in pairs(t2) do
            t1[k] = v
        end
    end
    return t1
end

---@param t1 table<number, any>
---@vararg table
---@return table<number, any> t1
function M.Table.Extend(t1, ...)
    for _, t in ipairs({ ... }) do
        for _, v in pairs(t) do
            table.insert(t1, v)
        end
    end
    return t1
end

function M.Table.Size(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

---@param t table<number, any> e.g. { 1, 2, 3 } or { {v=1}, {v=2}, {v=3} }
---@param value any|table<number, any> e.g. 2 or {v=2}
---@param multiple boolean|nil value is a table of value e.g. { 2, 3 } or { {v=2}, {v=3} }
---@return table t
function M.Table.Remove(t, value, multiple)
    for i = #t, 1, -1 do
        if multiple then
            for _, val in ipairs(value) do
                if M.Equals(t[i], val, true) then
                    table.remove(t, i)
                    break
                end
            end
        else
            if M.Equals(t[i], value, true) then
                table.remove(t, i)
            end
        end
    end
    return t
end

---@param t table
---@param seen table|nil used to prevent infinite recursion
---@return table
function M.Table.DeepClone(t, seen)
    -- Handle non-tables and previously-seen tables.
    if type(t) ~= "table" then
        return t
    end
    if seen and seen[t] then
        return seen[t]
    end

    -- New table; mark it as seen and copy recursively.
    local s = seen or {}
    local res = {}
    s[t] = res
    for k, v in pairs(t) do
        res[M.Table.DeepClone(k, s)] = M.Table.DeepClone(v, s)
    end
    return setmetatable(res, getmetatable(t))
end

---@param t table
---@return table
function M.Table.Clone(t)
    return M.Table.Map(t, function(v, k)
        return v, k
    end)
end

---@param t table
---@param func function
function M.Table.Each(t, func)
    for k, v in pairs(t) do
        func(v, k)
    end
end

---@param t table
---@param func fun(value, key): value: any|nil, key: any|nil
---@return table
function M.Table.Map(t, func)
    local r = {}
    for k, v in pairs(t) do
        local value, key = func(v, k)
        if value ~= nil then
            if key ~= nil then
                r[key] = value
            else
                table.insert(r, value)
            end
        end
    end
    return r
end

---@param t table
---@param func fun(value, key): boolean
---@return table
function M.Table.Filter(t, func, keepKeys)
    return M.Table.Map(t, function(v, k)
        if func(v, k) then
            if keepKeys then
                return v, k
            else
                return v
            end
        end
    end)
end

---@param t table table to search
---@param v any value to search for
---@param count boolean|nil return count instead of boolean
---@return boolean|number
function M.Table.Contains(t, v, count)
    local r = #M.Table.Filter(t, function(v2)
        return M.Equals(v, v2, true)
    end)
    return count and r or r > 0
end

---@param t table table to search
---@param func fun(value, key): boolean
---@return any|nil, string|number|nil @value, key
function M.Table.Find(t, func)
    for k, v in pairs(t) do
        if func(v, k) then
            return v, k
        end
    end
    return nil, nil
end

---@param t table
---@return table
function M.Table.Keys(t)
    return M.Table.Map(t, function(_, k)
        return k
    end)
end

---@param t table
---@return table
function M.Table.Values(t)
    return M.Table.Map(t, function(v)
        return v
    end)
end

---@param t table<number, string>
---@return table<string, number>
function M.Table.Set(t)
    return M.Table.Map(t, function(v, k)
        return k, tostring(v)
    end)
end

---@param t table
---@param key string
---@return table<string, table>
function M.Table.GroupBy(t, key)
    local r = {}
    for k, v in pairs(t) do
        local vk = v[key]
        if not r[vk] then
            r[vk] = {}
        end

        r[vk][k] = v
    end
    return r
end

-- remove unserializeable values
---@param t table
---@param maxEntityDepth number|nil default: 0
---@param seen table|nil used to prevent infinite recursion
---@return table
function M.Table.Clean(t, maxEntityDepth, seen)
    maxEntityDepth = maxEntityDepth or 0

    seen = seen or {}

    return M.Table.Map(t, function(v, k)
        k = tonumber(k) or tostring(k)

        if type(v) == "userdata" then
            local ok, value = pcall(Ext.Types.Serialize, v)
            if ok then
                v = value
            elseif getmetatable(v) == "EntityProxy" and maxEntityDepth > 0 then
                v = M.Table.Clean(v:GetAllComponents(), maxEntityDepth - 1)
            else
                v = Ext.Json.Parse(Ext.Json.Stringify(v, {
                    Beautify = false,
                    StringifyInternalTypes = true,
                    IterateUserdata = true,
                    AvoidRecursion = true,
                }))
            end
        end

        if type(v) == "function" then
            return nil, k
        end

        if type(v) == "table" then
            if not seen[v] then
                seen[v] = {}
                M.Table.Merge(seen[v], M.Table.Clean(v, maxEntityDepth, seen))
            end

            return seen[v], k
        end

        return v, k
    end)
end

---@param t table
---@param size number
---@return table
function M.Table.Batch(t, size)
    local r = {}
    local i = 1
    for _, v in pairs(t) do
        if not r[i] then
            r[i] = {}
        end
        table.insert(r[i], v)
        if #r[i] == size then
            i = i + 1
        end
    end
    return r
end

---@param t table
---@param patch table
---@param replaced table|nil
---@return table t, table patch, table|nil replaced
function M.Table.Patch(t, patch, replaced)
    if not replaced then
        replaced = {}
    end

    if type(patch) == "table" then
        for k, v in pairs(patch) do
            local diff = true
            if type(v) == "table" then
                diff = not M.Equals(v, {})

                if not replaced[k] then
                    replaced[k] = {}
                end
            else
                diff = v ~= t[k]

                if diff and replaced[k] == nil then
                    replaced[k] = t[k]
                end
            end

            if diff then
                local _, new = M.Table.Patch(t[k], v, replaced[k])
                t[k] = new
            end

            if M.Equals(replaced[k], {}) then
                replaced[k] = nil
            end
        end
    end

    if M.Equals(replaced, {}) then
        replaced = nil
    end

    return t, patch, replaced
end

---@param t table
---@return string
function M.Table.ToStringRaw(t)
    local meta = getmetatable(t)
    local str
    if meta then
        local s = meta.__tostring
        meta.__tostring = nil
        str = tostring(t)
        meta.__tostring = s
    else
        str = tostring(t)
    end
    return str
end

---@param t table
---@param onSet fun(value: any, key: string, raw: table, parent: table|nil): any value
---@param onGet fun(value: any, key: string, raw: table, parent: table|nil): any value
---@return Proxy, fun(): table toTable, fun(callback: fun(value: any, key: string, raw: table): any) onModified
function M.Table.Proxy(t, onSet, onGet)
    local raw = {}
    t = t or {}

    local proxy = false

    local onModified = {}
    local function modifiedEvent(raw, key, value)
        for _, callback in ipairs(onModified) do
            callback(value, key, raw)
        end
    end

    ---@class Proxy: table
    local Proxy = setmetatable({}, {
        __metatable = false,
        __name = "Proxy",
        __eq = function(self, other)
            -- create a closure around `t` to emulate shallow equality
            return rawequal(t, other) or rawequal(self, other)
        end,
        __pairs = function(self)
            -- wrap `next` to enable proxy hits during traversal
            return function(tab, key)
                local index, value = next(raw, key)

                return index, value ~= nil and self[index]
            end,
                self,
                nil
        end,
        -- these metamethods create closures around `actual`
        __len = function(self)
            return rawlen(raw)
        end,
        __index = function(self, key)
            local v = rawget(raw, key)
            if proxy and onGet then
                v = onGet(v, key, raw)
            end

            return v
        end,
        __newindex = function(self, key, value)
            if proxy and onSet then
                value = onSet(value, key, raw)
            end

            if type(value) == "table" then
                value = M.Proxy(value, function(sub, subKey, subValue)
                    local parent = {}
                    for k, v in pairs(raw) do
                        parent[k] = v
                    end

                    parent[key] = sub

                    if proxy and onSet then
                        return onSet(subValue, subKey, parent, raw)
                    end

                    return subValue
                end, function(sub, subKey, subValue)
                    local parent = {}
                    for k, v in pairs(raw) do
                        parent[k] = v
                    end

                    parent[key] = sub

                    if proxy and onGet then
                        return onGet(subValue, subKey, parent, raw)
                    end

                    return subValue
                end)
            end

            rawset(raw, key, value)

            modifiedEvent(raw, key, value)
        end,
    })

    -- copy all values from `t` to `proxy`
    for key, value in pairs(t) do
        Proxy[key] = value
    end

    -- enable after initialization
    proxy = true

    -- recursively convert `proxy` to a table
    local function toTable(tbl)
        local t = {}
        for k, v in pairs(tbl) do
            if type(v) == "table" then
                t[k] = toTable(v)
            else
                t[k] = v
            end
        end
        return t
    end

    return Proxy,
        function()
            return toTable(raw)
        end,
        function(callback)
            assert(
                type(callback) == "function",
                "_,_,onModified(callback) = Libs.Proxy(...) - function expected, got " .. type(callback)
            )
            table.insert(onModified, callback)
        end
end

-------------------------------------------------------------------------------------------------
--                                                                                             --
--                                           String                                            --
--                                                                                             --
-------------------------------------------------------------------------------------------------

M.String = {}

function M.String.Escape(s)
    local matches = {
        ["^"] = "%^",
        ["$"] = "%$",
        ["("] = "%(",
        [")"] = "%)",
        ["%"] = "%%",
        ["."] = "%.",
        ["["] = "%[",
        ["]"] = "%]",
        ["*"] = "%*",
        ["+"] = "%+",
        ["-"] = "%-",
        ["?"] = "%?",
        ["\0"] = "%z",
    }
    return (s:gsub(".", matches))
end

-- same as string.match but case insensitive
function M.String.IMatch(s, pattern, init)
    s = string.lower(s)
    pattern = string.lower(pattern)
    return string.match(s, pattern, init)
end

function M.String.MatchAfter(s, prefix)
    return string.match(s, prefix .. "(.*)")
end

function M.String.UpperFirst(s)
    return s:gsub("^%l", string.upper)
end

function M.String.LowerFirst(s)
    return s:gsub("^%l", string.lower)
end

---@param s string
---@param patterns string[]|string
---@param ignoreCase boolean|nil
---@param escape boolean|nil
---@return boolean
function M.String.Contains(s, patterns, ignoreCase, escape)
    if type(patterns) == "string" then
        patterns = { patterns }
    end
    for _, pattern in ipairs(patterns) do
        if escape then
            pattern = M.String.Escape(pattern)
        end

        if ignoreCase then
            if M.String.IMatch(s, pattern) ~= nil then
                return true
            end
        else
            if string.match(s, pattern) ~= nil then
                return true
            end
        end
    end
    return false
end

---@param s string
---@return string
function M.String.Trim(s)
    return s:match("^%s*(.-)%s*$")
end

---@param s string
---@param sep string
---@return string[]
function M.String.Split(s, sep)
    local r = {}
    for match in (s .. sep):gmatch("(.-)" .. sep) do
        table.insert(r, match)
    end
    return r
end

-------------------------------------------------------------------------------------------------
--                                                                                             --
--                                            UUID                                             --
--                                                                                             --
-------------------------------------------------------------------------------------------------

M.UUID = {}

function M.UUID.IsValid(str)
    return M.UUID.Extract(str) ~= nil
end

function M.UUID.Extract(str)
    if type(str) ~= "string" then
        return nil
    end

    local x = "%x"
    local t = { x:rep(8), x:rep(4), x:rep(4), x:rep(4), x:rep(12) }
    local pattern = table.concat(t, "%-")

    return str:match(pattern)
end

function M.UUID.Equals(item1, item2)
    if type(item1) == "string" and type(item2) == "string" then
        return (M.UUID.Extract(item1) == M.UUID.Extract(item2))
    end

    return false
end

-- expensive operation
---@param uuid string
---@return boolean
function M.UUID.Exists(uuid)
    return Ext.Template.GetTemplate(uuid)
        or Ext.Mod.IsModLoaded(uuid)
        or Ext.Entity.GetAllEntitiesWithUuid()[uuid] and true
        or false
end

---@return string @UUIDv4
function M.UUID.Random()
    -- version 4 UUID
    return string.gsub("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx", "[xy]", function(c)
        local v = (c == "x") and M.Random(0, 0xf) or M.Random(8, 0xb)
        return string.format("%x", v)
    end)
end

---@param str string
---@param iteration number|nil
---@return string @UUIDv4
function M.UUID.FromString(str, iteration)
    local function hashToUUID(hash)
        return string.format(
            "%08x-%04x-4%03x-%04x-%012x",
            tonumber(hash:sub(1, 8), 16),
            tonumber(hash:sub(9, 12), 16),
            tonumber(hash:sub(13, 15), 16),
            tonumber(hash:sub(16, 19), 16) & 0x3fff | 0x8000,
            tonumber(hash:sub(20, 31), 16)
        )
    end

    local function simpleHash(input)
        local hash = 0
        local shift = 0
        for i = 1, #input do
            hash = (hash ~ ((string.byte(input, i) + i) << shift)) & 0xFFFFFFFF
            shift = (shift + 6) % 25
        end
        return string.format("%08x%08x%08x%08x", hash, hash ~ 0x55555555, hash ~ 0x33333333, hash ~ 0x11111111)
    end

    local prefix = ""
    for i = 1, (iteration or 1) do
        prefix = prefix .. Mod.UUID
    end

    return hashToUUID(simpleHash(prefix .. str))
end

return M
