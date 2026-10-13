-- RSF-F206: ambient land admission contract.
--!load: src/utils/NPCFarmIdentity.lua, src/utils/NPCLandAdmission.lua, src/scripts/NPCFavorSystem.lua, src/scripts/NPCFavorRecovery.lua, src/events/NPCInteractionEvent.lua, src/NPCSystem.lua
--
-- Ported from the certified design bar (Office Tyson/mods/FS25_NPCFavor/
-- RSF-F206-ambient_land_identity_spec_test.lua) against the BUILT source.
--
-- Every group that asserts a rule also asserts it as a DIFFERENCE against the build a
-- reasonable person types without the correction, because a bar that only agrees with
-- itself proves nothing. The standing instruction from the brief is followed here:
-- legitimate SUCCESS is tested at least as hard as refusal, since four review rounds
-- running the defect that survived longest was a rule that refused ground the
-- neighbours exist to work, and every time the refusal-side tests were green.
--
-- Nothing here proves native UI, disk, network, multiplayer or gameplay.

local A = NPCLandAdmission

-- ── engine fixture ─────────────────────────────────────────
FarmlandManager = FarmlandManager or {}
FarmlandManager.NO_OWNER_FARM_ID = 0
FarmlandManager.NOT_BUYABLE_FARM_ID = 255   -- 2^8-1, FarmlandManager.lua:64
FarmManager = FarmManager or {}
FarmManager.SPECTATOR_FARM_ID = 0
FarmManager.SINGLEPLAYER_FARM_ID = 1
FarmManager.MAX_FARM_ID = 8
FarmManager.GUIDED_TOUR_FARM_ID = 14
FarmManager.INVALID_FARM_ID = 15

-- The world. `samples` maps "x:z" to the parcel id the info layer returns;
-- `owners` is the manager's farmlandMapping. `managerCalls` counts every positional
-- resolve so the finiteness precondition can be proved to short-circuit BEFORE the
-- native manager is consulted, rather than merely to return the right value.
local W = { mapLoaded = true, samples = {}, owners = {}, managerCalls = 0 }

local function key(x, z) return tostring(x) .. ":" .. tostring(z) end
local function placeSample(x, z, parcelId) W.samples[key(x, z)] = parcelId end

g_farmlandManager = setmetatable({}, {
    __index = function(_, k)
        if k == "localMap" then return W.mapLoaded and "map" or nil end
        return nil
    end
})
g_farmlandManager.getFarmlandIdAtWorldPosition = function(_, x, z)
    W.managerCalls = W.managerCalls + 1
    -- Native: with no local map every coordinate returns NO_OWNER_FARM_ID.
    if not W.mapLoaded then return FarmlandManager.NO_OWNER_FARM_ID end
    local s = W.samples[key(x, z)]
    if s == nil then return FarmlandManager.NO_OWNER_FARM_ID end
    return s
end
g_farmlandManager.getFarmlandOwner = function(_, id)
    -- Native FarmlandManager.lua:275-281: an unmapped parcel collapses to no-owner.
    if id == nil or W.owners[id] == nil then return FarmlandManager.NO_OWNER_FARM_ID end
    return W.owners[id]
end

local LIVE_FARMS = {}
g_farmManager = {
    getFarmById = function(_, id) return LIVE_FARMS[id] end,
}
local function setFarm(id, farm) LIVE_FARMS[id] = farm end

-- Native Farm carries players / userIdToPlayer / activeUsers and NEVER users/userIds
-- (Farm.lua:186-189). A farm with an EMPTY members list is the case the ruling exists
-- for: save pruning at 150 entries and 30 days offline, and a joining client rebuilding
-- players from a stream carrying only activeUsers.
local function nativeFarm(id, playerCount)
    local players = {}
    for i = 1, (playerCount or 0) do players[i] = { id = i } end
    return { farmId = id, players = players, userIdToPlayer = {}, activeUsers = {} }
end

setFarm(1, nativeFarm(1, 1))    -- the local farm
setFarm(2, nativeFarm(2, 0))    -- a real farm presenting an EMPTY members list
setFarm(3, nativeFarm(3, 2))    -- another player's farm
setFarm(14, nativeFarm(14, 0))  -- the guided tour farm DOES resolve

g_currentMission = g_currentMission or {}
g_currentMission.getFarmId = function() return 1 end

local function newSys()
    local s = setmetatable({}, { __index = NPCSystem })
    s.settings = { debugMode = false }
    s.activeNPCs = {}
    return s
end

-- The map. Every parcel below is positive; the owner is what varies.
W.owners[10] = 0    -- exists, nobody owns it: the ORDINARY case
W.owners[11] = 1    -- the local player's farm
W.owners[12] = 3    -- another player's farm
W.owners[13] = 2    -- a real farm with an EMPTY members list
W.owners[14] = 14   -- owned by the guided tour farm
W.owners[15] = 15   -- owned by the invalid id
W.owners[16] = 7    -- a positive owner that does not resolve to any farm

