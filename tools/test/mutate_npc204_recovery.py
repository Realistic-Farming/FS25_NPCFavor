#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""NPC-204 Recovery (companion contribution, slice 2): do the bars catch what they claim?

Each mutation breaks one clause of NPC-204 Implementation v1.1 (sections 3.8 and
3.9: held work, LET_GO, the contributed Resume, the waiting person and the
farm lifecycle) in shipped code and requires an NPC-204
bar to go RED with named FAIL rows. A bar that dies on a Lua error instead is
recorded CRASH, which is not a kill (a crash is unattributable). Every target is
restored in a finally and proved by sha256.

Run from tools/test:  py -u mutate_npc204_recovery.py
"""
import hashlib
import os
import re
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
FILES = {
    "cc": os.path.join(ROOT, "src", "scripts", "NPCCompanionContribution.lua"),
    "fr": os.path.join(ROOT, "src", "scripts", "NPCFavorRecovery.lua"),
}
BARS = ["NPC-204-host_core_entry_point_test.lua", "NPC-204-recovery_entry_point_test.lua"]
TICK, CROSS = "✓", "✗"

# (id, file, [(old, new, count)], the clause it breaks, the rows expected to go red)
MUTATIONS = [
    ("op-max-not-raised", "fr",
     [("NPCFavorRecovery.OP_MAX = 5\n", "NPCFavorRecovery.OP_MAX = 4\n", 1)],
     "3.8: the command event's whitelist drops OP_LET_GO", "H8"),

    ("contributed-dispatch-removed", "fr",
     [("    if NPCCompanion ~= nil and NPCCompanion.isContributed(record) then\n"
       "        local cResult, cKey = self:contributedRecoveryCommand(actor, op, record)\n",
       "    if false then\n"
       "        local cResult, cKey = self:contributedRecoveryCommand(actor, op, record)\n", 1)],
     "3.8: companion work falls through to the built-in recovery commands", "H8, U5"),

    ("letgo-allows-merely-paused", "cc",
     [("        if not self:contributedLetGoAllowed(favor) then\n"
       "            return R.RESULT_REFUSED, \"npc_recovery_refused_operation\"\n"
       "        end\n", "", 1)],
     "3.8: LET_GO closes a job the farmer could simply resume", "U2, W6"),

    ("letgo-master-exception", "cc",
     [("        if actor == nil or not NPCFarmIdentity.isOrdinaryFarmId(favor.ownerFarmId)\n"
       "            or actor.farmId == nil or actor.farmId ~= favor.ownerFarmId then\n"
       "            return R.RESULT_REFUSED, \"npc_recovery_refused_not_owner\"\n"
       "        end\n"
       "        if not contains(self.recoveryFavors, favor) or favor.status ~= PAUSED then\n"
       "            return R.RESULT_NO_LONGER_PAUSED, \"npc_recovery_no_longer_paused\"\n"
       "        end\n"
       "        if not self:contributedLetGoAllowed(favor) then\n",
       "        if (actor == nil or not NPCFarmIdentity.isOrdinaryFarmId(favor.ownerFarmId)\n"
       "            or actor.farmId == nil or actor.farmId ~= favor.ownerFarmId) and not actor.isMaster then\n"
       "            return R.RESULT_REFUSED, \"npc_recovery_refused_not_owner\"\n"
       "        end\n"
       "        if not contains(self.recoveryFavors, favor) or favor.status ~= PAUSED then\n"
       "            return R.RESULT_NO_LONGER_PAUSED, \"npc_recovery_no_longer_paused\"\n"
       "        end\n"
       "        if not self:contributedLetGoAllowed(favor) then\n", 1)],
     "3.8: a master of another farm lets the owner's held job go", "H6"),

    ("letgo-writes-history", "cc",
     [("        self:closeContributionNoFault(favor, \"let_go\")\n",
       "        self:closeContributionNoFault(favor, \"let_go\")\n        table.insert(self.abandonedFavors, favor)\n", 1)],
     "3.8: LET_GO leaves abandoned history like OP_ABANDON", "H10"),

    ("resume-stamps-legacy", "cc",
     [("        favor.expirationGameTime = nowMs() + favor.timeRemaining\n",
       "        favor.expirationGameTime = nowMs() + favor.timeRemaining\n        favor.recoveredFromLegacy = true\n", 1)],
     "3.8: the contributed Resume stamps recoveredFromLegacy like resumeRecoveryRecord", "U8, U9"),

    ("resume-ignores-hold", "cc",
     [("    if favor.contributionHeld == true then return \"npc_recovery_refused_not_resumable\" end\n", "", 1)],
     "3.8: held work resumes while its hold still applies", "H3, M2"),

    ("resume-ignores-waiting", "cc",
     [("    if self:resolveFavorPerson(favor) == nil then return \"npc_recovery_unavail_waiting\" end\n", "", 1)],
     "3.8: work resumes while its neighbour is away", "U3"),

    ("waiting-drops-pending-silently", "fr",
     [("            if favor.status == \"pending\" and NPCCompanion ~= nil and NPCCompanion.isContributed(favor) then\n"
       "                -- NPC-204 3.8: the provider sees its offer closed (token retired,\n"
       "                -- revision bumped); nothing is paid or penalised.\n"
       "                self:closeContributionNoFault(favor, \"person_waiting\")\n"
       "            elseif favor.status == \"pending\" then\n",
       "            if favor.status == \"pending\" then\n", 1)],
     "3.8: a waiting person's pending offer is dropped with its token live", "W1, W2"),

    ("farm-delete-orphans-companion", "fr",
     [("    -- NPC-204 3.9: companion work owned by or addressed to the farm closes\n"
       "    -- without fault; it is never orphaned as owner_farm_deleted.\n"
       "    if self.closeContributionsForFarm ~= nil then self:closeContributionsForFarm(farmId) end\n", "", 1)],
     "3.9: a deleted farm's companion job is orphaned instead of closed", "F2, F3"),

    ("farm-delete-before-guard", "fr",
     [("    if NPCFarmIdentity.getLiveFarm(farmId) ~= nil then return 0 end\n"
       "    -- NPC-204 3.9: companion work owned by or addressed to the farm closes\n"
       "    -- without fault; it is never orphaned as owner_farm_deleted.\n"
       "    if self.closeContributionsForFarm ~= nil then self:closeContributionsForFarm(farmId) end\n",
       "    if self.closeContributionsForFarm ~= nil then self:closeContributionsForFarm(farmId) end\n"
       "    if NPCFarmIdentity.getLiveFarm(farmId) ~= nil then return 0 end\n", 1)],
     "3.9: a stale FARM_DELETED closes a live farm's companion work", "F1, F6"),

    ("farm-created-inherits", "fr",
     [("    -- NPC-204 3.9: a reused number never inherits or receives companion work.\n"
       "    if self.closeContributionsForFarm ~= nil then self:closeContributionsForFarm(farmId) end\n", "", 1)],
     "3.9: a farm reusing the number inherits the old farm's companion job", "F5"),

    ("lifecycle-ignores-addressed-farm", "cc",
     [("        if favor.ownerFarmId == farmId or favor.contribution.addressedFarmId == farmId then\n",
       "        if favor.ownerFarmId == farmId then\n", 1)],
     "3.9: an offer addressed to a deleted farm survives it", "F2"),
]

def read_bytes(p):
    with open(p, "rb") as fh:
        return fh.read()


def run_suite():
    proc = subprocess.run([os.environ.get("NODE", "node"), "run-tests.mjs"], cwd=HERE,
                          capture_output=True, text=True, encoding="utf-8", errors="replace")
    return proc.stdout + proc.stderr


def bar_results(out):
    res = {}
    lines = out.splitlines()
    for i, line in enumerate(lines):
        for bar in BARS:
            if bar in line and (line.startswith(TICK) or line.startswith(CROSS)):
                rows, crash = [], "Lua error" in line
                j = i + 1
                while j < len(lines) and lines[j].startswith("    "):
                    if lines[j].strip().startswith("FAIL "):
                        rows.append(lines[j].strip())
                    j += 1
                res[bar] = (line[0], rows, crash)
    return res


def pattern(old):
    return "\r?\n".join(re.escape(part) for part in old.split("\n"))


def main():
    originals = {k: read_bytes(p) for k, p in FILES.items()}
    digests = {k: hashlib.sha256(b).hexdigest() for k, b in originals.items()}
    texts = {k: b.decode("utf-8") for k, b in originals.items()}
    for k, p in FILES.items():
        print("target : %-44s sha256 %s" % (os.path.relpath(p, ROOT), digests[k]))
    base = bar_results(run_suite())
    for bar in BARS:
        sym = base.get(bar, (None,))[0]
        if sym != TICK:
            print("bar not green before mutating: %s (%s)" % (bar, sym))
            return 2
    print("BASELINE both NPC-204 bars are green")
    print()

    results = []
    try:
        for mid, fkey, edits, clause, expect in MUTATIONS:
            mutated, landed = texts[fkey], True
            for old, new, want in edits:
                pat = pattern(old)
                found = len(re.findall(pat, mutated))
                if found != want:
                    print("%s: EDIT DID NOT LAND, anchor found %d, wanted %d" % (mid, found, want))
                    landed = False
                    break
                mutated = re.sub(pat, lambda _m, r=new: r, mutated, count=want)
            if not landed:
                results.append((mid, "NOT APPLIED"))
                continue
            if mutated == texts[fkey]:
                print("%s: the mutation is a no-op on the file" % mid)
                results.append((mid, "NOT APPLIED"))
                continue
            with open(FILES[fkey], "w", encoding="utf-8", newline="") as fh:
                fh.write(mutated)
            res = bar_results(run_suite())
            red = [(b, r) for b, r in res.items() if r[0] == CROSS]
            rows = [row for _, r in red for row in r[1]]
            crashed = any(r[2] for _, r in red)
            if rows:
                verdict = "KILLED"
            elif red and crashed:
                verdict = "CRASH"
            else:
                verdict = "SURVIVED"
            results.append((mid, verdict))
            print("%-8s %s\n    clause : %s\n    expect : %s" % (verdict, mid, clause, expect))
            for row in rows[:6]:
                print("    " + row)
            if len(rows) > 6:
                print("    ... and %d more" % (len(rows) - 6))
            print()
            with open(FILES[fkey], "wb") as fh:
                fh.write(originals[fkey])
    finally:
        bad = False
        for k, p in FILES.items():
            with open(p, "wb") as fh:
                fh.write(originals[k])
            ok = hashlib.sha256(read_bytes(p)).hexdigest() == digests[k]
            bad = bad or not ok
            print("restore: %-44s sha256 %s" % (os.path.relpath(p, ROOT), "MATCHES" if ok else "DOES NOT MATCH"))
        if bad:
            return 3
    after = bar_results(run_suite())
    green = all(after.get(b, (None,))[0] == TICK for b in BARS)
    print("after restore: %s\n" % ("both NPC-204 bars are green" if green else "NOT GREEN"))
    for m, v in results:
        print("  %-8s %s" % (v, m))
    killed = sum(1 for _, v in results if v == "KILLED")
    print("\n%d of %d mutations killed with named rows" % (killed, len(results)))
    return 0 if killed == len(results) and green else 1


if __name__ == "__main__":
    sys.exit(main())
