#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""NPC-204 views and text (companion contribution, slice 4): do the bars catch what they claim?

Each mutation breaks one clause of NPC-204 Implementation v1.1 (sections 3.11
and 3.12: the work page, the dialog view, the Recovery rows and door, provider
text and reconciliation) in shipped code and requires an NPC-204
bar to go RED with named FAIL rows. A bar that dies on a Lua error instead is
recorded CRASH, which is not a kill (a crash is unattributable). Every target is
restored in a finally and proved by sha256.

Run from tools/test:  py -u mutate_npc204_views_text.py
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
    "pd": os.path.join(ROOT, "src", "scripts", "NPCPersonDialog.lua"),
    "rev": os.path.join(ROOT, "src", "events", "NPCFavorRecoveryEvents.lua"),
    "pev": os.path.join(ROOT, "src", "events", "NPCPersonDialogEvents.lua"),
    "mg": os.path.join(ROOT, "src", "gui", "NPCFavorManagementDialog.lua"),
}
BARS = ["NPC-204-host_core_entry_point_test.lua", "NPC-204-recovery_entry_point_test.lua",
        "NPC-204-save_load_entry_point_test.lua", "NPC-204-views_text_entry_point_test.lua"]
TICK, CROSS = "✓", "✗"

# (id, file, [(old, new, count)], the clause it breaks, the rows expected to go red)
MUTATIONS = [
    ("work-page-hides-addressed-offer", "pd",
     [("        if favor.recoveryToken ~= nil and (owned or NPCPersonDialog.isPublicOffer(favor, now)\n"
       "            or addressedOffer(favor, actor, now)) then\n",
       "        if favor.recoveryToken ~= nil and (owned or NPCPersonDialog.isPublicOffer(favor, now)) then\n", 1)],
     "3.11: the addressed farm's work page does not list its companion offer", "V1"),

    ("addressed-offer-any-farm", "pd",
     [("    if actor == nil or actor.farmId == nil or actor.farmId ~= favor.contribution.addressedFarmId then return false end\n",
       "    if actor == nil or actor.farmId == nil then return false end\n", 1)],
     "3.11: every farm, masters included, is offered another farm's companion job", "V4, V5, V7, V8"),

    ("accept-dark-for-addressed-farm", "pd",
     [("    local offer = NPCPersonDialog.isPublicOffer(favor, now) or addressedOffer(favor, actor, now)\n",
       "    local offer = NPCPersonDialog.isPublicOffer(favor, now)\n", 1)],
     "3.11: canAccept follows isPublicOffer, so the addressed farm cannot accept", "V2"),

    ("master-sees-companion-rows", "fr",
     [("    if (NPCCompanion ~= nil and NPCCompanion.isContributed(favor)) or favor.contributionInert == true then\n"
       "        return actor.farmId ~= nil and favor.ownerFarmId == actor.farmId\n",
       "    if not actor.isMaster and ((NPCCompanion ~= nil and NPCCompanion.isContributed(favor)) or favor.contributionInert == true) then\n"
       "        return actor.farmId ~= nil and favor.ownerFarmId == actor.farmId\n", 1)],
     "3.11: a master of another farm lists the owner's companion job", "R7"),

    ("letgo-flag-dark", "cc",
     [("    row.canLetGo = canLetGo\n", "    row.canLetGo = false\n", 1)],
     "3.11: the Recovery row never offers LET_GO", "R2, D1"),

    ("resume-flag-from-builtin-predicate", "cc",
     [("    row.knownOwnerResumable = canResume\n", "", 1)],
     "3.11: Resume lights from isRecoveryRecordActionable (always false for a companion kind)", "R11"),

    ("unknown-type-key-shown", "cc",
     [("    row.unavailableKey = canResume and \"\" or self:contributedUnavailableKey(favor)\n", "", 1)],
     "3.11: the held row shows the unknown-type key instead of its hold", "R5"),

    ("wire-drops-letgo", "rev",
     [("    streamWriteBool(streamId, row.canLetGo == true)\n", "    streamWriteBool(streamId, false)\n", 1)],
     "3.11: the view reply never carries canLetGo to the client", "D1"),

    ("door-letgo-click-dropped", "mg",
     [("            if favor.canLetGo then\n"
       "                self:confirmRecovery(self:buildCommandContext(favor, NPCFavorRecovery.OP_LET_GO))\n"
       "            elseif favor.canAbandon then\n",
       "            if favor.canAbandon then\n", 1)],
     "3.11: the door's LET_GO control sends nothing", "D5, D7"),

    ("provider-text-unproved", "cc",
     [("        local own = rawget(texts, key)\n", "        local own = texts[key]\n", 1)],
     "3.11: a key the provider inherits from the base game passes as its own", "T6"),

    ("receiver-keeps-server-text", "pev",
     [("    if row.contributed and NPCCompanion ~= nil and NPCCompanion.resolveRowText ~= nil then\n",
       "    if false then\n", 1)],
     "3.11: the receiving machine shows the server's language", "T4"),

    ("host-copy-english-only", "cc",
     [("    if ok and type(text) == \"string\" and text ~= \"\" and text ~= key and not text:find(\"^Missing\") then\n"
       "        return text\n"
       "    end\n"
       "    return fallback\n",
       "    return fallback\n", 1)],
     "3.11: the host copy never reads the shipped locale", "V3, T6, T7, T8"),

    ("provider-work-before-ready", "cc",
     [("    if not self:isFavorLoadReady() then return answer(NPCCompanion.UNAVAILABLE, \"favor_load_waiting\") end\n"
       "    self:readCompanionSurface()\n"
       "    local rows = {}\n",
       "    self:readCompanionSurface()\n"
       "    local rows = {}\n", 1)],
     "3.12: before the favour load is ready the provider reads an empty list", "W7"),
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
    print("BASELINE all four NPC-204 bars are green")
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
    print("after restore: %s\n" % ("all four NPC-204 bars are green" if green else "NOT GREEN"))
    for m, v in results:
        print("  %-8s %s" % (v, m))
    killed = sum(1 for _, v in results if v == "KILLED")
    print("\n%d of %d mutations killed with named rows" % (killed, len(results)))
    return 0 if killed == len(results) and green else 1


if __name__ == "__main__":
    sys.exit(main())
