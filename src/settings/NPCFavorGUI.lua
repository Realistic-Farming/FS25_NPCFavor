-- =========================================================
-- TODO / FUTURE VISION
-- =========================================================
-- CONSOLE COMMANDS:
-- [x] npcStatus - Show NPC system status
-- [x] npcSpawn - Spawn NPC with optional name argument
-- [x] npcList - List all active NPCs
-- [x] npcReset - Reset/initialize NPC system
-- [x] npcHelp - Display help text with all commands
-- [x] npcDebug - Toggle debug mode on/off with save
-- [x] npcReload - Reload settings from XML
-- [x] npcTest - Basic connectivity test
-- GUI ROUTING:
-- [x] Routes console commands to g_NPCSystem methods
-- [x] Graceful fallback when NPC system not initialized
-- FUTURE ENHANCEMENTS:
-- [ ] npcTeleport [name] - Teleport player to named NPC
-- [ ] npcRelationship [name] - Show relationship status with specific NPC
-- [ ] npcFavor [accept|reject] - Accept or reject pending favor from console
-- [ ] npcGift [name] [item] - Give item to named NPC via console
-- [ ] Tab-completion for NPC names in console commands
-- [ ] GUI dialog for NPC interaction (favor list, relationship overview)
-- =========================================================

-- =========================================================
-- FS25 NPC Favor Mod - GUI and Console Commands
-- =========================================================
-- Handles console commands and GUI integration
-- =========================================================

NPCFavorGUI = NPCFavorGUI or {}
NPCFavorGUI_mt = Class(NPCFavorGUI)

function NPCFavorGUI.new(npcSystem)
    local self = setmetatable({}, NPCFavorGUI_mt)
    self.npcSystem = npcSystem
    
    return self
end

function NPCFavorGUI:registerConsoleCommands()
    print("[NPC Favor] Registering console commands...")
    addConsoleCommand("npcStatus", "Show NPC system status", "npcStatus", self)
    addConsoleCommand("npcSpawn", "Spawn an NPC with optional name", "npcSpawn", self)
    addConsoleCommand("npcList", "List all active NPCs", "npcList", self)
    addConsoleCommand("npcReset", "Reset/Initialize NPC system", "npcReset", self)
    addConsoleCommand("npcHelp", "Show help message", "npcHelp", self)
    addConsoleCommand("npcDebug", "Toggle debug mode", "npcDebug", self)
    addConsoleCommand("npcReload", "Reload NPC settings", "npcReload", self)
    addConsoleCommand("npcTest", "Test function", "npcTest", self)
    addConsoleCommand("npcGoto", "Teleport to an NPC by number", "npcGoto", self)
    addConsoleCommand("npcProbe", "Probe animation system APIs", "npcProbe", self)
    addConsoleCommand("npcVehicleMode", "Switch vehicle mode (hybrid/realistic/visual)", "npcVehicleMode", self)
    addConsoleCommand("npcFavors", "Open favor management dialog", "npcFavors", self)
    addConsoleCommand("npcAdmin", "Open NPC admin panel", "npcAdmin", self)
    addConsoleCommand("npcForceFavor", "Force a favor request (testing)", "npcForceFavor", self)
    addConsoleCommand("npcDeleteVehicle", "Delete the nearest vehicle/implement to you [radius]", "npcDeleteVehicle", self)

    print("[NPC Favor] Console commands registered successfully")
end

-- Console command handler functions that route to NPCSystem
function NPCFavorGUI:npcStatus()
    print("[NPC Favor] npcStatus command called")
    if g_NPCSystem then
        return g_NPCSystem:consoleCommandStatus()
    else
        return "NPC System not initialized. Try reloading the save or type 'NPCReset'."
    end
end

function NPCFavorGUI:npcSpawn(name)
    print("[NPC Favor] npcSpawn command called with name: " .. (name or "nil"))
    if g_NPCSystem then
        return g_NPCSystem:consoleCommandSpawn(name or "")
    else
        return "NPC System not initialized"
    end
end

