-- =========================================================
-- FS25 NPCFavor - NPC TREATMENT DECISIONS (SF-10 / the drop's item 10)
-- =========================================================
-- Each NPC farmer decides once per morning whether to deal with their own
-- fields' trouble, weighted by who they are; a yes runs a real treatment
-- through SoilFertilizer's own public entry; helping a neighbour genuinely
-- improves their diligence through the relationship machinery. No new mod.
--
-- Mechanism (from the brief):
--   B1. THE BREAKFAST ROLL (server-side, once per morning). Per assigned field
--       WITH trouble, roll treat-today with probability from the effective work
--       ethic (B3), trouble severity (raises urgency for everyone), and weather
--       (rain vetoes, the existing weather-override pattern). A yes queues the
--       field for that NPC's next work session. The trouble read is SF's
--       PUBLISHED getFieldInfo (diseasePressure/pestPressure), pcall-wrapped,
--       neutral-absent: no SF installed means no NPC ever treats, exactly
--       today's behaviour.
--   B3. THE DILIGENCE RULE. effectiveWorkEthic = clamp(personalityBase +
--       relationshipOffset, 0.5, 1.5). The personality base is the existing
--       aiPersonalityModifiers.workEthic (NEVER overwritten). The offset is new,
--       small, symmetric, persisted beside it: helping raises, damage lowers.
--   B4. THE TREATMENT INVOCATION (server-side). On session completion, call
--       SoilFertilitySystem:applyNamedFungicide(fieldId, chemId, { charge = false }).
--       charge = false is the NO-MONEY enforcement and is LAW: never route
--       through SoilTreatFieldEvent (the wire carries no opts), always the
--       server path. Chem selection: the active pressure type picks fungicide
--       vs insecticide via the same published read.
--
-- No ledger, no player money, no reveal of the disease name (B5: the visible
-- operation reveals TROUBLE only, never the name or numbers).
-- =========================================================
-- Author: TisonK
-- =========================================================

NPCTreatment = {}

NPCTreatment.ENABLED = true

-- Constants (XML-tunable later via the ratio pass / Community dial).
NPCTreatment.BASE_PROBABILITY      = 0.35  -- treat-today base chance
NPCTreatment.SEVERITY_URGENCY_GAIN = 0.10  -- per 10 pressure points above the threshold
NPCTreatment.RAIN_VETO             = true  -- rain days veto spraying
NPCTreatment.OFFSET_GAIN           = 0.05  -- relationship offset when helped (symmetric, bounded)
NPCTreatment.OFFSET_LOSS           = 0.05  -- relationship offset when damaged
NPCTreatment.OFFSET_CLAMP          = 0.30  -- offset bound (diligence clamp is 0.5..1.5)

-- =========================================================
-- B3. The diligence rule
-- =========================================================

--- Effective work ethic for an NPC: clamp(personalityBase + offset, 0.5, 1.5).
--- The personality base is NEVER overwritten; the offset is a separate field.
---@param npc table
---@return number ethic
function NPCTreatment:effectiveWorkEthic(npc)
    local base = (npc.aiPersonalityModifiers and npc.aiPersonalityModifiers.workEthic) or 1.0
    local offset = npc._workEthicOffset or 0
    local v = base + offset
    if v < 0.5 then v = 0.5 elseif v > 1.5 then v = 1.5 end
    return v
end

--- The relationship offset for an NPC (the persisted, symmetric diligence delta).
---@param npc table
---@return number offset
function NPCTreatment:workEthicOffset(npc)
    return npc._workEthicOffset or 0
end

--- Adjust the offset on a relationship change: helping raises, damage lowers.
--- Symmetric and bounded; the base workEthic is never touched.
---@param npc table
---@param change number  the relationship delta (positive = helped, negative = damaged)
function NPCTreatment:adjustOffset(npc, change)
    if not npc then return end
    local cur = npc._workEthicOffset or 0
    if change > 0 then
        cur = cur + NPCTreatment.OFFSET_GAIN
    elseif change < 0 then
        cur = cur - NPCTreatment.OFFSET_LOSS
    end
    if cur > NPCTreatment.OFFSET_CLAMP then cur = NPCTreatment.OFFSET_CLAMP end
    if cur < -NPCTreatment.OFFSET_CLAMP then cur = -NPCTreatment.OFFSET_CLAMP end
    npc._workEthicOffset = cur
end

-- =========================================================
-- B1. The breakfast roll
-- =========================================================

--- SF's soil system through the mission handle, pcall-safe.
---@return table|nil
function NPCTreatment:_soilSystem()
    local m = g_currentMission
    if not m or not m.soilFertilityManager then return nil end
    return m.soilFertilityManager.soilSystem or nil
end

--- SF's published getFieldInfo for a field, pcall-wrapped, neutral-absent.
---@param fieldId number
---@return table|nil info
function NPCTreatment:_fieldTrouble(fieldId)
    local soil = self:_soilSystem()
    if not soil or type(soil.getFieldInfo) ~= "function" then return nil end
    local ok, info = pcall(soil.getFieldInfo, soil, fieldId)
    if not ok or type(info) ~= "table" then return nil end
    return info
end

--- Does rain veto today's treatment? Uses the existing weather-override pattern.
---@return boolean raining
function NPCTreatment:isRainVeto()
    if not NPCTreatment.RAIN_VETO then return false end
    local env = g_currentMission and g_currentMission.environment
    local w = env and env.weather
    local t = w and w.currentWeather or "clear"
    return t == "rain" or t == "storm" or t == "snow"
end

--- Roll treat-today for one of an NPC's assigned fields. Returns true when the
--- NPC decides to treat this field today. Server-side only.
---@param npc table
---@param fieldId number
---@return boolean treatToday
---@return string|nil chemId  the chosen chemistry (fungicide/insecticide)
function NPCTreatment:rollTreatToday(npc, fieldId)
    if not NPCTreatment.ENABLED then return false, nil end
    if self:isRainVeto() then return false, nil end

    local info = self:_fieldTrouble(fieldId)
    if not info then return false, nil end   -- no SF / no trouble = never treat

    local disease = info.diseasePressure or 0
    local pest    = info.pestPressure    or 0
    local trouble = math.max(disease, pest)
    if trouble <= 0 then return false, nil end

    -- Chem selection from the ACTIVE pressure type (the published read).
    local chemId = nil
    if info.activeDisease and disease >= pest then
        chemId = "FUNGICIDE"
    elseif pest > 0 then
        chemId = "INSECTICIDE"
    else
        return false, nil
    end

    -- Probability: base x ethic x severity urgency.
    local ethic = self:effectiveWorkEthic(npc)
    local severityBoost = 1.0 + math.floor(trouble / 10) * NPCTreatment.SEVERITY_URGENCY_GAIN
    local p = NPCTreatment.BASE_PROBABILITY * ethic * severityBoost
    if p > 0.95 then p = 0.95 end

    return math.random() < p, chemId
end

--- The B1 pass: run the breakfast roll for every NPC's assigned fields on a new
--- day. A yes queues the field for the NPC's next work session.
---@param selfNpcSystem table the NPCSystem (for activeNPCs)
function NPCTreatment:breakfastRoll(selfNpcSystem)
    if not NPCTreatment.ENABLED or not selfNpcSystem then return end
    local npcs = selfNpcSystem.activeNPCs
    if not npcs then return end
    for _, npc in ipairs(npcs) do
        if npc and npc.isActive and npc.assignedFarmland and npc.assignedFarmland.farmlandId then
            local fid = npc.assignedFarmland.farmlandId
            local treatToday, chemId = self:rollTreatToday(npc, fid)
            if treatToday and chemId then
                npc._pendingTreat = { fieldId = fid, chemId = chemId }
            end
        end
    end
end

-- =========================================================
-- B4. The treatment invocation (server-side, NO MONEY)
-- =========================================================

--- Run the queued treatment for an NPC's field. Uses SF's OWN public entry with
--- charge = false (the NO-MONEY law). Never the event wire (it carries no opts).
---@param npc table
---@return boolean treated
function NPCTreatment:runPendingTreatment(npc)
    if not npc or not npc._pendingTreat then return false end
    local pending = npc._pendingTreat
    npc._pendingTreat = nil
    local soil = self:_soilSystem()
    if not soil or type(soil.applyNamedFungicide) ~= "function" then return false end
    local ok, result = pcall(soil.applyNamedFungicide, soil, pending.fieldId, pending.chemId, { charge = false })
    npc._pendingTreat = nil
    return ok and result ~= false
end
