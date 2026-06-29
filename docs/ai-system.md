# NPC AI System Reference

This document describes the AI system that drives NPC behavior in the FS25 NPCFavor mod.
The system is implemented across two primary files:

- `src/scripts/NPCAI.lua` -- State machine, decision-making, needs, mood, pathfinding, social grouping
- `src/scripts/NPCScheduler.lua` -- Daily schedule templates, timed events, weather effects, seasonal variation

---

## 1. AI States

The AI is built around a finite state machine. Each NPC holds an `aiState` value set to one of
the following canonical constants defined in `NPCAI.STATES`:

| State | Constant | Description |
|---|---|---|
| idle | `IDLE` | Standing in place, waiting for the next decision. Personality-specific micro-behaviors play (scanning, pacing, facing away). |
| walking | `WALKING` | Moving along a waypoint path to a nearby destination (under 100m). Supports walking-pair logic. |
| working | `WORKING` | Traversing an assigned field along a work pattern (rows, spiral, perimeter, or spot-check). |
| driving | `DRIVING` | Operating a vehicle (car or tractor) toward a drive destination. Speed depends on vehicle type. |
| resting | `RESTING` | Recovering energy. Also used for nighttime sleeping. Duration varies by personality. |
| socializing | `SOCIALIZING` | Engaged in a one-on-one conversation with another NPC. Both partners face each other. |
| traveling | `TRAVELING` | Walking to a distant destination (over 200m). Uses the same movement logic as WALKING. |
| gathering | `GATHERING` | Participating in a group activity -- chatting circle, lunch cluster, or event-based gathering. NPCs walk to assigned positions and face the group center. |

State transitions are managed by `NPCAI:setState()`, which resets relevant timers, clears
building-check flags, restores original movement speed when leaving movement states, deactivates
tractors when leaving WORKING, and flags multiplayer sync dirty.

---

## 2. Decision Making

When an NPC finishes its idle timer, `NPCAI:makeAIDecision()` determines the next action.
The decision pipeline has four stages, evaluated in order:

### Stage 1: Weather Override

The scheduler's weather factor is checked. If the factor is 0.3 or below (storm), all NPCs
go home. If 0.5 or below (heavy rain), non-hardworking NPCs go home. If 0.7 or below (light
rain), there is a 50% chance that NPCs scheduled to walk will go home instead.

### Stage 2: Needs Emergency Override

If any need exceeds the emergency threshold of 80:

- `energy > 80` -- forces "rest"
- `social > 80` (except grumpy/loner) -- forces "socialize"
- `hunger > 80` -- forces "go_home" (to eat)

### Stage 3: Structured Daily Schedule

The primary decision source. `getScheduledActivity()` maps the current game hour and minute
to a scheduled activity based on the NPC's personality. If a match is found, its mapped
decision is returned directly: "work", "walk", "socialize", "go_home", "rest", or "idle".

### Stage 4: Weighted-Random Fallback with Markov Influence

When no schedule slot applies, a weighted-random system selects the next action.

**Base weights (daytime, 06:00-18:00):**
- work: 40, walk: 30, socialize: 20, rest: 10

**Base weights (nighttime):**
- go_home: 60, rest: 30, walk: 10

These weights are then modified by:

1. **Markov chain transition probabilities** -- multipliers based on the current state:

   | Transition | Probability |
   |---|---|
   | idle -> walk | 0.30 |
   | idle -> work | 0.40 |
   | idle -> rest | 0.20 |
   | idle -> socialize | 0.25 |
   | walk -> idle | 0.10 |
   | walk -> socialize | 0.15 |
   | work -> idle | 0.05 |
   | work -> rest | 0.10 |
   | rest -> idle | 0.30 |
   | rest -> walk | 0.20 |
   | socialize -> idle | 0.20 |
   | socialize -> walk | 0.15 |

   Applied as: `weight = weight * (1 + transitionProbability)`

