-- =========================================================
-- FS25 NPC Favor — Settings Panel
-- =========================================================
-- Fully custom-drawn settings panel. No XML — pure overlay.
-- Open/close: F5
-- Landing page → category card → settings list.
-- =========================================================

---@class NPCSettingsPanel
NPCSettingsPanel = {}
local NPCSettingsPanel_mt = Class(NPCSettingsPanel)

local NPC_MOD_NAME = g_currentModName

-- ── i18n helper ───────────────────────────────────────────
local function tr(key, fallback)
    local modEnv = g_modEnvironments and g_modEnvironments[NPC_MOD_NAME]
    local i18n   = (modEnv and modEnv.i18n) or g_i18n
    if i18n then
        local ok, text = pcall(function() return i18n:getText(key) end)
        if ok and text and text ~= "" and text ~= ("$l10n_" .. key) then
            return text
        end
    end
    return fallback or key
end

-- ── Panel geometry (normalized, Y=0 at bottom) ────────────
local PW   = 0.62
local PH   = 0.76
local PX   = (1 - PW) / 2
local PY   = (1 - PH) / 2

local TB_H = 0.052
local IB_H = 0.046
local PAD  = 0.018

local CX     = PX + PAD
local CW     = PW - PAD * 2
local CY_BOT = PY + IB_H + 0.010
local CY_TOP = PY + PH - TB_H - 0.008
local CH     = CY_TOP - CY_BOT

-- Landing: 3 category cards
local CARD_GAP = 0.012
local CARD_W   = (CW - CARD_GAP * 2) / 3
local CARD_H   = 0.30
local CARD_Y   = CY_BOT + (CH - CARD_H) / 2

-- Category page rows
local ROW_H    = 0.036
local SEC_H    = 0.026
local TOGGLE_W = 0.048
local TOGGLE_H = 0.026
local TOGGLE_GAP = 0.004
local MULTI_W  = 0.175

-- Text sizes
local TS_TITLE = 0.018
local TS_BODY  = 0.015
local TS_SMALL = 0.013
local TS_TINY  = 0.011

-- ── Colors ────────────────────────────────────────────────
local C = {
    bg          = {0.04, 0.05, 0.09, 0.97},
    title_bg    = {0.06, 0.08, 0.12, 1.0},
    info_bg     = {0.03, 0.04, 0.07, 1.0},
    border      = {0.90, 0.72, 0.20, 0.40},
    shadow      = {0.00, 0.00, 0.00, 0.45},
    divider     = {0.20, 0.22, 0.28, 0.55},
    row_alt     = {1.00, 1.00, 1.00, 0.025},
    row_hover   = {0.90, 0.72, 0.20, 0.08},
    white       = {1.00, 1.00, 1.00, 1.0},
    dim         = {0.55, 0.55, 0.60, 1.0},
    hint        = {0.38, 0.38, 0.46, 1.0},
    on_bg       = {0.22, 0.75, 0.33, 1.0},
    off_bg      = {0.15, 0.16, 0.20, 1.0},
    on_text     = {0.00, 0.00, 0.00, 1.0},
    off_text    = {0.45, 0.46, 0.52, 1.0},
    lock_bg     = {0.22, 0.14, 0.05, 0.70},
    lock_text   = {0.88, 0.60, 0.18, 1.0},
    card_hover  = {1.00, 1.00, 1.00, 0.04},
    close_hover = {0.88, 0.25, 0.25, 0.80},
    back_hover  = {0.90, 0.72, 0.20, 0.18},
    green       = {0.32, 0.88, 0.44, 1.0},
    green_dim   = {0.20, 0.55, 0.28, 1.0},
    -- Category accents
    accent_npc  = {0.90, 0.72, 0.20, 1.0},   -- amber  — NPC Behavior
    accent_disp = {0.35, 0.60, 0.95, 1.0},   -- blue   — Display
    accent_play = {0.32, 0.88, 0.44, 1.0},   -- green  — Gameplay
    admin_acc   = {0.88, 0.25, 0.25, 1.0},   -- red    — Admin
    info_admin  = {0.32, 0.88, 0.44, 1.0},
    info_no_adm = {0.88, 0.60, 0.18, 1.0},
    info_mode   = {0.55, 0.55, 0.62, 1.0},
}

-- ── Multi-option definitions ───────────────────────────────
-- values: the actual stored value; labels: display string or i18n key; i18n=true if labels are keys
local MULTI_OPTS = {
    maxNPCs = {
        values = {2, 4, 6, 8, 10, 12, 16},
        labels = {"2", "4", "6", "8", "10", "12", "16"},
    },
    maxActiveFavors = {
        values = {1, 2, 3, 5, 8, 10},
        labels = {"1", "2", "3", "5", "8", "10"},
    },
    favorHudScale = {
        values = {0.75, 1.0, 1.25, 1.5},
        labels = {"75%", "100%", "125%", "150%"},
    },
    favorFrequency = {
        values = {1, 2, 3, 4, 5},
        labels = {"npc_freq_1", "npc_freq_2", "npc_freq_3", "npc_freq_4", "npc_freq_5"},
        i18n   = true,
    },
    npcWorkStart = {
        values = {5, 6, 7, 8, 9, 10, 11, 12},
        labels = {"5h", "6h", "7h", "8h", "9h", "10h", "11h", "12h"},
    },
    npcWorkEnd = {
        values = {14, 15, 16, 17, 18, 19, 20, 21, 22},
        labels = {"14h", "15h", "16h", "17h", "18h", "19h", "20h", "21h", "22h"},
    },
    npcActivityLevel = {
        values = {"low", "normal", "high"},
        labels = {"npc_activity_low", "npc_activity_normal", "npc_activity_high"},
        i18n   = true,
    },
    favorDifficulty = {
        values = {"easy", "normal", "hard"},
        labels = {"npc_diff_easy", "npc_diff_normal", "npc_diff_hard"},
        i18n   = true,
    },
}

