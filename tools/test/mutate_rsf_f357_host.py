# RSF-F357 host core mutation battery: the person roster (src/scripts/NPCPersonRoster.lua), the
# selected load, the live selection, the serializers and the transports in src/NPCSystem.lua,
# src/events/NPCStateSyncEvent.lua and src/integrations/*, the favour proof in
# src/scripts/NPCFavorRecovery.lua and NPCFavorSystem.lua, the field-work keys in NPCFieldWork.lua
# and NPCAI.lua, and the worker presences in ContractorModBridge.lua. Rows live in
# RSF-F357-host_core_spec_test.lua; the four preserved contract tests run with it.
#
# KILLED* means killed only by a Lua error: a weak kill, treated as a failure.
#
# NOT RUN, and why:
#   - the farm-mate distance and the fail-open in NPCInteractionEvent.execute, the accept cooldown
#     (NPCSystem.lua serverAcceptFavor), the SCS floor and its rel > 0 gate: PR 2 and PR 3 of this
#     brief (the intake's build shape), not this PR's code.
#   - the personKind line in isPersonActionable: redundant on both sides (a presence is never in
#     byId on the server and is never LIVE in clientById on the client), so removing it changes
#     nothing observable; declared equivalent rather than pretending a row pins it.
#   - the extra MAX_PAGES check in receivePage: pageCountFor(total) with total bounded to 4096 can
#     never exceed 82, so the check is belt and braces; the total bound is mutated instead (S39).
#   - the five isPersonActionable guards at the top of the server commands (NPCSystem.lua
#     serverAcceptFavor to serverUpdateRelationship): every one is masked by the deeper owner's
#     own guard (the favour system's resolveFavorPerson, the relationship manager's
#     isPersonActionable), which S13, P5 and P7 pin. They stay as defence in depth; removing
#     them changes nothing observable, so the mutation was declared equivalent, not run.
#   - the person-state gate in _doSaveToXMLFile: whenever the person load is not READY the favour
#     load is not READY either (_failSelectedLoad, and a late ledger holds both), so the F148
#     favour gate right below it skips the same save; G8 and Q12 pin the outcome. Declared
#     equivalent, kept for the explicit log line.
#
# Anchors are written with "\n"; in a CRLF file they are matched after normalising.
#
# RUN IT ALONE, THROUGH THE TEST LOCK. A battery edits production files in place.
#
# Usage: py tools/test/mutate_rsf_f357_host.py [id-prefix ...]
import hashlib, os, subprocess, sys

# The runner's own output carries non-ASCII marks; a cp1252 console must not stop a battery.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
def p(rel): return os.path.join(ROOT, rel)

SYS = "src/NPCSystem.lua"
ROS = "src/scripts/NPCPersonRoster.lua"
REC = "src/scripts/NPCFavorRecovery.lua"
FAV = "src/scripts/NPCFavorSystem.lua"
FLD = "src/scripts/NPCFieldWork.lua"
AI  = "src/scripts/NPCAI.lua"
CTR = "src/scripts/ContractorModBridge.lua"
EVT = "src/events/NPCStateSyncEvent.lua"
NET = "src/integrations/NPCNetworkSyncBridge.lua"
LED = "src/integrations/NPCStateLedgerBridge.lua"

