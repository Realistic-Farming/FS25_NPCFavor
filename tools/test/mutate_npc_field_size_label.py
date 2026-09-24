# PLAYER-REPORTS row 93 mutation battery: the field size read and extent (src/NPCSystem.lua), the
# clipped work square, the row clipping and the spot-check filter (src/scripts/NPCFieldWork.lua),
# the legacy half-size clamp and the field-work label exemption (src/scripts/NPCAI.lua). Rows live
# in RSF-NPC-field_size_and_label_spec_test.lua; the other bars run with it.
#
# Each mutation removes one clause and must be KILLED by a named row. For each: assert the edit
# LANDED (exact occurrence count), run the suite, record KILLED/SURVIVED with the named rows,
# restore byte-for-byte and PROVE the restore with a hash. "DID NOT APPLY" never counts as a kill.
# KILLED* means killed only by a Lua error: a weak kill, treated as a failure.
#
# Not run, and why:
# - the three removed dead reads of `field.fieldArea.fieldCenterX` in the farmland sweeps
#   (NPCSystem.lua, the placeable and eviction walks): they were dead on every engine field and
#   the posX branch behind them answered; restoring one changes nothing observable on an engine
#   field, and the selector's own dead read is pinned by A9.
# - the ray-casting arithmetic inside pointInPolygon beyond the shapes C6 and C7 drive: read,
#   not mutated.
#
# Anchors are written with "\n"; in a CRLF file they are matched as "\r\n".
#
# Usage (from the repo root): py tools/test/mutate_npc_field_size_label.py [id-prefix ...]
import hashlib, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
def p(rel): return os.path.join(ROOT, rel)

SYS = "src/NPCSystem.lua"
FW = "src/scripts/NPCFieldWork.lua"
AI = "src/scripts/NPCAI.lua"

