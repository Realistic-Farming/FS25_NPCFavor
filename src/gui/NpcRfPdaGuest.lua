-- =========================================================
-- NpcRfPdaGuest - Esc RF PDA NPC Favor densify (Table shell)
-- Soft-detect: mission.npcFavorSystem. Standing roster rows.
-- Active favors → rfFwMore bridge. Read-only glance; spoiler ban held.
-- =========================================================

NpcRfPdaGuest = NpcRfPdaGuest or {}

local MOD_DIR = (NPCFavorModDirectory or g_currentModDirectory)
local MOD_NAME = (NPCFavorModName or g_currentModName)
local PANEL_ID = "npcFavor"
local PANEL_ORDER = 80
local MAX_ROWS = 8
local _registered = false

-- BUILD 09:19 (PB-07). The roster is painted into rfFwTableBlock, a STATIC eight-row table
-- shared with Income, Dairy and Depot. With 11 neighbours the footer said "showing 8 of 11"
-- and the last three were unreachable: the block is not a SmoothList, so there was nothing
-- to scroll and no control to press.
--
-- This is a window over the sorted roster, not a new list. _pageIndex is which slice of
-- eight is on screen; the host's two rfFwPage* Buttons step it and repaint. A SmoothList
-- was rejected on George's standing hang lesson for this page (the same NO-GO that keeps
-- csConsultPanel on fixed Texts), and a window needs none of that machinery.
--
-- _lastRosterCount is what onPageStep clamps against. The host calls onPageStep BEFORE the
-- repaint, so at that moment the only honest roster size available is the one the last paint
-- actually put on screen; re-reading the system there could clamp against a count the player
-- has not been shown yet.
local _pageIndex = 1
local _lastRosterCount = 0

local function pageCountFor(n)
    if n == nil or n <= 0 then
        return 1
    end
    return math.max(1, math.ceil(n / MAX_ROWS))
end

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

local function paintActiveBridge(moreEl, sys, rosterN, firstRow, lastRow)
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
    -- BUILD 09:19 (PB-07): the range now describes the window that is actually on screen and
    -- moves with it. "showing 8 of 11" was both unreachable and, once paging exists, wrong on
    -- every page but the first.
    if rosterN > MAX_ROWS then
        parts[#parts + 1] = string.format(
            tr("npc_rf_pda_showing_range", "showing %d-%d of %d"),
            firstRow, lastRow, rosterN
        )
    end
    setText(moreEl, table.concat(parts, " · "))
end

local _rfFwTitleBaselineWarned = false

--- rfFwTableTitle is shared by every Table-mode module (Income, Dairy, Depot, NPCFavor).
--- Income deliberately drops it to the bottom band (-360) for its own glance, and no host
--- calls onHide, so whoever shows next must reassert its own baseline or it inherits
--- Income's position. Cheap, idempotent, and keeps each guest owning its own layout.
local function resetFwTableTitlePos(container)
    local el = findDescendant(container, "rfFwTableTitle")
    if el == nil or type(el.setPosition) ~= "function" then return end
    if GuiUtils == nil or type(GuiUtils.getNormalizedXValue) ~= "function"
        or type(GuiUtils.getNormalizedYValue) ~= "function" then
        if not _rfFwTitleBaselineWarned then
            _rfFwTitleBaselineWarned = true
            print("[NPCFavor] NpcRfPdaGuest: GuiUtils normalizer absent - cannot reassert rfFwTableTitle baseline")
        end
        return
    end
    -- BUILD 21:41: 0 / 0 is the PRE-16:32 baseline. The shared XML has had this title
    -- at 10 / -8 since the white-card inset, so the old reset handed it back to a place
    -- that no longer exists. Same miss Depot had.
    el:setPosition(GuiUtils.getNormalizedXValue("10px", 0), GuiUtils.getNormalizedYValue("-8px", 0))
    if type(el.updateAbsolutePosition) == "function" then el:updateAbsolutePosition() end
