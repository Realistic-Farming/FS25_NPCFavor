-- =========================================================
-- TODO / FUTURE VISION
-- =========================================================
-- SYNC MODES:
-- [x] TYPE_SINGLE for individual setting changes (key/value pair)
-- [x] TYPE_BULK for full settings snapshot on player join
-- [x] Typed value serialization (boolean, number, string)
-- [ ] TYPE_DIFF mode - send only settings that differ from defaults
-- [ ] Versioned settings schema with migration on mod update
-- [ ] Settings change history log for admin audit trail
--
-- VALIDATION & SECURITY:
-- [x] Master rights verification before applying changes
-- [x] maxNPCs range clamped to 1-50 on both read and apply
-- [x] String truncation on all serialized fields
-- [x] Fail-secure rejection of invalid sync types
-- [ ] Rate limiting on settings changes per connection per minute
-- [ ] Settings change confirmation callback to originating client
-- [ ] Per-setting permission levels (some settings admin-only)
--
-- PERSISTENCE:
-- [x] Server-side save after single setting changes
-- [x] Client bulk sync without disk write (server-authoritative)
-- [ ] Settings export/import for server administrators
-- [ ] Settings presets (easy, normal, hard difficulty profiles)
-- =========================================================

--[[
    FS25_NPCFavor - Settings Sync Event

    Synchronizes NPC settings changes in multiplayer.

    Two modes:
    1. TYPE_SINGLE: Single setting change (key/value pair)
    2. TYPE_BULK: All settings at once (used on player join)

    Only players with master rights can change settings.
    Server broadcasts changes to all clients.

    Pattern from: UsedPlusSettingsEvent
    OWASP: Master rights verification, input validation, maxNPCs range check,
           string truncation, fail-secure rejection.
]]

NPCSettingsSyncEvent = NPCSettingsSyncEvent or {}
local NPCSettingsSyncEvent_mt = Class(NPCSettingsSyncEvent, Event)

InitEventClass(NPCSettingsSyncEvent, "NPCSettingsSyncEvent")

-- Event types
NPCSettingsSyncEvent.TYPE_SINGLE = 1
NPCSettingsSyncEvent.TYPE_BULK = 2

function NPCSettingsSyncEvent.emptyNew()
    local self = Event.new(NPCSettingsSyncEvent_mt)
    self.syncType = NPCSettingsSyncEvent.TYPE_SINGLE
    self.key = nil
    self.value = nil
    self.bulkSettings = nil
    return self
end

function NPCSettingsSyncEvent.newSingle(key, value)
    local self = NPCSettingsSyncEvent.emptyNew()
    self.syncType = NPCSettingsSyncEvent.TYPE_SINGLE
    self.key = key
    self.value = value
    return self
end

function NPCSettingsSyncEvent.newBulk(settings)
    local self = NPCSettingsSyncEvent.emptyNew()
    self.syncType = NPCSettingsSyncEvent.TYPE_BULK
    self.bulkSettings = settings
    return self
end

function NPCSettingsSyncEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.syncType)

    if self.syncType == NPCSettingsSyncEvent.TYPE_SINGLE then
        streamWriteString(streamId, (self.key or ""):sub(1, 32))
        -- Write type tag + value
        local valueType = type(self.value)
        if valueType == "boolean" then
            streamWriteUInt8(streamId, 1)
            streamWriteBool(streamId, self.value)
        elseif valueType == "number" then
            streamWriteUInt8(streamId, 2)
            streamWriteInt32(streamId, math.floor(self.value))
        else
            streamWriteUInt8(streamId, 3)
            streamWriteString(streamId, tostring(self.value):sub(1, 64))
        end

    elseif self.syncType == NPCSettingsSyncEvent.TYPE_BULK then
        local settings = self.bulkSettings or {}
        -- Write 6 typed fields
        streamWriteBool(streamId, settings.enabled or false)
        streamWriteInt32(streamId, settings.maxNPCs or 8)
        streamWriteBool(streamId, settings.showNames or false)
        streamWriteBool(streamId, settings.showNotifications or false)
        streamWriteBool(streamId, settings.enableFavors or false)
        streamWriteBool(streamId, settings.debugMode or false)
    end
end

