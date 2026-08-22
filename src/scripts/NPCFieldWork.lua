-- =========================================================
-- NPC Field Work Pathing Module
-- =========================================================
-- Generates realistic field work patterns for NPCs:
--   - Boustrophedon (serpentine) row traversal (80% of NPCs)
--   - Perimeter walk (grumpy NPCs, 20% chance)
--   - Spot check (lazy NPCs, 20% chance)
-- Supports multi-worker coordination (max 2 per field) with
-- alternating rows (foot) or field halving (vehicle).
-- Headland transitions are simple straight walks between row
-- endpoints (~3m apart) for clean, realistic movement.
-- =========================================================

NPCFieldWork = NPCFieldWork or {}
local NPCFieldWork_mt = {__index = NPCFieldWork}

--- Constructor
function NPCFieldWork.new()
    local self = setmetatable({}, NPCFieldWork_mt)
    -- Registry: fieldId -> {npcId1, npcId2}
    self.activeWorkers = {}
    return self
end

-- =========================================================
-- Field Bounds Estimation
-- =========================================================

--- Estimate rectangular bounds from field center and area.
-- FS25 provides field.center and field.size (area in m²).
-- We approximate the field as a square.
-- @param field  Table with .center {x,z} and .size (area)
-- @return bounds table {minX, maxX, minZ, maxZ, width, height}
function NPCFieldWork:estimateBounds(field)
    if not field or not field.center then return nil end

    local area = field.size or 400
    local halfSide = math.sqrt(area) / 2
    halfSide = math.max(10, math.min(150, halfSide))  -- clamp to sane range

    return {
        minX = field.center.x - halfSide,
        maxX = field.center.x + halfSide,
        minZ = field.center.z - halfSide,
        maxZ = field.center.z + halfSide,
        width = halfSide * 2,
        height = halfSide * 2,
        centerX = field.center.x,
        centerZ = field.center.z,
    }
end

-- =========================================================
-- Multi-Worker Coordination
-- =========================================================

--- Determine max workers for a field based on its area.
-- Small (<2000m²): always 1
-- Medium (2000-8000m²): 1 default, 10% chance of 2
-- Large (>8000m²): 2
-- @param fieldArea  Field area in m²
-- @return number  1 or 2
function NPCFieldWork:getMaxWorkers(fieldArea, fieldId)
    fieldArea = fieldArea or 0
    if fieldArea < 2000 then
        return 1
    elseif fieldArea <= 8000 then
        -- Medium field: 10% chance of allowing 2 workers (cached per field)
        if fieldId then
            local key = tostring(fieldId)
            if self._maxWorkerCache == nil then self._maxWorkerCache = {} end
            if self._maxWorkerCache[key] == nil then
                self._maxWorkerCache[key] = (math.random(100) <= 10) and 2 or 1
            end
            return self._maxWorkerCache[key]
        end
        return (math.random(100) <= 10) and 2 or 1
    else
        return 2
    end
end

--- Register a worker on a field. Returns slot number (1 or 2) or nil if at capacity.
-- @param fieldId    Unique field identifier
-- @param npcId      NPC unique identifier
-- @param fieldArea  Field area in m² (for capacity calculation)
-- @return number|nil  Slot number (1 or 2) or nil if field is full
function NPCFieldWork:assignWorker(fieldId, npcId, fieldArea)
    if not fieldId or not npcId then return nil end

    local key = tostring(fieldId)

    -- Initialize registry entry if needed
    if not self.activeWorkers[key] then
        self.activeWorkers[key] = {}
    end

    local workers = self.activeWorkers[key]

    -- Check if this NPC is already assigned
    for i, id in ipairs(workers) do
        if id == npcId then
            return i  -- already assigned, return existing slot
        end
    end

    -- Check capacity
    local maxWorkers = self:getMaxWorkers(fieldArea, fieldId)
    if #workers >= maxWorkers then
        return nil  -- at capacity
    end

    -- Assign to next available slot
    table.insert(workers, npcId)
    return #workers