MUTATIONS = [
 # ── identity: the allocator, never the array ────────────────────────────────
 ("S01-array-length-as-id", SYS,
  [("        id = id,\n        name = name,\n", "        id = #self.activeNPCs + 1,\n        name = name,\n", 1)],
  "a newcomer's number is the array length: it collides with a waiting person's"),
 ("S02-increment-before-bound-check", ROS,
  [("    if self.highWater >= NPCPersonRoster.MAX_ID then\n"
    "        if not self.exhausted then\n"
    "            self.exhausted = true\n"
    "            print(\"[NPC Favor] Person identity numbers are exhausted; no new neighbour can be created\")\n"
    "        end\n"
    "        return nil, NPCPersonRoster.REASON_EXHAUSTED\n"
    "    end\n"
    "    self.highWater = self.highWater + 1\n"
    "    return self.highWater\n",
    "    self.highWater = self.highWater + 1\n"
    "    if self.highWater > NPCPersonRoster.MAX_ID then\n"
    "        self.exhausted = true\n"
    "        return nil, NPCPersonRoster.REASON_EXHAUSTED\n"
    "    end\n"
    "    return self.highWater\n", 1)],
  "exhaustion is checked after the increment: the mark overflows the Int32 field"),
 ("S03-duplicate-number-first-row-wins", ROS,
  [("            if NPCPersonRoster.validId(id) and not reservation.duplicate[id] then\n",
    "            if NPCPersonRoster.validId(id) then\n", 1)],
  "two saved rows with one number both keep it: a favour attaches to whichever loads last"),
 ("S04-favour-references-not-reserved", ROS,
  [("    for _, id in ipairs(selected.favourRefIds or {}) do add(id) end\n", "", 1)],
  "a minted number can equal a saved favour's reference: the favour attaches to a stranger"),
 ("S05-unknown-person-schema-applied", ROS,
  [("    if schema ~= nil and schema ~= NPCPersonRoster.SCHEMA then\n", "    if false then\n", 1)],
  "a future person schema is read as today's rows"),
 ("S06-throw-escapes-the-load", SYS,
  [("    local ok, err = pcall(function()\n"
    "        local selected = self:normalizeSavedState(block)\n"
    "        local applied, why = people:applySelected(selected)\n"
    "        if not applied then\n"
    "            error(tostring(why))\n"
    "        end\n"
    "        self:initializeNPCs()\n"
    "        people:markReady()\n"
    "    end)\n",
    "    local ok, err = true, nil\n"
    "    do\n"
    "        local selected = self:normalizeSavedState(block)\n"
    "        local applied, why = people:applySelected(selected)\n"
    "        if not applied then\n"
    "            error(tostring(why))\n"
    "        end\n"
    "        self:initializeNPCs()\n"
    "        people:markReady()\n"
    "    end\n", 1)],
  "an unsafe row throws out of the init pass instead of FAILED with the original preserved"),
 # ── the selected load ───────────────────────────────────────────────────────
 ("S07-late-ledger-falls-to-xml", SYS,
  [("        if NPCStateLedgerBridge.delivered ~= true then\n"
    "            self.people:noteWaitingOnLedger()\n"
    "            print(\"[NPC Favor] Person load WAITING: StateLedger is registered but has not delivered a block yet\")\n"
    "            return false\n"
    "        end\n", "", 1)],
  "a registered ledger that has not delivered lets XML own the load"),
 ("S08-late-delivery-stored-forever", LED,
  [("    sys:runPersonLoad(missionInfo)\n", "", 1)],
  "a late deserialize stores the block and never schedules the apply"),
 ("S09-repeated-load-reapplies", SYS,
  [("    if not self.people:isWaiting() then return false end\n", "", 1),
   ("    if people == nil or not people:isWaiting() then return people ~= nil and people:isReady() end\n",
    "    if people == nil then return false end\n", 1)],
  "a second entry point or a repeated delivery runs the selection again after READY (both guards)"),
 ("S10-client-selects-and-fills", SYS,
  [("                if self.isServer then\n"
    "                    self:runPersonLoad(missionInfo)\n"
    "                else\n"
    "                    self:bootstrapClient()\n"
    "                end\n",
    "                self:runPersonLoad(missionInfo)\n", 1),
   ("    if not self.isServer or self.people == nil then return false end\n"
    "    if not self.people:isWaiting() then return false end\n",
    "    if self.people == nil then return false end\n"
    "    if not self.people:isWaiting() then return false end\n", 1),
   ("    if not self.isServer then\n"
    "        return\n"
    "    end\n"
    "\n"
    "    -- Classify all world buildings before placing anyone\n",
    "    -- Classify all world buildings before placing anyone\n", 1)],
  "a pure client selects a source, mints numbers and fills a local town"),
 # ── the live selection ──────────────────────────────────────────────────────
 ("S11-waiting-by-descending-number", SYS,
  [("    table.sort(candidates, function(a, b) return a.id < b.id end)\n",
    "    table.sort(candidates, function(a, b) return a.id > b.id end)\n", 1)],
  "the count keeps the newest people and parks the oldest"),
 ("S12-waiting-person-stays-in-live-view", SYS,
  [("            for i, npc in ipairs(self.activeNPCs) do\n"
    "                if npc == person then\n"
    "                    table.remove(self.activeNPCs, i)\n"
    "                    self.npcCount = self.npcCount - 1\n"
    "                    break\n"
    "                end\n"
    "            end\n", "", 1)],
  "a person going waiting keeps her place in activeNPCs"),
 ("S13-waiting-person-not-actionable-ignored", SYS,
  [("    if not npc.live or npc.isActive == false then return false end\n",
    "    if npc.isActive == false then return false end\n", 1)],
  "a waiting person is actionable"),
 ("S14-waiting-does-not-pause-work", SYS,
  [("            if self.favorSystem ~= nil and self.favorSystem.pauseWorkForPerson ~= nil then\n"
    "                pcall(self.favorSystem.pauseWorkForPerson, self.favorSystem, person.id)\n"
    "            end\n", "", 1)],
  "accepted work of a person going waiting keeps running against nobody"),
 ("S15-house-not-resolved", SYS,
  [("    if person.homeUniqueId ~= nil and self.classifiedBuildings ~= nil then\n", "    if false then\n", 1)],
  "a saved house is never matched: everyone is re-placed on every load"),
 ("S16-name-pool-ignores-retained", SYS,
  [("            if not (self.people ~= nil and self.people:isNameRetained(name)) then\n"
    "                return name\n"
    "            end\n",
    "            return name\n", 1)],
  "a newcomer takes a saved person's name: a namesake"),
 ("S17-consultant-wakes-without-claim", SYS,
  [("            if not person.live then\n"
    "                self:setPersonLive(person, false, NPCPersonRoster.REASON_WAITING_COMPANION)\n"
    "            else\n"
    "                self:setPersonLive(person, true)\n"
    "            end\n",
    "            self:setPersonLive(person, true)\n", 1)],
  "a saved consultant is live before her companion claimed her"),
 ("S18-duplicate-claim-creates-a-third", SYS,
  [("    if #matches > 1 then\n", "    if false then\n", 1)],
  "two saved consultants: the claim creates a third instead of refusing"),
 ("S19-reset-lowers-the-mark", SYS,
  [("    self:teardownTown(true)\n", "    self:teardownTown(false)\n", 1)],
  "the developer reset drops the mark to what the save carries"),
 # ── guards ──────────────────────────────────────────────────────────────────
 ("S21-ai-gate-removed", AI,
  [("    local sys = self.npcSystem\n"
    "    if sys ~= nil and sys.isPersonActionable ~= nil and not sys:isPersonActionable(npc) then\n"
    "        return\n"
    "    end\n", "", 1)],
  "a presence or a waiting person is put to field work"),
 ("S22-field-key-by-text", FLD,
  [("    local npcId = npc.id\n"
    "    if type(npcId) ~= \"number\" or npcId < 1 or npcId ~= math.floor(npcId) then return nil, nil end\n",
    "    local npcId = npc.uniqueId or npc.id or npc.name or tostring(npc)\n", 1)],
  "the reservation key is the legacy text again: two people share one slot"),
 ("S23-ai-release-by-text", AI,
  [("        fieldWork:releaseWorker(npc._fieldWorkFieldId, npc.id)\n"
    "        npc._fieldWorkFieldId = nil\n"
    "        npc.fieldWorkWaypoints = nil\n",
    "        fieldWork:releaseWorker(npc._fieldWorkFieldId, npc.uniqueId or npc.id or npc.name)\n"
    "        npc._fieldWorkFieldId = nil\n"
    "        npc.fieldWorkWaypoints = nil\n", 1)],
  "the release helper releases by legacy text: nothing is released"),
 ("S24-ai-break-release-by-text", AI,
  [("                fieldWork:releaseWorker(npc._fieldWorkFieldId, npc.id)\n"
    "                npc._fieldWorkFieldId = nil\n",
    "                fieldWork:releaseWorker(npc._fieldWorkFieldId, npc.uniqueId or npc.id or npc.name)\n"
    "                npc._fieldWorkFieldId = nil\n", 1)],
  "the work-timer break releases by legacy text"),
 # ── favours ─────────────────────────────────────────────────────────────────
 ("S25-new-favour-unmarked", FAV,
  [("        personRefKind = \"durable\",\n", "", 1)],
  "a new favour carries no durable mark: it is held on the next load"),
 ("S26-export-drops-the-mark", REC,
  [("        personRefKind = (favor.personRefKind == NPCFavorRecovery.REF_DURABLE) and NPCFavorRecovery.REF_DURABLE or nil,\n", "", 1)],
  "the writers drop the mark"),
 ("S27-xml-mark-not-read", SYS,
  [("        personRefKind = personRefKind,\n", "", 1)],
  "the XML reader drops the mark"),
 ("S28-legacy-favour-promoted", REC,
  [("    if proof == \"proved\" then return collection end\n",
    "    if proof == \"proved\" or proof == \"unproven\" then return collection end\n", 1)],
  "an unmarked accepted row goes live against a namesake"),
 ("S29-name-fallback-restored", REC,
  [("    if sys.resolveRetainedPerson ~= nil then\n"
    "        return sys:resolveRetainedPerson(id)\n"
    "    end\n",
    "    if saved.npcName ~= nil and saved.npcName ~= \"\" then\n"
    "        for _, candidate in ipairs(sys.activeNPCs or {}) do\n"
    "            if candidate.name == saved.npcName then return candidate end\n"
    "        end\n"
    "    end\n"
    "    if sys.resolveRetainedPerson ~= nil then\n"
    "        return sys:resolveRetainedPerson(id)\n"
    "    end\n", 1)],
  "a saved name resolves a live person: a namesake is a witness"),
 ("S30-unproven-row-resumes", REC,
  [("    if type(favor) ~= \"table\" or favor.personUnproven == true then\n"
    "        return false\n"
    "    end\n", "", 1)],
  "an unproven held row can be resumed"),
 # ── serializers ─────────────────────────────────────────────────────────────
 ("S31-npcCount-gate-restored", SYS,
  [("    if not self.isInitialized then\n"
    "        return\n"
    "    end\n"
    "\n"
    "    -- RSF-F357: the gate is the selected-state readiness, not npcCount.",
    "    if not self.isInitialized or self.npcCount == 0 then\n"
    "        return\n"
    "    end\n"
    "\n"
    "    -- RSF-F357: the gate is the selected-state readiness, not npcCount.", 1)],
  "an empty roster with an allocated mark is not saved: the mark is lost"),
 ("S33-presences-saved", SYS,
  [("    for _, person in ipairs(self.people.roster) do\n"
    "        state.npcs[#state.npcs + 1] = NPCPersonRoster.exportPersonRow(person)\n"
    "    end\n",
    "    for _, person in ipairs(self.people.roster) do\n"
    "        state.npcs[#state.npcs + 1] = NPCPersonRoster.exportPersonRow(person)\n"
    "    end\n"
    "    for _, key in ipairs(self.people.presenceOrder) do\n"
    "        state.npcs[#state.npcs + 1] = NPCPersonRoster.exportPersonRow(self.people.presences[key])\n"
    "    end\n", 1)],
  "a worker presence is persisted as a person"),
 ("S34-unmarked-tie-reconnected", ROS,
  [("        if type(tie) == \"table\" and tie.endpointKind == NPCPersonRoster.REF_DURABLE\n",
    "        if type(tie) == \"table\"\n", 1)],
  "a legacy numeric tie is reattached to whoever holds those numbers now"),
 # ── the public snapshot and the client ─────────────────────────────────────
 ("S35-empty-snapshot-skipped", EVT,
  [("    if snapshot == nil then return end\n", "    if snapshot == nil or snapshot.total == 0 then return end\n", 1)],
  "an initialized empty roster is never published: clients keep stale bodies"),
 ("S36-waiting-row-gets-live-trust", ROS,
  [("    if live and NPCPersonRoster.isFiniteNumber(person.relationship) then\n",
    "    if NPCPersonRoster.isFiniteNumber(person.relationship) then\n", 1)],
  "a waiting person's public row claims a live trust value"),
 ("S37-conflicting-page-accepted", ROS,
  [("        if not sameRecords(held, page.records) then\n"
    "            pending.invalid = true\n"
    "            return \"rejected\"\n"
    "        end\n", "", 1)],
  "a conflicting duplicate page is accepted and the snapshot publishes"),
 ("S38-older-sequence-accepted", ROS,
  [("    if sequence < self.publishedSequence then return \"rejected\" end\n", "", 1)],
  "an older snapshot replaces the published one"),
 ("S39-total-unbounded", ROS,
  [("    if not NPCPersonRoster.isFiniteNumber(total) or total < 0 or total > NPCPersonRoster.MAX_RECORDS\n"
    "        or total ~= math.floor(total) then return \"rejected\" end\n",
    "    if not NPCPersonRoster.isFiniteNumber(total) or total < 0\n"
    "        or total ~= math.floor(total) then return \"rejected\" end\n", 1)],
  "a page claiming more than 4096 records starts an assembly"),
 ("S40-unavailable-publishes-empty", ROS,
  [("    if page.unavailable == true then\n"
    "        -- The server could not assemble a current snapshot. Nothing partial is\n"
    "        -- published; what is displayed stays last-confirmed and unavailable for\n"
    "        -- interactions.\n"
    "        self.clientUnavailable = true\n"
    "        self.clientReason = page.reasonKey or NPCPersonRoster.REASON_SNAPSHOT_TOO_LARGE\n"
    "        if self.pending ~= nil and self.pending.sequence < sequence then self.pending = nil end\n"
    "        return \"unavailable\"\n"
    "    end\n", "", 1)],
  "an unavailable snapshot publishes as a complete empty town"),
 ("S41-over-limit-published-truncated", ROS,
  [("    if #records > NPCPersonRoster.MAX_RECORDS then\n"
    "        return nil, NPCPersonRoster.REASON_SNAPSHOT_TOO_LARGE\n"
    "    end\n", "", 1)],
  "a roster over the supported snapshot publishes anyway"),
 ("S42-netsync-trailer-unchecked", NET,
  [("    if trailerSeq ~= snapshot.sequence or trailerTotal ~= total then return nil, \"bad_trailer\" end\n", "", 1)],
  "a mismatched completeness trailer is accepted"),
 ("S43-netsync-stamp-unchecked", NET,
  [("        if stamp ~= snapshot.sequence then return nil, \"stale_stamp\" end\n", "", 1)],
  "a stale per-record stamp is accepted"),
 ("S44-netsync-duplicate-id-accepted", NET,
  [("            if not NPCPersonRoster.validId(rec.personId) or seen[rec.personId] then return nil, \"bad_id\" end\n",
    "            if not NPCPersonRoster.validId(rec.personId) then return nil, \"bad_id\" end\n", 1)],
  "duplicate ids publish an apparently complete array"),
 # ── presences ───────────────────────────────────────────────────────────────
 ("S45-presence-enters-live-view", CTR,
  [("            local presence = people:upsertPresence(key, observed)\n",
    "            local presence = people:upsertPresence(key, observed)\n"
    "            if presence ~= nil then table.insert(self.npcSystem.activeNPCs, presence) end\n", 1)],
  "a worker presence is put into activeNPCs"),
 ("S46-unreadable-removes-presences", CTR,
  [("        people:setPresencesUnavailable(true)\n"
    "        return\n",
    "        people:clearPresences()\n"
    "        return\n", 1)],
  "an unreadable worker list removes the presences instead of marking them unavailable"),
]

def sha(b): return hashlib.sha256(b).hexdigest()

def run_suite():
    r = subprocess.run([sys.executable and "node", "run-tests.mjs"], cwd=p("tools/test"),
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    out = (r.stdout or "") + (r.stderr or "")
    fails = [l.strip() for l in out.splitlines() if "FAIL " in l and "##" not in l and l.strip().startswith("FAIL")]
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
            print("  BAD EDIT %s: anchor found %d times, want %d" % (mid, text.count(old), count)); ok = False; break
        text = text.replace(old, new)
    if not ok: bad += 1; continue
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
        for l in fails[:4]: print("        " + l)
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
