-- 远程流量嗅探器 (基于 SimpleSpy 日志逻辑重构)
-- 使用 hookfunction 拦截所有远程通讯

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- ============ SimpleSpy 风格的基础设施 ============
local running = coroutine.running
local resume = coroutine.resume
local yield = coroutine.yield
local create = coroutine.create
local status = coroutine.status
local delay = task.delay
local spawn = task.spawn

-- 日志存储（SimpleSpy 风格）
local remoteLogs = {}          -- 存储所有日志条目
local MAX_REMOTES = 300        -- 最大日志数量，防止内存溢出

-- 清理函数：防止远程调用过多导致卡顿
local function cleanLogs()
    local max = MAX_REMOTES
    if #remoteLogs > max then
        for i = 100, #remoteLogs do
            local v = remoteLogs[i]
            if typeof(v[1]) == "RBXScriptConnection" then
                v[1]:Disconnect()
            end
            if typeof(v[2]) == "Instance" then
                v[2]:Destroy()
            end
        end
        local newLogs = {}
        for i = 1, 100 do
            table.insert(newLogs, remoteLogs[i])
        end
        remoteLogs = newLogs
    end
end

-- ============ SimpleSpy 风格的日志记录 ============
-- 将参数转换为可读字符串（SimpleSpy 的 deepclone + tostring 逻辑）
local function argsToString(...)
    local args = {...}
    local result = {}
    for i, v in ipairs(args) do
        local t = type(v)
        if t == "table" or t == "userdata" then
            -- 尝试获取 __tostring
            local mt = getrawmetatable(v)
            local tostr = mt and rawget(mt, "__tostring")
            if tostr then
                result[i] = tostring(v)
            else
                result[i] = "[" .. t .. "]"
            end
        elseif t == "string" then
            result[i] = '"' .. v .. '"'
        elseif t == "number" or t == "boolean" then
            result[i] = tostring(v)
        elseif t == "function" then
            result[i] = "[Function]"
        elseif t == "thread" then
            result[i] = "[Thread]"
        else
            result[i] = tostring(v)
        end
    end
    return table.concat(result, ", ")
end

-- SimpleSpy 风格的日志函数
local function logRemoteCall(callType, remoteObject, ...)
    local args = {...}
    local argsStr = argsToString(...)
    
    -- 构建日志条目（SimpleSpy 格式）
    local logEntry = {
        callType,                    -- 调用类型 (FireServer, InvokeServer, etc.)
        remoteObject,                -- 远程对象本身
        os.time(),                   -- 时间戳
        argsStr,                     -- 参数文本
        getcallingscript and getcallingscript() or nil  -- 调用脚本
    }
    
    -- 存入日志表
    table.insert(remoteLogs, logEntry)
    
    -- 打印到控制台（SimpleSpy 同时输出到 GUI 和控制台）
    print(string.format("[Sniffer] %s called on %s with args: %s", 
        callType, tostring(remoteObject), argsStr))
    
    -- 清理过旧日志
    cleanLogs()
end

-- ============ SimpleSpy 风格的 Hook 逻辑 ============
local function safeHook(func, hook)
    if type(func) == "function" and type(hook) == "function" then
        local success, original = pcall(hookfunction, func, hook)
        if success then
            return original
        else
            warn("[Sniffer] Hook failed:", original)
            return func
        end
    end
    return func
end

local function hookRemoteObject(remoteObject)
    if not remoteObject then return end

    local objectType = remoteObject.ClassName

    -- 根据类型决定要 Hook 的方法
    local methodsToHook = {}
    if objectType == "RemoteEvent" or objectType == "UnreliableRemoteEvent" then
        methodsToHook = {"FireServer", "FireClient", "FireAllClients"}
    elseif objectType == "RemoteFunction" then
        methodsToHook = {"InvokeServer", "InvokeClient"}
    elseif objectType == "BindableEvent" then
        methodsToHook = {"Fire"}
    elseif objectType == "BindableFunction" then
        methodsToHook = {"Invoke"}
    end

    for _, methodName in ipairs(methodsToHook) do
        local originalMethod = remoteObject[methodName]
        if type(originalMethod) == "function" then
            local hookFunction = function(...)
                -- SimpleSpy 风格：异步日志记录，避免阻塞
                local args = {...}
                spawn(function()
                    logRemoteCall(methodName, remoteObject, unpack(args))
                end)
                -- 调用原始方法
                return originalMethod(remoteObject, ...)
            end
            safeHook(originalMethod, hookFunction)
        end
    end
end

-- ============ 遍历所有远程对象 ============
local function hookAllRemotes()
    local services = {
        game:GetService("ReplicatedStorage"),
        game:GetService("Workspace"),
        game:GetService("ServerStorage")
    }
    for _, service in ipairs(services) do
        for _, descendant in ipairs(service:GetDescendants()) do
            local class = descendant.ClassName
            if class == "RemoteEvent" or class == "RemoteFunction" or 
               class == "BindableEvent" or class == "BindableFunction" or 
               class == "UnreliableRemoteEvent" then
                hookRemoteObject(descendant)
            end
        end
    end
end

-- ============ 监听新创建的远程对象 ============
local function watchForNewRemotes(service)
    service.ChildAdded:Connect(function(child)
        task.wait()
        local class = child.ClassName
        if class == "RemoteEvent" or class == "RemoteFunction" or 
           class == "BindableEvent" or class == "BindableFunction" or 
           class == "UnreliableRemoteEvent" then
            hookRemoteObject(child)
        end
        child.DescendantAdded:Connect(function(descendant)
            local descClass = descendant.ClassName
            if descClass == "RemoteEvent" or descClass == "RemoteFunction" or 
               descClass == "BindableEvent" or descClass == "BindableFunction" or 
               descClass == "UnreliableRemoteEvent" then
                hookRemoteObject(descendant)
            end
        end)
    end)
end

-- ============ 初始化 ============
local function init()
    print("[Sniffer] Initializing Remote Traffic Sniffer (SimpleSpy style)...")
    
    -- Hook 所有已存在的远程对象
    hookAllRemotes()
    
    -- 监听新对象
    local servicesToWatch = {
        game:GetService("ReplicatedStorage"),
        game:GetService("Workspace"),
        game:GetService("ServerStorage")
    }
    for _, service in ipairs(servicesToWatch) do
        watchForNewRemotes(service)
    end
    
    print("[Sniffer] Sniffer active. Monitoring all remote traffic.")
    print(string.format("[Sniffer] Max logs: %d (auto-cleanup enabled)", MAX_REMOTES))
end

-- 启动
init()
