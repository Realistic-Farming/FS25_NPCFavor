import re
path = r'c:\Users\tison\Desktop\FS25 MODS\FS25_NPCFavor\src\scripts\NPCEntity.lua'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

old = (
    "function NPCEntity:buildHotspotPlaceableProxy(npc)\n"
    "    local name = (npc and npc.name) or \"NPC\"\n"
    "    local farmId = (g_localPlayer and g_localPlayer.farmId) or 1\n"
    "    local entityManager = self\n"
    "    return setmetatable({\n"
    "        canBeSold        = function() return false end,\n"
    "        getName          = function() return tostring(name) end,\n"
    "        getImageFilename = function() return entityManager:getPortraitImagePath(npc) end,\n"
    "        getDailyUpkeep   = function() return 0 end,\n"
    "        getAge           = function() return 0 end,\n"
    "        ownerFarmId      = farmId,\n"
    "        storeItem        = nil,\n"
    "        specializations  = {},\n"
    "    }, {\n"
    "        __index = function(_, k)\n"
    "            if type(k) == \"string\" and k:sub(1, 5) == \"spec_\" then\n"
    "                return nil\n"
    "            end\n"
    "            return function() return nil end\n"
    "        end,\n"
    "    })\n"
    "end"
)

new = (
    "function NPCEntity:buildHotspotPlaceableProxy(npc)\n"
    "    local name = (npc and npc.name) or \"NPC\"\n"
    "    local farmId = (g_localPlayer and g_localPlayer.farmId) or 1\n"
    "    local entityManager = self\n"
    "    return setmetatable({\n"
    "        canBeSold        = function() return false end,\n"
    "        getName          = function() return tostring(name) end,\n"
    "        getImageFilename = function() return entityManager:getPortraitImagePath(npc) end,\n"
    "        getDailyUpkeep   = function() return 0 end,\n"
    "        getAge           = function() return 0 end,\n"
    "        ownerFarmId      = farmId,\n"
    "        storeItem        = nil,\n"
    "        specializations  = {},\n"
    "        getClass         = function() return \"HumanCharacter\" end,\n"
    "        getFirstName     = function() return tostring(name) end,\n"
    "        getFullName      = function() return tostring(name) end,\n"
    "    }, {\n"
    "        __index = function(_, k)\n"
    "            if type(k) == \"string\" and k:sub(1, 5) == \"spec_\" then\n"
    "                return nil\n"
    "            end\n"
    "            return function() return nil end\n"
    "        end,\n"
    "    })\n"
    "end"
)

if old in content:
    content = content.replace(old, new, 1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print('SUCCESS')
else:
    print('FAIL')
