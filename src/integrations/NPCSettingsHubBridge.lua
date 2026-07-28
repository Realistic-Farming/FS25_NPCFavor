-- =========================================================
-- FS25 NPC Favor - SettingsHub bridge
-- =========================================================
-- Author: TisonK
-- =========================================================
-- COPYRIGHT NOTICE:
-- All rights reserved. Unauthorized redistribution, copying,
-- or claiming this code as your own is strictly prohibited.
-- Original author: TisonK
-- =========================================================
-- Optional bridge to FS25_SettingsHub. NPCFavor ships standalone, so register() just
-- no-ops when SettingsHub is absent. Purpose: mirror NPCFavor's settings into the
-- ecosystem's unified settings panel (and the FarmTablet System Settings app).
--
-- delegate-when-present, selfPersisted mirror: NPCSettings (npc_favor_settings.xml) stays
-- the single source of truth and loads its own values before this registration runs, so
-- the hub must mirror-for-display only (selfPersisted = true): it never restores its own
-- stale copy over the real value on load. The mod's own ESC settings panel keeps working
-- exactly as before; this bridge only surfaces the same settings in the hub and applies
-- edits made through it.
--
-- The exposed set, the admin/player split, and the labels all mirror the mod's own
-- settings panel (NPCSettingsPanel SETTING_LABELS + LOCAL_ONLY), so nothing new is
-- invented here. adminOnly = true settings are server-shared; adminOnly = false are
-- per-player, exactly the LOCAL_ONLY split the panel already enforces.
--
-- The cross-mod handle is g_currentMission.settingsHub (the bare g_settingsHub global is
-- only visible inside SettingsHub's own mod environment). Registration is order
-- independent, at Mission00.loadMission00Finished.
-- =========================================================

NPCSettingsHubBridge = {}

-- Exactly the settings the mod's own panel exposes (NPCSettingsPanel.SETTING_LABELS),
-- with the same admin/player split (admin = not in NPCSettingsPanel.LOCAL_ONLY) and the
-- same label l10n keys (English fallback if a language lacks the key). type/min/max/values
-- mirror the panel's editors.
local DEFS = {
    -- Admin (server-authoritative gameplay / behaviour)
    { id = "enabled",                  type = "bool",  admin = true,  labelKey = "npc_enabled_short",            fb = "Enable NPC System" },
    { id = "maxNPCs",                  type = "int",   admin = true,  min = 1,  max = 16, step = 1, labelKey = "npc_max_count_short",         fb = "Max NPC Count" },
    { id = "favorFrequency",           type = "int",   admin = true,  min = 1,  max = 5,  step = 1, labelKey = "npc_favor_freq_short",        fb = "Favor Frequency" },
    { id = "npcWorkStart",             type = "int",   admin = true,  min = 5,  max = 12, step = 1, labelKey = "npc_work_start_short",        fb = "Work Day Start" },
    { id = "npcWorkEnd",               type = "int",   admin = true,  min = 14, max = 22, step = 1, labelKey = "npc_work_end_short",          fb = "Work Day End" },
    { id = "npcActivityLevel",         type = "enum",  admin = true,  values = {"low", "normal", "high"},         labelKey = "npc_activity_level_short",    fb = "Activity Level" },
    { id = "npcSocialize",             type = "bool",  admin = true,  labelKey = "npc_socialize_short",           fb = "Enable Socializing" },
    { id = "npcHelpPlayer",            type = "bool",  admin = true,  labelKey = "npc_help_player_short",         fb = "Offer Help to Player" },
    { id = "enableFavors",             type = "bool",  admin = true,  labelKey = "npc_enable_favors_short",       fb = "Enable Favors" },
    { id = "allowMultipleFavors",      type = "bool",  admin = true,  labelKey = "npc_allow_multi_favors_short",  fb = "Multiple Favors" },
    { id = "maxActiveFavors",          type = "int",   admin = true,  min = 1,  max = 20, step = 1, labelKey = "npc_max_active_favors_short", fb = "Max Active Favors" },
    { id = "favorTimeLimit",           type = "bool",  admin = true,  labelKey = "npc_favor_time_limit_short",    fb = "Favor Time Limit" },
    { id = "favorDifficulty",          type = "enum",  admin = true,  values = {"easy", "normal", "hard"},        labelKey = "npc_favor_difficulty_short", fb = "Favor Difficulty" },
    { id = "enableGifts",              type = "bool",  admin = true,  labelKey = "npc_enable_gifts_short",        fb = "Enable Gifts" },
    { id = "enableRelationshipSystem", type = "bool",  admin = true,  labelKey = "npc_rel_system_short",          fb = "Relationship System" },
    { id = "relationshipDecay",        type = "bool",  admin = true,  labelKey = "npc_rel_decay_short",           fb = "Relationship Decay" },
    -- Per-player (NPCSettingsPanel.LOCAL_ONLY)
    { id = "showNames",                type = "bool",  admin = false, labelKey = "npc_show_names_short",          fb = "Show NPC Names" },
    { id = "showNotifications",        type = "bool",  admin = false, labelKey = "npc_show_notifications_short",  fb = "Show Notifications" },
    { id = "showFavorList",            type = "bool",  admin = false, labelKey = "npc_show_favor_list_short",     fb = "Show Favor List" },
    { id = "showRelationshipBars",     type = "bool",  admin = false, labelKey = "npc_show_rel_bars_short",       fb = "Relationship Bars" },
    { id = "showMapMarkers",           type = "bool",  admin = false, labelKey = "npc_show_map_markers_short",    fb = "Show Map Markers" },
    { id = "favorHudScale",            type = "float", admin = false, min = 0.5, max = 2.0, step = 0.25, labelKey = "npc_hud_scale_short",   fb = "Favor HUD Scale" },
    { id = "favorPanelScale",          type = "float", admin = false, min = 0.8, max = 2.0, step = 0.1,  labelKey = "npc_panel_scale_short",  fb = "Settings Panel Scale" },
    { id = "favorHudLocked",           type = "bool",  admin = false, labelKey = "npc_hud_locked_short",          fb = "Lock Favor HUD" },
    { id = "showPaths",                type = "bool",  admin = false, labelKey = "npc_show_paths_short",          fb = "Show NPC Paths" },
    { id = "showAIDecisions",          type = "bool",  admin = false, labelKey = "npc_show_ai_short",             fb = "AI Decisions" },
    { id = "debugMode",                type = "bool",  admin = false, labelKey = "npc_debug_short",               fb = "Debug Mode" },
}

-- FarmTablet's System Settings app renders the label string as-is (no l10n lookup on its
-- end), so resolve each setting's human-readable name here from its short key, falling
-- back to the English string if the current language lacks the key.
local function resolveLabel(def)
    if g_i18n ~= nil and g_i18n.hasText ~= nil and def.labelKey ~= nil and g_i18n:hasText(def.labelKey) then
        return g_i18n:getText(def.labelKey)
    end
    return def.fb or def.id
