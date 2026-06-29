import re
path = r'c:\Users\tison\Desktop\FS25 MODS\FS25_NPCFavor\src\scripts\NPCEntity.lua'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

old = (
    "        specializations  = {},\n"
    "        getClass         = function() return \"HumanCharacter\" end,\n"
)

new = (
    "        specializations  = { Character = true },\n"
    "        class            = \"Character\",\n"
    "        getClass         = function() return \"HumanCharacter\" end,\n"
)

if old in content:
    content = content.replace(old, new, 1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print('SUCCESS')
else:
    print('FAIL')
