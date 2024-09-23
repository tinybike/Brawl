---@type Libs
local Libs = Require("Hlib/Libs")

---@type Utils
local Utils = Require("Hlib/Utils")

---@type Log
local Log = Require("Hlib/Log")

---@class Async
local M = {}

---@class Loop : Struct
---@field Startable boolean
---@field Queues Queue[]
---@field Handle number|nil
---@field Tasks { Count: number, Inc: fun(self: Loop.Tasks), Dec: fun(self: Loop.Tasks) }
---@field IsRunning fun(self: Loop): boolean
---@field IsEmpty fun(self: Loop): boolean
---@field Start fun(self: Loop)
---@field Stop fun(self: Loop)
---@field Tick fun(self: Loop, time: GameTime)
local Loop = Libs.Struct({
    Startable = true,
    Queues = {},
    Tasks = {
        Count = 0,
        Inc = function(self)
            self.Count = self.Count + 1
        end,
        Dec = function(self)
            self.Count = self.Count - 1
        end,
    },
    Handle = nil,
    IsRunning = function(self) ---@param self Loop
        return self.Handle ~= nil
    end,
    IsEmpty = function(self) ---@param self Loop
        if self.Tasks.Count > 0 then
            return false
        end

        local count = 0
        for _, queue in ipairs(self.Queues) do
            count = count + #queue.Tasks
        end
        return count == 0
    end,
    Start = function(self) ---@param self Loop
        assert(self.Handle == nil, "Loop already running.")
        if Mod.Dev then
            Log.Debug("Loop/Start", self.Startable)
        end
        if not self.Startable or self:IsEmpty() then
            return
        end

        local ticks = 0
        self.Handle = Ext.Events.Tick:Subscribe(function(e)
            if self:IsEmpty() then
                self:Stop()
                return
            end

            self:Tick(e.Time)

            ticks = ticks + 1
            if ticks % 3000 == 0 then
                Log.Debug("Loop is running for long.", "Ticks:", ticks, "Tasks:", self.Tasks.Count)
                if Mod.Dev then
                    for _, queue in ipairs(self.Queues) do
                        for _, runner in queue:Iter() do
                            Log.Debug("Async/Runner", runner._Origin)
                        end
                    end
                end
            end
        end)
    end,
    Stop = function(self) ---@param self Loop
        assert(self.Handle ~= nil, "Loop not running.")
        Ext.Events.Tick:Unsubscribe(self.Handle)
        self.Handle = nil
        if Mod.Dev then
            Log.Debug("Loop/Stop")
        end
    end,
    Tick = function(self, time) ---@param self Loop
        local startTime = Ext.Utils.MonotonicTime()
        for _, queue in ipairs(self.Queues) do
            for _, runner in queue:Iter() do
                local success, result = pcall(function()
                    if runner:ExecCond(time) then
                        runner:Exec()

                        if runner:ClearCond(time) then
                            runner:Clear()
                        end

                        return true
                    end
                end)

                if not success then
                    runner:Failed(result)
                    return
                end

                if result == true then
                    if Ext.Utils.MonotonicTime() - startTime > 10000 then
                        return
                    end
                end
            end
        end
    end,
})

---@class Queue : Struct
---@field Loop Loop
---@field Tasks table<number, { idx: number, item: Runner }>
---@field Enqueue fun(self: Queue, item: Runner): string
---@field Dequeue fun(self: Queue, idx: number)
---@field Iter fun(self: Queue): fun(): number, Runner
---@field New fun(loop: Loop): Queue
local Queue = Libs.Struct({
    Loop = nil,
    Tasks = {},
    Enqueue = function(self, item) ---@param self Queue
        local idx = Utils.RandomId("Queue_", item)
        table.insert(self.Tasks, { idx = idx, item = item })

        self.Loop.Tasks:Inc()
        if not self.Loop:IsRunning() then
            self.Loop:Start()
        end

        if Mod.Dev then
            Log.Debug("Queue/Enqueue", self.Loop.Tasks.Count, idx, item._Origin)
        end

        return idx
    end,
    Dequeue = function(self, idx) ---@param self Queue
        for i, v in ipairs(self.Tasks) do
            if v.idx == idx then
                table.remove(self.Tasks, i)
                self.Loop.Tasks:Dec()

                if Mod.Dev then
                    Log.Debug("Queue/Dequeue", self.Loop.Tasks.Count, idx, v.item._Origin)
                end

                return
            end
        end
    end,
    Iter = function(self) ---@param self Queue
        return ipairs(Utils.Table.Map(self.Tasks, function(v)
            return v.item
        end))
        -- local i = 0
        -- return function()
        --     i = i + 1
        --     if self.Tasks[i] then
        --         return i, self.Tasks[i].item
        --     end
        -- end
    end,
})