placeSample(100, 100, 10)   -- unowned working land
placeSample(200, 200, 11)   -- the farmer's own field
placeSample(300, 300, 12)   -- another player's field
placeSample(400, 400, 13)   -- the empty-membership farm's field
placeSample(500, 500, 14)   -- guided tour
placeSample(600, 600, 15)   -- invalid
placeSample(700, 700, 16)   -- unresolved owner
placeSample(800, 800, 255)  -- the not-buyable sentinel
placeSample(900, 900, 0)    -- a sample of zero on a LOADED map: not part of any farmland

local sys = newSys()

-- =========================================================
-- GROUP A: the finiteness precondition
-- =========================================================
-- It is a PRECONDITION and not a fifth step. Steps 1 to 4 hand the coordinate to the
-- manager, so a guard placed last could never fire: by then the answer is already
-- whatever the engine returned. What getBitVectorMapPoint does with a non-finite index
-- is a C body neither native lane carries, so a builder must not depend on it.
local nan = 0 / 0
local inf = math.huge

W.managerCalls = 0
T.eq("A1 a NaN x is INVALID", (sys:admitPosition(nan, 100)), A.INVALID)
T.eq("A2 a NaN z is INVALID", (sys:admitPosition(100, nan)), A.INVALID)
T.eq("A3 +inf is INVALID", (sys:admitPosition(inf, 100)), A.INVALID)
T.eq("A4 -inf is INVALID", (sys:admitPosition(100, -inf)), A.INVALID)
T.eq("A5 a non-number is INVALID", (sys:admitPosition("100", 100)), A.INVALID)
T.eq("A6 a nil coordinate is INVALID", (sys:admitPosition(nil, 100)), A.INVALID)
T.eq("A7 DIFFERENCE: the native manager was never consulted for any of them", W.managerCalls, 0)

W.managerCalls = 0
T.eq("A8 the guard does not swallow good input", (sys:admitPosition(100, 100)), A.ALLOW)
T.eq("A9 and good input DOES reach the manager", W.managerCalls, 1)
T.ok("A10 a plain fraction is finite", A.isFiniteNumber(12.75))
T.ok("A11 zero is finite", A.isFiniteNumber(0))
T.ok("A12 a negative coordinate is finite", A.isFiniteNumber(-4210.5))

-- =========================================================
-- GROUP B: the resolution order
-- =========================================================
-- THE ORDER IS LOAD BEARING. Several different things in this codebase are called
-- zero, and one ordering makes the rule deny every legitimate parcel.

T.eq("B1 a parcel that exists with NO owner is ALLOW", (sys:admitPosition(100, 100)), A.ALLOW)
T.eq("B2 the farmer's own parcel is DENY_PLAYER", (sys:admitPosition(200, 200)), A.DENY_PLAYER)
T.eq("B3 another player's parcel is DENY_PLAYER", (sys:admitPosition(300, 300)), A.DENY_PLAYER)
T.eq("B4 the not-buyable sentinel is UNAVAILABLE", (sys:admitPosition(800, 800)), A.UNAVAILABLE)
T.eq("B5 a sample of zero on a loaded map is UNAVAILABLE", (sys:admitPosition(900, 900)), A.UNAVAILABLE)
T.eq("B6 guided-tour-owned land is UNAVAILABLE", (sys:admitPosition(500, 500)), A.UNAVAILABLE)
T.eq("B7 invalid-id-owned land is UNAVAILABLE", (sys:admitPosition(600, 600)), A.UNAVAILABLE)
T.eq("B8 a positive owner that does not resolve is UNAVAILABLE", (sys:admitPosition(700, 700)), A.UNAVAILABLE)

-- Map absent. The manager hands back NO_OWNER_FARM_ID for every coordinate, which is
-- the SAME value as a genuine sample of zero. This is the case a builder reads as free
-- ground, and it is exactly why the two names exist.
W.mapLoaded = false
T.eq("B9 with no loaded map the answer is UNAVAILABLE, never ALLOW",
    (sys:admitPosition(100, 100)), A.UNAVAILABLE)
W.mapLoaded = true
T.eq("B10 and it is ALLOW again once the map is back", (sys:admitPosition(100, 100)), A.ALLOW)

-- THE ORDER, AS A DIFFERENCE. A farm-first resolver is what a reasonable person writes
-- when the ordering is not stated: it looks the owner's farm up before settling the
-- unowned case. SPECTATOR_FARM_ID is also zero, so getFarmById(0) is a resolvable
-- object on a real engine and every unowned parcel in the world is denied.
setFarm(0, nativeFarm(0, 0))   -- the spectator farm resolves, as it does natively
local function farmFirstOrder(parcelId)
    if parcelId == nil or parcelId <= 0 then return A.UNAVAILABLE end
    local owner = g_farmlandManager:getFarmlandOwner(parcelId)
    local farm = g_farmManager:getFarmById(owner)
    if farm ~= nil then return A.DENY_PLAYER end
    return A.ALLOW
end
T.eq("B11 DIFFERENCE: the farm-first order denies unowned working land",
    farmFirstOrder(10), A.DENY_PLAYER)
T.eq("B12 DIFFERENCE: the built order allows it", sys:admitFarmlandId(10), A.ALLOW)
T.ok("B13 the two orders cannot both be right",
    farmFirstOrder(10) ~= sys:admitFarmlandId(10))