end

--- Unregister a worker from a field.
-- @param fieldId  Unique field identifier
-- @param npcId    NPC unique identifier
function NPCFieldWork:releaseWorker(fieldId, npcId)
    if not fieldId or not npcId then return end

    local key = tostring(fieldId)
    local workers = self.activeWorkers[key]
    if not workers then return end

    for i, id in ipairs(workers) do
        if id == npcId then
            table.remove(workers, i)
            break
        end
    end

    -- Clean up empty entries
    if #workers == 0 then
        self.activeWorkers[key] = nil
    end
end

-- =========================================================
-- Headland Turn Generation
-- =========================================================

--- Create a smooth U-turn curve between two row endpoints.
-- Uses VectorHelper.bezierQuadratic with a control point offset
-- perpendicular to the row direction.
-- @param p1x,p1z    End of current row
-- @param p2x,p2z    Start of next row
-- @param rowSpacing  Distance between rows (for control point offset)
-- @param bounds      Field bounds for clamping
-- @return table  Array of {x, z} waypoints for the turn (5 points)
function NPCFieldWork:createHeadlandTurn(p1x, p1z, p2x, p2z, rowSpacing, bounds)
    local turnPoints = {}
    local numPoints = 5

    -- Direction from p1 to p2
    local dx = p2x - p1x
    local dz = p2z - p1z

    -- Midpoint between the two row endpoints
    local midX = (p1x + p2x) / 2
    local midZ = (p1z + p2z) / 2

    -- Perpendicular offset for the control point (push outward)
    -- The turn bulges outward from the field
    local perpX, perpZ = 0, 0
    if VectorHelper and VectorHelper.getPerpendicular then
        perpX, perpZ = VectorHelper.getPerpendicular(dx, dz)
        local len = math.sqrt(perpX * perpX + perpZ * perpZ)
        if len > 0 then
            perpX = perpX / len
            perpZ = perpZ / len
        end
    end

    local offset = rowSpacing * 0.6
    local ctrlX = midX + perpX * offset
    local ctrlZ = midZ + perpZ * offset

    -- Clamp control point within field bounds (with small margin)
    if bounds then
        local margin = 2
        ctrlX = math.max(bounds.minX - margin, math.min(bounds.maxX + margin, ctrlX))
        ctrlZ = math.max(bounds.minZ - margin, math.min(bounds.maxZ + margin, ctrlZ))
    end

    -- Generate Bezier curve points
    for i = 1, numPoints do
        local t = i / (numPoints + 1)
        local bx, bz
        if VectorHelper and VectorHelper.bezierQuadratic then
            bx, bz = VectorHelper.bezierQuadratic(p1x, p1z, ctrlX, ctrlZ, p2x, p2z, t)
        else
            -- Linear fallback
            bx = p1x + (p2x - p1x) * t
            bz = p1z + (p2z - p1z) * t
        end
        table.insert(turnPoints, {x = bx, z = bz})
    end

    return turnPoints
end

-- =========================================================
-- Pattern Generators
-- =========================================================