-- ── Setting labels (label i18n key + English fallback) ────
local SETTING_LABELS = {
    enabled                = { key = "npc_enabled_short",           fb = "Enable NPC System"    },
    maxNPCs                = { key = "npc_max_count_short",         fb = "Max NPC Count"         },
    favorFrequency         = { key = "npc_favor_freq_short",        fb = "Favor Frequency"       },
    npcWorkStart           = { key = "npc_work_start_short",        fb = "Work Day Start"        },
    npcWorkEnd             = { key = "npc_work_end_short",          fb = "Work Day End"          },
    npcActivityLevel       = { key = "npc_activity_level_short",    fb = "Activity Level"        },
    npcSocialize           = { key = "npc_socialize_short",         fb = "Enable Socializing"    },
    npcHelpPlayer          = { key = "npc_help_player_short",       fb = "Offer Help to Player"  },
    showFavorList          = { key = "npc_show_favor_list_short",   fb = "Show Favor List"       },
    favorHudScale          = { key = "npc_hud_scale_short",         fb = "Favor HUD Scale"       },
    favorHudLocked         = { key = "npc_hud_locked_short",        fb = "Lock Favor HUD"        },
    showNames              = { key = "npc_show_names_short",        fb = "Show NPC Names"        },
    showRelationshipBars   = { key = "npc_show_rel_bars_short",     fb = "Relationship Bars"     },
    showMapMarkers         = { key = "npc_show_map_markers_short",  fb = "Show Map Markers"      },
    showNotifications      = { key = "npc_show_notifications_short",fb = "Show Notifications"    },
    enableFavors           = { key = "npc_enable_favors_short",     fb = "Enable Favors"         },
    allowMultipleFavors    = { key = "npc_allow_multi_favors_short",fb = "Multiple Favors"       },
    maxActiveFavors        = { key = "npc_max_active_favors_short", fb = "Max Active Favors"     },
    favorTimeLimit         = { key = "npc_favor_time_limit_short",  fb = "Favor Time Limit"      },
    favorDifficulty        = { key = "npc_favor_difficulty_short",  fb = "Favor Difficulty"      },
    enableGifts            = { key = "npc_enable_gifts_short",      fb = "Enable Gifts"          },
    enableRelationshipSystem = { key = "npc_rel_system_short",      fb = "Relationship System"   },
    relationshipDecay      = { key = "npc_rel_decay_short",         fb = "Relationship Decay"    },
    debugMode              = { key = "npc_debug_short",             fb = "Debug Mode"            },
    showPaths              = { key = "npc_show_paths_short",        fb = "Show NPC Paths"        },
    showAIDecisions        = { key = "npc_show_ai_short",           fb = "AI Decisions"          },
}

-- Short descriptions shown as sub-labels in setting rows
local SETTING_DESCS = {
    enabled                = "npc_desc_enabled",
    maxNPCs                = "npc_desc_maxNPCs",
    favorFrequency         = "npc_desc_favorFrequency",
    npcWorkStart           = "npc_desc_npcWorkStart",
    npcWorkEnd             = "npc_desc_npcWorkEnd",
    npcActivityLevel       = "npc_desc_npcActivityLevel",
    npcSocialize           = "npc_desc_npcSocialize",
    npcHelpPlayer          = "npc_desc_npcHelpPlayer",
    showFavorList          = "npc_desc_showFavorList",
    favorHudScale          = "npc_desc_favorHudScale",
    favorHudLocked         = "npc_desc_favorHudLocked",
    showNames              = "npc_desc_showNames",
    showRelationshipBars   = "npc_desc_showRelationshipBars",
    showMapMarkers         = "npc_desc_showMapMarkers",
    showNotifications      = "npc_desc_showNotifications",
    enableFavors           = "npc_desc_enableFavors",
    allowMultipleFavors    = "npc_desc_allowMultipleFavors",
    maxActiveFavors        = "npc_desc_maxActiveFavors",
    favorTimeLimit         = "npc_desc_favorTimeLimit",
    favorDifficulty        = "npc_desc_favorDifficulty",
    enableGifts            = "npc_desc_enableGifts",
    enableRelationshipSystem = "npc_desc_enableRelationshipSystem",
    relationshipDecay      = "npc_desc_relationshipDecay",
    debugMode              = "npc_desc_debugMode",
    showPaths              = "npc_desc_showPaths",
    showAIDecisions        = "npc_desc_showAIDecisions",
}

-- Settings applied locally (no admin check, no network sync)
local LOCAL_ONLY = {
    showNames = true, showNotifications = true, showFavorList = true,
    showRelationshipBars = true, showMapMarkers = true,
    favorHudScale = true, favorHudLocked = true,
    showPaths = true, showAIDecisions = true, debugMode = true,
}

