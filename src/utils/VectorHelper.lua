-- =========================================================
-- TODO / FUTURE VISION
-- =========================================================
-- MATH OPERATIONS:
-- [x] 2D and 3D distance calculations
-- [x] Scalar and vector linear interpolation (lerp)
-- [x] Value clamping (scalar and vector)
-- [ ] Dot product and cross product
-- [x] Smoothstep / ease-in-out interpolation for smoother NPC movement
-- [x] Bezier curve evaluation for curved NPC walking paths
--
-- GEOMETRY:
-- [x] Point-in-circle and point-in-rectangle tests
-- [x] Random point generation in circle and rectangle regions
-- [x] Angle calculation between two points
-- [x] Vector normalization and rotation
-- [x] Perpendicular and reflection vectors
-- [x] MoveTowards with max distance delta
-- [ ] Point-in-polygon test for irregular NPC activity zones
-- [ ] Line segment intersection for path collision detection
-- [ ] Closest point on line segment (for NPC-to-road snapping)
--
-- PERFORMANCE:
-- [ ] Squared distance variants to avoid sqrt in hot paths
-- [ ] Lookup table for sin/cos in frequently called rotation code
-- =========================================================

-- =========================================================
-- Vector Helper Utilities
-- =========================================================
-- Math utilities for vector operations
-- =========================================================

VectorHelper = VectorHelper or {}

function VectorHelper.distance2D(x1, z1, x2, z2)
    local dx = x2 - x1
    local dz = z2 - z1
    return math.sqrt(dx * dx + dz * dz)
end

function VectorHelper.distance3D(x1, y1, z1, x2, y2, z2)
    local dx = x2 - x1
    local dy = y2 - y1
    local dz = z2 - z1
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function VectorHelper.angleBetween(x1, z1, x2, z2)
    return math.atan2(z2 - z1, x2 - x1)
end

function VectorHelper.normalize(x, z)
    local length = math.sqrt(x * x + z * z)
    if length > 0 then
        return x / length, z / length
    end
    return 0, 0
end


function VectorHelper.lerp(start, finish, t)
    return start + (finish - start) * t
end


function VectorHelper.clamp(value, min, max)
    return math.max(min, math.min(max, value))
end


function VectorHelper.getPerpendicular(x, z)
    return -z, x
end


--- Evaluate a quadratic Bezier curve at parameter t.
-- @param p0x,p0z  Start point
-- @param p1x,p1z  Control point
-- @param p2x,p2z  End point
-- @param t        Parameter in [0,1]
-- @return number, number  Point on the curve
function VectorHelper.bezierQuadratic(p0x, p0z, p1x, p1z, p2x, p2z, t)
    local u = 1 - t
    local x = u * u * p0x + 2 * u * t * p1x + t * t * p2x
    local z = u * u * p0z + 2 * u * t * p1z + t * t * p2z
    return x, z
end

--- Smooth a list of waypoints by replacing sharp corners with Bezier curves.
-- @param waypoints  Array of {x, z} tables
-- @param segments   Number of curve segments per corner (default 4)
-- @return table  New array of smoothed {x, z} waypoints
function VectorHelper.smoothPath(waypoints, segments)
    if not waypoints or #waypoints < 3 then return waypoints end
    segments = segments or 4

    local smoothed = {{x = waypoints[1].x, z = waypoints[1].z}}

    for i = 2, #waypoints - 1 do
        local prev = waypoints[i - 1]
        local curr = waypoints[i]
        local next = waypoints[i + 1]

        -- Control point is the corner itself; start/end are midpoints
        local startX = (prev.x + curr.x) / 2
        local startZ = (prev.z + curr.z) / 2
        local endX = (curr.x + next.x) / 2
        local endZ = (curr.z + next.z) / 2

        for s = 0, segments do
            local t = s / segments
            local bx, bz = VectorHelper.bezierQuadratic(startX, startZ, curr.x, curr.z, endX, endZ, t)
            table.insert(smoothed, {x = bx, z = bz})
        end
    end

    table.insert(smoothed, {x = waypoints[#waypoints].x, z = waypoints[#waypoints].z})
    return smoothed
end

