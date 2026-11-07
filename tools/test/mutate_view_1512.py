# Favor detail View mutation battery (JamesW report 2026-11-05, RF-1512).
#
# Every claim the V rows in RSF-F357-actions_views_spec_test.lua make about the
# repaired View button gets a mutation that must break it. The battery edits
# src/gui/NPCFavorManagementDialog.lua and translations/lang_en.xml in place and
# restores both byte-identically, hash-checked, after each run.
#
# KILLED* means killed only by a Lua error: a weak kill, treated as a failure,
# because an assertion should have named the defect rather than the interpreter.
#
# M01 is the ORIGINAL DEFECT put back: if it ever survives, the bar has stopped
# testing the thing JamesW reported.
#
# RUN IT ALONE. A battery edits production files in place.
#
# Usage: py tools/test/mutate_view_1512.py [id-prefix ...]
import hashlib, os, subprocess, sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
def p(rel): return os.path.join(ROOT, rel)

MGD = "src/gui/NPCFavorManagementDialog.lua"
EN = "translations/lang_en.xml"

MUTATIONS = [
 # ── the reported defect itself ──────────────────────────────────────────────
 ("M01-log-only-again", MGD,
  [("""    NPCFavorManagementDialog["onClickFavor" .. i .. "View"] = function(self)
        self:showFavorDetails(i)
    end
""",
    """    NPCFavorManagementDialog["onClickFavor" .. i .. "View"] = function(self)
        local favor = self.favorIndices[i]
        if favor == nil then return end
        print("[NPC Favor] " .. self:buildFavorDetailLines(favor, self.npcSystem))
    end
""", 1)],
  "the detail goes back to the log and nothing reaches the screen"),
 ("M02-open-nothing-silently", MGD,
  [("    InfoDialog.show(text, nil, nil, nil, getModText(\"npc_mgmt_view_ok\", \"Close\"))\n", "", 1)],
  "the handler computes the detail and shows no dialog"),

 # ── the guard on a missing dialog ───────────────────────────────────────────
 ("M03-instance-unchecked", MGD,
  [("    if InfoDialog == nil or type(InfoDialog.show) ~= \"function\" or InfoDialog.INSTANCE == nil then\n",
    "    if InfoDialog == nil or type(InfoDialog.show) ~= \"function\" then\n", 1)],
  "a registered-but-uninstanced InfoDialog is called anyway"),
 ("M04-absent-row-shows-dialog", MGD,
  [("""    local favor = self.favorIndices ~= nil and self.favorIndices[rowNum] or nil
    local sys = self.npcSystem
    if favor == nil or sys == nil then
""",
    """    local favor = self.favorIndices ~= nil and self.favorIndices[rowNum] or nil
    local sys = self.npcSystem
    if false then
""", 1)],
  "a row that is no longer on the page is rendered as current detail"),

 # ── destination guidance ────────────────────────────────────────────────────
 ("M05-fabricate-step-location", MGD,
  [("    if favor.status ~= \"pending\" and favor.nextStepLocationPresent == true\n"
    "        and type(favor.nextStepX) == \"number\" and type(favor.nextStepZ) == \"number\" then\n",
    "    if favor.status ~= \"pending\" then\n", 1)],
  "a step with no recorded location still produces coordinates"),
 ("M06-ignore-player-position", MGD,
  [("    if type(px) ~= \"number\" or type(pz) ~= \"number\" then\n"
    "        return getModText(\"npc_mgmt_view_dest_unknown\", \"location recorded, your own position is not\")\n"
    "    end\n",
    "    if type(px) ~= \"number\" or type(pz) ~= \"number\" then px, pz = 0, 0 end\n", 1)],
  "an unknown player position is treated as the map origin, so the distance is invented"),
 ("M07-distance-off-by-axis", MGD,
  [("    local dx, dz = tx - px, tz - pz\n    return string.format(\"%dm\", math.floor(math.sqrt(dx * dx + dz * dz)))\n",
    "    local dx, dz = tx - px, tz - pz\n    return string.format(\"%dm\", math.floor(math.sqrt(dx * dx)))\n", 1)],
  "the distance ignores the Z axis"),

 # ── the objective line ──────────────────────────────────────────────────────
 ("M08-objective-drops-next-step", MGD,
  [("    elseif type(favor.nextStepText) == \"string\" and favor.nextStepText ~= \"\" then\n        text = favor.nextStepText\n",
    "    elseif false then\n        text = favor.nextStepText\n", 1)],
  "the objective falls back to the job title and never shows the current step"),
 ("M09-pending-reads-as-work", MGD,
  [("    if favor.status == \"pending\" then\n"
    "        text = string.format(getModText(\"npc_mgmt_view_step_accept\", \"talk to %s to accept this offer\"), npcName)\n",
    "    if false then\n"
    "        text = string.format(getModText(\"npc_mgmt_view_step_accept\", \"talk to %s to accept this offer\"), npcName)\n", 1)],
  "an unaccepted offer is described as work in progress"),
 ("M10-awaiting-silent", MGD,
  [("    if favor.awaitingConfirmation == true then\n", "    if false then\n", 1)],
  "work waiting on the neighbour looks like work the player still has to do"),
 ("M11-repay-amount-dropped", MGD,
  [("    elseif favor.isLoanRepayStep == true and favor.loanAmountPresent == true then\n",
    "    elseif false then\n", 1)],
  "a repayment step does not name the amount"),

 # ── the numbers ─────────────────────────────────────────────────────────────
 ("M12-time-from-absent-field", MGD,
  [("    if favor.timeKnown == true and type(favor.timeRemainingMs) == \"number\" then\n"
    "        return string.format(getModText(\"npc_mgmt_time_left\", \"%s left\"), formatMs(favor.timeRemainingMs))\n"
    "    end\n",
    "", 1)],
  "the time text goes back to reading the expirationGameTime a work row does not have"),
 ("M13-urgency-permanently-calm", MGD,
  [("    if favor.timeKnown == true and type(favor.timeRemainingMs) == \"number\" then\n"
    "        local hours = favor.timeRemainingMs / 3600000\n",
    "    if false then\n"
    "        local hours = favor.timeRemainingMs / 3600000\n", 1)],
  "the row's time colour never becomes urgent"),
 ("M14-urgency-unit-slip", MGD,
  [("        local hours = favor.timeRemainingMs / 3600000\n",
    "        local hours = favor.timeRemainingMs / 60000\n", 1)],
  "minutes are read where hours belong, so nothing is ever urgent"),
 ("M15-progress-scaled-wrong", MGD,
  [("    lines[#lines + 1] = string.format(getModText(\"npc_mgmt_view_progress\", \"Progress: %d%% done\"),\n"
    "        math.floor(tonumber(favor.progress) or 0))\n",
    "    lines[#lines + 1] = string.format(getModText(\"npc_mgmt_view_progress\", \"Progress: %d%% done\"),\n"
    "        math.floor((tonumber(favor.progress) or 0) / 100))\n", 1)],
  "progress is divided again and always reads zero"),
 ("M16-reward-ignores-wire-field", MGD,
  [("    elseif type(favor.rewardMoney) == \"number\" then\n        reward = favor.rewardMoney\n", "", 1)],
  "a row carrying only rewardMoney reports no reward"),

 # ── the lines that could only ever read nil ────────────────────────────────
 ("M17-owner-line-restored", MGD,
  [("    lines[#lines + 1] = string.format(getModText(\"npc_mgmt_view_reward\", \"Reward: $%d\"), reward)\n",
    "    lines[#lines + 1] = string.format(getModText(\"npc_mgmt_view_reward\", \"Reward: $%d\"), reward)\n"
    "    lines[#lines + 1] = \"Owner: \" .. tostring(favor.ownerFarmId)\n", 1)],
  "the Owner line is back, reading a field a work row does not carry"),
 ("M18-stale-page-silent", MGD,
  [("    if self.mode ~= \"recovery\" and self.workView ~= nil and self.workView.state ~= \"CURRENT\" then\n",
    "    if false then\n", 1)],
  "a last-confirmed page is presented as if it were current"),
 ("M19-current-page-claims-stale", MGD,
  [("    if self.mode ~= \"recovery\" and self.workView ~= nil and self.workView.state ~= \"CURRENT\" then\n",
    "    if self.mode ~= \"recovery\" and self.workView ~= nil then\n", 1)],
  "a current page is labelled last-confirmed"),

 # ── the shipped locale ──────────────────────────────────────────────────────
 ("M20-key-missing-from-english", EN,
  [("\t\t<text name=\"npc_mgmt_view_destination\" text=\"Where: %s\" />\n", "", 1)],
  "a key the source resolves is absent from the shipped English file"),
 ("M21-format-signature-diverges", EN,
  [("\t\t<text name=\"npc_mgmt_view_reward\" text=\"Reward: $%d\" />\n",
    "\t\t<text name=\"npc_mgmt_view_reward\" text=\"Reward: $%s\" />\n", 1)],
  "the shipped text takes a different format argument from the code fallback"),
]