function NPCFavorGUI:npcList()
    if not g_NPCSystem then
        return "NPC System not initialized"
    end

    -- Show popup dialog if DialogLoader is available
    if DialogLoader and DialogLoader.show then
        local shown = DialogLoader.show("NPCListDialog", "setNPCSystem", g_NPCSystem)
        if shown then
            return "NPC roster dialog opened"
        end
    end

    -- Fallback to console text if dialog unavailable
    return g_NPCSystem:consoleCommandList()
end

function NPCFavorGUI:npcReset()
    print("[NPC Favor] npcReset command called")
    if g_NPCSystem then
        return g_NPCSystem:consoleCommandReset()
    else
        return "NPC System not initialized"
    end
end

function NPCFavorGUI:npcHelp()
    local helpText = [[
=== NPC Favor Mod Commands ===
npcStatus           - Show NPC system status
npcSpawn [name]     - Spawn an NPC with optional name
npcList             - List all active NPCs
npcReset            - Reset/Initialize NPC system
npcHelp             - Show this help message
npcDebug [on|off]   - Toggle debug mode
npcReload           - Reload NPC settings
npcGoto [number]    - Teleport to an NPC (no number = show list)
npcProbe            - Probe animation system APIs
npcFavors           - Open favor management dialog
npcAdmin            - Open NPC admin panel (adjust relationships)
npcVehicleMode [mode] - Switch vehicle mode (hybrid/realistic/visual)
npcForceFavor       - Force generate a favor request (testing)
npcDeleteVehicle [r] - Delete the nearest vehicle/implement to you (r = radius, default 30m)
npcTest             - Test function

=== Interaction ===
Press E near an NPC to interact
Favors will appear in your task list
NPCs will roam near you as you move around the map

=== Troubleshooting ===
If commands don't work, try:
1. Type 'NPCReset' to force initialization
2. Save and reload the game
3. Check game console for NPC Favor messages
]]
    return helpText
end

function NPCFavorGUI:npcDebug(state)
    if not g_NPCSystem then
        return "NPC System not initialized. Type 'NPCReset' first."
    end
    
    if state == "on" then
        g_NPCSystem.settings.debugMode = true
        return "Debug mode enabled (persists on next game save)"
    elseif state == "off" then
        g_NPCSystem.settings.debugMode = false
        return "Debug mode disabled (persists on next game save)"
    else
        return "Usage: npcDebug [on|off]"
    end
end

function NPCFavorGUI:npcReload()
    if g_NPCSystem then
        g_NPCSystem.settings:load()
        return "NPC settings reloaded"
    else
        return "NPC System not initialized"
    end
end

function NPCFavorGUI:npcTest()
    print("[NPC Favor] Test function called - console commands are working!")
    return "NPC Favor test successful. Type 'npcHelp' for commands."
end

function NPCFavorGUI:npcDeleteVehicle(radius)
    if not g_NPCSystem then
        return "NPC System not initialized"
    end
    return g_NPCSystem:consoleCommandDeleteNearestVehicle(radius)
end

function NPCFavorGUI:npcForceFavor()
    if not g_NPCSystem or not g_NPCSystem.favorSystem then
        return "NPC System not initialized"
    end
    local result = g_NPCSystem.favorSystem:generateFavorRequest()
    if result then
        return "Favor generated! Check HUD flash or type 'npcFavors' to see active favors."
    else
        return "No favor generated — no eligible NPCs (need relationship >= 10 and favorCooldown = 0)"
    end
end