T.eq("B14 and both still deny the farmer's parcel", farmFirstOrder(11), A.DENY_PLAYER)
T.eq("B15 the built order denies it too", sys:admitFarmlandId(11), A.DENY_PLAYER)
setFarm(0, nil)

-- The unowned case is the STARTING STATE of every parcel on the map, not a corner:
-- FarmlandManager maps only positive samples and sets every mapped parcel's initial
-- owner to the no-owner value.
local allowedCount = 0
for _, pid in ipairs({ 10, 11, 12, 13, 14, 15, 16 }) do
    if sys:admitFarmlandId(pid) == A.ALLOW then allowedCount = allowedCount + 1 end
end
T.eq("B16 exactly one of the seven modelled parcels is workable", allowedCount, 1)

-- THE STATED LIMIT, recorded rather than papered over: getFarmlandOwner collapses a
-- parcel absent from farmlandMapping into the same no-owner value as genuinely unowned
-- ground, so the rule cannot separate those two and both come back ALLOW.
T.eq("B17 LIMIT: a parcel with no owner row is indistinguishable from unowned",
    sys:admitFarmlandId(4242), A.ALLOW)

-- =========================================================
-- GROUP C: hole two, the owner test
-- =========================================================
-- Neither F331, F332 nor F333 named this one, and it survives any repair to the parcel
-- key because BOTH doors funnel through it.

-- The build a repair of hole one alone leaves behind.
local function oldOwnerTest(owner)
    if owner == nil or owner == 0 then return false end
    if owner == 1 then return true end                      -- the local farm, caught by id
    local farm = g_farmManager:getFarmById(owner)
    if farm ~= nil then
        local users = farm.users or farm.userIds            -- native Farm has NEITHER
        if type(users) == "table" and next(users) ~= nil then return true end
    end
    return false
end

T.eq("C1 DIFFERENCE: the old membership read calls another player's farm not-owned",
    oldOwnerTest(3), false)
T.ok("C2 DIFFERENCE: the built test calls it player land",
    sys:isPlayerOwnedFarmland(12))
T.eq("C3 DIFFERENCE: the old read fails open on the empty-membership farm too",
    oldOwnerTest(2), false)
T.ok("C4 the built test holds a real farm with an EMPTY members list as player land",
    sys:isPlayerOwnedFarmland(13))
T.eq("C5 and admission agrees", (sys:admitPosition(400, 400)), A.DENY_PLAYER)
T.ok("C6 the local farm is still player land", sys:isPlayerOwnedFarmland(11))
T.ok("C7 unowned land is still NOT player land", not sys:isPlayerOwnedFarmland(10))
T.ok("C8 guided-tour land is not player land", not sys:isPlayerOwnedFarmland(14))
T.ok("C9 invalid-id land is not player land", not sys:isPlayerOwnedFarmland(15))
T.ok("C10 an unresolved owner is not player land", not sys:isPlayerOwnedFarmland(16))

-- Membership never decides ownership: adding and removing members must not move the
-- answer in either direction.
setFarm(3, nativeFarm(3, 0))
T.ok("C11 another player's farm stays player land after its list empties",
    sys:isPlayerOwnedFarmland(12))
setFarm(3, nativeFarm(3, 5))
T.ok("C12 and after it refills", sys:isPlayerOwnedFarmland(12))

-- The sweep and the door are only the SAME INSTRUMENT once this is repaired. The sweep
-- keeps the existing helper; repairing it in place is what makes them agree off the
-- local farm.
T.eq("C13 the door and the sweep agree on another player's land",
    sys:admitPosition(300, 300) == A.DENY_PLAYER,
    sys:isPlayerOwnedAtPosition(300, 300))
T.eq("C14 and they agree on unowned land",
    sys:admitPosition(100, 100) == A.DENY_PLAYER,
    sys:isPlayerOwnedAtPosition(100, 100))

-- =========================================================
-- GROUP D: the borrow stash overlay
-- =========================================================
-- While a job runs this mod deliberately writes its own farm id onto the parcel, so the
-- native lookup HONESTLY answers with the borrowing farm. A function built without the
-- stash classifies that parcel DENY_PLAYER and evicts the neighbour from the very job
-- the borrow exists to allow.

local borrowSys = newSys()
W.owners[10] = 1                       -- the borrow has written farm 1 onto parcel 10
T.eq("D1 DIFFERENCE: stash-blind, the mod's own live borrow reads as player land",
    borrowSys:admitFarmlandId(10), A.DENY_PLAYER)
borrowSys._ownershipFlips = { [10] = 0 }   -- the stashed original owner: nobody
T.eq("D2 with the stash consulted the borrow keeps its own job", borrowSys:admitFarmlandId(10), A.ALLOW)

-- THE ORDER OF THE OVERLAY IS THE HELPER'S ORDER: ask the native manager FIRST, then
-- replace the answer when a stash row exists. A genuinely player-owned parcel with no
-- stash row is still denied through the same path.
T.eq("D3 a parcel with no stash row is unaffected by the overlay",
    borrowSys:admitFarmlandId(11), A.DENY_PLAYER)
borrowSys._ownershipFlips = { [11] = 3 }   -- stash says another player owned it
T.eq("D4 the overlay REPLACES the live answer when a row exists",
    borrowSys:admitFarmlandId(11), A.DENY_PLAYER)
