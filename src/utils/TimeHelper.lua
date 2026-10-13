-- =========================================================
-- TODO / FUTURE VISION
-- =========================================================
-- TIME CONVERSION:
-- [x] Milliseconds to hours/minutes/seconds (msToHMS)
-- [x] Milliseconds to days/hours/minutes/seconds (msToDHMS)
-- [x] Long and short time formatting
-- [x] Time comparison helpers (isSameDay, daysBetween, hoursBetween)
-- [ ] Relative time formatting ("2 hours ago", "yesterday")
-- [ ] Localized time format strings (12h vs 24h based on language)
--
-- GAME TIME:
-- [x] Current game day accessor (getGameDay)
-- [ ] Formatted game time string output
-- [x] Time prediction (predictFutureTime, getTimeUntil)
-- [ ] Game time speed multiplier awareness for accurate real-time estimates
-- [ ] Alarm/timer system for scheduling NPC events at specific game times
--
-- SEASONS:
-- [x] Growing season detection (April-October)
-- [x] Winter detection (December-February)
-- [x] Full four-season classification (spring, summer, autumn, winter)
-- [ ] Southern hemisphere season support for map variety
-- [ ] Weather-aware time checks (rainy day behavior, etc.)
--
-- TIME OF DAY:
-- [x] Morning, afternoon, evening, night classification
-- [x] getTimeOfDay returns string label for current period
-- [ ] Dawn/dusk transition periods for NPC schedule blending
-- [ ] Configurable time-of-day thresholds per NPC personality
-- =========================================================

-- =========================================================
-- Time Helper Utilities
-- =========================================================
-- Time conversion and formatting utilities
-- =========================================================

TimeHelper = TimeHelper or {}

-- Convert milliseconds to hours, minutes, seconds
function TimeHelper.msToHMS(ms)
    local totalSeconds = math.floor(ms / 1000)
    local hours = math.floor(totalSeconds / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local seconds = totalSeconds % 60
    
    return hours, minutes, seconds
end

function TimeHelper.msToDHMS(ms)
    local totalSeconds = math.floor(ms / 1000)
    local days = math.floor(totalSeconds / 86400)
    local hours = math.floor((totalSeconds % 86400) / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local seconds = totalSeconds % 60
    
    return days, hours, minutes, seconds
end


function TimeHelper.getGameDay()
    if g_currentMission and g_currentMission.environment then
        return g_currentMission.environment.currentDay or 1
    end
    return 1
end

--- Returns absolute game time in milliseconds (currentDay * 86400000 + dayTime).
-- Scales with game speed (1x, 5x, 120x etc) unlike g_currentMission.time which
-- is real wall-clock ms. Use this for favor timers and any gameplay countdowns.
function TimeHelper.getGameTimeMs()
    if g_currentMission and g_currentMission.environment then
        local env = g_currentMission.environment
        local DAY_MS = 24 * 60 * 60 * 1000  -- 86,400,000
        return (env.currentDay or 0) * DAY_MS + (env.dayTime or 0)
    end
    return 0
end


-- Time comparison
function TimeHelper.isSameDay(time1, time2)
    if not time1 or not time2 then
        return false
    end
    
    local day1 = math.floor(time1 / (24 * 60 * 60 * 1000))
    local day2 = math.floor(time2 / (24 * 60 * 60 * 1000))
    
    return day1 == day2
end

function TimeHelper.daysBetween(time1, time2)
    if not time1 or not time2 then
        return 0
    end
    
    local day1 = math.floor(time1 / (24 * 60 * 60 * 1000))
    local day2 = math.floor(time2 / (24 * 60 * 60 * 1000))
    
    return math.abs(day2 - day1)
end

function TimeHelper.hoursBetween(time1, time2)
    if not time1 or not time2 then
        return 0
    end
    
    local hour1 = math.floor(time1 / (60 * 60 * 1000))
    local hour2 = math.floor(time2 / (60 * 60 * 1000))
    
    return math.abs(hour2 - hour1)
end

-- Time prediction
function TimeHelper.predictFutureTime(currentTime, hoursFromNow)
    return currentTime + (hoursFromNow * 60 * 60 * 1000)
end

function TimeHelper.getTimeUntil(targetTime)
    local currentTime = g_currentMission.time or 0
    if targetTime <= currentTime then
        return 0
    end
    return targetTime - currentTime
end

-- Seasonal time checks

-- Time of day checks
function TimeHelper.isMorning(hour)
    return hour >= 6 and hour < 12
end

function TimeHelper.isAfternoon(hour)
    return hour >= 12 and hour < 18
end

function TimeHelper.isEvening(hour)
    return hour >= 18 and hour < 22
end


function TimeHelper.getTimeOfDay(hour)
    if TimeHelper.isMorning(hour) then
        return "morning"
    elseif TimeHelper.isAfternoon(hour) then
        return "afternoon"
    elseif TimeHelper.isEvening(hour) then
        return "evening"
    else
        return "night"
    end
end