---@param loop Loop
---@return Queue
function Queue.New(loop)
    local obj = Queue.Init({
        Loop = loop,
    })

    table.insert(loop.Queues, obj)

    return obj
end

-- exposed
---@class Runner : Struct
---@field Cleared boolean
---@field ExecCond fun(self: Runner, time: GameTime): boolean
---@field Exec fun(self: Runner)
---@field ClearCond fun(self: Runner, time: GameTime): boolean
---@field Clear fun(self: Runner)
---@field Failed fun(self: Runner, error: any)
local Runner = Libs.Struct({
    _Id = nil,
    _Queue = nil,
    _Origin = nil,
    Cleared = false,
    ExecCond = function(_, _)
        return true
    end,
    Exec = function(_) end,
    ClearCond = function(_, _)
        return true
    end,
    Clear = function(self)
        self._Queue:Dequeue(self._Id)
        self.Cleared = true
    end,
    Failed = function(self, _)
        self:Clear()
    end,
})

---@param queue Queue
---@param func fun(self: Runner)
---@return Runner
function Runner.New(queue, func)
    local obj = Runner.Init()

    obj.Exec = func

    if Mod.Dev then
        obj._Origin = Utils.CallStack({ "Hlib/Async.lua" })
    end

    obj._Id = queue:Enqueue(obj)
    obj._Queue = queue

    return obj
end

---@class ChainableRunner : Chainable
---@field Source Runner
---@param queue Queue
---@param func fun()|nil
---@return ChainableRunner
function Runner.Chainable(queue, func)
    local obj = Runner.New(queue, func)

    local chainable = Libs.Chainable(obj)
    obj.Exec = function()
        chainable:Begin()
    end

    local clearFunc = obj.Clear

    obj.Failed = function(self, error)
        clearFunc(self)
        chainable:Throw(error)
    end

    obj.Clear = function(self)
        clearFunc(self)
        chainable:End(true, {})
    end

    if func then
        chainable:After(func)
    end

    return chainable
end

---@type Loop
local loop = Loop.New()
---@type Queue
local prio = Queue.New(loop)
---@type Queue
local lowPrio = Queue.New(loop)

---@type GameState
local GameState = Require("Hlib/GameState")
-- TODO save loop state in SavingAction or run all tasks from prio queue at once
GameState.OnUnload(function()
    if loop:IsRunning() then
        loop:Stop()
    end
end)
GameState.OnSave(function()
    if loop:IsRunning() then
        loop:Stop()
    end
end)
GameState.OnLoadSession(function()
    loop.Startable = false
end)
GameState.OnLoad(function()
    loop.Startable = true
    if not loop:IsRunning() then
        loop:Start()
    end
end)

-------------------------------------------------------------------------------------------------
--                                                                                             --
--                                           Runners                                           --
--                                                                                             --
-------------------------------------------------------------------------------------------------

---@param ms number
---@param func fun()|nil
---@return ChainableRunner
function M.Defer(ms, func)
    local seconds = ms / 1000
    local last = 0

    local chainable = Runner.Chainable(prio, func)

    chainable.Source.ExecCond = function(_, time)
        last = last + time.DeltaTime
        return last >= seconds
    end

    return chainable
end

---@param func fun()|nil
---@return ChainableRunner
function M.Run(func)
    return Runner.Chainable(prio, func)
end

---@param func fun()|nil
---@return ChainableRunner
function M.Schedule(func)
    return Runner.Chainable(lowPrio, func)
end

---@param ticks number
---@param func fun()|nil
---@return ChainableRunner
function M.WaitTicks(ticks, func)
    local chainable = Runner.Chainable(prio, func)
    local tick = 0

    chainable.Source.ExecCond = function(_, _)
        tick = tick + 1
        return tick >= ticks
    end

    return chainable
end

---@param ms number
---@param func fun(self: Runner)
---@return Runner
function M.Interval(ms, func)
    local seconds = ms / 1000
    local last = 0
    local skip = false -- avoid consecutive executions

    local runner = Runner.New(lowPrio, func)

    runner.ExecCond = function(_, time)
        last = last + time.DeltaTime

        local cond = last >= seconds and not skip
        if cond then
            last = 0
        end
        skip = cond

        return cond
    end

    runner.ClearCond = function(_, _)
        return false
    end

    return runner
end

---@param cond fun(self: Runner, chainable: ChainableRunner): boolean
---@param func fun()|nil
---@return ChainableRunner
-- check for condition every ~100ms
function M.WaitUntil(cond, func)
    local chainable = Runner.Chainable(prio, func)
    local last = 0

    chainable.Source.ExecCond = function(self, time)
        last = last + time.DeltaTime
        if last < 0.1 then
            return false
        end
        last = 0

        return cond(self, chainable)
    end

    return chainable
end