def sha(b): return hashlib.sha256(b).hexdigest()


def run_suite():
    r = subprocess.run(["node", "run-tests.mjs"], cwd=p("tools/test"),
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    out = (r.stdout or "") + (r.stderr or "")
    fails = [l.strip() for l in out.splitlines()
             if "FAIL " in l and "##" not in l and l.strip().startswith("FAIL")]
    crashes = [l.strip() for l in out.splitlines() if "Lua error" in l or "attempt to" in l]
    return r.returncode, fails, crashes


only = sys.argv[1:]
rc, fails, crashes = run_suite()
if rc != 0:
    print("BASELINE IS NOT GREEN; fix that before trusting any mutation result.")
    for l in fails[:10]: print("   " + l)
    for l in crashes[:5]: print("   " + l)
    sys.exit(2)
print("baseline green")

killed, survived, bad, weak = 0, 0, 0, 0
for mid, rel, edits, why in MUTATIONS:
    if only and not any(mid.startswith(o) for o in only): continue
    path = p(rel)
    original = open(path, "rb").read()
    before = sha(original)
    crlf = b"\r\n" in original
    text = original.decode("utf-8").replace("\r\n", "\n")
    ok = True
    for old, new, count in edits:
        if text.count(old) != count:
            print("  BAD EDIT %s: anchor found %d times, want %d" % (mid, text.count(old), count))
            ok = False
            break
        text = text.replace(old, new)
    if not ok:
        bad += 1
        continue
    open(path, "wb").write((text.replace("\n", "\r\n") if crlf else text).encode("utf-8"))
    try:
        rc, fails, crashes = run_suite()
    finally:
        open(path, "wb").write(original)
        assert sha(open(path, "rb").read()) == before, "restore failed for " + rel
    if rc != 0:
        killed += 1
        star = "*" if (len(fails) == 0 and len(crashes) > 0) else " "
        if star == "*": weak += 1
        print("  KILLED%s  %s  [%s]" % (star, mid, rel))
        for l in fails[:3]: print("        " + l)
        for l in crashes[:2]: print("        " + l)
    else:
        survived += 1
        print("  SURVIVED %s  [%s]  (%s)" % (mid, rel, why))

print("\n==== MUTATION RESULT ====")
print("killed   %d (of which %d only by a Lua error, marked KILLED*)" % (killed, weak))
print("survived %d" % survived)
print("bad edit %d" % bad)
print("all files restored byte-identical (hash-checked per mutation)")
sys.exit(0 if survived == 0 and bad == 0 and weak == 0 else 1)