end

-- ============================================================
-- BUILD 21:41: the column grid, applied every show.
-- ============================================================
-- All four Table guests (Income, Depot, Dairy, NPC Favor) paint into the SAME shared
-- elements, so whichever ran last leaves its geometry behind for the next one. Every guest
-- therefore has to state its own grid on entry rather than assume the XML baseline, or it
-- inherits the previous module's columns. This block is the XML freeze.
--
-- Y IS HELD. Each move reads the element's own current Y and writes it straight back, and
-- setSize keeps the element's own height, so this can only ever change X and width.
--
-- Positions and sizes are NORMALISED in FS25, so everything goes through GuiUtils. A raw
-- pixel integer here would throw the row off the screen.
local FW_GRID_COLS = {
    { "A", "10px", "280px" },
    { "B", "310px", "280px" },
    { "C", "610px", "220px" },
    { "D", "850px", "280px" },
}
local FW_GRID_RULES = { "300px", "600px", "840px" }
local _fwGridWarned = false

local function applyFwGrid(container)
    if GuiUtils == nil or type(GuiUtils.getNormalizedXValue) ~= "function"
        or type(GuiUtils.getNormalizedScreenValues) ~= "function" then
        if not _fwGridWarned then
            _fwGridWarned = true
            print("[RF] applyFwGrid: GuiUtils normalizer absent - leaving the XML grid")
        end
        return
    end

    local function place(el, xPx, wPx)
        if el == nil then return end
        if type(el.setPosition) == "function" and el.position ~= nil then
            el:setPosition(GuiUtils.getNormalizedXValue(xPx, 0), el.position[2])
        end
        if wPx ~= nil and type(el.setSize) == "function" and el.size ~= nil then
            local norms = GuiUtils.getNormalizedScreenValues(wPx .. " 1px")
            if type(norms) == "table" and norms[1] ~= nil then
                el:setSize(norms[1], el.size[2])
            end
        end
        if type(el.updateAbsolutePosition) == "function" then el:updateAbsolutePosition() end
    end

    -- BUILD 21:54: this was ipairs over a table my generator had written with ",," between
    -- entries, which puts a nil at the skipped index. ipairs stops at the first nil, so only
    -- column A was ever placed and B, C and D stayed on the freeze XML while the rules moved
    -- anyway. A literal 1..4 walk cannot be truncated by a hole, and skipping a nil entry
    -- costs one column rather than throwing inside onShow.
    for i = 1, 4 do
        local c = FW_GRID_COLS[i]
        if c ~= nil then
            local letter, xPx, wPx = c[1], c[2], c[3]
            place(findDescendant(container, "rfFwCol" .. letter), xPx, wPx)
            for row = 1, 8 do
                place(findDescendant(container, "rfFwRow" .. row .. letter), xPx, wPx)
            end
        end
    end
    -- Vertical rules keep their own Y and their 1px width; only the column boundary moves.
    for i, xPx in ipairs(FW_GRID_RULES) do
        place(findDescendant(container, "rfFwRuleCol" .. i), xPx, nil)
    end
end

-- ============================================================
-- BUILD 07:06: put the shared empty-hint box back.
-- ============================================================
-- rfFwEmptyHint is ONE element behind all nine doors. Income and Depot now shrink it to bay A
-- (10 / 280 / -68 / 22) so their empty notice sits in the first cell instead of running across
-- the grid. applyFwGrid does not list that id, so without this an empty Income visited earlier
-- in the same session leaves this page's notice in a 280x22 box.
--
-- This page never uses bay A. It restores the XML numbers verbatim, every show, before the
-- text is set, so the notice is painted into a box that is already the right size.
local FW_HINT_X = "10px"
local FW_HINT_Y = "-68px"
local FW_HINT_W = "1120px"
local FW_HINT_H = "44px"

