-- =========================================================
-- FS25 NPC Favor - MasterHUD bridge
-- =========================================================
-- Author: TisonK
-- =========================================================
-- COPYRIGHT NOTICE:
-- All rights reserved. Unauthorized redistribution, copying,
-- or claiming this code as your own is strictly prohibited.
-- Original author: TisonK
-- =========================================================
-- Optional bridge to FS25_MasterHUD. NPCFavor ships standalone, so this is strictly
-- delegate-when-present:
--   * MasterHUD installed -> NPCFavor registers its whole HUD draw entry (interaction
--     hints, name tags, the movable favor HUD, the settings panel overlay) as a
--     self-draw. MasterHUD then owns the single draw loop, the menu/dialog suspend, and
--     cross-mod ordering, so the NPC HUD stacks cleanly with the rest of the ecosystem.
--   * MasterHUD absent -> NPCFavor's own FSBaseMission.draw hook runs the exact same
--     NPCSystem:draw() body, exactly as before.
--
-- subscribe() is MasterHUD's path for self-drawn content: the element draws its own
-- positioned content (the favor HUD keeps its own drag position), MasterHUD only owns
-- ordering + suspend. NPCSystem:draw() is the single draw body shared with the fallback
-- hook, so the two paths can never diverge.
--
-- The in-game-menu g_gui dialogs (NPCDialog, favor management, admin list/edit) stay
-- g_gui-managed. They are not HUD overlays and are not registered here.
--
-- The cross-mod handle is g_currentMission.masterHUD (the bare g_masterHUD global is
-- only visible inside MasterHUD's own mod environment). Registration is order
-- independent and happens at Mission00.loadMission00Finished.
-- =========================================================

NPCMasterHUDBridge = NPCMasterHUDBridge or {}

NPCMasterHUDBridge.HUD_ID = "NPCFavor_HUD"
NPCMasterHUDBridge.active = NPCMasterHUDBridge.active or false   -- survives reload; register() re-derives it

-- The NPC HUD draw body. Resolves the system from the canonical global so it can be
-- driven either by MasterHUD or by NPCFavor's own FSBaseMission.draw hook. NPCSystem:draw
-- already guards on enabled + initialized internally.
function NPCMasterHUDBridge.drawStack()
    -- Suite hide: MasterHUD # key. No-op when MasterHUD absent.
    local mh = (g_currentMission ~= nil and g_currentMission.masterHUD) or g_masterHUD
    if mh ~= nil and mh.areHudsHidden ~= nil and mh:areHudsHidden() then return end
    if g_NPCSystem ~= nil and g_NPCSystem.draw ~= nil then
        g_NPCSystem:draw()
    end
end

-- Register with MasterHUD if present. Called at loadMission00Finished, after the HUD
-- has published its g_currentMission handle in Mission00.load.
function NPCMasterHUDBridge.register()
    NPCMasterHUDBridge.active = false

    local hud = (g_currentMission ~= nil and g_currentMission.masterHUD) or g_masterHUD
    if hud == nil then
        print("[NPC Favor] MasterHUD not detected; NPC HUD uses its own draw hook")
        return
    end

    local ok, err = pcall(function()
        hud:subscribe(NPCMasterHUDBridge.HUD_ID, {
            draw = NPCMasterHUDBridge.drawStack,
        })
    end)

    if ok then
        NPCMasterHUDBridge.active = true
        print("[NPC Favor] Registered NPC HUD with MasterHUD (single draw loop + menu-suspend)")
        if hud.registerEditListener ~= nil then
            hud:registerEditListener(NPCMasterHUDBridge.HUD_ID, {
                enter = function()
                    local sys = g_NPCSystem
                    if sys ~= nil and sys.favorHUD ~= nil and sys.favorHUD.enterEditMode ~= nil then
                        if sys.settings and sys.settings.favorHudLocked then return end
                        sys.favorHUD:enterEditMode()
                    end
                end,
                exit = function()
                    local sys = g_NPCSystem
                    if sys ~= nil and sys.favorHUD ~= nil and sys.favorHUD.editMode
                        and sys.favorHUD.exitEditMode ~= nil then
                        -- suite-owned exit: the HUD ignores every other exit while suite edit is ON
                        sys.favorHUD._suiteExiting = true
                        sys.favorHUD:exitEditMode()
                        sys.favorHUD._suiteExiting = false
                    end
                end,
            })
        end
    else
        print(string.format("[NPC Favor] MasterHUD registration failed: %s (using own draw hook)", tostring(err)))
    end
end

-- =========================================================
-- Hot-reload delivery (2026-08-22): register() only runs at mission load, so a
-- push of this file alone would define the new listener without registering it.
-- NOT gated on .active (the gated shape skips silently when the boot-time bridge
-- predates the flag). register() is idempotent - subscribe and
-- registerEditListener both replace by id - so every live source pass may fire it;
-- on a cold pass the mission handle does not exist yet and this is a no-op.
local __hud = (g_currentMission ~= nil and g_currentMission.masterHUD) or g_masterHUD
if __hud ~= nil then
    pcall(function() NPCMasterHUDBridge.register() end)
end