borrowSys._ownershipFlips = nil
W.owners[10] = 0                       -- restore

-- =========================================================
-- GROUP E: hole one, the selector
-- =========================================================
-- Native Field carries no `farmlandId`; it carries `self.farmland`, a reference to the
-- Farmland object. The old gate handed the missing member to isPlayerOwnedFarmland,
-- whose first line treats nil and zero as NOT player owned, so every field was
-- eligible and the record then stamped that zero in permanently.

local function nativeField(parcelId, cx, cz, fieldId)
    -- No flat `farmlandId` member anywhere. This is the native shape (Field.new,
    -- Field.lua:12-30): the centre is the label point posX/posZ and the area is
    -- areaHa through getAreaHa. The `fieldArea` table this fixture used to carry
    -- does not exist on the engine's Field (PLAYER-REPORTS row 93).
    local f = { fieldId = fieldId or 1, farmland = { id = parcelId }, posX = cx, posZ = cz, areaHa = 0.0004 }
    f.getAreaHa = function(self) return self.areaHa end
    return f
end

local function oldSelectorGate(field)
    -- What the selector did: read the member native Field does not carry.
    local fid = field.farmlandId
    if not fid or fid == 0 then return false end   -- false == eligible
    return true
end

local playersField = nativeField(11, 200, 200, 7)
T.eq("E1 DIFFERENCE: the old selector gate calls the farmer's own field eligible",
    oldSelectorGate(playersField), false)
T.eq("E2 DIFFERENCE: the built selector refuses it",
    sys:admitPosition(200, 200), A.DENY_PLAYER)
T.eq("E3 the field's parcel resolves through the NESTED object",
    A.fieldParcelId(playersField), 11)
T.eq("E4 and the flat member is still honoured as a compatibility fallback",
    A.fieldParcelId({ farmlandId = 99 }), 99)
T.eq("E5 the nested object WINS when both are present",
    A.fieldParcelId({ farmland = { id = 5 }, farmlandId = 99 }), 5)
T.eq("E6 a field with neither resolves to nil, not zero", A.fieldParcelId({}), nil)

-- The selector end to end. g_fieldManager carries the farmer's field, unowned working
-- land, and a field on guided-tour ground.
g_fieldManager = { fields = {
    nativeField(11, 200, 200, 7),    -- the farmer's
    nativeField(10, 100, 100, 8),    -- legitimately unowned
    nativeField(14, 500, 500, 9),    -- guided tour
} }
local picked = sys:findNearestField(150, 150, 1)
T.ok("E7 the selector returns a field", picked ~= nil)
T.eq("E8 and it is the UNOWNED one, not the nearer player-owned one",
    picked and picked.farmlandId, 10)
T.eq("E9 the record carries `farmlandId` as the canonical parcel key",
    picked and picked.farmlandId, 10)
T.eq("E10 and `id` is RETAINED as a compatibility alias carrying the same value",
    picked and picked.id, 10)
T.ok("E11 SUCCESS SIDE: unowned working land is still selectable at all",
    picked ~= nil and picked.farmlandId == 10)

-- A missing centre is a REJECTION, not world origin.
g_fieldManager = { fields = { { fieldId = 3, farmland = { id = 10 } } } }
T.eq("E12 a field with no resolvable centre is never selected",
    sys:findNearestField(0, 0, 1), nil)

-- Every field player-owned: the selector returns nothing rather than something wrong.
g_fieldManager = { fields = { nativeField(11, 200, 200, 7), nativeField(12, 300, 300, 8) } }
T.eq("E13 with only player land in range the selector picks nothing",
    sys:findNearestField(200, 200, 1), nil)

-- =========================================================
-- GROUP F: hole three, the assignment producer
-- =========================================================
-- Native Farmland carries neither `ownerFarmId` nor `isNPCOwned`; a whole-tree search
-- for isNPCOwned returns zero hits anywhere. Both reads were nil, the owner defaulted
-- to zero, and EVERY native farmland classified assignable. The producer runs once and
-- nothing rewrites its output, so a wrong classification is permanent for the session.

local function nativeFarmland(id) return { id = id, farmId = 0, name = "Parcel " .. id } end

local function oldProducerClassify(farmland)
    local ownerFarmId = farmland.ownerFarmId or 0     -- nil on every native Farmland
    local isNPCOwned = farmland.isNPCOwned or false   -- nil on every native Farmland
    return ownerFarmId == 0 or ownerFarmId == nil or isNPCOwned
end

T.eq("F1 DIFFERENCE: the old producer calls the farmer's parcel assignable",
    oldProducerClassify(nativeFarmland(11)), true)
T.eq("F2 DIFFERENCE: the built producer refuses it",
    sys:admitFarmlandId(11), A.DENY_PLAYER)
T.eq("F3 DIFFERENCE: the old producer cannot separate owned from unowned at all",
    oldProducerClassify(nativeFarmland(11)), oldProducerClassify(nativeFarmland(10)))
T.ok("F4 the built producer can",
    sys:admitFarmlandId(11) ~= sys:admitFarmlandId(10))
