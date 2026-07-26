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

NPCMasterHUDBridge = {}

NPCMasterHUDBridge.HUD_ID = "NPCFavor_HUD"
NPCMasterHUDBridge.active = false   -- MasterHUD present and we registered

-- The NPC HUD draw body. Resolves the system from the canonical global so it can be
-- driven either by MasterHUD or by NPCFavor's own FSBaseMission.draw hook. NPCSystem:draw
-- already guards on enabled + initialized internally.
function NPCMasterHUDBridge.drawStack()
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
    else
        print(string.format("[NPC Favor] MasterHUD registration failed: %s (using own draw hook)", tostring(err)))
    end
end