local function restoreFwEmptyHintBox(container)
    local el = findDescendant(container, "rfFwEmptyHint")
    if el == nil then
        return
    end
    if GuiUtils == nil or type(GuiUtils.getNormalizedXValue) ~= "function"
        or type(GuiUtils.getNormalizedYValue) ~= "function"
        or type(GuiUtils.getNormalizedScreenValues) ~= "function" then
        return
    end
    el.textMaxNumLines = 2
    local norms = GuiUtils.getNormalizedScreenValues(FW_HINT_W .. " " .. FW_HINT_H)
    if type(norms) ~= "table" or norms[1] == nil or norms[2] == nil then
        return
    end
    if type(el.setSize) == "function" then
        el:setSize(norms[1], norms[2])
    end
    if type(el.setPosition) == "function" then
        el:setPosition(GuiUtils.getNormalizedXValue(FW_HINT_X, 0),
                       GuiUtils.getNormalizedYValue(FW_HINT_Y, 0))
        if type(el.updateAbsolutePosition) == "function" then el:updateAbsolutePosition() end
    end
end

local function stripButtonGlyph(btn)
    if btn == nil then return end
    btn.inputActionName = nil
    btn.keyDisplayText = nil
    btn.keyOverlay = nil
    btn.hideKeyboardGlyph = true
    btn.hasLoadedInputGlyph = false
    btn.isKeyboardMode = false
    btn.keyGlyphOffsetX = 0
    btn.keyGlyphSize = { 0, 0 }
    btn.iconSize = { 0, 0 }
    btn.icon = {}
end

--- BUILD 09:19 (PB-07): show and label the two shared row-pager Buttons.
---
--- The host hides both on every refresh before the guest paints (see _syncHostGuestChrome),
--- so this is the only thing that turns them on and the other three Table guests are
--- untouched. One page means no pager at all rather than two dead buttons - Sam's single-page
--- feel lock on the module pager reads the same here: a control that cannot act should not
--- look like one that can.
---
--- The Next button carries the page position rather than a bare arrow, so the player can see
--- there is a page 2 without counting rows.
local function paintPager(container, rosterN, pages)
    local prevEl = findDescendant(container, "rfFwPagePrev")
    local nextEl = findDescendant(container, "rfFwPageNext")
    local multi = rosterN > MAX_ROWS and pages > 1

    stripButtonGlyph(prevEl)
    stripButtonGlyph(nextEl)

    for _, el in ipairs({ prevEl, nextEl }) do
        if el ~= nil then
            if type(el.setVisible) == "function" then el:setVisible(multi) end
            if type(el.setDisabled) == "function" then el:setDisabled(not multi) end
        end
    end
    if not multi then
        return
    end

    if prevEl ~= nil and type(prevEl.setText) == "function" then
        prevEl:setText(tr("npc_rf_pda_page_prev", "< Back"))
        stripButtonGlyph(prevEl)
    end
    if nextEl ~= nil and type(nextEl.setText) == "function" then
        nextEl:setText(string.format(
            tr("npc_rf_pda_page_next", "More (%d/%d) >"), _pageIndex, pages))
        stripButtonGlyph(nextEl)
    end
end

function NpcRfPdaGuest.onShow(container, lightOnly)
    applyFwGrid(container)
    restoreFwEmptyHintBox(container)
    resetFwTableTitlePos(container)
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

    -- BUILD 09:19 (PB-07): resolve the window before anything is painted, so the rows, the
    -- footer range and the two buttons all describe the same slice.
    local rosterN = #roster
    _lastRosterCount = rosterN
    local pages = pageCountFor(rosterN)
    if _pageIndex > pages then _pageIndex = pages end
    if _pageIndex < 1 then _pageIndex = 1 end
    local firstRow = (_pageIndex - 1) * MAX_ROWS + 1
    local lastRow = math.min(rosterN, _pageIndex * MAX_ROWS)

    paintActiveBridge(moreEl, sys, rosterN, firstRow, lastRow)
    paintPager(container, rosterN, pages)

    if rosterN == 0 then
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
    -- How many of the eight slots this page fills. A short last page (11 neighbours = 8 + 3)
    -- hides the slots it does not use rather than leaving the previous page's names in them.
    local show = lastRow - firstRow + 1
    for i = 1, MAX_ROWS do
        local a = findDescendant(container, "rfFwRow" .. i .. "A")
        local b = findDescendant(container, "rfFwRow" .. i .. "B")
        local c = findDescendant(container, "rfFwRow" .. i .. "C")
        local d = findDescendant(container, "rfFwRow" .. i .. "D")
        if i <= show then
            local row = roster[firstRow + i - 1]
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
    if rosterN > MAX_ROWS then
        setText(hintEl, "")
    else
        setText(hintEl, string.format(
            tr("npc_rf_pda_hint_sort", "%d neighbors · sorted by standing (best first)"),
            rosterN
        ))
    end
