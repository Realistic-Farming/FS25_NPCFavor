-- =========================================================
-- FS25 NPC Favor Mod - Ambient land admission (RSF-F206)
-- =========================================================
-- One typed answer to one question: may an ambient neighbour work the PARCEL
-- that exists at this world coordinate.
--
-- The mod already owned a correct positional read (NPCSystem:isPlayerOwnedAtPosition)
-- and used it in exactly two places, the eviction sweep and the synthetic mint. This
-- module is built BESIDE those two rather than on top of them: they keep their boolean
-- signatures and their callers, and everything that has to distinguish "denied",
-- "could not ask" and "nonsense" comes here instead.
--
-- Engine facts, verified in D:\FS25_Decoded\dataS\scripts_decompiled:
--   FarmlandManager.NO_OWNER_FARM_ID   = 0                  (FarmlandManager.lua:2)
--   FarmlandManager.NOT_BUYABLE_FARM_ID= 2^numberOfBits - 1 (FarmlandManager.lua:64; 255 in practice)
--   getFarmlandIdAtWorldPosition       returns NO_OWNER_FARM_ID when localMap is nil
--                                                           (FarmlandManager.lua:282-288)
--   getFarmlandOwner                   returns NO_OWNER_FARM_ID for an unmapped parcel
--                                                           (FarmlandManager.lua:275-281)
--   Farm carries players / userIdToPlayer / activeUsers, never users / userIds
--                                                           (Farm.lua:186-189)
-- The farm-identity constants are NOT restated here; NPCFarmIdentity owns them.
-- =========================================================

NPCLandAdmission = NPCLandAdmission or {}

--- The four results. UNAVAILABLE and INVALID both end the attempt and both wait for
--- the existing retry, so they create no separate branch; they are two names because
--- they mean different things in a log. UNAVAILABLE says the question could not be
--- asked, INVALID says the answer was nonsense.
NPCLandAdmission.ALLOW       = "ALLOW"
NPCLandAdmission.DENY_PLAYER = "DENY_PLAYER"
NPCLandAdmission.UNAVAILABLE = "UNAVAILABLE"
NPCLandAdmission.INVALID     = "INVALID"

--- True for a real, finite number. Unlike NPCFarmIdentity.isInteger this accepts
--- fractions, because world coordinates are not integers.
function NPCLandAdmission.isFiniteNumber(value)
    return type(value) == "number"
        and value == value                -- not NaN
        and value ~= math.huge
        and value ~= -math.huge
end

function NPCLandAdmission.noOwnerFarmId()
    if FarmlandManager ~= nil and FarmlandManager.NO_OWNER_FARM_ID ~= nil then
        return FarmlandManager.NO_OWNER_FARM_ID
    end
    return 0
end

function NPCLandAdmission.notBuyableFarmlandId()
    if FarmlandManager ~= nil and FarmlandManager.NOT_BUYABLE_FARM_ID ~= nil then
        return FarmlandManager.NOT_BUYABLE_FARM_ID
    end
    return 255
end

--- True when the farmland manager has a loaded local map. Without one,
--- getFarmlandIdAtWorldPosition returns NO_OWNER_FARM_ID for every coordinate, which
--- is the SAME value as a genuine sample of zero. Separating those two is the first
--- job of the order below and the manager alone does not do it.
function NPCLandAdmission.hasLoadedMap()
    return g_farmlandManager ~= nil and g_farmlandManager.localMap ~= nil
end

--- Resolve a parcel's owner, then overlay this mod's borrow stash.
-- ORDER MATTERS AND IT IS THE HELPER'S ORDER: ask the native manager FIRST, then
-- replace the answer when a stash row exists for that parcel. While a job runs this
-- mod has deliberately written its own farm id onto the parcel, so the native lookup
-- honestly answers with the BORROWING farm; without the overlay this function would
-- classify the parcel DENY_PLAYER and evict the neighbour from the very job the
-- borrow exists to allow.
-- KNOWN LIMIT, registered separately and not repaired here: the stash row is captured
-- once when the borrow begins, so a parcel bought by the farmer DURING a borrow reads
-- as its pre-purchase owner for the rest of that job.
-- @param farmlandId      positive parcel id
-- @param ownershipFlips  NPCSystem._ownershipFlips, or nil
-- @return number|nil     owner farm id, or nil when it could not be read
function NPCLandAdmission.resolveOwner(farmlandId, ownershipFlips)
    if g_farmlandManager == nil then return nil end

    local owner
    pcall(function() owner = g_farmlandManager:getFarmlandOwner(farmlandId) end)

    if type(ownershipFlips) == "table" and ownershipFlips[farmlandId] ~= nil then
        owner = ownershipFlips[farmlandId]
    end

    return owner
end