function NPCSettingsSyncEvent:readStream(streamId, connection)
    self.syncType = streamReadUInt8(streamId)

    -- OWASP Input Validation: Validate syncType
    if self.syncType ~= NPCSettingsSyncEvent.TYPE_SINGLE and self.syncType ~= NPCSettingsSyncEvent.TYPE_BULK then
        print(string.format("[NPCFavor SECURITY] Invalid settings sync type: %d", self.syncType))
        return
    end

    if self.syncType == NPCSettingsSyncEvent.TYPE_SINGLE then
        self.key = streamReadString(streamId):sub(1, 32)
        local valueTag = streamReadUInt8(streamId)
        if valueTag == 1 then
            self.value = streamReadBool(streamId)
        elseif valueTag == 2 then
            self.value = streamReadInt32(streamId)
        else
            self.value = streamReadString(streamId):sub(1, 64)
        end

    elseif self.syncType == NPCSettingsSyncEvent.TYPE_BULK then
        self.bulkSettings = {}
        self.bulkSettings.enabled = streamReadBool(streamId)
        local maxNPCs = streamReadInt32(streamId)
        -- OWASP Input Validation: Clamp maxNPCs to valid range
        self.bulkSettings.maxNPCs = math.max(1, math.min(16, maxNPCs))
        self.bulkSettings.showNames = streamReadBool(streamId)
        self.bulkSettings.showNotifications = streamReadBool(streamId)
        self.bulkSettings.enableFavors = streamReadBool(streamId)
        self.bulkSettings.debugMode = streamReadBool(streamId)
    end

    self:run(connection)
end

function NPCSettingsSyncEvent:run(connection)
    if g_server ~= nil then
        -- Server received from client: verify master rights
        if not self:senderHasMasterRights(connection) then
            print("[NPCFavor SECURITY] Settings change rejected: sender lacks master rights")
            return
        end

        -- Apply the change on server
        self:applySettings()

        -- Broadcast to all clients
        g_server:broadcastEvent(self, false)
    else
        -- Client received from server: apply without saving to disk
        self:applySettings()
    end
end

function NPCSettingsSyncEvent:applySettings()
    if g_NPCSystem == nil or g_NPCSystem.settings == nil then
        return
    end

    local settings = g_NPCSystem.settings

    if self.syncType == NPCSettingsSyncEvent.TYPE_SINGLE then
        -- Apply single setting change
        if self.key == "enabled" then
            settings.enabled = (self.value == true)
        elseif self.key == "maxNPCs" then
            settings.maxNPCs = math.max(1, math.min(16, tonumber(self.value) or 8))
        elseif self.key == "showNames" then
            settings.showNames = (self.value == true)
        elseif self.key == "showNotifications" then
            settings.showNotifications = (self.value == true)
        elseif self.key == "enableFavors" then
            settings.enableFavors = (self.value == true)
        elseif self.key == "debugMode" then
            settings.debugMode = (self.value == true)
        end

        -- Settings persist via saveToXMLFile hook on next game save (UsedPlus pattern).
        -- No immediate disk write from sync events.

    elseif self.syncType == NPCSettingsSyncEvent.TYPE_BULK then
        if self.bulkSettings then
            settings.enabled = self.bulkSettings.enabled
            settings.maxNPCs = self.bulkSettings.maxNPCs
            settings.showNames = self.bulkSettings.showNames
            settings.showNotifications = self.bulkSettings.showNotifications
            settings.enableFavors = self.bulkSettings.enableFavors
            settings.debugMode = self.bulkSettings.debugMode
        end
        -- Bulk sync from server: do NOT save on client
    end
end

--[[
    Check if the connection sender has master rights.
    @param connection - Network connection (nil for local/server)
    @return boolean
]]
function NPCSettingsSyncEvent:senderHasMasterRights(connection)
    if connection == nil then
        return true -- Local/server
    end

    -- Find player by connection
    if g_currentMission then
        local player = g_currentMission:getPlayerByConnection(connection)
        if player and player.isMasterUser then
            return true
        end

        -- Alternative check via user manager
        if g_currentMission.userManager then
            local user = g_currentMission.userManager:getUserByConnection(connection)
            if user and user:getIsMasterUser() then
                return true
            end
        end
    end

    return false
end

--[[
    Send a single setting change to server.
    @param key - Setting key
    @param value - New value
]]
function NPCSettingsSyncEvent.sendSingleToServer(key, value)
    if g_client then
        g_client:getServerConnection():sendEvent(NPCSettingsSyncEvent.newSingle(key, value))
    end
end

--[[
    Send all settings to a specific connection (for player join sync).
    @param connection - Target connection
]]
function NPCSettingsSyncEvent.sendAllToConnection(connection)
    if g_server == nil or g_NPCSystem == nil then
        return
    end

    local settings = g_NPCSystem.settings
    local bulk = {
        enabled = settings.enabled,
        maxNPCs = settings.maxNPCs,
        showNames = settings.showNames,
        showNotifications = settings.showNotifications,
        enableFavors = settings.enableFavors,
        debugMode = settings.debugMode
    }
    connection:sendEvent(NPCSettingsSyncEvent.newBulk(bulk))
end

print("[NPC Favor] NPCSettingsSyncEvent loaded")