2. **Personality modifiers** (see Section 6)
3. **Mood modifiers** (see Section 4)
4. **Needs modifiers** -- energy > 50 boosts rest weight; social > 50 boosts socialize weight; workSatisfaction < 30 boosts work weight by 1.5x
5. **Player relationship** -- relationship > 70 boosts walk weight by 1.5x

Final selection uses weighted random sampling over the adjusted weights.

---

## 3. Needs System

Each NPC has four needs on a 0-100 scale, where 0 is fully satisfied and 100 is desperate.
Needs are updated every frame by `NPCAI:updateNeeds()`.

### Need Definitions

| Need | Meaning | Increases when | Decreases when |
|---|---|---|---|
| energy | Fatigue level | Awake and active | Resting or sleeping |
| social | Loneliness | Alone (any non-social state) | Socializing or gathering |
| hunger | Need to eat | Over time (always) | During lunch slot |
| workSatisfaction | Fulfillment from work | Idle or non-work states | Working (rises toward 100 = satisfied) |

### Base Rates (per second)

| Need | Base Rate | Working | Socializing | Resting | Walking |
|---|---|---|---|---|---|
| energy | +0.08 | +0.15 | +0.05 | -0.15 | +0.10 |
| social | +0.06 | +0.06 | -0.30 | +0.06 | +0.06 |
| hunger | +0.04 | +0.04 | +0.04 | +0.04 | +0.04 |
| workSatisfaction decay | -0.03 | -0.20 (satisfying) | -0.03 | -0.03 | -0.03 |

During lunch hours (12:00 to 12:00 + lunchDuration), hunger rate becomes -0.50.

### Personality Modifiers to Rates

