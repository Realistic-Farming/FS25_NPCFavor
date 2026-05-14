-- =========================================================
-- TODO / FUTURE VISION
-- =========================================================
-- SETTINGS VALUES & DEFAULTS:
-- [x] Core settings (enabled, maxNPCs, work hours, spawn distance)
-- [x] Display settings (names, notifications, relationship bars, paths)
-- [x] Gameplay settings (favors, gifts, relationships, decay)
-- [x] Difficulty multipliers (gain, loss, reward, penalty)
-- [x] AI behavior tuning (activity level, movement, breaks, social)
-- [x] Debug toggles (paths, spawn points, AI decisions, log to file)
-- [x] Sound settings (effects, voice lines, UI sounds, notifications)
-- [x] Performance settings (update frequency, render/update distance, batching)
-- [x] Multiplayer sync flags (NPCs, relationships, favors)
-- [x] Full XML save/load with per-field read/write
-- [x] Validation with clamping for all numeric ranges
-- [x] Reset to defaults with optional immediate save
-- [x] Helper methods (difficulty multiplier, work time check, NPC culling)
-- FUTURE ENHANCEMENTS:
-- [ ] Per-NPC setting overrides (custom work hours for specific NPCs)
-- [ ] Settings profiles (presets: "Casual", "Realistic", "Performance")
-- [ ] Settings change event system to notify listeners on value change
-- [ ] Import/export settings to share between savegames
-- [ ] Settings versioning with automatic migration on mod update
-- =========================================================

-- =========================================================
-- FS25 NPC Favor Mod - Settings Data (NPCSettings)
-- =========================================================

local SETTINGS_SCHEMA_VERSION = "1.2.4"

---@class NPCSettings
NPCSettings = {}
local NPCSettings_mt = Class(NPCSettings)

function NPCSettings.new()
    local self = setmetatable({}, NPCSettings_mt)
    self:resetToDefaults(false)
    return self
end

function NPCSettings:resetToDefaults()
    -- Core
    self.enabled = true
    self.maxNPCs = 10
    self.npcWorkStart = 8
    self.npcWorkEnd = 17
    self.favorFrequency = 3
    self.npcSpawnDistance = 150

    -- Display
    self.showNames = true
    self.showNotifications = true
    self.showFavorList = true
    self.showRelationshipBars = true
    self.showMapMarkers = true
    self.showNPCPaths = false
    self.nameDisplayDistance = 50
    self.notificationDuration = 4000

    -- Gameplay
    self.enableFavors = true
    self.enableGifts = true
    self.enableRelationshipSystem = true
    self.npcHelpPlayer = true
    self.npcSocialize = true
    self.npcDriveVehicles = true
    self.npcVehicleMode = "hybrid"      -- "hybrid" (static prop, real when working), "realistic" (always real), "visual" (props only)
    self.allowMultipleFavors = true
    self.maxActiveFavors = 5
    self.favorTimeLimit = true
    self.relationshipDecay = false
    self.decayRate = 1

    -- Difficulty
    self.favorDifficulty = "normal"
    self.relationshipGainMultiplier = 1.0
    self.relationshipLossMultiplier = 1.0
    self.favorRewardMultiplier = 1.0
    self.favorPenaltyMultiplier = 1.0

    -- AI
    self.npcActivityLevel = "normal"
    self.npcMovementSpeed = 1.0
    self.npcWorkDuration = 1.0
    self.npcBreakFrequency = 1.0
    self.npcSocialFrequency = 1.0

    -- Debug
    self.debugMode = false
    self.showPaths = false
    self.showSpawnPoints = false
    self.showAIDecisions = false
    self.showRelationshipChanges = false
    self.logToFile = false

    -- Sound
    self.soundEffects = true
    self.voiceLines = true
    self.uiSounds = true
    self.notificationSound = true

    -- Performance
    self.updateFrequency = "normal"
    self.npcRenderDistance = 200
    self.npcUpdateDistance = 300
    self.batchUpdates = true
    self.maxUpdatesPerFrame = 5

    -- Multiplayer
    self.syncNPCs = true
    self.syncRelationships = true
    self.syncFavors = true

    -- Settings persist via saveToXMLFile hook on next game save (UsedPlus pattern).
    -- No immediate disk write — avoids "orphan" files outside official save process.
end

function NPCSettings:getSavegameXmlPath()
    if not (g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.savegameDirectory) then
        return nil
    end
    return g_currentMission.missionInfo.savegameDirectory .. "/npc_favor_settings.xml"
end

