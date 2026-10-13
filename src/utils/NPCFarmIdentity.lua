-- =========================================================
-- FS25 NPC Favor Mod - Farm identity helpers (RSF-F148)
-- =========================================================
-- One place that answers "is this an ordinary farm" and "who is acting"
-- for every favor path. Native User carries no farmId field, so the acting
-- farm is always resolved through g_currentMission:getFarmId(connection),
-- whose server branch reads getPlayerByConnection(connection). A client's
-- own farm id is only ever a claim; the server re-resolves it.
--
-- Engine facts (FarmManager.lua:2-8, verified in the decompiled scripts):
--   SPECTATOR_FARM_ID   = 0
--   MAX_FARM_ID         = 8
--   GUIDED_TOUR_FARM_ID = 14
--   INVALID_FARM_ID     = 15
-- =========================================================

NPCFarmIdentity = NPCFarmIdentity or {}

NPCFarmIdentity.WIRE_MAX = 2147483647
NPCFarmIdentity.WIRE_MAX_DIGITS = 10

local function farmConst(name, fallback)
    if FarmManager ~= nil and FarmManager[name] ~= nil then
        return FarmManager[name]
    end
    return fallback
end

function NPCFarmIdentity.spectatorFarmId()  return farmConst("SPECTATOR_FARM_ID", 0) end
function NPCFarmIdentity.maxFarmId()        return farmConst("MAX_FARM_ID", 8) end
function NPCFarmIdentity.guidedTourFarmId() return farmConst("GUIDED_TOUR_FARM_ID", 14) end
function NPCFarmIdentity.invalidFarmId()    return farmConst("INVALID_FARM_ID", 15) end

--- True when value is a finite integer.
function NPCFarmIdentity.isInteger(value)
    return type(value) == "number" and value == value and value ~= math.huge
        and value ~= -math.huge and value == math.floor(value)
end

--- True when farmId is an integer in 1..MAX_FARM_ID that is not one of the
--- special farms. Does not consult the farm manager.
function NPCFarmIdentity.isOrdinaryFarmIdShape(farmId)
    if not NPCFarmIdentity.isInteger(farmId) then return false end
    if farmId < 1 or farmId > NPCFarmIdentity.maxFarmId() then return false end
    if farmId == NPCFarmIdentity.spectatorFarmId()
        or farmId == NPCFarmIdentity.guidedTourFarmId()
        or farmId == NPCFarmIdentity.invalidFarmId() then
        return false
    end
    return true
end

--- Return the live farm object for farmId, or nil when the manager is absent
--- or the id does not resolve.
function NPCFarmIdentity.getLiveFarm(farmId)
    if g_farmManager == nil or type(g_farmManager.getFarmById) ~= "function" then
        return nil
    end
    return g_farmManager:getFarmById(farmId)
end

--- True when farmId has the ordinary shape AND the farm manager currently
--- holds a farm for it. This is the one test every own-farm operation and
--- every assignment target must pass.
function NPCFarmIdentity.isOrdinaryFarmId(farmId)
    if not NPCFarmIdentity.isOrdinaryFarmIdShape(farmId) then return false end
    return NPCFarmIdentity.getLiveFarm(farmId) ~= nil
end

--- The local machine's acting farm as a CLAIM. Returns nil when unavailable
--- (no mission, spectator, guided tour, invalid, or no farm behind the id).
--- Never defaults to farm 0 or farm 1.
function NPCFarmIdentity.localClaimFarmId()
    if g_currentMission == nil or type(g_currentMission.getFarmId) ~= "function" then
        return nil
    end
    local ok, farmId = pcall(function() return g_currentMission:getFarmId() end)
    if not ok then return nil end
    if NPCFarmIdentity.isOrdinaryFarmId(farmId) then
        return farmId
    end
    return nil
end

--- Resolve the verified server-side actor for a request.
--- connection == nil is the local host entry: only valid on a listen server or
--- single player where g_server and g_localPlayer both exist. A dedicated
--- server has no local player and therefore no actor for a nil connection;
--- no console or nil-connection administrator bypass exists.
--- @return table|nil { connectionId, connection, farmId, rawFarmId, isMaster, isLocal }
function NPCFarmIdentity.resolveActor(connection)
    if g_server == nil or g_currentMission == nil then
        return nil
    end

    if connection == nil then
        if g_localPlayer == nil then
            return nil
        end
        local rawFarmId = nil
        if type(g_currentMission.getFarmId) == "function" then
            rawFarmId = g_currentMission:getFarmId()
        end
        local actor = {
            connectionId = "local",
            connection = nil,
            rawFarmId = rawFarmId,
            farmId = nil,
            isMaster = true,
            isLocal = true,
        }
        if NPCFarmIdentity.isOrdinaryFarmId(rawFarmId) then
            actor.farmId = rawFarmId
        end
        return actor
    end

    local userManager = g_currentMission.userManager
    if userManager == nil or type(userManager.getUserByConnection) ~= "function" then
        return nil
    end
    local user = userManager:getUserByConnection(connection)
    if user == nil then
        return nil
    end

    local rawFarmId = nil
    if type(g_currentMission.getFarmId) == "function" then
        rawFarmId = g_currentMission:getFarmId(connection)
    end

    local userId = nil
    if type(user.getId) == "function" then
        userId = user:getId()
    end
    if userId == nil then
        return nil
    end

    local isMaster = false
    if type(user.getIsMasterUser) == "function" then
        isMaster = (user:getIsMasterUser() == true)
    end

    local actor = {
        connectionId = "user:" .. tostring(userId),
        connection = connection,
        rawFarmId = rawFarmId,
        farmId = nil,
        isMaster = isMaster,
        isLocal = false,
    }
    if NPCFarmIdentity.isOrdinaryFarmId(rawFarmId) then
        actor.farmId = rawFarmId
    end
    return actor
end

--- Bounded ASCII decimal wire number: digits only, at most 10 characters,
--- decoded value in 0..2147483647. Never evaluated as Lua.
function NPCFarmIdentity.validWireNumber(value)
    if type(value) ~= "string" then return false end
    if #value == 0 or #value > NPCFarmIdentity.WIRE_MAX_DIGITS then return false end
    if not value:match("^%d+$") then return false end
    local n = tonumber(value)
    return n ~= nil and n >= 0 and n <= NPCFarmIdentity.WIRE_MAX
end

--- A selection token is a wire number that is strictly positive.
function NPCFarmIdentity.validToken(value)
    if not NPCFarmIdentity.validWireNumber(value) then return false end
    return tonumber(value) > 0
end

--- Decode a validated wire number to a Lua number, or nil.
function NPCFarmIdentity.decodeWireNumber(value)
    if not NPCFarmIdentity.validWireNumber(value) then return nil end
    return tonumber(value)
end

--- Encode a non-negative integer as a wire number string, or nil when out of range.
function NPCFarmIdentity.encodeWireNumber(n)
    if not NPCFarmIdentity.isInteger(n) or n < 0 or n > NPCFarmIdentity.WIRE_MAX then
        return nil
    end
    return string.format("%d", n)
end