-- ── Category / section definitions ────────────────────────
local CATEGORIES = {
    {
        id       = "behavior",
        labelKey = "npc_panel_cat_behavior",
        descKey  = "npc_panel_cat_behavior_desc",
        accent   = C.accent_npc,
        sections = {
            { headerKey = "npc_panel_hdr_core",     items = {"enabled", "maxNPCs", "favorFrequency"} },
            { headerKey = "npc_panel_hdr_schedule",  items = {"npcWorkStart", "npcWorkEnd", "npcActivityLevel"} },
            { headerKey = "npc_panel_hdr_social",    items = {"npcSocialize", "npcHelpPlayer"} },
        },
    },
    {
        id       = "display",
        labelKey = "npc_panel_cat_display",
        descKey  = "npc_panel_cat_display_desc",
        accent   = C.accent_disp,
        sections = {
            { headerKey = "npc_panel_hdr_hud",   items = {"showFavorList", "favorHudScale", "favorHudLocked"} },
            { headerKey = "npc_panel_hdr_world",  items = {"showNames", "showRelationshipBars", "showMapMarkers", "showNotifications"} },
        },
    },
    {
        id       = "gameplay",
        labelKey = "npc_panel_cat_gameplay",
        descKey  = "npc_panel_cat_gameplay_desc",
        accent   = C.accent_play,
        sections = {
            { headerKey = "npc_panel_hdr_favors",    items = {"enableFavors", "allowMultipleFavors", "maxActiveFavors", "favorTimeLimit", "favorDifficulty"} },
            { headerKey = "npc_panel_hdr_relations",  items = {"enableGifts", "enableRelationshipSystem", "relationshipDecay"} },
        },
    },
}

local ADMIN_SECTIONS = {
    {
        headerKey = "npc_panel_hdr_admin_sys",
        items = {
            { stype = "setting", id = "enabled"        },
            { stype = "setting", id = "debugMode"      },
            { stype = "setting", id = "showPaths"      },
            { stype = "setting", id = "showAIDecisions"},
        },
    },
    {
        headerKey = "npc_panel_hdr_admin_actions",
        items = {
            { stype = "action", id = "admin_save"  },
            { stype = "danger", id = "admin_reset" },
        },
    },
}

local ADMIN_ROW_H  = 0.033
local ADMIN_ACT_H  = 0.028

-- Pages
local PAGE_LANDING  = "landing"
local PAGE_CATEGORY = "category"
local PAGE_ADMIN    = "admin"

-- ── Constructor ───────────────────────────────────────────
function NPCSettingsPanel.new(settings)
    local self = setmetatable({}, NPCSettingsPanel_mt)
    self.settings     = settings
    self.fillOverlay  = nil
    self.isVisible    = false
    self.initialized  = false
    self.page         = PAGE_LANDING
    self.activeCatIdx = nil
    self.mouseX       = 0
    self.mouseY       = 0
    self.savedCamRotX = nil
    self.savedCamRotY = nil
    self.savedCamRotZ = nil
    self._clickRects  = {}
    return self
end

function NPCSettingsPanel:initialize()
    if self.initialized then return end
    if createImageOverlay then
        self.fillOverlay = createImageOverlay("dataS/menu/base/graph_pixel.dds")
    end
    self.initialized = true
end

function NPCSettingsPanel:delete()
    if self.fillOverlay then
        delete(self.fillOverlay)
        self.fillOverlay = nil
    end
    self.initialized = false
end

-- ── Visibility ────────────────────────────────────────────
function NPCSettingsPanel:open()
    if not self.initialized then self:initialize() end
    self.isVisible    = true
    self.page         = PAGE_LANDING
    self.activeCatIdx = nil
    self.savedCamRotX = nil
    self.savedCamRotY = nil
    self.savedCamRotZ = nil
    if getCamera and getRotation then
        local ok, cam = pcall(getCamera)
        if ok and cam and cam ~= 0 then
            local ok2, rx, ry, rz = pcall(getRotation, cam)
            if ok2 then
                self.savedCamRotX, self.savedCamRotY, self.savedCamRotZ = rx, ry, rz
            end
        end
    end
    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(true, true)
    end
end

function NPCSettingsPanel:close()
    self.isVisible    = false
    self.savedCamRotX = nil
    self.savedCamRotY = nil
    self.savedCamRotZ = nil
    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(false)
    end
end

function NPCSettingsPanel:toggle()
    if self.isVisible then self:close() else self:open() end
end

function NPCSettingsPanel:isOpen()
    return self.isVisible
end

-- Called every frame from NPCSystem:update()
function NPCSettingsPanel:update()
    if not self.isVisible then return end
    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(true, true)
    end
    -- Freeze camera so mouse-look doesn't spin the world while panel is open
    if self.savedCamRotX ~= nil and getCamera and setRotation then
        local ok, cam = pcall(getCamera)
        if ok and cam and cam ~= 0 then
            pcall(setRotation, cam, self.savedCamRotX, self.savedCamRotY, self.savedCamRotZ)
        end
    end
    -- Auto-close when a game dialog/menu opens on top
    if g_gui and (g_gui:getIsGuiVisible() or g_gui:getIsDialogVisible()) then
        self:close()
    end