function NPCSettings:load()
    local xmlPath = self:getSavegameXmlPath()
    if not xmlPath then
        print("[NPC Settings] No savegame path available, using defaults")
        return
    end

    -- Use XMLFile.loadIfExists (proven FS25 pattern, works with savegame paths).
    -- g_fileIO:fileExists is unreliable for savegame directories.
    local xml = XMLFile.loadIfExists("npc_settings", xmlPath, "NPCSettings")
    if not xml then
        print("[NPC Settings] No settings file found (new game), using defaults")
        return
    end

    print(string.format("[NPC Settings] Loading settings from %s", xmlPath))

    local savedSchemaVersion = xml:getString("NPCSettings#schemaVersion", "0.0.0")
    if savedSchemaVersion ~= SETTINGS_SCHEMA_VERSION then
        print(string.format("[NPC Settings] Schema version mismatch: file=%s current=%s", savedSchemaVersion, SETTINGS_SCHEMA_VERSION))
    end

    local function getBool(path, default) return xml:getBool("NPCSettings."..path, default) end
    local function getInt(path, default) return xml:getInt("NPCSettings."..path, default) end
    local function getFloat(path, default) return xml:getFloat("NPCSettings."..path, default) end
    local function getString(path, default) return xml:getString("NPCSettings."..path, default) end

    -- Core
    self.enabled = getBool("enabled", self.enabled)
    self.maxNPCs = getInt("maxNPCs", self.maxNPCs)
    self.npcWorkStart = getInt("npcWorkStart", self.npcWorkStart)
    self.npcWorkEnd = getInt("npcWorkEnd", self.npcWorkEnd)
    self.favorFrequency = getInt("favorFrequency", self.favorFrequency)
    self.npcSpawnDistance = getInt("npcSpawnDistance", self.npcSpawnDistance)

    -- Display
    self.showNames = getBool("showNames", self.showNames)
    self.showNotifications = getBool("showNotifications", self.showNotifications)
    self.showFavorList = getBool("showFavorList", self.showFavorList)
    self.showRelationshipBars = getBool("showRelationshipBars", self.showRelationshipBars)
    self.showMapMarkers = getBool("showMapMarkers", self.showMapMarkers)
    self.showNPCPaths = getBool("showNPCPaths", self.showNPCPaths)
    self.nameDisplayDistance = getInt("nameDisplayDistance", self.nameDisplayDistance)
    self.notificationDuration = getInt("notificationDuration", self.notificationDuration)

    -- Gameplay
    self.enableFavors = getBool("enableFavors", self.enableFavors)
    self.enableGifts = getBool("enableGifts", self.enableGifts)
    self.enableRelationshipSystem = getBool("enableRelationshipSystem", self.enableRelationshipSystem)
    self.npcHelpPlayer = getBool("npcHelpPlayer", self.npcHelpPlayer)
    self.npcSocialize = getBool("npcSocialize", self.npcSocialize)
    self.npcDriveVehicles = getBool("npcDriveVehicles", self.npcDriveVehicles)
    self.npcVehicleMode = getString("npcVehicleMode", self.npcVehicleMode)
    self.allowMultipleFavors = getBool("allowMultipleFavors", self.allowMultipleFavors)
    self.maxActiveFavors = getInt("maxActiveFavors", self.maxActiveFavors)
    self.favorTimeLimit = getBool("favorTimeLimit", self.favorTimeLimit)
    self.relationshipDecay = getBool("relationshipDecay", self.relationshipDecay)
    self.decayRate = getFloat("decayRate", self.decayRate)

    -- Difficulty
    self.favorDifficulty = getString("favorDifficulty", self.favorDifficulty)
    self.relationshipGainMultiplier = getFloat("relationshipGainMultiplier", self.relationshipGainMultiplier)
    self.relationshipLossMultiplier = getFloat("relationshipLossMultiplier", self.relationshipLossMultiplier)
    self.favorRewardMultiplier = getFloat("favorRewardMultiplier", self.favorRewardMultiplier)
    self.favorPenaltyMultiplier = getFloat("favorPenaltyMultiplier", self.favorPenaltyMultiplier)

    -- AI
    self.npcActivityLevel = getString("npcActivityLevel", self.npcActivityLevel)
    self.npcMovementSpeed = getFloat("npcMovementSpeed", self.npcMovementSpeed)
    self.npcWorkDuration = getFloat("npcWorkDuration", self.npcWorkDuration)
    self.npcBreakFrequency = getFloat("npcBreakFrequency", self.npcBreakFrequency)
    self.npcSocialFrequency = getFloat("npcSocialFrequency", self.npcSocialFrequency)

    -- Debug
    self.debugMode = getBool("debugMode", self.debugMode)
    self.showPaths = getBool("showPaths", self.showPaths)
    self.showSpawnPoints = getBool("showSpawnPoints", self.showSpawnPoints)
    self.showAIDecisions = getBool("showAIDecisions", self.showAIDecisions)
    self.showRelationshipChanges = getBool("showRelationshipChanges", self.showRelationshipChanges)
    self.logToFile = getBool("logToFile", self.logToFile)

    -- Sound
    self.soundEffects = getBool("soundEffects", self.soundEffects)
    self.voiceLines = getBool("voiceLines", self.voiceLines)
    self.uiSounds = getBool("uiSounds", self.uiSounds)
    self.notificationSound = getBool("notificationSound", self.notificationSound)

    -- Performance
    self.updateFrequency = getString("updateFrequency", self.updateFrequency)
    self.npcRenderDistance = getInt("npcRenderDistance", self.npcRenderDistance)
    self.npcUpdateDistance = getInt("npcUpdateDistance", self.npcUpdateDistance)
    self.batchUpdates = getBool("batchUpdates", self.batchUpdates)
    self.maxUpdatesPerFrame = getInt("maxUpdatesPerFrame", self.maxUpdatesPerFrame)

    -- Multiplayer
    self.syncNPCs = getBool("syncNPCs", self.syncNPCs)
    self.syncRelationships = getBool("syncRelationships", self.syncRelationships)
    self.syncFavors = getBool("syncFavors", self.syncFavors)

    xml:delete()
    self:validateSettings()

    print(string.format("[NPC Settings] Loaded settings (enabled=%s, showNames=%s, debugMode=%s)",
        tostring(self.enabled), tostring(self.showNames), tostring(self.debugMode)))