--- Classify a KNOWN parcel id. Steps 2 to 4 of the resolution order; the caller has
--- already done step 1 (or holds the id for another reason, as the assignment
--- producer does).
-- @return string status
function NPCLandAdmission.classifyFarmlandId(farmlandId, ownershipFlips)
    local A = NPCLandAdmission

    if not A.isFiniteNumber(farmlandId) then return A.UNAVAILABLE end

    -- Step 2: a deliberately defined non-buyable area is not free ground.
    if farmlandId == A.notBuyableFarmlandId() then return A.UNAVAILABLE end

    -- Step 3: a sample of zero is NOT PART OF ANY FARMLAND. There is nothing there to
    -- own and no field can exist there. This is not "unowned ground" and must not be
    -- confused with it: only one of the two is workable land.
    if farmlandId <= 0 then return A.UNAVAILABLE end

    -- Step 4: the parcel exists, so resolve its owner.
    local owner = A.resolveOwner(farmlandId, ownershipFlips)
    if owner == nil then return A.UNAVAILABLE end

    -- The parcel exists and nobody owns it. THIS IS SETTLED BEFORE ANY FARM LOOKUP
    -- and that ordering is the whole reason the rule works: SPECTATOR_FARM_ID is also
    -- zero, so a lookup on owner zero returns a resolvable spectator farm object and a
    -- rule that resolves the farm first denies every unowned parcel on the map.
    if owner == A.noOwnerFarmId() then return A.ALLOW end

    -- Any currently resolvable ordinary farm owns this as player land, whatever its
    -- membership list says (Arissani's ruling 2026-09-14). Membership never decides
    -- ownership: a legitimate farm may carry no current or retained players after a
    -- save prune, a disconnect, or a joining client rebuilding from the connected set.
    -- isOrdinaryFarmId excludes the spectator, guided-tour and invalid ids and requires
    -- the farm to actually resolve, which is exactly this step's rule.
    if NPCFarmIdentity.isOrdinaryFarmId(owner) then return A.DENY_PLAYER end

    -- Guided tour, invalid, or a positive owner that does not resolve. An unresolved
    -- owner is an unanswered question, not free land: never ALLOW.
    return A.UNAVAILABLE
end

--- The full order, from a world coordinate. This is the read every door uses.
-- @return string status, number|nil farmlandId
function NPCLandAdmission.classifyPosition(x, z, ownershipFlips)
    local A = NPCLandAdmission

    -- PRECONDITION, ahead of the order and not part of it. A malformed or non-finite
    -- coordinate is INVALID without ever reaching the native manager, because what
    -- getBitVectorMapPoint returns for a non-finite index is a C body neither native
    -- lane carries and a builder must not depend on it.
    if not A.isFiniteNumber(x) or not A.isFiniteNumber(z) then
        return A.INVALID, nil
    end

    if g_farmlandManager == nil then return A.UNAVAILABLE, nil end

    -- Step 1: parcel identity at the coordinate, through the native manager. With no
    -- loaded map the manager hands back NO_OWNER_FARM_ID for every coordinate, which
    -- means the question could not be asked. That is UNAVAILABLE and never ALLOW.
    if not A.hasLoadedMap() then return A.UNAVAILABLE, nil end

    local farmlandId
    pcall(function() farmlandId = g_farmlandManager:getFarmlandIdAtWorldPosition(x, z) end)
    if farmlandId == nil then return A.UNAVAILABLE, nil end

    return A.classifyFarmlandId(farmlandId, ownershipFlips), farmlandId
end

--- The synthetic branch's door result, and it is a table rather than an inference.
-- A synthetic record is not a parcel claim: its id zero is a deliberate placeholder
-- because no field object was selected, so it is NOT put to the parcel order. It IS
-- still judged by position, on the same terms the eviction sweep already uses.
--
--   ground under the synthetic centre        -> result
--   position resolves to player-owned        -> DENY_PLAYER (the one refusal)
--   sample of zero on a loaded map           -> ALLOW (the fallback's ordinary ground)
--   positive parcel, no owner                -> ALLOW
--   not-buyable sentinel                     -> ALLOW
--   guided tour or invalid farm id           -> ALLOW
--   map absent, so the sample is no-owner    -> ALLOW
--
-- ONE VALUE AND ONE ONLY REFUSES. UNAVAILABLE and INVALID are parcel-order answers
-- and this branch is not put to the parcel order, so neither is a door result here.
-- A builder who refuses on anything other than ALLOW takes sample-zero ground away
-- and kills the fallback the exemption exists to keep, while a refusal-side check
-- stays green the whole time.
-- @return string  ALLOW or DENY_PLAYER, and nothing else
function NPCLandAdmission.classifySynthetic(x, z, ownershipFlips)
    local A = NPCLandAdmission
    local status = A.classifyPosition(x, z, ownershipFlips)
    if status == A.DENY_PLAYER then return A.DENY_PLAYER end
    return A.ALLOW
end

--- The mark is `isSynthetic` and NEVER `id == 0`. Hole one leaves every selector
--- record carrying zero today, so an identity test would exempt the whole selector
--- path from admission, which is the opposite of this repair.
function NPCLandAdmission.isSyntheticRecord(record)
    return type(record) == "table" and record.isSynthetic == true
end

--- Resolve the native parcel a field object belongs to, nested object first and the
--- flat member only as a compatibility fallback. Native Field carries `self.farmland`,
--- a reference to the Farmland object; it carries no `farmlandId`, which is hole one.
--- assignFarmlands already reads it in this order and the selector did not.
-- @return number|nil
function NPCLandAdmission.fieldParcelId(field)
    if type(field) ~= "table" then return nil end
    if field.farmland ~= nil and field.farmland.id ~= nil then
        return field.farmland.id
    end
    if field.farmlandId ~= nil then
        return field.farmlandId
    end
    return nil
end
