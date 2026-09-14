--!load: src/scripts/NPCFavorSystem.lua
-- RSF-F220 v1.0: expiring one favor must not delete another valid favor.
--
-- Runs the real NPCFavorSystem:update and the real failFavor / getFavorById /
-- getNPCFromFavor / applyFavorPenalties on a controlled fixture. The game clock,
-- relationship manager, interaction UI, HUD and progress check are recorded stubs.
-- No favor generation, money, save or multiplayer path is exercised: update runs
-- server-only in the mod and clients hold no activeFavors.

T.ok("F220 A0 NPCFavorSystem module loaded", type(NPCFavorSystem) == "table")
if type(NPCFavorSystem) ~= "table" then T.summary() return end

-- Fixture ----------------------------------------------------------------
local NOW = 100000
TimeHelper = { getGameTimeMs = function() return NOW end }
g_currentMission.time = 555

local function newSystem()
    local calls = { relationship = {}, uiUpdates = 0, hudFlashes = {}, progress = {}, generate = 0 }
    local npcSystem = {
        activeNPCs = {
            { id = "npcA", name = "Anna", totalFavorsFailed = 0 },
            { id = "npcB", name = "Bert", totalFavorsFailed = 0 },
        },
        relationshipManager = { updateRelationship = function(_s, id, delta, reason)
            calls.relationship[#calls.relationship + 1] = { id = id, delta = delta, reason = reason } end },
        interactionUI = { updateFavorList = function() calls.uiUpdates = calls.uiUpdates + 1 end },
        favorHUD = { flashFavor = function(_s, msg) calls.hudFlashes[#calls.hudFlashes + 1] = msg end },
        settings = { enableFavors = false, debugMode = false },
        playerPosition = nil, playerPositionValid = false,
    }
    local sys = setmetatable({}, NPCFavorSystem_mt)
    sys.npcSystem = npcSystem
    sys.activeFavors, sys.completedFavors, sys.failedFavors, sys.abandonedFavors = {}, {}, {}, {}
    sys.stats = { totalFavorsCompleted = 0, totalRelationshipEarned = 0, totalMoneyEarned = 0, totalXPEarned = 0 }
    -- Recorded stubs for the two neighbours of the expiry branch.
    sys.checkFavorProgress = function(_self, favor) calls.progress[#calls.progress + 1] = favor.id end
    sys.tryGenerateFavorRequest = function() calls.generate = calls.generate + 1 end
    return sys, calls
end

local function favor(id, npcId, expiresIn, extra)
    local f = { id = id, npcId = npcId, npcName = npcId, status = "active",
                description = "job " .. id, expirationGameTime = NOW + expiresIn,
                penalty = { relationship = -5 }, progress = 0.4, loanAmount = 1200,
                loanReturned = false, paymentPending = true, ownerFarmId = 7 }
    if extra then for k, v in pairs(extra) do f[k] = v end end
    return f
end

local function ids(list)
    local out = {}
    for i, f in ipairs(list) do out[i] = f.id end
    return table.concat(out, ",")
end

-- B1: [expired A, live B] keeps B with its record intact.
do
    local sys, calls = newSystem()
    local B = favor("B", "npcB", 5000)
    sys.activeFavors = { favor("A", "npcA", -1), B }
    sys:update(16)
    T.eq("F220 B1 survivor list", ids(sys.activeFavors), "B")
    T.ok("F220 B1 survivor is the same table", sys.activeFavors[1] == B)
    T.eq("F220 B1 survivor status", B.status, "active")
    T.eq("F220 B1 survivor npc", B.npcId, "npcB")
    T.eq("F220 B1 survivor progress", B.progress, 0.4)
    T.eq("F220 B1 survivor loan", B.loanAmount, 1200)
    T.eq("F220 B1 survivor loanReturned", B.loanReturned, false)
    T.eq("F220 B1 survivor paymentPending", B.paymentPending, true)
    T.eq("F220 B1 survivor owner farm", B.ownerFarmId, 7)
    T.eq("F220 B1 survivor timeRemaining", B.timeRemaining, 5000)
    T.eq("F220 B1 failed list", ids(sys.failedFavors), "A")
    T.eq("F220 B1 A status", sys.failedFavors[1].status, "failed")
    T.eq("F220 B1 A reason", sys.failedFavors[1].failureReason, "time_expired")
    T.eq("F220 B1 A failureTime", sys.failedFavors[1].failureTime, 555)
    T.eq("F220 B1 penalty once", #calls.relationship, 1)
    T.eq("F220 B1 penalty target", calls.relationship[1].id, "npcA")
    T.eq("F220 B1 penalty reason", calls.relationship[1].reason, "favor_failed")
    T.eq("F220 B1 npcA stat", sys.npcSystem.activeNPCs[1].totalFavorsFailed, 1)
    T.eq("F220 B1 npcB stat untouched", sys.npcSystem.activeNPCs[2].totalFavorsFailed, 0)
    T.eq("F220 B1 UI update once", calls.uiUpdates, 1)
    T.eq("F220 B1 HUD flash once", #calls.hudFlashes, 1)
    T.eq("F220 B1 live row reached progress check", table.concat(calls.progress, ","), "B")
end

-- B2: expired row in first, middle and last position each fail exactly once.
local function positionCase(label, layout)
    local sys, calls = newSystem()
    local list, expectedLive, expectedFailed = {}, {}, {}
    for i, spec in ipairs(layout) do
        local id = spec[1]
        list[i] = favor(id, "npcA", spec[2] and -1 or 5000)
        if spec[2] then expectedFailed[#expectedFailed + 1] = id else expectedLive[#expectedLive + 1] = id end
    end
    sys.activeFavors = list
    sys:update(16)
    T.eq("F220 B2 " .. label .. " live", ids(sys.activeFavors), table.concat(expectedLive, ","))
    T.eq("F220 B2 " .. label .. " failed count", #sys.failedFavors, #expectedFailed)
    T.eq("F220 B2 " .. label .. " penalties", #calls.relationship, #expectedFailed)
    T.eq("F220 B2 " .. label .. " UI updates", calls.uiUpdates, #expectedFailed)
    T.eq("F220 B2 " .. label .. " HUD flashes", #calls.hudFlashes, #expectedFailed)
    T.eq("F220 B2 " .. label .. " progress checks", #calls.progress, #expectedLive)
    T.eq("F220 B2 " .. label .. " npc stat", sys.npcSystem.activeNPCs[1].totalFavorsFailed, #expectedFailed)
    return sys, calls
end
positionCase("first",    { {"A", true}, {"B"}, {"C"} })
positionCase("middle",   { {"A"}, {"B", true}, {"C"} })
positionCase("last",     { {"A"}, {"B"}, {"C", true} })
positionCase("adjacent", { {"A", true}, {"B", true}, {"C"}, {"D"} })
positionCase("all",      { {"A", true}, {"B", true}, {"C", true} })
positionCase("none",     { {"A"}, {"B"}, {"C"} })

-- B3: a second update repeats nothing.
do
    local sys, calls = positionCase("repeat-setup", { {"A", true}, {"B"} })
    sys:update(16)
    T.eq("F220 B3 second update live", ids(sys.activeFavors), "B")
    T.eq("F220 B3 second update failed", #sys.failedFavors, 1)
    T.eq("F220 B3 second update penalties", #calls.relationship, 1)
    T.eq("F220 B3 second update UI", calls.uiUpdates, 1)
    T.eq("F220 B3 second update progress", table.concat(calls.progress, ","), "B,B")
end

-- B4: expiry exactly at zero remaining counts as expired; one ms left does not.
do
    local sys = newSystem()
    sys.activeFavors = { favor("Z", "npcA", 0), favor("O", "npcA", 1) }
    sys:update(16)
    T.eq("F220 B4 zero expires, one ms stays", ids(sys.activeFavors), "O")
end

-- B5: a row without expirationGameTime keeps its timeRemaining and never expires here.
do
    local sys, calls = newSystem()
    local f = favor("N", "npcA", 0); f.expirationGameTime = nil; f.timeRemaining = nil
    sys.activeFavors = { f }
    sys:update(16)
    T.eq("F220 B5 untimed row stays", ids(sys.activeFavors), "N")
    T.eq("F220 B5 untimed row progressed", table.concat(calls.progress, ","), "N")
end

-- B6: failFavor refusing leaves the row in place (no compensating removal).
do
    local sys, calls = newSystem()
    local A = favor("A", "npcA", -1)
    sys.activeFavors = { A, favor("B", "npcA", 5000) }
    sys.getFavorById = function() return nil end   -- lookup fails: failFavor returns false
    sys:update(16)
    T.eq("F220 B6 refused row retained", ids(sys.activeFavors), "A,B")
    T.eq("F220 B6 nothing failed", #sys.failedFavors, 0)
    T.eq("F220 B6 no penalty", #calls.relationship, 0)
end

-- B7: post-loop generation path unchanged: gated on enableFavors.
do
    local sys, calls = newSystem()
    sys.activeFavors = { favor("A", "npcA", -1) }
    sys:update(16)
    T.eq("F220 B7 generation off", calls.generate, 0)
    sys.npcSystem.settings.enableFavors = true
    sys:update(16)
    T.eq("F220 B7 generation on", calls.generate, 1)
end

-- B8: failFavor is the single removal owner: one call removes exactly once and
-- reports true; a repeat on the same id cannot remove anything more.
do
    local sys = newSystem()
    sys.activeFavors = { favor("A", "npcA", 5000) }
    T.eq("F220 B8 failFavor true", sys:failFavor("A", "time_expired"), true)
    T.eq("F220 B8 active empty", #sys.activeFavors, 0)
    T.eq("F220 B8 failed one", #sys.failedFavors, 1)
    sys:failFavor("A", "time_expired")
    T.eq("F220 B8 repeat leaves active empty", #sys.activeFavors, 0)
end