--- Generate boustrophedon (serpentine back-and-forth) row waypoints.
-- @param bounds  Field bounds from estimateBounds()
-- @param config  Table with:
--   slot    (number) Worker slot 1 or 2
--   spacing (number) Row spacing in meters (default 3)
--   mode    (string) "foot" or "vehicle"
-- @return table  Array of {x, z} waypoints
function NPCFieldWork:generateRowPattern(bounds, config)
    if not bounds then return {} end

    config = config or {}
    local spacing = config.spacing or 3
    local slot = config.slot or 1
    local mode = config.mode or "foot"

    local waypoints = {}

    -- Determine work area based on multi-worker mode
    local workMinX = bounds.minX
    local workMaxX = bounds.maxX
    local workMinZ = bounds.minZ
    local workMaxZ = bounds.maxZ

    if slot == 2 and mode == "vehicle" then
        -- Vehicle mode: field halving — worker 2 gets right half
        workMinX = bounds.centerX
    elseif slot == 1 and mode == "vehicle" then
        -- Vehicle mode: worker 1 gets left half
        workMaxX = bounds.centerX
    end

    -- Calculate rows along Z-axis
    local fieldDepth = workMaxZ - workMinZ
    local numRows = math.floor(fieldDepth / spacing)
    numRows = math.max(1, math.min(numRows, 60))  -- cap for performance

    for row = 0, numRows - 1 do
        -- Multi-worker foot mode: alternating rows
        if mode == "foot" and config.slot == 2 then
            -- Worker 2 gets even rows (0, 2, 4...)
            if row % 2 ~= 0 then
                -- skip odd rows (those belong to worker 1)
                -- but we need to continue the loop
            else
                local rowZ = workMinZ + row * spacing + spacing * 0.5
                if row % 4 == 0 then
                    -- Even-even: go left to right
                    table.insert(waypoints, {x = workMinX, z = rowZ})
                    table.insert(waypoints, {x = workMaxX, z = rowZ})
                else
                    -- Even-odd: go right to left
                    table.insert(waypoints, {x = workMaxX, z = rowZ})
                    table.insert(waypoints, {x = workMinX, z = rowZ})
                end
            end
        elseif mode == "foot" and config.slot == 1 and self:_hasSecondWorker(config.fieldId) then
            -- Worker 1 gets odd rows (1, 3, 5...) when sharing
            if row % 2 == 0 then
                -- skip even rows (those belong to worker 2)
            else
                local rowZ = workMinZ + row * spacing + spacing * 0.5
                if (row - 1) % 4 == 0 then
                    table.insert(waypoints, {x = workMinX, z = rowZ})
                    table.insert(waypoints, {x = workMaxX, z = rowZ})
                else
                    table.insert(waypoints, {x = workMaxX, z = rowZ})
                    table.insert(waypoints, {x = workMinX, z = rowZ})
                end
            end
        else
            -- Solo worker or vehicle mode: all rows, standard boustrophedon
            local rowZ = workMinZ + row * spacing + spacing * 0.5
            if row % 2 == 0 then
                table.insert(waypoints, {x = workMinX, z = rowZ})
                table.insert(waypoints, {x = workMaxX, z = rowZ})
            else
                table.insert(waypoints, {x = workMaxX, z = rowZ})
                table.insert(waypoints, {x = workMinX, z = rowZ})
            end
        end
    end

    -- Headland turns removed: raw boustrophedon waypoints produce clean
    -- straight rows.  Row ends connect directly to the next row start
    -- (~3m apart), which looks like a natural tight turn at the headland.

    return waypoints
end

--- Check if a field has a second worker assigned.
-- @param fieldId  Field identifier
-- @return boolean
function NPCFieldWork:_hasSecondWorker(fieldId)
    if not fieldId then return false end
    local key = tostring(fieldId)
    local workers = self.activeWorkers[key]
    return workers and #workers >= 2
end

--- Generate perimeter walk pattern (grumpy NPCs — fence inspection).
-- Walks the field edges with slight inset.
-- @param bounds  Field bounds from estimateBounds()
-- @return table  Array of {x, z} waypoints
function NPCFieldWork:generatePerimeterPattern(bounds)
    if not bounds then return {} end

    local inset = 2  -- stay 2m inside field edge
    local minX = bounds.minX + inset
    local maxX = bounds.maxX - inset
    local minZ = bounds.minZ + inset
    local maxZ = bounds.maxZ - inset

    -- Walk the perimeter with intermediate points for longer edges
    local waypoints = {}
    local edgeSteps = math.max(2, math.floor(bounds.width / 15))

    -- Bottom edge (minZ): left to right
    for i = 0, edgeSteps do
        local t = i / edgeSteps
        table.insert(waypoints, {x = minX + (maxX - minX) * t, z = minZ})
    end
    -- Right edge (maxX): bottom to top
    for i = 1, edgeSteps do
        local t = i / edgeSteps
        table.insert(waypoints, {x = maxX, z = minZ + (maxZ - minZ) * t})
    end
    -- Top edge (maxZ): right to left
    for i = 1, edgeSteps do
        local t = i / edgeSteps
        table.insert(waypoints, {x = maxX - (maxX - minX) * t, z = maxZ})
    end
    -- Left edge (minX): top to bottom
    for i = 1, edgeSteps do
        local t = i / edgeSteps
        table.insert(waypoints, {x = minX, z = maxZ - (maxZ - minZ) * t})
    end

    return waypoints