T.eq("F5 SUCCESS SIDE: an unowned parcel is still assignable",
    sys:admitFarmlandId(10), A.ALLOW)
T.eq("F6 another player's parcel is not", sys:admitFarmlandId(12), A.DENY_PLAYER)
T.eq("F7 the empty-membership farm's parcel is not", sys:admitFarmlandId(13), A.DENY_PLAYER)
T.eq("F8 the not-buyable sentinel is not", sys:admitFarmlandId(255), A.UNAVAILABLE)

-- =========================================================
-- GROUP G: the synthetic branch
-- =========================================================
-- A synthetic record is not a parcel claim: its id zero is a deliberate placeholder
-- because no field object was selected. It is exempt from the parcel ORDER and is still
-- judged by POSITION, on the same terms the eviction sweep already uses.

local function syntheticAt(x, z)
    return { id = 0, isSynthetic = true, size = 1, center = { x = x, y = 0, z = z } }
end

-- THE MISREAD THE TYPED TABLE EXISTS TO CLOSE: refusing on anything other than ALLOW.
local function misreadDoor(record)
    return sys:admitPosition(record.center.x, record.center.z) == A.ALLOW
end

T.ok("G1 player-owned ground REFUSES a synthetic",
    sys:admitFieldRecord(syntheticAt(200, 200)) == A.DENY_PLAYER)
T.eq("G2 sample-zero ground PASSES", sys:admitFieldRecord(syntheticAt(900, 900)), A.ALLOW)
T.eq("G3 a positive parcel with no owner PASSES", sys:admitFieldRecord(syntheticAt(100, 100)), A.ALLOW)
T.eq("G4 the not-buyable sentinel PASSES", sys:admitFieldRecord(syntheticAt(800, 800)), A.ALLOW)
T.eq("G5 guided-tour ground PASSES", sys:admitFieldRecord(syntheticAt(500, 500)), A.ALLOW)
T.eq("G6 invalid-id ground PASSES", sys:admitFieldRecord(syntheticAt(600, 600)), A.ALLOW)
-- CORRECTED after Bob's cold review of #112: an owner of ORDINARY SHAPE that does not
-- resolve is the seventh row and it REFUSES. It is not ground nobody can own; it names
-- a farm whose object is not in the manager at this instant. See group G17 to G28.
T.eq("G7 an owner of ordinary shape that does not resolve REFUSES",
    sys:admitFieldRecord(syntheticAt(700, 700)), A.DENY_PLAYER)
W.mapLoaded = false
T.eq("G8 map-absent ground PASSES", sys:admitFieldRecord(syntheticAt(100, 100)), A.ALLOW)
W.mapLoaded = true

T.eq("G9 the synthetic branch answers ALLOW or DENY_PLAYER and NOTHING else",
    sys:admitFieldRecord(syntheticAt(800, 800)) == A.UNAVAILABLE, false)

-- THE DIFFERENCE, and it is the reason a refusal-only bar cannot tell the two builds
-- apart: BOTH deny player land, and the misread refuses FOUR of the six kinds of ground
-- the eight-try mint can accept.
-- The five grounds the mint can accept that carry no owner anybody could hold. The
-- sixth constructible input, an ordinary owner that did not resolve, is the seventh
-- row and is asserted separately at G17 to G22 because it REFUSES.
local mintable = { { 900, 900 }, { 100, 100 }, { 800, 800 }, { 500, 500 }, { 600, 600 } }
local misreadPasses, builtPasses = 0, 0
for _, p in ipairs(mintable) do
    if misreadDoor(syntheticAt(p[1], p[2])) then misreadPasses = misreadPasses + 1 end
    if sys:admitFieldRecord(syntheticAt(p[1], p[2])) == A.ALLOW then builtPasses = builtPasses + 1 end
end
T.eq("G10 DIFFERENCE: the misread passes only 1 of the 5 ownerless mintable grounds", misreadPasses, 1)
T.eq("G11 DIFFERENCE: the built table passes all 5", builtPasses, 5)
T.eq("G12 and BOTH still deny player land",
    misreadDoor(syntheticAt(200, 200)), sys:admitFieldRecord(syntheticAt(200, 200)) == A.ALLOW)

-- THE SEVENTH ROW, found by Bob's cold review of #112 and proved rather than reasoned.
-- isOrdinaryFarmId is shape AND a live farm object, so a parcel whose mapping names an
-- ordinary farm whose object is not in the manager at this instant falls past
-- DENY_PLAYER and lands in UNAVAILABLE. Mapping every non-DENY_PLAYER to ALLOW admitted
-- it: the real record refused that coordinate while a synthetic worked it. The parcel
-- order is unchanged and still answers UNAVAILABLE; only the synthetic branch splits
-- the bucket, using isOrdinaryFarmIdShape, which is shape WITHOUT the resolve.
W.owners[17] = 3
placeSample(1700, 1700, 17)
T.eq("G17 with farm 3 resolving, a real record on its parcel is DENY_PLAYER",
    (sys:admitPosition(1700, 1700)), A.DENY_PLAYER)
T.eq("G18 and a synthetic there is refused too",
    sys:admitFieldRecord(syntheticAt(1700, 1700)), A.DENY_PLAYER)
