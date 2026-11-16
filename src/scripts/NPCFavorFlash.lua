-- =========================================================
-- FS25 NPC Favor Mod - Favour pop-ups: who sees them
-- =========================================================
-- Every favour pop-up ("Step 1 done", "Done", "Failed", ...) is raised inside
-- the server's own favour sim. This file decides who it belongs to and gets it
-- there: the host's own screen when the host is one of them, and a
-- NPCFavorFlashEvent to every joined player who is. Before this, the sim called
-- the local HUD directly, so a dedicated server (no screen) and a listen host
-- (its own screen only) never showed a joined player anything.
--
-- Audience, by favour:
--   owned by an ordinary farm      the players of that farm
--   companion (contributed) work   the owning farm and the farm it is addressed to
--   no owner yet (a public offer)  every player who belongs to an ordinary farm
--   an owner that is not ordinary  nobody
-- =========================================================

--- The farms a favour's pop-up belongs to: nil for everyone, else a set of farm ids.
function NPCFavorSystem:flashAudience(favor)
    if type(favor) ~= "table" then return nil end
    local owner = favor.ownerFarmId
    if NPCCompanion ~= nil and NPCCompanion.isContributed(favor) then
        local set = {}
        if NPCFarmIdentity.isOrdinaryFarmId(owner) then set[owner] = true end
        local c = favor.contribution
        if type(c) == "table" and NPCFarmIdentity.isOrdinaryFarmId(c.addressedFarmId) then
            set[c.addressedFarmId] = true
        end
        return set
    end
    if owner == nil then return nil end
    local set = {}
    if NPCFarmIdentity.isOrdinaryFarmId(owner) then set[owner] = true end
    return set
end

--- True when THIS machine's own screen is one of the favour's audience. A
--- machine with no ordinary local farm (a dedicated server) shows nothing for an
--- owned favour; an offer nobody owns shows everywhere, as it always did.
function NPCFavorSystem:mayFlashFavor(favor)
    local audience = self:flashAudience(favor)
    if audience == nil then return true end
    local localFarm = NPCFarmIdentity.localClaimFarmId()
    return localFarm ~= nil and audience[localFarm] == true
end

--- Raise one pop-up for a favour: on this machine's own screen when it belongs
--- there, and to every joined player it belongs to. kind is NPCFavorFlashEvent.KIND;
--- n is the step id of a step pop-up (else 0); text is the favour's own words.
function NPCFavorSystem:raiseFavorFlash(favor, kind, n, text)
    local sys = self.npcSystem
    if sys ~= nil and sys.favorHUD ~= nil and self:mayFlashFavor(favor) then
        local msg, color = NPCFavorFlashEvent.compose(kind, n, text)
        if msg ~= nil then
            sys.favorHUD:flashFavor(msg, color)
        end
    end
    if g_server ~= nil then
        NPCFavorFlashEvent.sendTo(self:flashAudience(favor), kind, n, text)
    end
end

print("[NPC Favor] NPCFavorFlash loaded")
