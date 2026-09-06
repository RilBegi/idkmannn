local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local WebSocket = WebSocket or syn and syn.websocket or nil
if not WebSocket then
    error("Current executor does not support WebSocket. Please use sUNC or syn environment.")
end

local WS_URL = "wss://frhk3f27-4000.euw.devtunnels.ms/" 
local ws = WebSocket.new(WS_URL)

ws.OnMessage:Connect(function(message)
    local data = HttpService:JSONDecode(message)
    if not data then return end

    if data.type == "execute" and data.script then
        local func, err = loadstring(data.script)
        if func then
            local success, result = pcall(func)
            if not success then
                ws:Send(HttpService:JSONEncode({
                    type = "execute_result",
                    success = false,
                    error = tostring(result)
                }))
            end
        else
            ws:Send(HttpService:JSONEncode({
                type = "execute_result",
                success = false,
                error = "Script syntax error: " .. tostring(err)
            }))
        end
    elseif data.type == "ping" then
        ws:Send(HttpService:JSONEncode({ type = "pong" }))
    end
end)

ws.OnClose:Connect(function()
    warn("WebSocket disconnected")
end)

ws.OnOpen:Connect(function()
    ws:Send(HttpService:JSONEncode({
        type = "handshake",
        player = LocalPlayer.Name,
        userId = LocalPlayer.UserId
    }))
end)

local function SerializeInstance(instance, visited)
    visited = visited or {}
    if visited[instance] then
        return { Reference = "circular" }
    end
    visited[instance] = true

    local info = {
        Name = instance.Name,
        ClassName = instance.ClassName,
        Parent = instance.Parent and instance.Parent.Name or nil,
        Properties = {},
        Children = {}
    }

    local propList = {"Position", "Size", "Color", "BackgroundColor3", "Text", "Value", "Visible", "Enabled"}
    for _, prop in ipairs(propList) do
        local success, val = pcall(function() return instance[prop] end)
        if success and val ~= nil then
            if typeof(val) == "Vector3" or typeof(val) == "UDim2" or typeof(val) == "Color3" then
                info.Properties[prop] = tostring(val)
            else
                info.Properties[prop] = val
            end
        end
    end

    local children = instance:GetChildren()
    for _, child in ipairs(children) do
        if #info.Children < 500 then
            table.insert(info.Children, SerializeInstance(child, visited))
        end
    end

    return info
end

local function GenerateExplorerReport()
    local report = {
        timestamp = os.time(),
        player = LocalPlayer.Name,
        game = {
            name = game.Name,
            placeId = game.PlaceId,
            jobId = game.JobId
        },
        root = SerializeInstance(game)
    }
    return HttpService:JSONEncode(report)
end

local function SendExplorerReport()
    if ws and ws.State == WebSocket.State.Open then
        local json = GenerateExplorerReport()
        ws:Send(HttpService:JSONEncode({
            type = "explorer_report",
            data = json
        }))
    end
end

local explorerUpdatePending = false

local function ScheduleExplorerUpdate()
    if not explorerUpdatePending then
        explorerUpdatePending = true
        task.defer(function()
            explorerUpdatePending = false
            SendExplorerReport()
        end)
    end
end

task.spawn(function()
    while ws and ws.State == WebSocket.State.Open do
        task.wait(1)
        SendExplorerReport()
    end
end)

game.DescendantAdded:Connect(ScheduleExplorerUpdate)
game.DescendantRemoved:Connect(ScheduleExplorerUpdate)

local RemoteReport = {
    enabled = true,
    maxLogs = 300,
    logs = {}
}

local function SafeSerialize(args, depth)
    depth = depth or 0
    if depth > 3 then return "[depth limit]" end
    local result = {}
    for i, v in ipairs(args) do
        local t = typeof(v)
        if t == "string" or t == "number" or t == "boolean" then
            result[i] = v
        elseif t == "Instance" then
            result[i] = string.format("[Instance: %s (%s)]", v.Name, v.ClassName)
        elseif t == "table" then
            result[i] = SafeSerialize(v, depth + 1)
        elseif t == "function" then
            result[i] = "[Function]"
        else
            result[i] = tostring(v)
        end
    end
    return result
