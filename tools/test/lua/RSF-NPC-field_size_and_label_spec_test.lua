-- RSF-NPC-field_size_and_label_spec_test.lua
--
-- PLAYER-REPORTS row 93 (jamesw8439, "NPC going around in circles / figure of 8
-- mid-field"; the roster reading "working indoors" on a tractor), Bob's intake of
-- 2026-09-24. Two defects, one PR, design origin none:
--
--   1. THE FIELD SIZE. The engine's Field has no `fieldArea` table (Field.new,
--      Field.lua:12-30); its area is areaHa (:20, :60, getAreaHa :138) and its centre
--      the label point posX/posZ. findNearestField read a member that never existed,
--      so every field was one square metre, NPCFieldWork clamped that to a 20 m
--      square around the label point, and a tractor drew three short rows in a loop
--      that crossed itself. The record now carries the real area in square metres and
--      the field's polygon extent; the work square is clipped to the extent and its
--      rows kept inside the polygon; the legacy patterns' half-size is clamped as the
--      zigzag path's is and to the extent; the four dead reads are gone.
--   2. THE LABEL. updateNPCState rewrote currentAction from the schedule every tick,
--      exempting only gathering, greeting and stepping aside, so a person on field
--      work showed the schedule's label. The overwrite now stands down while the
--      field-work code's own flags are set (activeAIJob, usingComboFieldWork,
--      _fieldWorkFieldId), never by aiState.
--
-- THE ENTRY-POINT BAR IS GROUP A. Production's selector, NPCSystem:findNearestField,
-- runs over an engine-shaped g_fieldManager (fields with areaHa, getAreaHa, posX and
-- posZ, polygon nodes read through getWorldTranslation, a nested farmland) with the
-- real land admission over a native-shaped farmland manager; the pattern module and
-- the AI are the real ones, built by their own constructors; nothing hand-fills a
-- record, a bound, a waypoint or a label.
--
-- MAINTENANCE row 109 (Bob's cold verdict on #117): the grumpy perimeter walk went
-- round the clipped work square's corners, so on an L or a U it cut across the notch
-- or the gap. It now walks the field polygon's own edges 2 m inside. Group P drives it
-- from the same selector record through getWorkPattern; its rows P1 to P4 are the
-- entry-point bar for that walk.
--
--!load: src/utils/NPCFarmIdentity.lua, src/utils/NPCLandAdmission.lua, src/scripts/NPCFavorSystem.lua, src/scripts/NPCFavorRecovery.lua, src/events/NPCInteractionEvent.lua, src/NPCSystem.lua, src/scripts/NPCFieldWork.lua, src/scripts/NPCAI.lua

local A = NPCLandAdmission

-- ── engine fixture: the farmland manager and farms, as the F206 bar shapes them ──
FarmlandManager = FarmlandManager or {}
FarmlandManager.NO_OWNER_FARM_ID = 0
FarmlandManager.NOT_BUYABLE_FARM_ID = 255
FarmManager = FarmManager or {}
FarmManager.SPECTATOR_FARM_ID = 0
FarmManager.SINGLEPLAYER_FARM_ID = 1
FarmManager.MAX_FARM_ID = 8
FarmManager.GUIDED_TOUR_FARM_ID = 14
FarmManager.INVALID_FARM_ID = 15
local W = { mapLoaded = true, samples = {}, owners = {} }
local function key(x, z) return tostring(x) .. ":" .. tostring(z) end
g_farmlandManager = setmetatable({}, { __index = function(_, k) if k == "localMap" then return W.mapLoaded and "map" or nil end return nil end })
g_farmlandManager.getFarmlandIdAtWorldPosition = function(_, x, z)
    if not W.mapLoaded then return FarmlandManager.NO_OWNER_FARM_ID end
    return W.samples[key(x, z)] or FarmlandManager.NO_OWNER_FARM_ID
end
g_farmlandManager.getFarmlandOwner = function(_, id)
    if id == nil or W.owners[id] == nil then return FarmlandManager.NO_OWNER_FARM_ID end
    return W.owners[id]
end
local LIVE_FARMS = { [1] = { farmId = 1, players = { { id = 1 } }, userIdToPlayer = {}, activeUsers = {} } }
g_farmManager = { getFarmById = function(_, id) return LIVE_FARMS[id] end }
g_currentMission = g_currentMission or {}
g_currentMission.getFarmId = function() return 1 end
g_currentMission.terrainRootNode = nil
-- Unowned working land: parcel 10, owner nobody.
W.owners[10] = 0

-- Nodes are tables carrying their world position (the engine reads a field's polygon
-- through getWorldTranslation, MathUtil.lua:825-830).
function getWorldTranslation(node)
    if type(node) == "table" then return node.x or 0, node.y or 0, node.z or 0 end
    return 0, 0, 0
end

--- An engine-shaped Field (Field.new, Field.lua:12-30): the label point, the area in
--- hectares behind getAreaHa, and polygon nodes behind getPolygonPoints. The parcel
--- sample is placed at the label point so the admission answers for it.
local function engineField(parcelId, cx, cz, areaHa, polygon, fieldId)
    W.samples[key(cx, cz)] = parcelId
    local nodes = {}
    for i, p in ipairs(polygon or {}) do nodes[i] = { x = p[1], y = 0, z = p[2] } end
    local f = { fieldId = fieldId or 1, farmland = { id = parcelId }, posX = cx, posZ = cz, areaHa = areaHa, polygonPoints = nodes }
    f.getAreaHa = function(self) return self.areaHa end
    f.getPolygonPoints = function(self) return self.polygonPoints end
    return f
end
--- A square of side `side` around (cx, cz).
local function square(cx, cz, side)
    local h = side / 2
    return { { cx - h, cz - h }, { cx + h, cz - h }, { cx + h, cz + h }, { cx - h, cz + h } }
end
--- A rectangle of width w (x) and depth d (z) around (cx, cz).
local function rect(cx, cz, w, d)
    return { { cx - w / 2, cz - d / 2 }, { cx + w / 2, cz - d / 2 }, { cx + w / 2, cz + d / 2 }, { cx - w / 2, cz + d / 2 } }
end

-- The system: production's selector on a partial system (as the F206 bar drives it),
-- the real pattern module and the real AI from their own constructors.
local function newSys()
    local s = setmetatable({}, { __index = NPCSystem })
    s.settings = { debugMode = false, showNotifications = false }
    s.activeNPCs = {}
    s.scheduler = { hour = 12, activity = "indoor_work",
        getCurrentHour = function(self) return self.hour end, getCurrentMinute = function() return 0 end,
        getActivityForCurrentTime = function(self) return self.activity end,
        getActivityDisplayName = function(_, a) return ({ indoor_work = "working indoors", field_maintenance = "working the field" })[a] or a end,
        getWeatherFactor = function() return 1 end }
    s.fieldWork = NPCFieldWork.new()
    s.aiSystem = NPCAI.new(s)
    s.showNotification = function() end
    s.playerPositionValid = false
    return s
end
local function num(x)
    if type(x) ~= "number" then return tostring(x) end
    local r = math.floor(x * 100 + 0.5) / 100
    if r == math.floor(r) then return string.format("%d", math.floor(r)) end
    return tostring(r)
end
local function allInside(points, minX, maxX, minZ, maxZ)
    for _, p in ipairs(points) do
        if p.x < minX - 1e-6 or p.x > maxX + 1e-6 or p.z < minZ - 1e-6 or p.z > maxZ + 1e-6 then return false end
    end
    return #points > 0
end
local function anyInside(points, minX, maxX, minZ, maxZ)
    for _, p in ipairs(points) do
        if p.x > minX and p.x < maxX and p.z > minZ and p.z < maxZ then return true end
    end
    return false
end
local function group(name, fn)
    local ok, err = pcall(fn)
    if not ok then T.ok(name .. " [group raised: " .. tostring(err) .. "]", false) end
end

-- ══════════════════════════════════════════════════════════════════════════
-- A. THE RECORD: THE ENGINE'S OWN AREA AND EXTENT (the entry-point bar)
-- ══════════════════════════════════════════════════════════════════════════
group("A", function()
    local sys = newSys()
    -- A 3 ha square field, 173.2 m a side, labelled at (100, 100).
    local side = math.sqrt(30000)
    g_fieldManager = { fields = { engineField(10, 100, 100, 3, square(100, 100, side), 7) } }
    local rec = sys:findNearestField(90, 90, 1)
    T.ok("A1 [reached] the selector admits the unowned field", rec ~= nil and rec.farmlandId == 10)
    T.eq("A2 the record's size is the engine's hectares in square metres", rec.size, 30000)
    T.eq("A3 the record's extent is the polygon's bounding box, with the polygon on it",
        num(rec.extent.minX) .. "/" .. num(rec.extent.maxX) .. "/" .. num(rec.extent.minZ) .. "/" .. num(rec.extent.maxZ) .. "/" .. #rec.extent.polygon,
        num(100 - side / 2) .. "/" .. num(100 + side / 2) .. "/" .. num(100 - side / 2) .. "/" .. num(100 + side / 2) .. "/4")
    T.eq("A4 the centre is the label point", rec.center.x .. "/" .. rec.center.z, "100/100")

    -- Guards: a field with no finite positive area carries no size (the consumers
    -- keep their own defaults), and a field the getter cannot answer for uses the
    -- member.
    g_fieldManager = { fields = { engineField(10, 100, 100, 0, square(100, 100, 40)) } }
    T.eq("A5 an area of zero hectares gives no size, not zero", tostring(sys:findNearestField(90, 90, 1).size), "nil")
    local nanField = engineField(10, 100, 100, 0 / 0, square(100, 100, 40))
    g_fieldManager = { fields = { nanField } }
    T.eq("A6 a NaN area gives no size", tostring(sys:findNearestField(90, 90, 1).size), "nil")
    local memberOnly = engineField(10, 100, 100, 2, square(100, 100, 40))
    memberOnly.getAreaHa = nil
    g_fieldManager = { fields = { memberOnly } }
    T.eq("A7 with no getter the areaHa member is read", sys:findNearestField(90, 90, 1).size, 20000)
    local noPolygon = engineField(10, 100, 100, 2, {})
    g_fieldManager = { fields = { noPolygon } }
    T.eq("A8 a field with fewer than three polygon points carries no extent", tostring(sys:findNearestField(90, 90, 1).extent), "nil")

    -- DIFFERENCE: a field shaped like the old fixture, a `fieldArea` table and no
    -- label point, is what no engine field looks like; the selector no longer reads it
    -- and, with no centre, rejects it.
    W.samples[key(100, 100)] = 10
    g_fieldManager = { fields = { { fieldId = 1, farmland = { id = 10 }, fieldArea = { fieldCenterX = 100, fieldCenterZ = 100, fieldArea = 30000 } } } }
    T.eq("A9 DIFFERENCE: the dead fieldArea read is gone; a field with only that table has no centre and is not selected", tostring(sys:findNearestField(90, 90, 1)), "nil")
end)

-- ══════════════════════════════════════════════════════════════════════════
-- B. THE WORK SQUARE IS CLIPPED TO THE FIELD
-- ══════════════════════════════════════════════════════════════════════════
group("B", function()
    local sys = newSys()
    local side = math.sqrt(30000)
    g_fieldManager = { fields = { engineField(10, 100, 100, 3, square(100, 100, side)) } }
    local rec = sys:findNearestField(90, 90, 1)
    local b = sys.fieldWork:estimateBounds(rec)
    T.eq("B1 a 3 ha square field: the square around the label point is the field itself, 173 m a side",
        num(b.width) .. "/" .. num(b.height) .. "/" .. num(b.minX) .. "/" .. num(b.maxX), "173.21/173.21/13.4/186.6")
    -- A 50 by 600 m strip (3 ha): the 173 m square would reach 60 m past each edge.
    g_fieldManager = { fields = { engineField(10, 100, 100, 3, rect(100, 100, 50, 600)) } }
    rec = sys:findNearestField(90, 90, 1)
    b = sys.fieldWork:estimateBounds(rec)
    T.eq("B2 a 50 by 600 m strip: the square is clipped to the strip's width and keeps its own depth", num(b.minX) .. "/" .. num(b.maxX) .. "/" .. num(b.width) .. "/" .. num(b.height), "75/125/50/173.21")
    -- DIFFERENCE: without the extent the square spills 60 m either side.
    local spilled = sys.fieldWork:estimateBounds({ center = rec.center, size = rec.size })
    T.eq("B3 DIFFERENCE: the same record with no extent spills 61.6 m past each edge of the strip", num(spilled.minX) .. "/" .. num(spilled.maxX), "13.4/186.6")
    -- 30 ha: the half-side clamps at 150 m inside a 547 m field.
    g_fieldManager = { fields = { engineField(10, 100, 100, 30, square(100, 100, math.sqrt(300000))) } }
    rec = sys:findNearestField(90, 90, 1)
    b = sys.fieldWork:estimateBounds(rec)
    T.eq("B4 a 30 ha field clamps the work square at 300 m a side, inside the field", num(b.width) .. "/" .. num(b.height) .. "/" .. tostring(b.minX >= rec.extent.minX and b.maxX <= rec.extent.maxX), "300/300/true")
    T.eq("B5 the polygon rides on the bounds for the row generator", #b.polygon, 4)
end)

-- ══════════════════════════════════════════════════════════════════════════
-- C. THE ROWS STAY ON THE FIELD
-- ══════════════════════════════════════════════════════════════════════════
group("C", function()
    local sys = newSys()
    local side = math.sqrt(30000)
    g_fieldManager = { fields = { engineField(10, 100, 100, 3, square(100, 100, side), 7) } }
    local rec = sys:findNearestField(90, 90, 1)
    math.randomseed(7)
    local origRandom = math.random
    math.random = function(n, m) if n == 100 and m == nil then return 50 end if n == nil then return origRandom() end if m == nil then return origRandom(n) end return origRandom(n, m) end
    -- The reporter's case: a tractor (vehicle mode, 6 m spacing) on a 3 ha field.
    local tractor = { id = 1, personality = "hardworking", currentVehicle = {} }
    local wps, slot = sys.fieldWork:getWorkPattern(tractor, rec)
    T.eq("C1 a tractor on a 3 ha field gets 28 rows of its half of the field, 56 waypoints, not 3 rows of a 20 m square",
        #wps .. "/" .. tostring(slot), "56/1")
    T.eq("C2 every waypoint lies inside the field's extent", tostring(allInside(wps, rec.extent.minX, rec.extent.maxX, rec.extent.minZ, rec.extent.maxZ)), "true")
    T.eq("C3 and the rows are the field's rows, 86.6 m long (the worker's half), not 20 m", num(math.abs(wps[2].x - wps[1].x)), "86.6")
    -- DIFFERENCE: the old record (size 1, no extent) gives the figure of 8: three rows
    -- of a 20 m square around the label point.
    sys.fieldWork:releaseWorker(rec.id, 1)
    local old = sys.fieldWork:getWorkPattern({ id = 1, personality = "hardworking", currentVehicle = {} }, { id = 7, center = rec.center, size = 1 })
    T.eq("C4 DIFFERENCE: the old one-square-metre record gives three 10 m rows in a 20 m square", #old .. "/" .. num(math.abs(old[2].x - old[1].x)), "6/10")
    sys.fieldWork:releaseWorker(7, 1)

    -- The strip on foot: 3 m rows, each 50 m long, none off the strip.
    g_fieldManager = { fields = { engineField(10, 100, 100, 3, rect(100, 100, 50, 600), 8) } }
    rec = sys:findNearestField(90, 90, 1)
    local walker = { id = 2, personality = "hardworking" }
    wps = sys.fieldWork:getWorkPattern(walker, rec)
    T.eq("C5 on a 50 m strip every row stays on the strip", tostring(allInside(wps, 75, 125, rec.extent.minZ, rec.extent.maxZ)) .. "/" .. num(math.abs(wps[2].x - wps[1].x)), "true/50")
    sys.fieldWork:releaseWorker(rec.id, 2)

    -- An L-shaped field: a 100 m square with its north-east 50 m quarter missing.
    -- Rows through the missing quarter are clipped to the western half; no waypoint
    -- lands in the notch.
    local L = { { 50, 50 }, { 150, 50 }, { 150, 100 }, { 100, 100 }, { 100, 150 }, { 50, 150 } }
    g_fieldManager = { fields = { engineField(10, 75, 75, 0.75, L, 9) } }
    rec = sys:findNearestField(70, 70, 1)
    local w3 = { id = 3, personality = "hardworking" }
    wps = sys.fieldWork:getWorkPattern(w3, rec)
    T.eq("C6 an L-shaped field: rows are clipped to the polygon, none in the missing quarter, and every row stays inside the L's box",
        tostring(anyInside(wps, 100, 150, 100, 150)) .. "/" .. tostring(allInside(wps, 50, 150, 50, 150)) .. "/" .. tostring(#wps > 20), "false/true/true")
    local lpoly = rec.extent.polygon
    T.eq("C7 point in polygon: inside the L, in the notch, outside", tostring(NPCFieldWork.pointInPolygon(75, 125, lpoly)) .. "/" .. tostring(NPCFieldWork.pointInPolygon(125, 125, lpoly)) .. "/" .. tostring(NPCFieldWork.pointInPolygon(200, 200, lpoly)), "true/false/false")
    sys.fieldWork:releaseWorker(rec.id, 3)

    -- A spot-check pattern stays inside the L too (the lazy roll).
    local lazy = { id = 4, personality = "lazy" }
    math.random = function(n, m) if n == 100 and m == nil then return 10 end if n == nil then return origRandom() end if m == nil then return origRandom(n) end return origRandom(n, m) end
    local spots = sys.fieldWork:getWorkPattern(lazy, rec)
    T.eq("C8 a spot-check pattern draws its points inside the polygon", tostring(anyInside(spots, 100, 150, 100, 150)) .. "/" .. tostring(#spots >= 4), "false/true")
    -- Every draw aimed at the notch: the filter retries and then takes the box centre.
    sys.fieldWork:releaseWorker(rec.id, 4)
    math.random = function(n, m) if n == 100 and m == nil then return 10 end if n == nil then return 0.95 end if m == nil then return origRandom(n) end return origRandom(n, m) end
    local aimed = sys.fieldWork:getWorkPattern({ id = 5, personality = "lazy" }, rec)
    T.eq("C8b a draw that lands in the notch every time is refused ten times and the point falls to the box centre, inside the L", tostring(anyInside(aimed, 100, 150, 100, 150)) .. "/" .. tostring(#aimed >= 4) .. "/" .. tostring(NPCFieldWork.pointInPolygon(aimed[1].x, aimed[1].z, lpoly)), "false/true/true")
    sys.fieldWork:releaseWorker(rec.id, 5)
    math.random = origRandom
    sys.fieldWork:releaseWorker(rec.id, 4)

    -- A U-shaped field: a 100 m square with a 40 m wide gap cut in from the south
    -- up to z 120, two arms x 50..80 and 120..150 joined across the top. Its label
    -- point is in the top bar at (100, 135), so the work square around it reaches
    -- both arms. A row through the arms is two stretches, and the gap between them
    -- is never crossed.
    local U = { { 50, 50 }, { 80, 50 }, { 80, 120 }, { 120, 120 }, { 120, 50 }, { 150, 50 }, { 150, 150 }, { 50, 150 } }
    g_fieldManager = { fields = { engineField(10, 100, 135, 0.72, U, 12) } }
    rec = sys:findNearestField(95, 130, 1)
    local wu = { id = 7, personality = "hardworking" }
    wps = sys.fieldWork:getWorkPattern(wu, rec)
    local gapHit, twoStretches, midpoints = false, 0, 0
    for i = 1, #wps - 1, 2 do
        local a, b = wps[i], wps[i + 1]
        local mx = (a.x + b.x) * 0.5
        if a.z < 120 and mx > 80 and mx < 120 then gapHit = true end
        if a.z < 120 then midpoints = midpoints + 1 end
    end
    local rowsBelow = {}
    for i = 1, #wps - 1, 2 do if wps[i].z < 120 then rowsBelow[wps[i].z] = (rowsBelow[wps[i].z] or 0) + 1 end end
    for _, n in pairs(rowsBelow) do if n == 2 then twoStretches = twoStretches + 1 end end
    T.eq("C10 a U-shaped field: each of the nine rows through the arms is two stretches, no stretch's midpoint lies in the gap, and every waypoint stays inside the U's box",
        tostring(gapHit) .. "/" .. tostring(twoStretches) .. "/" .. tostring(allInside(wps, 50, 150, 50, 150)), "false/9/true")
    sys.fieldWork:releaseWorker(rec.id, 7)
    -- A spot-check whose every draw lands in the gap falls to the label point, in the
    -- west arm, not to the box centre in the gap.
    math.random = function(n, m) if n == 100 and m == nil then return 10 end if n == nil then return 0.4 end if m == nil then return origRandom(n) end return origRandom(n, m) end
    local gapSpots = sys.fieldWork:getWorkPattern({ id = 8, personality = "lazy" }, rec)
    math.random = origRandom
    T.eq("C11 a spot-check aimed at the gap of a U falls to the field's label point inside the top bar, never to the box centre in the gap",
        tostring(anyInside(gapSpots, 80, 120, 50, 120)) .. "/" .. tostring(#gapSpots >= 4) .. "/" .. tostring(NPCFieldWork.pointInPolygon(gapSpots[1].x, gapSpots[1].z, rec.extent.polygon)) .. "/" .. num(gapSpots[1].x) .. "," .. num(gapSpots[1].z), "false/true/true/100,135")
    sys.fieldWork:releaseWorker(rec.id, 8)
    T.eq("C12 clipRowToPolygon on the U at z 100 gives the two stretches, exact at the row's ends, and at z 130 one stretch across the top",
        (function()
            local function show(segs)
                local parts = {}
                for i = 1, #segs do parts[i] = num(segs[i][1]) .. "-" .. num(segs[i][2]) end
                return #segs .. ":" .. table.concat(parts, ",")
            end
            return show(NPCFieldWork.clipRowToPolygon(100, 50, 150, rec.extent.polygon, 1.5)) .. "/" .. show(NPCFieldWork.clipRowToPolygon(130, 50, 150, rec.extent.polygon, 1.5))
        end)(), "2:50-78.5,120.5-150/1:50-150")

    -- Two workers on a large field: the code's written intent, now reachable.
    g_fieldManager = { fields = { engineField(10, 100, 100, 3, square(100, 100, side), 11) } }
    rec = sys:findNearestField(90, 90, 1)
    local _, sA = sys.fieldWork:getWorkPattern({ id = 5, personality = "hardworking" }, rec)
    local _, sB = sys.fieldWork:getWorkPattern({ id = 6, personality = "hardworking" }, rec)
    T.eq("C9 a 3 ha field admits two workers (above 8,000 square metres), which a one-metre field never did", tostring(sA) .. "/" .. tostring(sB), "1/2")
end)

-- ══════════════════════════════════════════════════════════════════════════
-- D. THE LEGACY PATTERNS' HALF-SIZE IS CLAMPED
-- ══════════════════════════════════════════════════════════════════════════
group("D", function()
    local sys = newSys()
    local ai = sys.aiSystem
    local function farthest(path, cx, cz)
        local m = 0
        for _, p in ipairs(path) do m = math.max(m, math.abs(p.x - cx), math.abs(p.z - cz)) end
        return m
    end
    -- 30 ha: the old arithmetic reached 0.4 * 547 = 219 m; the clamp is 100 m.
    g_fieldManager = { fields = { engineField(10, 100, 100, 30, square(100, 100, math.sqrt(300000))) } }
    local rec = sys:findNearestField(90, 90, 1)
    local npc = { id = 1, personality = "hardworking", position = { x = 100, y = 0, z = 100 }, assignedField = rec, movementSpeed = 3 }
    ai:initFieldWorkLegacy(npc)
    T.eq("D1 the legacy rows on a 30 ha field reach at most 100 m from the centre", num(farthest(npc.fieldWorkPath, 100, 100)), "100")
    T.eq("D2 DIFFERENCE: the old arithmetic reached 219 m", num(math.sqrt(300000) * 0.4), "219.09")
    -- The strip: the extent's room (25 m in x) binds.
    g_fieldManager = { fields = { engineField(10, 100, 100, 3, rect(100, 100, 50, 600)) } }
    rec = sys:findNearestField(90, 90, 1)
    npc = { id = 1, personality = "generous", position = { x = 100, y = 0, z = 100 }, assignedField = rec, movementSpeed = 3 }
    ai:initFieldWorkLegacy(npc)
    T.eq("D3 on the strip the spiral stays within the strip's 25 m either side", tostring(farthest(npc.fieldWorkPath, 100, 100) <= 25.001), "true")
    -- No extent: the 15..100 clamp alone.
    npc = { id = 1, personality = "grumpy", position = { x = 100, y = 0, z = 100 }, assignedField = { center = { x = 100, z = 100 }, size = 300000 }, movementSpeed = 3 }
    ai:initFieldWorkLegacy(npc)
    T.eq("D4 with no extent the clamp alone holds the perimeter at 100 m", num(farthest(npc.fieldWorkPath, 100, 100)), "100")
end)

-- ══════════════════════════════════════════════════════════════════════════
-- P. THE PERIMETER WALKS THE FIELD'S OWN EDGES (MAINTENANCE row 109)
-- ══════════════════════════════════════════════════════════════════════════
group("P", function()
    local sys = newSys()
    local origRandom = math.random
    -- The personality roll at 10 of 100: a grumpy person takes the perimeter.
    math.random = function(n, m) if n == 100 and m == nil then return 10 end if n == nil then return origRandom() end if m == nil then return origRandom(n) end return origRandom(n, m) end
    -- Every leg between two waypoints, sampled each metre, inside the polygon.
    local function legsInside(path, polygon)
        for i = 1, #path - 1 do
            local a, b = path[i], path[i + 1]
            local steps = math.max(1, math.ceil(math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)))
            for s = 0, steps do
                local t = s / steps
                if not NPCFieldWork.pointInPolygon(a.x + (b.x - a.x) * t, a.z + (b.z - a.z) * t, polygon) then return false end
            end
        end
        return #path > 1
    end
    -- The least distance from any waypoint to any edge of the polygon.
    local function nearest(path, polygon)
        local best = math.huge
        for _, p in ipairs(path) do
            for i = 1, #polygon do
                local a, b = polygon[i], polygon[i % #polygon + 1]
                local dx, dz = b.x - a.x, b.z - a.z
                local t = math.max(0, math.min(1, ((p.x - a.x) * dx + (p.z - a.z) * dz) / (dx * dx + dz * dz)))
                local ex, ez = a.x + dx * t - p.x, a.z + dz * t - p.z
                best = math.min(best, math.sqrt(ex * ex + ez * ez))
            end
        end
        return best
    end
    local function has(path, x, z)
        for _, p in ipairs(path) do if math.abs(p.x - x) < 1e-6 and math.abs(p.z - z) < 1e-6 then return true end end
        return false
    end
    local function closed(path) return #path > 1 and path[1].x == path[#path].x and path[1].z == path[#path].z end

    -- The L of C6: the walk goes round the missing quarter, turning at its inner
    -- corner (100, 100) 2 m inside both edges.
    local L = { { 50, 50 }, { 150, 50 }, { 150, 100 }, { 100, 100 }, { 100, 150 }, { 50, 150 } }
    g_fieldManager = { fields = { engineField(10, 75, 75, 0.75, L, 9) } }
    local rec = sys:findNearestField(70, 70, 1)
    local walk = sys.fieldWork:getWorkPattern({ id = 1, personality = "grumpy" }, rec)
    T.eq("P1 an L-shaped field: every leg of the grumpy walk, sampled each metre, stays inside the L, and the walk turns at the inner corner (98, 98)",
        tostring(legsInside(walk, rec.extent.polygon)) .. "/" .. tostring(has(walk, 98, 98)), "true/true")
    T.eq("P2 every waypoint is 2 m inside the L's nearest edge, the corners included, and the walk ends where it began",
        num(nearest(walk, rec.extent.polygon)) .. "/" .. tostring(closed(walk)), "2/true")
    -- The same L with its points in the other order.
    local Lcw = {}
    for i = #L, 1, -1 do Lcw[#Lcw + 1] = L[i] end
    g_fieldManager = { fields = { engineField(10, 75, 75, 0.75, Lcw, 13) } }
    rec = sys:findNearestField(70, 70, 1)
    local back = sys.fieldWork:getWorkPattern({ id = 2, personality = "grumpy" }, rec)
    T.eq("P3 the same L with its points in the other winding is walked 2 m inside too, round the notch",
        tostring(legsInside(back, rec.extent.polygon)) .. "/" .. num(nearest(back, rec.extent.polygon)) .. "/" .. tostring(has(back, 98, 98)), "true/2/true")

    -- The U of C10: the walk goes up the west arm's inner side and down the east
    -- arm's, round the gap.
    local U = { { 50, 50 }, { 80, 50 }, { 80, 120 }, { 120, 120 }, { 120, 50 }, { 150, 50 }, { 150, 150 }, { 50, 150 } }
    g_fieldManager = { fields = { engineField(10, 100, 135, 0.72, U, 12) } }
    rec = sys:findNearestField(95, 130, 1)
    local uwalk = sys.fieldWork:getWorkPattern({ id = 3, personality = "grumpy" }, rec)
    local upWest, downEast = 0, 0
    for _, p in ipairs(uwalk) do
        if math.abs(p.x - 78) < 1e-6 and p.z < 100 then upWest = upWest + 1 end
        if math.abs(p.x - 122) < 1e-6 and p.z < 100 then downEast = downEast + 1 end
    end
    T.eq("P4 a U-shaped field: the walk runs along both sides of the gap (x 78 and x 122 below z 100), and every leg stays inside the U",
        upWest .. "/" .. downEast .. "/" .. tostring(legsInside(uwalk, rec.extent.polygon)), "4/4/true")

    -- A square field with a lane 1.5 m wide running east: 2 m in from a lane edge is
    -- past the other edge, so the lane's points take half the inset.
    local lane = { { 50, 50 }, { 100, 50 }, { 100, 70 }, { 140, 70 }, { 140, 71.5 }, { 100, 71.5 }, { 100, 100 }, { 50, 100 } }
    g_fieldManager = { fields = { engineField(10, 75, 75, 0.256, lane, 14) } }
    rec = sys:findNearestField(70, 70, 1)
    local lwalk = sys.fieldWork:getWorkPattern({ id = 4, personality = "grumpy" }, rec)
    local allIn, onLane = #lwalk > 0, 0
    for _, p in ipairs(lwalk) do
        if not NPCFieldWork.pointInPolygon(p.x, p.z, rec.extent.polygon) then allIn = false end
        if p.x > 100 and (math.abs(p.z - 71) < 1e-6 or math.abs(p.z - 70.5) < 1e-6) then onLane = onLane + 1 end
    end
    T.eq("P5 a lane narrower than twice the inset: its points take half the inset, and every waypoint lies inside the field",
        tostring(allIn) .. "/" .. onLane, "true/6")
    math.random = origRandom

    -- No polygon: the work square's walk, as before.
    local plain = sys.fieldWork:generatePerimeterPattern(sys.fieldWork:estimateBounds({ center = { x = 100, z = 100 }, size = 400 }))
    local lo, hi = math.huge, -math.huge
    for _, p in ipairs(plain) do lo, hi = math.min(lo, p.x), math.max(hi, p.x) end
    T.eq("P6 UNCHANGED: with no polygon the walk is the work square 2 m inside, nine waypoints", num(lo) .. "/" .. num(hi) .. "/" .. #plain, "92/108/9")
end)

-- ══════════════════════════════════════════════════════════════════════════
-- E. THE FIELD-WORK LABEL SURVIVES THE SCHEDULE WHILE THE WORK IS ON
-- ══════════════════════════════════════════════════════════════════════════
group("E", function()
    local sys = newSys()
    local ai = sys.aiSystem
    local function person(label)
        return { id = 1, name = "Alex", personality = "hardworking", aiState = ai.STATES.RESTING, isSleeping = false,
            position = { x = 0, y = 0, z = 0 }, homePosition = { x = 0, y = 0, z = 0 }, rotation = { y = 0 },
            needs = { energy = 100, hunger = 0, social = 50, workSatisfaction = 50 }, currentAction = label }
    end
    -- The AI job: the flag is set by the field-work code; the state is whatever it was.
    local npc = person("field work (AI)")
    npc.activeAIJob = {}
    ai:updateNPCState(npc, 0.016)
    ai:updateNPCState(npc, 0.016)
    T.eq("E1 on an AI job the field-work label survives the schedule's tick", npc.currentAction, "field work (AI)")
    npc.activeAIJob = nil
    ai:updateNPCState(npc, 0.016)
    T.eq("E2 the tick after the job clears restores the schedule's label", npc.currentAction, "working indoors")
    -- The combo fallback and a pattern slot are the same.
    npc = person("field work")
    npc.usingComboFieldWork = true
    ai:updateNPCState(npc, 0.016)
    T.eq("E3 on the combo fallback the label survives", npc.currentAction, "field work")
    npc.usingComboFieldWork = false
    ai:updateNPCState(npc, 0.016)
    T.eq("E4 and returns to the schedule when it ends", npc.currentAction, "working indoors")
    npc = person("field work")
    npc._fieldWorkFieldId = "7"
    ai:updateNPCState(npc, 0.016)
    T.eq("E5 with a pattern slot held the label survives", npc.currentAction, "field work")
    -- DIFFERENCE: the test is the flags, not the state. An ordinary scheduled worker
    -- in the WORKING state with no flag takes the schedule's label as before.
    npc = person("idle")
    npc.aiState = ai.STATES.WORKING
    npc.workTimer = 0
    ai:updateNPCState(npc, 0.016)
    T.eq("E6 DIFFERENCE: an ordinary worker in the WORKING state with no field-work flag still shows the schedule's label", npc.currentAction, "working indoors")
    -- The existing exemptions stand.
    npc = person("greeting")
    npc.greetingTimer = 5
    ai:updateNPCState(npc, 0.016)
    T.eq("E7 a greeting in progress is still not overwritten", npc.currentAction, "greeting")
end)

T.summary()
