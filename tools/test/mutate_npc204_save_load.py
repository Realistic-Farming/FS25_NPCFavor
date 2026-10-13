#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""NPC-204 save and load (companion contribution, slice 3): do the bars catch what they claim?

Each mutation breaks one clause of NPC-204 Implementation v1.1 (section 3.10:
both save paths, the contribution block, the favour-number high-water, the
restore held in Recovery, person_unproven and the inert future schema) in shipped code and requires an NPC-204
bar to go RED with named FAIL rows. A bar that dies on a Lua error instead is
recorded CRASH, which is not a kill (a crash is unattributable). Every target is
restored in a finally and proved by sha256.

Run from tools/test:  py -u mutate_npc204_save_load.py
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
    "sys": os.path.join(ROOT, "src", "NPCSystem.lua"),
}
BARS = ["NPC-204-host_core_entry_point_test.lua", "NPC-204-recovery_entry_point_test.lua",
        "NPC-204-save_load_entry_point_test.lua"]
TICK, CROSS = "✓", "✗"

# (id, file, [(old, new, count)], the clause it breaks, the rows expected to go red)
MUTATIONS = [
    ("highwater-not-in-xml", "sys",
     [("        xmlFile:setInt(NPC_SAVE_ROOT .. \"#nextFavorId\", state.nextFavorId)\n", "", 1)],
     "3.10: the XML save omits the favour-number high-water", "X5, X15, X20"),

    ("highwater-not-installed", "fr",
     [("(staging.maxId or 0) + 1, staging.savedNextId or 1)\n", "(staging.maxId or 0) + 1)\n", 1)],
     "3.10: the load derives the next number from restored ids only", "X15, X20, L6"),

    ("highwater-not-in-state", "sys",
     [("        state.nextFavorId = self.favorSystem._nextFavorId\n", "", 1)],
     "3.10: the ledger state omits the favour-number high-water", "L3, L6"),

    ("pending-offer-saved", "sys",
     [("            if not (NPCCompanion ~= nil and NPCCompanion.isContributed(favor) and favor.status == \"pending\") then\n",
       "            if true then\n", 1)],
     "3.10: a companion's pending offer is saved", "X4, L4"),

    ("block-not-exported", "fr",
     [("        flat.contribution = NPCCompanion.exportBlock(favor)\n", "", 1)],
     "3.10: the contribution block is not written by either save path", "X2, L1"),

    ("block-read-after-builder", "fr",
     [("    if saved.contribution ~= nil and self.restoreContributedFavor ~= nil then\n",
       "    if false then\n", 1)],
     "3.10: the built-in builder and classifier read a companion row (unknown type, invalid record)", "X8, X14"),

    ("no-reevaluation-at-restore", "fr",
     [("        self:readCompanionSurface()\n        self:reevaluateContributedWork(nil)\n", "", 1)],
     "3.8 at restore: work stays held although its kind was declared before the load", "E2, E3"),

    ("report-flag-lost", "cc",
     [("              completed = c.reportDone, isDialogStep = false },\n",
       "              completed = false, isDialogStep = false },\n", 1)],
     "3.10: the REPORT step is rebuilt without its saved completion flag", "X12, X21"),

    ("penalty-not-saved", "cc",
     [("        penaltyRelationship = (type(favor.penalty) == \"table\" and favor.penalty.relationship) or 0,\n",
       "        penaltyRelationship = 0,\n", 1)],
     "3.10: the copied penalty is not saved", "X13"),

    ("unproven-letgo-refused", "cc",
     [("    return favor.contributionHeld == true or favor.personUnproven == true\n"
       "        or favor.recoveryReason == NPCFavorRecovery.REASON_PERSON_UNPROVEN\n",
       "    return favor.contributionHeld == true\n", 1)],
     "3.8: a reloaded job whose person cannot be proved has no LET_GO", "P5"),

    ("unproven-reason-not-set", "cc",
     [("        record.recoveryReason = NPCFavorRecovery.REASON_PERSON_UNPROVEN\n        record.resumable = false\n", "", 1)],
     "3.10: an unproven reloaded job carries no person_unproven reason", "P1"),

    ("future-schema-decoded", "cc",
     [("    if type(block) ~= \"table\" or block.schema ~= NPCCompanion.CONTRIBUTION_SCHEMA then return nil end\n",
       "    if type(block) ~= \"table\" then return nil end\n", 1)],
     "3.10: a block of an unsupported schema is decoded as live work", "F2"),

    ("inert-row-rewritten", "fr",
     [("    if favor.contributionInert == true and type(favor.inertSavedRow) == \"table\" and NPCCompanion ~= nil then\n",
       "    if false then\n", 1)],
     "3.10: an inert row is rewritten from its record, losing its saved block", "F5"),

    ("gone-farm-restored", "cc",
     [("    if not NPCFarmIdentity.isOrdinaryFarmId(saved.ownerFarmId) or not NPCFarmIdentity.isOrdinaryFarmId(c.addressedFarmId) then\n"
       "        return nil, \"withdrawn\"\n"
       "    end\n", "", 1)],
     "3.9 at load: a job whose farm is gone is restored", "G2"),
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
    print("BASELINE all three NPC-204 bars are green")
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
    print("after restore: %s\n" % ("all three NPC-204 bars are green" if green else "NOT GREEN"))
    for m, v in results:
        print("  %-8s %s" % (v, m))
    killed = sum(1 for _, v in results if v == "KILLED")
    print("\n%d of %d mutations killed with named rows" % (killed, len(results)))
    return 0 if killed == len(results) and green else 1


if __name__ == "__main__":
    sys.exit(main())