MUTATIONS = [
 # ── the record ──────────────────────────────────────────────────────────────
 ("S1-size-is-one-again", SYS,
  [("                        size = NPCSystem.fieldAreaSqm(field),", "                        size = 1,", 1)],
  "every field is one square metre again: the figure of 8"),
 ("S2-hectares-not-scaled", SYS,
  [("    return ha * 10000\n", "    return ha\n", 1)],
  "the record carries hectares where square metres are expected"),
 ("S3-zero-area-accepted", SYS,
  [("    if type(ha) ~= \"number\" or ha ~= ha or ha == math.huge or ha <= 0 then return nil end",
    "    if type(ha) ~= \"number\" or ha ~= ha or ha == math.huge then return nil end", 1)],
  "an area of zero hectares becomes size zero instead of no size"),
 ("S4-nan-area-accepted", SYS,
  [("    if type(ha) ~= \"number\" or ha ~= ha or ha == math.huge or ha <= 0 then return nil end",
    "    if type(ha) ~= \"number\" or ha == math.huge or ha <= 0 then return nil end", 1)],
  "a NaN area passes the guard"),
 ("S5-member-not-read", SYS,
  [("    if ha == nil then ha = field.areaHa end\n", "", 1)],
  "a field without the getter carries no size even with the member"),
 ("S6-extent-not-built", SYS,
  [("                        extent = NPCSystem.fieldExtent(field),", "                        extent = nil,", 1)],
  "the record carries no extent: the work square spills off a narrow field"),
 ("S7-extent-needs-no-points", SYS,
  [("    if #polygon < 3 then return nil end\n    return { minX = minX", "    if #polygon < 0 then return nil end\n    return { minX = minX", 1)],
  "a field with no placeable points gets an extent of nils"),
 ("S8-dead-read-restored", SYS,
  [("        if field.posX and field.posZ then\n            cx = field.posX\n            cz = field.posZ\n        elseif field.rootNode then\n            local ok, fx, _, fz = pcall(getWorldTranslation, field.rootNode)\n            if ok and fx then\n                cx = fx\n                cz = fz\n            end\n        end\n\n        -- A missing centre is a REJECTION",
    "        if field.fieldArea and field.fieldArea.fieldCenterX then\n            cx = field.fieldArea.fieldCenterX\n            cz = field.fieldArea.fieldCenterZ\n        elseif field.posX and field.posZ then\n            cx = field.posX\n            cz = field.posZ\n        elseif field.rootNode then\n            local ok, fx, _, fz = pcall(getWorldTranslation, field.rootNode)\n            if ok and fx then\n                cx = fx\n                cz = fz\n            end\n        end\n\n        -- A missing centre is a REJECTION", 1)],
  "the selector reads the table no engine field carries, first"),
 # ── the work square ─────────────────────────────────────────────────────────
 ("B1-square-not-clipped", FW,
  [("        minX, maxX = math.max(minX, extent.minX), math.min(maxX, extent.maxX)\n        minZ, maxZ = math.max(minZ, extent.minZ), math.min(maxZ, extent.maxZ)\n", "", 1)],
  "the work square ignores the field's extent"),
 ("B2-polygon-not-carried", FW,
  [("        polygon = extent.polygon\n", "", 1)],
  "the bounds carry no polygon: rows cross an L-shaped field's notch"),
 ("B3-rows-not-clipped", FW,
  [("        if polygon ~= nil then\n            segments = NPCFieldWork.clipRowToPolygon(rowZ, workMinX, workMaxX, polygon, math.max(1, spacing * 0.5))\n        end\n", "", 1)],
  "rows span the work area whatever the polygon says"),
 ("B4-inside-means-always", FW,
  [("    if type(polygon) ~= \"table\" or #polygon < 3 then return true end\n    local inside = false", "    if type(polygon) ~= \"table\" or #polygon < 3 then return true end\n    local inside = true", 1)],
  "point in polygon answers the opposite parity: the notch is inside and the field outside"),
 ("B6-ends-only-shortcut", FW,
  [("    step = math.max(0.5, step or 1)\n    local eps = 0.01\n    local segments = {}",
    "    step = math.max(0.5, step or 1)\n    local eps = 0.01\n    if NPCFieldWork.pointInPolygon(lo + eps, rowZ, polygon) and NPCFieldWork.pointInPolygon(hi - eps, rowZ, polygon) then return { { lo, hi } } end\n    local segments = {}", 1)],
  "a row whose two ends are inside is not sampled: it crosses a U's gap"),
 ("B7-stretches-merged", FW,
  [("        elseif segStart ~= nil then\n            segments[#segments + 1] = { segStart, segEnd }\n            segStart, segEnd = nil, nil\n        end",
    "        end", 1)],
  "the inside stretches of a row are merged first-to-last across the gap"),
 ("B8-spotcheck-falls-to-box-centre", FW,
  [("        if px == nil then px, pz = bounds.labelX or bounds.centerX, bounds.labelZ or bounds.centerZ end",
    "        if px == nil then px, pz = bounds.centerX, bounds.centerZ end", 1)],
  "a draw that cannot land inside falls to the box centre, in a U's gap"),
 ("B5-spotcheck-not-filtered", FW,
  [("            if polygon == nil or NPCFieldWork.pointInPolygon(x, z, polygon) then px, pz = x, z break end",
    "            px, pz = x, z break", 1)],
  "spot-check points land in the notch"),
 # ── the legacy clamp ────────────────────────────────────────────────────────
 ("L1-legacy-not-clamped", AI,
  [("    local halfSize = math.max(15, math.min(100, fieldSize * 0.4))", "    local halfSize = fieldSize * 0.4", 1)],
  "the legacy patterns reach 219 m at 30 ha"),
 ("L2-legacy-ignores-extent", AI,
  [("        if room > 0 then halfSize = math.min(halfSize, room) end\n", "", 1)],
  "the legacy patterns leave a narrow field"),
 # ── the label ───────────────────────────────────────────────────────────────
 ("A1-label-not-exempt", AI,
  [("    local onFieldWork = npc.activeAIJob ~= nil or npc.usingComboFieldWork == true or npc._fieldWorkFieldId ~= nil\n    if not onFieldWork\n       and npc.aiState ~= self.STATES.GATHERING",
    "    if npc.aiState ~= self.STATES.GATHERING", 1)],
  "the schedule overwrites the field-work label every tick"),
 ("A2-exempt-by-state-not-flags", AI,
  [("    local onFieldWork = npc.activeAIJob ~= nil or npc.usingComboFieldWork == true or npc._fieldWorkFieldId ~= nil",
    "    local onFieldWork = npc.aiState == self.STATES.WORKING or npc.aiState == self.STATES.DRIVING", 1)],
  "the exemption tests aiState: the AI job (which sets none) is overwritten and every ordinary worker is exempt"),
 ("A3-combo-flag-ignored", AI,
  [("    local onFieldWork = npc.activeAIJob ~= nil or npc.usingComboFieldWork == true or npc._fieldWorkFieldId ~= nil",
    "    local onFieldWork = npc.activeAIJob ~= nil or npc._fieldWorkFieldId ~= nil", 1)],
  "the combo fallback's label is overwritten"),
 ("A4-slot-flag-ignored", AI,
  [("    local onFieldWork = npc.activeAIJob ~= nil or npc.usingComboFieldWork == true or npc._fieldWorkFieldId ~= nil",
    "    local onFieldWork = npc.activeAIJob ~= nil or npc.usingComboFieldWork == true", 1)],
  "a pattern slot's label is overwritten"),
]

