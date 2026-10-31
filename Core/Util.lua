local _, ns = ...

local PREFIX = "|cff33ccffGryphonThreat|r: "

-- Prints a message to the default chat frame with the addon prefix.
function ns:Print(message, ...)
    if select("#", ...) > 0 then
        message = message:format(...)
    end
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(message))
end

-- Prints a message the addon shows on its own (not as the answer to a command). The user can turn
-- these off with "/gryphonthreat notify off".
function ns:Notify(message, ...)
    if self.charDb and self.charDb.notifications then
        self:Print(message, ...)
    end
end

-- Prints only when debug mode is enabled in the saved variables.
function ns:Debug(message, ...)
    if self.db and self.db.debug then
        self:Print("|cff999999[debug]|r " .. tostring(message), ...)
    end
end

-- Memory the addon keeps (in KB) after a full garbage collection. Slow (collects garbage and scans
-- every addon), so it is only used in debug mode.
local function GetRetainedMemory()
    collectgarbage("collect")
    UpdateAddOnMemoryUsage()
    return GetAddOnMemoryUsage(ns.name)
end

-- Calls fn(...). In debug mode, also prints how much memory it retained afterwards.
function ns:MeasureMemory(label, fn, ...)
    if not (self.db and self.db.debug) then
        fn(...)
        return
    end
    local before = GetRetainedMemory()
    fn(...)
    local after = GetRetainedMemory()
    self:Debug("Memory %s: %+.1f KB (total %.1f KB)", label, after - before, after)
end

-- In debug mode, prints the memory the addon currently retains.
function ns:DebugMemory(label)
    if self.db and self.db.debug then
        self:Debug("Memory %s: %.1f KB", label, GetRetainedMemory())
    end
end

-- In debug mode, prints the memory the addon uses right now, including garbage that was not
-- collected yet. Without a garbage collection, so it can run at combat start without a stutter.
function ns:DebugCurrentMemory(label)
    if self.db and self.db.debug then
        UpdateAddOnMemoryUsage()
        self:Debug("Memory %s: %.1f KB", label, GetAddOnMemoryUsage(self.name))
    end
end

-- Recursively copies missing default values into the target table.
function ns.ApplyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            ns.ApplyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end