end

-- ── Admin / routing helpers ───────────────────────────────
function NPCSettingsPanel:isAdmin()
    if g_server ~= nil then return true end
    if g_currentMission and g_currentMission.missionDynamicInfo then
        if not g_currentMission.missionDynamicInfo.isMultiplayer then
            return true
        end
    end
    if g_localPlayer and g_localPlayer.getIsAdmin then
        return g_localPlayer:getIsAdmin()
    end
    return false
end

function NPCSettingsPanel:getValue(id)
    return self.settings and self.settings[id]
end

function NPCSettingsPanel:requestChange(id, value)
    if not id or not self.settings then return end

    -- Clamp work-hour ordering so end > start
    if id == "npcWorkStart" then
        local endH = self.settings.npcWorkEnd or 17
        if value >= endH then value = endH - 1 end
    elseif id == "npcWorkEnd" then
        local startH = self.settings.npcWorkStart or 8
        if value <= startH then value = startH + 1 end
    end

    if LOCAL_ONLY[id] then
        self.settings[id] = value
        -- Live side-effects
        if id == "favorHudScale" then
            if g_NPCSystem and g_NPCSystem.favorHUD then
                g_NPCSystem.favorHUD.scale = value
            end
        elseif id == "showMapMarkers" then
            if g_NPCSystem and g_NPCSystem.entityManager and
               g_NPCSystem.entityManager.toggleAllMapHotspots then
                g_NPCSystem.entityManager:toggleAllMapHotspots(value)
            end
        end
        return
    end

    if not self:isAdmin() then
        if g_currentMission and g_currentMission.hud and
           g_currentMission.hud.showBlinkingWarning then
            g_currentMission.hud:showBlinkingWarning(
                tr("npc_panel_admin_only", "Admin only — cannot change this setting"), 4000)
        end
        return
    end

    if g_server ~= nil then
        self.settings[id] = value
        if NPCSettingsSyncEvent and g_server then
            g_server:broadcastEvent(NPCSettingsSyncEvent.newSingle(id, value), false)
        end
    else
        if NPCSettingsSyncEvent then
            NPCSettingsSyncEvent.sendSingleToServer(id, value)
        end
    end
end

-- ── Drawing helpers ───────────────────────────────────────
function NPCSettingsPanel:drawRect(x, y, w, h, col, alpha)
    if not self.fillOverlay then return end
    local a = alpha or col[4] or 1.0
    setOverlayColor(self.fillOverlay, col[1], col[2], col[3], a)
    renderOverlay(self.fillOverlay, x, y, w, h)
end

function NPCSettingsPanel:drawText(x, y, size, text, col, align, bold)
    setTextColor(col[1], col[2], col[3], col[4] or 1.0)
    setTextBold(bold == true)
    setTextAlignment(align or RenderText.ALIGN_LEFT)
    renderText(x, y, size, tostring(text))
end

function NPCSettingsPanel:registerClick(id, x, y, w, h, data)
    table.insert(self._clickRects, {id = id, x = x, y = y, w = w, h = h, data = data})
end

function NPCSettingsPanel:hitTest(rx, ry, rw, rh, mx, my)
    return mx >= rx and mx <= rx + rw and my >= ry and my <= ry + rh
end

-- ── Main draw entry ───────────────────────────────────────
function NPCSettingsPanel:draw()
    if not self.isVisible then return end
    if not self.initialized then return end
    if not g_currentMission then return end

    self._clickRects = {}

    -- Dark screen fade
    self:drawRect(0, 0, 1, 1, C.shadow, 0.38)

    -- Panel shadow
    self:drawRect(PX + 0.004, PY - 0.004, PW, PH, C.shadow, 0.55)

    -- Panel background
    self:drawRect(PX, PY, PW, PH, C.bg)

    -- Border
    local bw = 0.0015
    local bc = self.activeCatIdx and CATEGORIES[self.activeCatIdx].accent or C.border
    self:drawRect(PX,           PY,           PW, bw, bc)
    self:drawRect(PX,           PY + PH - bw, PW, bw, bc)
    self:drawRect(PX,           PY,           bw, PH, bc)
    self:drawRect(PX + PW - bw, PY,           bw, PH, bc)

    if self.page == PAGE_LANDING then
        self:drawLandingPage()
    elseif self.page == PAGE_CATEGORY then
        self:drawCategoryPage()
    elseif self.page == PAGE_ADMIN then
        self:drawAdminPage()
    end

    -- Title bar and info bar drawn on top so they clip scrolled content
    self:drawTitleBar()
    self:drawInfoBar()
end

