# FS25 NPC Favor - Living Neighborhood Mod
![Downloads](https://img.shields.io/github/downloads/TheCodingDad-TisonK/FS25_NPCFavor/total?style=for-the-badge)
![Release](https://img.shields.io/github/v/release/TheCodingDad-TisonK/FS25_NPCFavor?style=for-the-badge)
![License](https://img.shields.io/badge/license-All%20Rights%20Reserved-red?style=for-the-badge)

**From a follower:**
> "Hello friend,
> I just wanted to write to you that I came across your mod realistic worker cost and that I like it because I am a fan of fs and realism myself. I was thinking and wanted to share this idea with you, since I am not good at programming I thought I could share this idea > with you. The idea is to add a living neighborhood to fs, i.e. NPCs who live around come to life and work on their fields with their own machinery. That would be the first part, and the second would be that you could ask them for a favor or they would ask you for a  > favor, so that they would be physically present on the map. If you like the idea in any way, I would be happy if you would respond.
> Your new follower,"

Thanks for reading; Now about the mod itself...

---

**Breathe life into your farmland!** This mod adds a living, breathing community of NPC neighbors to Farming Simulator 25. They walk the roads, follow daily routines driven by their own internal needs, build relationships with each other and with you, and ask for help with favors. Each NPC has a personality, a home, and opinions about you that change over time.

The mod supports singleplayer and multiplayer (not yet tested) , saves all NPC data across sessions, and is fully localized in 10 languages.

## ✨ Features

- **Animated NPC Neighbors** -- NPCs spawn at buildings around the map (shops, gas stations, production points, farms) as visible human figures with walk and idle animations.
- **Needs-Based AI** -- NPCs are driven by four internal needs (energy, social, hunger, work satisfaction) rather than rigid schedules. A tired NPC goes home to sleep. A lonely NPC seeks a neighbor to chat with. A restless worker heads to the fields early.
- **Personality System** -- Five personality types (hardworking, lazy, social, grumpy, generous) affect wake times, work habits, social tendencies, and conversation tone.
- **Road Pathfinding** -- NPCs follow FS25's road spline network instead of walking through buildings and fences. Paths are cached for performance.
- **Relationship System** -- A 0-100 relationship scale with seven tiers: Hostile, Unfriendly, Neutral, Acquaintance, Friend, Close Friend, and Best Friend. Each tier unlocks new benefits and dialog options.
- **NPC-NPC Social Graph** -- NPCs form relationships with each other based on personality compatibility. Compatible pairs drift toward friendship; incompatible pairs drift toward rivalry.
- **Favor System** -- NPCs ask for help with tasks like harvesting, transporting goods, fixing fences, and delivering seeds. Completing favors earns money and relationship points.
- **Dynamic Dialog** -- Context-aware conversations that change based on time of day, relationship level, NPC personality, and current activity.
- **Gift Giving** -- Spend $500 to give an NPC a gift and boost your relationship (unlocked at relationship 30+).
- **Weather Awareness** -- Rain and storms interrupt field work. NPCs comment on weather in conversations. Seasonal schedule shifts adjust wake times and work hours.
- **Speech Bubbles** -- NPCs display conversation text in world-space speech bubbles when socializing with each other.
- **Persistent Save/Load** -- NPC positions, relationships, active favors, personality data, and needs save to your savegame and restore on load.
- **10-Language Localization** -- 1,500+ i18n strings in English, German, French, Polish, Spanish, Italian, Czech, Brazilian Portuguese, Ukrainian, and Russian.
- **In-Game Settings** -- Toggle the NPC system on/off, set max NPC count, configure work hours, favor frequency, name display, notifications, and debug mode.
- **Console Commands** -- Type `npcHelp` in the developer console for a list of available commands.

---

## 🛠️ Installation

1. Download the `FS25_NPCFavor.zip` file.
2. Place it in your FS25 mods folder:
   - **Windows:** `Documents\My Games\FarmingSimulator2025\mods\`
   - **macOS:** `~/Library/Application Support/FarmingSimulator2025/mods/`
3. Launch Farming Simulator 25.
4. When starting or loading a savegame, enable **NPC Favor - Living Neighborhood** in the mod selection screen.
5. Load into your farm and start playing.

---

## 🎮 Quick Start

1. **NPCs spawn automatically.** After the map loads, NPCs appear near buildings around the map. You'll see a console message confirming initialization.
2. **Look for the talk prompt.** Walk near an NPC and a contextual prompt appears: "Talk to [NPC Name]" with the key the game has assigned to *Talk to NPC* (assign your own under Options > Controls > Mods). Press it to open the dialog.
3. **Start a conversation.** The dialog shows the NPC's name, your relationship level, and a greeting that reflects how well they know you.
4. **Choose an action.** Talk, Ask About Work, Ask for Favor, Give Gift, or view Relationship Info.
5. **Build the relationship.** Chat regularly, complete favors when available (at relationship 25+), and give gifts (at relationship 30+).
6. **Adjust settings.** Open the mod settings in the game's settings menu to tweak NPC count, work hours, favor frequency, and more.
7. **Your progress is saved.** All NPC data saves with your savegame and restores on load.

---

## 💬 Dialog System

When you press **E** near an NPC, a dialog opens with 5 action buttons:

| Button | What It Does | Requirements |
|--------|-------------|-------------|
| **Talk** | Random conversation topic, +1 relationship (once per day) | Always available |
| **Ask about work** | Shows what the NPC is currently doing | Always available |
| **Ask for favor** | Check active favor progress or request a new one | Relationship 25+ |
| **Give gift** | Spend $500 for a relationship boost | Relationship 30+ |
| **Relationship info** | See your level, benefits, next unlock, favor stats | Always available |

---

## 💕 Relationship System

Friendship with each NPC ranges from 0 to 100, organized into 7 tiers:

| Level | Range | Benefits Unlocked |
|-------|-------|-------------------|
| Hostile | 0-9 | None |
| Unfriendly | 10-24 | Basic interaction |
| Neutral | 25-39 | Can ask for favors, 5% discount |
| Acquaintance | 40-59 | Borrow equipment, 10% discount |
| Friend | 60-74 | NPC may offer help, 15% discount |
| Close Friend | 75-89 | Receives gifts, shared resources, 18% discount |
| Best Friend | 90-100 | Full benefits, 20% discount |

**How to improve:** Talk regularly (+1 per day), complete favors (+15), give gifts (+varies). Relationships decay slowly (-0.5/day) after 2 days without contact for relationships above 25.

---

## 🎁 Favor Types

NPCs can ask for help with 7 different kinds of tasks:

- **Help with harvest** -- Assist during busy harvest season
- **Transport goods to market** -- Deliver items to a selling point
- **Fix broken fence** -- Repair work around their property
- **Deliver seeds to my farm** -- Bring supplies they need
- **Borrow my tractor** -- Let an NPC use your equipment
- **Loan money** -- Financial assistance
- **Watch property** -- Keep an eye on things while they're away

Each favor has a time limit, progress tracking, and rewards (cash + relationship boost). Fail to complete one, and your relationship takes a small hit.

---

## 🖥️ Console Commands

Open the in-game console (`~` key) and type any of these:

| Command | Description |
|---------|-------------|
| `npcHelp` | Show all available commands |
| `npcStatus` | Full system status -- NPCs, subsystems, player position, game time |
| `npcList` | Opens a GUI table of all NPCs with personality, action, distance, relationship, and teleport buttons |
| `npcGoto <number>` | Teleport to an NPC by number (run without a number to see the list) |

---

## 🏗️ Architecture

The mod is built from cooperating subsystems coordinated by a central `NPCSystem`:

| Subsystem | What It Does |
|-----------|-------------|
| **NPCSystem** | Central coordinator -- spawns NPCs, runs the update loop, manages multiplayer sync, save/load |
| **NPCAI** | Needs-based AI state machine (idle, walking, working, resting, socializing, traveling, gathering) with road spline pathfinding |
| **NPCScheduler** | Personality-specific daily routines with weekend variation and seasonal adjustments |
| **NPCEntity** | Visual representation -- animated character models via FS25 HumanGraphicsComponent |
| **NPCRelationshipManager** | Player-NPC and NPC-NPC relationship tracking, personality compatibility, grudges, gift events |
| **NPCFavorSystem** | Favor generation, tracking, and completion with 7 favor types and timed objectives |
| **NPCInteractionUI** | World-space HUD -- speech bubbles, name tags, mood indicators, interaction prompts |
| **NPCDialog** | Press-E conversation dialog with 5 action buttons and hover effects |
| **NPCListDialog** | Console-triggered roster table with 16 rows and teleport buttons |
| **DialogLoader** | Lazy-loading dialog registry that wraps FS25's g_gui system |

---

## 📂 File Structure

```
FS25_NPCFavor/
+-- main.lua                          # Entry point -- hooks into FS25, E key binding, draw/save/load
+-- modDesc.xml                       # Mod config, input bindings, 1500+ i18n strings (10 languages)
+-- icon.dds / icon_small.dds         # Mod icons
+-- gui/
|   +-- NPCDialog.xml                # NPC interaction dialog layout (5 buttons + response area)
|   +-- NPCListDialog.xml            # NPC roster table layout (16 rows + teleport)
+-- src/
|   +-- NPCSystem.lua                # Central coordinator (spawning, update loop, save/load)
|   +-- gui/
|   |   +-- DialogLoader.lua         # Lazy-loading dialog registry
|   |   +-- NPCDialog.lua            # Interaction dialog logic
|   |   +-- NPCListDialog.lua        # Roster table logic
|   +-- scripts/
|   |   +-- NPCAI.lua                # AI state machine + road spline pathfinding
|   |   +-- NPCEntity.lua            # Animated character models, transform management
|   |   +-- NPCScheduler.lua         # Daily routines, personality schedules
|   |   +-- NPCRelationshipManager.lua  # Relationship tiers, NPC-NPC graph, compatibility
|   |   +-- NPCFavorSystem.lua       # Favor generation and tracking
|   |   +-- NPCInteractionUI.lua     # World-space HUD rendering (bubbles, tags, prompts)
|   +-- events/
|   |   +-- NPCStateSyncEvent.lua    # Server -> client NPC state sync
|   |   +-- NPCInteractionEvent.lua  # Client -> server interaction routing
|   |   +-- NPCSettingsSyncEvent.lua # Bidirectional settings sync
|   +-- settings/
|   |   +-- NPCSettings.lua          # Settings persistence (XML)
|   |   +-- NPCSettingsUI.lua        # Settings UI elements
|   |   +-- NPCSettingsIntegration.lua  # ESC menu injection
|   |   +-- NPCFavorGUI.lua          # Console command routing
|   +-- utils/
|       +-- VectorHelper.lua         # Math utilities (distance, lerp, normalize)
|       +-- TimeHelper.lua           # Game time conversion from dayTime ms
+-- docs/                            # Architecture, AI, relationship, settings, dialog, versioning docs
+-- CHANGELOG.md                     # Version history and release notes
```

---

## 🚧 Known Limitations

- **NPC vehicles** -- Vehicle prop code is in place but no vehicles spawn or render. NPCs walk everywhere.
- **Silent groups** -- Group gatherings and walking pairs position NPCs correctly but generate no conversation content. Only 1-on-1 socializing produces speech bubbles.
- **Flavor text localization** -- Mood prefixes, backstories, and personality-flavored dialog are English-only. Core UI and settings are fully localized.

---

## 📖 Documentation

For deeper details on each subsystem, see the [docs/ folder](docs/README.md):

- [Architecture Overview](docs/architecture.md)
- [AI System](docs/ai-system.md)
- [Relationship System](docs/relationship-system.md)
- [Settings Reference](docs/settings.md)
- [Changelog](CHANGELOG.md)

---

## 📝 License & Credits

- **Original Idea:** Lion2008
- **Implementation & Coding:** TisonK
- **AI Overhaul (v1.2.0):** XelaNull & Claude AI -- living neighborhood system, dialog framework, relationship engine, multiplayer sync, i18n.
- **License:** All rights reserved. Unauthorized redistribution, copying, or claiming this code as your own is strictly prohibited. This is a free mod for the community.

---

*Enjoy your new neighborhood, and happy farming!*