end

--- Save settings to XML file.
-- Called from FSCareerMissionInfo.saveToXMLFile hook.
-- Settings take effect immediately in memory; this persists them to disk.
-- @param missionInfo  Mission info containing savegameDirectory
function NPCSettings:saveToXMLFile(missionInfo)
    local savegameDirectory = missionInfo and missionInfo.savegameDirectory
    if not savegameDirectory then return end

    local xmlPath = savegameDirectory .. "/npc_favor_settings.xml"

    local xml = XMLFile.create("npc_settings", xmlPath, "NPCSettings")
    if not xml then return end

    xml:setString("NPCSettings#schemaVersion", SETTINGS_SCHEMA_VERSION)

    local function setBool(path, value) xml:setBool("NPCSettings."..path, value) end
    local function setInt(path, value) xml:setInt("NPCSettings."..path, value) end
    local function setFloat(path, value) xml:setFloat("NPCSettings."..path, value) end
    local function setString(path, value) xml:setString("NPCSettings."..path, value) end

    -- Core
    setBool("enabled", self.enabled)
    setInt("maxNPCs", self.maxNPCs)
    setInt("npcWorkStart", self.npcWorkStart)
    setInt("npcWorkEnd", self.npcWorkEnd)
    setInt("favorFrequency", self.favorFrequency)
    setInt("npcSpawnDistance", self.npcSpawnDistance)

    -- Display
    setBool("showNames", self.showNames)
    setBool("showNotifications", self.showNotifications)
    setBool("showFavorList", self.showFavorList)
    setBool("showRelationshipBars", self.showRelationshipBars)
    setBool("showMapMarkers", self.showMapMarkers)
    setBool("showNPCPaths", self.showNPCPaths)
    setInt("nameDisplayDistance", self.nameDisplayDistance)
    setInt("notificationDuration", self.notificationDuration)

    -- Gameplay
    setBool("enableFavors", self.enableFavors)
    setBool("enableGifts", self.enableGifts)
    setBool("enableRelationshipSystem", self.enableRelationshipSystem)
    setBool("npcHelpPlayer", self.npcHelpPlayer)
    setBool("npcSocialize", self.npcSocialize)
    setBool("npcDriveVehicles", self.npcDriveVehicles)
    setString("npcVehicleMode", self.npcVehicleMode)
    setBool("allowMultipleFavors", self.allowMultipleFavors)
    setInt("maxActiveFavors", self.maxActiveFavors)
    setBool("favorTimeLimit", self.favorTimeLimit)
    setBool("relationshipDecay", self.relationshipDecay)
    setFloat("decayRate", self.decayRate)

    -- Difficulty
    setString("favorDifficulty", self.favorDifficulty)
    setFloat("relationshipGainMultiplier", self.relationshipGainMultiplier)
    setFloat("relationshipLossMultiplier", self.relationshipLossMultiplier)
    setFloat("favorRewardMultiplier", self.favorRewardMultiplier)
    setFloat("favorPenaltyMultiplier", self.favorPenaltyMultiplier)

    -- AI
    setString("npcActivityLevel", self.npcActivityLevel)
    setFloat("npcMovementSpeed", self.npcMovementSpeed)
    setFloat("npcWorkDuration", self.npcWorkDuration)
    setFloat("npcBreakFrequency", self.npcBreakFrequency)
    setFloat("npcSocialFrequency", self.npcSocialFrequency)

    -- Debug
    setBool("debugMode", self.debugMode)
    setBool("showPaths", self.showPaths)
    setBool("showSpawnPoints", self.showSpawnPoints)
    setBool("showAIDecisions", self.showAIDecisions)
    setBool("showRelationshipChanges", self.showRelationshipChanges)
    setBool("logToFile", self.logToFile)

    -- Sound
    setBool("soundEffects", self.soundEffects)
    setBool("voiceLines", self.voiceLines)
    setBool("uiSounds", self.uiSounds)
    setBool("notificationSound", self.notificationSound)

    -- Performance
    setString("updateFrequency", self.updateFrequency)
    setInt("npcRenderDistance", self.npcRenderDistance)
    setInt("npcUpdateDistance", self.npcUpdateDistance)
    setBool("batchUpdates", self.batchUpdates)
    setInt("maxUpdatesPerFrame", self.maxUpdatesPerFrame)

    -- Multiplayer
    setBool("syncNPCs", self.syncNPCs)
    setBool("syncRelationships", self.syncRelationships)
    setBool("syncFavors", self.syncFavors)

    xml:save()
    xml:delete()