-- ── Title bar ─────────────────────────────────────────────
function NPCSettingsPanel:drawTitleBar()
    local ty = PY + PH - TB_H
    self:drawRect(PX, ty, PW, TB_H, C.title_bg)

    local acc = (self.page == PAGE_ADMIN) and C.admin_acc
             or (self.activeCatIdx and CATEGORIES[self.activeCatIdx].accent)
             or C.border
    self:drawRect(PX, ty, 0.004, TB_H, acc)

    local title = "NPC FAVOR SETTINGS"
    if self.page == PAGE_ADMIN then
        title = title .. "  /  ADMIN"
    elseif self.activeCatIdx then
        local cat = CATEGORIES[self.activeCatIdx]
        title = title .. "  /  " .. string.upper(tr(cat.labelKey, cat.id))
    end
    self:drawText(PX + 0.018, ty + TB_H * 0.32, TS_TITLE, title, C.white, RenderText.ALIGN_LEFT, true)

    -- Version
    local ver = (g_NPCFavorMod and g_NPCFavorMod.version) or "?"
    self:drawText(PX + PW - 0.020, ty + TB_H * 0.32, TS_TINY, "v" .. ver, C.hint, RenderText.ALIGN_RIGHT, false)

    -- [X] close button
    local cbW = 0.038
    local cbH = TB_H * 0.60
    local cbX = PX + PW - cbW - 0.010
    local cbY = ty + (TB_H - cbH) / 2
    local chov = self:hitTest(cbX, cbY, cbW, cbH, self.mouseX, self.mouseY)
    self:drawRect(cbX, cbY, cbW, cbH, chov and C.close_hover or C.off_bg)
    self:drawText(cbX + cbW * 0.5, cbY + cbH * 0.18, TS_SMALL, "X", C.white, RenderText.ALIGN_CENTER, true)
    self:registerClick("close", cbX, cbY, cbW, cbH)
end

-- ── Info bar ──────────────────────────────────────────────
function NPCSettingsPanel:drawInfoBar()
    local iy = PY
    self:drawRect(PX, iy, PW, IB_H, C.info_bg)
    self:drawRect(PX, iy + IB_H - 0.001, PW, 0.001, C.divider)

    local isAdmin = self:isAdmin()
    local isMP    = g_currentMission and g_currentMission.missionDynamicInfo and
                    g_currentMission.missionDynamicInfo.isMultiplayer

    local adminText  = isAdmin and tr("npc_panel_admin_yes", "Admin: Yes")
                                or tr("npc_panel_admin_no",  "Admin: No")
    local adminColor = isAdmin and C.info_admin or C.info_no_adm
    local modeText   = isMP   and tr("npc_panel_multiplayer",   "Multiplayer")
                               or tr("npc_panel_singleplayer",  "Singleplayer")

    local textY = iy + IB_H * 0.25
    self:drawText(PX + PAD,         textY, TS_SMALL, adminText,          adminColor, RenderText.ALIGN_LEFT, true)
    self:drawText(PX + PAD + 0.095, textY, TS_SMALL, "·  " .. modeText,  C.info_mode, RenderText.ALIGN_LEFT, false)

    if self.page == PAGE_CATEGORY or self.page == PAGE_ADMIN then
        -- Back button
        local bbW = 0.085
        local bbH = IB_H * 0.62
        local bbX = PX + PW - bbW - 0.014
        local bbY = iy + (IB_H - bbH) / 2
        local bhov = self:hitTest(bbX, bbY, bbW, bbH, self.mouseX, self.mouseY)
        self:drawRect(bbX, bbY, bbW, bbH, bhov and C.back_hover or C.off_bg)
        self:drawRect(bbX, bbY, 0.002, bbH, C.green_dim)
        self:drawText(bbX + bbW * 0.5, bbY + bbH * 0.18, TS_SMALL,
            tr("npc_panel_btn_back", "Back"), C.white, RenderText.ALIGN_CENTER, false)
        self:registerClick("back", bbX, bbY, bbW, bbH)
    else
        self:drawText(PX + PW - PAD, textY, TS_SMALL,
            tr("npc_panel_btn_close_hint", "F5 to close"), C.hint, RenderText.ALIGN_RIGHT, false)
    end
end

-- ── Landing page ──────────────────────────────────────────
function NPCSettingsPanel:drawLandingPage()
    local headerY = CY_BOT + CH - 0.040
    self:drawText(PX + PW * 0.5, headerY, TS_SMALL,
        tr("npc_panel_select_category", "Select a category to configure"),
        C.hint, RenderText.ALIGN_CENTER, false)

    for i, cat in ipairs(CATEGORIES) do
        local cardX = CX + (i - 1) * (CARD_W + CARD_GAP)
        self:drawCategoryCard(cardX, CARD_Y, CARD_W, CARD_H, cat, i)
    end

    -- ADMIN button — bottom-right
    local btnW = 0.090
    local btnH = 0.030
    local btnX = CX + CW - btnW
    local btnY = CY_BOT + 0.005
    local bhov = self:hitTest(btnX, btnY, btnW, btnH, self.mouseX, self.mouseY)
    self:drawRect(btnX, btnY, btnW, btnH,
        bhov and {0.55, 0.08, 0.08, 0.95} or {0.22, 0.05, 0.05, 0.88})
    self:drawRect(btnX, btnY, 0.003, btnH, C.admin_acc)
    self:drawText(btnX + btnW * 0.5 + 0.001, btnY + btnH * 0.22, TS_SMALL, "ADMIN",
        bhov and {1.0, 0.55, 0.55, 1.0} or {0.85, 0.35, 0.35, 1.0},
        RenderText.ALIGN_CENTER, true)
    self:registerClick("open_admin", btnX, btnY, btnW, btnH)
end

