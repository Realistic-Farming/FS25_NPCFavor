-- =========================================================
-- NpcRfPdaGuest - Esc RF PDA NPC Favor densify (Table shell)
-- Soft-detect: mission.npcFavorSystem. Standing roster rows.
-- Active favors → rfFwMore bridge. Read-only glance; spoiler ban held.
-- =========================================================

NpcRfPdaGuest = {}

local MOD_DIR = g_currentModDirectory
local MOD_NAME = g_currentModName
local PANEL_ID = "npcFavor"
local PANEL_ORDER = 80
local MAX_ROWS = 8
local _registered = false

local TIER_KEYS = {
    ["Hostile"] = "npc_rel_hostile",
    ["Unfriendly"] = "npc_rel_unfriendly",
    ["Neutral"] = "npc_rel_neutral",
    ["Acquaintance"] = "npc_rel_acquaintance",
    ["Friend"] = "npc_rel_friend",
    ["Close Friend"] = "npc_rel_close_friend",
    ["Best Friend"] = "npc_rel_best_friend",
}

local function tr(key, fallback)
    local modEnv = g_modEnvironments and g_modEnvironments[MOD_NAME]
    local i18n = (modEnv and modEnv.i18n) or g_i18n
    if i18n then
        local ok, text = pcall(function() return i18n:getText(key) end)
        if ok and type(text) == "string" and text ~= "" then
            local lower = text:lower()
            if lower ~= tostring(key):lower()
                and text ~= ("$l10n_" .. key)
                and not lower:find("^missing%s")
                and not lower:find("^missing_")
            then
                return text
            end
        end
    end
    return fallback or key
end

local function getHost()
    if g_currentMission ~= nil and g_currentMission.rfEscModules ~= nil then
        return g_currentMission.rfEscModules
    end
    local env = getfenv(0)
    if env ~= nil and env.g_rfEscModules ~= nil then
        return env.g_rfEscModules
    end
    if RfEscModules ~= nil then
        return RfEscModules.getOrCreate()
    end
    return nil
end

local function getHostPage()
    if g_inGameMenu == nil then return nil end
    return g_inGameMenu.menuRealisticFarming
end

local function findDescendant(root, id)
    if root == nil or id == nil then return nil end
    if root.getDescendantById then
        local el = root:getDescendantById(id)
        if el ~= nil then return el end
    end
    local page = getHostPage()
    if page and page.getDescendantById then
        return page:getDescendantById(id)
    end
    return nil
end

local function setText(el, text)
    if el ~= nil and type(el.setText) == "function" then el:setText(text or "") end
end

local function setVis(el, visible)
    if el ~= nil and type(el.setVisible) == "function" then el:setVisible(visible) end
end

local function paintSide(container, key, fallback)
    setVis(findDescendant(container, "wcSideInfoShell"), false)
    setVis(findDescendant(container, "mdSideInfoShell"), false)
    local shell = findDescendant(container, "rfSideInfoShell")
    local body = findDescendant(container, "rfSideInfoBody")
    setVis(shell, true)
    setText(body, tr(key, fallback))
end


local function refreshFwAbs(container)
    local page = getHostPage()
    local host = findDescendant(container, "rfHostPlaceholder") or (page and page.rfHostPlaceholder)
    local shell = findDescendant(container, "rfFrameworkGlanceShell")
    local status = findDescendant(container, "rfFwStatusBlock")
    local tableBlock = findDescendant(container, "rfFwTableBlock")
    for _, el in ipairs({ host, shell, status, tableBlock }) do
        if el ~= nil and type(el.updateAbsolutePosition) == "function" then
            el:updateAbsolutePosition()
        end
    end
end

local function clearHostDupes(container)
    setText(findDescendant(container, "rfHostBody"), "")
    setText(findDescendant(container, "rfHostTitle"), "")
    setText(findDescendant(container, "rfHostBlurb"), "")
    setVis(findDescendant(container, "rfHostTitle"), false)
    setVis(findDescendant(container, "rfHostBlurb"), false)
end

local function showTableMode(container)
    setVis(findDescendant(container, "rfFrameworkGlanceShell"), true)
    setVis(findDescendant(container, "rfFwStatusBlock"), false)
    setVis(findDescendant(container, "rfFwTableBlock"), true)
    refreshFwAbs(container)
end

local function getSys()
    if g_currentMission ~= nil and g_currentMission.npcFavorSystem ~= nil then
        return g_currentMission.npcFavorSystem
    end
    return nil
end