---@class RetryForOptions
---@field retries number|nil default: 3, -1 for infinite
---@field interval number|nil default: 1000
---@field immediate boolean|nil default: false
---@field throw boolean|nil default: false
---@param cond fun(self: Runner, triesLeft: number, chainable: ChainableRunner): boolean
---@param options RetryForOptions|nil
---@return ChainableRunner
-- retries every (default: 1000 ms) until condition is met or tries (default: 3) are exhausted
function M.RetryUntil(cond, options)
    options = options or {}
    local retries = options.retries or 3
    local interval = options.interval or 1000
    local immediate = options.immediate or false

    local chainable = Libs.Chainable()
    local function fail(...)
        if not options.throw then
            chainable:Catch(function(err)
                L.Debug("RetryUntil catch error:", err)
                return err
            end)
        end

        chainable:Throw(...)
    end

    local runner = M.Interval(interval, function(self)
        local ok, result = pcall(cond, self, retries, chainable)
        if ok and result then
            self:Clear()
            chainable:Begin(result)
            return
        end

        if not ok then
            L.Debug("RetryUntil error:", result)
        end

        retries = retries - 1

        if retries == 0 then
            self:Clear()

            fail(result)
        end
    end)

    runner.Failed = function(self, error)
        self:Clear()

        fail(result)
    end

    chainable.Source = runner

    if immediate then
        M.Run(function()
            chainable.Source:Exec()
        end)
    end

    return chainable
end

-------------------------------------------------------------------------------------------------
--                                                                                             --
--                                          Wrappers                                           --
--                                                                                             --
-------------------------------------------------------------------------------------------------

---@param ms number
---@param func fun(...)
---@param immediate boolean|nil
---@return fun(...)
-- will create a function that is debounced
function M.Debounce(ms, func, immediate)
    local runner

    local origin = nil
    if Mod.Dev then
        origin = Utils.CallStack({ "Hlib/Async.lua" })
    end

    return function(...)
        local exec = Utils.Bind(func, ...)

        if runner then
            runner:Clear()
        elseif immediate then
            exec()
            exec = nil
        end

        runner = M.Defer(ms, function()
            runner = nil
            if exec then
                exec()
            end
        end).Source
        runner._Origin = origin
    end
end

---@param ms number
---@param func fun(...)
---@return fun(...)
-- will create a function that is throttled
function M.Throttle(ms, func)
    local canRun = true

    local origin = nil
    if Mod.Dev then
        origin = Utils.CallStack({ "Hlib/Async.lua" })
    end

    return function(...)
        if not canRun then
            return
        end
        canRun = false

        local runner = M.Defer(ms, function()
            canRun = true
        end).Source
        runner._Origin = origin

        func(...)
    end
end

-------------------------------------------------------------------------------------------------
--                                                                                             --
--                                         Async/Await                                         --
--                                                                                             --
-------------------------------------------------------------------------------------------------

local function resumeCoroutine(co, ...)
    return M.Run(Utils.Bind(function(...)
        local result = { coroutine.resume(co, ...) }
        local ok = table.remove(result, 1)

        if not ok then
            error(table.unpack(result))
        end

        return table.unpack(result)
    end, ...))
end

---@param func fun()
---@return fun(): Chainable
function M.Wrap(func)
    assert(type(func) == "function", "Async.Wrap(func) - function expected, got " .. type(func))

    return function(...)
        return resumeCoroutine(coroutine.create(func), ...)
    end
end

---@param chainable Chainable
---@return any
function M.Sync(chainable)
    local co = coroutine.running()

    assert(co ~= nil, "Async.Sync(chainable) - Can't await outside coroutine.")

    assert(Libs.IsChainable(chainable), "Async.Sync(chainable) - Chainable expected")

    chainable:Final(function(...)
        return true, resumeCoroutine(co, ...)
    end)

    local result = { coroutine.yield(chainable) }
    local ok = table.remove(result, 1)

    if not ok then
        error(debug.traceback(table.unpack(result)))
    end

    return table.unpack(result)
end

---@param chainables table<Chainable>
---@return table<any>
function M.SyncAll(chainables)
    assert(type(chainables) == "table", "Async.SyncAll(chainables) - table expected, got " .. type(chainables))

    local awaiting = #chainables
    local results = {}

    local combined = Libs.Chainable()
    local errors = {}

    for i, chainable in ipairs(chainables) do
        assert(
            Libs.IsChainable(chainable),
            "Async.SyncAll(chainables[" .. i .. "]) - Chainable expected, got " .. type(chainable)
        )

        chainable:Final(function(success, ...)
            results[i] = { ... }
            awaiting = awaiting - 1

            if not success then
                errors[i] = { ... }
            end

            if awaiting == 0 then
                if Utils.Table.Size(errors) > 0 then
                    combined:Throw(table.unpack(errors))
                else
                    combined:Begin(table.unpack(results))
                end
            end

            return true
        end)
    end

    return M.Sync(combined)
end

return M