function NPCSettingsPanel:drawCategoryCard(x, y, w, h, cat, idx)
    local hovered = self:hitTest(x, y, w, h, self.mouseX, self.mouseY)

    self:drawRect(x, y, w, h, C.bg)
    if hovered then self:drawRect(x, y, w, h, C.card_hover) end

    -- Border
    local bw = 0.0012
    self:drawRect(x,         y,         w, bw, cat.accent, 0.30)
    self:drawRect(x,         y + h - bw, w, bw, cat.accent, 0.30)
    self:drawRect(x,         y,         bw, h,  cat.accent, 0.30)
    self:drawRect(x + w - bw, y,         bw, h,  cat.accent, 0.30)

    -- Top color bar
    self:drawRect(x, y + h - 0.018, w, 0.018, cat.accent, hovered and 0.85 or 0.65)

    -- Title
    local titleY = y + h - 0.018 - 0.042
    self:drawText(x + w * 0.5, titleY, TS_BODY,
        string.upper(tr(cat.labelKey, cat.id)), C.white, RenderText.ALIGN_CENTER, true)

    -- Divider
    self:drawRect(x + 0.010, titleY - 0.006, w - 0.020, 0.001, C.divider)

    -- Count
    local count = 0
    for _, sec in ipairs(cat.sections) do count = count + #sec.items end

    -- Description
    local descY = titleY - 0.036
    local descStr = tr(cat.descKey, "")
    for line in (descStr .. "\n"):gmatch("([^\n]*)\n") do
        self:drawText(x + w * 0.5, descY, TS_SMALL, line, C.dim, RenderText.ALIGN_CENTER, false)
        descY = descY - 0.020
    end

    -- Count badge
    self:drawText(x + w * 0.5, y + 0.038, TS_SMALL,
        count .. " settings", cat.accent, RenderText.ALIGN_CENTER, false)

    -- Configure button
    local bW = w - 0.024
    local bH = 0.028
    local bX = x + 0.012
    local bY = y + 0.006
    self:drawRect(bX, bY, bW, bH, hovered and cat.accent or C.off_bg, hovered and 0.20 or 1.0)
    self:drawText(bX + bW * 0.5, bY + bH * 0.18, TS_SMALL,
        hovered and tr("npc_panel_btn_open", "Open") or tr("npc_panel_btn_configure", "Configure"),
        hovered and cat.accent or C.hint, RenderText.ALIGN_CENTER, false)

    self:registerClick("cat_" .. idx, x, y, w, h)
end

-- ── Category page ─────────────────────────────────────────
function NPCSettingsPanel:drawCategoryPage()
    if not self.activeCatIdx then return end
    local cat = CATEGORIES[self.activeCatIdx]
    if not cat then return end

    local curY   = CY_TOP
    local isAdmin = self:isAdmin()
    local rowIdx  = 0

    for _, sec in ipairs(cat.sections) do
        curY = curY - SEC_H
        if curY < CY_BOT then break end

        self:drawRect(CX, curY, CW, SEC_H, C.title_bg, 0.60)
        self:drawRect(CX, curY, 0.003, SEC_H, cat.accent)
        self:drawText(CX + 0.012, curY + SEC_H * 0.25, TS_SMALL,
            string.upper(tr(sec.headerKey, "")), cat.accent, RenderText.ALIGN_LEFT, true)

        for _, sid in ipairs(sec.items) do
            curY = curY - ROW_H
            if curY < CY_BOT then break end
            rowIdx = rowIdx + 1
            self:drawSettingRow(CX, curY, CW, sid, rowIdx, isAdmin, cat.accent)
        end

        curY = curY - 0.005
    end

    self:drawRect(CX, CY_TOP, CW, 0.001, C.divider)
end

-- ── Admin page ────────────────────────────────────────────
function NPCSettingsPanel:drawAdminPage()
    local curY   = CY_TOP
    local isAdmin = self:isAdmin()
    local rowIdx  = 0

    for _, sec in ipairs(ADMIN_SECTIONS) do
        curY = curY - SEC_H
        if curY < CY_BOT then break end

        self:drawRect(CX, curY, CW, SEC_H, C.title_bg, 0.60)
        self:drawRect(CX, curY, 0.003, SEC_H, C.admin_acc)
        self:drawText(CX + 0.012, curY + SEC_H * 0.25, TS_SMALL,
            string.upper(tr(sec.headerKey, "")),
            {C.admin_acc[1], C.admin_acc[2], C.admin_acc[3], 1.0},
            RenderText.ALIGN_LEFT, true)

        for _, item in ipairs(sec.items) do
            local isAction = (item.stype == "action" or item.stype == "danger")
            local rh = isAction and ADMIN_ACT_H or ADMIN_ROW_H
            curY = curY - rh
            if curY < CY_BOT then break end
            rowIdx = rowIdx + 1

            if rowIdx % 2 == 0 then self:drawRect(CX, curY, CW, rh, C.row_alt) end

            if item.stype == "setting" then
                self:drawSettingRow(CX, curY, CW, item.id, rowIdx, isAdmin, C.admin_acc, rh)
            else
                local isDanger = (item.stype == "danger")
                local btnW = 0.130
                local btnH = rh * 0.72
                local btnX = CX + CW - btnW - 0.012
                local btnY = curY + (rh - btnH) * 0.5
                local hov  = self:hitTest(btnX, btnY, btnW, btnH, self.mouseX, self.mouseY)

                local aLabel = tr("npc_" .. item.id .. "_label", item.id)
                local aDesc  = tr("npc_" .. item.id .. "_desc",  "")
                self:drawText(CX + 0.008, curY + rh * 0.55, TS_BODY, aLabel, C.white, RenderText.ALIGN_LEFT, true)
                self:drawText(CX + 0.008, curY + rh * 0.15, TS_TINY, aDesc,  C.dim,   RenderText.ALIGN_LEFT, false)

                local bgCol = isDanger
                    and (hov and {0.65, 0.10, 0.10, 0.95} or {0.30, 0.06, 0.06, 0.85})
                    or  (hov and {0.10, 0.35, 0.15, 0.95} or {0.08, 0.18, 0.10, 0.85})
                local acCol = isDanger and C.admin_acc or C.accent_play
                self:drawRect(btnX, btnY, btnW, btnH, bgCol)
                self:drawRect(btnX, btnY, 0.002, btnH, acCol)
                self:drawText(btnX + btnW * 0.5, btnY + btnH * 0.20, TS_TINY,
                    (isDanger and "!! " or ">  ") .. aLabel,
                    hov and C.white or {0.75, 0.75, 0.75, 1},
                    RenderText.ALIGN_CENTER, isDanger)
                self:registerClick("admin_action_" .. item.id, btnX, btnY, btnW, btnH)
            end

            self:drawRect(CX, curY, CW, 0.0005, C.divider, 0.35)
        end

        curY = curY - 0.005
    end

    self:drawRect(CX, CY_TOP, CW, 0.001, C.divider)
