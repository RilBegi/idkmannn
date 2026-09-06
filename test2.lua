local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

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

local function logRemoteCall(callType, remoteObject, ...)
    local args = {...}
    local argsStr = table.concat(args, ", ")
    print(string.format("[Sniffer] %s called on %s with args: %s", callType, tostring(remoteObject), argsStr))
end

local function hookRemoteObject(remoteObject)
    if not remoteObject then return end

    local objectName = tostring(remoteObject)
    local objectType = remoteObject.ClassName

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
                logRemoteCall(methodName, remoteObject, ...)
                return originalMethod(remoteObject, ...)
            end
            safeHook(originalMethod, hookFunction)
        end
    end
end

local function hookAllRemotes()
    local services = {game:GetService("ReplicatedStorage"), game:GetService("Workspace"), game:GetService("ServerStorage")}
    for _, service in ipairs(services) do
        for _, descendant in ipairs(service:GetDescendants()) do
            local class = descendant.ClassName
            if class == "RemoteEvent" or class == "RemoteFunction" or class == "BindableEvent" or class == "BindableFunction" or class == "UnreliableRemoteEvent" then
                hookRemoteObject(descendant)
            end
        end
    end
end

local function watchForNewRemotes(service)
    service.ChildAdded:Connect(function(child)
        task.wait()
        local class = child.ClassName
        if class == "RemoteEvent" or class == "RemoteFunction" or class == "BindableEvent" or class == "BindableFunction" or class == "UnreliableRemoteEvent" then
            hookRemoteObject(child)
        end
        child.DescendantAdded:Connect(function(descendant)
            local descClass = descendant.ClassName
            if descClass == "RemoteEvent" or descClass == "RemoteFunction" or descClass == "BindableEvent" or descClass == "BindableFunction" or descClass == "UnreliableRemoteEvent" then
                hookRemoteObject(descendant)
            end
        end)
    end)
end

local function init()
    print("[Sniffer] Initializing Remote Traffic Sniffer...")
    hookAllRemotes()
    local servicesToWatch = {game:GetService("ReplicatedStorage"), game:GetService("Workspace"), game:GetService("ServerStorage")}
    for _, service in ipairs(servicesToWatch) do
        watchForNewRemotes(service)
    end
    print("[Sniffer] Sniffer is now active. Monitoring all remote traffic.")
end

init()