| Personality | Effect |
|---|---|
| hardworking | workSatisfaction decay rate x1.5 (gets unsatisfied faster when idle) |
| lazy | energy rate x1.4 (tires more quickly); workSatisfaction decay rate x0.5 (doesn't care about work) |
| social | social rate x1.5 (gets lonely faster) |
| grumpy | social rate x0.5 (doesn't mind being alone) |

### Sleeping

While sleeping, special rates apply outside of `updateNeeds()`:
- energy: -0.8/s (recovering)
- hunger: +0.02/s (slowly getting hungry overnight)

---

## 4. Mood System

Mood is derived from the average of all needs by `NPCAI:updateMood()`. The formula averages
`energy`, `social`, `hunger`, and `(100 - workSatisfaction)`. Lower average means more
satisfied.

| Average Need Level | Mood |
|---|---|
| < 30 | happy |
| 30-59 | neutral |
| 60-79 | stressed |
| 80+ | tired |

### Mood Effects

**Movement speed:**
- happy: speed x1.1 (10% faster)
- tired: speed x0.85 (15% slower)

**Decision weight modifiers:**
- happy: socialize weight x1.4, walk weight x1.3
- stressed: socialize weight x0.5, go_home weight x1.5
- tired: rest weight x2.0, work weight x0.5

**Social behavior:**
- Stressed NPCs reject social invitations unless the inviter is a friend (relationship > 60).

**Greeting tone:**
- tired: "I'm so tired today..."
- stressed: "Not the best day..."
- happy: random cheerful greeting ("What a great day!", "Feeling wonderful!", "Life is good!")

---

## 5. Daily Schedule

Each NPC follows a structured daily routine defined in `NPCAI.personalitySchedule`. The
schedule is queried by `getScheduledActivity()`, which maps the current time to an activity
name, a decision string, and a display action string.

### Personality-Specific Schedules

All times are in 24-hour format. Seasonal and weekend adjustments are applied on top.

| Parameter | hardworking | lazy | social | grumpy | generous |
|---|---|---|---|---|---|
| Wake | 5:00 | 7:00 | 5:30 | 5:30 | 5:30 |
| Work Start | 5:30 | 8:00 | 6:30 | 6:00 | 6:30 |
| Lunch Duration (hours) | 0.5 | 1.5 | 1.5 | 0.5 | 1.0 |
| Work End | 18:00 | 16:00 | 17:00 | 17:00 | 17:00 |
| Sleep | 21:00 | 23:00 | 22:00 | 21:00 | 22:00 |

Default schedule (for unlisted personalities): wake 5:30, work start 6:30, lunch 1h, work end 17:00, sleep 22:00.

### Daily Timeline (Weekday)

Using the schedule parameters, a weekday unfolds as:

| Time Block | Activity | Decision | Display Action |
|---|---|---|---|
| sleep -> wake | sleeping | rest | sleeping |
| wake -> wake+1 | wake_up | idle | waking up |
| wake+1 -> workStart-0.5 | morning_routine | walk | morning walk |
| workStart-0.5 -> workStart | commute_to_work | work | commuting |
| workStart -> 12:00 | work_morning | work | working |
| 12:00 -> 12:00+lunchDuration | lunch | socialize | at lunch |
| lunchEnd -> workEnd | work_afternoon | work | working |
| workEnd -> workEnd+0.5 | commute_home | go_home | heading home |
| workEnd+0.5 -> eveningSocialEnd | evening_social | socialize | socializing |
| eveningSocialEnd -> eveningSocialEnd+1 | dinner | go_home | dinner |
| dinnerEnd -> sleep | leisure | idle or walk (20% chance) | relaxing / evening stroll |

Evening social end time varies by personality: social gets until 21:00, grumpy until 19:00, others until 19:00.

### Seasonal Adjustments

Season is derived from the current game month:
- Spring: months 3-5
- Summer: months 6-8
- Autumn: months 9-11
- Winter: months 12, 1-2

| Season | Wake Adjustment | Work End Adjustment | Work Start Adjustment |
|---|---|---|---|
| Winter | +1 hour | -1 hour | -- |
| Summer | -0.5 hours | +0.5 hours | -0.5 hours |

---

## 6. Personality Types

Five personality types affect behavior throughout the system:

### hardworking

- Wakes earliest (5:00), sleeps earliest (21:00), shortest lunch (30 min)
- Idle timer: 1.5 seconds (gets restless fast)
- Idle micro-behavior: micro-pacing, small position shifts every 1.5s
- Decision weights: work x2, rest x0.5
- Work duration: 180 seconds before break (longest)
- Rest duration: 30 seconds (shortest)
- Drive duration: 30 seconds (longest)
- Weather override: pushes through heavy rain (weatherFactor 0.5); only goes home in storms (0.3)
- Work satisfaction decays 1.5x faster when idle
- Activity duration: work-related activities last 30% longer

### lazy

- Wakes latest (7:00), sleeps latest (23:00), longest lunch (1.5 hours)
- Idle timer: 6 seconds (stands around twice as long)
- Idle micro-behavior: none (extended stillness IS the behavior)
- Decision weights: work x0.5, rest x2
- Work duration: 60 seconds before break (shortest)
- Rest duration: 90 seconds (longest)
- Drive duration: 10 seconds (shortest)
- Energy drains 1.4x faster (tires easily)
- Work satisfaction decay x0.5 (doesn't care about work)
- Scheduler classification: uses "casual" schedule template
- Activity duration: work-related activities last 30% shorter

### social

- Wake at 5:30, sleep at 22:00, lunch 1.5 hours
- Idle timer: 2 seconds (seeks company quickly)
- Idle micro-behavior: slow rotation scanning every 2 seconds, looking for nearby NPCs
- Decision weights: socialize x2
- Social timer: 25 seconds per conversation (longest)
- Gathering duration: 90 seconds (longest)
- Evening social time: until 21:00 (latest)
- Social need rises 1.5x faster (gets lonely quickly)
- Sociability chance: 0.8 (highest)

### grumpy

- Wake at 5:30, sleep at 21:00, lunch 30 min
- Idle timer: 4 seconds (lingers impatiently)
- Idle micro-behavior: faces away from nearest NPC every 3 seconds
- Decision weights: socialize x0.4
- Gathering duration: 30 seconds (shortest, tied with loner)
- Evening social time: until 19:00 (earliest)
- Social need rate x0.5 (doesn't mind being alone)
- Sociability chance: 0.3
- Greeting style: "What do you want?", "Hmph.", "*grunt*", "..."
- Conversation topics: "Make it quick.", "I've got things to do."

### generous

- Wake at 5:30, sleep at 22:00, lunch 1 hour
- Uses default idle timer (3 seconds)
- No specific idle micro-behavior
- Field work pattern: spiral inward (edges to center)
- Conversation topics: offers help, asks about others' crops
- Responses: "Of course!", "Happy to help!"

---

## 7. Weather Response

Weather is read from the game environment and converted to a numerical factor by
`NPCScheduler:getWeatherFactor()`:

| Weather | Factor |
|---|---|
| clear / sunny | 1.0 |
| cloudy | 0.9 |
| fog | 0.8 |
| rain | 0.7 |
| snow | 0.5 |
| storm | 0.3 |

### Decision-Level Effects

In `makeAIDecision()`:
- Factor <= 0.3 (storm): all NPCs go home. Hardworking NPCs also go home.
- Factor <= 0.5 (heavy rain/snow): non-hardworking NPCs go home. Hardworking NPCs continue.
- Factor <= 0.7 (rain): 50% chance that NPCs scheduled to walk go home instead.

### Work Interruption

In `updateWorkingState()`, weather is checked every 30 seconds:
- Factor <= 0.3: all NPCs stop field work and go home.
- Factor <= 0.5: non-hardworking NPCs stop field work and go home.

### Event System

Weather affects favor generation likelihood. The scheduler multiplies the base 30% favor
opportunity chance by the weather factor, reducing favor requests during bad weather.

### Rain Shelter Event

When a rain shelter event triggers, NPCs:
1. Increase movement speed to 1.5x normal (hurrying through rain)
2. Walk to the nearest building
3. Cluster near the building in a gathering state

### Conversation Topics

When weatherFactor < 0.7, there is a 40% chance NPCs will discuss weather:
"Looks like rain is coming...", "Hope the crops can handle this weather.",
"Should we head inside?", "My fields are getting soaked!"

---

## 8. Weekend Variation

Day type is determined by `(currentDay % 7)`:
- 0 = Sunday
- 6 = Saturday
- 1-5 = Weekday

### Sunday Schedule

Sunday overrides the normal daily routine entirely:

- Wake time: +2 hours later than weekday
- Sleep time: +1 hour later (capped at 24:00)
- No work at all

| Time Block | Activity | Decision | Display Action |
|---|---|---|---|
| sleep -> wake | sleeping | rest | sleeping |
| wake -> wake+1 | wake_up | idle | waking up |
| wake+1 -> 12:00 | morning_leisure | walk | morning stroll |
| 12:00 -> 14:00 | lunch | socialize | Sunday lunch |
| 14:00 -> 18:00 | afternoon_social | socialize | Sunday socializing |
| 18:00 -> 20:00 | dinner | go_home | Sunday dinner |
| 20:00 -> sleep | evening_rest | idle | relaxing at home |

Additionally, the event system can trigger "sunday_rest" events where NPCs mill about near
home in the morning or visit a neighbor's home.

### Saturday Schedule

Saturday is a half-day:

- Wake time: +1 hour later than weekday
- Work end: capped at 13:00 (half-day work)
- Evening social time: +1 hour extension (capped at 22:00)
- Afternoon and evening follow the normal timeline with the shortened work day

---

## 9. Field Work Patterns

When an NPC starts working, `NPCAI:initFieldWork()` generates a set of waypoints across the
assigned field. The pattern depends on the NPC's personality:

### Row Traversal (hardworking, default)

East-west rows across the field with 6m spacing. Alternating direction per row (zigzag).
Capped at 12 rows. This is the most thorough coverage pattern.

```
 --->  --->  --->
 <---  <---  <---
 --->  --->  --->
```

### Spiral Inward (generous)

Starts at the field edges and spirals toward the center over 20 steps, completing 2 full
rotations. The radius decreases linearly from the field half-size to zero.

```
  ___________
 |  _______  |
 | |  ___  | |
 | | | * | | |
 | | |___| | |
 | |_______| |
 |___________|
```

### Perimeter Walk (grumpy)

Walks the four corners of the field in a closed loop. Simulates fence inspection or
boundary checking. Minimal coverage of the interior.

```
 *-----------*
 |           |
 |           |
 |           |
 *-----------*
```

### Spot Check (lazy, social)

Six random inspection points scattered across the field. No systematic coverage.
The NPC walks between random positions within the field bounds.

```
       *
   *       *
     *
  *      *
```

### Field Work Behavior

- Movement speed is set to 1.8 m/s (tractor field speed) during work.
- When an NPC reaches a waypoint (within 2m), it advances to the next one.
- After completing all waypoints, the index loops back to 1.
- Work duration before a break depends on personality:
  - hardworking: 180 seconds
  - default: 120 seconds
  - lazy: 60 seconds
- After the timer expires: 30% chance to take a break (transition to IDLE), 70% chance to
  continue with a new work pattern from the current position.

---

## 10. Social System

### NPC-NPC Socializing

`startSocializing()` pairs two NPCs:

1. Both NPCs face each other (yaw rotation computed via atan2).
2. A conversation topic is generated based on time, weather, personality, and context.
3. The initiator shows the topic as a speech bubble (greetingText) for 4 seconds.
4. The responder shows a personality-appropriate response for 4 seconds.
5. Both are set to SOCIALIZING state with cross-references to each other.
6. The encounter is recorded in the NPC memory system.

**Social duration:**
- social personality: 25 seconds
- loner personality: 5 seconds
- default: 15 seconds

On completion, NPC-NPC relationship is updated and both NPCs' social need decreases by 15.

### Finding Social Partners

`findSocialPartners()` searches for suitable partners within a range (default 50m).
A partner must be:
- Active and not the same NPC
- Within range
- Willing based on mood (stressed NPCs refuse unless the initiator is a friend with relationship > 60)
- Willing based on personality (social NPCs always willing; others have a 30% base chance; friends override)
- In IDLE or WALKING state

Partners are sorted by NPC-NPC relationship value (friends first).

### Chatting Groups

`tryFormGroup()` creates groups of 3-4 NPCs:
- Finds 2-3 partners within 30m
- Calculates the average position as the group center
- Offsets the center 20% toward the nearest building for natural placement
- Ensures the center is not inside a building
- Arranges members in a loose circle (2m radius) with slight angular randomness
- All members enter GATHERING state

### Walking Pairs

`tryFormWalkingPair()` pairs two NPCs during commute hours (7-8 AM, 5-6 PM):
- Finds another unpaired NPC within 20m that is walking or traveling
- Sets mutual `walkingPartner` references
- The follower nudges toward the leader if distance exceeds 3m
- Speed is matched to the partner's movement speed
- The pair dissolves when either NPC stops walking or changes state

### Lunch Clusters

`tryFormLunchCluster()` activates during lunch hour (12:00-13:00):
- Finds the nearest building to the initiating NPC
- Gathers up to 4 NPCs within 20m of the building and each other
- Positions the cluster center 3m outside the building (toward the NPC group)
- Arranges members in a semicircle (144-degree arc) facing the building
- Duration: 30-60 real seconds
- All members enter GATHERING state with "lunching" action label

### Conversation Topics

Topics are selected based on context:

| Context | Example Topics |
|---|---|
| Bad weather (factor < 0.7) | "Looks like rain is coming...", "My fields are getting soaked!" |
| Morning (6-9) | "Beautiful morning, isn't it?", "Coffee first, then work." |
| Lunch (12-13) | "What's for lunch today?", "I'm starving!" |
| Evening (17-20) | "Long day, huh?", "Plans for the evening?" |
| hardworking personality | "The fields need attention.", "Work keeps me going." |
| lazy personality | "Think we could take a longer break?", "I could use a nap." |
| social personality | "Have you heard the latest news?", "We should get the others together!" |
| grumpy personality | "What do YOU want?", "Make it quick." |
| generous personality | "Need any help with your field?", "Let me know if I can help." |

Responses vary by the responder's personality (e.g., grumpy responds with "Whatever.", "Hmph.").

---

## 11. Pathfinding

The `NPCPathfinder` class provides waypoint-based pathfinding with several layers of safety.

### Path Generation

`findPath()` proceeds through these steps:

1. **Cache lookup** -- paths are cached by start/end coordinates (rounded to 0.1m). Cache holds
   up to 50 paths with LRU-style eviction every 60 seconds.

2. **Road spline path** -- if road splines have been discovered, attempts to find a same-spline
   route. The path has three phases:
   - Walk from start to the nearest point on the spline
   - Follow the spline at 5m waypoint intervals
   - Walk from the spline exit to the destination
   For traffic splines, a 2.5m side offset keeps NPCs on the roadside rather than the center lane.
   Pedestrian splines have no offset.

3. **Direct-line path with intermediate waypoints** -- for distances over 50m, up to 5
   intermediate points are generated with random perpendicular variation to avoid straight lines.
   Each intermediate point is:
   - Pushed out of buildings via `getSafePosition()`
   - Checked for steep terrain; if the rise exceeds 1.5x the horizontal distance, the waypoint
     is nudged sideways (trying offsets of 15m and 30m in both perpendicular directions)

4. **Path optimization** -- removes waypoints where the direction change is less than 30 degrees.

5. **Bezier smoothing** -- if VectorHelper.smoothPath is available, corners are smoothed with
   4-point subdivision. Terrain heights are reapplied to all smoothed points.

### Road Spline Discovery

`discoverRoadSplines()` runs once at map load:
- Traverses the scene graph root looking for `trafficSystem` and `pedestrianSystem` transform groups
- Also searches one level deeper (some maps nest these under a map root node)
- Collects all valid spline nodes with their lengths
- Traffic splines get a 2.5m side offset; pedestrian splines get 0
- Results are cached in `self.roadSplines` and `self.pedestrianSplines`

### Movement-Level Safety

Applied every frame in `updateNPCState()` after all state updates:

**Cliff prevention:**
- Looks 3m ahead in the movement direction
- If terrain rises more than 3m over that distance, the movement is reverted
- Tries 8 compass directions to find a gentler alternative (rise < 2m)
- If all directions are blocked, skips the current waypoint if it's on a cliff

**Building collision:**
- Checks NPC position against all non-home buildings every frame
- If inside a building's collision radius (+1m margin), pushes the NPC outward
- If dead center (< 0.1m from building center), escapes in a random direction

**Terrain height snap:**
- Every NPC is snapped to terrain height every frame (+0.05m offset)

**Walking state building avoidance:**
- While walking, checks if the next position enters or approaches a building
- Uses an approach margin of building radius + 2m
- Computes a tangent direction (perpendicular to the building vector) that moves the NPC
  roughly toward the target
- Adds outward push that increases as the NPC gets closer to the building center

**Steep terrain during walking:**
- If terrain ahead rises more than 3m or slope exceeds 1.5, movement is blocked
- Tries left and right perpendicular directions
- Falls back to reversing direction (walking downhill)
- On gentle slopes (rise > 1m), speed is reduced to 70%

### Water Avoidance

`getSafeTerrainHeight()` checks for water at each waypoint position. If water is detected
(via `getWaterTypeAtWorldPos`), it searches outward in a spiral pattern (5m to 50m, 16
directions per ring) to find the nearest dry land and reroutes to that position.

---

## 12. Night Safety

The night safety system operates at two levels to ensure NPCs are indoors after dark.

### Sleep/Wake Cycle (updateSleepState)

Called every frame before the state dispatch:

- Uses the personality-specific wake and sleep times to determine if the NPC should be sleeping.
- **Going to sleep:** sets `isSleeping = true`, `canInteract = false`, transitions to RESTING,
  teleports NPC to their home position, clears any active path and target.
- **Waking up:** sets `isSleeping = false`, restores entity visibility (both main node and
  animated character root node if applicable), transitions to IDLE.
- While sleeping, the NPC is effectively invisible and non-interactive.

### Safety Net Teleport (23:00-04:00)

A hard safety net in `updateNPCState()` catches NPCs that are still outdoors late at night
due to stuck states or edge cases:

- Active between 23:00 and 04:00
- Skipped if a dynamic event is currently active
- If an NPC is more than 20m from their home position:
  1. Teleports the NPC to their home coordinates
  2. Forces `isSleeping = true`
  3. Sets state to RESTING
  4. Clears path, field work path, and field work index
  5. Stops any active AI job (real tractor or legacy)
  6. Logs the teleport distance in debug mode

### Other Night Behavior

- Stuck detection is disabled for stationary states (IDLE, WORKING, RESTING, SOCIALIZING,
  GATHERING) so sleeping NPCs don't trigger the 5-second stuck threshold.
- If an NPC is talking to the player (dialog open), AI is frozen regardless of time.

---

## Appendix: Scheduler Templates

The `NPCScheduler` provides a parallel schedule system with three templates (farmer, worker,
casual) and seasonal variants for farmers. The schedule templates define activity slots with
start/end hours and priority levels.

### Farmer Schedule (Seasonal)

**Spring:**
06-07 morning routine, 07-12 field preparation, 12-13 lunch, 13-17 planting,
17-19 equipment maintenance, 19-22 personal time, 22-06 sleeping

**Summer:**
05-06 morning routine, 06-11 irrigation, 11-15 heat break, 15-20 field maintenance,
20-22 evening chores, 22-05 sleeping

**Autumn:**
06-07 morning routine, 07-12 harvesting, 12-13 lunch, 13-18 harvesting,
18-20 storage work, 20-22 personal time, 22-06 sleeping

**Winter:**
08-09 morning routine, 09-12 indoor work, 12-13 lunch, 13-16 equipment repair,
16-18 planning, 18-22 personal time, 22-08 sleeping

### Worker Schedule
07-08 commute, 08-12 work shift, 12-13 lunch, 13-16 work shift, 16-17 commute home,
17-22 free time, 22-07 sleep

### Casual Schedule
09-10 breakfast, 10-12 chores, 12-14 lunch social, 14-17 leisure, 17-19 evening activities,
19-23 dinner/relax, 23-09 sleep

### Personality-to-Template Mapping

| Personality | Template |
|---|---|
| worker, perfectionist | worker |
| casual, lazy | casual |
| All others (hardworking, social, grumpy, generous, farmer) | farmer |

---

## Appendix: Transport Mode Selection

NPCs choose how to travel based on distance and available vehicles:

| Condition | Transport Mode | Speed |
|---|---|---|
| Distance < 150m (no real tractor, or < 100m) | walk | 1.4 m/s (default); 2.8 m/s for long commutes (> 100m) |
| Distance > 100m with real tractor in realistic mode | tractor | 5.5 m/s (~20 km/h) |
| Distance > 150m with vehicle driving enabled | car | 8.3 m/s (~30 km/h) |

Vehicle props (car/tractor i3d models) are shown during the commute via the entity manager.
On arrival, cars are parked 5-8m from the destination at a random angle. Tractors are hidden
(they stay at the field). The NPC is restored to ground level and `canInteract` is set to true.

---

## Appendix: Stuck Detection and Recovery

`isNPCStuck()` runs every frame for movement states (WALKING, TRAVELING, DRIVING):

- Compares current position to previous position
- If movement is less than 0.1m, accumulates `stuckTimer`
- After 5 seconds of no movement, the NPC is considered stuck

`handleStuckNPC()` recovery:
1. Hides any active vehicle props (car/tractor)
2. Clears transport mode state
3. Releases current vehicle (prevents permanent vehicle lock)
4. Clears drive destination and callback
5. Resets to IDLE state
6. Clears path and target position
7. Resets stuck timer

Stationary states (IDLE, WORKING, RESTING, SOCIALIZING, GATHERING) reset the stuck timer
to 0 every frame to prevent false positives.