def sha(b): return hashlib.sha256(b).hexdigest()


def run_suite():
    r = subprocess.run(["node", "run-tests.mjs"], cwd=os.path.join(ROOT, "tools", "test"),
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    out = r.stdout + r.stderr
    strip = lambda l: (re.sub(r"\x1b\[[0-9;]*m", "", l).strip()
                       .encode("ascii", "replace").decode("ascii"))
    fails = [strip(l) for l in out.splitlines() if "FAIL" in l and "assertions passed" not in l]
    crashes = [strip(l) for l in out.splitlines() if "Lua error while loading/running" in l]
    return r.returncode, fails, crashes


only = sys.argv[1:]
rc, fails, crashes = run_suite()
if rc != 0:
    print("BASELINE IS NOT GREEN; fix that before trusting any mutation result.")
    for l in fails[:10]:
        print("   " + l)
    sys.exit(2)
print("baseline green")

killed, crashkills, survived, badedit = [], [], [], []

for mid, rel, edits, why in MUTATIONS:
    if only and not any(mid.startswith(o) for o in only):
        continue
    path = p(rel)
    with open(path, "rb") as f:
        original = f.read()
    crlf = b"\r\n" in original
    enc = lambda s: (s.replace("\n", "\r\n") if crlf else s).encode("utf-8")

    ok, mutated = True, original
    for old, new, want in edits:
        ob, nb = enc(old), enc(new)
        n = mutated.count(ob)
        if n != want:
            badedit.append((mid, "anchor matched %dx, expected %d" % (n, want)))
            print("  !! %s: ANCHOR MISMATCH (%d != %d), mutation NOT applied" % (mid, n, want))
            ok = False
            break
        mutated = mutated.replace(ob, nb, want)
    if not ok:
        continue

    with open(path, "wb") as f:
        f.write(mutated)
    with open(path, "rb") as f:
        landed = f.read()
    if landed == original or landed != mutated:
        with open(path, "wb") as f:
            f.write(original)
        badedit.append((mid, "edit did not land"))
        print("  !! %s: EDIT DID NOT LAND" % mid)
        continue

    try:
        rc, fails, crashes = run_suite()
    finally:
        with open(path, "wb") as f:
            f.write(original)
    with open(path, "rb") as f:
        if sha(f.read()) != sha(original):
            print("  !! %s: RESTORE FAILED, stopping" % mid)
            sys.exit(3)

    named = [l for l in fails if l.startswith("FAIL ")]
    if rc != 0:
        killed.append(mid)
        tag = "KILLED  "
        if crashes and not named:
            crashkills.append(mid)
            tag = "KILLED* "
    else:
        survived.append((mid, why))
        tag = "SURVIVED"
    print("  %s %s  [%s]" % (tag, mid, rel))
    print("        (%s)" % why)
    for l in named[:4]:
        print("        " + l[:170])
    for l in crashes[:2]:
        print("        CRASH " + l[:170])

print("\n==== MUTATION RESULT ====")
print("killed   %d (of which %d only by a Lua error, marked KILLED*)" % (len(killed), len(crashkills)))
print("survived %d" % len(survived))
print("bad edit %d" % len(badedit))
for mid, why in survived:
    print("--- SURVIVED %s: %s" % (mid, why))
for mid, msg in badedit:
    print("--- BAD EDIT %s: %s" % (mid, msg))
print("all files restored byte-identical (hash-checked per mutation)")
sys.exit(1 if (survived or badedit or crashkills) else 0)