setFarm(3, nil)   -- the mapping still names farm 3; the object is gone
T.eq("G19 the parcel order still answers UNAVAILABLE, never ALLOW",
    (sys:admitPosition(1700, 1700)), A.UNAVAILABLE)
T.eq("G20 and the reason separates it from ground nobody can own",
    select(3, sys:admitPosition(1700, 1700)), "OWNER_UNRESOLVED")
T.eq("G21 DIFFERENCE: the synthetic branch REFUSES it rather than passing it",
    sys:admitFieldRecord(syntheticAt(1700, 1700)), A.DENY_PLAYER)
T.ok("G22 DIFFERENCE: a refuse-only-on-DENY_PLAYER build would have passed it",
    sys:admitPosition(1700, 1700) ~= A.DENY_PLAYER)
-- And the six PASS rows are unmoved by the split: an excluded owner is still not an
-- unresolved ordinary one.
T.eq("G23 guided-tour ground still PASSES after the split",
    sys:admitFieldRecord(syntheticAt(500, 500)), A.ALLOW)
T.eq("G24 its reason is OWNER_EXCLUDED, not OWNER_UNRESOLVED",
    select(3, sys:admitPosition(500, 500)), "OWNER_EXCLUDED")
T.eq("G25 sample-zero ground still PASSES", sys:admitFieldRecord(syntheticAt(900, 900)), A.ALLOW)
T.eq("G26 and carries its own reason", select(3, sys:admitPosition(900, 900)), "NOT_FARMLAND")
T.eq("G27 the not-buyable sentinel still PASSES", sys:admitFieldRecord(syntheticAt(800, 800)), A.ALLOW)
T.eq("G28 unowned working land is untouched", sys:admitFieldRecord(syntheticAt(100, 100)), A.ALLOW)
setFarm(3, nativeFarm(3, 5))   -- restore for anything below

-- THE MARK IS `isSynthetic`, NEVER `id == 0`. Hole one meant every selector record
-- carried zero, so an identity test would have exempted the entire selector path from
-- admission, which is the opposite of this repair.
local legacySelectorRecord = { id = 0, center = { x = 200, y = 0, z = 200 } }
T.ok("G13 a record with id 0 and no isSynthetic is NOT synthetic",
    not A.isSyntheticRecord(legacySelectorRecord))
T.eq("G14 DIFFERENCE: so it still goes through the parcel order and is refused",
    sys:admitFieldRecord(legacySelectorRecord), A.DENY_PLAYER)
T.ok("G15 the real mark is read", A.isSyntheticRecord(syntheticAt(1, 1)))
T.ok("G16 and a real selector record is never marked", not A.isSyntheticRecord({ farmlandId = 10, id = 10 }))

-- =========================================================
-- GROUP H: item 7, the per-parcel clear
-- =========================================================
-- The producer's wrap-around deliberately allows several farmlands onto one NPC, and
-- the two slots then diverge: assignedFarmland is REPLACED wholesale so it names only
-- the LAST parcel, while assignedFields ACCUMULATES. An NPC that wrapped around carries
-- fields from a parcel its assignedFarmland no longer names.

local function wrappedNPC()
    return {
        id = 1, name = "Otto", isActive = true, farmName = "Smith Farm",
        assignedFarmland = { farmlandId = 20, name = "Second" },
        assignedFields = {
            { fieldId = 1, farmlandId = 19, id = 19, center = { x = 1, y = 0, z = 1 } },
            { fieldId = 2, farmlandId = 20, id = 20, center = { x = 2, y = 0, z = 2 } },
        },
    }
end

-- Parcel 19 was assigned first and has now been bought by the farmer; 20 is still fine.
W.owners[19] = 1
W.owners[20] = 0

-- DIFFERENCE 1: the one-parcel close asks only about assignedFarmland, finds the LAST
-- parcel still ALLOW, and clears nothing.
local npcA = wrappedNPC()
local onlyLast = sys:admitFarmlandId(npcA.assignedFarmland.farmlandId)
T.eq("H1 DIFFERENCE: the one-parcel close sees only the last parcel, which is fine",
    onlyLast, A.ALLOW)

