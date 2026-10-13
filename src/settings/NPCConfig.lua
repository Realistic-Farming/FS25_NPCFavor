-- =========================================================
-- TODO / FUTURE VISION
-- =========================================================
-- CONFIGURATION DATA:
-- [x] NPC name pool with localization key support
-- [x] Personality type definitions (12 types)
-- [x] Vehicle type and color configuration
-- [x] Clothing set definitions (farmer, worker, casual, formal)
-- [x] Age range mappings by personality category
-- [x] Work hour schedules per personality type
-- [x] Favor frequency tuning per personality
-- [x] Gift preference lists per personality
-- [x] Default vehicle loadouts per personality
-- FUTURE ENHANCEMENTS:
-- [ ] Seasonal personality modifiers (grumpy in winter, social in summer)
-- [ ] NPC backstory/biography generation from personality traits
-- [ ] Expandable name pools loaded from external XML data files
-- [ ] NPC portrait/avatar selection tied to age and clothing set
-- [ ] Relationship compatibility matrix between personality types
-- [ ] Regional name pools (German, French, American, etc.)
-- =========================================================

-- =========================================================
-- FS25 NPC Favor Mod - Configuration Data
-- =========================================================
-- Contains NPC definitions, names, and configuration data
-- =========================================================

NPCConfig = NPCConfig or {}
local NPCConfig_mt = Class(NPCConfig)

function NPCConfig.new()
    local self = setmetatable({}, NPCConfig_mt)
    
    -- NPC Names (using localization keys)
    self.npcNames = {
        "npc_name_1", "npc_name_2", "npc_name_3", 
        "npc_name_4", "npc_name_5", "npc_name_6"
    }
    
    -- Personalities
    self.personalities = {
        "hardworking",  -- Works long hours, rarely takes breaks
        "lazy",         -- Takes many breaks, short work days
        "social",       -- Likes to talk with other NPCs
        "loner",        -- Prefers to work alone
        "generous",     -- More likely to give gifts/help
        "greedy",       -- Less likely to help, wants payment
        "friendly",     -- Quick to build relationships
        "grumpy",       -- Slow to build relationships
        "early_riser",  -- Starts work early
        "night_owl",    -- Works late, starts late
        "perfectionist",-- Takes time to do things right
        "hasty"         -- Works quickly, may make mistakes
    }
    
    -- Vehicle types NPCs can own
    self.vehicleTypes = {
        "tractor",
        "harvester",
        "truck",
        "trailer",
        "plow",
        "seeder",
        "sprayer",
        "loader"
    }
    
    -- Vehicle colors
    self.vehicleColors = {
        {r = 1.0, g = 0.2, b = 0.2, name = "red"},
        {r = 0.2, g = 0.6, b = 1.0, name = "blue"},
        {r = 0.2, g = 0.8, b = 0.2, name = "green"},
        {r = 1.0, g = 1.0, b = 0.2, name = "yellow"},
        {r = 0.8, g = 0.5, b = 0.2, name = "orange"},
        {r = 0.6, g = 0.2, b = 0.8, name = "purple"},
        {r = 0.9, g = 0.9, b = 0.9, name = "white"},
        {r = 0.2, g = 0.2, b = 0.2, name = "black"}
    }
    
    -- Clothing sets
    self.clothingSets = {
        farmer = {"overalls", "boots", "hat"},
        worker = {"jeans", "t-shirt", "vest"},
        casual = {"shirt", "pants", "jacket"},
        formal = {"suit", "tie", "dress_shoes"}
    }
    
    -- Age ranges by personality type
    self.ageRanges = {
        young = {min = 25, max = 35},
        middle = {min = 36, max = 50},
        senior = {min = 51, max = 65}
    }
    
    return self
end

function NPCConfig:getRandomNPCName()
    local nameKey = self.npcNames[math.random(1, #self.npcNames)]
    local name = g_i18n:getText(nameKey)
    
    if not name or name == "" then
        -- Fallback names
        local fallbackNames = {
            "Old MacDonald", "Farmer Joe", "Mrs. Henderson", 
            "Young Peter", "Anna Schmidt", "Hans Bauer"
        }
        name = fallbackNames[math.random(1, #fallbackNames)]
    end
    
    return name
end

function NPCConfig:getRandomPersonality()
    return self.personalities[math.random(1, #self.personalities)]
end

function NPCConfig:getRandomVehicleType()
    return self.vehicleTypes[math.random(1, #self.vehicleTypes)]
end

function NPCConfig:getRandomVehicleColor()
    return self.vehicleColors[math.random(1, #self.vehicleColors)]
end

function NPCConfig:getRandomClothing()
    local sets = {"farmer", "worker", "casual", "formal"}
    local set = sets[math.random(1, #sets)]
    return self.clothingSets[set]
end

function NPCConfig:getRandomNPCModel()
    -- In actual implementation, return path to 3D model
    -- For now, return a placeholder
    return "farmer"
end


