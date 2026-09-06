-- Simple Remote Spy (Console Only) - HookFunction Version

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Helper to format arguments into a readable string
local function formatArgs(...)
    local args = {...}
    local strings = {}
    for i, v in pairs(args) do
        if typeof(v) == "table" then
            -- Basic table dump
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

-- Create dummy instances to get the real function references
local dummyEvent = Instance.new("RemoteEvent")
local dummyFunction = Instance.new("RemoteFunction")

-- Store the original functions
local oldFireServer = dummyEvent.FireServer
local oldInvokeServer = dummyFunction.InvokeServer

-- Clean up the dummies
dummyEvent:Destroy()
dummyFunction:Destroy()

-- Define the new FireServer function
local newFireServer = newcclosure(function(self, ...)
    -- self is the RemoteEvent being fired
    print("[FIRE SERVER] " .. self:GetFullName() .. " | Args: " .. formatArgs(...))
    
    -- Execute the original function so the game doesn't break
    return oldFireServer(self, ...)
end)

-- Define the new InvokeServer function
local newInvokeServer = newcclosure(function(self, ...)
    -- self is the RemoteFunction being invoked
    print("[INVOKE SERVER] " .. self:GetFullName() .. " | Args: " .. formatArgs(...))
    
    -- Execute the original function
    return oldInvokeServer(self, ...)
end)

-- Apply the hooks
hookfunction(oldFireServer, newFireServer)
hookfunction(oldInvokeServer, newInvokeServer)

print("Remote Spy Loaded: Using hookfunction")
