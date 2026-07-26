-- =========================================================
-- FS25 NPC Favor — FieldSentry integration (#56)
-- =========================================================
-- Registers NPCFavor as a contract provider for Soil & Fertilizer's FieldSentry, so a
-- field under an active NPC favor is masked from the soil simulation (the harvest gets
-- vanilla yields and the favor stays completable) instead of being wrecked by nutrient
-- depletion on land no one manages. High-relationship neighbours can opt the field back
-- into the sim, so a best friend lets the player benefit from real soil management while
-- a hostile neighbour's field stays a plain vanilla mask.
--
-- See FS25_SoilFertilizer docs/integration-npcfavor.md and S&F #654. Server/host only;
-- clients receive the resulting mask through S&F's own sync. Fully guarded — NPCFavor
-- loads and runs normally when Soil & Fertilizer is absent.
-- =========================================================

NPCFieldSentry = NPCFieldSentry or {}
NPCFieldSentry.PROVIDER_NAME = "NPCFavor"
NPCFieldSentry._registered   = false

-- Resolve the FieldSentry control surface. Prefer the plain global if it is visible
-- cross-mod (as the integration doc describes); otherwise use the g_currentMission.fieldSentry
-- bridge S&F publishes, which is the reliable cross-mod handle in FS25.
local function getFieldSentry()
    if FieldSentry_API and FieldSentry_API.registerContractProvider then
        return FieldSentry_API
    end
    local bridge = g_currentMission and g_currentMission.fieldSentry
    if bridge and bridge.registerContractProvider then
        return bridge
    end
    return nil
end

-- Favor states that count as "a contract is running on this field" for masking. A pending
-- (offered, not yet accepted) favor does not claim the field; completed/failed are done.
local ACTIVE_STATUS = { active = true, in_progress = true }

-- The relationship tier as a 1..7 index into RELATIONSHIP_LEVELS (1 = Hostile … 7 = best),
-- which is what FieldSentry compares against its favorTierThreshold.
local function tierForValue(rm, value)
    if rm == nil or rm.RELATIONSHIP_LEVELS == nil then
        return 0
    end
    value = value or 0
    for i, level in ipairs(rm.RELATIONSHIP_LEVELS) do
        if value >= level.min and value <= level.max then
            return i
        end
    end
    return 0
end

-- The provider callback. fn(fieldId) -> { active, favorTier, allowSAndF }.
-- Must be cheap, never error, and fail closed — FieldSentry pcalls it and treats any
-- garbage/crash as "contract active, masked", so a bug here can never un-mask a field.
--
-- NOTE on ids: FieldSentry keys by the same field id S&F uses; NPCFavor stores the
-- harvest favor's field as field.fieldId (NPCSystem:findNearestField). On standard maps
-- these coincide, so a direct match is correct.
local function npcFavorContractStatus(fieldId)
    local sys = g_NPCSystem
    local favorSystem = sys and sys.favorSystem
    if fieldId == nil or favorSystem == nil or favorSystem.activeFavors == nil then
        return { active = false }
    end

    for _, favor in ipairs(favorSystem.activeFavors) do
        local td = favor.taskData
        if td ~= nil and td.fieldId == fieldId and ACTIVE_STATUS[favor.status] then
            -- Tier from the requesting neighbour's current relationship.
            local tier = 0
            if favor.npcId and sys.getNPCById and sys.relationshipManager then
                local npc = sys:getNPCById(favor.npcId)
                if npc then
                    tier = tierForValue(sys.relationshipManager, npc.relationship)
                end
            end

            -- Threshold from FieldSentry (default 4 if it is not reachable for any reason).
            local threshold = 4
            local fs = getFieldSentry()
            if fs and fs.favorTierThreshold then
                threshold = fs.favorTierThreshold
            elseif FieldSentry_Core and FieldSentry_Core.FAVOR_TIER_THRESHOLD then
                threshold = FieldSentry_Core.FAVOR_TIER_THRESHOLD
            end

            return {
                active     = true,
                favorTier  = tier,
                allowSAndF = tier >= threshold,
            }
        end
    end

    return { active = false }
end

--- Register the provider. Server/host/SP only; a pure client is ignored (S&F rejects it
--- too). No-ops cleanly when Soil & Fertilizer / FieldSentry is not installed.
function NPCFieldSentry.register()
    if NPCFieldSentry._registered then
        return
    end
    if g_server == nil then
        return
    end
    local fs = getFieldSentry()
    if fs == nil then
        return
    end
    if fs.registerContractProvider(NPCFieldSentry.PROVIDER_NAME, npcFavorContractStatus) then
        NPCFieldSentry._registered = true
        print("[NPC Favor] Registered as a FieldSentry contract provider")
    end
end

--- Remove the provider on mission teardown.
function NPCFieldSentry.unregister()
    if not NPCFieldSentry._registered then
        return
    end
    local fs = getFieldSentry()
    if fs and fs.unregisterContractProvider then
        fs.unregisterContractProvider(NPCFieldSentry.PROVIDER_NAME)
    end
    NPCFieldSentry._registered = false
end

-- Register once the mission (and g_NPCSystem) are up; unregister on mission teardown.
if Mission00 and Mission00.loadMission00Finished then
    Mission00.loadMission00Finished = Utils.appendedFunction(
        Mission00.loadMission00Finished,
        function() NPCFieldSentry.register() end
    )
end
if FSBaseMission and FSBaseMission.delete then
    FSBaseMission.delete = Utils.appendedFunction(
        FSBaseMission.delete,
        function() NPCFieldSentry.unregister() end
    )
end