end

local function ReportRemote(name, args, isFunction)
    if not RemoteReport.enabled then return end

    if #RemoteReport.logs >= RemoteReport.maxLogs then
        table.remove(RemoteReport.logs, 1)
    end

    local entry = {
        name = name,
        args = SafeSerialize(args),
        isFunction = isFunction or false,
        timestamp = os.time(),
        caller = getcallingscript and getcallingscript().Name or "Unknown"
    }
    table.insert(RemoteReport.logs, entry)

    ws:Send(HttpService:JSONEncode({
        type = "remote_report",
        data = entry
    }))
end

local oldFireServer = nil
local function HookRemoteEvent()
    local meta = getrawmetatable(game)
    if not meta then return end

    local oldIndex = meta.__index
    meta.__index = function(self, key)
        if key == "FireServer" and self:IsA("RemoteEvent") then
            return function(remote, ...)
                local args = {...}
                ReportRemote(remote.Name, args, false)
                return oldFireServer(remote, ...)
            end
        end
        return oldIndex(self, key)
    end
    setreadonly(meta, false)
    meta.__index = oldIndex
    setreadonly(meta, true)
end

local oldInvokeServer = nil
local function HookRemoteFunction()
    local meta = getrawmetatable(game)
    if not meta then return end

    local oldIndex = meta.__index
    meta.__index = function(self, key)
        if key == "InvokeServer" and self:IsA("RemoteFunction") then
            return function(remote, ...)
                local args = {...}
                ReportRemote(remote.Name, args, true)
                return oldInvokeServer(remote, ...)
            end
        end
        return oldIndex(self, key)
    end
    setreadonly(meta, false)
    meta.__index = oldIndex
    setreadonly(meta, true)
end

local function InitRemoteHooks()
    if not hookfunction or not getrawmetatable then
        warn("Current environment does not support hooking. Remote Report unavailable.")
        return
    end

    pcall(function()
        for _, obj in ipairs(game:GetDescendants()) do
            if obj:IsA("RemoteEvent") then
                if not oldFireServer then
                    oldFireServer = obj.FireServer
                end
            elseif obj:IsA("RemoteFunction") then
                if not oldInvokeServer then
                    oldInvokeServer = obj.InvokeServer
                end
            end
        end
    end)

    HookRemoteEvent()
    HookRemoteFunction()
    print("[Remote Report] Hooks installed.")
end

game.DescendantAdded:Connect(function(child)
    if child:IsA("RemoteEvent") and not oldFireServer then
        oldFireServer = child.FireServer
        HookRemoteEvent()
    elseif child:IsA("RemoteFunction") and not oldInvokeServer then
        oldInvokeServer = child.InvokeServer
        HookRemoteFunction()
    end
end)

local function Initialize()
    pcall(InitRemoteHooks)

    print("[Client] Multi‑function client started.")
    print("[Client] WebSocket: " .. WS_URL)
    print("[Client] Explorer Report: auto‑send every 1s + instant on structural changes.")
    print("[Client] Remote Report: " .. (RemoteReport.enabled and "enabled" or "disabled"))
    print("[Client] Remote Execution: ready.")
end

pcall(Initialize)

_G.ClientCommands = {
    sendExplorer = SendExplorerReport,
    toggleRemoteSpy = function(enabled)
        RemoteReport.enabled = (enabled ~= false)
        print("[Remote Report] Status: " .. tostring(RemoteReport.enabled))
    end,
    getRemoteLogs = function()
        return RemoteReport.logs
    end
}

game:BindToClose(function()
    if ws then
        pcall(ws.Close, ws)
    end
end)