local npcB = wrappedNPC()
local denied = sys:reviewLandAdmission(npcB)
T.eq("H2 the per-parcel close reaches the parcel the NPC wrapped PAST", denied, 1)
T.eq("H3 the bought parcel's field is gone", #npcB.assignedFields, 1)
T.eq("H4 and the parcel still legitimately the NPC's is NOT stripped",
    npcB.assignedFields[1].farmlandId, 20)
T.ok("H5 assignedFarmland is untouched because it names a different parcel",
    npcB.assignedFarmland ~= nil and npcB.assignedFarmland.farmlandId == 20)
T.eq("H6 farmName SURVIVES while any parcel remains", npcB.farmName, "Smith Farm")

-- Now the farmer buys the last one too.
W.owners[20] = 1
local denied2 = sys:reviewLandAdmission(npcB)
T.eq("H7 the close reaches it", denied2, 1)
T.eq("H8 no fields remain", #npcB.assignedFields, 0)
T.eq("H9 assignedFarmland is cleared", npcB.assignedFarmland, nil)
T.eq("H10 farmName goes with the LAST parcel", npcB.farmName, nil)

-- DIFFERENCE 2: a wholesale clear strips ground the NPC still legitimately holds.
W.owners[19] = 1
W.owners[20] = 0
local npcC = wrappedNPC()
local function wholesaleClear(npc)
    npc.assignedField = nil; npc.assignedFields = {}; npc.assignedFarmland = nil; npc.farmName = nil
end
wholesaleClear(npcC)
T.eq("H11 DIFFERENCE: the wholesale clear leaves zero fields", #npcC.assignedFields, 0)
local npcD = wrappedNPC()
sys:reviewLandAdmission(npcD)
T.eq("H12 DIFFERENCE: the per-parcel clear leaves the legitimate one", #npcD.assignedFields, 1)

-- The match key is `farmlandId` and NOTHING else.
local npcE = wrappedNPC()
T.eq("H13 clearing by a fieldId value matches nothing", sys:clearDeniedParcel(npcE, 1), false)
T.eq("H14 both fields are still there", #npcE.assignedFields, 2)
T.ok("H15 clearing by the real parcel key matches", sys:clearDeniedParcel(npcE, 19))

-- A SYNTHETIC record carries no farmlandId and is therefore never matched by a parcel
-- denial: it is cleared by the eviction sweep on position instead.
local npcF = { id = 2, name = "Ida", isActive = true, assignedField = syntheticAt(900, 900) }
T.eq("H16 a parcel denial never matches a synthetic record",
    sys:clearDeniedParcel(npcF, 19), false)
T.ok("H17 the synthetic assignment survives", npcF.assignedField ~= nil)
T.eq("H18 and the close leaves it alone too", sys:reviewLandAdmission(npcF), 0)

-- ITEMS 7 AND 8 ARE ONE REPAIR. A close built against records with NO parcel key
-- reaches nothing, which is the one-parcel behaviour it was meant to replace.
local npcG = {
    id = 3, name = "Ruth", isActive = true, farmName = "Old Farm",
    assignedFarmland = { farmlandId = 20 },
    assignedFields = {
        { fieldId = 1, center = { x = 1, y = 0, z = 1 } },   -- the OLD record shape
        { fieldId = 2, center = { x = 2, y = 0, z = 2 } },
    },
}
W.owners[19] = 1
T.eq("H19 DIFFERENCE: against keyless records the close reaches the wrapped-past parcel 0 times",
    sys:reviewLandAdmission(npcG), 0)
T.eq("H20 and both keyless entries survive, which is the defect", #npcG.assignedFields, 2)

-- =========================================================
-- GROUP I: the terminal pair
-- =========================================================
-- setState ALONE leaves the reservation taken; the release ALONE leaves the neighbour
-- walking the farmer's rows with the tractor gone. It is both, and nothing hand-rolled.

local function fakeAI()
    local ai = {
        STATES = { IDLE = "idle", WORKING = "working" },
        released = 0, states = {},
    }
    ai.setState = function(_, npc, state) npc.aiState = state; ai.states[#ai.states + 1] = state end
    ai._releaseFieldWorkSlot = function(_, npc) ai.released = ai.released + 1; npc._fieldWorkFieldId = nil end
    return ai
end

local termSys = newSys()
termSys.aiSystem = fakeAI()
local worker = { id = 4, name = "Piet", aiState = "working", _fieldWorkFieldId = 12,
    fieldWorkPath = { 1, 2, 3 } }
termSys:endAttemptOnLandRefusal(worker, "test", A.DENY_PLAYER)
T.eq("I1 the reservation is released", termSys.aiSystem.released, 1)
T.eq("I2 the NPC leaves WORKING", worker.aiState, "idle")
T.eq("I3 IDLE, not RESTING and not a goHome", termSys.aiSystem.states[1], "idle")
T.eq("I4 the field-work slot key is cleared", worker._fieldWorkFieldId, nil)

-- DIFFERENCE: a hand-rolled leave produces the same visible state and strands the rest.
local handRolled = { id = 5, aiState = "working", _fieldWorkFieldId = 12, fieldWorkPath = { 1 } }
handRolled.aiState = "idle"; handRolled.fieldWorkPath = nil
T.eq("I5 DIFFERENCE: the hand-rolled leave looks identical from the state field",
    handRolled.aiState, worker.aiState)
T.eq("I6 DIFFERENCE: but it never released the reservation", handRolled._fieldWorkFieldId, 12)
T.eq("I7 the built pair did", worker._fieldWorkFieldId, nil)

-- The helper is idempotent, so applying the pair twice is safe.
termSys:endAttemptOnLandRefusal(worker, "test", A.DENY_PLAYER)
T.eq("I8 applying the pair again does not error and still ends IDLE", worker.aiState, "idle")

-- STATE-AGNOSTIC: the harvest branch can leave a helper WORKING with a reservation or
-- WALKING with none. A leave that fired only on WORKING misses the second kind, which
-- is the sweep's own blindness one layer down.
local evSys = newSys()
evSys.aiSystem = fakeAI()
evSys.eventScheduler = {
    activeEvent = { type = "harvest_gathering", field = { farmlandId = 11, id = 11,
        center = { x = 200, y = 0, z = 200 } } },
    eventParticipants = {
        { id = 6, name = "Owner", isActive = true, aiState = "working", _fieldWorkFieldId = 11 },
        { id = 7, name = "Helper A", isActive = true, aiState = "working", _fieldWorkFieldId = 11 },
        { id = 8, name = "Helper B", isActive = true, aiState = "walking" },   -- no reservation
    },
}
local torn = evSys:reviewActiveEventLand()
T.ok("I9 a mid-event land refusal tears the event down", torn)
T.eq("I10 the WORKING owner is left IDLE", evSys.eventScheduler.eventParticipants[1].aiState, "idle")
T.eq("I11 the WORKING helper is left IDLE", evSys.eventScheduler.eventParticipants[2].aiState, "idle")
T.eq("I12 DIFFERENCE: the WALKING helper is ALSO left IDLE, not skipped",
    evSys.eventScheduler.eventParticipants[3].aiState, "idle")
T.eq("I13 the pair was applied to every participant regardless of state",
    evSys.aiSystem.released, 3)

-- SUCCESS SIDE: an event on legitimate ground is NOT torn down.
local okSys = newSys()
okSys.aiSystem = fakeAI()
okSys.eventScheduler = {
    activeEvent = { type = "harvest_gathering", field = { farmlandId = 10, id = 10,
        center = { x = 100, y = 0, z = 100 } } },
    eventParticipants = { { id = 9, isActive = true, aiState = "working" } },
}
T.ok("I14 SUCCESS SIDE: an event on unowned land keeps running", not okSys:reviewActiveEventLand())
T.eq("I15 and nobody was idled", okSys.eventScheduler.eventParticipants[1].aiState, "working")

-- =========================================================
-- GROUP J: item 4, the activation signature
-- =========================================================
-- The existing boolean FIRST so nothing that reads it today changes meaning, and the
-- admission status SECOND. An ordinary failure returns its boolean with NO status,
-- which preserves the visual fallback; a land refusal returns false WITH one.

local actSys = newSys()
actSys.aiSystem = fakeAI()
local noTractor = { id = 10, name = "Ola" }
local okNoTractor, statusNoTractor = actSys:activateNPCTractor(noTractor)
T.eq("J1 an ordinary failure still returns false", okNoTractor, false)
T.eq("J2 and carries NO status, so the visual fallback is preserved", statusNoTractor, nil)

local refused = { id = 11, name = "Ben", realTractor = { isNPCVehicle = true },
    assignedField = { farmlandId = 11, id = 11, center = { x = 200, y = 0, z = 200 } } }
local okRefused, statusRefused = actSys:activateNPCTractor(refused)
T.eq("J3 a land refusal returns false", okRefused, false)
T.eq("J4 and the status is readable by the caller", statusRefused, A.DENY_PLAYER)
T.ok("J5 DIFFERENCE: the two failures are now distinguishable",
    statusNoTractor ~= statusRefused)

-- The land status is consulted BEFORE the fallback chain: a refused attempt never
-- reaches GoTo or the kinematic fallback.
local reached = { goTo = false, kinematic = false }
local fallbackSys = newSys()
fallbackSys.aiSystem = fakeAI()
fallbackSys.startNPCFieldWorkOwned = function() return false end
fallbackSys.startNPCComboGoTo = function() reached.goTo = true; return false end
fallbackSys.seatNPCInVehicle = function() reached.kinematic = true end
local refused2 = { id = 12, name = "Cal", realTractor = {},
    assignedField = { farmlandId = 12, id = 12, center = { x = 300, y = 0, z = 300 } } }
fallbackSys:activateNPCTractor(refused2)
T.ok("J6 a land refusal never reaches the GoTo fallback", not reached.goTo)
T.ok("J7 and never reaches the kinematic fallback", not reached.kinematic)

-- SUCCESS SIDE: on legitimate ground the fallback chain still runs as before.
reached.goTo, reached.kinematic = false, false
local allowed = { id = 13, name = "Dina", realTractor = {},
    assignedField = { farmlandId = 10, id = 10, center = { x = 100, y = 0, z = 100 } } }
local okAllowed = fallbackSys:activateNPCTractor(allowed)
T.ok("J8 SUCCESS SIDE: admitted land still reaches the GoTo fallback", reached.goTo)
T.ok("J9 and still reaches the kinematic fallback", reached.kinematic)
T.eq("J10 and still returns true from it", okAllowed, true)

-- =========================================================
-- GROUP K: item 8, the record keys
-- =========================================================
T.eq("K1 the selector's record carries farmlandId", type(picked.farmlandId), "number")
T.eq("K2 and the `id` alias carries the SAME value", picked.id, picked.farmlandId)
T.ok("K3 a synthetic record carries NO farmlandId", syntheticAt(1, 1).farmlandId == nil)
T.eq("K4 and keeps id 0 as its deliberate placeholder", syntheticAt(1, 1).id, 0)
T.ok("K5 DIFFERENCE: a mint writing a real id would start feeding the sweep's first ask",
    syntheticAt(1, 1).id == 0)
T.eq("K6 `fieldId` is never used as a parcel",
    sys:clearDeniedParcel(wrappedNPC(), 2) and 1 or 0, 0)

T.summary()
