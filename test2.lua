-- Simple Remote Spy (Console Only)
-- Based on SimpleSpy logic

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Helper function to format arguments into a readable string
local function formatArgs(...)
    local args = {...}
    local strings = {}
    for i, v in pairs(args) do
        if type(v) == "table" then
            -- Simple table formatting
            local s = {}
            for k, v2 in pairs(v) do
                table.insert(s, tostring(k) .. "=" .. tostring(v2))
            end
            strings[i] = "{" .. table.concat(s, ", ") .. "}"
        else
            strings[i] = tostring(v)
        end
    end
    return table.concat(strings, ", ")
end

-- Core Hooking Logic
local function hookRemote(remote)
    -- Hook RemoteEvents (FireServer)
    if remote:IsA("RemoteEvent") then
        local oldFireServer = remote:FireServer
        remote:FireServer = function(self, ...)
            print("[FIRE] " .. remote:GetFullName() .. " | Args: " .. formatArgs(...))
            return oldFireServer(self, ...)
        end
    end

    -- Hook RemoteFunctions (InvokeServer)
    if remote:IsA("RemoteFunction") then
        local oldInvokeServer = remote.InvokeServer
        remote.InvokeServer = function(self, ...)
            print("[INVOKE] " .. remote:GetFullName() .. " | Args: " .. formatArgs(...))
            return oldInvokeServer(self, ...)
        end
    end
end

-- 1. Hook existing remotes in the game
for _, v in pairs(game:GetDescendants()) do
    hookRemote(v)
end

-- 2. Hook remotes that are added later (streaming service or late loading)
game.DescendantAdded:Connect(function(v)
    hookRemote(v)
end)

print("Remote Spy Loaded: Listening for Remotes...")