local function getLocalFarmId()
    if g_currentMission == nil then return nil end
    local farmId = g_currentMission.playerFarmId or g_currentMission:getFarmId()
    if farmId == nil and g_currentMission.player ~= nil then
        farmId = g_currentMission.player.farmId
    end
    return farmId
end

-- Urgency: check <1h BEFORE <2h (live guest dead branch fixed).
local function urgencyLabel(favor)
    local ms = tonumber(favor and favor.timeRemaining) or 0
    local hours = ms / (60 * 60 * 1000)
    if hours < 1 then return tr("npc_rf_pda_urg_min", "<1h") end
    if hours < 2 then return tr("npc_rf_pda_urg_hot", "Urgent") end
    if hours < 6 then return tr("npc_rf_pda_urg_warn", "Soon") end
    return string.format("%.0fh", hours)
end

-- favor.name is an l10n key (npc_favor_*); resolve before raw fallback.
local function favorWhat(favor)
    if favor == nil then return "--" end
    local nameKey = favor.name
    if type(nameKey) == "string" and nameKey ~= "" then
        local human = tr(nameKey, nil)
        if human ~= nil and human ~= nameKey then
            return human
        end
        -- tr returned key as fallback - try description / type
    end
    if type(favor.description) == "string" and favor.description ~= "" then
        return favor.description
    end
    if favor.type ~= nil then
        return tostring(favor.type)
    end
    if type(nameKey) == "string" and nameKey ~= "" then
        return nameKey
    end
    return "--"
end

local function tierLabel(levelName)
    if levelName == nil or levelName == "" then return "--" end
    local key = TIER_KEYS[levelName]
    if key ~= nil then
        return tr(key, levelName)
    end
    return tostring(levelName)
end


local function clipCell(s, maxChars)
    s = tostring(s or "")
    maxChars = maxChars or 36
    if #s <= maxChars then
        return s
    end
    local cut = s:sub(1, maxChars)
    local sp = cut:match("^(.*)%s+%S*$")
    if sp ~= nil and #sp >= math.floor(maxChars * 0.55) then
        cut = sp
    end
    return cut .. "..."
end

