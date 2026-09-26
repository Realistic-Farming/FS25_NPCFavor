-- =========================================================
-- FS25 NPC Favor Mod - Release gate (NPC-204)
-- =========================================================
-- Which new NPCFavor surfaces are released (STABLE) and which are experimental
-- (LOCKED), per Office Tyson/RELEASE-GATE-DESIGN.md: a per-mod lock registry
-- and one runtime predicate. A surface earns STABLE only when it is built and
-- observed in a real save, its player surface exists, its known high defects
-- are closed and it is balance-safe; releasing it is a deliberate act.
--
-- Orthogonal to difficulty. The opt-in is its own persisted setting,
-- settings.experimentalSystems, default false.
--
-- FAIL-CLOSED. The companion work surface moves money and trust, so an opt-in
-- that cannot be read counts as not opted in. This gate never touches built-in
-- favours, and it never locks an exit: the held work's LET_GO stays available
-- while the surface is LOCKED.
-- =========================================================

NPCReleaseGate = NPCReleaseGate or {}

-- The companion work surface (NPC-204 Implementation v1.1 section 3.7).
NPCReleaseGate.COMPANION_WORK = "npc204_companion_work"

-- The experimental (LOCKED) set. A system not in this table is released.
NPCReleaseGate.EXPERIMENTAL = {
    [NPCReleaseGate.COMPANION_WORK] = {
        name = "Companion work",
        status = "awaiting its Recovery door, a companion caller and in-game observation",
    },
}

--- A system is released when it is not experimental, or when the player has
--- explicitly opted in to experimental systems.
---@param systemId string
---@param optIn boolean|nil
---@return boolean
function NPCReleaseGate.isReleased(systemId, optIn)
    if NPCReleaseGate.EXPERIMENTAL[systemId] == nil then return true end
    return optIn == true
end

--- The live opt-in from a settings object: true or false when it is a readable
--- boolean, nil otherwise.
---@param settings table|nil
---@return boolean|nil
function NPCReleaseGate.liveOptIn(settings)
    if type(settings) ~= "table" then return nil end
    local value = settings.experimentalSystems
    if value == true or value == false then return value end
    return nil
end

--- The single runtime predicate. Fail-closed: an unreadable opt-in is LOCKED.
---@param systemId string
---@param settings table|nil
---@return boolean
function NPCReleaseGate.isSystemLive(systemId, settings)
    return NPCReleaseGate.isReleased(systemId, NPCReleaseGate.liveOptIn(settings) == true)
end
