-- =========================================================
-- FS25 NPC Favor Mod - Smart Teleport System (Issue #6)
-- =========================================================
-- Context-aware player teleportation to NPCs:
--   - NPC in building: block teleport (don't strand player inside geometry)
--   - NPC walking: spawn behind them, facing their travel direction
--   - NPC standing: spawn in front of them, facing them
--   - Always snaps to terrain, avoids building interiors
--
-- Single shared implementation used by:
--   - npcGoto console command (NPCFavorGUI.lua)
--   - NPC List dialog "Go" buttons (NPCListDialog.lua)
--   - Favor Management dialog "Goto" buttons (NPCFavorManagementDialog.lua)
-- =========================================================

NPCTeleport = NPCTeleport or {}

--- Compute a safe approach position near an NPC: in front of them if standing,
-- behind them (facing the same way) if moving, snapped to terrain, and nudged
-- clear of buildings. Returns nil x/y/z and a reason if the NPC itself is
-- inside a building (we never hand out a teleport target into geometry).
-- Shared by teleportToNPC and the native map hotspot "Visit" button (see
-- NPCEntity:createMapHotspot / updateMapHotspot).
-- @param npcSystem  NPCSystem instance (for building detection)
-- @param npc        NPC data table (requires .position, .rotation, .aiState)
-- @return number|nil x, number|nil y, number|nil z, string|nil blockedReason,
--         number|nil playerRotY, boolean|nil isMoving
function NPCTeleport.getSafeApproachPosition(npcSystem, npc)
    if not npc or not npc.position then
        return nil, nil, nil, "NPC position unknown"
    end

    -- Check if NPC is inside a building — don't hand out a target inside structures
    if npcSystem and npcSystem.isPositionInsideBuilding then
        local insideBuilding, building = npcSystem:isPositionInsideBuilding(
            npc.position.x, npc.position.z, nil)
        if insideBuilding then
            local buildingName = building and building.name or "a building"
            return nil, nil, nil, string.format("%s is inside %s", npc.name or "NPC", buildingName)
        end
    end

    -- Determine spawn position based on NPC movement state
    local npcX, npcZ = npc.position.x, npc.position.z
    local npcRotY = npc.rotation and npc.rotation.y or 0
    local distance = 3  -- spawn 3m away
    local x, z, playerRotY

    local isMoving = (npc.aiState == "walking" or npc.aiState == "traveling"
        or npc.aiState == "driving" or npc.aiState == "working")
        and (npc.movementSpeed or 0) > 0.1

    if isMoving then
        -- NPC is walking: spawn BEHIND them, facing their travel direction
        -- NPC faces along rotation.y; "behind" = opposite from their facing direction
        x = npcX - math.sin(npcRotY) * distance
        z = npcZ - math.cos(npcRotY) * distance
        playerRotY = npcRotY  -- face same direction as NPC (looking at their back)
    else
        -- NPC is standing still: spawn IN FRONT of them, facing them
        x = npcX + math.sin(npcRotY) * distance
        z = npcZ + math.cos(npcRotY) * distance
        -- Rotate player to face the NPC
        local dx = npcX - x
        local dz = npcZ - z
        playerRotY = math.atan2(dx, dz)
    end

    -- Ensure we don't land inside a building
    if npcSystem and npcSystem.getSafePosition then
        x, z = npcSystem:getSafePosition(x, z, nil)
    end

    -- Snap Y to terrain
    local y = npc.position.y
    if g_currentMission and g_currentMission.terrainRootNode then
        local ok, h = pcall(getTerrainHeightAtWorldPos,
            g_currentMission.terrainRootNode, x, 0, z)
        if ok and h then
            y = h + 0.05
        end
    end

    return x, y, z, nil, playerRotY, isMoving
end

--- Teleport the player to an NPC with context-aware positioning.
-- @param npcSystem  NPCSystem instance (for building detection, time tracking)
-- @param npc        NPC data table (requires .position, .rotation, .aiState)
-- @return boolean   true if teleported successfully
-- @return string    status message describing what happened
function NPCTeleport.teleportToNPC(npcSystem, npc)
    local x, y, z, blockedReason, playerRotY, isMoving = NPCTeleport.getSafeApproachPosition(npcSystem, npc)
    if not x then
        return false, (blockedReason or "NPC position unknown") .. " - cannot teleport there"
    end

    -- Teleport the player
    local teleported = false
    if g_localPlayer and g_localPlayer.rootNode and g_localPlayer.rootNode ~= 0 then
        pcall(function()
            setWorldTranslation(g_localPlayer.rootNode, x, y, z)
            setWorldRotation(g_localPlayer.rootNode, 0, playerRotY, 0)
            teleported = true
        end)
    end
    if not teleported and g_currentMission and g_currentMission.player then
        local player = g_currentMission.player
        if player.rootNode and player.rootNode ~= 0 then
            pcall(function()
                setWorldTranslation(player.rootNode, x, y, z)
                setWorldRotation(player.rootNode, 0, playerRotY, 0)
                teleported = true
            end)
        end
    end

    -- Build status message with map coordinates
    local halfSize = (g_currentMission and g_currentMission.terrainSize or 2048) / 2
    local mapX = math.floor(x + halfSize)
    local mapZ = math.floor(z + halfSize)

    if teleported then
        local posDesc = isMoving and "behind" or "in front of"
        return true, string.format("Teleported %s %s at map(%d, %d)",
            posDesc, npc.name or "NPC", mapX, mapZ)
    else
        return false, string.format("Could not teleport. %s is at map(%d, %d) - go there manually.",
            npc.name or "NPC", mapX, mapZ)
    end
end