local function formatBenefits(benefits)
    if benefits == nil then
        return tr("npc_rel_benefit_none", "none")
    end
    local list = {}
    if benefits.discount and benefits.discount > 0 then
        list[#list + 1] = string.format(tr("npc_rel_benefit_discount", "%d%% discount"), benefits.discount)
    end
    if benefits.canAskFavor then
        list[#list + 1] = tr("npc_rel_benefit_favors", "can ask favors")
    end
    if benefits.canBorrowEquipment then
        list[#list + 1] = tr("npc_rel_benefit_borrow", "borrow equipment")
    end
    if benefits.mayOfferHelp then
        list[#list + 1] = tr("npc_rel_benefit_help", "may offer help")
    end
    if benefits.mayGiveGifts then
        list[#list + 1] = tr("npc_rel_benefit_gifts", "gives gifts")
    end
    if benefits.sharedResources then
        list[#list + 1] = tr("npc_rel_benefit_shared", "shared resources")
    end
    if #list == 0 then
        return tr("npc_rel_benefit_none", "none")
    end
    return table.concat(list, " · ")
end

local function countFavorsForNpc(list, npcId)
    local n = 0
    if list == nil or npcId == nil then return 0 end
    for _, favor in ipairs(list) do
        if favor ~= nil and favor.npcId == npcId then
            n = n + 1
        end
    end
    return n
end

local function formatHistory(sys, npcId, info)
    local completed, failed = 0, 0
    if sys ~= nil and sys.favorSystem ~= nil then
        local ok1, completedList = pcall(function() return sys.favorSystem:getCompletedFavors() end)
        if ok1 and completedList then
            completed = countFavorsForNpc(completedList, npcId)
        end
        local ok2, failedList = pcall(function() return sys.favorSystem:getFailedFavors() end)
        if ok2 and failedList then
            failed = countFavorsForNpc(failedList, npcId)
        end
    end
    local total = completed + failed
    if total == 0 then
        return tr("npc_rf_pda_history_none", "no favors yet")
    end
    local pct = math.floor((completed / total) * 100)
    local cell = string.format(tr("npc_rf_pda_history_fmt", "%d%% (%d/%d)"), pct, completed, total)
    local trend = info and info.statistics and info.statistics.trend
    if type(trend) == "number" then
        if trend > 0 then
            cell = cell .. " · " .. tr("npc_rf_pda_trend_warming", "warming")
        elseif trend < 0 then
            cell = cell .. " · " .. tr("npc_rf_pda_trend_cooling", "cooling")
        end
    end
    return cell
end

local function buildRoster(sys)
    local roster = {}
    if sys == nil or type(sys.activeNPCs) ~= "table" then
        return roster
    end
    for _, npc in ipairs(sys.activeNPCs) do
        if npc ~= nil and npc.isActive ~= false then
            local npcId = npc.id
            local info = nil
            if sys.relationshipManager ~= nil and type(sys.relationshipManager.getRelationshipInfo) == "function" then
                local ok, got = pcall(function() return sys.relationshipManager:getRelationshipInfo(npcId) end)
                if ok then info = got end
            end
            local score = nil
            if info ~= nil and info.value ~= nil then
                score = tonumber(info.value)
            end
            if score == nil and type(sys.getRelationshipValue) == "function" then
                local ok, v = pcall(function() return sys:getRelationshipValue(npcId) end)
                if ok then score = tonumber(v) end
            end
            if score == nil then
                score = tonumber(npc.relationship) or 0
            end
            score = math.floor(score + 0.5)

            local level = info and info.level
            if level == nil and sys.relationshipManager ~= nil
                and type(sys.relationshipManager.getRelationshipLevel) == "function" then
                local ok, got = pcall(function() return sys.relationshipManager:getRelationshipLevel(score) end)
                if ok then level = got end
            end

            local benefits = nil
            if level ~= nil and level.benefits ~= nil then
                benefits = level.benefits
            elseif info ~= nil and info.benefits ~= nil then
                benefits = info.benefits
            end

            local who = npc.name
            if who == nil or who == "" then
                who = tostring(npcId or "?")
            end

            local standing
            if level ~= nil and level.name ~= nil then
                standing = string.format("%s · %d", tierLabel(level.name), score)
            else
                standing = "--"
            end

            roster[#roster + 1] = {
                who = tostring(who),
                score = score,
                standing = standing,
                benefits = formatBenefits(benefits),
                history = formatHistory(sys, npcId, info),
            }
        end
    end

    table.sort(roster, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        return string.lower(a.who) < string.lower(b.who)
    end)
    return roster
end

local function collectActiveFavors(sys)
    local favors = {}
    if sys == nil or sys.favorSystem == nil or type(sys.favorSystem.getActiveFavors) ~= "function" then
        return favors
    end
    local ok, list = pcall(function() return sys.favorSystem:getActiveFavors() end)
    if not ok or type(list) ~= "table" then
        return favors
    end
    local farmId = getLocalFarmId()
    local farmFiltered = {}
    for _, favor in ipairs(list) do
        if favor ~= nil then
            if farmId ~= nil and favor.ownerFarmId ~= nil then
                if favor.ownerFarmId == farmId then
                    farmFiltered[#farmFiltered + 1] = favor
                end
            else
                favors[#favors + 1] = favor
            end
        end
    end
    if #farmFiltered > 0 then
        return farmFiltered
    end
    return favors
end

local function hottestFavor(favors)
    local best, bestMs = nil, nil
    for _, favor in ipairs(favors) do
        local ms = tonumber(favor.timeRemaining)
        if ms == nil then ms = math.huge end
        if best == nil or ms < bestMs then
            best = favor
            bestMs = ms
        end
    end
    return best
end

local function favorWho(favor, sys)
    if favor == nil then return "?" end
    if favor.npcName ~= nil and favor.npcName ~= "" then
        return tostring(favor.npcName)
    end
    if sys ~= nil and type(sys.activeNPCs) == "table" and favor.npcId ~= nil then
        for _, npc in ipairs(sys.activeNPCs) do
            if npc ~= nil and npc.id == favor.npcId then
                return tostring(npc.name or favor.npcId)
            end
        end
    end
    return tostring(favor.npcId or "?")
end

local function paintActiveBridge(moreEl, sys, rosterN)
    local favors = collectActiveFavors(sys)
    local parts = {}
    if #favors == 0 then
        parts[#parts + 1] = tr("npc_rf_pda_active_none", "Active favors: none")
    else
        local hot = hottestFavor(favors)
        local who = favorWho(hot, sys)
        local what = favorWhat(hot)
        local urg = urgencyLabel(hot)
        parts[#parts + 1] = string.format(
            tr("npc_rf_pda_active_one", "Active: %s · %s · %s"),
            who, what, urg
        )
        if #favors > 1 then
            parts[#parts + 1] = string.format(
                tr("npc_rf_pda_active_more", "and %d more"),
                #favors - 1
            )
        end
    end
    if rosterN > MAX_ROWS then
        parts[#parts + 1] = string.format(
            tr("npc_rf_pda_showing_of", "showing %d of %d"),
            MAX_ROWS, rosterN
        )
    end
    setText(moreEl, table.concat(parts, " · "))
end

function NpcRfPdaGuest.onShow(container, lightOnly)
    clearHostDupes(container)
    showTableMode(container)
    paintSide(container, "rf_pda_side_info_npc_favor",
        "Neighbor standing roster: who, standing, benefits, history.\n"
        .. "Favor waits show above the table. Esc does not finish favors - use world NPC tools.")
    setText(findDescendant(container, "rfFwTableTitle"), "")
    setVis(findDescendant(container, "rfFwTableTitle"), false)
    setText(findDescendant(container, "rfFwColA"), tr("npc_rf_pda_col_who", "Who"))
    setText(findDescendant(container, "rfFwColB"), tr("npc_rf_pda_col_standing", "Standing"))
    setText(findDescendant(container, "rfFwColC"), tr("npc_rf_pda_col_benefits", "Benefits"))
    setText(findDescendant(container, "rfFwColD"), tr("npc_rf_pda_col_history", "History"))

    local sys = getSys()
    local roster = buildRoster(sys)
    local emptyEl = findDescendant(container, "rfFwEmptyHint")
    local moreEl = findDescendant(container, "rfFwMore")
    local hintEl = findDescendant(container, "rfFwHintTable")

    paintActiveBridge(moreEl, sys, #roster)

    if #roster == 0 then
        setVis(emptyEl, true)
        setText(emptyEl, tr("npc_rf_pda_empty", "no neighbors yet"))
        for i = 1, MAX_ROWS do
            for _, c in ipairs({"A", "B", "C", "D"}) do
                setVis(findDescendant(container, "rfFwRow" .. i .. c), false)
            end
        end
        setText(hintEl, "")
        return
    end

    setVis(emptyEl, false)
    setText(emptyEl, "")
    local show = math.min(#roster, MAX_ROWS)
    for i = 1, MAX_ROWS do
        local a = findDescendant(container, "rfFwRow" .. i .. "A")
        local b = findDescendant(container, "rfFwRow" .. i .. "B")
        local c = findDescendant(container, "rfFwRow" .. i .. "C")
        local d = findDescendant(container, "rfFwRow" .. i .. "D")
        if i <= show then
            local row = roster[i]
            setVis(a, true); setVis(b, true); setVis(c, true); setVis(d, true)
            setText(a, row.who)
            setText(b, row.standing)
            setText(c, clipCell(row.benefits, 34))
            setText(d, clipCell(row.history, 34))
        else
            setVis(a, false); setVis(b, false); setVis(c, false); setVis(d, false)
        end
    end

    -- Hint only when More is not already dense (no overflow clause).
    if #roster > MAX_ROWS then
        setText(hintEl, "")
    else
        setText(hintEl, string.format(
            tr("npc_rf_pda_hint_sort", "%d neighbors · sorted by standing (best first)"),
            #roster
        ))
    end
end

function NpcRfPdaGuest.onHide() end

function NpcRfPdaGuest.tryRegister()
    if RfEscBootstrap ~= nil then
        if MOD_DIR == nil then
            print("[NPCFavor] NpcRfPdaGuest: WARNING MOD_DIR nil - cannot ensureDoor")
        else
            local doorOk = RfEscBootstrap.ensureDoor(MOD_DIR, {
                profilesXml = MOD_DIR .. "xml/gui/rfEscProfiles.xml",
                iconPath = "textures/ui/menuIcon.dds",
            })
            if not doorOk then print("[NPCFavor] NpcRfPdaGuest: WARNING ensureDoor failed (will retry)") end
        end
    end
    local host = getHost()
    local registerFn = host and (host.registerModule or host.registerPanel)
    if host == nil or registerFn == nil then return false end
    if not _registered then
        local ok = registerFn(host, {
            id = PANEL_ID,
            title = tr("npc_rf_pda_module_title", "NPC Favor"),
            blurb = tr("npc_rf_pda_blurb", "Neighbor standing roster: score, tier, benefits, favor history. Active favors on the header line. Read-only."),
            order = PANEL_ORDER,
            isAvailable = function() return getSys() ~= nil end,
            onShow = NpcRfPdaGuest.onShow,
            onHide = NpcRfPdaGuest.onHide,
        })
        if ok then
            _registered = true
            print("[NPCFavor] NpcRfPdaGuest: registered module npcFavor on rfEscModules")
        else
            return false
        end
    end
    return _registered and g_inGameMenu ~= nil and g_inGameMenu.menuRealisticFarming ~= nil
end

function NpcRfPdaGuest.isRegistered() return _registered end
function NpcRfPdaGuest.reset() _registered = false end