end

function NPCSettings:validateSettings()
    self.maxNPCs = math.max(1, math.min(16, self.maxNPCs))
    self.npcWorkStart = math.max(0, math.min(23, self.npcWorkStart))
    self.npcWorkEnd = math.max(0, math.min(23, self.npcWorkEnd))
    self.favorFrequency = math.max(1, math.min(30, self.favorFrequency))
    self.maxActiveFavors = math.max(1, math.min(20, self.maxActiveFavors))
    self.npcSpawnDistance = math.max(50, math.min(1000, self.npcSpawnDistance))
    self.nameDisplayDistance = math.max(10, math.min(500, self.nameDisplayDistance))
    self.npcRenderDistance = math.max(50, math.min(1000, self.npcRenderDistance))
    self.npcUpdateDistance = math.max(100, math.min(2000, self.npcUpdateDistance))
    self.notificationDuration = math.max(1000, math.min(10000, self.notificationDuration))
    self.decayRate = math.max(0, math.min(10, self.decayRate))

    self.relationshipGainMultiplier = math.max(0.1, math.min(5.0, self.relationshipGainMultiplier))
    self.relationshipLossMultiplier = math.max(0.1, math.min(5.0, self.relationshipLossMultiplier))
    self.favorRewardMultiplier = math.max(0.1, math.min(5.0, self.favorRewardMultiplier))
    self.favorPenaltyMultiplier = math.max(0.1, math.min(5.0, self.favorPenaltyMultiplier))

    self.npcMovementSpeed = math.max(0.1, math.min(5.0, self.npcMovementSpeed))
    self.npcWorkDuration = math.max(0.1, math.min(5.0, self.npcWorkDuration))
    self.npcBreakFrequency = math.max(0.1, math.min(5.0, self.npcBreakFrequency))
    self.npcSocialFrequency = math.max(0.1, math.min(5.0, self.npcSocialFrequency))
    self.maxUpdatesPerFrame = math.max(1, math.min(50, self.maxUpdatesPerFrame))

    local validDifficulties = {"easy","normal","hard"}
    if not Utils.containsValue(validDifficulties, self.favorDifficulty) then
        self.favorDifficulty = "normal"
    end

    local validActivityLevels = {"low","normal","high"}
    if not Utils.containsValue(validActivityLevels, self.npcActivityLevel) then
        self.npcActivityLevel = "normal"
    end

    local validUpdateFrequencies = {"low","normal","high"}
    if not Utils.containsValue(validUpdateFrequencies, self.updateFrequency) then
        self.updateFrequency = "normal"
    end

    local validVehicleModes = {"realistic","visual","hybrid"}
    if not Utils.containsValue(validVehicleModes, self.npcVehicleMode) then
        self.npcVehicleMode = "hybrid"
    end

    self.enabled = not not self.enabled
    self.showNames = not not self.showNames
    self.showNotifications = not not self.showNotifications
    self.debugMode = not not self.debugMode
    self.enableFavors = not not self.enableFavors
end

