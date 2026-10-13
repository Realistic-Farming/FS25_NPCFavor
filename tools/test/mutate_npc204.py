#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""NPC-204 host core (companion contribution): do the bars catch what they claim?

Each mutation breaks one clause of NPC-204 Implementation v1.1 (sections 3.1 to
3.7 and invariant 1, the money gate) in shipped code and requires the entry-point
bar to go RED with named FAIL rows. A bar that dies on a Lua error instead is
recorded CRASH, which is not a kill (a crash is unattributable). Every target is
restored in a finally and proved by sha256.

Run from tools/test:  py -u mutate_npc204.py
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
    "cc":   os.path.join(ROOT, "src", "scripts", "NPCCompanionContribution.lua"),
    "fs":   os.path.join(ROOT, "src", "scripts", "NPCFavorSystem.lua"),
    "pd":   os.path.join(ROOT, "src", "scripts", "NPCPersonDialog.lua"),
    "gate": os.path.join(ROOT, "src", "utils", "NPCReleaseGate.lua"),
    "ev":   os.path.join(ROOT, "src", "events", "NPCInteractionEvent.lua"),
}
BARS = ["NPC-204-host_core_entry_point_test.lua"]
TICK, CROSS = "✓", "✗"

# (id, file, [(old, new, count)], the clause it breaks, the rows expected to go red)
MUTATIONS = [
    ("reward-replay-pays-trust", "fs",
     [("    if contributed and favor.rewardPaid ~= false then\n        return\n    end\n", "", 1)],
     "invariant 1: the relationship reward is paid again on a replayed completion", "C11"),

    ("completeFavor-accepts-contributed", "fs",
     [("    if NPCCompanion ~= nil and NPCCompanion.isContributed(favor) then\n        return false\n    end\n", "", 1)],
     "3.6: another caller of completeFavor finishes and pays companion work", "C1, C3"),

    ("accept-routed-to-builtin", "ev",
     [("        contributed = NPCCompanion.isContributed((sys:_selectedWorkRecord(npc, selection)))\n",
       "        contributed = false\n", 1)],
     "3.5: a contribution record is sent to the built-in accept and complete", "A5"),

    ("addressed-offer-public", "pd",
     [("    if type(favor.contribution) == \"table\" then return false end\n", "", 1)],
     "3.5: an addressed offer reads as a public offer", "A1"),

    ("person-first-accept-takes-it", "fs",
     [("            and not (NPCCompanion ~= nil and NPCCompanion.isContributed(favor)) then\n", "            then\n", 1)],
     "3.5: acceptFavorForNPC accepts a contributed row", "A2"),

    ("roll-ignores-occupancy", "fs",
     [("    if self.isPersonHeldByContribution ~= nil and self:isPersonHeldByContribution(npc.id) then\n        return false\n    end\n", "", 1)],
     "3.4: the random roll, the trigger and npcForceFavor reach an occupied person", "G1, L8"),

    ("direct-generation-ignores-held-work", "fs",
     [("    if self.isPersonHeldByContribution ~= nil and self:isPersonHeldByContribution(npc.id) then\n        return nil\n    end\n", "", 1)],
     "3.4: generateFavorForNPC reaches a person whose job is held in Recovery", "L8"),

    ("lapse-fails-with-penalty", "fs",
     [("                self:closeContributionNoFault(favor, \"lapsed\")\n",
       "                self:failFavor(favor.id, \"time_expired\")\n", 1)],
     "3.7: an unanswered offer lapses through the penalised failure writer", "F5, F6"),

    ("gate-fails-open", "gate",
     [("    return NPCReleaseGate.isReleased(systemId, NPCReleaseGate.liveOptIn(settings) == true)\n",
       "    local optIn = NPCReleaseGate.liveOptIn(settings)\n    if optIn == nil then return true end\n    return NPCReleaseGate.isReleased(systemId, optIn)\n", 1)],
     "3.7: an unreadable opt-in opens the work surface", "O2"),

    ("lock-keeps-pending-offers", "cc",
     [("                if favor.status == \"pending\" then self:closeContributionNoFault(favor, \"surface_locked\") end\n", "", 1)],
     "3.7: pending offers survive the lock", "L1"),

    ("hold-keeps-the-clock", "cc",
     [("        favor.expirationGameTime = nil\n        favor.status = PAUSED\n",
       "        favor.status = PAUSED\n", 1)],
     "3.7: held work keeps its expiry, so the clock is not stopped", "L3"),

    ("unlock-never-returns", "cc",
     [("    if favor.contributionHeld == true then\n        return self:releaseContributedHold(favor)\n    end\n", "", 1)],
     "3.7 (v1.1): lock-held work does not return when the surface opens", "L10, L11, U9"),

    ("locked-report-advances", "cc",
     [("    if surface ~= NPCCompanion.SURFACE_OPEN then return answer(NPCCompanion.REFUSED, \"surface_locked\") end\n    if self:companionState().kinds",
       "    if self:companionState().kinds", 1)],
     "3.6: an advancing report is accepted while LOCKED", "L5"),

    ("any-farm-accepts", "cc",
     [("    if not NPCFarmIdentity.isOrdinaryFarmId(farmId) or farmId ~= favor.contribution.addressedFarmId then\n",
       "    if not NPCFarmIdentity.isOrdinaryFarmId(farmId) then\n", 1)],
     "3.5: a farm other than the addressed farm accepts the offer", "A4"),
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
    print("BASELINE the NPC-204 bar is green")
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
    print("after restore: %s\n" % ("the NPC-204 bar is green" if green else "NOT GREEN"))
    for m, v in results:
        print("  %-8s %s" % (v, m))
    killed = sum(1 for _, v in results if v == "KILLED")
    print("\n%d of %d mutations killed with named rows" % (killed, len(results)))
    return 0 if killed == len(results) and green else 1


if __name__ == "__main__":
    sys.exit(main())
