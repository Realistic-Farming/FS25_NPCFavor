-- =========================================================
-- TODO / FUTURE VISION
-- =========================================================
-- IMPLEMENTED FEATURES (v0.1):
-- [x] Building-based NPC spawning (non-player placeables)
-- [x] Multiplayer sync via NPCStateSyncEvent (5-second intervals)
-- [x] Console commands (npcStatus, npcList, npcSpawn, npcReset)
-- [x] Field assignment via g_fieldManager (nearest field detection)
-- [x] Player position detection (4 fallback methods: g_localPlayer, mission.player, controlledVehicle, camera)
-- [x] Subsystem architecture (Entity, AI, Scheduler, Relationship, Favor, InteractionUI, Settings, GUI)
-- [x] NPC data structure (personality, age, home position, assigned field, vehicles, relationship)
-- [x] Basic AI state machine (idle, traveling, working)
-- [x] Proximity detection and interaction flags
-- [x] Relationship tracking (0-100 scale)
-- [x] Favor cooldown system
-- [x] Sequential name/personality assignment (prevents duplicates)
-- [x] Delayed initialization (waits for mission start + terrain)
-- [x] Settings integration (enabled, maxNPCs, debugMode, showNotifications, showNames, enableFavors)
--
-- PERSISTENCE & SAVE SYSTEM:
-- [x] NPC persistence across save/load (saveToXMLFile/loadFromXMLFile)
-- [x] Save NPC state to savegame XML (positions, relationships, active favors, personality modifiers)
-- [x] Load NPC state from savegame XML (restore NPCs at saved positions via uniqueId/name matching)
-- [x] Preserve favor progress across sessions (via NPCFavorSystem:restoreFavor)
-- [x] Preserve relationship levels across sessions
-- [ ] Auto-save NPC data every 30 seconds (currently only saves on manual save)
-- [ ] Migration system for savegame format changes
--
-- SPAWNING & POPULATION DYNAMICS:
-- [x] NPC spawning at specific building types (shops, gas stations, production points)
-- [x] Role-based spawning (shopkeeper at shop, mechanic at garage, farmer at farm)
-- [ ] Dynamic NPC population (new NPCs arrive over time, some leave/move away)
-- [ ] NPC lifecycle (birth/arrival, aging, retirement, death/departure)
-- [ ] Population density settings (rural vs urban areas)
-- [ ] Random events (new family moves to town, NPC relocates)
-- [ ] NPC migration between farms/towns
--
-- ECONOMY & OWNERSHIP:
-- [x] NPC farm ownership (farmland assignment, farm naming, field assignment)
-- [ ] NPC economy (NPCs buy/sell at shops, own property, earn/spend money)
-- [ ] NPC-owned vehicles (visible in world, can be borrowed/rented)
-- [ ] NPC-owned fields (compete with player for harvest/sales)
-- [ ] NPC bank accounts (track wealth, debt, credit)
-- [ ] NPC shopping behavior (buy equipment, upgrades, consumables)
-- [ ] NPC loans (borrow from player or bank)
-- [ ] NPC property ownership (houses, barns, land)
--
-- EMPLOYMENT & HIRING:
-- [ ] Player can hire NPCs as farmhands (permanent workers)
-- [ ] NPC wage system (hourly/daily pay, bonuses)
-- [ ] NPC skill levels (improve over time with experience)
-- [ ] NPC work schedules (shifts, breaks, overtime)
-- [ ] NPC task assignment (plow field, harvest, delivery)
-- [ ] NPC performance tracking (efficiency, quality, reliability)
-- [ ] NPC can quit if mistreated (low pay, overwork, bad relationship)
-- [ ] NPC can be fired (severance pay, reputation impact)
--
-- QUESTS & STORY:
-- [ ] NPC quest chains (multi-step favor sequences with story)
-- [ ] Quest prerequisites (relationship level, completed favors, items)
-- [ ] Quest rewards (money, items, relationship boost, unlocks)
-- [ ] Quest branching (player choices affect outcomes)
-- [ ] Quest failures (time limits, wrong choices, consequences)
-- [ ] Story arcs (seasonal events, character development, community goals)
-- [ ] Reputation system (town-wide opinion affects all NPCs)
--
-- CONFIGURATION & MODDING:
-- [ ] Settings UI integration (in-game settings page for NPC mod)
-- [ ] XML-based NPC definitions (load names, personalities, models from config)
-- [ ] Custom NPC templates (modders can add new NPC types)
-- [ ] Localization support (translate NPC names, dialog, quests)
-- [ ] NPC model customization (clothing, appearance, accessories)
-- [x] Building type definitions (categorize placeables for role assignment)
-- [ ] Economy config (price multipliers, wage rates, loan terms)
--
-- ADVANCED AI & BEHAVIOR:
-- [ ] NPC daily schedules (wake, work, lunch, socialize, sleep)
-- [ ] NPC social interactions (talk to each other, form friendships/rivalries)
-- [ ] NPC vehicle usage (drive tractors, trucks, cars)
-- [ ] NPC pathfinding improvements (avoid obstacles, use roads)
-- [ ] NPC animations (wave, work, talk, eat, sleep)
-- [ ] NPC needs (hunger, fatigue, happiness)
-- [ ] NPC hobbies (fishing, sports, gardening)
-- [ ] Weather response (seek shelter in rain, wear coat in winter)
--
-- VISUAL & UI ENHANCEMENTS:
-- [ ] NPC 3D models (actual characters, not placeholders)
-- [ ] Map icons for NPC locations (color-coded by relationship)
-- [ ] NPC info panel (click NPC to see stats, history, active quests)
-- [ ] Relationship progression UI (visual meter, milestones)
-- [ ] Favor board UI (see all available favors in town)
-- [ ] NPC speech bubbles (thoughts, greetings, status updates)
-- [ ] Photo mode (take pictures with NPCs, share on social wall)
--
-- MULTIPLAYER ENHANCEMENTS:
-- [ ] Per-player NPC relationships (each player has own relationship values)
-- [ ] Co-op favor completion (multiple players work together on favor)
-- [ ] Competitive favors (race to complete, best reward to winner)
-- [ ] NPC chat messages (NPCs comment in multiplayer chat)
-- [ ] Admin controls (host can spawn/remove/configure NPCs)
--
-- PERFORMANCE & OPTIMIZATION:
-- [ ] NPC LOD system (reduce updates for distant NPCs)
-- [ ] Spatial partitioning (only update NPCs in active cells)
-- [ ] Async pathfinding (don't block main thread)
-- [ ] Entity pooling (reuse NPC objects instead of destroy/create)
-- [ ] Network optimization (delta sync, compression)
-- [ ] Profiling tools (measure NPC system performance impact)
--
-- INTEGRATION WITH OTHER MODS:
-- [ ] Courseplay integration (NPCs can use Courseplay for fieldwork)
-- [ ] AutoDrive integration (NPCs use AutoDrive routes)
-- [ ] Seasons integration (NPC behavior changes with seasons)
-- [ ] Economy mods integration (sync prices, market data)
-- [ ] Placeable mods integration (recognize custom building types)
--
-- DEBUGGING & DEVELOPER TOOLS:
-- [ ] NPC debug overlay (show AI state, path, target in 3D)
-- [ ] NPC spawn editor (place NPCs in editor, save to config)
-- [ ] AI behavior debugger (visualize state machine transitions)
-- [ ] Performance profiler (track update times, memory usage)
-- [ ] Network debugger (monitor sync events, bandwidth)
-- [ ] Savegame inspector (view/edit NPC data in savegame)
--
-- =========================================================
-- FS25 NPC Favor Mod - Main NPC System (Coordinator)
-- =========================================================
-- Central hub that owns and coordinates all NPC subsystems:
--   - NPCEntity          (3D models, map icons, visibility)
--   - NPCAI              (state machine, pathfinding, decisions)
--   - NPCScheduler       (daily routines, timed events, seasons)
--   - NPCRelationshipManager (friendship levels, gifts, decay)
--   - NPCFavorSystem     (favor generation, tracking, completion)
--   - NPCInteractionUI   (world-space HUD, dialog helpers)
--   - NPCSettingsIntegration (user settings bridge)
--   - NPCFavorGUI        (dialog XML loader)
--
-- Lifecycle: new() → onMissionLoaded() → [delayed init] → initializeNPCs()
--            → update() each frame → delete() on shutdown
--
-- Multiplayer: Server runs full simulation + periodic sync via
--   NPCStateSyncEvent. Clients receive state and render only.
--
-- Time convention: FS25 passes dt in milliseconds. NPCSystem:update()
--   converts to seconds (dt = dt / 1000) before passing to subsystems.
-- =========================================================

NPCSystem = {}
NPCSystem_mt = Class(NPCSystem)

--- Create a new NPCSystem coordinator.
-- @param mission       g_currentMission reference
-- @param modDirectory  Mod directory path (with trailing slash)
-- @param modName       Mod name string
-- @return NPCSystem instance
function NPCSystem.new(mission, modDirectory, modName)
    print("[NPCSystem] Creating new NPCSystem instance")
    local self = setmetatable({}, NPCSystem_mt)

    self.mission = mission
    self.modDirectory = modDirectory
    self.modName = modName

    -- Initialize subsystems FIRST with safe defaults
    print("[NPCSystem] Initializing subsystems...")
    self.settings = NPCSettings.new()
    
    -- NPC name/personality lists with index counter for unique assignment
    self.npcNameIndex = 0
    self.npcPersonalityIndex = 0

    -- Gender-separated name pools for proper name-sex alignment
    self.maleNames = {
        "Old MacDonald", "Farmer Joe", "Young Peter", "Hans Bauer",
        "Wilhelm Braun", "Thomas Meier", "Gunther Schulz", "Erik Larsson",
        "Klaus Fischer", "Fritz Weber", "Otto Hartmann", "Karl Richter"
    }
    self.femaleNames = {
        "Mrs. Henderson", "Anna Schmidt", "Maria Stein", "Greta Hoffmann",
        "Elsa Becker", "Helga Wagner", "Ingrid Muller", "Liesel Baumann",
        "Clara Vogt", "Rosa Schreiber", "Martha Gruber", "Frieda Koch"
    }
    self.maleNameIndex = 0
    self.femaleNameIndex = 0

    self.config = {
        getNPCName = function(isFemale)
            if isFemale then
                self.femaleNameIndex = self.femaleNameIndex + 1
                return self.femaleNames[((self.femaleNameIndex - 1) % #self.femaleNames) + 1]
            else
                self.maleNameIndex = self.maleNameIndex + 1
                return self.maleNames[((self.maleNameIndex - 1) % #self.maleNames) + 1]
            end
        end,
        getRandomNPCName = function(isFemale)
            return self.config.getNPCName(isFemale)
        end,
        getRandomPersonality = function()
            local personalities = {"hardworking", "lazy", "social", "generous", "grumpy"}
            self.npcPersonalityIndex = self.npcPersonalityIndex + 1
            return personalities[((self.npcPersonalityIndex - 1) % #personalities) + 1]
        end,
        getRandomNPCModel = function()
            return "farmer"
        end,
        getRandomClothing = function()
            return {"farmer"}
        end,
        getRandomVehicleType = function()
            return "tractor"
        end,
        getRandomVehicleColor = function()
            return {r = 1.0, g = 0.2, b = 0.2, name = "red"}
        end
    }
    
    -- Core subsystems - instantiate the REAL classes
    self.entityManager = NPCEntity.new(self)
    self.aiSystem = NPCAI.new(self)
    self.scheduler = NPCScheduler.new(self)
    self.relationshipManager = NPCRelationshipManager.new(self)
    self.favorSystem = NPCFavorSystem.new(self)
    self.interactionUI = NPCInteractionUI.new(self)
    self.favorHUD = NPCFavorHUD.new(self)
    self.settingsIntegration = NPCSettingsIntegration.new(self)
    self.settingsPanel = NPCSettingsPanel.new(self.settings)

    self.fieldWork = NPCFieldWork.new()
    self.gui = NPCFavorGUI.new(self)
    self.contractorBridge = ContractorModBridge.new(self)

    self.dailyEvents = {}
    self.scheduledNPCInteractions = {}
    self.lastScheduleUpdate = 0
    self.scheduleUpdateInterval = 1000
    self.eventIdCounter = 1
    
    -- Multiplayer
    self.isServer = (g_server ~= nil)
    self.syncTimer = 0
    self.SYNC_INTERVAL = 5  -- seconds (dt is converted to seconds)
    self.syncDirty = false

    -- State
    self.isInitialized = false
    self.initializing = false
    self.delayedInitAttempts = 0
    self.initTimer = nil
    self.activeNPCs = {}
    self.npcCount = 0
    self.lastUpdateTime = 0
    self.updateCounter = 0
    self.playerPosition = {x = 0, y = 0, z = 0}
    self.playerPositionValid = false
    self.nearbyNPCs = {}
    self.lastSaveTime = 0
    self.saveInterval = 30000
    self.savedNPCData = nil

    -- Town reputation (0-100 scale, average of all NPC relationships weighted by interaction frequency)
    self.townReputation = 50

    -- Proximity respawning: relocate HOMELESS NPCs near the player
    -- NPCs with assigned homes stay at their homes — only unassigned NPCs get relocated
    self.relocateTimer = 0
    self.RELOCATE_INTERVAL = 30  -- seconds between relocation checks (less aggressive)
    self.RELOCATE_MAX_DISTANCE = 500  -- only truly lost NPCs get relocated
    self.RELOCATE_MIN_SPAWN = 60     -- minimum spawn distance from player
    self.RELOCATE_MAX_SPAWN = 200    -- maximum spawn distance from player

    print("[NPCSystem] NPCSystem instance created successfully")
    return self
end

function NPCSystem:onMissionLoaded()
    -- Prevent multiple init attempts
    if self.isInitialized then
        return
    end
    
    if self.initializing then
        return
    end
    
    if self.settingsIntegration and self.settingsIntegration.initialize then
        self.settingsIntegration:initialize()
    end
    if self.settingsPanel then
        self.settingsPanel:initialize()
    end

    -- Load saved settings from disk
    pcall(function() self.settings:load() end)

    -- Apply saved HUD position/scale
    if self.favorHUD then
        self.favorHUD:loadFromSettings(self.settings)
    end

    self.initializing = true
    
    if self.settings.debugMode then
        print("[NPC Favor] Starting mission-loaded initialization...")
    end
    
    -- Create a one-time init updater with proper return logic
    local initUpdater = {
        initDone = false,
        update = function(_, dt)
            -- If already done, return true to remove updater
            if self.initDone then
                return true
            end
            
            -- Check mission state
            if not g_currentMission or not g_currentMission.isMissionStarted then
                return false -- Keep trying
            end
            
            if not g_currentMission.terrainRootNode then
                return false -- Keep trying
            end
            
            -- All checks passed, initialize ONCE
            if not self.initDone then
                self.initDone = true
                
                if self.settings.debugMode then
                    print("[NPC Favor] All checks passed, initializing NPCs...")
                end
                
                -- Initialize NPCs (fresh spawn)
                self:initializeNPCs()

                -- Bridge ContractorMod workers into the favor system.
                -- Must run AFTER initializeNPCs() and BEFORE loadFromXMLFile()
                -- so that contractor uniqueIds exist when save data is matched.
                self.contractorBridge:initialize()

                -- Restore saved state (relationships, positions, favor history)
                local missionInfo = nil
                if g_currentMission and g_currentMission.missionInfo then
                    missionInfo = g_currentMission.missionInfo
                elseif g_currentMission and g_currentMission.savegameDirectory then
                    missionInfo = { savegameDirectory = g_currentMission.savegameDirectory }
                end
                if missionInfo then
                    self:loadFromXMLFile(missionInfo)
                end

                -- Show notification
                if self.settings.showNotifications then
                    if g_currentMission and g_currentMission.hud then
                        local ver = (g_NPCFavorMod and g_NPCFavorMod.version) or "?"
                        g_currentMission.hud:showBlinkingWarning(
                            "NPC Favor v" .. ver .. " loaded - Type 'npcHelp' for commands",
                            8000
                        )
                    end
                end
                
                -- Detect companion mods — must run after mission is fully started
                self:detectOptionalMods()

                self.isInitialized = true
                self.initializing = false

                -- Watch for the game ending an NPC's AI field-work job (field
                -- finished, blocked, vehicle deleted) so we release the NPC and
                -- free its job slot instead of leaking it. Subscribe once.
                if not self._aiJobMsgSubscribed and g_messageCenter and MessageType and MessageType.AI_JOB_STOPPED then
                    g_messageCenter:subscribe(MessageType.AI_JOB_STOPPED, self.onAIJobStopped, self)
                    self._aiJobMsgSubscribed = true
                end

                print("[NPC Favor] Initialized with " .. tostring(self.npcCount) .. " NPCs")
                
                return true -- Remove updater
            end
            
            return false
        end
    }
    
    -- Add the updater
    if self.mission and self.mission.addUpdateable then
        self.mission:addUpdateable(initUpdater)
    else
        print("[NPC Favor] ERROR: Cannot add updateable")
        self.initializing = false
    end
end

--- Classify all placeables in the world into building categories.
-- Each placeable is inspected for spec_ fields that indicate its type.
-- Results stored in self.classifiedBuildings keyed by category name.
-- Called once during initializeNPCs() before NPC creation.
function NPCSystem:classifyBuildings()
    self.classifiedBuildings = {
        residential  = {},
        farm_storage = {},
        animal       = {},
        production   = {},
        shop         = {},
        workshop     = {},
        greenhouse   = {},
        utility      = {},
        other        = {}
    }

    if not g_currentMission or not g_currentMission.placeableSystem then
        if self.settings.debugMode then
            print("[NPC Favor] classifyBuildings: no placeableSystem available")
        end
        return
    end

    local placeables = g_currentMission.placeableSystem.placeables
    if not placeables and g_currentMission.placeableSystem.getPlaceables then
        placeables = g_currentMission.placeableSystem:getPlaceables()
    end

    for _, placeable in pairs(placeables or {}) do
        -- Skip deleted/invalid placeables
        if placeable.markedForDeletion or placeable.isDeleted then
            -- skip
        else
            -- Skip fences and trivial objects
            local typeName = placeable.typeName or ""
            if typeName ~= "newFence" and typeName ~= "fence" then
                -- Determine category from spec fields
                local category = "other"

                if placeable.spec_farmhouse ~= nil then
                    category = "residential"
                elseif placeable.spec_silo ~= nil or placeable.spec_bunkerSilo ~= nil then
                    category = "farm_storage"
                elseif placeable.spec_husbandry ~= nil or placeable.spec_husbandryAnimals ~= nil then
                    category = "animal"
                elseif placeable.spec_productionPoint ~= nil or placeable.spec_factory ~= nil then
                    category = "production"
                elseif placeable.spec_sellingStation ~= nil or placeable.spec_buyingStation ~= nil then
                    category = "shop"
                elseif placeable.spec_workshop ~= nil or placeable.spec_washingStation ~= nil then
                    category = "workshop"
                elseif placeable.spec_greenhouse ~= nil or placeable.spec_beehive ~= nil then
                    category = "greenhouse"
                elseif placeable.spec_weatherStation ~= nil or placeable.spec_windTurbine ~= nil then
                    category = "utility"
                end

                -- Get world position via pcall
                local x, y, z = 0, 0, 0
                if placeable.rootNode then
                    local ok, wx, wy, wz = pcall(getWorldTranslation, placeable.rootNode)
                    if ok and wx then
                        x, y, z = wx, wy, wz
                    end
                end

                -- Get building name safely
                local buildingName = "Building"
                if placeable.getName then
                    local ok, n = pcall(placeable.getName, placeable)
                    if ok and n then
                        buildingName = n
                    end
                end

                -- Estimate building footprint radius for avoidance
                local radius = self:estimateBuildingRadius(placeable, category)

                local entry = {
                    placeable   = placeable,
                    x           = x,
                    y           = y,
                    z           = z,
                    name        = buildingName,
                    ownerFarmId = placeable.ownerFarmId or 0,
                    category    = category,
                    radius      = radius
                }

                table.insert(self.classifiedBuildings[category], entry)
            end
        end
    end

    -- Debug: log counts per category
    if self.settings.debugMode then
        local total = 0
        for cat, entries in pairs(self.classifiedBuildings) do
            local count = #entries
            total = total + count
            if count > 0 then
                print(string.format("[NPC Favor] classifyBuildings: %s = %d", cat, count))
            end
        end
        print(string.format("[NPC Favor] classifyBuildings: %d buildings classified total", total))
    end
end

--- Estimate the footprint radius of a placeable building.
-- Tries to measure from the i3d node hierarchy first; falls back to
-- category-based defaults.
-- @param placeable  FS25 placeable object
-- @param category   Building category string from classifyBuildings
-- @return number    Estimated radius in metres
function NPCSystem:estimateBuildingRadius(placeable, category)
    -- Category-based defaults (conservative — slightly smaller than real footprint
    -- so NPCs don't get pushed too far from small decorative placeables)
    local defaults = {
        residential  = 7,
        farm_storage = 9,
        animal       = 11,
        production   = 10,
        shop         = 7,
        workshop     = 8,
        greenhouse   = 5,
        utility      = 3,
        other        = 5
    }

    -- Try to measure from child node extents for a more accurate size
    local measured = nil
    if placeable.rootNode then
        local ok, result = pcall(function()
            local rootX, _, rootZ = getWorldTranslation(placeable.rootNode)
            local maxDist = 0
            local numChildren = getNumOfChildren(placeable.rootNode)
            for i = 0, math.min(numChildren - 1, 20) do  -- cap at 20 children
                local child = getChildAt(placeable.rootNode, i)
                if child and child ~= 0 then
                    local cx, _, cz = getWorldTranslation(child)
                    local dx = cx - rootX
                    local dz = cz - rootZ
                    local dist = math.sqrt(dx * dx + dz * dz)
                    if dist > maxDist then
                        maxDist = dist
                    end
                end
            end
            -- If children extend beyond 3m, use that as a better estimate
            if maxDist > 3 then
                return maxDist + 2  -- add 2m margin for walls
            end
            return nil
        end)
        if ok and result then
            measured = result
        end
    end

    return measured or defaults[category] or 5
end

--- Check if a world position is inside any classified building.
-- Skips the building passed as excludePlaceable (NPC's home).
-- @param x                 World X position
-- @param z                 World Z position
-- @param excludePlaceable  Placeable object to skip (NPC's home building), or nil
-- @return boolean          true if inside a building
-- @return table|nil        The building entry the position is inside, or nil
function NPCSystem:isPositionInsideBuilding(x, z, excludePlaceable)
    if not self.classifiedBuildings then return false, nil end

    for _, entries in pairs(self.classifiedBuildings) do
        for _, entry in ipairs(entries) do
            if entry.placeable ~= excludePlaceable then
                local dx = x - entry.x
                local dz = z - entry.z
                local dist = math.sqrt(dx * dx + dz * dz)
                if dist < entry.radius then
                    return true, entry
                end
            end
        end
    end
    return false, nil
end

--- Given a position that may be inside a building, push it outward to safety.
-- Returns the original position if it's already outside all buildings.
-- @param x                 World X position
-- @param z                 World Z position
-- @param excludePlaceable  Placeable to skip (NPC's home building), or nil
-- @return number, number   Safe X, Z coordinates
function NPCSystem:getSafePosition(x, z, excludePlaceable)
    local inside, building = self:isPositionInsideBuilding(x, z, excludePlaceable)
    if not inside then
        return x, z
    end

    -- Push position outward from building center to just beyond its radius
    local dx = x - building.x
    local dz = z - building.z
    local dist = math.sqrt(dx * dx + dz * dz)

    if dist < 0.5 then
        -- Dead center — pick a random direction
        local angle = math.random() * math.pi * 2
        dx = math.cos(angle)
        dz = math.sin(angle)
        dist = 1
    end

    local safeRadius = building.radius + 2  -- 2m outside the building edge
    local safeX = building.x + (dx / dist) * safeRadius
    local safeZ = building.z + (dz / dist) * safeRadius

    return safeX, safeZ
end

--- Get a position near a building that is guaranteed to be outside it.
-- Used when choosing walking destinations near buildings.
-- @param buildingX   Building center X
-- @param buildingZ   Building center Z
-- @param building    Building entry table (with .radius, .placeable)
-- @param excludePlaceable  Placeable to skip for overlap check (NPC's home)
-- @return number, number   Safe X, Z at the building's exterior
function NPCSystem:getExteriorPositionNear(buildingX, buildingZ, building, excludePlaceable)
    local angle = math.random() * math.pi * 2
    local offset = (building.radius or 5) + 2 + math.random() * 3  -- radius + 2-5m
    local x = buildingX + math.cos(angle) * offset
    local z = buildingZ + math.sin(angle) * offset

    -- Double-check we didn't land inside another building
    x, z = self:getSafePosition(x, z, excludePlaceable)
    return x, z
end


function NPCSystem:initializeNPCs()
    -- Classify all world buildings before spawning NPCs
    self:classifyBuildings()

    -- Initialize the event scheduler for dynamic emergent events
    self:initEventScheduler()

    -- Clear existing NPCs if any
    self:clearAllNPCs()
    
    -- Find suitable spawn locations
    local spawnLocations = self:findNPCSpawnLocations()
    
    -- Create NPCs
    for i = 1, math.min(#spawnLocations, self.settings.maxNPCs) do
        local location = spawnLocations[i]
        local npc = self:createNPCAtLocation(location)
        
        if npc then
            -- Initialize NPC with proper data
            self:initializeNPCData(npc, location, i)
            
            table.insert(self.activeNPCs, npc)
            self.npcCount = self.npcCount + 1
            
            if i <= 3 then
                print(string.format("NPC %d created: %s", i, npc.name))
            end
        end
    end

    if self.npcCount > 3 then
        print(string.format("... and %d more NPCs created", self.npcCount - 3))
    end
    print(string.format("NPC Favor: Generated %d total NPCs", self.npcCount))

    -- Assign farmlands and fields to farmer NPCs (after all NPCs are created)
    self:assignFarmlands()

    -- Phase B: Spawn real NPC vehicles. Player entry is blocked by lockNPCVehicle
    -- (removes the vehicle from the interactive list, neutralizes getDistanceToNode
    -- and interact, and re-locks after async finalization). Gated by the
    -- npcDriveVehicles setting and npcVehicleMode inside initializeNPCVehicles.
    self:initializeNPCVehicles()
end

--- Set up an NPC's home position, field assignment, vehicles, AI state, and entity.
-- @param npc       NPC data table (from createNPCAtLocation)
-- @param location  Spawn location table {x, y, z, building, buildingName}
-- @param npcId     Sequential NPC index
function NPCSystem:initializeNPCData(npc, location, npcId)
    -- Assign properties with validation
    if location then
        npc.homePosition = {
            x = location.x or 0,
            y = location.y or 0,
            z = location.z or 0
        }
    else
        npc.homePosition = {x = 0, y = 0, z = 0}
    end

    -- Store home building reference from spawn location
    npc.homeBuilding = (location and location.building) or nil
    npc.homeBuildingName = (location and location.buildingName) or "Unknown"
    npc.ownerFarmId = (location and location.ownerFarmId) or (FarmManager.SPECTATOR_FARM_ID or 15)

    -- Assign workplace and role based on nearest classified building
    npc.role = "farmer"  -- default role
    npc.workplaceBuilding = nil

    if self.classifiedBuildings and location then
        local locX = location.x or 0
        local locZ = location.z or 0
        local bestDist = math.huge
        local bestEntry = nil
        local bestCategory = nil

        -- Search all non-residential categories to find the nearest workplace
        local workCategories = {"shop", "production", "farm_storage", "animal", "workshop", "greenhouse", "utility"}
        for _, cat in ipairs(workCategories) do
            for _, entry in ipairs(self.classifiedBuildings[cat] or {}) do
                local dx = entry.x - locX
                local dz = entry.z - locZ
                local dist = math.sqrt(dx * dx + dz * dz)
                if dist < bestDist then
                    bestDist = dist
                    bestEntry = entry
                    bestCategory = cat
                end
            end
        end

        if bestEntry then
            npc.workplaceBuilding = bestEntry

            -- Assign role based on workplace category
            if bestCategory == "shop" then
                npc.role = "shopkeeper"
            elseif bestCategory == "production" then
                npc.role = "worker"
            elseif bestCategory == "farm_storage" or bestCategory == "animal" then
                npc.role = "farmhand"
            elseif bestCategory == "workshop" then
                npc.role = "worker"
            elseif bestCategory == "greenhouse" then
                npc.role = "farmhand"
            elseif bestCategory == "utility" then
                npc.role = "worker"
            else
                npc.role = "farmer"
            end

            if self.settings.debugMode then
                print(string.format("[NPC Favor] NPC %s assigned role '%s' (nearest %s: %s at %.0fm)",
                    npc.name or "?", npc.role, bestCategory, bestEntry.name or "?", bestDist))
            end
        end
    end

    -- Guard against nil location for field lookup
    local locX = (location and location.x) or 0
    local locZ = (location and location.z) or 0
    npc.assignedField = self:findNearestField(locX, locZ, npcId)
    npc.assignedVehicles = self:generateNPCVehicles(npcId)
    
    -- Initialize AI state
    npc.aiState = "idle"
    npc.currentAction = "idle"
    npc.path = nil
    
    -- Initialize relationship: random 5-35 (Hostile to Neutral range).
    -- New neighbors aren't enemies, but you haven't earned their trust yet either.
    npc.relationship = math.random(5, 35)
    
    -- Set unique NPC ID
    npc.uniqueId = string.format("npc_%d_%s_%d", 
        npcId, 
        string.lower((npc.name or "Unknown"):gsub("%s+", "_")),
        math.random(1000, 9999)
    )
    
    -- Add to entity manager
    self.entityManager:createNPCEntity(npc)
end

--- Find spawn locations by enumerating non-player-owned placeables.
-- Filters out fences, deleted objects, and player-owned buildings.
-- NPCs are distributed round-robin across buildings with 3-8m offsets.
-- Falls back to terrain center if no buildings are found.
-- @return table  Array of location tables {x, y, z, building, buildingName, ...}
function NPCSystem:findNPCSpawnLocations()
    local locations = {}
    local playerFarmId = 1 -- Default player farm

    if g_currentMission and g_currentMission.getFarmId then
        playerFarmId = g_currentMission:getFarmId()
    end

    -- Prefer residential buildings from classified data, then fall back to others
    local buildings = {}

    if self.classifiedBuildings then
        -- First: add all non-player residential buildings
        for _, entry in ipairs(self.classifiedBuildings.residential or {}) do
            if entry.ownerFarmId ~= playerFarmId then
                table.insert(buildings, {
                    x = entry.x, y = entry.y, z = entry.z,
                    placeable = entry.placeable,
                    ownerFarmId = entry.ownerFarmId,
                    name = entry.name,
                    category = entry.category,
                    isResidential = true
                })
            end
        end

        if self.settings.debugMode then
            print(string.format("[NPC Favor] Found %d non-player residential buildings", #buildings))
        end

        -- If not enough residential buildings, also pull from other categories
        if #buildings < self.settings.maxNPCs then
            -- Add 'other' category buildings as secondary homes
            for _, entry in ipairs(self.classifiedBuildings.other or {}) do
                if entry.ownerFarmId ~= playerFarmId then
                    table.insert(buildings, {
                        x = entry.x, y = entry.y, z = entry.z,
                        placeable = entry.placeable,
                        ownerFarmId = entry.ownerFarmId,
                        name = entry.name,
                        category = entry.category,
                        isResidential = false
                    })
                end
            end
        end

        -- Still not enough? Pull from all remaining non-player categories
        if #buildings < self.settings.maxNPCs then
            local fallbackCategories = {"shop", "production", "workshop", "farm_storage", "animal", "greenhouse", "utility"}
            for _, cat in ipairs(fallbackCategories) do
                for _, entry in ipairs(self.classifiedBuildings[cat] or {}) do
                    if entry.ownerFarmId ~= playerFarmId then
                        table.insert(buildings, {
                            x = entry.x, y = entry.y, z = entry.z,
                            placeable = entry.placeable,
                            ownerFarmId = entry.ownerFarmId,
                            name = entry.name,
                            category = entry.category,
                            isResidential = false
                        })
                    end
                end
            end
        end
    else
        -- Fallback: classifyBuildings not yet run, iterate placeables directly
        if g_currentMission and g_currentMission.placeableSystem then
            local placeables = g_currentMission.placeableSystem.placeables
            if not placeables and g_currentMission.placeableSystem.getPlaceables then
                placeables = g_currentMission.placeableSystem:getPlaceables()
            end

            for _, placeable in pairs(placeables or {}) do
                if not placeable.markedForDeletion and not placeable.isDeleted then
                    local typeName = placeable.typeName or ""
                    if typeName ~= "newFence" and typeName ~= "fence" then
                        local isPlayerOwned = (placeable.ownerFarmId == playerFarmId)
                        if not isPlayerOwned and placeable.rootNode then
                            local ok, x, y, z = pcall(getWorldTranslation, placeable.rootNode)
                            if ok and x then
                                table.insert(buildings, {
                                    x = x, y = y, z = z,
                                    placeable = placeable,
                                    ownerFarmId = placeable.ownerFarmId or 0,
                                    name = (placeable.getName and placeable:getName()) or "Building",
                                    category = "other",
                                    isResidential = false
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    if self.settings.debugMode then
        print(string.format("[NPC Favor] Found %d non-player buildings for NPC spawning", #buildings))
    end

    -- Fallback: if no buildings found, use terrain center
    if #buildings == 0 then
        local cx = (g_currentMission and g_currentMission.terrainSize or 2048) / 2
        table.insert(buildings, { x = cx, y = 0, z = cx, placeable = nil, name = "MapCenter" })
    end

    -- Assign NPCs to buildings (round-robin if more NPCs than buildings)
    local neededLocations = self.settings.maxNPCs
    for i = 1, neededLocations do
        local building = buildings[((i - 1) % #buildings) + 1]
        -- Offset each NPC slightly from the building center (3-8m)
        local angle = (i / neededLocations) * math.pi * 2
        local offset = 3 + math.random() * 5
        local spawnX = building.x + math.cos(angle) * offset
        local spawnZ = building.z + math.sin(angle) * offset

        table.insert(locations, {
            x = spawnX,
            y = 0,
            z = spawnZ,
            building = building,
            buildingName = building.name,
            ownerFarmId = building.ownerFarmId or 0,
            isPredefined = true,
            isResidential = building.isResidential or false,
            category = building.category or "other"
        })
    end

    -- Validate terrain heights
    if g_currentMission and g_currentMission.terrainRootNode then
        for _, loc in ipairs(locations) do
            local success, terrainHeight = pcall(getTerrainHeightAtWorldPos,
                g_currentMission.terrainRootNode, loc.x, 0, loc.z)
            if success and terrainHeight then
                loc.y = terrainHeight + 0.05
            end
        end
    end

    return locations
end

--- Create an NPC data table at a given location with randomized properties.
-- Personality modifiers affect movementSpeed and AI behavior weights.
-- @param location  Location table {x, y, z}
-- @return table    NPC data table, or nil on error
function NPCSystem:createNPCAtLocation(location)
    if not location then
        print("[NPC Favor] ERROR: No location provided for NPC creation")
        return nil
    end
    
    -- Determine gender: alternate male/female based on NPC count for balanced distribution
    local npcCount = #self.activeNPCs
    local isFemale = (npcCount % 2 == 0)
    -- Appearance seed: use NPC count + location hash for variety, avoid math.randomseed corruption
    local locHash = math.floor(math.abs((location and location.x or 0) * 7 + (location and location.z or 0) * 13)) % 1000
    local appearanceSeed = (npcCount * 137 + locHash) % 1000 + 1

    local npc = {
        id = #self.activeNPCs + 1,
        name = self.config.getNPCName(isFemale),
        isFemale = isFemale,
        age = math.random(25, 65),
        personality = self.config.getRandomPersonality(),
        
        -- Position with validation
        position = {
            x = location.x or 0,
            y = location.y or 0,
            z = location.z or 0
        },
        rotation = {x = 0, y = math.random() * math.pi * 2, z = 0},
        
        -- State
        isActive = true,
        currentAction = "idle",
        currentTask = nil,
        currentVehicle = nil,
        targetPosition = nil,
        canInteract = false,
        interactionDistance = 999,
        
        -- Properties
        homePosition = location,
        assignedField = nil,
        assignedVehicles = {},
        
        -- Stats (random 5-35: mix of Hostile/Unfriendly/Neutral)
        relationship = math.random(5, 35),
        favorCooldown = 0,
        lastInteractionTime = 0,
        totalFavorsCompleted = 0,
        totalFavorsFailed = 0,
        
        -- Visual
        model = self.config.getRandomNPCModel(),
        clothing = self.config.getRandomClothing(),
        appearanceSeed = appearanceSeed,
        
        -- Visual variation
        heightScale = 0.95 + math.random() * 0.1,  -- 0.95-1.05 height variation

        -- AI
        aiState = "idle",
        path = nil,
        movementSpeed = 1.0, -- base speed, overridden by personality below
        aiPersonalityModifiers = {
            workEthic = 1.0,
            sociability = 1.0,
            generosity = 1.0,
            punctuality = 1.0
        },
        
        -- Performance
        lastUpdateTime = 0,
        updatePriority = 1,

        -- Memory: recent encounters (max 5)
        encounters = {},

        -- Greeting state
        lastGreetingTime = 0,
        greetingText = nil,
        greetingTimer = 0,

        -- Vehicle dodge state
        dodgeTimer = 0,

        -- Needs system (0 = satisfied, 100 = desperate)
        needs = {
            energy = 20,            -- rises while awake, drops while sleeping
            social = 30,            -- rises while alone, drops while socializing
            hunger = 10,            -- rises over time, drops during meal slots
            workSatisfaction = 50,  -- rises from working, drops from idle
        },
        mood = "neutral",           -- derived from needs: happy/neutral/stressed/tired

        -- 4i: Special day events
        birthdayMonth = math.random(1, 12),
        birthdayDay = math.random(1, 28),

        -- Persistence
        uniqueId = nil,
        saveData = {},
        entityId = nil
    }
    
    -- Apply personality-based modifiers
    if npc.personality == "hardworking" then
        npc.aiPersonalityModifiers.workEthic = 1.5
        npc.aiPersonalityModifiers.punctuality = 1.3
    elseif npc.personality == "lazy" then
        npc.aiPersonalityModifiers.workEthic = 0.5
        npc.aiPersonalityModifiers.punctuality = 0.7
    elseif npc.personality == "social" then
        npc.aiPersonalityModifiers.sociability = 1.5
        npc.aiPersonalityModifiers.workEthic = 0.8
    elseif npc.personality == "generous" then
        npc.aiPersonalityModifiers.generosity = 1.5
    elseif npc.personality == "grumpy" then
        npc.aiPersonalityModifiers.sociability = 0.3
        npc.aiPersonalityModifiers.generosity = 0.5
    end
    
    -- Personality-specific movement speed ranges (observable differentiation)
    local speedRanges = {
        hardworking = {1.4, 1.6},   -- brisk, purposeful
        lazy        = {0.7, 0.85},  -- dawdling, unhurried
        social      = {1.0, 1.2},   -- normal, conversational pace
        grumpy      = {1.1, 1.3},   -- impatient, quick
        generous    = {0.9, 1.1},   -- relaxed, approachable
    }
    local range = speedRanges[npc.personality] or {0.9, 1.2}
    npc.movementSpeed = range[1] + math.random() * (range[2] - range[1])
    
    return npc
end

--- Find the nearest field to a world position using g_fieldManager.
-- Tries 3 field-center patterns: fieldArea.fieldCenterX, posX/posZ, rootNode.
-- @param x      World X position
-- @param z      World Z position
-- @param npcId  NPC ID (for debug logging)
-- @return table  {id, center={x,y,z}, size} or nil if no fields found
function NPCSystem:findNearestField(x, z, npcId)
    if not g_fieldManager or not g_fieldManager.fields then
        return nil
    end

    local nearest = nil
    local nearestDist = math.huge

    for _, field in pairs(g_fieldManager.fields) do
        -- Try multiple field center location patterns used by FS25
        local cx, cz = nil, nil

        if field.fieldArea and field.fieldArea.fieldCenterX then
            cx = field.fieldArea.fieldCenterX
            cz = field.fieldArea.fieldCenterZ
        elseif field.posX and field.posZ then
            cx = field.posX
            cz = field.posZ
        elseif field.rootNode then
            local ok, fx, _, fz = pcall(getWorldTranslation, field.rootNode)
            if ok and fx then
                cx = fx
                cz = fz
            end
        end

        if cx and cz then
            local dx = cx - x
            local dz = cz - z
            local dist = math.sqrt(dx * dx + dz * dz)
            if dist < nearestDist then
                nearestDist = dist
                nearest = {
                    id = field.fieldId or 0,
                    center = { x = cx, y = 0, z = cz },
                    size = (field.fieldArea and field.fieldArea.fieldArea) or 1
                }
            end
        end
    end

    -- Enhance with crop/growth state info when available
    if nearest then
        nearest.cropInfo = nil
        for _, field in pairs(g_fieldManager.fields) do
            local fid = field.fieldId or 0
            if fid == nearest.id then
                local cropInfo = {}
                -- Try to read fruit type
                pcall(function()
                    if field.fruitType then
                        cropInfo.fruitType = field.fruitType
                    elseif field.currentFruit then
                        cropInfo.fruitType = field.currentFruit
                    end
                end)
                -- Try to read growth state
                pcall(function()
                    if field.growthState then
                        cropInfo.growthState = field.growthState
                    elseif field.fieldState then
                        cropInfo.growthState = field.fieldState
                    end
                end)
                if cropInfo.fruitType or cropInfo.growthState then
                    nearest.cropInfo = cropInfo
                end
                break
            end
        end
    end

    if nearest and self.settings.debugMode then
        local cropStr = ""
        if nearest.cropInfo then
            cropStr = string.format(" crop=%s growth=%s",
                tostring(nearest.cropInfo.fruitType or "?"),
                tostring(nearest.cropInfo.growthState or "?"))
        end
        print(string.format("[NPC Favor] Field #%d found for NPC %d at dist %.0fm%s",
            nearest.id, npcId or 0, nearestDist, cropStr))
    end

    return nearest
end

function NPCSystem:generateNPCVehicles(npcId)
    local vehicles = {}
    
    -- Each NPC gets 1 vehicle for now
    table.insert(vehicles, {
        type = "tractor",
        color = {r = 0.2, g = 0.6, b = 1.0},
        isAvailable = true,
        currentTask = nil,
        position = nil,
        fuelLevel = 100,
        condition = 100
    })
    
    return vehicles
end

--- Generate a farm name from an NPC's name.
-- Extracts last name and appends " Farm".
-- Special case: "Old MacDonald" -> "MacDonald Farm"
-- @param npc  NPC data table with .name field
-- @return string  Farm name (e.g., "Henderson Farm")
function NPCSystem:generateFarmName(npc)
    if not npc or not npc.name then
        return "Unknown Farm"
    end

    local name = npc.name

    -- Split name into words
    local words = {}
    for word in name:gmatch("%S+") do
        table.insert(words, word)
    end

    if #words == 0 then
        return "Unknown Farm"
    end

    -- Extract last name (last word), skipping common prefixes/titles
    local lastName = words[#words]

    -- Strip common title prefixes like "Mrs.", "Mr.", "Dr." if they are the last word
    -- (shouldn't happen, but be safe)
    local titlePrefixes = { "Mr.", "Mrs.", "Ms.", "Dr.", "Prof.", "Old", "Young", "Farmer" }
    if #words == 1 then
        -- Single word name: check if it's a title, if so use it anyway
        for _, prefix in ipairs(titlePrefixes) do
            if lastName == prefix then
                return name .. " Farm"
            end
        end
    end

    -- Store on NPC and return
    local farmName = lastName .. " Farm"
    npc.farmName = farmName
    return farmName
end

--- Assign farmlands to NPC farmers using g_farmlandManager.
-- Uses proximity-based matching: farmers get farmlands nearest their homes.
-- Also finds fields belonging to each farmland and stores them on the NPC.
-- Called after NPC creation in initializeNPCs().
function NPCSystem:assignFarmlands()
    -- Guard: need both farmland manager and field manager
    local hasFarmlandManager = false
    local farmlands = nil

    pcall(function()
        if g_farmlandManager then
            if g_farmlandManager.getFarmlands then
                farmlands = g_farmlandManager:getFarmlands()
            elseif g_farmlandManager.farmlands then
                farmlands = g_farmlandManager.farmlands
            end
            if farmlands then
                hasFarmlandManager = true
            end
        end
    end)

    if not hasFarmlandManager or not farmlands then
        if self.settings.debugMode then
            print("[NPC Favor] assignFarmlands: g_farmlandManager not available, skipping")
        end
        return
    end

    -- Collect farmer NPCs (role == "farmer" or "farmhand")
    local farmerNPCs = {}
    for _, npc in ipairs(self.activeNPCs) do
        if npc.isActive and (npc.role == "farmer" or npc.role == "farmhand") then
            table.insert(farmerNPCs, npc)
        end
    end

    if #farmerNPCs == 0 then
        if self.settings.debugMode then
            print("[NPC Favor] assignFarmlands: no farmer NPCs found, skipping")
        end
        return
    end

    -- Collect assignable farmlands (unowned or NPC-owned)
    local assignableFarmlands = {}
    for _, farmland in pairs(farmlands) do
        local farmlandId = nil
        local ownerFarmId = nil
        local isNPCOwned = false
        local farmlandName = "Farmland"

        pcall(function()
            farmlandId = farmland.id or farmland.farmlandId
            ownerFarmId = farmland.ownerFarmId or 0
            isNPCOwned = farmland.isNPCOwned or false
            if farmland.getName then
                farmlandName = farmland:getName()
            elseif farmland.name then
                farmlandName = farmland.name
            end
        end)

        if farmlandId then
            -- Assign if unowned (farmId 0, nil, or 15=spectator) or marked as NPC-owned
            -- FarmId 15 is the spectator farm — used for all non-ownable map features
            local spectatorId = FarmManager.SPECTATOR_FARM_ID or 15
            if ownerFarmId == 0 or ownerFarmId == nil or ownerFarmId == spectatorId or isNPCOwned then
                table.insert(assignableFarmlands, {
                    farmlandId = farmlandId,
                    name = farmlandName or ("Farmland #" .. tostring(farmlandId)),
                    farmland = farmland
                })
            end
        end
    end

    if self.settings.debugMode then
        print(string.format("[NPC Favor] assignFarmlands: %d assignable farmlands, %d farmer NPCs",
            #assignableFarmlands, #farmerNPCs))
    end

    if #assignableFarmlands == 0 then
        -- Generate farm names even without farmland assignments
        for _, npc in ipairs(farmerNPCs) do
            self:generateFarmName(npc)
        end
        return
    end

    -- Compute farmland centroids from their fields for distance matching
    local farmlandCentroids = {}
    for _, farmlandEntry in ipairs(assignableFarmlands) do
        local cx, cz, fieldCount = 0, 0, 0
        pcall(function()
            if g_fieldManager and g_fieldManager.fields then
                for _, field in pairs(g_fieldManager.fields) do
                    local fieldFarmlandId = nil
                    if field.farmland and field.farmland.id then
                        fieldFarmlandId = field.farmland.id
                    elseif field.farmlandId then
                        fieldFarmlandId = field.farmlandId
                    end
                    if fieldFarmlandId and fieldFarmlandId == farmlandEntry.farmlandId then
                        local fx, fz = nil, nil
                        if field.fieldArea and field.fieldArea.fieldCenterX then
                            fx = field.fieldArea.fieldCenterX
                            fz = field.fieldArea.fieldCenterZ
                        elseif field.posX and field.posZ then
                            fx = field.posX
                            fz = field.posZ
                        elseif field.rootNode then
                            local ok2, rx, _, rz = pcall(getWorldTranslation, field.rootNode)
                            if ok2 and rx then fx = rx; fz = rz end
                        end
                        if fx and fz then
                            cx = cx + fx
                            cz = cz + fz
                            fieldCount = fieldCount + 1
                        end
                    end
                end
            end
        end)
        if fieldCount > 0 then
            farmlandCentroids[farmlandEntry.farmlandId] = { x = cx / fieldCount, z = cz / fieldCount }
        else
            -- Try farmland's own position as fallback
            local fl = farmlandEntry.farmland
            if fl and fl.posX and fl.posZ then
                farmlandCentroids[farmlandEntry.farmlandId] = { x = fl.posX, z = fl.posZ }
            end
        end
    end

    -- Proximity-based greedy nearest-first assignment:
    -- For each farmland, find the closest unassigned farmer NPC
    local assignedNPCIds = {}

    for _, farmlandEntry in ipairs(assignableFarmlands) do
        local centroid = farmlandCentroids[farmlandEntry.farmlandId]
        local bestNPC = nil
        local bestDist = math.huge

        if centroid then
            for _, npc in ipairs(farmerNPCs) do
                if not assignedNPCIds[npc.id] and npc.homePosition then
                    local dx = npc.homePosition.x - centroid.x
                    local dz = npc.homePosition.z - centroid.z
                    local dist = math.sqrt(dx * dx + dz * dz)
                    if dist < bestDist then
                        bestDist = dist
                        bestNPC = npc
                    end
                end
            end
        end

        -- If all NPCs already assigned, wrap around (allow multiple farmlands per NPC)
        if not bestNPC then
            if centroid then
                bestDist = math.huge
                for _, npc in ipairs(farmerNPCs) do
                    if npc.homePosition then
                        local dx = npc.homePosition.x - centroid.x
                        local dz = npc.homePosition.z - centroid.z
                        local dist = math.sqrt(dx * dx + dz * dz)
                        if dist < bestDist then
                            bestDist = dist
                            bestNPC = npc
                        end
                    end
                end
            else
                -- No centroid, fall back to first farmer
                bestNPC = farmerNPCs[1]
                bestDist = 0
            end
        end

        if bestNPC then
            assignedNPCIds[bestNPC.id] = true

            bestNPC.assignedFarmland = {
                farmlandId = farmlandEntry.farmlandId,
                name = farmlandEntry.name
            }
            bestNPC.homeToFieldDistance = bestDist

            -- Find fields belonging to this farmland
            bestNPC.assignedFields = bestNPC.assignedFields or {}
            pcall(function()
                if g_fieldManager and g_fieldManager.fields then
                    for _, field in pairs(g_fieldManager.fields) do
                        local fieldFarmlandId = nil
                        if field.farmland and field.farmland.id then
                            fieldFarmlandId = field.farmland.id
                        elseif field.farmlandId then
                            fieldFarmlandId = field.farmlandId
                        end

                        if fieldFarmlandId and fieldFarmlandId == farmlandEntry.farmlandId then
                            local fieldId = field.fieldId or 0
                            local fcx, fcz = nil, nil
                            if field.fieldArea and field.fieldArea.fieldCenterX then
                                fcx = field.fieldArea.fieldCenterX
                                fcz = field.fieldArea.fieldCenterZ
                            elseif field.posX and field.posZ then
                                fcx = field.posX
                                fcz = field.posZ
                            elseif field.rootNode then
                                local ok3, fx3, _, fz3 = pcall(getWorldTranslation, field.rootNode)
                                if ok3 and fx3 then fcx = fx3; fcz = fz3 end
                            end

                            table.insert(bestNPC.assignedFields, {
                                fieldId = fieldId,
                                center = { x = fcx or 0, y = 0, z = fcz or 0 },
                                field = field
                            })
                        end
                    end
                end
            end)

            -- Generate farm name for this NPC
            self:generateFarmName(bestNPC)

            -- Fallback: relocate home if field is >300m away
            if bestDist > 300 and centroid then
                self:tryRelocateNPCHome(bestNPC, centroid.x, centroid.z)
            end

            if self.settings.debugMode then
                print(string.format("[NPC Favor] Farmland '%s' (#%d) assigned to %s (%s) with %d fields (%.0fm from home)",
                    farmlandEntry.name, farmlandEntry.farmlandId,
                    bestNPC.name or "?", bestNPC.farmName or "?",
                    #bestNPC.assignedFields, bestDist))
            end
        end
    end

    -- Generate farm names for farmer NPCs that didn't get a farmland
    for _, npc in ipairs(farmerNPCs) do
        if not npc.farmName then
            self:generateFarmName(npc)
        end
    end
end

--- Try to relocate an NPC's home to a residential building closer to their field.
-- Only relocates if a residential building exists within 150m of the field centroid.
-- @param npc       NPC data table
-- @param fieldX    Field centroid X
-- @param fieldZ    Field centroid Z
function NPCSystem:tryRelocateNPCHome(npc, fieldX, fieldZ)
    if not self.classifiedBuildings or not self.classifiedBuildings.residential then
        return
    end

    local bestBuilding = nil
    local bestDist = 150  -- max search radius

    for _, entry in ipairs(self.classifiedBuildings.residential) do
        local dx = entry.x - fieldX
        local dz = entry.z - fieldZ
        local dist = math.sqrt(dx * dx + dz * dz)
        if dist < bestDist then
            bestDist = dist
            bestBuilding = entry
        end
    end

    if bestBuilding then
        local oldDist = npc.homeToFieldDistance or 0
        npc.homePosition = { x = bestBuilding.x, y = bestBuilding.y or 0, z = bestBuilding.z }
        npc.homeBuilding = bestBuilding.placeable or bestBuilding
        npc.homeBuildingName = bestBuilding.name or "Relocated Home"
        npc.homeToFieldDistance = bestDist

        if self.settings.debugMode then
            print(string.format("[NPC Favor] Relocated %s's home to %s (%.0fm from field, was %.0fm)",
                npc.name or "?", bestBuilding.name or "?", bestDist, oldDist))
        end
    else
        if self.settings.debugMode then
            print(string.format("[NPC Favor] %s lives %.0fm from field — no closer home available",
                npc.name or "?", npc.homeToFieldDistance or 0))
        end
    end
end

-- =========================================================
-- Real Vehicle Spawning (Phase B1 + B2 + C)
-- =========================================================

--- Pool of base-game tractor XML paths for variety.
-- These are validated at runtime via g_storeManager; invalid entries are removed.
-- Medium-class Fendts (500/700 Vario) so they look right AND have the power to
-- pull the field-work implements in IMPLEMENT_POOL (the Vario 200 was far too
-- small under a 6-furrow plow).
NPCSystem.TRACTOR_POOL = {
    "data/vehicles/fendt/vario700/vario700.xml",
    "data/vehicles/fendt/vario500/vario500.xml",
}

--- Pool of commute vehicles (cars/pickups). Falls back to TRACTOR_POOL if empty.
-- Populated at runtime via discoverVehiclesFromStore or store-item validation.
NPCSystem.COMMUTE_VEHICLE_POOL = {}

--- Pool of base-game implement XML paths (plows/cultivators for TILL jobs).
NPCSystem.IMPLEMENT_POOL = {
    "data/vehicles/poettinger/servoT6000Plus/servoT6000Plus.xml",
    "data/vehicles/kuhn/kuhnCultimer400/kuhnCultimer400.xml",
}

--- Seeders/planters for SOW jobs (tractor-drawn). Filled with seed after attach.
NPCSystem.SEEDER_POOL = {
    "data/vehicles/amazone/citan15001C/citan15001C.xml",
    "data/vehicles/horsch/avatar1225/avatar1225.xml",
    "data/vehicles/vaderstad/nzExtreme1425/nzExtreme1425.xml",
}

--- Self-propelled combine + matching header pairs for HARVEST jobs. The combine
-- is the work vehicle (npc.realTractor); the header attaches to it. Paired by
-- brand so the header actually fits the combine.
NPCSystem.HARVEST_COMBOS = {
    { combine = "data/vehicles/claas/lexion6900/lexion6900.xml",   header = "data/vehicles/claas/convioFlex1080/convioFlex1080.xml" },
    { combine = "data/vehicles/newHolland/cr980_830/cr980_830.xml", header = "data/vehicles/newHolland/varifeed28/varifeed28.xml" },
}

--- Max NPCs allowed to run a real game AI field-work job at once. The game AI
-- limit (maxNumHirables) is SHARED with the player's own hired helpers, so we
-- cap our usage low to always leave the player room to hire.
NPCSystem.MAX_NPC_AI_JOBS = 2

--- Validate vehicle pools against the store manager at runtime.
-- Removes entries that aren't registered storeitems and discovers alternatives.
function NPCSystem:validateVehiclePools()
    if not g_storeManager then return end

    -- Validate tractor pool
    local validTractors = {}
    for _, path in ipairs(self.TRACTOR_POOL) do
        local ok, item = pcall(function() return g_storeManager:getItemByXMLFilename(path) end)
        if ok and item then
            table.insert(validTractors, path)
        else
            print(string.format("[NPC Favor] Tractor pool: '%s' not found in store, removing", path))
        end
    end

    -- Validate implement pool
    local validImplements = {}
    for _, path in ipairs(self.IMPLEMENT_POOL) do
        local ok, item = pcall(function() return g_storeManager:getItemByXMLFilename(path) end)
        if ok and item then
            table.insert(validImplements, path)
        else
            print(string.format("[NPC Favor] Implement pool: '%s' not found in store, removing", path))
        end
    end

    -- If pools are empty after validation, try runtime discovery
    if #validTractors == 0 then
        print("[NPC Favor] No valid tractors in pool — attempting store discovery")
        validTractors = self:discoverVehiclesFromStore("TRACTOR")
    end
    if #validImplements == 0 then
        print("[NPC Favor] No valid implements in pool — attempting store discovery")
        validImplements = self:discoverVehiclesFromStore("CULTIVATOR")
    end

    self.TRACTOR_POOL = validTractors
    self.IMPLEMENT_POOL = validImplements

    -- Validate seeder pool (SOW role)
    local validSeeders = {}
    for _, path in ipairs(self.SEEDER_POOL or {}) do
        local ok, item = pcall(function() return g_storeManager:getItemByXMLFilename(path) end)
        if ok and item then table.insert(validSeeders, path) end
    end
    self.SEEDER_POOL = validSeeders

    -- Validate harvest combos (HARVEST role): keep only combos whose combine AND header both exist
    local validCombos = {}
    for _, combo in ipairs(self.HARVEST_COMBOS or {}) do
        local okC, itemC = pcall(function() return g_storeManager:getItemByXMLFilename(combo.combine) end)
        local okH, itemH = pcall(function() return g_storeManager:getItemByXMLFilename(combo.header) end)
        if okC and itemC and okH and itemH then table.insert(validCombos, combo) end
    end
    self.HARVEST_COMBOS = validCombos

    -- Build commute vehicle pool: try car/pickup discovery first, fall back to tractors
    local commuteKeywords = {"car", "pickup", "sedan", "hatchback", "suv"}
    local foundCars = {}
    for _, kw in ipairs(commuteKeywords) do
        local cars = self:discoverVehiclesFromStore(kw)
        for _, path in ipairs(cars) do
            table.insert(foundCars, path)
        end
    end
    -- No tractor fallback: if no commute vehicles found, NPCs walk instead.
    -- Using tractors as commute vehicles caused map-filling since every commute
    -- spawned a real tractor that didn't get cleaned up reliably.
    self.COMMUTE_VEHICLE_POOL = foundCars

    print(string.format("[NPC Favor] Vehicle pools validated: %d tractors, %d implements, %d seeders, %d harvest combos, %d commute",
        #self.TRACTOR_POOL, #self.IMPLEMENT_POOL, #self.SEEDER_POOL, #self.HARVEST_COMBOS, #self.COMMUTE_VEHICLE_POOL))
end

--- Discover valid vehicles from the store by category keyword.
-- @param keyword  "TRACTOR" or "CULTIVATOR"
-- @return table  Array of valid XML paths
function NPCSystem:discoverVehiclesFromStore(keyword)
    local results = {}
    pcall(function()
        local items = g_storeManager:getItems()
        if not items then return end
        for _, item in pairs(items) do
            local catName = item.categoryName or ""
            if catName:upper():find(keyword) and item.xmlFilename then
                table.insert(results, item.xmlFilename)
                if #results >= 3 then break end  -- limit to 3 per type
            end
        end
    end)
    return results
end

--- Job role for a farmer NPC: "till" (plow/cultivate), "sow" (seeder) or
-- "harvest" (combine). Assigned once from the appearance seed, weighted toward
-- tillage, and downgraded to "till" if the role's pool is empty.
-- @param npc  NPC data table
-- @return string  role
function NPCSystem:getNPCJobRole(npc)
    if npc.jobRole then return npc.jobRole end

    -- Field-aware: match the role to the assigned field's CURRENT need so we never
    -- park a combine on a growing crop (or on bare ground). A harvester is only
    -- assigned when the field is actually ripe; a field with a growing crop gets a
    -- tractor+plow (which won't till it - the work gate protects the crop - so the
    -- NPC just drives/inspects, far less jarring than a combine on standing peas).
    local field = npc.assignedField or (npc.assignedFields and npc.assignedFields[1])
    local need = field and self:getFieldJobType(field) or "open"

    local role
    if need == "harvest" and self.HARVEST_COMBOS and #self.HARVEST_COMBOS > 0 then
        role = "harvest"
    elseif need == "open" then
        local r = (npc.appearanceSeed or npc.id or 1) % 100
        if r >= 55 and self.SEEDER_POOL and #self.SEEDER_POOL > 0 then
            role = "sow"
        else
            role = "till"
        end
    else
        -- Growing crop: nothing to work. Give a BARE tractor (no implement) so the
        -- NPC just drives out to inspect; never a plow dragged over a standing crop.
        role = "inspect"
    end

    npc.jobRole = role
    return role
end

--- The work VEHICLE for an NPC based on their job role: a combine for harvest
-- (also records the paired header via npc._harvestComboIndex), else a tractor.
-- @param npc  NPC data table
-- @return string|nil  Vehicle XML path
function NPCSystem:getWorkVehicleFilename(npc)
    local role = self:getNPCJobRole(npc)
    if role == "harvest" and self.HARVEST_COMBOS and #self.HARVEST_COMBOS > 0 then
        local idx = ((npc.appearanceSeed or npc.id or 1) % #self.HARVEST_COMBOS) + 1
        npc._harvestComboIndex = idx
        return self.HARVEST_COMBOS[idx].combine
    end
    if not self.TRACTOR_POOL or #self.TRACTOR_POOL == 0 then return nil end
    local index = ((npc.appearanceSeed or npc.id or 1) % #self.TRACTOR_POOL) + 1
    return self.TRACTOR_POOL[index]
end

--- Backwards-compatible alias (till/sow both drive a tractor; harvest a combine).
function NPCSystem:getTractorFilename(npc)
    return self:getWorkVehicleFilename(npc)
end

--- The IMPLEMENT for an NPC based on their job role: the paired header for
-- harvest, a seeder for sow, else a plow/cultivator for till.
-- @param npc  NPC data table
-- @return string|nil  Implement XML path, or nil if unavailable
function NPCSystem:getImplementFilename(npc)
    local role = self:getNPCJobRole(npc)
    if role == "inspect" then return nil end  -- bare tractor, no implement
    if role == "harvest" then
        local combo = self.HARVEST_COMBOS and self.HARVEST_COMBOS[npc._harvestComboIndex or 1]
        return combo and combo.header
    elseif role == "sow" then
        if not self.SEEDER_POOL or #self.SEEDER_POOL == 0 then return nil end
        local index = (((npc.appearanceSeed or npc.id or 1) + 3) % #self.SEEDER_POOL) + 1
        return self.SEEDER_POOL[index]
    end
    if not self.IMPLEMENT_POOL or #self.IMPLEMENT_POOL == 0 then return nil end
    local index = (((npc.appearanceSeed or npc.id or 1) + 7) % #self.IMPLEMENT_POOL) + 1
    return self.IMPLEMENT_POOL[index]
end

--- Fill a seeder's fill units with SEEDS so it can actually sow (best-effort).
-- @param implement  the attached seeder vehicle
function NPCSystem:fillSeederWithSeed(implement)
    if not implement or not implement.getFillUnits or not g_fillTypeManager then return end
    local seedsIndex = g_fillTypeManager:getFillTypeIndexByName("SEEDS")
    if not seedsIndex then return end
    local farmId = (implement.getOwnerFarmId and implement:getOwnerFarmId()) or 1
    local units = implement:getFillUnits()
    if not units then return end
    for i = 1, #units do
        pcall(function()
            if implement.getFillUnitSupportsFillType and implement:getFillUnitSupportsFillType(i, seedsIndex) then
                local cap = (implement.getFillUnitCapacity and implement:getFillUnitCapacity(i)) or 1000
                local tt = (ToolType and ToolType.UNDEFINED) or 0
                implement:addFillUnitFillLevel(farmId, i, cap, seedsIndex, tt)
            end
        end)
    end
end

--- Spawn a real FS25 vehicle for an NPC farmer using VehicleLoadingData.
-- Gracefully falls back to nil if VehicleLoadingData API is unavailable.
-- @param npc       NPC data table (requires npc.assignedField)
-- @param callback  Optional function(vehicle) called on success/failure
function NPCSystem:spawnNPCTractor(npc, callback)
    -- Guard: API must exist
    if not VehicleLoadingData then
        if self.settings.debugMode then
            print("[NPC Favor] VehicleLoadingData not available — using prop fallback")
        end
        if callback then callback(nil) end
        return
    end

    -- Guard: need a field to position the tractor
    if not npc.assignedField and not (npc.assignedFields and #npc.assignedFields > 0) then
        if callback then callback(nil) end
        return
    end

    -- Get field edge position for tractor placement
    local field = npc.assignedField or (npc.assignedFields and npc.assignedFields[1])
    local fieldEdgeX, fieldEdgeZ = self:getFieldEdgePosition(field)
    if not fieldEdgeX then
        if callback then callback(nil) end
        return
    end

    local tractorFile = self:getTractorFilename(npc)

    local loadingData = VehicleLoadingData.new()
    loadingData:setFilename(tractorFile)
    loadingData:setPosition(fieldEdgeX, nil, fieldEdgeZ)  -- nil y = auto terrain height
    loadingData:setRotation(0, (npc.id or 0) * 1.2, 0)   -- varied facing

    -- Use spectator farm ID so it doesn't appear in player's vehicle list
    local spectatorFarmId = FarmManager.SPECTATOR_FARM_ID or 0
    loadingData:setOwnerFarmId(spectatorFarmId)
    loadingData:setPropertyState(VehiclePropertyState.OWNED)
    loadingData:setIsRegistered(true)
    loadingData:setAddToPhysics(true)
    loadingData:setIsSaved(false)  -- Don't persist — we respawn on load

    loadingData:load(function(_, loadedVehicles, loadingState, args)
        -- VehicleLoadingData calls back as (callbackTarget, loadedVehicles, loadingState, callbackArguments).
        -- loadedVehicles is a list; the root vehicle is entry [1].
        local vehicle = loadedVehicles and loadedVehicles[1] or nil
        if vehicle and VehicleLoadingState ~= nil and loadingState ~= VehicleLoadingState.OK then
            vehicle = nil
        end

        if vehicle then
            npc.realTractor = vehicle
            npc.realTractor.isNPCVehicle = true  -- tag for identification

            -- Prevent player from entering the NPC's tractor.
            -- FS25 entry flow: VehicleSystem.interactiveVehicles → getDistanceToNode()
            -- → interactiveVehicleInRange → E key → vehicle:interact(player)
            -- → player:requestToEnterVehicle(). We attack at multiple levels.
            self:lockNPCVehicle(vehicle)
            print(string.format("[NPC Favor] Tractor locked for %s (not enterable)", npc.name or "?"))

            -- The NPC is seated only on reaching the field and entering WORKING
            -- state (activateNPCTractor), so the tractor stays parked until then.

            print(string.format("[NPC Favor] Real tractor spawned for %s at (%.0f, %.0f) — %s",
                npc.name or "?", fieldEdgeX, fieldEdgeZ, tractorFile))

            -- Give the tractor a field-work implement so it is actually
            -- field-work capable (getCanStartFieldWork). Async; attaches when
            -- loaded. On any failure the implement is cleaned up and the NPC
            -- falls back to the visual row-driving path (never strands a tool).
            self:spawnNPCImplement(npc, vehicle)
        else
            print(string.format("[NPC Favor] Tractor spawn FAILED for %s — %s",
                npc.name or "?", tractorFile))
        end

        if callback then callback(vehicle) end
    end, self, {npc = npc})
end

--- Spawn a field-work implement for an NPC and attach it to their tractor.
-- Async: loads the implement, then attaches via joint-compatibility matching.
-- Robust: if the tractor vanished, the pool is empty, or the attach fails, the
-- implement is deleted (never stranded) and the NPC uses the visual fallback.
-- @param npc       NPC data table (must already have npc.realTractor == tractor)
-- @param tractor   The spawned tractor vehicle to attach to
-- @param callback  Optional function(success) called after the attach attempt
function NPCSystem:spawnNPCImplement(npc, tractor, callback)
    if not VehicleLoadingData or not tractor or tractor.rootNode == nil then
        if callback then callback(false) end
        return
    end

    -- Harvest: many combines spawn WITH a header from their store config, so the
    -- cutter joint is already occupied. If the combine can already do field work,
    -- skip spawning a header (attaching a second one fails and would otherwise
    -- scrap a perfectly good combine).
    if self:getNPCJobRole(npc) == "harvest" then
        local canWork = false
        pcall(function() canWork = tractor.getCanStartFieldWork ~= nil and tractor:getCanStartFieldWork() end)
        if canWork then
            if self.settings.debugMode then
                print(string.format("[NPC Favor] %s combine already has a header, ready to harvest", npc.name or "?"))
            end
            if callback then callback(true) end
            return
        end
    end

    -- Implement depends on the NPC's job role (plow/cultivator, seeder, or header).
    local implementFile = self:getImplementFilename(npc)
    if not implementFile then
        if self.settings.debugMode then
            print(string.format("[NPC Favor] No implement for %s (role=%s) — visual work only",
                npc.name or "?", self:getNPCJobRole(npc)))
        end
        if callback then callback(false) end
        return
    end

    -- Spawn a few metres behind the tractor. attachImplement snaps the tool to
    -- the attacher joint, so exact placement only needs to be in the vicinity.
    local sx, sz, yaw = 0, 0, 0
    local okPos = pcall(function()
        local tx, _, tz = getWorldTranslation(tractor.rootNode)
        local bx, _, bz = localDirectionToWorld(tractor.rootNode, 0, 0, -1)  -- tractor rear
        sx, sz = tx + bx * 5, tz + bz * 5
        local fx, _, fz = localDirectionToWorld(tractor.rootNode, 0, 0, 1)   -- match facing
        yaw = MathUtil.getYRotationFromDirection(fx, fz)
    end)
    if not okPos then
        if callback then callback(false) end
        return
    end

    local loadingData = VehicleLoadingData.new()
    loadingData:setFilename(implementFile)
    loadingData:setPosition(sx, nil, sz)  -- nil y = auto terrain height
    loadingData:setRotation(0, yaw, 0)
    loadingData:setOwnerFarmId(FarmManager.SPECTATOR_FARM_ID or 0)
    loadingData:setPropertyState(VehiclePropertyState.OWNED)
    loadingData:setIsRegistered(true)
    loadingData:setAddToPhysics(true)
    loadingData:setIsSaved(false)  -- respawned on load, never persisted

    loadingData:load(function(_, loadedVehicles, loadingState, args)
        local implement = loadedVehicles and loadedVehicles[1] or nil
        if implement and VehicleLoadingState ~= nil and loadingState ~= VehicleLoadingState.OK then
            implement = nil
        end
        if not implement then
            print(string.format("[NPC Favor] Implement spawn FAILED for %s — %s", npc.name or "?", implementFile))
            if callback then callback(false) end
            return
        end

        -- The tractor may have been removed while we loaded async. Don't strand.
        if npc.realTractor ~= tractor then
            pcall(function() if implement.delete then implement:delete() end end)
            if callback then callback(false) end
            return
        end

        implement.isNPCVehicle = true
        self:lockNPCVehicle(implement)

        if self:attachImplementToTractor(tractor, implement) then
            npc.realImplement = implement
            -- Sowers need seed loaded to actually plant.
            if self:getNPCJobRole(npc) == "sow" then
                pcall(function() self:fillSeederWithSeed(implement) end)
            end
            print(string.format("[NPC Favor] Implement attached for %s — %s", npc.name or "?", implementFile))
            if callback then callback(true) end
        else
            -- Could not attach. Delete the tool rather than leave it in the field.
            pcall(function() if implement.delete then implement:delete() end end)
            -- A combine with no header is useless: remove it too so the NPC falls
            -- back cleanly (prop/visual) instead of a headerless combine that can
            -- do nothing.
            if self:getNPCJobRole(npc) == "harvest" then
                pcall(function() self:removeNPCTractor(npc) end)
            end
            if self.settings.debugMode then
                print(string.format("[NPC Favor] Implement attach failed for %s — removed, using visual work", npc.name or "?"))
            end
            if callback then callback(false) end
        end
    end, self, {npc = npc})
end

--- Attach an implement to a tractor by matching a free attacher joint on the
-- tractor with a compatible input attacher joint on the implement.
-- Mirrors the engine's own compatibility test (jointType + getAttacherJointCompatibility).
-- @param tractor    Attacher vehicle (has attacherJoints)
-- @param implement  Attachable (has inputAttacherJoints)
-- @return boolean   true if attached
function NPCSystem:attachImplementToTractor(tractor, implement)
    local ok, result = pcall(function()
        if not tractor.getAttacherJoints or not implement.getInputAttacherJoints then
            return false
        end
        local attacherJoints = tractor:getAttacherJoints()
        local inputJoints = implement:getInputAttacherJoints()
        if not attacherJoints or not inputJoints then return false end

        -- Pass 1: strict compatibility (jointType + getAttacherJointCompatibility).
        for aIdx, aJoint in ipairs(attacherJoints) do
            -- jointIndex 0 == this attacher joint is free (nothing attached)
            if (aJoint.jointIndex or 0) == 0 then
                for iIdx, iJoint in ipairs(inputJoints) do
                    if aJoint.jointType == iJoint.jointType then
                        local compatible = true
                        if AttacherJoints ~= nil and AttacherJoints.getAttacherJointCompatibility ~= nil then
                            compatible = AttacherJoints.getAttacherJointCompatibility(tractor, aJoint, implement, iJoint)
                        end
                        if compatible then
                            tractor:attachImplement(implement, iIdx, aIdx)
                            return true
                        end
                    end
                end
            end
        end

        -- Pass 2: fall back to a jointType match alone. Header/cutter joints often
        -- fail the strict subType compatibility check even for a valid pairing; a
        -- slightly-relaxed attach is better than a headerless combine.
        for aIdx, aJoint in ipairs(attacherJoints) do
            if (aJoint.jointIndex or 0) == 0 then
                for iIdx, iJoint in ipairs(inputJoints) do
                    if aJoint.jointType == iJoint.jointType then
                        tractor:attachImplement(implement, iIdx, aIdx)
                        return true
                    end
                end
            end
        end
        return false
    end)
    return ok and result == true
end

--- Seat an NPC's HumanModel character in a vehicle's cab via VehicleCharacter.
-- @param npc      NPC data table
-- @param vehicle  The spawned FS25 Vehicle object
function NPCSystem:seatNPCInVehicle(npc, vehicle)
    pcall(function()
        if not vehicle.spec_enterable or not vehicle.spec_enterable.vehicleCharacter then
            return
        end

        local vc = vehicle.spec_enterable.vehicleCharacter
        local entity = self.entityManager and self.entityManager.npcEntities[npc.id]

        if entity and entity.playerStyle then
            -- Correct signature is loadCharacter(playerStyle, asyncCallbackObject,
            -- asyncCallbackFunction, asyncCallbackArguments); the engine then calls
            -- asyncCallbackFunction(asyncCallbackObject, loadingState, args).
            -- The old call passed a closure as the OBJECT and self as the FUNCTION,
            -- so the engine tried to call a table (VehicleCharacter.lua:190).
            vc:loadCharacter(entity.playerStyle, self, self.onNPCCharacterLoaded, {npc = npc, entity = entity})
        end
    end)
end

--- Async callback fired when an NPC character finishes loading into a vehicle
-- seat. Invoked by the engine as self:onNPCCharacterLoaded(loadingState, args).
-- @param loadingState  Engine loading state (unused)
-- @param args          { npc = <npc>, entity = <entity> }
function NPCSystem:onNPCCharacterLoaded(loadingState, args)
    if not args then return end
    local npc, entity = args.npc, args.entity
    if entity and entity.node then
        pcall(function() setVisibility(entity.node, false) end)  -- hide standalone walking model
    end
    if npc then npc.isSeatedInVehicle = true end
end

--- Unseat an NPC from their vehicle and restore the walking model.
-- @param npc  NPC data table
function NPCSystem:unseatNPCFromVehicle(npc)
    pcall(function()
        if npc.realTractor and npc.realTractor.spec_enterable then
            local vc = npc.realTractor.spec_enterable.vehicleCharacter
            if vc and vc.setCharacterVisibility then
                vc:setCharacterVisibility(false)
            end
        end

        self:setNPCEntityHidden(npc, false)
        npc.isSeatedInVehicle = false
    end)
end

--- Hide or show an NPC's standalone walking/human model.
-- Used while the game's AI helper drives the NPC's tractor: the helper occupies
-- the cab (via createAgent), so our separate model must be hidden to avoid a
-- visible duplicate person.
-- @param npc     NPC data table
-- @param hidden  true to hide the model, false to show it
function NPCSystem:setNPCEntityHidden(npc, hidden)
    local entity = self.entityManager and self.entityManager.npcEntities[npc.id]
    if not entity then return end
    if entity.node then
        pcall(function() setVisibility(entity.node, not hidden) end)
    end
    if entity.humanModel and entity.humanModel.rootNode then
        pcall(function() setVisibility(entity.humanModel.rootNode, not hidden) end)
    end
end

--- Count NPCs currently running a real game AI field-work job.
-- @return number  active NPC AI job count
function NPCSystem:countActiveNPCAIJobs()
    local n = 0
    for _, npc in ipairs(self.activeNPCs) do
        if npc.activeAIJob then n = n + 1 end
    end
    return n
end

--- Start an AI field work job for an NPC using their real tractor.
-- Follows the game's own start recipe (see AISystem:consoleCommandAIStart):
--   createJob(FIELDWORK) -> set vehicle + position -> setValues() -> validate() -> startJob().
-- The critical step is job:setValues(): it wires the vehicle and drive target
-- into the drive/fieldwork tasks. Skipping it leaves AITaskDriveTo running
-- against a nil vehicle every frame, which is what spammed the console.
-- We also gate on vehicle:getCanStartFieldWork() — the engine's own check for
-- "is this vehicle actually field-work capable". A bare tractor (no lowered
-- implement with work areas) returns false, so we never hand the AI machine a
-- job it cannot run. Returns true only when the job actually started.
-- @param npc  NPC data table (requires npc.realTractor and npc.assignedField)
function NPCSystem:startNPCFieldWork(npc)
    local vehicle = npc.realTractor
    if not vehicle or not g_currentMission or not g_currentMission.aiJobTypeManager then
        return false
    end
    if AIJobType == nil or AIJobType.FIELDWORK == nil then
        return false
    end

    -- Engine gate: only start field work on a field-work-capable vehicle.
    -- Bare tractor -> false -> fall back to the visual path (no spam, no crash).
    local canFieldWork = false
    pcall(function()
        canFieldWork = vehicle.getCanStartFieldWork ~= nil and vehicle:getCanStartFieldWork()
    end)
    if not canFieldWork then
        if self.settings.debugMode then
            print(string.format("[NPC Favor] %s cannot start AI field work (no field-work implement) — using visual work",
                npc.name or "?"))
        end
        return false
    end

    -- Guardrail: the game AI limit (maxNumHirables) is shared with the player's
    -- hired helpers. Respect it, and cap concurrent NPC jobs so we never starve
    -- the player's ability to hire. Fall back to visual work when at capacity.
    local aiSystem = g_currentMission.aiSystem
    if aiSystem and aiSystem.getAILimitedReached and aiSystem:getAILimitedReached() then
        return false
    end
    if self:countActiveNPCAIJobs() >= (self.MAX_NPC_AI_JOBS or 2) then
        return false
    end

    -- Determine field target
    local field = npc.assignedField or (npc.assignedFields and npc.assignedFields[1])
    if not field then return false end

    local cx = (field.center and field.center.x) or 0
    local cz = (field.center and field.center.z) or 0

    local job = g_currentMission.aiJobTypeManager:createJob(AIJobType.FIELDWORK)
    if not job then return false end

    -- Set vehicle via named parameter
    pcall(function()
        local vehicleParam = job:getNamedParameter("vehicle")
        if vehicleParam and vehicleParam.setVehicle then
            vehicleParam:setVehicle(vehicle)
        end
    end)

    -- Set field position/angle
    pcall(function()
        local posParam = job:getNamedParameter("positionAngle")
        if posParam and posParam.setPosition then
            posParam:setPosition(cx, cz)
            posParam:setAngle(0)
        end
    end)

    -- CRITICAL: transfer the parameters into the tasks (task vehicle + drive
    -- target). Without this the AI tasks run unconfigured and spam every frame.
    local valuesOk = pcall(function() job:setValues() end)
    if not valuesOk then
        if self.settings.debugMode then
            print(string.format("[NPC Favor] AI job setValues failed for %s — aborting", npc.name or "?"))
        end
        return false
    end

    -- Validate before starting
    local farmId = npc.ownerFarmId or FarmManager.SPECTATOR_FARM_ID or 0
    local valid, errorMsg = false, "unknown"
    pcall(function()
        valid, errorMsg = job:validate(farmId)
    end)

    if valid then
        local started = pcall(function()
            g_currentMission.aiSystem:startJob(job, farmId)
        end)
        if not started then
            if self.settings.debugMode then
                print(string.format("[NPC Favor] AI startJob failed for %s", npc.name or "?"))
            end
            return false
        end
        npc.activeAIJob = job
        npc.currentAction = "field work (AI)"

        -- The game's AI helper drives the tractor: createAgent seats a helper in
        -- the cab. Do NOT also load our own character into the same seat — that
        -- double-loads the vehicleCharacter and throws in loadSharedI3DFileAsyncFinished.
        -- Just hide our standalone walking model while the AI works.
        npc.isSeatedInVehicle = true
        self:setNPCEntityHidden(npc, true)

        if self.settings.debugMode then
            print(string.format("[NPC Favor] AI field work started for %s on field at (%.0f, %.0f)",
                npc.name or "?", cx, cz))
        end
        return true
    else
        if self.settings.debugMode then
            print(string.format("[NPC Favor] AI job validation failed for %s: %s",
                npc.name or "?", tostring(errorMsg)))
        end
        return false
    end
end

--- Stop an active AI field work job for an NPC.
-- @param npc  NPC data table
function NPCSystem:stopNPCFieldWork(npc)
    -- If the base-game AI GoTo chain is driving, stop that (handles unseat too).
    if npc.goToActive then
        self:stopNPCGoTo(npc)
        if self.settings.debugMode then
            print(string.format("[NPC Favor] AI GoTo driving stopped for %s", npc.name or "?"))
        end
        return
    end

    if npc.activeAIJob then
        pcall(function()
            g_currentMission.aiSystem:stopJob(npc.activeAIJob)
        end)
        npc.activeAIJob = nil
    end

    -- Restore any temporary field ownership from a tillage job.
    if npc.usingFieldWorkOwned then
        self:_restoreNPCFieldOwnership(npc)
        npc.usingFieldWorkOwned = false
    end

    -- Unseat NPC from tractor
    self:unseatNPCFromVehicle(npc)

    if self.settings.debugMode then
        print(string.format("[NPC Favor] AI field work stopped for %s", npc.name or "?"))
    end
end

--- React to the game stopping an AI job (field finished, blocked, vehicle gone).
-- If it was one of our NPCs' field-work jobs, drop the reference, unseat the NPC
-- and return them to idle so they re-decide. Fires for ALL AI jobs including the
-- player's hired helpers, so we only touch a job we own.
-- @param job        The AIJob that stopped
-- @param aiMessage  The stop reason (unused)
function NPCSystem:onAIJobStopped(job, aiMessage)
    if job == nil then return end
    for _, npc in ipairs(self.activeNPCs) do
        if npc.activeAIJob == job then
            npc.activeAIJob = nil
            if npc.goToActive then
                -- A GoTo waypoint finished: drive to the next one (keep working).
                self:advanceNPCGoTo(npc, aiMessage)
            else
                -- Real tillage job ended: restore the field's original owner.
                if npc.usingFieldWorkOwned then
                    self:_restoreNPCFieldOwnership(npc)
                    npc.usingFieldWorkOwned = false
                end
                pcall(function() self:unseatNPCFromVehicle(npc) end)
                npc.aiState = "idle"
                npc.currentAction = "idle"
                npc.workTimer = 0
                if self.settings.debugMode then
                    local reason = "?"
                    pcall(function()
                        if aiMessage ~= nil then
                            if aiMessage.getMessage ~= nil then
                                local m = aiMessage:getMessage(job)
                                if m ~= nil and m ~= "" then reason = tostring(m) end
                            end
                            if reason == "?" and aiMessage.getType ~= nil then
                                reason = "type=" .. tostring(aiMessage:getType())
                            end
                            if reason == "?" and ClassUtil and ClassUtil.getClassNameByObject then
                                reason = tostring(ClassUtil.getClassNameByObject(aiMessage))
                            end
                        end
                    end)
                    print(string.format("[NPC Favor] AI job ended for %s (released) reason=%s", npc.name or "?", reason))
                end
            end
            break
        end
    end
end


--- Remove an NPC's real tractor and implement from the world.
-- @param npc  NPC data table
function NPCSystem:removeNPCTractor(npc)
    -- Stop active AI job first
    self:stopNPCFieldWork(npc)

    -- Remove implement. Vehicle:delete() is the real FS25 deletion API;
    -- g_currentMission:removeVehicle does not exist and silently no-ops inside
    -- the pcall, which is why NPC tractors used to strand on the map.
    if npc.realImplement then
        pcall(function()
            if npc.realTractor and npc.realTractor.detachImplement then
                npc.realTractor:detachImplement(npc.realImplement)
            end
        end)
        pcall(function()
            if npc.realImplement.delete then npc.realImplement:delete() end
        end)
        npc.realImplement = nil
    end

    -- Remove tractor
    if npc.realTractor then
        pcall(function()
            if npc.realTractor.delete then npc.realTractor:delete() end
        end)
        npc.realTractor = nil
    end

    npc.isSeatedInVehicle = false
end

--- Spawn a commute vehicle for an NPC (car or tractor fallback).
-- Hides walking entity on spawn; caller must call removeNPCCar on arrival.
-- @param npc       NPC data table
-- @param callback  Optional function(vehicle) called after spawn attempt
function NPCSystem:spawnNPCCar(npc, callback)
    if not VehicleLoadingData then
        if callback then callback(nil) end
        return
    end

    -- Guard: don't double-spawn. If NPC already has a car or a load is in-flight, bail.
    if npc.realCar or npc.pendingVehicleLoad then
        if callback then callback(npc.realCar) end
        return
    end

    local pool = self.COMMUTE_VEHICLE_POOL
    if not pool or #pool == 0 then
        if callback then callback(nil) end
        return
    end

    local seed = npc.appearanceSeed or npc.id or 1
    local vehicleFile = pool[(seed % #pool) + 1]

    -- Spawn 15 m ahead of the NPC in the direction of travel so the vehicle
    -- starts outside the home building rather than clipped into it.
    local spawnX, spawnZ = npc.position.x, npc.position.z
    if npc.driveDestination then
        local dx = npc.driveDestination.x - npc.position.x
        local dz = npc.driveDestination.z - npc.position.z
        local dist = math.sqrt(dx * dx + dz * dz)
        if dist > 20 then
            spawnX = npc.position.x + (dx / dist) * 15
            spawnZ = npc.position.z + (dz / dist) * 15
        end
    end

    local loadingData = VehicleLoadingData.new()
    loadingData:setFilename(vehicleFile)
    loadingData:setPosition(spawnX, nil, spawnZ)
    loadingData:setRotation(0, npc.rotation.y or 0, 0)

    -- Use the player's farm so createAgent/setAITarget work (spectator farm blocks AI helpers)
    local playerFarmId = (g_currentMission and g_currentMission.player and g_currentMission.player.farmId) or 1
    loadingData:setOwnerFarmId(playerFarmId)
    loadingData:setPropertyState(VehiclePropertyState.OWNED)
    loadingData:setIsRegistered(true)
    loadingData:setAddToPhysics(true)
    loadingData:setIsSaved(false)

    loadingData:load(function(_, loadedVehicles, loadingState, args)
        -- Clear pending flag regardless of outcome
        npc.pendingVehicleLoad = false

        -- VehicleLoadingData calls back as (callbackTarget, loadedVehicles, loadingState, callbackArguments).
        -- loadedVehicles is a list; the root vehicle is entry [1].
        local vehicle = loadedVehicles and loadedVehicles[1] or nil
        if vehicle and VehicleLoadingState ~= nil and loadingState ~= VehicleLoadingState.OK then
            vehicle = nil
        end

        if vehicle then
            -- Guard: NPC must still be in DRIVING state and awake
            if not npc.isActive or npc.aiState ~= "driving" or npc.isSleeping then
                if self.settings.debugMode then
                    print(string.format("[NPC Favor] spawnNPCCar: discarding orphan vehicle for %s (state=%s sleeping=%s)",
                        npc.name or "?", tostring(npc.aiState), tostring(npc.isSleeping)))
                end
                pcall(function() if vehicle.delete then vehicle:delete() end end)
                if callback then callback(nil) end
                return
            end
            -- Guard: race condition — if a second spawn somehow completed first, discard this one
            if npc.realCar then
                if self.settings.debugMode then
                    print(string.format("[NPC Favor] spawnNPCCar: race condition discard for %s", npc.name or "?"))
                end
                pcall(function() if vehicle.delete then vehicle:delete() end end)
                if callback then callback(npc.realCar) end
                return
            end
            npc.realCar = vehicle
            vehicle.isNPCVehicle = true
            self:lockNPCVehicle(vehicle)
            self:seatNPCInVehicle(npc, vehicle)
            self:startNPCCarDriving(npc, vehicle)
            if self.settings.debugMode then
                print(string.format("[NPC Favor] Commute vehicle spawned for %s — %s",
                    npc.name or "?", vehicleFile))
            end
        else
            -- Spawn failed: restore entity visibility (was hidden in startCommute)
            local entity = self.entityManager and self.entityManager.npcEntities[npc.id]
            if entity and entity.node then
                pcall(function() setVisibility(entity.node, true) end)
            end
        end
        if callback then callback(vehicle) end
    end, self, {npc = npc})
end

--- Start AI driving on the NPC's commute vehicle toward npc.driveDestination.
-- Calls prepareForAIDriving; NPCAI:updateDrivingState polls readiness and calls setAITarget.
-- @param npc      NPC data table (must have driveDestination set)
-- @param vehicle  Spawned commute vehicle
function NPCSystem:startNPCCarDriving(npc, vehicle)
    if not vehicle or not npc.driveDestination then return end
    if not vehicle.createAgent or not vehicle.setAITarget then return end

    -- Minimal task proxy: called back by AIDrivable when target is reached or errors
    local task = {
        onTargetReached = function()
            npc.vehicleReachedTarget = true
        end,
        onError = function(_, msg)
            if self.settings.debugMode then
                print("[NPC Favor] AI commute error for " .. (npc.name or "?") .. ": " .. tostring(msg))
            end
        end,
    }
    npc.realCarTask = task
    npc.realCarPreparing = true

    pcall(function()
        vehicle:createAgent(1)
        vehicle:prepareForAIDriving()
    end)

    if self.settings.debugMode then
        print(string.format("[NPC Favor] AI driving prepared for %s → (%.0f, %.0f)",
            npc.name or "?", npc.driveDestination.x, npc.driveDestination.z))
    end
end

--- Remove an NPC's commute vehicle and restore their walking character.
-- @param npc  NPC data table
function NPCSystem:removeNPCCar(npc)
    if not npc.realCar then return end

    -- Stop AI driving cleanly before removing
    pcall(function()
        if npc.realCar.unsetAITarget then npc.realCar:unsetAITarget() end
        if npc.realCar.deleteAgent   then npc.realCar:deleteAgent()   end
    end)
    npc.realCarTask     = nil
    npc.realCarPreparing = nil
    npc.vehicleReachedTarget = nil

    -- Restore walking entity visibility
    local entity = self.entityManager and self.entityManager.npcEntities[npc.id]
    if entity and entity.node then
        pcall(function() setVisibility(entity.node, true) end)
    end
    npc.isSeatedInVehicle = false

    -- Remove vehicle from world (Vehicle:delete is the real FS25 API)
    pcall(function()
        if npc.realCar and npc.realCar.delete then npc.realCar:delete() end
    end)
    npc.realCar = nil
end

--- Activate an NPC's parked tractor for field work (hybrid mode).
-- Seats the NPC in the tractor and starts AI field work.
-- Called when NPC enters WORKING state.
-- @param npc  NPC data table
-- =========================================================
-- Real AI tillage via AIJobFieldWork + temporary field ownership
-- =========================================================
-- AIJobFieldWork refuses to work a field the job's farm does not own, and NPC
-- farms aren't real land-owning farms (the engine has no farm-creation API). So
-- we TEMPORARILY transfer the field's farmland to a real farm (the local
-- player's) for the duration of the job, then restore the original owner when it
-- ends. A save-hook safeguard (restoreAllOwnershipFlips, called at the top of
-- saveToXMLFile) restores every flip before any save writes, so a temporary flip
-- can never persist to disk.

--- Flip a farmland's owner to toFarmId, remembering the original for restore.
function NPCSystem:_flipFarmlandOwnership(farmlandId, toFarmId)
    if not g_farmlandManager or not farmlandId then return false end
    self._ownershipFlips = self._ownershipFlips or {}
    if self._ownershipFlips[farmlandId] == nil then
        self._ownershipFlips[farmlandId] = g_farmlandManager:getFarmlandOwner(farmlandId) or 0
    end
    local ok = false
    pcall(function() ok = g_farmlandManager:setLandOwnership(farmlandId, toFarmId) end)
    return ok
end

--- Restore a single flipped farmland to its original owner (idempotent).
function NPCSystem:_restoreFarmlandOwnership(farmlandId)
    if not g_farmlandManager or not farmlandId or not self._ownershipFlips then return end
    local original = self._ownershipFlips[farmlandId]
    if original == nil then return end
    pcall(function() g_farmlandManager:setLandOwnership(farmlandId, original) end)
    self._ownershipFlips[farmlandId] = nil
end

--- Restore the ownership flip for a specific NPC's field, if any.
function NPCSystem:_restoreNPCFieldOwnership(npc)
    if npc._ownedFarmland then
        self:_restoreFarmlandOwnership(npc._ownedFarmland)
        npc._ownedFarmland = nil
    end
end

--- Restore ALL flipped farmlands (before every save, and on shutdown), so no
-- temporary ownership ever persists.
function NPCSystem:restoreAllOwnershipFlips()
    if not self._ownershipFlips or not g_farmlandManager then return end
    for farmlandId, original in pairs(self._ownershipFlips) do
        pcall(function() g_farmlandManager:setLandOwnership(farmlandId, original) end)
    end
    self._ownershipFlips = {}
    for _, npc in ipairs(self.activeNPCs) do
        npc._ownedFarmland = nil
    end
end

--- Classify what job a field needs right now by reading its crop + growth state.
-- Uses FieldState (verified: FieldState.new():update(x,z) -> fruitTypeIndex /
-- growthState) + FruitTypeDesc growth predicates.
-- @param field  assignedField-style table with .center
-- @return string  "open" (no crop / stubble: tillable + sowable), "harvest"
--                 (ripe crop), or "protect" (growing crop, never touched).
function NPCSystem:getFieldJobType(field)
    if not field or not field.center or FieldState == nil then return "open" end

    local fruitIndex, growth
    local ok = pcall(function()
        local fs = FieldState.new()
        fs:update(field.center.x, field.center.z)
        fruitIndex = fs.fruitTypeIndex
        growth = fs.growthState
    end)
    if not ok then return "open" end

    -- No crop (or unknown) -> open ground: tillable and sowable.
    local unknown = (FruitType and FruitType.UNKNOWN) or 0
    if not fruitIndex or fruitIndex == unknown or fruitIndex == 0 then
        return "open"
    end

    local fruitDesc = g_fruitTypeManager and g_fruitTypeManager:getFruitTypeByIndex(fruitIndex)
    if fruitDesc then
        if fruitDesc.getIsHarvestable and fruitDesc:getIsHarvestable(growth) then
            return "harvest"   -- ripe: harvesters only
        end
        if fruitDesc.getIsCut and fruitDesc:getIsCut(growth) then
            return "open"      -- stubble after harvest: fine to work under
        end
        if fruitDesc.getIsGrowing and fruitDesc:getIsGrowing(growth) then
            return "protect"   -- growing crop: never plow or cut it
        end
    end
    -- Unclassified but a crop is present: protect it rather than risk destroying it.
    return "protect"
end

--- Start real AI tillage for an NPC: temporarily own the field, run AIJobFieldWork.
-- @return boolean  true if the tillage job started
function NPCSystem:startNPCFieldWorkOwned(npc)
    local vehicle = npc.realTractor
    if not vehicle or not g_currentMission or not g_currentMission.aiJobTypeManager then return false end
    if AIJobType == nil or AIJobType.FIELDWORK == nil or not g_farmlandManager then return false end

    -- Needs a field-work-capable combo (tractor + lowerable implement with work areas).
    local canFieldWork = false
    pcall(function() canFieldWork = vehicle.getCanStartFieldWork ~= nil and vehicle:getCanStartFieldWork() end)
    if not canFieldWork then return false end

    -- Guardrail: shared AI hire limit + our own cap.
    local aiSystem = g_currentMission.aiSystem
    if aiSystem and aiSystem.getAILimitedReached and aiSystem:getAILimitedReached() then return false end
    if self:countActiveNPCAIJobs() >= (self.MAX_NPC_AI_JOBS or 2) then return false end

    local field = npc.assignedField or (npc.assignedFields and npc.assignedFields[1])
    if not field or not field.center then return false end
    local cx, cz = field.center.x, field.center.z

    -- Job-to-field matching: run the AI only when the field's current need matches
    -- this NPC's job role. "open" (no crop / stubble) is worked by tillers + sowers;
    -- "harvest" (ripe) by harvesters; a "protect" (growing) field is never touched.
    -- A mismatch falls through to GoTo driving (drive/inspect).
    local need = self:getFieldJobType(field)
    local role = self:getNPCJobRole(npc)
    local matches = (need == "harvest" and role == "harvest")
        or (need == "open" and (role == "till" or role == "sow"))
    if not matches then
        if self.settings.debugMode then
            print(string.format("[NPC Favor] %s (role=%s): field need=%s, skipping (drive/inspect)",
                npc.name or "?", role, need))
        end
        return false
    end

    local farmlandId
    pcall(function() farmlandId = g_farmlandManager:getFarmlandIdAtWorldPosition(cx, cz) end)
    if not farmlandId then return false end

    -- Temporarily own the field with the local player's farm (a guaranteed real farm).
    local jobFarmId = (g_currentMission.getFarmId and g_currentMission:getFarmId())
        or (FarmManager and FarmManager.SINGLEPLAYER_FARM_ID) or 1
    if not self:_flipFarmlandOwnership(farmlandId, jobFarmId) then return false end
    npc._ownedFarmland = farmlandId

    local job = g_currentMission.aiJobTypeManager:createJob(AIJobType.FIELDWORK)
    if not job then self:_restoreNPCFieldOwnership(npc); return false end

    pcall(function()
        local vp = job:getNamedParameter("vehicle")
        if vp and vp.setVehicle then vp:setVehicle(vehicle) end
    end)
    pcall(function()
        local pp = job:getNamedParameter("positionAngle")
        if pp and pp.setPosition then
            pp:setPosition(cx, cz)
            pp:setAngle(0)
        end
    end)
    if not pcall(function() job:setValues() end) then
        self:_restoreNPCFieldOwnership(npc)
        return false
    end

    -- Don't charge the borrowed farm for the NPC's own work.
    job.getPricePerMs = function() return 0 end

    local valid = false
    pcall(function() valid = job:validate(jobFarmId) end)
    if not valid then
        self:_restoreNPCFieldOwnership(npc)
        return false
    end

    if not pcall(function() g_currentMission.aiSystem:startJob(job, jobFarmId) end) then
        self:_restoreNPCFieldOwnership(npc)
        return false
    end

    npc.activeAIJob = job
    npc.usingFieldWorkOwned = true
    npc.currentAction = "field work (AI)"
    -- The game's helper (createAgent) drives; hide our walking model.
    self:setNPCEntityHidden(npc, true)
    return true
end

-- =========================================================
-- Base-game AI driving via chained AIJobGoTo
-- =========================================================
-- AIJobFieldWork can't be used on NPC fields (the farm must own the field, and
-- NPC farms don't own land -> "field not owned"). AIJobGoTo has NO ownership
-- check, so we use the REAL base-game AI to DRIVE the combo (pathfinding,
-- collision avoidance, road following) across the field's row waypoints, one
-- GoTo target at a time, chaining on job completion. This is genuine game-AI
-- driving without the ownership wall. FOLLOW-UP: real tillage via AIJobFieldWork
-- would need NPC-owned farmland (setLandOwnership + a real NPC farm); deferred.

--- Start (or restart) a GoTo job to the NPC's current field waypoint.
-- @return boolean  true if the job started
function NPCSystem:startGoToWaypoint(npc)
    local vehicle = npc.realTractor
    if not vehicle or not g_currentMission or not g_currentMission.aiJobTypeManager then return false end
    if AIJobType == nil or AIJobType.GOTO == nil then return false end

    local wps = npc.goToWaypoints
    local idx = npc.goToIndex or 1
    local wp = wps and wps[idx]
    if not wp then return false end

    local job = g_currentMission.aiJobTypeManager:createJob(AIJobType.GOTO)
    if not job then return false end

    pcall(function()
        local vp = job:getNamedParameter("vehicle")
        if vp and vp.setVehicle then vp:setVehicle(vehicle) end
    end)

    -- Head toward the next waypoint for a natural final heading.
    local angle = 0
    local nextWp = wps[idx + 1]
    if nextWp and MathUtil and MathUtil.getYRotationFromDirection then
        pcall(function() angle = MathUtil.getYRotationFromDirection(nextWp.x - wp.x, nextWp.z - wp.z) end)
    end
    pcall(function()
        local pp = job:getNamedParameter("positionAngle")
        if pp and pp.setPosition then
            pp:setPosition(wp.x, wp.z)
            pp:setAngle(angle)
        end
    end)

    if not pcall(function() job:setValues() end) then return false end

    -- NPC GoTo jobs run under the spectator farm; zero the AI cost so it never
    -- tries to charge it ("Can't change money of spectator farm").
    job.getPricePerMs = function() return 0 end

    local farmId = npc.ownerFarmId or (FarmManager and FarmManager.SPECTATOR_FARM_ID) or 0
    local valid = false
    pcall(function() valid = job:validate(farmId) end)
    if not valid then return false end

    if not pcall(function() g_currentMission.aiSystem:startJob(job, farmId) end) then return false end

    npc.activeAIJob = job
    npc.goToStartTime = (g_currentMission and g_currentMission.time) or 0
    return true
end

--- Begin driving an NPC's combo across its field via chained GoTo jobs.
-- @return boolean  true if the first GoTo started (real AI driving is active)
function NPCSystem:startNPCComboGoTo(npc)
    if not npc.realTractor then return false end

    -- Respect the shared AI hire limit and our own cap so the player isn't starved.
    local aiSystem = g_currentMission and g_currentMission.aiSystem
    if aiSystem and aiSystem.getAILimitedReached and aiSystem:getAILimitedReached() then return false end
    if self:countActiveNPCAIJobs() >= (self.MAX_NPC_AI_JOBS or 2) then return false end

    local field = npc.assignedField or (npc.assignedFields and npc.assignedFields[1])
    if not field then return false end

    local waypoints
    if self.fieldWork and self.fieldWork.getWorkPattern then
        pcall(function() waypoints = self.fieldWork:getWorkPattern(npc, field) end)
    end
    if not waypoints or #waypoints == 0 then return false end

    npc.goToWaypoints = waypoints
    npc.goToIndex = 1
    npc.goToActive = true
    npc.goToFailCount = 0
    npc.usingComboFieldWork = false
    npc.currentAction = "field work (AI)"

    -- The game's helper (createAgent) occupies the cab; hide our walking model.
    self:setNPCEntityHidden(npc, true)

    if self:startGoToWaypoint(npc) then
        return true
    end

    -- Could not start the first GoTo; roll back.
    npc.goToActive = false
    npc.goToWaypoints = nil
    npc.goToIndex = nil
    self:setNPCEntityHidden(npc, false)
    return false
end

--- Advance the GoTo chain when a waypoint job finishes. Detects likely failures
-- (a job that stopped almost immediately) and gives up after a few in a row.
-- @param npc        the NPC whose GoTo just stopped
-- @param aiMessage  the stop message (unused; timing is the reliable signal)
function NPCSystem:advanceNPCGoTo(npc, aiMessage)
    if not npc.goToActive then return end

    -- A GoTo that stops within ~1s almost certainly failed to path rather than
    -- actually drove somewhere. Class-name detection of the AIMessage is unreliable.
    local now = (g_currentMission and g_currentMission.time) or 0
    local elapsed = now - (npc.goToStartTime or now)
    if elapsed >= 0 and elapsed < 1000 then
        npc.goToFailCount = (npc.goToFailCount or 0) + 1
    else
        npc.goToFailCount = 0
    end

    if (npc.goToFailCount or 0) >= 3 then
        -- The AI can't drive this field; stop and let the NPC idle out.
        self:stopNPCGoTo(npc)
        return
    end

    npc.goToIndex = (npc.goToIndex or 1) + 1
    if npc.goToIndex > #(npc.goToWaypoints or {}) then
        npc.goToIndex = 1  -- loop the field pass until the NPC leaves WORKING
    end

    if not self:startGoToWaypoint(npc) then
        self:stopNPCGoTo(npc)
    end
end

--- Stop an NPC's GoTo chain cleanly (order avoids re-entrancy via onAIJobStopped).
function NPCSystem:stopNPCGoTo(npc)
    npc.goToActive = false
    npc.goToWaypoints = nil
    npc.goToIndex = nil
    local job = npc.activeAIJob
    npc.activeAIJob = nil  -- clear BEFORE stopJob so onAIJobStopped won't re-match
    if job then
        pcall(function() g_currentMission.aiSystem:stopJob(job) end)
    end
    self:unseatNPCFromVehicle(npc)
end

function NPCSystem:activateNPCTractor(npc)
    if not npc.realTractor then return false end

    -- 1. Real AI TILLAGE via AIJobFieldWork with temporary field ownership
    --    (the AI actually works the ground).
    if self:startNPCFieldWorkOwned(npc) then
        print(string.format("[NPC Favor] %s tilling field via base-game AI (temp ownership)", npc.name or "?"))
        return true
    end

    -- 2. Real AI DRIVING via chained AIJobGoTo (no ownership needed; drives but
    --    does not till). Used when there's no implement or the ownership flip fails.
    if self:startNPCComboGoTo(npc) then
        print(string.format("[NPC Favor] %s driving combo via base-game AI (GoTo)", npc.name or "?"))
        return true
    end

    -- 3. Kinematic visual fallback (AI hire limit reached, etc.).
    self:seatNPCInVehicle(npc, npc.realTractor)
    npc.usingComboFieldWork = true
    npc.currentAction = "field work"
    print(string.format("[NPC Favor] %s working field with combo (visual fallback)", npc.name or "?"))
    return true
end

--- Deactivate an NPC's tractor after field work (hybrid mode).
-- Unseats the NPC and stops AI. Tractor stays parked where it is.
-- Called when NPC leaves WORKING state.
-- @param npc  NPC data table
function NPCSystem:deactivateNPCTractor(npc)
    if not npc.realTractor then return end

    npc.usingComboFieldWork = false

    if npc.goToActive then
        -- Stop the base-game AI GoTo chain (also unseats).
        self:stopNPCGoTo(npc)
    else
        -- Stop any AI job (no-op in visual mode) and unseat, restoring the walking model
        self:stopNPCFieldWork(npc)
        self:unseatNPCFromVehicle(npc)
    end

    print(string.format("[NPC Favor] %s left tractor (parked at field)", npc.name or "?"))
end

--- Initialize real vehicles for all farmer NPCs (called after NPC init).
-- Modes: "hybrid" = spawn parked tractors at fields (activated when NPC works),
--        "realistic" = spawn + immediately available for AI,
--        "visual" = no real vehicles (prop-only).
function NPCSystem:initializeNPCVehicles()
    if not self.settings.npcDriveVehicles then return end
    local mode = self.settings.npcVehicleMode
    if mode ~= "realistic" and mode ~= "hybrid" then return end
    if not g_currentMission:getIsServer() then return end  -- server authority only

    -- Validate vehicle pools against the store before spawning
    self:validateVehiclePools()

    -- If no valid tractors found, can't spawn anything
    if #self.TRACTOR_POOL == 0 then
        print("[NPC Favor] No valid tractors available — skipping vehicle initialization")
        return
    end

    local spawnCount = 0
    local maxConcurrent = 4  -- limit concurrent real tractors for performance

    for _, npc in ipairs(self.activeNPCs) do
        if spawnCount >= maxConcurrent then break end
        if npc.isActive and (npc.role == "farmer" or npc.role == "farmhand") then
            if npc.assignedField or (npc.assignedFields and #npc.assignedFields > 0) then
                self:spawnNPCTractor(npc, function(vehicle)
                    if vehicle and mode == "hybrid" then
                        -- Hybrid mode: tractor spawns parked at the field.
                        -- NPC walks on foot normally. When NPC enters WORKING state,
                        -- NPCAI calls activateNPCTractor() to seat NPC + start AI.
                        -- When NPC leaves WORKING state, deactivateNPCTractor() restores walking.
                        print(string.format("[NPC Favor] Hybrid tractor parked at field for %s", npc.name or "?"))
                    end
                end)
                spawnCount = spawnCount + 1
            end
        end
    end

    if self.settings.debugMode then
        print(string.format("[NPC Favor] Initialized %d real NPC vehicles (mode: %s)",
            spawnCount, self.settings.npcVehicleMode))
    end
end

--- Switch vehicle mode at runtime (called from console command).
-- @param oldMode  Previous mode string
-- @param newMode  New mode string ("hybrid", "realistic", or "visual")
function NPCSystem:switchVehicleMode(oldMode, newMode)
    if oldMode == newMode then return end

    if newMode == "visual" then
        -- Despawn all real vehicles
        for _, npc in ipairs(self.activeNPCs) do
            if npc.realTractor then
                self:removeNPCTractor(npc)
            end
        end
        print("[NPC Favor] Switched to visual mode — real vehicles removed")
    elseif newMode == "realistic" or newMode == "hybrid" then
        -- Remove existing vehicles first (clean slate)
        for _, npc in ipairs(self.activeNPCs) do
            if npc.realTractor then
                self:removeNPCTractor(npc)
            end
        end
        -- Spawn fresh
        self:initializeNPCVehicles()
        print(string.format("[NPC Favor] Switched to %s mode — spawning vehicles", newMode))
    end
end

--- Lock an NPC vehicle so the player cannot enter it.
-- Uses three independent layers that each prevent entry on their own:
-- 1) Remove from VehicleSystem.interactiveVehicles (no E prompt)
-- 2) Override getDistanceToNode to return math.huge (invisible to proximity)
-- 3) Override interact() to no-op (blocks entry if proximity somehow fires)
-- Also schedules a delayed re-lock because async vehicle finalization
-- can re-register the vehicle after our initial lock.
function NPCSystem:lockNPCVehicle(vehicle)
    if not vehicle then return end

    local function applyLock(v)
        -- Layer 1: Remove from interactive vehicles list
        pcall(function()
            if g_currentMission and g_currentMission.vehicleSystem then
                g_currentMission.vehicleSystem:removeInteractiveVehicle(v)
            end
        end)

        -- Layer 2: Override getDistanceToNode — makes vehicle invisible to
        -- the proximity scan in BaseMission:getInteractiveVehicleInRange()
        v.getDistanceToNode = function(self, node)
            self.interactionFlag = Vehicle.INTERACTION_FLAG_NONE or 0
            return math.huge
        end

        -- Layer 3: Override interact() on instance — blocks the E key action
        v.interact = function(self, player) return end

        -- Layer 4: Prevent Tab-cycling
        pcall(function()
            if v.setIsTabbable then v:setIsTabbable(false) end
        end)
        pcall(function()
            if v.spec_enterable then
                v.spec_enterable.isTabbable = false
                v.spec_enterable.isEnterable = false
            end
        end)
    end

    -- Apply immediately
    applyLock(vehicle)

    -- Re-apply after a short delay — async vehicle finalization may
    -- re-register the vehicle with VehicleSystem after our initial lock
    if g_currentMission and g_currentMission.addDelayedCallback then
        pcall(function()
            g_currentMission:addDelayedCallback(function()
                if vehicle ~= nil then
                    applyLock(vehicle)
                end
            end, 2000) -- 2 second delay
        end)
    end

    -- Also schedule a one-shot delayed re-lock via our own timer
    if not vehicle._npcLockScheduled then
        vehicle._npcLockScheduled = true
        self._pendingVehicleLocks = self._pendingVehicleLocks or {}
        table.insert(self._pendingVehicleLocks, {
            vehicle = vehicle,
            timer = 3.0  -- seconds until re-lock
        })
    end
end

--- Eject the player from any NPC vehicle they've managed to enter.
-- This is the nuclear fallback — runs every 2 seconds in the update loop.
function NPCSystem:ejectPlayerFromNPCVehicles()
    for _, npc in ipairs(self.activeNPCs) do
        if npc.realTractor then
            pcall(function()
                local vehicle = npc.realTractor
                if vehicle.spec_enterable and vehicle.spec_enterable.isControlled then
                    -- Player somehow got into this NPC vehicle — eject them
                    if vehicle.spec_enterable.exitVehicle then
                        vehicle.spec_enterable:exitVehicle()
                    elseif vehicle.leaveVehicle then
                        vehicle:leaveVehicle()
                    end
                    print(string.format("[NPC Favor] Ejected player from %s's tractor!", npc.name or "?"))

                    -- Re-apply full lockdown
                    vehicle._npcLockScheduled = nil
                    self:lockNPCVehicle(vehicle)
                end
            end)

            -- Also ensure lock is maintained every check cycle
            -- (vehicle may have been re-registered by VehicleSystem)
            pcall(function()
                local v = npc.realTractor
                if g_currentMission and g_currentMission.vehicleSystem then
                    g_currentMission.vehicleSystem:removeInteractiveVehicle(v)
                end
                v.interact = function(self, player) return end
                v.getDistanceToNode = function(self, node)
                    self.interactionFlag = 0
                    return math.huge
                end
            end)
        end
    end
end

--- Get a position at the edge of a field closest to the nearest road spline.
-- Used to position NPCs at field edges rather than field centers when they
-- are "planning" or "inspecting" their fields.
-- @param field  Field data table (from g_fieldManager.fields or assignedFields entry)
-- @return x, z  World position at field edge, or nil if field is invalid
function NPCSystem:getFieldEdgePosition(field)
    if not field then
        return nil, nil
    end

    -- Get field center position
    local cx, cz = nil, nil

    pcall(function()
        if field.center then
            cx = field.center.x
            cz = field.center.z
        elseif field.fieldArea and field.fieldArea.fieldCenterX then
            cx = field.fieldArea.fieldCenterX
            cz = field.fieldArea.fieldCenterZ
        elseif field.posX and field.posZ then
            cx = field.posX
            cz = field.posZ
        elseif field.rootNode then
            local ok, fx, _, fz = pcall(getWorldTranslation, field.rootNode)
            if ok and fx then
                cx = fx
                cz = fz
            end
        end
    end)

    if not cx or not cz then
        return nil, nil
    end

    -- Try to find nearest road spline via AI pathfinder
    local splineX, splineZ = nil, nil
    pcall(function()
        if self.aiSystem and self.aiSystem.pathfinder and self.aiSystem.pathfinder.findNearestSpline then
            local ok, sx, _, sz = pcall(self.aiSystem.pathfinder.findNearestSpline,
                self.aiSystem.pathfinder, cx, 0, cz, 100)
            if ok and sx then
                splineX = sx
                splineZ = sz
            end
        end
    end)

    if splineX and splineZ then
        -- Position at field edge closest to the spline
        -- Direction from field center to spline
        local dirX = splineX - cx
        local dirZ = splineZ - cz
        local dist = math.sqrt(dirX * dirX + dirZ * dirZ)
        if dist > 0.1 then
            -- Normalize and offset 10-15m from center toward road
            local edgeDist = 10 + math.random() * 5
            local ex = cx + (dirX / dist) * edgeDist
            local ez = cz + (dirZ / dist) * edgeDist
            return ex, ez
        end
    end

    -- Fallback: offset 10-15m from field center in a random direction
    local angle = math.random() * math.pi * 2
    local offset = 10 + math.random() * 5
    local ex = cx + math.cos(angle) * offset
    local ez = cz + math.sin(angle) * offset
    return ex, ez
end

--- Main update loop, called every frame by the mission.
-- Converts dt from milliseconds to seconds, then dispatches to subsystems.
-- Server: runs full simulation + periodic multiplayer sync.
-- Client: UI rendering + proximity checks using synced positions.
-- @param dt  Delta time in milliseconds (from FS25 engine)
function NPCSystem:update(dt)
    if not self.settings.enabled or not self.isInitialized then
        return
    end

    -- FS25 passes dt in milliseconds - convert to seconds for all timers/movement
    dt = dt / 1000

    self.updateCounter = self.updateCounter + 1

    -- Both server and client need player position for proximity checks / UI
    self:updatePlayerPosition()

    -- Periodically relocate far-away NPCs near the player
    self.relocateTimer = self.relocateTimer + dt
    if self.relocateTimer >= self.RELOCATE_INTERVAL then
        self.relocateTimer = 0
        self:relocateFarNPCs()
    end

    if self.isServer then
        -- SERVER: Full simulation
        self:updateNPCs(dt)                    -- AI states + entity positions
        self.contractorBridge:update(dt)       -- Sync ContractorMod worker positions
        self.scheduler:update(dt)              -- Time tracking + daily events
        self.favorSystem:update(dt)            -- Favor timers + generation
        self.relationshipManager:update(dt)    -- Mood decay + behavior updates
        self.interactionUI:update(dt)          -- Timers + logic only (no rendering)
        if self.favorHUD then
            self.favorHUD:update(dt)           -- HUD edit mode auto-exit checks
        end

        -- Check emergent events once per game hour
        local currentHour = self.scheduler:getCurrentHour()
        if self.eventScheduler and currentHour ~= self.eventScheduler.lastCheckHour then
            self.eventScheduler.lastCheckHour = currentHour
            local weatherFactor = self:getWeatherFactor()
            local currentDay = self.scheduler:getCurrentDay()
            self:updateEventScheduler(currentHour, currentDay, weatherFactor)
        end

        -- Update town reputation every ~10 seconds (not every frame)
        self.reputationTimer = (self.reputationTimer or 0) + dt
        if self.reputationTimer >= 10 then
            self.reputationTimer = 0
            self:updateTownReputation()
        end

        -- NPC vehicle protection: process pending locks + eject player
        self.vehicleCheckTimer = (self.vehicleCheckTimer or 0) + dt
        if self.vehicleCheckTimer >= 2 then  -- check every 2 seconds
            self.vehicleCheckTimer = 0
            self:ejectPlayerFromNPCVehicles()
        end

        -- Periodic auto-save (every 5 real minutes) to prevent data loss on crash
        self.autoSaveTimer = (self.autoSaveTimer or 0) + dt
        if self.autoSaveTimer >= 300 then
            self.autoSaveTimer = 0
            if g_currentMission and g_currentMission.missionInfo and self.isInitialized then
                self:saveToXMLFile(g_currentMission.missionInfo)
            end
        end

        -- Bug 1 fix: orphan vehicle cleanup — remove vehicles whose NPC left DRIVING state
        -- after the async spawn completed (e.g. NPC went to sleep mid-commute).
        self.orphanCheckTimer = (self.orphanCheckTimer or 0) + dt
        if self.orphanCheckTimer >= 15 then
            self.orphanCheckTimer = 0
            for _, npc in ipairs(self.activeNPCs) do
                if npc.realCar and npc.aiState ~= "driving" and not npc.pendingVehicleLoad then
                    if self.settings.debugMode then
                        print(string.format("[NPC Favor] Orphan vehicle cleanup: removing car for %s (state=%s)",
                            npc.name or "?", tostring(npc.aiState)))
                    end
                    self:removeNPCCar(npc)
                end
            end
        end

        -- Bug 4 fix: deferred field assignment for NPCs whose field was nil at init
        -- (g_fieldManager.fields may have been empty when the NPC was first created).
        self.fieldRetryTimer = (self.fieldRetryTimer or 0) + dt
        if self.fieldRetryTimer >= 5 then
            self.fieldRetryTimer = 0
            for _, npc in ipairs(self.activeNPCs) do
                if not npc.assignedField and npc.homePosition then
                    npc.assignedField = self:findNearestField(npc.homePosition.x, npc.homePosition.z, npc.id)
                    -- After 30s without a real field, create a synthetic one so the NPC can work
                    if not npc.assignedField then
                        npc._fieldRetryAge = (npc._fieldRetryAge or 0) + 5
                        if npc._fieldRetryAge >= 30 then
                            local angle = math.random() * math.pi * 2
                            local dist  = math.random(80, 200)
                            npc.assignedField = {
                                id = 0,
                                center = {
                                    x = npc.homePosition.x + math.cos(angle) * dist,
                                    y = npc.homePosition.y,
                                    z = npc.homePosition.z + math.sin(angle) * dist
                                },
                                size = 1,
                                isSynthetic = true
                            }
                            if self.settings.debugMode then
                                print(string.format("[NPC Favor] Synthetic field assigned to %s after field-manager timeout",
                                    npc.name or "?"))
                            end
                        end
                    else
                        npc._fieldRetryAge = nil  -- found a real field; clear the counter
                    end
                end
            end
        end

        -- Process delayed vehicle re-locks (async finalization workaround)
        if self._pendingVehicleLocks then
            for i = #self._pendingVehicleLocks, 1, -1 do
                local entry = self._pendingVehicleLocks[i]
                entry.timer = entry.timer - dt
                if entry.timer <= 0 then
                    if entry.vehicle then
                        -- Re-apply lock directly (don't call lockNPCVehicle to avoid recursion)
                        pcall(function()
                            local v = entry.vehicle
                            if g_currentMission and g_currentMission.vehicleSystem then
                                g_currentMission.vehicleSystem:removeInteractiveVehicle(v)
                            end
                            v.getDistanceToNode = function(self, node)
                                self.interactionFlag = 0
                                return math.huge
                            end
                            v.interact = function(self, player) return end
                        end)
                    end
                    table.remove(self._pendingVehicleLocks, i)
                end
            end
        end

        -- Periodic sync to clients
        self.syncTimer = self.syncTimer + dt
        if self.syncTimer >= self.SYNC_INTERVAL or self.syncDirty then
            self.syncTimer = 0
            self.syncDirty = false
            if NPCStateSyncEvent then
                NPCStateSyncEvent.broadcastState()
            end
        end

        -- Debug info occasionally
        if self.updateCounter % 300 == 0 then
            print(string.format("[NPC Favor] Update #%d - Active NPCs: %d (server)",
                self.updateCounter, self.npcCount))
        end
    else
        -- CLIENT: Display only, state comes from server sync events
        self.interactionUI:update(dt)          -- Timers + logic only (no rendering)
        if self.favorHUD then
            self.favorHUD:update(dt)           -- HUD edit mode auto-exit checks
        end

        -- NPC proximity checks use synced positions
        for _, npc in ipairs(self.activeNPCs) do
            self:checkPlayerProximity(npc)
        end
    end

    -- Settings panel update (cursor + camera freeze while open)
    if self.settingsPanel then
        self.settingsPanel:update()
    end
end

--- Draw loop, called every frame from FSBaseMission.draw.
-- FS25 requires all renderOverlay/renderText calls to happen inside draw callbacks.
-- This method handles all HUD rendering for the NPC system.
function NPCSystem:draw()
    if not self.settings.enabled or not self.isInitialized then
        return
    end

    -- HUD rendering (interaction hints, speech bubbles, name tags)
    if self.interactionUI and self.interactionUI.draw then
        self.interactionUI:draw()
    end

    -- Moveable favor list HUD (replaces old interactionUI:drawFavorList)
    if self.favorHUD and self.favorHUD.draw then
        self.favorHUD:draw()
    end

    -- Custom settings panel (drawn on top of everything)
    if self.settingsPanel then
        self.settingsPanel:draw()
    end
end

function NPCSystem:updatePlayerPosition()
    if not g_currentMission then
        self.playerPositionValid = false
        return
    end

    -- Periodic diagnostic (only when debugMode is on)
    self._playerDiagCounter = (self._playerDiagCounter or 0) + 1
    local shouldLog = self.settings.debugMode and
        ((self._playerDiagCounter <= 3) or (self._playerDiagCounter % 600 == 0))

    -- Method 1: g_localPlayer:getPosition() — proven pattern from FieldServiceKit (UsedPlus)
    if g_localPlayer then
        local x, y, z

        if g_localPlayer.getPosition then
            x, y, z = g_localPlayer:getPosition()
        elseif g_localPlayer.rootNode and g_localPlayer.rootNode ~= 0 then
            local ok
            ok, x, y, z = pcall(getWorldTranslation, g_localPlayer.rootNode)
            if not ok then x = nil end
        end

        if x then
            self.playerPosition.x = x
            self.playerPosition.y = y
            self.playerPosition.z = z
            self.playerPositionValid = true
            if shouldLog then
                print(string.format("[NPC Favor] PlayerPos via g_localPlayer: (%.0f, %.0f, %.0f)", x, y, z))
            end
            return
        end

        -- Player is in vehicle — get vehicle position
        if g_localPlayer.getIsInVehicle and g_localPlayer:getIsInVehicle() then
            local vehicle = g_localPlayer:getCurrentVehicle()
            if vehicle and vehicle.rootNode and vehicle.rootNode ~= 0 then
                local ok
                ok, x, y, z = pcall(getWorldTranslation, vehicle.rootNode)
                if ok and x then
                    self.playerPosition.x = x
                    self.playerPosition.y = y
                    self.playerPosition.z = z
                    self.playerPositionValid = true
                    if shouldLog then
                        print(string.format("[NPC Favor] PlayerPos via g_localPlayer.vehicle: (%.0f, %.0f, %.0f)", x, y, z))
                    end
                    return
                end
            end
        end
    end

    -- Method 2: g_currentMission.player.rootNode
    local player = g_currentMission.player
    if player and player.rootNode and player.rootNode ~= 0 then
        local ok, x, y, z = pcall(getWorldTranslation, player.rootNode)
        if ok and x then
            self.playerPosition.x = x
            self.playerPosition.y = y
            self.playerPosition.z = z
            self.playerPositionValid = true
            if shouldLog then
                print(string.format("[NPC Favor] PlayerPos via mission.player: (%.0f, %.0f, %.0f)", x, y, z))
            end
            return
        end
    end

    -- Method 3: Controlled vehicle
    local vehicle = g_currentMission.controlledVehicle
    if vehicle and vehicle.rootNode and vehicle.rootNode ~= 0 then
        local ok, x, y, z = pcall(getWorldTranslation, vehicle.rootNode)
        if ok and x then
            self.playerPosition.x = x
            self.playerPosition.y = y
            self.playerPosition.z = z
            self.playerPositionValid = true
            if shouldLog then
                print(string.format("[NPC Favor] PlayerPos via controlledVehicle: (%.0f, %.0f, %.0f)", x, y, z))
            end
            return
        end
    end

    -- Method 4: Camera position (last resort)
    if getCamera then
        local ok, cameraNode = pcall(getCamera)
        if ok and cameraNode and cameraNode ~= 0 then
            local ok2, x, y, z = pcall(getWorldTranslation, cameraNode)
            if ok2 and x then
                self.playerPosition.x = x
                self.playerPosition.y = y
                self.playerPosition.z = z
                self.playerPositionValid = true
                if shouldLog then
                    print(string.format("[NPC Favor] PlayerPos via camera: (%.0f, %.0f, %.0f)", x, y, z))
                end
                return
            end
        end
    end

    self.playerPositionValid = false
    if shouldLog then
        print(string.format("[NPC Favor] PlayerPos FAILED! g_localPlayer=%s hasGetPosition=%s rootNode=%s | mission.player=%s | controlledVehicle=%s",
            tostring(g_localPlayer ~= nil),
            tostring(g_localPlayer and g_localPlayer.getPosition ~= nil),
            tostring(g_localPlayer and g_localPlayer.rootNode),
            tostring(player ~= nil),
            tostring(vehicle ~= nil)))
    end
end

function NPCSystem:updateNPCs(dt)
    -- Clear nearby NPCs cache
    self.nearbyNPCs = {}
    
    for _, npc in ipairs(self.activeNPCs) do
        if npc.isActive then
            -- Update AI state
            self.aiSystem:updateNPCState(npc, dt)
            
            -- Update entity position
            self.entityManager:updateNPCEntity(npc, dt)
            
            -- Check for player proximity
            self:checkPlayerProximity(npc)
            
            -- Update timers
            if npc.favorCooldown > 0 then
                npc.favorCooldown = npc.favorCooldown - dt
                if npc.favorCooldown < 0 then
                    npc.favorCooldown = 0
                end
            end
            
            -- Add to nearby list if close enough
            if npc.canInteract then
                table.insert(self.nearbyNPCs, npc)
            end
            
            -- Update last update time
            npc.lastUpdateTime = self:getCurrentGameTime()
        end
    end
end

--- Find buildings/placeables near a world position within a given radius.
-- Filters out fences, deleted objects. Includes all non-fence placeables.
-- @param centerX  World X center position
-- @param centerZ  World Z center position
-- @param radius   Search radius in meters
-- @return table   Array of {x, y, z, distance, name, placeable} sorted by distance
--- Look up a placeable's cached radius from classifiedBuildings.
-- @param placeable  FS25 placeable object
-- @return number|nil  Radius if found, nil otherwise
function NPCSystem:getBuildingRadius(placeable)
    if not self.classifiedBuildings then return nil end
    for _, entries in pairs(self.classifiedBuildings) do
        for _, entry in ipairs(entries) do
            if entry.placeable == placeable then
                return entry.radius
            end
        end
    end
    return nil
end

function NPCSystem:findNearbyBuildings(centerX, centerZ, radius)
    local buildings = {}

    if not g_currentMission or not g_currentMission.placeableSystem then
        return buildings
    end

    local placeables = g_currentMission.placeableSystem.placeables
    if not placeables and g_currentMission.placeableSystem.getPlaceables then
        placeables = g_currentMission.placeableSystem:getPlaceables()
    end

    for _, placeable in pairs(placeables or {}) do
        if not placeable.markedForDeletion and not placeable.isDeleted then
            local typeName = placeable.typeName or ""
            if typeName ~= "newFence" and typeName ~= "fence" then
                if placeable.rootNode then
                    local ok, x, y, z = pcall(getWorldTranslation, placeable.rootNode)
                    if ok and x then
                        local dx = x - centerX
                        local dz = z - centerZ
                        local dist = math.sqrt(dx * dx + dz * dz)
                        if dist <= radius then
                            -- Look up building radius from classified data, or estimate
                            local bRadius = self:getBuildingRadius(placeable) or 5
                            table.insert(buildings, {
                                x = x, y = y, z = z,
                                distance = dist,
                                name = (placeable.getName and placeable:getName()) or "Building",
                                placeable = placeable,
                                radius = bRadius
                            })
                        end
                    end
                end
            end
        end
    end

    table.sort(buildings, function(a, b) return a.distance < b.distance end)
    return buildings
end

--- Relocate only HOMELESS NPCs that are truly lost (no home, no field, drifted far).
-- NPCs with assigned homes or fields live their lives at those locations — they are
-- NOT teleported to follow the player. This creates a realistic spread-out world
-- where you encounter different NPCs as you travel to different parts of the map.
function NPCSystem:relocateFarNPCs()
    if not self.playerPositionValid then return end

    for _, npc in ipairs(self.activeNPCs) do
        if npc.isActive then
            -- Skip NPCs that have a home — they belong where they are
            if npc.homePosition then
                -- If NPC drifted very far from their own home (>400m), send them home
                local hx = npc.homePosition.x - npc.position.x
                local hz = npc.homePosition.z - npc.position.z
                local homeDist = math.sqrt(hx * hx + hz * hz)
                if homeDist > 400 then
                    local newY = npc.homePosition.y or npc.position.y
                    if g_currentMission and g_currentMission.terrainRootNode then
                        local ok, h = pcall(getTerrainHeightAtWorldPos,
                            g_currentMission.terrainRootNode, npc.homePosition.x, 0, npc.homePosition.z)
                        if ok and h then newY = h + 0.05 end
                    end
                    npc.position.x = npc.homePosition.x
                    npc.position.y = newY
                    npc.position.z = npc.homePosition.z
                    self.entityManager:updateNPCEntity(npc, 0)
                    if self.settings.debugMode then
                        print(string.format("[NPC Favor] %s drifted too far, sent home (%.0f, %.0f)",
                            npc.name, npc.position.x, npc.position.z))
                    end
                end
            else
                -- Homeless NPC — only relocate if truly far from player
                local dx = npc.position.x - self.playerPosition.x
                local dz = npc.position.z - self.playerPosition.z
                local distance = math.sqrt(dx * dx + dz * dz)

                if distance > self.RELOCATE_MAX_DISTANCE then
                    -- Place near a random building within range of player
                    local nearbyBuildings = self:findNearbyBuildings(
                        self.playerPosition.x, self.playerPosition.z, self.RELOCATE_MAX_SPAWN)
                    if #nearbyBuildings > 0 then
                        local building = nearbyBuildings[math.random(1, #nearbyBuildings)]
                        local newX, newZ = self:getExteriorPositionNear(
                            building.x, building.z, building, npc.homeBuilding)
                        local newY = building.y
                        if g_currentMission and g_currentMission.terrainRootNode then
                            local ok, h = pcall(getTerrainHeightAtWorldPos,
                                g_currentMission.terrainRootNode, newX, 0, newZ)
                            if ok and h then newY = h + 0.05 end
                        end
                        npc.position.x = newX
                        npc.position.y = newY
                        npc.position.z = newZ
                        self.entityManager:updateNPCEntity(npc, 0)
                        if self.settings.debugMode then
                            print(string.format("[NPC Favor] Relocated homeless %s near %s (%.0f, %.0f)",
                                npc.name, building.name or "?", newX, newZ))
                        end
                    end
                end
            end
        end
    end
end

function NPCSystem:checkPlayerProximity(npc)
    if not self.playerPositionValid then
        npc.canInteract = false
        return
    end

    -- Sleeping NPCs cannot be interacted with (they're inside their house)
    if npc.isSleeping then
        npc.canInteract = false
        if self.interactionUI and self.interactionUI.interactionHintNPC == npc then
            self.interactionUI:hideInteractionHint()
        end
        return
    end

    local dx = npc.position.x - self.playerPosition.x
    local dz = npc.position.z - self.playerPosition.z
    local distance = math.sqrt(dx * dx + dz * dz)

    -- Show interaction hint when player is close
    if distance < 5 then
        npc.canInteract = true
        npc.interactionDistance = distance

        -- Show world-space "Press [E] to talk" hint above NPC head
        if self.interactionUI then
            self.interactionUI:showInteractionHint(npc, distance)
        end
    else
        npc.canInteract = false

        -- Hide hint if this NPC was the one being shown
        if self.interactionUI and self.interactionUI.interactionHintNPC == npc then
            self.interactionUI:hideInteractionHint()
        end
    end
end

function NPCSystem:getCurrentGameTime()
    -- SAFE time getter
    if g_currentMission and g_currentMission.time then
        return g_currentMission.time
    end
    return 0
end

function NPCSystem:showNotification(title, message)
    if not self.settings.showNotifications then
        return
    end

    -- Route to HUD flash instead of game's messageCenter
    if self.favorHUD then
        self.favorHUD:flashFavor(message, {1, 0.9, 0.3, 1})
    end

    if self.settings.debugMode then
        print(string.format("[NPC Favor] %s: %s", title, message))
    end
end

function NPCSystem:consoleCommandStatus()
    local gameTime = self:getCurrentGameTime()
    local status = "=== NPC Favor System Status ===\n"
    status = status .. string.format("Enabled: %s | Initialized: %s | Debug: %s\n",
        tostring(self.settings.enabled), tostring(self.isInitialized), tostring(self.settings.debugMode))
    status = status .. string.format("Active NPCs: %d/%d | Nearby: %d | Updates: %d\n",
        self.npcCount, self.settings.maxNPCs, #self.nearbyNPCs, self.updateCounter)

    -- Player position
    if self.playerPositionValid then
        status = status .. string.format("Player: (%.0f, %.0f, %.0f)\n",
            self.playerPosition.x, self.playerPosition.y, self.playerPosition.z)
    else
        status = status .. "Player: position unknown\n"
    end

    -- Game time info
    if g_currentMission and g_currentMission.environment then
        local env = g_currentMission.environment
        local dayTime = env.dayTime or 0
        local hours = math.floor(dayTime / 3600000)
        local minutes = math.floor((dayTime % 3600000) / 60000)
        status = status .. string.format("Game Time: %02d:%02d | Day: %s\n",
            hours, minutes, tostring(env.currentDay or "?"))
    end

    -- Town reputation
    local repLabel = self:getReputationLabel(self.townReputation)
    status = status .. string.format("Town Reputation: %s (%d/100)\n", repLabel, self.townReputation)

    -- Subsystem health
    status = status .. string.format("Subsystems: Entity=%s AI=%s Sched=%s Rel=%s Favor=%s UI=%s\n",
        tostring(self.entityManager ~= nil), tostring(self.aiSystem ~= nil),
        tostring(self.scheduler ~= nil), tostring(self.relationshipManager ~= nil),
        tostring(self.favorSystem ~= nil), tostring(self.interactionUI ~= nil))

    -- Settings snapshot
    status = status .. string.format("Settings: names=%s notif=%s favors=%s\n",
        tostring(self.settings.showNames), tostring(self.settings.showNotifications),
        tostring(self.settings.enableFavors))

    -- Per-NPC detail
    status = status .. "\n--- NPCs ---\n"
    for i, npc in ipairs(self.activeNPCs) do
        if npc.isActive then
            -- Distance from player
            local dist = "?"
            if self.playerPositionValid then
                local dx = npc.position.x - self.playerPosition.x
                local dz = npc.position.z - self.playerPosition.z
                dist = string.format("%.0f", math.sqrt(dx * dx + dz * dz))
            end

            -- Time since last update
            local age = "never"
            if npc.lastUpdateTime and npc.lastUpdateTime > 0 and gameTime > 0 then
                local ms = gameTime - npc.lastUpdateTime
                if ms < 2000 then
                    age = "LIVE"
                else
                    age = string.format("%.1fs ago", ms / 1000)
                end
            end

            status = status .. string.format(
                "%d. %s [%s] role=%s | pos=(%.0f,%.0f,%.0f) | dist=%sm | action=%s | ai=%s | rel=%d | upd=%s\n",
                i, npc.name, npc.personality, npc.role or "farmer",
                npc.position.x, npc.position.y, npc.position.z,
                dist, npc.currentAction or "?", npc.aiState or "?",
                npc.relationship or 0, age)

            -- Show favor stats if any activity
            if (npc.totalFavorsCompleted or 0) > 0 or (npc.totalFavorsFailed or 0) > 0 then
                status = status .. string.format("   Favors: %d done / %d failed | cooldown=%.0f\n",
                    npc.totalFavorsCompleted or 0, npc.totalFavorsFailed or 0, npc.favorCooldown or 0)
            end
        end
    end

    -- Farmland summary section
    status = status .. "\n--- Farmland Summary ---\n"
    local totalFarmlandsAssigned = 0
    local farmerCount = 0
    for _, npc in ipairs(self.activeNPCs) do
        if npc.isActive then
            local isFarmer = (npc.role == "farmer" or npc.role == "farmhand")
            if isFarmer then
                farmerCount = farmerCount + 1
            end
            if npc.assignedFarmland then
                totalFarmlandsAssigned = totalFarmlandsAssigned + 1
                local numFields = npc.assignedFields and #npc.assignedFields or 0
                status = status .. string.format("  %s (%s): farmland=#%d '%s' | %d fields\n",
                    npc.name or "?",
                    npc.farmName or "?",
                    npc.assignedFarmland.farmlandId or 0,
                    npc.assignedFarmland.name or "?",
                    numFields)
            end
        end
    end
    status = status .. string.format("Total: %d farmlands assigned to %d farmer NPCs\n",
        totalFarmlandsAssigned, farmerCount)

    return status
end

function NPCSystem:consoleCommandSpawn(name)
    if not self.isInitialized then
        return "NPC System not initialized. Try 'npcReset' first."
    end
    
    if self.npcCount >= self.settings.maxNPCs then
        return string.format("Cannot spawn NPC: maximum NPC limit reached (%d/%d)", 
            self.npcCount, self.settings.maxNPCs)
    end
    
    -- Find position near player
    local location = nil
    if self.playerPositionValid then
        local angle = math.random() * math.pi * 2
        local distance = 20 + math.random(0, 30)

        location = {
            x = self.playerPosition.x + math.cos(angle) * distance,
            y = self.playerPosition.y,
            z = self.playerPosition.z + math.sin(angle) * distance
        }
    else
        location = {x = 0, y = 0, z = 0}
    end

    local npc = self:createNPCAtLocation(location)
    if npc then
        -- Override name only if user specified one; otherwise keep the gendered name
        if name and name ~= "" then
            npc.name = name
        end
        name = npc.name
        
        -- Initialize NPC data
        self:initializeNPCData(npc, location, #self.activeNPCs + 1)
        
        table.insert(self.activeNPCs, npc)
        self.npcCount = self.npcCount + 1
        
        return string.format("NPC '%s' spawned at (%.1f, %.1f, %.1f)", 
            name, location.x, location.y, location.z)
    end
    
    return "Failed to spawn NPC"
end

--- Convert world coordinates to map display coordinates.
-- FS25 world origin is at terrain center; map HUD shows coords from corner.
-- @param worldX  World X coordinate
-- @param worldZ  World Z coordinate
-- @return mapX, mapZ  Map display coordinates
function NPCSystem:worldToMap(worldX, worldZ)
    local halfSize = (g_currentMission and g_currentMission.terrainSize or 2048) / 2
    return worldX + halfSize, worldZ + halfSize
end

function NPCSystem:consoleCommandList()
    if self.npcCount == 0 then
        return "No active NPCs. System initialized: " .. tostring(self.isInitialized)
    end

    local gameTime = self:getCurrentGameTime()
    local terrainSize = g_currentMission and g_currentMission.terrainSize or 2048
    local list = string.format("=== Active NPCs (%d/%d) | Updates: %d | Terrain: %d ===\n",
        self.npcCount, self.settings.maxNPCs, self.updateCounter, terrainSize)
    list = list .. string.format("%-4s %-18s %-10s %-8s %5s %3s %-15s %-15s %s\n",
        "#", "Name", "Role", "Action", "Dist", "Rel", "Map Pos (X,Z)", "Map Home (X,Z)", "Building")
    list = list .. string.rep("-", 110) .. "\n"

    for i, npc in ipairs(self.activeNPCs) do
        if npc.isActive then
            -- Distance from player
            local dist = "  -"
            if self.playerPositionValid then
                local dx = npc.position.x - self.playerPosition.x
                local dz = npc.position.z - self.playerPosition.z
                dist = string.format("%4.0f", math.sqrt(dx * dx + dz * dz))
            end

            -- Map display coordinates (offset from world coords)
            local mx, mz = self:worldToMap(npc.position.x, npc.position.z)
            local pos = string.format("(%d, %d)", math.floor(mx), math.floor(mz))
            local homePos = "  -"
            if npc.homePosition then
                local hx, hz = self:worldToMap(npc.homePosition.x, npc.homePosition.z)
                homePos = string.format("(%d, %d)", math.floor(hx), math.floor(hz))
            end

            list = list .. string.format("%-4d %-18s %-10s %-8s %4sm %3d %-15s %-15s %s\n",
                i,
                (npc.name or "?"):sub(1, 18),
                (npc.role or "farmer"):sub(1, 10),
                (npc.currentAction or "?"):sub(1, 8),
                dist,
                npc.relationship or 0,
                pos,
                homePos,
                (npc.homeBuildingName or "?"):sub(1, 20))
        end
    end

    -- Debug footer (only shown when debugMode is on)
    if self.settings and self.settings.debugMode then
        list = list .. "\n--- Debug Details ---\n"
        for i, npc in ipairs(self.activeNPCs) do
            if npc.isActive then
                local mx, mz = self:worldToMap(npc.position.x, npc.position.z)
                local parts = {string.format("  %d. %s @ map(%d, %d)", i, npc.name, math.floor(mx), math.floor(mz))}
                if npc.farmName then table.insert(parts, "farm=" .. npc.farmName) end
                if npc.assignedFarmland then table.insert(parts, string.format("farmland=#%d", npc.assignedFarmland.farmlandId or 0)) end
                if npc.assignedField then table.insert(parts, string.format("field=#%d", npc.assignedField.id or 0)) end
                local numFields = npc.assignedFields and #npc.assignedFields or 0
                if numFields > 0 then table.insert(parts, string.format("fields=%d", numFields)) end
                if npc.ownerFarmId and npc.ownerFarmId > 0 then table.insert(parts, string.format("farm#%d", npc.ownerFarmId)) end
                if npc.homeToFieldDistance then table.insert(parts, string.format("fieldDist=%.0fm", npc.homeToFieldDistance)) end
                list = list .. table.concat(parts, "  ") .. "\n"
            end
        end
    end

    return list
end

function NPCSystem:consoleCommandReset()
    print("NPC Favor: Resetting NPC system...")

    -- Remove all NPCs
    self:clearAllNPCs()
    
    -- Reset state
    self.isInitialized = false
    self.initializing = false
    self.initDone = false
    self.delayedInitAttempts = 0
    self.npcCount = 0
    
    -- Try to reinitialize
    self:onMissionLoaded()

    return "NPC system reset and reinitializing..."
end

--- Clear any NPC references to a vehicle about to be deleted, so the AI never
-- touches a deleted object. Stops an active AI job for that NPC as well.
-- @param vehicle  The vehicle being removed
function NPCSystem:clearNPCVehicleReferences(vehicle)
    if not vehicle then return end
    for _, npc in ipairs(self.activeNPCs) do
        local matches = (npc.realTractor == vehicle)
            or (npc.realImplement == vehicle)
            or (npc.realCar == vehicle)
            or (npc.currentVehicle == vehicle)
        if matches then
            if npc.activeAIJob then
                pcall(function() g_currentMission.aiSystem:stopJob(npc.activeAIJob) end)
                npc.activeAIJob = nil
            end
            if npc.realTractor == vehicle then npc.realTractor = nil end
            if npc.realImplement == vehicle then npc.realImplement = nil end
            if npc.realCar == vehicle then npc.realCar = nil end
            if npc.currentVehicle == vehicle then npc.currentVehicle = nil end
            npc.isSeatedInVehicle = false
        end
    end
end

--- Console: delete the nearest vehicle (and its whole attached combo) to the
-- player. Cleanup tool for stranded NPC tractors/implements. Server/SP only.
-- Never deletes the vehicle the player is currently inside.
-- @param radiusArg  optional search radius in metres (default 30, clamped 1-200)
function NPCSystem:consoleCommandDeleteNearestVehicle(radiusArg)
    if g_currentMission == nil then
        return "Not in a game"
    end
    if g_currentMission.getIsServer and not g_currentMission:getIsServer() then
        return "npcDeleteVehicle only works on the host / single player"
    end

    local vehicleSystem = g_currentMission.vehicleSystem
    if vehicleSystem == nil or vehicleSystem.vehicles == nil then
        return "Vehicle system unavailable"
    end

    -- Refresh and read the player's current position
    pcall(function() self:updatePlayerPosition() end)
    if not self.playerPositionValid then
        return "Could not determine player position"
    end
    local px, pz = self.playerPosition.x, self.playerPosition.z

    local radius = tonumber(radiusArg) or 30
    radius = math.max(1, math.min(200, radius))

    -- The vehicle the player is currently controlling — never delete it
    local controlled = nil
    if g_localPlayer and g_localPlayer.getCurrentVehicle then
        pcall(function() controlled = g_localPlayer:getCurrentVehicle() end)
    end
    if controlled == nil then
        controlled = g_currentMission.controlledVehicle
    end
    local controlledRoot = controlled and (controlled.rootVehicle or controlled) or nil

    -- Find the nearest vehicle within radius (by root node distance)
    local nearest, nearestDist = nil, radius + 1
    for _, vehicle in ipairs(vehicleSystem.vehicles) do
        if vehicle ~= nil and vehicle.rootNode ~= nil and vehicle.rootNode ~= 0 then
            local root = vehicle.rootVehicle or vehicle
            if root ~= controlledRoot then
                local ok, vx, _, vz = pcall(getWorldTranslation, vehicle.rootNode)
                if ok and vx then
                    local dist = math.sqrt((px - vx) ^ 2 + (pz - vz) ^ 2)
                    if dist <= radius and dist < nearestDist then
                        nearestDist = dist
                        nearest = vehicle
                    end
                end
            end
        end
    end

    if nearest == nil then
        return string.format("No vehicle found within %.0fm of you", radius)
    end

    -- Collect the whole combo the nearest vehicle belongs to
    local root = nearest.rootVehicle or nearest
    local combo = {}
    if type(root.childVehicles) == "table" and #root.childVehicles > 0 then
        for _, v in ipairs(root.childVehicles) do
            table.insert(combo, v)
        end
    else
        table.insert(combo, root)
    end

    -- Friendly name for feedback (grab before deletion)
    local name = "vehicle"
    pcall(function()
        if root.getName then name = root:getName() or name end
    end)

    -- Drop any NPC references so the AI won't touch the deleted objects
    for _, v in ipairs(combo) do
        self:clearNPCVehicleReferences(v)
    end

    -- Delete children first, then the root (Vehicle:delete stops the AI job too)
    local removed = 0
    for _, v in ipairs(combo) do
        if v ~= root then
            local ok = pcall(function() if v.delete then v:delete() end end)
            if ok then removed = removed + 1 end
        end
    end
    local okRoot = pcall(function() if root.delete then root:delete() end end)
    if okRoot then removed = removed + 1 end

    return string.format("Deleted '%s' (%d part%s) %.0fm away",
        tostring(name), removed, removed == 1 and "" or "s", nearestDist)
end

function NPCSystem:clearAllNPCs()
    for _, npc in ipairs(self.activeNPCs) do
        -- Remove real vehicles before entity cleanup
        if npc.realTractor then
            self:removeNPCTractor(npc)
        end
        if npc.realCar then
            self:removeNPCCar(npc)
        end
        self.entityManager:removeNPCEntity(npc)
    end

    self.activeNPCs = {}
    self.npcCount = 0
    self.nearbyNPCs = {}
end

-- =========================================================
-- Multiplayer: Sync Data Collection + Application
-- =========================================================

--[[
    Collect current NPC state for network sync (server only).
    @return array of NPC data tables
]]
function NPCSystem:collectSyncData()
    local data = {}
    for _, npc in ipairs(self.activeNPCs) do
        if npc.isActive then
            table.insert(data, {
                id = npc.id,
                name = npc.name or "",
                personality = npc.personality or "",
                x = npc.position.x or 0,
                y = npc.position.y or 0,
                z = npc.position.z or 0,
                aiState = npc.aiState or "idle",
                relationship = npc.relationship or 50,
                isActive = npc.isActive,
                currentAction = npc.currentAction or "idle"
            })
        end
    end
    return data
end

--[[
    Apply NPC state received from server (client only).
    Updates existing NPCs or creates placeholders for new ones.
    Removes NPCs not present in sync data.
    @param npcDataArray - Array of NPC data from NPCStateSyncEvent
]]
function NPCSystem:applyNetworkState(npcDataArray)
    if not npcDataArray then return end

    -- Build lookup of received NPC IDs
    local receivedIds = {}
    for _, entry in ipairs(npcDataArray) do
        receivedIds[entry.id] = true

        -- Find existing NPC or create placeholder
        local npc = self:getNPCById(entry.id)
        if npc then
            -- Update existing NPC
            npc.position.x = entry.x
            npc.position.y = entry.y
            npc.position.z = entry.z
            npc.aiState = entry.aiState
            npc.currentAction = entry.currentAction
            npc.relationship = entry.relationship
            npc.isActive = entry.isActive
        else
            -- Create placeholder NPC (client doesn't run full init)
            local newNPC = {
                id = entry.id,
                name = entry.name,
                personality = entry.personality,
                position = { x = entry.x, y = entry.y, z = entry.z },
                rotation = { x = 0, y = 0, z = 0 },
                isActive = entry.isActive,
                currentAction = entry.currentAction,
                aiState = entry.aiState,
                relationship = entry.relationship,
                favorCooldown = 0,
                canInteract = false,
                interactionDistance = 999,
                homePosition = { x = entry.x, y = entry.y, z = entry.z },
                movementSpeed = 1.0,
                totalFavorsCompleted = 0,
                totalFavorsFailed = 0,
                lastUpdateTime = 0,
                entityId = nil
            }
            table.insert(self.activeNPCs, newNPC)
            self.npcCount = self.npcCount + 1
        end
    end

    -- Remove NPCs not in sync data (they were removed on server)
    local i = 1
    while i <= #self.activeNPCs do
        local npc = self.activeNPCs[i]
        if not receivedIds[npc.id] then
            self.entityManager:removeNPCEntity(npc)
            table.remove(self.activeNPCs, i)
            self.npcCount = self.npcCount - 1
        else
            i = i + 1
        end
    end
end

--[[
    Find an NPC by their integer ID.
    @param id - NPC ID
    @return NPC table or nil
]]
function NPCSystem:getNPCById(id)
    for _, npc in ipairs(self.activeNPCs) do
        if npc.id == id then
            return npc
        end
    end
    return nil
end

-- =========================================================
-- Multiplayer: Server-Side Interaction Handlers
-- Called from NPCInteractionEvent.execute() after validation
-- =========================================================

function NPCSystem:serverAcceptFavor(npc, farmId)
    -- Rate limiting: check cooldown
    if npc.favorCooldown > 0 then
        if self.settings.debugMode then
            print(string.format("[NPC Favor] Favor accept blocked: %s has cooldown %.0f", npc.name, npc.favorCooldown))
        end
        return false
    end

    -- Delegate to favor system
    if self.favorSystem and self.favorSystem.acceptFavor then
        local success = self.favorSystem:acceptFavor(npc.id, farmId)
        if success then
            self.syncDirty = true
        end
        return success
    end
    return false
end

function NPCSystem:serverCompleteFavor(npc, farmId)
    if self.favorSystem and self.favorSystem.completeFavor then
        local success = self.favorSystem:completeFavor(npc.id, farmId)
        if success then
            -- Update relationship on favor completion
            self.relationshipManager:updateRelationship(npc.id, 15, "FAVOR_COMPLETED")
            self.syncDirty = true
        end
        return success
    end
    return false
end

function NPCSystem:serverAbandonFavor(npc, farmId)
    if self.favorSystem and self.favorSystem.abandonFavor then
        local success = self.favorSystem:abandonFavor(npc.id, farmId)
        if success then
            -- Negative relationship impact
            self.relationshipManager:updateRelationship(npc.id, -5, "FAVOR_ABANDONED")
            self.syncDirty = true
        end
        return success
    end
    return false
end

function NPCSystem:serverGiveGift(npc, farmId, giftValue, giftType)
    if self.relationshipManager and self.relationshipManager.giveGiftToNPC then
        local success = self.relationshipManager:giveGiftToNPC(npc.id, giftType or "money", giftValue)
        if success then
            self.syncDirty = true
        end
        return success
    end
    return false
end

function NPCSystem:serverUpdateRelationship(npc, farmId, change, reason)
    if self.relationshipManager then
        local success = self.relationshipManager:updateRelationship(npc.id, change, reason or "DAILY_INTERACTION")
        if success then
            self.syncDirty = true
        end
        return success
    end
    return false
end

-- =========================================================
-- Town Reputation & NPC Memory
-- =========================================================

--- Update town reputation as weighted average of all NPC relationships.
-- NPCs with more interactions (encounters) contribute more to the score.
-- Called periodically from update loop.
function NPCSystem:updateTownReputation()
    local ok, err = pcall(function()
        if not self.activeNPCs or #self.activeNPCs == 0 then
            return
        end

        local weightedSum = 0
        local totalWeight = 0

        for _, npc in ipairs(self.activeNPCs) do
            if npc.isActive then
                -- Weight by interaction frequency: more encounters = more influence
                local encounterCount = npc.encounters and #npc.encounters or 0
                local weight = 1 + encounterCount  -- minimum weight of 1
                weightedSum = weightedSum + (npc.relationship or 50) * weight
                totalWeight = totalWeight + weight
            end
        end

        if totalWeight > 0 then
            self.townReputation = math.floor(weightedSum / totalWeight + 0.5)
            self.townReputation = math.max(0, math.min(100, self.townReputation))
        end
    end)

    if not ok and self.settings.debugMode then
        print("[NPC Favor] updateTownReputation error: " .. tostring(err))
    end
end

--- Get the reputation label for a given reputation value.
-- @param reputation  Reputation value (0-100)
-- @return string     Label: "Outcast", "Disliked", "Neutral", "Respected", or "Beloved"
function NPCSystem:getReputationLabel(reputation)
    if reputation <= 20 then
        return "Outcast"
    elseif reputation <= 40 then
        return "Disliked"
    elseif reputation <= 60 then
        return "Neutral"
    elseif reputation <= 80 then
        return "Respected"
    else
        return "Beloved"
    end
end

--- Record an encounter with an NPC (max 5 recent entries, newest first).
-- @param npc            NPC data table
-- @param encounterType  String: "talked", "favor_completed", "favor_failed", "gift_given", "helped"
-- @param details        Optional string with extra context
function NPCSystem:recordEncounter(npc, encounterType, details, partnerName, sentiment)
    if not npc then return end

    local ok, err = pcall(function()
        npc.encounters = npc.encounters or {}

        local gameTime = self:getCurrentGameTime()
        local entry = {
            type = encounterType or "talked",
            time = gameTime,
            details = details or "",
            partner = partnerName or nil,      -- who was involved
            sentiment = sentiment or "neutral", -- positive/neutral/negative
        }

        -- Insert at front (newest first)
        table.insert(npc.encounters, 1, entry)

        -- Trim to max 10 entries (expanded from 5)
        while #npc.encounters > 10 do
            table.remove(npc.encounters)
        end

        if self.settings.debugMode then
            print(string.format("[NPC Favor] Recorded encounter: %s with %s (%s, %s)",
                encounterType, npc.name or "?", details or "", sentiment or "neutral"))
        end
    end)

    if not ok and self.settings.debugMode then
        print("[NPC Favor] recordEncounter error: " .. tostring(err))
    end
end

-- =========================================================
-- Save/Load Persistence
-- =========================================================
-- File: savegameX/npc_favor.xml
-- Saves: NPC positions, relationships, favor stats, unique IDs, encounters
-- Follows UsedPlus pattern: XMLFile.create/loadIfExists

local NPC_SAVE_FILE = "npc_favor.xml"
local NPC_SAVE_ROOT = "npcFavor"
local SAVE_SCHEMA_VERSION = "1.2.4"

local function schemaVersionLessThan(a, b)
    local function parts(v)
        local t = {}
        for n in v:gmatch("%d+") do t[#t+1] = tonumber(n) end
        while #t < 3 do t[#t+1] = 0 end
        return t
    end
    local pa, pb = parts(a), parts(b)
    for i = 1, 3 do
        if pa[i] ~= pb[i] then return pa[i] < pb[i] end
    end
    return false
end

--- Save all NPC state to XML file in savegame directory.
-- Called from FSCareerMissionInfo.saveToXMLFile hook in main.lua.
-- @param missionInfo  FS25 missionInfo table (has savegameDirectory)
function NPCSystem:saveToXMLFile(missionInfo)
    -- Safeguard: restore any temporary field-ownership flips BEFORE saving so a
    -- borrowed farmland can never persist to disk (see startNPCFieldWorkOwned).
    pcall(function() self:restoreAllOwnershipFlips() end)

    local ok, err = pcall(function()
        self:_doSaveToXMLFile(missionInfo)
    end)
    if not ok then
        print(string.format("[NPC Favor] Save error (non-fatal): %s", tostring(err)))
    end
end

function NPCSystem:_doSaveToXMLFile(missionInfo)
    local savegameDirectory = missionInfo and missionInfo.savegameDirectory
    if not savegameDirectory then
        return
    end

    if not self.isInitialized or self.npcCount == 0 then
        return
    end

    local filePath = savegameDirectory .. "/" .. NPC_SAVE_FILE

    -- XMLFile.create overwrites existing file
    local xmlFile = XMLFile.create("npcFavorXML", filePath, NPC_SAVE_ROOT)
    if xmlFile == nil then
        print("[NPC Favor] ERROR: Failed to create save file: " .. filePath)
        return
    end

    xmlFile:setString(NPC_SAVE_ROOT .. "#version", SAVE_SCHEMA_VERSION)
    xmlFile:setInt(NPC_SAVE_ROOT .. "#npcCount", self.npcCount)

    -- Save each NPC
    local npcIndex = 0
    for _, npc in ipairs(self.activeNPCs) do
        if npc.isActive then
            local npcKey = string.format(NPC_SAVE_ROOT .. ".npcs.npc(%d)", npcIndex)

            -- Identity
            xmlFile:setString(npcKey .. "#uniqueId", npc.uniqueId or "")
            xmlFile:setString(npcKey .. "#name", npc.name or "")
            xmlFile:setString(npcKey .. "#personality", npc.personality or "")
            xmlFile:setInt(npcKey .. "#age", npc.age or 30)

            -- Position
            xmlFile:setFloat(npcKey .. ".position#x", npc.position.x or 0)
            xmlFile:setFloat(npcKey .. ".position#y", npc.position.y or 0)
            xmlFile:setFloat(npcKey .. ".position#z", npc.position.z or 0)
            xmlFile:setFloat(npcKey .. ".rotation#y", npc.rotation.y or 0)

            -- Home position
            if npc.homePosition then
                xmlFile:setFloat(npcKey .. ".home#x", npc.homePosition.x or 0)
                xmlFile:setFloat(npcKey .. ".home#y", npc.homePosition.y or 0)
                xmlFile:setFloat(npcKey .. ".home#z", npc.homePosition.z or 0)
            end
            xmlFile:setString(npcKey .. ".home#buildingName", npc.homeBuildingName or "")

            -- Relationship & stats
            xmlFile:setInt(npcKey .. ".stats#relationship", npc.relationship or 50)
            xmlFile:setInt(npcKey .. ".stats#favorsCompleted", npc.totalFavorsCompleted or 0)
            xmlFile:setInt(npcKey .. ".stats#favorsFailed", npc.totalFavorsFailed or 0)
            xmlFile:setFloat(npcKey .. ".stats#favorCooldown", npc.favorCooldown or 0)

            -- AI state
            xmlFile:setString(npcKey .. ".ai#state", npc.aiState or "idle")
            xmlFile:setString(npcKey .. ".ai#action", npc.currentAction or "idle")

            -- Personality modifiers
            if npc.aiPersonalityModifiers then
                xmlFile:setFloat(npcKey .. ".personality#workEthic", npc.aiPersonalityModifiers.workEthic or 1.0)
                xmlFile:setFloat(npcKey .. ".personality#sociability", npc.aiPersonalityModifiers.sociability or 1.0)
                xmlFile:setFloat(npcKey .. ".personality#generosity", npc.aiPersonalityModifiers.generosity or 1.0)
                xmlFile:setFloat(npcKey .. ".personality#punctuality", npc.aiPersonalityModifiers.punctuality or 1.0)
            end

            -- Visual
            xmlFile:setInt(npcKey .. ".visual#appearanceSeed", npc.appearanceSeed or 1)
            xmlFile:setBool(npcKey .. ".visual#isFemale", npc.isFemale or false)
            xmlFile:setFloat(npcKey .. ".visual#movementSpeed", npc.movementSpeed or 1.0)

            -- Needs system
            if npc.needs then
                xmlFile:setFloat(npcKey .. ".needs#energy", npc.needs.energy or 20)
                xmlFile:setFloat(npcKey .. ".needs#social", npc.needs.social or 30)
                xmlFile:setFloat(npcKey .. ".needs#hunger", npc.needs.hunger or 10)
                xmlFile:setFloat(npcKey .. ".needs#workSatisfaction", npc.needs.workSatisfaction or 50)
            end
            xmlFile:setString(npcKey .. ".needs#mood", npc.mood or "neutral")

            -- Encounters (up to 10 recent, with sentiment + partner)
            if npc.encounters and #npc.encounters > 0 then
                for ei, encounter in ipairs(npc.encounters) do
                    if ei > 10 then break end
                    local eKey = string.format("%s.encounters.encounter(%d)", npcKey, ei - 1)
                    xmlFile:setString(eKey .. "#type", encounter.type or "")
                    xmlFile:setFloat(eKey .. "#time", encounter.time or 0)
                    xmlFile:setString(eKey .. "#details", encounter.details or "")
                    xmlFile:setString(eKey .. "#partner", encounter.partner or "")
                    xmlFile:setString(eKey .. "#sentiment", encounter.sentiment or "neutral")
                end
            end

            npcIndex = npcIndex + 1
        end
    end

    -- Save active favors from the favor system
    if self.favorSystem then
        local activeFavors = self.favorSystem:getActiveFavors()
        if activeFavors then
            local favorIndex = 0
            for _, favor in ipairs(activeFavors) do
                local favorKey = string.format(NPC_SAVE_ROOT .. ".favors.favor(%d)", favorIndex)
                xmlFile:setInt(favorKey .. "#npcId", favor.npcId or 0)
                xmlFile:setString(favorKey .. "#npcName", favor.npcName or "")
                xmlFile:setString(favorKey .. "#type", favor.type or "")
                xmlFile:setString(favorKey .. "#description", favor.description or "")
                xmlFile:setFloat(favorKey .. "#timeRemaining", favor.timeRemaining or 0)
                xmlFile:setInt(favorKey .. "#progress", favor.progress or 0)
                xmlFile:setBool(favorKey .. "#awaitingConfirmation", favor.awaitingConfirmation or false)
                if favor.taskData then
                    xmlFile:setBool(favorKey .. "#loanAmountDeducted", favor.taskData.loanAmountDeducted or false)
                    if favor.taskData.loanAmount then
                        xmlFile:setFloat(favorKey .. "#loanAmount", favor.taskData.loanAmount)
                    end
                end
                if type(favor.reward) == "table" then
                    xmlFile:setFloat(favorKey .. "#rewardRelationship", favor.reward.relationship or 0)
                    xmlFile:setFloat(favorKey .. "#rewardMoney", favor.reward.money or 0)
                    xmlFile:setFloat(favorKey .. "#rewardXp", favor.reward.xp or 0)
                else
                    xmlFile:setFloat(favorKey .. "#rewardMoney", tonumber(favor.reward) or 0)
                end
                favorIndex = favorIndex + 1
            end
        end
    end

    -- Save NPC-NPC relationships
    if self.relationshipManager and self.relationshipManager.npcRelationships then
        local relIndex = 0
        for key, rel in pairs(self.relationshipManager.npcRelationships) do
            local relKey = string.format(NPC_SAVE_ROOT .. ".npcRelationships.rel(%d)", relIndex)
            xmlFile:setString(relKey .. "#key", key)
            xmlFile:setFloat(relKey .. "#value", rel.value or 50)
            xmlFile:setFloat(relKey .. "#lastInteraction", rel.lastInteraction or 0)
            xmlFile:setInt(relKey .. "#interactionCount", rel.interactionCount or 0)
            relIndex = relIndex + 1
        end
    end

    xmlFile:save()
    xmlFile:delete()

    -- Save settings to the same directory (tempsavegame during game save)
    if self.settings and self.settings.saveToXMLFile then
        local ok, settingsErr = pcall(function()
            self.settings:saveToXMLFile(missionInfo)
        end)
        if not ok then
            print(string.format("[NPC Favor] Settings save error (non-fatal): %s", tostring(settingsErr)))
        end
    end

    if self.settings.debugMode then
        print(string.format("[NPC Favor] Saved %d NPCs to %s", npcIndex, filePath))
    end
end

function NPCSystem:migrateSaveData(xmlFile, fromVersion)
    if not schemaVersionLessThan(fromVersion, SAVE_SCHEMA_VERSION) then
        return
    end

    print(string.format("[NPC Favor] Migrating save from v%s to v%s", fromVersion, SAVE_SCHEMA_VERSION))

    if fromVersion == "0.0.0.0" then
        print("[NPC Favor] Legacy save detected (pre-versioned)")
        self.legacySaveLoaded = true
    end

    if schemaVersionLessThan(fromVersion, "1.2.0") then
        -- Future: backfill personality field if missing
    end
end

--- Load saved NPC state from XML file, restoring relationships and positions.
-- Called after initializeNPCs() in the delayed init updater.
-- Matches saved NPCs to spawned NPCs by uniqueId or name.
-- @param missionInfo  FS25 missionInfo table (has savegameDirectory)
function NPCSystem:loadFromXMLFile(missionInfo)
    local savegameDirectory = missionInfo and missionInfo.savegameDirectory
    if not savegameDirectory then
        return
    end

    local filePath = savegameDirectory .. "/" .. NPC_SAVE_FILE

    -- loadIfExists returns nil for new games (no save file yet)
    local xmlFile = XMLFile.loadIfExists("npcFavorXML", filePath, NPC_SAVE_ROOT)
    if xmlFile == nil then
        if self.settings.debugMode then
            print("[NPC Favor] No save file found (new game)")
        end
        return
    end

    local savedVersion = xmlFile:getString(NPC_SAVE_ROOT .. "#version", "0.0.0.0")
    local savedNpcCount = xmlFile:getInt(NPC_SAVE_ROOT .. "#npcCount", 0)

    if self.settings.debugMode then
        print(string.format("[NPC Favor] Loading save file v%s with %d NPCs", savedVersion, savedNpcCount))
    end

    if schemaVersionLessThan(savedVersion, SAVE_SCHEMA_VERSION) then
        self:migrateSaveData(xmlFile, savedVersion)
    end

    -- Build lookup tables for matching saved NPCs to spawned ones
    local npcByUniqueId = {}
    local npcByName = {}
    for _, npc in ipairs(self.activeNPCs) do
        if npc.uniqueId then
            npcByUniqueId[npc.uniqueId] = npc
        end
        if npc.name then
            npcByName[npc.name] = npc
        end
    end

    local restoredCount = 0

    -- Iterate saved NPCs and restore state
    xmlFile:iterate(NPC_SAVE_ROOT .. ".npcs.npc", function(_, npcKey)
        local uniqueId = xmlFile:getString(npcKey .. "#uniqueId", "")
        local name = xmlFile:getString(npcKey .. "#name", "")

        -- Match to existing NPC: prefer uniqueId, fall back to name
        local npc = npcByUniqueId[uniqueId] or npcByName[name]

        if npc then
            -- Restore position
            npc.position.x = xmlFile:getFloat(npcKey .. ".position#x", npc.position.x)
            npc.position.y = xmlFile:getFloat(npcKey .. ".position#y", npc.position.y)
            npc.position.z = xmlFile:getFloat(npcKey .. ".position#z", npc.position.z)
            npc.rotation.y = xmlFile:getFloat(npcKey .. ".rotation#y", npc.rotation.y)

            -- Restore home position
            if xmlFile:hasProperty(npcKey .. ".home#x") then
                npc.homePosition = npc.homePosition or {}
                npc.homePosition.x = xmlFile:getFloat(npcKey .. ".home#x", 0)
                npc.homePosition.y = xmlFile:getFloat(npcKey .. ".home#y", 0)
                npc.homePosition.z = xmlFile:getFloat(npcKey .. ".home#z", 0)
            end
            npc.homeBuildingName = xmlFile:getString(npcKey .. ".home#buildingName", npc.homeBuildingName or "")

            -- Restore relationship & stats (most important!)
            npc.relationship = xmlFile:getInt(npcKey .. ".stats#relationship", npc.relationship)
            npc.totalFavorsCompleted = xmlFile:getInt(npcKey .. ".stats#favorsCompleted", 0)
            npc.totalFavorsFailed = xmlFile:getInt(npcKey .. ".stats#favorsFailed", 0)
            npc.favorCooldown = xmlFile:getFloat(npcKey .. ".stats#favorCooldown", 0)

            -- Restore AI state
            npc.aiState = xmlFile:getString(npcKey .. ".ai#state", "idle")
            npc.currentAction = xmlFile:getString(npcKey .. ".ai#action", "idle")

            -- Restore personality modifiers
            if npc.aiPersonalityModifiers then
                npc.aiPersonalityModifiers.workEthic = xmlFile:getFloat(npcKey .. ".personality#workEthic", npc.aiPersonalityModifiers.workEthic)
                npc.aiPersonalityModifiers.sociability = xmlFile:getFloat(npcKey .. ".personality#sociability", npc.aiPersonalityModifiers.sociability)
                npc.aiPersonalityModifiers.generosity = xmlFile:getFloat(npcKey .. ".personality#generosity", npc.aiPersonalityModifiers.generosity)
                npc.aiPersonalityModifiers.punctuality = xmlFile:getFloat(npcKey .. ".personality#punctuality", npc.aiPersonalityModifiers.punctuality)
            end

            -- Restore visual properties
            npc.appearanceSeed = xmlFile:getInt(npcKey .. ".visual#appearanceSeed", npc.appearanceSeed)
            npc.isFemale = xmlFile:getBool(npcKey .. ".visual#isFemale", npc.isFemale or false)
            npc.movementSpeed = xmlFile:getFloat(npcKey .. ".visual#movementSpeed", npc.movementSpeed)

            -- Restore needs system
            if npc.needs then
                npc.needs.energy = xmlFile:getFloat(npcKey .. ".needs#energy", npc.needs.energy)
                npc.needs.social = xmlFile:getFloat(npcKey .. ".needs#social", npc.needs.social)
                npc.needs.hunger = xmlFile:getFloat(npcKey .. ".needs#hunger", npc.needs.hunger)
                npc.needs.workSatisfaction = xmlFile:getFloat(npcKey .. ".needs#workSatisfaction", npc.needs.workSatisfaction)
            end
            npc.mood = xmlFile:getString(npcKey .. ".needs#mood", npc.mood or "neutral")

            -- Restore encounters (up to 10, with sentiment + partner)
            npc.encounters = {}
            pcall(function()
                xmlFile:iterate(npcKey .. ".encounters.encounter", function(_, eKey)
                    if #npc.encounters >= 10 then return end
                    local encounter = {
                        type = xmlFile:getString(eKey .. "#type", ""),
                        time = xmlFile:getFloat(eKey .. "#time", 0),
                        details = xmlFile:getString(eKey .. "#details", ""),
                        partner = xmlFile:getString(eKey .. "#partner", ""),
                        sentiment = xmlFile:getString(eKey .. "#sentiment", "neutral"),
                    }
                    if encounter.partner == "" then encounter.partner = nil end
                    table.insert(npc.encounters, encounter)
                end)
            end)

            -- Update entity position to match restored data
            self.entityManager:updateNPCEntity(npc, 0)

            restoredCount = restoredCount + 1
        end
    end)

    -- Restore active favors
    if self.favorSystem and self.favorSystem.restoreFavor then
        xmlFile:iterate(NPC_SAVE_ROOT .. ".favors.favor", function(_, favorKey)
            local favor = {
                npcId = xmlFile:getInt(favorKey .. "#npcId", 0),
                npcName = xmlFile:getString(favorKey .. "#npcName", ""),
                type = xmlFile:getString(favorKey .. "#type", ""),
                description = xmlFile:getString(favorKey .. "#description", ""),
                timeRemaining = xmlFile:getFloat(favorKey .. "#timeRemaining", 0),
                progress = xmlFile:getInt(favorKey .. "#progress", 0),
                awaitingConfirmation = xmlFile:getBool(favorKey .. "#awaitingConfirmation", false),
                loanAmountDeducted = xmlFile:getBool(favorKey .. "#loanAmountDeducted", false),
                loanAmount = xmlFile:getFloat(favorKey .. "#loanAmount", nil),
                reward = {
                    relationship = xmlFile:getFloat(favorKey .. "#rewardRelationship", 0),
                    money = xmlFile:getFloat(favorKey .. "#rewardMoney", xmlFile:getFloat(favorKey .. "#reward", 0)),
                    xp = xmlFile:getFloat(favorKey .. "#rewardXp", 0)
                }
            }
            self.favorSystem:restoreFavor(favor)
        end)
    end

    -- Restore NPC-NPC relationships
    if self.relationshipManager then
        pcall(function()
            xmlFile:iterate(NPC_SAVE_ROOT .. ".npcRelationships.rel", function(_, relKey)
                local key = xmlFile:getString(relKey .. "#key", "")
                if key ~= "" then
                    self.relationshipManager.npcRelationships[key] = {
                        value = xmlFile:getFloat(relKey .. "#value", 50),
                        lastInteraction = xmlFile:getFloat(relKey .. "#lastInteraction", 0),
                        interactionCount = xmlFile:getInt(relKey .. "#interactionCount", 0),
                    }
                end
            end)
        end)
    end

    xmlFile:delete()

    if self.settings.debugMode then
        print(string.format("[NPC Favor] Restored %d/%d NPCs from save", restoredCount, savedNpcCount))
    end
end

-- =========================================================
-- Dynamic Emergent Events (Step 9)
-- =========================================================
-- Event scheduler drives community-scale activities:
--   Friday night party, harvest gathering, morning market,
--   Sunday rest day, and rainy day shelter behavior.
-- Events are checked once per game hour and override normal
-- NPC AI decisions for participants. Non-participants and
-- player interactions are unaffected.
-- =========================================================

--- Initialize the event scheduler data structure.
-- Called from initializeNPCs() after building classification.
function NPCSystem:initEventScheduler()
    self.eventScheduler = {
        lastCheckHour = -1,
        activeEvent = nil,
        eventParticipants = {},
    }

    if self.settings.debugMode then
        print("[NPC Favor] Event scheduler initialized")
    end
end

--- Get current weather factor for event decisions.
-- Reads from g_currentMission.environment.weather and returns
-- a numeric factor: 1.0 = clear, 0.7 = rain, 0.3 = storm.
-- @return number  Weather factor (0.0 - 1.0)
function NPCSystem:getWeatherFactor()
    if not g_currentMission or not g_currentMission.environment then
        return 1.0
    end

    local weather = g_currentMission.environment.weather
    if not weather then
        return 1.0
    end

    local weatherType = nil
    pcall(function()
        weatherType = weather.currentWeather or weather.weatherType
    end)

    if not weatherType then
        return 1.0
    end

    local factors = {
        clear  = 1.0,
        sunny  = 1.0,
        cloudy = 0.9,
        rain   = 0.7,
        storm  = 0.3,
        snow   = 0.5,
        fog    = 0.8,
    }

    return factors[weatherType] or 1.0
end

--- Get terrain height at a world position, with safe fallback.
-- @param x  World X
-- @param z  World Z
-- @return number  Terrain Y height (0 if unavailable)
function NPCSystem:getTerrainHeight(x, z)
    if g_currentMission and g_currentMission.terrainRootNode then
        local ok, h = pcall(getTerrainHeightAtWorldPos,
            g_currentMission.terrainRootNode, x, 0, z)
        if ok and h then
            return h + 0.05
        end
    end
    return 0
end

--- Check if any NPC's assigned field has mature/ready-to-harvest crops.
-- Returns the NPC and field info if found.
-- @return npc, field  or nil, nil
function NPCSystem:findHarvestReadyNPC()
    for _, npc in ipairs(self.activeNPCs) do
        if npc.isActive and npc.assignedField then
            local cropInfo = npc.assignedField.cropInfo
            if cropInfo then
                -- Growth state patterns: look for harvest-ready indicators
                local gs = cropInfo.growthState
                if gs then
                    -- FS25 growth states: typically 4+ means mature/harvestable
                    if type(gs) == "number" and gs >= 4 then
                        return npc, npc.assignedField
                    elseif type(gs) == "string" then
                        local gsLower = gs:lower()
                        if gsLower == "harvest" or gsLower == "mature" or gsLower == "ready" then
                            return npc, npc.assignedField
                        end
                    end
                end
            end
        end
    end
    return nil, nil
end

--- Main event scheduler update. Called once per game hour from update().
-- Evaluates conditions and triggers at most one event at a time.
-- Active events are ended when their time window expires.
-- @param hour           Current game hour (0-23)
-- @param day            Current game day
-- @param weatherFactor  Weather factor from getWeatherFactor()
function NPCSystem:updateEventScheduler(hour, day, weatherFactor)
    -- Safety: need AI system and active NPCs
    if not self.aiSystem or #self.activeNPCs == 0 then
        return
    end

    local scheduler = self.eventScheduler

    -- -------------------------------------------------------
    -- End expired events first
    -- -------------------------------------------------------
    if scheduler.activeEvent then
        local ev = scheduler.activeEvent
        local shouldEnd = false

        if ev.type == "friday_party" and hour >= 22 then
            shouldEnd = true
        elseif ev.type == "harvest_gathering" then
            ev.hoursElapsed = (ev.hoursElapsed or 0) + 1
            if ev.hoursElapsed >= 2 then
                shouldEnd = true
            end
        elseif ev.type == "morning_market" and hour >= 10 then
            shouldEnd = true
        elseif ev.type == "sunday_rest" and hour >= 22 then
            shouldEnd = true
        elseif ev.type == "rainy_day" and weatherFactor >= 0.7 then
            shouldEnd = true
        end

        if shouldEnd then
            self:endEvent(scheduler.activeEvent)
            scheduler.activeEvent = nil
            scheduler.eventParticipants = {}
        else
            -- Event still active, skip new event evaluation
            return
        end
    end

    -- -------------------------------------------------------
    -- Rainy Day (highest priority -- overrides other events)
    -- -------------------------------------------------------
    if weatherFactor < 0.7 then
        self:startRainyDayEvent()
        return
    end

    -- -------------------------------------------------------
    -- Sunday Rest (day % 7 == 0)
    -- -------------------------------------------------------
    if day % 7 == 0 then
        if hour >= 7 and hour <= 21 then
            self:startSundayRestEvent(hour)
            return
        end
    end

    -- -------------------------------------------------------
    -- Friday Night Party (day % 7 == 5, hour 19-21)
    -- -------------------------------------------------------
    if day % 7 == 5 and hour >= 19 and hour < 22 then
        self:startFridayPartyEvent()
        return
    end

    -- -------------------------------------------------------
    -- Morning Market (hour 8-9, any day, needs shop building)
    -- -------------------------------------------------------
    if hour >= 8 and hour < 10 then
        self:startMorningMarketEvent()
        return
    end

    -- -------------------------------------------------------
    -- Harvest Gathering (any time during work hours, if crops ready)
    -- -------------------------------------------------------
    if hour >= 7 and hour <= 17 then
        self:startHarvestGatheringEvent()
        -- Note: may not start if no harvest-ready fields found
    end
end

--- Start Friday Night Party event.
-- The most sociable NPC hosts; 4-6 NPCs attend at host's home.
function NPCSystem:startFridayPartyEvent()
    -- Find host: NPC with highest sociability
    local host = nil
    local bestSociability = -1

    for _, npc in ipairs(self.activeNPCs) do
        if npc.isActive then
            local soc = (npc.aiPersonalityModifiers and npc.aiPersonalityModifiers.sociability) or 1.0
            if soc > bestSociability then
                bestSociability = soc
                host = npc
            end
        end
    end

    if not host or not host.homePosition then
        return
    end

    -- Select 4-6 attendees (excluding host)
    local candidates = {}
    for _, npc in ipairs(self.activeNPCs) do
        if npc.isActive and npc ~= host then
            table.insert(candidates, npc)
        end
    end

    -- Shuffle candidates
    for i = #candidates, 2, -1 do
        local j = math.random(1, i)
        candidates[i], candidates[j] = candidates[j], candidates[i]
    end

    local attendeeCount = math.min(math.random(4, 6), #candidates)
    local participants = {host}

    for i = 1, attendeeCount do
        local npc = candidates[i]
        table.insert(participants, npc)

        -- Send attendees to host's home
        local angle = (i / attendeeCount) * math.pi * 2
        local offset = 2 + math.random() * 3
        local targetX = host.homePosition.x + math.cos(angle) * offset
        local targetZ = host.homePosition.z + math.sin(angle) * offset

        self.aiSystem:startEventBehavior(npc, "party", {
            targetX = targetX,
            targetZ = targetZ,
            hostNPC = host,
        })
    end

    -- Host stays home and socializes
    host.currentAction = "partying"

    self.eventScheduler.activeEvent = {
        type = "friday_party",
        host = host,
        startHour = self.scheduler:getCurrentHour(),
    }
    self.eventScheduler.eventParticipants = participants

    if self.settings.debugMode then
        print(string.format("[NPC Favor] Friday party started at %s's home with %d guests",
            host.name, attendeeCount))
    end

    if self.settings.showNotifications then
        self:showNotification("Community Event",
            string.format("%s is hosting a Friday night party!", host.name))
    end
end

--- Start Harvest Gathering event.
-- Find an NPC with a harvest-ready field; 2-3 nearby NPCs join to help.
function NPCSystem:startHarvestGatheringEvent()
    local ownerNPC, field = self:findHarvestReadyNPC()
    if not ownerNPC or not field then
        return
    end

    -- Find 2-3 nearby NPCs to help
    local helpers = {}
    for _, npc in ipairs(self.activeNPCs) do
        if npc.isActive and npc ~= ownerNPC then
            local dx = npc.position.x - ownerNPC.position.x
            local dz = npc.position.z - ownerNPC.position.z
            local dist = math.sqrt(dx * dx + dz * dz)
            if dist < 200 then
                table.insert(helpers, {npc = npc, dist = dist})
            end
        end
    end

    -- Sort by distance, take closest 2-3
    table.sort(helpers, function(a, b) return a.dist < b.dist end)
    local helperCount = math.min(math.random(2, 3), #helpers)

    local participants = {ownerNPC}

    -- Send owner to their field for harvesting
    self.aiSystem:startEventBehavior(ownerNPC, "harvest", {
        field = field,
        rowIndex = 0,
    })

    for i = 1, helperCount do
        local helper = helpers[i].npc
        table.insert(participants, helper)
        self.aiSystem:startEventBehavior(helper, "harvest", {
            field = field,
            rowIndex = i,
        })
    end

    self.eventScheduler.activeEvent = {
        type = "harvest_gathering",
        owner = ownerNPC,
        field = field,
        hoursElapsed = 0,
    }
    self.eventScheduler.eventParticipants = participants

    if self.settings.debugMode then
        print(string.format("[NPC Favor] Harvest gathering started at %s's field #%d with %d helpers",
            ownerNPC.name, field.id or 0, helperCount))
    end

    if self.settings.showNotifications then
        self:showNotification("Community Event",
            string.format("%s's field is ready! Neighbors are helping with the harvest.", ownerNPC.name))
    end
end

--- Start Morning Market event.
-- NPCs gather near a shop building for casual shopping/socializing.
function NPCSystem:startMorningMarketEvent()
    -- Need classified shop buildings
    if not self.classifiedBuildings or not self.classifiedBuildings.shop then
        return
    end

    local shops = self.classifiedBuildings.shop
    if #shops == 0 then
        return
    end

    -- Pick a random shop
    local shop = shops[math.random(1, #shops)]

    -- Select 3-5 NPCs to attend
    local candidates = {}
    for _, npc in ipairs(self.activeNPCs) do
        if npc.isActive then
            table.insert(candidates, npc)
        end
    end

    -- Shuffle
    for i = #candidates, 2, -1 do
        local j = math.random(1, i)
        candidates[i], candidates[j] = candidates[j], candidates[i]
    end

    local attendeeCount = math.min(math.random(3, 5), #candidates)
    local participants = {}

    for i = 1, attendeeCount do
        local npc = candidates[i]
        table.insert(participants, npc)

        self.aiSystem:startEventBehavior(npc, "market", {
            centerX = shop.x,
            centerZ = shop.z,
            radius = 8,
        })
    end

    self.eventScheduler.activeEvent = {
        type = "morning_market",
        shop = shop,
    }
    self.eventScheduler.eventParticipants = participants

    if self.settings.debugMode then
        print(string.format("[NPC Favor] Morning market started near %s with %d NPCs",
            shop.name or "shop", attendeeCount))
    end
end

--- Start Sunday Rest event.
-- NPCs stay home in the morning, visit neighbors in the afternoon.
-- @param hour  Current hour (affects morning vs afternoon behavior)
function NPCSystem:startSundayRestEvent(hour)
    local participants = {}

    for _, npc in ipairs(self.activeNPCs) do
        if npc.isActive then
            table.insert(participants, npc)

            if hour < 12 then
                -- Morning: stay near home
                self.aiSystem:startEventBehavior(npc, "sunday_rest", {
                    phase = "morning",
                    homeX = npc.homePosition and npc.homePosition.x or npc.position.x,
                    homeZ = npc.homePosition and npc.homePosition.z or npc.position.z,
                })
            else
                -- Afternoon: visit 1-2 neighbors or form groups in town
                local neighbor = nil
                for _, other in ipairs(self.activeNPCs) do
                    if other.isActive and other ~= npc then
                        local dx = other.position.x - npc.position.x
                        local dz = other.position.z - npc.position.z
                        if math.sqrt(dx * dx + dz * dz) < 100 then
                            neighbor = other
                            break
                        end
                    end
                end

                if neighbor and neighbor.homePosition then
                    self.aiSystem:startEventBehavior(npc, "sunday_rest", {
                        phase = "visit",
                        targetX = neighbor.homePosition.x,
                        targetZ = neighbor.homePosition.z,
                    })
                else
                    self.aiSystem:startEventBehavior(npc, "sunday_rest", {
                        phase = "morning",
                        homeX = npc.homePosition and npc.homePosition.x or npc.position.x,
                        homeZ = npc.homePosition and npc.homePosition.z or npc.position.z,
                    })
                end
            end
        end
    end

    self.eventScheduler.activeEvent = {
        type = "sunday_rest",
        hour = hour,
    }
    self.eventScheduler.eventParticipants = participants

    if self.settings.debugMode then
        print(string.format("[NPC Favor] Sunday rest event active (%s) with %d NPCs",
            hour < 12 and "morning" or "afternoon", #participants))
    end
end

--- Start Rainy Day event.
-- All NPCs seek shelter at the nearest building and increase movement speed.
function NPCSystem:startRainyDayEvent()
    local participants = {}

    for _, npc in ipairs(self.activeNPCs) do
        if npc.isActive then
            table.insert(participants, npc)

            -- Find nearest building for shelter
            local buildings = self:findNearbyBuildings(npc.position.x, npc.position.z, 100)
            local shelterX, shelterZ = npc.position.x, npc.position.z

            if #buildings > 0 then
                local building = buildings[1]
                -- Stand right next to the building
                local angle = math.random() * math.pi * 2
                local offset = 1 + math.random() * 2
                shelterX = building.x + math.cos(angle) * offset
                shelterZ = building.z + math.sin(angle) * offset
            elseif npc.homePosition then
                shelterX = npc.homePosition.x
                shelterZ = npc.homePosition.z
            end

            self.aiSystem:startEventBehavior(npc, "rain_shelter", {
                targetX = shelterX,
                targetZ = shelterZ,
            })
        end
    end

    self.eventScheduler.activeEvent = {
        type = "rainy_day",
    }
    self.eventScheduler.eventParticipants = participants

    if self.settings.debugMode then
        print(string.format("[NPC Favor] Rainy day event: %d NPCs seeking shelter", #participants))
    end
end

--- End an active event: restore NPC states to idle.
-- @param event  The active event table to end
function NPCSystem:endEvent(event)
    if not event then
        return
    end

    for _, npc in ipairs(self.eventScheduler.eventParticipants or {}) do
        if npc.isActive then
            -- Restore normal movement speed if it was boosted
            if npc._originalSpeed then
                npc.movementSpeed = npc._originalSpeed
                npc._originalSpeed = nil
            end

            -- Clear event-specific action and return to idle
            npc.currentAction = "idle"
            self.aiSystem:setState(npc, self.aiSystem.STATES.IDLE)
        end
    end

    if self.settings.debugMode then
        print(string.format("[NPC Favor] Event '%s' ended, participants returned to idle",
            event.type or "unknown"))
    end
end

-- =========================================================
-- Cleanup
-- =========================================================

-- Detect companion mods via mission bridge properties.
-- Called once after the deferred init guards pass (mission fully started).
-- Stores references used by NPCInteractionUI for context-aware dialog.
function NPCSystem:detectOptionalMods()
    local rwe = g_currentMission and g_currentMission.randomWorldEvents
    if rwe then
        self.rweManager = rwe
        print("[NPC Favor] FS25_RandomWorldEvents detected — NPCs will reference active world events in conversation")
    end

    local md = g_currentMission and g_currentMission.MarketDynamics
    if md then
        self.marketDynamicsManager = md
        print("[NPC Favor] FS25_MarketDynamics detected — NPCs will reference market conditions in conversation")
    end
end

function NPCSystem:delete()
    print("[NPC Favor] Shutting down")

    -- Drop AI job message subscription
    if self._aiJobMsgSubscribed and g_messageCenter then
        pcall(function() g_messageCenter:unsubscribeAll(self) end)
        self._aiJobMsgSubscribed = false
    end

    -- Restore any temporary field-ownership flips on shutdown.
    pcall(function() self:restoreAllOwnershipFlips() end)

    -- Clean up NPCs
    self:clearAllNPCs()

    -- Clean up subsystems
    if self.interactionUI and self.interactionUI.delete then
        self.interactionUI:delete()
    end
    if self.favorHUD and self.favorHUD.delete then
        self.favorHUD:delete()
    end
    if self.contractorBridge then
        self.contractorBridge:delete()
    end
    if self.settingsPanel then
        self.settingsPanel:delete()
        self.settingsPanel = nil
    end
end