end

--- Generate spot check pattern (lazy NPCs — random inspection points).
-- Picks random points within the field and sorts by proximity for
-- a reasonable walking order.
-- @param bounds  Field bounds from estimateBounds()
-- @return table  Array of {x, z} waypoints
function NPCFieldWork:generateSpotcheckPattern(bounds)
    if not bounds then return {} end

    local waypoints = {}
    local numPoints = math.max(4, math.floor(bounds.width / 10))
    numPoints = math.min(numPoints, 8)

    local margin = 3
    for _ = 1, numPoints do
        table.insert(waypoints, {
            x = bounds.minX + margin + math.random() * (bounds.width - margin * 2),
            z = bounds.minZ + margin + math.random() * (bounds.height - margin * 2),
        })
    end

    -- Sort by distance from first point for a more natural walking order
    if #waypoints > 1 then
        local current = waypoints[1]
        for i = 2, #waypoints do
            local bestIdx = i
            local bestDist = 999999
            for j = i, #waypoints do
                local dx = waypoints[j].x - current.x
                local dz = waypoints[j].z - current.z
                local d = dx * dx + dz * dz
                if d < bestDist then
                    bestDist = d
                    bestIdx = j
                end
            end
            -- Swap
            waypoints[i], waypoints[bestIdx] = waypoints[bestIdx], waypoints[i]
            current = waypoints[i]
        end
    end

    return waypoints
end

-- =========================================================
-- Main Entry Point
-- =========================================================

--- Get a work pattern for an NPC on a field.
-- Selects pattern based on personality (80% boustrophedon, 20% personality override).
-- Manages worker slot assignment for multi-worker coordination.
-- @param npc    NPC data table with .personality (string), .id or .uniqueId
-- @param field  Field data table with .center {x,z}, .size (area), .id
-- @return table  Array of {x, z} waypoints, or nil on failure
-- @return number|nil  Worker slot (1 or 2)
function NPCFieldWork:getWorkPattern(npc, field)
    if not npc or not field then return nil, nil end

    local bounds = self:estimateBounds(field)
    if not bounds then return nil, nil end

    local personality = npc.personality or "hardworking"
    local npcId = npc.uniqueId or npc.id or npc.name or tostring(npc)
    local fieldId = field.id or tostring(field.center.x) .. "_" .. tostring(field.center.z)
    local fieldArea = field.size or 0

    -- 20% chance for personality-driven pattern override
    local roll = math.random(100)
    if roll <= 20 and personality == "grumpy" then
        return self:generatePerimeterPattern(bounds), nil
    elseif roll <= 20 and (personality == "lazy" or personality == "social") then
        return self:generateSpotcheckPattern(bounds), nil
    end

    -- Default: boustrophedon rows (80% of the time, or 100% for non-grumpy/lazy)
    local slot = self:assignWorker(fieldId, npcId, fieldArea)
    if not slot then
        -- Field at capacity — fall back to spotcheck near the field
        return self:generateSpotcheckPattern(bounds), nil
    end

    -- Determine if foot or vehicle mode
    local mode = "foot"
    local spacing = 3
    if npc.currentVehicle then
        mode = "vehicle"
        spacing = 6
    end

    local waypoints = self:generateRowPattern(bounds, {
        slot = slot,
        spacing = spacing,
        mode = mode,
        fieldId = fieldId,
    })

    -- Store field ID on NPC for later release
    npc._fieldWorkFieldId = fieldId

    return waypoints, slot
end