function NPCFavorGUI:npcGoto(num)
    if not g_NPCSystem then
        return "NPC System not initialized"
    end

    local index = tonumber(num)
    if not index then
        -- No number given: show a quick list with numbers
        if g_NPCSystem.npcCount == 0 then
            return "No active NPCs"
        end
        local list = "Usage: npcGoto <number>\n"
        for i, npc in ipairs(g_NPCSystem.activeNPCs) do
            if npc.isActive then
                local dist = "?"
                if g_NPCSystem.playerPositionValid then
                    local dx = npc.position.x - g_NPCSystem.playerPosition.x
                    local dz = npc.position.z - g_NPCSystem.playerPosition.z
                    dist = string.format("%.0f", math.sqrt(dx * dx + dz * dz))
                end
                list = list .. string.format("  %d. %s (%sm away)\n", i, npc.name, dist)
            end
        end
        return list
    end

    local npc = g_NPCSystem.activeNPCs[index]
    if not npc then
        return string.format("NPC #%d not found. Use npcGoto to see the list.", index)
    end

    -- Smart teleport: context-aware positioning (Issue #6)
    local success, message = NPCTeleport.teleportToNPC(g_NPCSystem, npc)
    return message
end

function NPCFavorGUI:npcFavors()
    if not g_NPCSystem then
        return "NPC System not initialized"
    end

    -- Show favor management dialog if DialogLoader is available
    if DialogLoader and DialogLoader.show then
        local shown = DialogLoader.show("NPCFavorManagementDialog", "setNPCSystem", g_NPCSystem)
        if shown then
            return "Favor management dialog opened"
        end
    end

    -- Fallback to console text if dialog unavailable
    if not g_NPCSystem.favorSystem then
        return "No active favors"
    end
    
    local activeFavors = g_NPCSystem.favorSystem.activeFavors or {}
    if #activeFavors == 0 then
        return "No active favors"
    end
    
    local result = "=== Active Favors ===\n"
    for i, favor in ipairs(activeFavors) do
        local npc = g_NPCSystem:getNPCById(favor.npcId)
        local npcName = npc and npc.name or "Unknown"
        result = result .. string.format("%d. %s - %s (Reward: $%d)\n",
            i, npcName, favor.description or favor.type, favor.reward or 0)
    end
    return result
end

function NPCFavorGUI:npcAdmin()
    if not g_NPCSystem then
        return "NPC System not initialized"
    end
    if DialogLoader and DialogLoader.show then
        local shown = DialogLoader.show("NPCAdminListDialog", "setNPCSystem", g_NPCSystem)
        if shown then
            return "NPC Admin panel opened"
        end
    end
    return "Admin dialog not available"
end

function NPCFavorGUI:npcProbe()
    local out = "=== NPC ANIMATION SYSTEM PROBE v3 ===\n"

    -- =====================================================
    -- SECTION 1: OUR SPAWNED NPC ENTITIES — animation clips
    -- =====================================================
    out = out .. "\n-- OUR NPC ENTITY ANIMATION CLIPS --\n"
    if g_NPCSystem and g_NPCSystem.entityManager then
        local em = g_NPCSystem.entityManager
        local entityCount = 0
        for npcId, entity in pairs(em.npcEntities) do
            entityCount = entityCount + 1
            out = out .. string.format("\nEntity #%d (npcId=%s):\n", entity.id, tostring(npcId))
            out = out .. "  isAnimatedCharacter: " .. tostring(entity.isAnimatedCharacter) .. "\n"
            out = out .. "  useDirectAnimation: " .. tostring(entity.useDirectAnimation) .. "\n"
            out = out .. "  animatedModelLoaded: " .. tostring(entity.animatedModelLoaded) .. "\n"
            out = out .. "  animCharSet: " .. tostring(entity.animCharSet) .. "\n"
            out = out .. "  isFemale: " .. tostring(entity.isFemale) .. "\n"

            -- Dump ALL clips from this entity's character set
            if entity.animCharSet and entity.animCharSet ~= 0 then
                local okNC, numClips = pcall(function() return getAnimNumOfClips(entity.animCharSet) end)
                out = out .. "  numClips: " .. tostring(okNC and numClips) .. "\n"
                if okNC and numClips and numClips > 0 then
                    for ci = 0, numClips - 1 do
                        local okCN, clipName = pcall(function() return getAnimClipName(entity.animCharSet, ci) end)
                        local clipDuration = 0
                        pcall(function() clipDuration = getAnimClipDuration(entity.animCharSet, ci) end)
                        out = out .. string.format("    clip[%d]: %-40s  dur=%.2fs\n",
                            ci, tostring(okCN and clipName or "?"), clipDuration)
                    end
                end
            end

            -- Check humanModel skeleton
            if entity.humanModel then
                out = out .. "  humanModel.rootNode: " .. tostring(entity.humanModel.rootNode) .. "\n"
                out = out .. "  humanModel.skeleton: " .. tostring(entity.humanModel.skeleton) .. "\n"

                -- Search skeleton tree for any char sets we might have missed
                if entity.humanModel.skeleton and entity.humanModel.skeleton ~= 0 then
                    local function findCharSets(node, depth, maxDepth)
                        if depth > maxDepth then return end
                        local okA, acs = pcall(function() return getAnimCharacterSet(node) end)
                        if okA and acs and acs ~= 0 and acs ~= entity.animCharSet then
                            local nc2 = 0
                            pcall(function() nc2 = getAnimNumOfClips(acs) end)
                            out = out .. string.format("  EXTRA charSet at depth %d: '%s' id=%s clips=%d\n",
                                depth, tostring(getName(node)), tostring(acs), nc2)
                            for ci = 0, math.min(nc2 - 1, 10) do
                                local okCN, cn = pcall(function() return getAnimClipName(acs, ci) end)
                                out = out .. string.format("    clip[%d]: %s\n", ci, tostring(okCN and cn))
                            end
                        end
                        for i = 0, getNumOfChildren(node) - 1 do
                            findCharSets(getChildAt(node, i), depth + 1, maxDepth)
                        end
                    end
                    pcall(function() findCharSets(entity.humanModel.skeleton, 0, 4) end)
                end
            end

            -- Check track states
            if entity.animCharSet and entity.animCharSet ~= 0 then
                out = out .. "  -- Track States --\n"
                for track = 0, 3 do
                    local enabled = false
                    local weight = 0
                    local speed = 0
                    pcall(function() enabled = isAnimTrackEnabled(entity.animCharSet, track) end)
                    pcall(function() weight = getAnimTrackBlendWeight(entity.animCharSet, track) end)
                    pcall(function() speed = getAnimTrackSpeedScale(entity.animCharSet, track) end)
                    if enabled then
                        out = out .. string.format("    track[%d]: enabled=%s weight=%.2f speed=%.2f\n",
                            track, tostring(enabled), weight, speed)
                    end
                end
            end

            -- Only probe first 2 entities in detail
            if entityCount >= 2 then
                out = out .. "\n  (... remaining entities omitted, showing first 2 ...)\n"
                break
            end
        end
        if entityCount == 0 then
            out = out .. "  (no NPC entities found)\n"
        end
    else
        out = out .. "  g_NPCSystem or entityManager not available\n"
    end

    -- =====================================================
    -- SECTION 2: ANIMATION CACHE — what clips are available
    -- =====================================================
    out = out .. "\n-- ANIMATION CACHE CLIP CATALOG --\n"
    if g_animCache and AnimationCache then
        -- List all AnimationCache constants
        out = out .. "AnimationCache constants:\n"
        pcall(function()
            for k, v in pairs(AnimationCache) do
                if type(v) == "number" then
                    out = out .. string.format("  AnimationCache.%s = %d\n", tostring(k), v)
                end
            end
        end)

        -- Dump clips from CHARACTER cache
        local charNode = nil
        pcall(function() charNode = g_animCache:getNode(AnimationCache.CHARACTER) end)
        out = out .. "\nCHARACTER cache node: " .. tostring(charNode) .. "\n"
        if charNode and charNode ~= 0 then
            -- Walk the cache node children looking for char sets
            local function dumpCacheNode(node, label, depth)
                local okCS, cs = pcall(function() return getAnimCharacterSet(node) end)
                if okCS and cs and cs ~= 0 then
                    local nc = 0
                    pcall(function() nc = getAnimNumOfClips(cs) end)
                    out = out .. string.format("  %s '%s' clips=%d\n", label, tostring(getName(node)), nc)
                    for ci = 0, math.min(nc - 1, 50) do
                        local okCN, cn = pcall(function() return getAnimClipName(cs, ci) end)
                        out = out .. string.format("    [%d] %s\n", ci, tostring(okCN and cn))
                    end
                end
                if depth < 3 then
                    for i = 0, getNumOfChildren(node) - 1 do
                        dumpCacheNode(getChildAt(node, i), label .. "/" .. tostring(i), depth + 1)
                    end
                end
            end
            pcall(function() dumpCacheNode(charNode, "CHAR", 0) end)
        end

        -- Dump clips from PEDESTRIAN cache if it exists
        local pedNode = nil
        pcall(function() pedNode = g_animCache:getNode(AnimationCache.PEDESTRIAN) end)
        if pedNode and pedNode ~= 0 then
            out = out .. "\nPEDESTRIAN cache node: " .. tostring(pedNode) .. "\n"
            pcall(function()
                local function dumpP(node, label, depth)
                    local okCS, cs = pcall(function() return getAnimCharacterSet(node) end)
                    if okCS and cs and cs ~= 0 then
                        local nc = 0
                        pcall(function() nc = getAnimNumOfClips(cs) end)
                        out = out .. string.format("  %s '%s' clips=%d\n", label, tostring(getName(node)), nc)
                        for ci = 0, math.min(nc - 1, 50) do
                            local okCN, cn = pcall(function() return getAnimClipName(cs, ci) end)
                            out = out .. string.format("    [%d] %s\n", ci, tostring(okCN and cn))
                        end
                    end
                    if depth < 3 then
                        for i = 0, getNumOfChildren(node) - 1 do
                            dumpP(getChildAt(node, i), label .. "/" .. tostring(i), depth + 1)
                        end
                    end
                end
                dumpP(pedNode, "PED", 0)
            end)
        else
            out = out .. "\nPEDESTRIAN cache: not found (tried AnimationCache.PEDESTRIAN)\n"
        end
    else
        out = out .. "  g_animCache or AnimationCache not available\n"
    end

    -- =====================================================
    -- SECTION 3: Try common clip names on entity #1
    -- =====================================================
    out = out .. "\n-- CLIP NAME SEARCH (entity #1) --\n"
    if g_NPCSystem and g_NPCSystem.entityManager then
        local firstEntity = nil
        for _, entity in pairs(g_NPCSystem.entityManager.npcEntities) do
            firstEntity = entity
            break
        end
        if firstEntity and firstEntity.animCharSet and firstEntity.animCharSet ~= 0 then
            local cs = firstEntity.animCharSet
            local tryNames = {
                -- Standard player clips
                "idle1Source", "idle2Source", "idleSource",
                "idle1FemaleSource", "idle2FemaleSource",
                "walkSource", "walk1Source", "walkFemaleSource",
                "runSource", "run1Source", "runFemaleSource",
                "sprintSource",
                -- NPC-specific clips
                "NPCWalkMale01Source", "NPCWalkFemale01Source",
                "NPCIdleMale01Source", "NPCIdleFemale01Source",
                "NPCRunMale01Source", "NPCRunFemale01Source",
                -- Generic names
                "walk", "run", "idle", "sprint",
                -- Pedestrian clips
                "pedestrianWalk", "pedestrianIdle",
                "npcWalk", "npcIdle", "npcRun",
            }
            for _, name in ipairs(tryNames) do
                local okIdx, idx = pcall(function() return getAnimClipIndex(cs, name) end)
                if okIdx and idx and idx >= 0 then
                    out = out .. string.format("  FOUND: '%s' -> clipIndex=%d\n", name, idx)
                end
            end
            out = out .. "  (names with no result were not found)\n"
        else
            out = out .. "  No entity with animCharSet available\n"
        end
    end

    out = out .. "\n=== END PROBE v3 ===\n"
    print(out)
    return out
end

function NPCFavorGUI:npcVehicleMode(mode)
    if not g_NPCSystem then
        return "NPC System not initialized"
    end

    local settings = g_NPCSystem.settings
    if not settings then
        return "NPC settings not available"
    end

    if not mode or mode == "" then
        return string.format("Current vehicle mode: %s (options: hybrid, realistic, visual)", settings.npcVehicleMode or "hybrid")
    end

    mode = string.lower(mode)
    if mode ~= "realistic" and mode ~= "visual" and mode ~= "hybrid" then
        return "Invalid mode. Use: npcVehicleMode hybrid  OR  npcVehicleMode realistic  OR  npcVehicleMode visual"
    end

    local oldMode = settings.npcVehicleMode
    settings.npcVehicleMode = mode

    -- Notify the NPC system to switch vehicle modes
    if g_NPCSystem.switchVehicleMode then
        g_NPCSystem:switchVehicleMode(oldMode, mode)
    end

    return string.format("Vehicle mode changed: %s -> %s", oldMode or "realistic", mode)
end

function NPCFavorGUI:delete()
    -- Clean up if needed
end