end

-- ── Setting row ────────────────────────────────────────────
function NPCSettingsPanel:drawSettingRow(x, y, w, sid, rowIdx, isAdmin, accent, rh)
    rh = rh or ROW_H
    local lbl = SETTING_LABELS[sid]
    if not lbl then return end

    if rowIdx % 2 == 0 then
        self:drawRect(x, y, w, rh, C.row_alt)
    end
    if self:hitTest(x, y, w, rh, self.mouseX, self.mouseY) then
        self:drawRect(x, y, w, rh, C.row_hover)
    end

    local locked = not LOCAL_ONLY[sid] and not isAdmin
    local lc = locked and C.lock_text or C.white
    local dc = locked and {C.lock_text[1] * 0.7, C.lock_text[2] * 0.7, C.lock_text[3] * 0.7, 1} or C.dim

    if locked then
        self:drawRect(x, y, 0.003, rh, {0.88, 0.60, 0.18, 0.45})
    end

    local lx = x + (locked and 0.010 or 0.008)
    local labelText = tr(lbl.key, lbl.fb)
    local descKey   = SETTING_DESCS[sid]
    local descText  = (descKey and tr(descKey, "")) or ""

    self:drawText(lx, y + rh * 0.54, TS_BODY, labelText, lc, RenderText.ALIGN_LEFT, not locked)
    self:drawText(lx, y + rh * 0.15, TS_TINY, descText,  dc, RenderText.ALIGN_LEFT, false)

    local ctrlX = x + w - 0.012
    local ctrlY = y + (rh - TOGGLE_H) / 2

    if MULTI_OPTS[sid] then
        self:drawMultiControl(ctrlX, ctrlY, sid, locked)
    else
        self:drawToggleControl(ctrlX, ctrlY, sid, locked)
    end

    self:drawRect(x, y, w, 0.0005, C.divider, 0.35)
end

-- ── Toggle control [OFF] [ON] ─────────────────────────────
function NPCSettingsPanel:drawToggleControl(rightX, y, sid, locked)
    local val = self:getValue(sid)
    local isOn = val == true

    local offX = rightX - TOGGLE_W * 2 - TOGGLE_GAP
    local onX  = rightX - TOGGLE_W

    local offHov = not locked and self:hitTest(offX, y, TOGGLE_W, TOGGLE_H, self.mouseX, self.mouseY)
    self:drawRect(offX, y, TOGGLE_W, TOGGLE_H, (not isOn) and C.dim or C.off_bg, (not isOn) and 0.90 or 0.60)
    self:drawText(offX + TOGGLE_W * 0.5, y + TOGGLE_H * 0.20, TS_TINY,
        "OFF", (not isOn) and C.white or C.off_text, RenderText.ALIGN_CENTER, not isOn)

    local onHov = not locked and self:hitTest(onX, y, TOGGLE_W, TOGGLE_H, self.mouseX, self.mouseY)
    self:drawRect(onX, y, TOGGLE_W, TOGGLE_H, isOn and C.on_bg or C.off_bg, isOn and 1.0 or 0.60)
    self:drawText(onX + TOGGLE_W * 0.5, y + TOGGLE_H * 0.20, TS_TINY,
        "ON", isOn and C.on_text or C.off_text, RenderText.ALIGN_CENTER, isOn)

    if not locked then
        self:registerClick("toggle_off_" .. sid, offX, y, TOGGLE_W, TOGGLE_H, {id = sid, value = false})
        self:registerClick("toggle_on_"  .. sid, onX,  y, TOGGLE_W, TOGGLE_H, {id = sid, value = true})
    end
end