end

-- Apply an edit made through the hub back onto NPCSettings (the source of truth). Set +
-- validate; persistence rides the mod's normal save hook, exactly like the mod's own
-- panel (NPCSettings persists on FSCareerMissionInfo.saveToXMLFile, not on every change).
local function applyChange(key, value, playerId)
    local sys = g_NPCSystem
    if sys == nil or sys.settings == nil then return end

    sys.settings[key] = value
    if sys.settings.validateSettings then
        pcall(function() sys.settings:validateSettings() end)
    end

    -- Reflect runtime-visible changes (HUD scale/lock/visibility) immediately.
    if sys.favorHUD and sys.favorHUD.loadFromSettings then
        pcall(function() sys.favorHUD:loadFromSettings(sys.settings) end)
    end
end

function NPCSettingsHubBridge.register()
    local hub = (g_currentMission ~= nil and g_currentMission.settingsHub) or g_settingsHub
    if hub == nil then
        print("[NPC Favor] SettingsHub not detected; skipping unified-settings registration")
        return
    end

    local sys = g_NPCSystem
    if sys == nil or sys.settings == nil then return end

    local defs = {}
    for _, d in ipairs(DEFS) do
        defs[#defs + 1] = {
            id        = d.id,
            type      = d.type,
            default   = sys.settings[d.id],
            adminOnly = d.admin,
            min       = d.min,
            max       = d.max,
            step      = d.step,
            values    = d.values,
            label     = resolveLabel(d),
        }
    end

    local ok, err = pcall(function()
        hub:registerModule("FS25_NPCFavor", {
            adminSettings = defs,
            onChange      = applyChange,
            -- We own npc_favor_settings.xml and load it before this runs, so the hub must
            -- mirror-for-display only and never replay a stale copy back over our values.
            selfPersisted = true,
        })
    end)

    if ok then
        print(string.format("[NPC Favor] Registered with SettingsHub (%d setting(s))", #defs))
    else
        print(string.format("[NPC Favor] SettingsHub registration failed: %s", tostring(err)))
    end
end
