-- =========================================================
-- FS25 NPC Favor Mod - Settings Integration
-- =========================================================
-- ESC menu injection removed in v1.2.5.0.
-- Settings are now managed by NPCSettingsPanel (F5).
-- This file is kept as a subsystem stub — NPCSystem holds
-- a reference to the instance and calls lifecycle methods.
-- =========================================================

NPCSettingsIntegration = {}
NPCSettingsIntegration_mt = Class(NPCSettingsIntegration)

function NPCSettingsIntegration.new(npcSystem)
    local self = setmetatable({}, NPCSettingsIntegration_mt)
    self.npcSystem = npcSystem
    return self
end

function NPCSettingsIntegration:initialize() end
function NPCSettingsIntegration:update(dt)     end
function NPCSettingsIntegration:delete()        end