end

--- BUILD 09:19 (PB-07): one page step from the host's rfFwPage* Buttons.
--- Wraps at both ends, the same way the module pager beside it does, so neither button is
--- ever a dead click. Returns false when nothing moved so the host can skip a repaint.
---@param delta number -1 previous page, +1 next page
---@return boolean moved
function NpcRfPdaGuest.onPageStep(delta)
    local pages = pageCountFor(_lastRosterCount)
    if pages <= 1 then
        return false
    end
    local step = tonumber(delta) or 0
    if step == 0 then
        return false
    end
    local target = _pageIndex + (step > 0 and 1 or -1)
    if target > pages then target = 1 end
    if target < 1 then target = pages end
    if target == _pageIndex then
        return false
    end
    _pageIndex = target
    return true
end

function NpcRfPdaGuest.onHide()
    -- BUILD 14:04: leaving the module puts the roster back on page 1. The 09:19 build kept
    -- the index across hide so a returning player landed on the slice they left; the 14:04
    -- brief pins it the other way (module _currentPage, reset on hide), and the brief wins:
    -- a re-entered roster always opens on its best-standing head, which is also the only
    -- state whose MORE label needs no memory to be true.
    _pageIndex = 1
end

--- BUILD 14:04: publish the guest handle the same way MdRfPdaGuest publishes its classes
--- (mdPublishHandles, BUILD 11:43/12:59) - sandbox root plus mission handle, re-published
--- on every register attempt so a reload cannot leave it stale. Vera's live gates have
--- shown the mission handle is the one cross-env channel that actually resolves on the
--- live engine (via=mission), and the host's _rfFwPageStep belt reaches this guest through
--- exactly that channel when a stale registry copy has eaten the registered onPageStep.
local function npcPublishHandles()
    local okEnv, root = pcall(getfenv, 0)
    if okEnv and type(root) == "table" then
        root.NpcRfPdaGuest = NpcRfPdaGuest
    end
    if g_currentMission ~= nil then
        g_currentMission.NpcRfPdaGuest = NpcRfPdaGuest
    end
end

function NpcRfPdaGuest.tryRegister()
    npcPublishHandles()
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
            -- BUILD 09:19 (PB-07): the host reads onPageStep off the REGISTERED descriptor,
            -- not off the guest table, so the pager only exists for a module that opts in
            -- here. Leaving it out is what keeps Income / Dairy / Depot unpaged and
            -- unchanged. BUILD 14:04: this registration is only real once
            -- RfEscModules:registerModule carries onPageStep in its whitelist - it did not,
            -- the field was silently dropped, and the live MORE was a painted no-op. The
            -- page index resets to 1 in onHide (14:04 brief), and onShow still re-clamps it
            -- against the live roster so a shrunk roster cannot strand anyone.
            onPageStep = NpcRfPdaGuest.onPageStep,
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
function NpcRfPdaGuest.reset()
    _registered = false
    -- A reset is a re-register, i.e. a new session or a re-entered save. The remembered
    -- page belongs to the roster that is going away with it.
    _pageIndex = 1
    _lastRosterCount = 0
end
