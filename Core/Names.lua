local _, ns = ...

-- Character names differ per client (see Compat.HasRealmNames):
--   Forever: "First Surname" ("Tor Donnerstein"), unique per region, without a realm. Names from
--            other APIs may still carry a "-Realm" suffix, which is ignored.
--   Retail:  "Name-Realm" ("Tor-Gehennas"). The APIs leave out the realm for characters of the own
--            realm, so names are compared with the own realm filled in.
local Names = {}
ns.Names = Names

local separatorConsts = Constants and Constants.CharacterNameSeparatorConsts
local SEPARATOR = separatorConsts and separatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or " "

local function IsUsableString(value)
    return type(value) == "string" and not (issecretvalue and issecretvalue(value)) and value ~= ""
end

-- Does not change during a session; cached because names are compared for every mail and filter.
local hasRealmNames

local function HasRealmNames()
    if hasRealmNames == nil then
        hasRealmNames = ns.Compat.HasRealmNames()
    end
    return hasRealmNames
end

-- Realm of the logged-in character as used in "Name-Realm" (without spaces), or nil while it is not
-- available yet.
local function GetOwnRealm()
    local realm = GetNormalizedRealmName()
    return IsUsableString(realm) and realm or nil
end

-- "Tor", "Donnerstein" -> "Tor Donnerstein"; without surname just the first name.
function Names.Join(firstName, surname)
    if IsUsableString(surname) then
        return firstName .. SEPARATOR .. surname
    end
    return firstName
end

-- Comparable form of a name: on Forever without realm suffix, on Retail always
-- "Name-Realm". Returns nil for secret or empty values.
function Names.Normalize(name)
    if not IsUsableString(name) then
        return nil
    end
    if not HasRealmNames() then
        return (name:gsub("%-.*$", ""))
    end
    if name:find("-", 1, true) then
        return name
    end
    local realm = GetOwnRealm()
    return realm and (name .. "-" .. realm) or name
end

-- Realm part of a normalized name, nil on Forever or without realm.
function Names.GetRealm(name)
    return HasRealmNames() and name:match("%-(.+)$") or nil
end

-- Form to show and to enter as mail recipient: the short name for the own realm, otherwise the
-- normalized name. Names on Forever are returned unchanged.
function Names.ToDisplay(name)
    if not HasRealmNames() then
        return name
    end
    local shortName, realm = name:match("^(.-)%-(.+)$")
    if shortName and realm == GetOwnRealm() then
        return shortName
    end
    return name
end

-- "Tor Donnerstein" -> "Tor" on Forever, "Tor-Gehennas" -> "Tor" on Retail.
function Names.GetFirstName(name)
    if HasRealmNames() then
        return name:match("^[^%-]+") or name
    end
    return name:match("^%S+") or name
end

-- Full name of the logged-in character, or nil while it is not available. UnitName("player")
-- returns first name and surname on Forever, and the name without realm on Retail.
function Names.GetPlayerName()
    local firstName, surname = UnitName("player")
    if not IsUsableString(firstName) then
        return nil
    end
    if HasRealmNames() then
        -- Without the realm the name could not be told apart from same-named characters.
        local realm = GetOwnRealm()
        return realm and (firstName .. "-" .. realm) or nil
    end
    return Names.Join(firstName, surname)
end