-- ── Multi-select control [< Option >] ────────────────────
function NPCSettingsPanel:drawMultiControl(rightX, y, sid, locked)
    local opt = MULTI_OPTS[sid]
    if not opt then return end

    local curVal = self:getValue(sid)
    local curIdx = 1
    for i, v in ipairs(opt.values) do
        if v == curVal then curIdx = i; break end
    end
    local rawLabel = opt.labels[curIdx] or "?"
    local label    = (opt.i18n and tr(rawLabel, rawLabel)) or rawLabel

    local arrowW = 0.022
    local labelW = MULTI_W - arrowW * 2
    local totalX = rightX - MULTI_W
    local leftX  = totalX
    local midX   = totalX + arrowW
    local rightBX = totalX + arrowW + labelW

    local lHov = not locked and self:hitTest(leftX, y, arrowW, TOGGLE_H, self.mouseX, self.mouseY)
    self:drawRect(leftX, y, arrowW, TOGGLE_H, lHov and C.back_hover or C.off_bg)
    self:drawText(leftX + arrowW * 0.5, y + TOGGLE_H * 0.18, TS_TINY,
        "<", lHov and C.accent_npc or C.dim, RenderText.ALIGN_CENTER, true)

    self:drawRect(midX, y, labelW, TOGGLE_H, {0.10, 0.11, 0.15, 0.90})
    self:drawText(midX + labelW * 0.5, y + TOGGLE_H * 0.18, TS_TINY,
        label, C.white, RenderText.ALIGN_CENTER, false)

    local rHov = not locked and self:hitTest(rightBX, y, arrowW, TOGGLE_H, self.mouseX, self.mouseY)
    self:drawRect(rightBX, y, arrowW, TOGGLE_H, rHov and C.back_hover or C.off_bg)
    self:drawText(rightBX + arrowW * 0.5, y + TOGGLE_H * 0.18, TS_TINY,
        ">", rHov and C.accent_npc or C.dim, RenderText.ALIGN_CENTER, true)

    if not locked then
        self:registerClick("multi_prev_" .. sid, leftX,   y, arrowW, TOGGLE_H, {id = sid, dir = -1})
        self:registerClick("multi_next_" .. sid, rightBX, y, arrowW, TOGGLE_H, {id = sid, dir =  1})
    end
end

-- ── Mouse event ───────────────────────────────────────────
function NPCSettingsPanel:onMouseEvent(posX, posY, isDown, isUp, button, eventUsed)
    if not self.isVisible then return false end

    self.mouseX = posX
    self.mouseY = posY

    if not isDown then return true end
    if button ~= Input.MOUSE_BUTTON_LEFT then return true end

    for _, r in ipairs(self._clickRects) do
        if self:hitTest(r.x, r.y, r.w, r.h, posX, posY) then
            self:handleClick(r.id, r.data)
            return true
        end
    end

    -- Click outside panel → close
    if not self:hitTest(PX, PY, PW, PH, posX, posY) then
        self:close()
    end

    return true
end

function NPCSettingsPanel:handleClick(id, data)
    if id == "close" then
        self:close()

    elseif id == "back" then
        self.page         = PAGE_LANDING
        self.activeCatIdx = nil

    elseif id:sub(1, 4) == "cat_" then
        local idx = tonumber(id:sub(5))
        if idx and CATEGORIES[idx] then
            self.activeCatIdx = idx
            self.page = PAGE_CATEGORY
        end

    elseif id == "open_admin" then
        self.page = PAGE_ADMIN

    elseif id:sub(1, 11) == "toggle_off_" then
        if data then self:requestChange(data.id, false) end

    elseif id:sub(1, 10) == "toggle_on_" then
        if data then self:requestChange(data.id, true) end

    elseif id:sub(1, 10) == "multi_prev" or id:sub(1, 10) == "multi_next" then
        if data then
            local opt = MULTI_OPTS[data.id]
            if opt then
                local curVal = self:getValue(data.id)
                local curIdx = 1
                for i, v in ipairs(opt.values) do
                    if v == curVal then curIdx = i; break end
                end
                local nxtIdx = curIdx + data.dir
                if nxtIdx < 1 then nxtIdx = #opt.values end
                if nxtIdx > #opt.values then nxtIdx = 1 end
                self:requestChange(data.id, opt.values[nxtIdx])
            end
        end

    elseif id:sub(1, 13) == "admin_action_" then
        local actionId = id:sub(14)
        if actionId == "admin_save" then
            local ok = pcall(function()
                if g_NPCSystem and g_NPCSystem.isInitialized then
                    local mi = g_currentMission and g_currentMission.missionInfo
                    if mi then
                        g_NPCSystem:saveToXMLFile(mi)
                        if g_NPCSystem.settings then
                            g_NPCSystem.settings:saveToXMLFile(mi)
                        end
                    end
                end
            end)
            if g_currentMission and g_currentMission.hud and
               g_currentMission.hud.showBlinkingWarning then
                g_currentMission.hud:showBlinkingWarning(
                    ok and tr("npc_admin_save_ok", "NPC data saved.")
                       or tr("npc_admin_save_fail", "Save failed — check log."), 4000)
            end

        elseif actionId == "admin_reset" then
            if self.settings then
                self.settings:resetToDefaults()
            end
            if g_currentMission and g_currentMission.hud and
               g_currentMission.hud.showBlinkingWarning then
                g_currentMission.hud:showBlinkingWarning(
                    tr("npc_admin_reset_ok", "Settings reset to defaults."), 4000)
            end
        end
    end
end
