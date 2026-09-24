# RSF-F357 actions and private views mutation battery: the actor binding and the work-action
# selection in src/events/NPCInteractionEvent.lua, the request and reply wire in
# src/events/NPCPersonDialogEvents.lua, the dispatcher, the per-connection gate, the copied
# views and the client adapters in src/scripts/NPCPersonDialog.lua, the bound server work
# actions in src/NPCSystem.lua, the acting-farm money read in src/scripts/NPCFavorSystem.lua,
# and the identity-binding rewires of NPCDialog, NPCAdminEditDialog, NPCListDialog, NPCFavorHUD
# and NPCFavorGUI. Rows live in RSF-F357-actions_views_spec_test.lua; the host-core spec and
# the four preserved contract tests run with it.
#
# KILLED* means killed only by a Lua error: a weak kill, treated as a failure.
#
# NOT RUN, and why:
#   - the local-host guard in NPCInteractionEvent.sendToServer (a dedicated server's nil local
#     player): masked by the exact-actor distance rule, which refuses every person-scoped
#     action whose actor has no position, so a fabricated actor there changes nothing
#     observable; the dialog dispatcher's own local guard IS run (A45) on the proximity-free
#     page, where nothing masks it. Declared equivalent, kept as defence in depth.
#   - the sole-pending check in serverAcceptFavor: no production path creates a second pending
#     row for one person (generation refuses a person with any favour; PR 1's load holds
#     legacy rows out of the pending set), so the spec has no world in which it fires.
#     Declared not reachable here, not equivalent; it guards a save edited by hand.
#   - retireRecoveryToken after completeFavor and abandonFavor in the two server commands:
#     the favour owner retires the token itself on every terminal status (K18, K22 pin that),
#     so the second call is belt and braces. Declared equivalent.
#   - the CURRENT/LAST_CONFIRMED gate in NPCFavorHUD.visibleWork and
#     NPCFavorManagementDialog.getPageItems: getPersonalWorkView hands out rows only in those
#     two states already (A33 and A34 pin the states), so the readers' own gate is redundant.
#     Declared equivalent.
#   - the SCS floor and its rel > 0 gate: PR 3 of this brief.
#
# Anchors are written with "\n"; in a CRLF file they are matched after normalising.
#
# RUN IT ALONE, THROUGH THE TEST LOCK. A battery edits production files in place.
#
# Usage: py tools/test/mutate_rsf_f357_actions.py [id-prefix ...]
import hashlib, os, subprocess, sys

# The runner's own output carries non-ASCII marks; a cp1252 console must not stop a battery.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
def p(rel): return os.path.join(ROOT, rel)

IEV = "src/events/NPCInteractionEvent.lua"
EVT = "src/events/NPCPersonDialogEvents.lua"
DLG = "src/scripts/NPCPersonDialog.lua"
SYS = "src/NPCSystem.lua"
FAV = "src/scripts/NPCFavorSystem.lua"
UI  = "src/gui/NPCDialog.lua"
ADM = "src/gui/NPCAdminEditDialog.lua"
GUI = "src/settings/NPCFavorGUI.lua"
LST = "src/gui/NPCListDialog.lua"
HUD = "src/scripts/NPCFavorHUD.lua"

MUTATIONS = [
 # ── the exact acting player ─────────────────────────────────────────────────
 ("A01-unknown-position-is-near", IEV,
  [("    local px, _, pz = NPCInteractionEvent.actorPosition(actor)\n    if px == nil then return nil end\n",
    "    local px, _, pz = NPCInteractionEvent.actorPosition(actor)\n    if px == nil then return 0 end\n", 1)],
  "an actor whose position cannot be established counts as standing on the person"),
 ("A02-fail-open-in-execute", IEV,
  [("    local dist = NPCInteractionEvent.actorDistanceTo(actor, npc)\n    if dist == nil or dist > NPCInteractionEvent.MAX_INTERACTION_DISTANCE then\n",
    "    local dist = NPCInteractionEvent.actorDistanceTo(actor, npc)\n    if dist ~= nil and dist > NPCInteractionEvent.MAX_INTERACTION_DISTANCE then\n", 1)],
  "a work action with no distance proceeds"),
 ("A03-farm-mate-surrogate", IEV,
  [("    local dx, dz = px - nx, pz - nz\n    return math.sqrt(dx * dx + dz * dz)\nend\n",
    "    local dx, dz = px - nx, pz - nz\n    local best = math.sqrt(dx * dx + dz * dz)\n"
    "    for _, pl in pairs((g_currentMission and g_currentMission.playerSystem and g_currentMission.playerSystem.players) or {}) do\n"
    "        local ok, qx, _, qz = pcall(pl.getPosition, pl)\n"
    "        if ok and type(qx) == \"number\" and type(qz) == \"number\" then\n"
    "            local d = math.sqrt((qx - nx) ^ 2 + (qz - nz) ^ 2)\n"
    "            if d < best then best = d end\n"
    "        end\n"
    "    end\n"
    "    return best\nend\n", 1)],
  "the closest player on the farm stands in for the actor"),
 ("A04-relationship-action-dispatched", IEV,
  [("    if actionType == NPCInteractionEvent.ACTION_RELATIONSHIP then\n"
    "        print(\"[NPCFavor SECURITY] Rejected client-supplied relationship change\")\n"
    "        return false, nil\n    end\n",
    "    if actionType == NPCInteractionEvent.ACTION_RELATIONSHIP then\n"
    "        local npcRel = sys:getNPCById(npcId)\n"
    "        if npcRel ~= nil then sys:serverUpdateRelationship(npcRel, farmId, value, data) end\n"
    "        return true, nil\n    end\n", 1)],
  "a client-supplied trust change reaches the model again"),
 # ── the selection binding ───────────────────────────────────────────────────
 ("A05-lenient-selection", IEV,
  [("    local a, b, c = data:match(\"^(%d+)|(%d+)|(%d+)$\")\n    if a == nil then return nil end\n"
    "    if not NPCFarmIdentity.validWireNumber(a) or not NPCFarmIdentity.validToken(b)\n"
    "        or not NPCFarmIdentity.validWireNumber(c) then\n        return nil\n    end\n",
    "    local a, b, c = data:match(\"^([^|]+)|([^|]+)|([^|]+)$\")\n    if a == nil then return nil end\n", 1)],
  "a malformed selection is evaluated instead of dropped"),
 ("A06-revision-unchecked", SYS,
  [("    if (record.recordRevision or 0) ~= selection.recordRevision then return nil, \"npc_dialog_refused_stale\" end\n", "", 1)],
  "a stale revision acts on the current record"),
 ("A07-token-person-unchecked", SYS,
  [("    if record == nil or record.npcId ~= npc.id then return nil, \"npc_dialog_refused_stale\" end\n",
    "    if record == nil then return nil, \"npc_dialog_refused_stale\" end\n", 1)],
  "another person's token acts for this person"),
 ("A08-accept-cooldown-barrier", SYS,
  [("    local fav = self.favorSystem\n    if fav == nil or fav.acceptFavorForNPC == nil then return false, \"npc_dialog_unavailable\" end\n",
    "    local fav = self.favorSystem\n    if fav == nil or fav.acceptFavorForNPC == nil then return false, \"npc_dialog_unavailable\" end\n"
    "    if (npc.favorCooldown or 0) > 0 then return false, \"npc_dialog_refused_stale\" end\n", 1)],
  "the generation cooldown refuses the offer already made"),
 ("A09-reply-broadcast", EVT,
  [("    local reply = g_NPCSystem:serverPersonDialogRequest(connection, self.request)\n    if reply ~= nil then\n"
    "        connection:sendEvent(NPCPersonDialogReplyEvent.new(reply))\n    end\n",
    "    local reply = g_NPCSystem:serverPersonDialogRequest(connection, self.request)\n    if reply ~= nil then\n"
    "        g_server:broadcastEvent(NPCPersonDialogReplyEvent.new(reply))\n    end\n", 1)],
  "a private reply goes to every client"),
 ("A10-eligibility-not-rederived", SYS,
  [("    local eligible, step = NPCPersonDialog.completionEligible(record)\n    if not eligible then\n"
    "        return false, \"npc_dialog_refused_not_ready\"\n    end\n"
    "    if record.awaitingConfirmation == true then\n        record.awaitingConfirmation = false\n"
    "    elseif step ~= nil then\n        step.completed = true\n    end\n",
    "    for _, s in ipairs(record.steps or {}) do s.completed = true end\n    record.awaitingConfirmation = false\n", 1)],
  "completion accepts the client's word and finishes an open travel step"),
 ("A11-other-farm-completes", SYS,
  [("    if record.ownerFarmId ~= farmId then\n"
    "        print(string.format(\"[NPC Favor SECURITY] Complete refused: farm %s does not own favor %s (owner %s)\",\n"
    "            tostring(farmId), tostring(record.id), tostring(record.ownerFarmId)))\n"
    "        return false, \"npc_recovery_refused_not_owner\"\n    end\n", "", 1)],
  "another farm completes the owner's work"),
 ("A56-other-farm-abandons", SYS,
  [("    if record.ownerFarmId ~= farmId then\n"
    "        print(string.format(\"[NPC Favor SECURITY] Abandon refused: farm %s does not own favor %s (owner %s)\",\n"
    "            tostring(farmId), tostring(record.id), tostring(record.ownerFarmId)))\n"
    "        return false, \"npc_recovery_refused_not_owner\"\n    end\n", "", 1)],
  "another farm abandons the owner's work"),
 ("A74-work-actions-skip-the-gate", IEV,
  [("    local gate, cached = nil, nil\n    if isWorkAction and sys.dialogRequestGate ~= nil then\n",
    "    local gate, cached = nil, nil\n    if false then\n", 1)],
  "an older or reused work-action id executes"),
 ("A75-work-reply-not-retained", IEV,
  [("        if isWorkAction and sys.dialogRequestRecord ~= nil and r ~= nil then\n"
    "            sys:dialogRequestRecord(actor, selection.requestId, r)\n        end\n", "", 1)],
  "a replayed accept has no retained result to re-send"),
 ("A40-accept-reply-without-row", IEV,
  [("        if ok and record ~= nil and sys.describeWorkRow ~= nil then\n"
    "            r.rows = { sys:describeWorkRow(record, actor) }\n        end\n", "", 1)],
  "the dialog learns nothing about the work it just accepted"),
 # ── the per-connection gate ─────────────────────────────────────────────────
 ("A12-replay-reexecutes", DLG,
  [("    if id == session.highWater and session.latest ~= nil then\n"
    "        if session.latest.fingerprint ~= fingerprint then return \"changed\", nil end\n"
    "        if session.latest.farmId ~= actor.farmId then return \"changed\", nil end\n"
    "        return \"replay\", session.latest.reply\n    end\n", "", 1)],
  "an identical repeat runs again (credits Talk twice, rerolls a decline)"),
 ("A13-stale-executes", DLG,
  [("    if id < session.highWater then return \"stale\", nil end\n", "", 1)],
  "an older request id is executed"),
 ("A14-changed-request-replayed", DLG,
  [("        if session.latest.fingerprint ~= fingerprint then return \"changed\", nil end\n", "", 1)],
  "the same id with a different request re-sends the old result"),
 ("A15-farm-change-replayed", DLG,
  [("        if session.latest.farmId ~= actor.farmId then return \"changed\", nil end\n", "", 1)],
  "a replay after a farm change hands out the old farm's reply"),
 ("A16-session-shared", DLG,
  [("    local key = actor.connectionId\n    local session = self.dialogSessions[key]\n",
    "    local key = \"all\"\n    local session = self.dialogSessions[key]\n", 1)],
  "one gate for every connection: another client's id collides"),
 ("A17-session-kept-after-leave", SYS,
  [("        if self.clearDialogSession ~= nil then self:clearDialogSession(\"user:\" .. tostring(userId)) end\n", "", 1)],
  "a departed user's high-water mark refuses the same user's fresh session"),
 ("A45-local-actor-fabricated", DLG,
  [("    local actor = NPCFarmIdentity.resolveActor(connection)\n    if actor == nil then return nil end\n    local op = request.op\n",
    "    local actor = NPCFarmIdentity.resolveActor(connection)\n"
    "    if actor == nil then actor = { connectionId = \"local\", connection = nil, farmId = NPCFarmIdentity.localClaimFarmId(), isMaster = true, isLocal = true } end\n"
    "    local op = request.op\n", 1)],
  "a dedicated server's nil local actor is invented"),
 # ── the person-scoped operations ────────────────────────────────────────────
 ("A18-talk-writes-trust-directly", DLG,
  [("        if rm ~= nil and rm.updateRelationship ~= nil then\n"
    "            applied = rm:updateRelationship(npc.id, 1, \"daily_interaction\") == true\n        end\n",
    "        npc.relationship = math.min(100, (npc.relationship or 0) + 1)\n        applied = true\n", 1)],
  "Talk bypasses the owner's daily limit and mood rules"),
 ("A19-offer-threshold-dropped", DLG,
  [("        if (npc.relationship or 0) < 25 then\n"
    "            return refused(NPCPersonDialog.RESULT_REFUSED, \"npc_dialog_refused_relationship\")\n        end\n", "", 1)],
  "Offer help below the threshold creates an offer"),
 ("A20-existing-offer-not-returned", DLG,
  [("        local existing = self:serverPersonDialogView(actor, npc, requestId, op)\n"
    "        if existing.result == NPCPersonDialog.RESULT_OFFER or existing.result == NPCPersonDialog.RESULT_ACCEPTED\n"
    "            or existing.result == NPCPersonDialog.RESULT_BUSY then\n            return existing\n        end\n", "", 1)],
  "a second Offer help answers no-work instead of the offer already made"),
 ("A21-busy-leaks-details", DLG,
  [("                else\n                    reply.result, reply.messageKey = NPCPersonDialog.RESULT_BUSY, \"npc_dialog_busy\"\n                end\n",
    "                else\n                    reply.rows[#reply.rows + 1] = self:describeWorkRow(favor, actor)\n"
    "                    reply.result, reply.messageKey = NPCPersonDialog.RESULT_BUSY, \"npc_dialog_busy\"\n                end\n", 1)],
  "another farm's accepted work travels with the busy answer"),
 ("A72-accepted-view-for-any-farm", DLG,
  [("            elseif ACTIVE_STATUS[favor.status] then\n                if favor.ownerFarmId == actor.farmId then\n",
    "            elseif ACTIVE_STATUS[favor.status] then\n                if true then\n", 1)],
  "the accepted-work view is supplied to a farm that does not own it"),
 ("A59-page-needs-proximity", DLG,
  [("        else\n            reply = self:serverPersonalWorkPage(actor, requestId, cursor)\n        end\n",
    "        else\n            local near = false\n"
    "            for _, npc in ipairs(self.activeNPCs or {}) do\n"
    "                local d = NPCInteractionEvent.actorDistanceTo(actor, npc)\n"
    "                if d ~= nil and d <= 15 then near = true break end\n            end\n"
    "            reply = near and self:serverPersonalWorkPage(actor, requestId, cursor) or refused(NPCPersonDialog.RESULT_REFUSED, \"npc_dialog_refused_far\")\n"
    "        end\n", 1)],
  "the own-farm page acquires a proximity requirement"),
 # ── the farm-private page ───────────────────────────────────────────────────
 ("A22-other-farms-work-on-page", DLG,
  [("        local owned = ACTIVE_STATUS[favor.status] == true and favor.ownerFarmId == actor.farmId\n"
    "        if favor.recoveryToken ~= nil and (owned or NPCPersonDialog.isPublicOffer(favor, now)) then\n",
    "        local owned = ACTIVE_STATUS[favor.status] == true\n"
    "        if favor.recoveryToken ~= nil and (owned or NPCPersonDialog.isPublicOffer(favor, now)) then\n", 1)],
  "every farm's accepted work is on every farm's page"),
 ("A23-page-over-20", DLG,
  [("            if #reply.rows >= NPCPersonDialog.WORK_PAGE_ROWS then\n",
    "            if #reply.rows >= NPCPersonDialog.WORK_PAGE_ROWS * 5 then\n", 1)],
  "a page carries more than 20 rows"),
 ("A24-wire-rows-uncapped", EVT,
  [("    local n = math.min(#rows, NPCPersonDialog.WORK_PAGE_ROWS)\n", "    local n = #rows\n", 1)],
  "the wire writes every row it is given"),
 ("A25-unready-page-claims-zero", DLG,
  [("    if fav == nil or (fav.isFavorLoadReady ~= nil and not fav:isFavorLoadReady())\n"
    "        or (self.people ~= nil and not self.people:isReady()) or fav._recoveryCounterExhausted then\n"
    "        reply.messageKey = \"npc_work_view_unavailable\"\n        return reply\n    end\n",
    "    if fav == nil then\n        reply.messageKey = \"npc_work_view_unavailable\"\n        return reply\n    end\n", 1)],
  "a host that has not loaded answers an empty page as if it were true"),
 ("A26-legacy-row-is-an-offer", DLG,
  [("    if favor.recoveredFromLegacy == true then return false end\n", "", 1)],
  "a resumed legacy pending row is a public offer"),
 # ── the wire ────────────────────────────────────────────────────────────────
 ("A46-tone-off-the-wire", EVT,
  [("    streamWriteString(streamId, textString(r.toneKey))\n", "", 1),
   ("    r.toneKey = textString(streamReadString(streamId))\n", "", 1)],
  "a remote client never receives the Talk tone"),
 ("A47-op-range-unchecked", EVT,
  [("    if r.op < NPCPersonDialog.OP_MIN or r.op > NPCPersonDialog.OP_MAX then\n"
    "        print(string.format(\"[NPCFavor SECURITY] Invalid dialog operation: %d\", r.op))\n        return\n    end\n", "", 1)],
  "an operation outside the range reaches run"),
 ("A48-text-cut-mid-character", EVT,
  [("    if #s <= 256 then return s end\n    local cut = 256\n    while cut > 0 do\n"
    "        local b = s:byte(cut + 1)\n        if b == nil or b < 0x80 or b >= 0xC0 then break end\n        cut = cut - 1\n    end\n"
    "    return s:sub(1, cut)\n",
    "    return s:sub(1, 256)\n", 1)],
  "the 256-byte cut splits a UTF-8 character"),
 ("A66-absent-person-placeholder-kept", EVT,
  [("    if not row.personIdPresent then row.personId = 0 end\n", "", 1)],
  "an absent person reads as its placeholder number"),
 # ── the client adapters ─────────────────────────────────────────────────────
 ("A27-reply-farm-unchecked", DLG,
  [("    local farmId = NPCFarmIdentity.localClaimFarmId()\n    if farmId == nil or reply.farmId ~= farmId then return end\n\n"
    "    if reply.kind == NPCPersonDialog.KIND_WORK_PAGE then\n",
    "    local farmId = NPCFarmIdentity.localClaimFarmId()\n    if farmId == nil then return end\n\n"
    "    if reply.kind == NPCPersonDialog.KIND_WORK_PAGE then\n", 1)],
  "a reply for another farm is shown"),
 ("A28-reply-id-unchecked", DLG,
  [("    if c.pending == nil or reply.requestId ~= c.pending.requestId then return end\n    if c.context == nil then\n",
    "    if c.pending == nil then return end\n    if c.context == nil then\n", 1)],
  "a reply for an older request lands on the current one"),
 ("A29-reply-person-unchecked", DLG,
  [("    if reply.personId ~= c.context.personId and reply.personId ~= 0 then return end\n", "", 1)],
  "a reply about another person lands on this dialog"),
 ("A30-context-kept-on-end", DLG,
  [("function NPCSystem:endPersonDialog()\n    local c = self:_dialogClient()\n    c.context = nil\n    c.pending = nil\n    c.lastReply = nil\nend\n",
    "function NPCSystem:endPersonDialog()\n    local c = self:_dialogClient()\n    c.lastReply = nil\nend\n", 1)],
  "a closed dialog still receives replies"),
 ("A31-request-id-reset-on-open", DLG,
  [("    c.context = { personId = personId, farmId = NPCFarmIdentity.localClaimFarmId() }\n    c.pending = nil\n    c.lastReply = nil\nend\n",
    "    c.context = { personId = personId, farmId = NPCFarmIdentity.localClaimFarmId() }\n    c.pending = nil\n    c.lastReply = nil\n    c.nextRequestId = 1\nend\n", 1)],
  "every dialog open restarts the request counter"),
 ("A68-selection-unvalidated-locally", DLG,
  [("    if type(selection) ~= \"table\" or not NPCFarmIdentity.validToken(tostring(selection.token or \"\"))\n"
    "        or not NPCFarmIdentity.validWireNumber(tostring(selection.recordRevision or \"\")) then\n"
    "        return false, \"npc_dialog_refused_stale\"\n    end\n",
    "    if type(selection) ~= \"table\" then return false, \"npc_dialog_refused_stale\" end\n", 1)],
  "a selection that is not a wire number is sent"),
 ("A69-view-work-through-the-person-adapter", DLG,
  [("    if opCode == nil or opCode == NPCPersonDialog.OP_VIEW_WORK then return false, \"npc_dialog_refused_operation\" end\n",
    "    if opCode == nil then return false, \"npc_dialog_refused_operation\" end\n", 1)],
  "the person adapter sends the farm page request"),
 ("A32-farm-change-keeps-views", DLG,
  [("    if c.context ~= nil and c.context.farmId ~= farmId then self:clearPrivateViews() end\n"
    "    if c.work.farmId ~= nil and c.work.farmId ~= farmId then self:clearPrivateViews() end\n", "", 1)],
  "a farm change keeps the old farm's private views"),
 ("A33-pending-reads-current", DLG,
  [("        view.state = (w.pendingRequestId ~= nil) and \"PENDING\" or \"UNAVAILABLE\"\n",
    "        view.state = (w.pendingRequestId ~= nil) and \"CURRENT\" or \"UNAVAILABLE\"\n", 1)],
  "a page that has not arrived reads CURRENT"),
 ("A34-never-last-confirmed", DLG,
  [("    elseif view.ageMs > NPCPersonDialog.STALE_AFTER_MS and w.pendingRequestId ~= nil then\n"
    "        view.state = \"LAST_CONFIRMED\"\n        view.reasonKey = \"npc_work_view_last_confirmed\"\n    else\n",
    "    else\n", 1)],
  "an old page with a missing reply still reads CURRENT"),
 ("A35-two-outstanding", DLG,
  [("    self:_releaseLostWorkPage()\n    if w.pendingRequestId ~= nil then return false end\n",
    "    self:_releaseLostWorkPage()\n", 1)],
  "a second page request goes out while one is outstanding"),
 ("A55-lost-page-never-released", DLG,
  [("    if w.pendingRequestId ~= nil and w.requestedAt ~= nil\n"
    "        and nowMs() - w.requestedAt > NPCPersonDialog.STALE_AFTER_MS * 2 then\n"
    "        w.pendingRequestId = nil\n    end\n", "", 1)],
  "a request that never came back blocks the page forever"),
 ("A36-refresh-without-watcher", DLG,
  [("    self:_releaseLostWorkPage()\n    if c.watchers <= 0 then return end\n",
    "    self:_releaseLostWorkPage()\n", 1)],
  "the page polls with nobody watching"),
 ("A37-context-free-reply-dropped", DLG,
  [("    if c.context == nil then\n        c.pending = nil\n"
    "        if c.watchers > 0 then c.refreshTimerMs = NPCPersonDialog.REFRESH_INTERVAL_MS end\n"
    "        if NPCFavorManagementDialog ~= nil and NPCFavorManagementDialog.onWorkActionResult ~= nil then\n"
    "            pcall(NPCFavorManagementDialog.onWorkActionResult, reply)\n        end\n        return\n    end\n",
    "    if c.context == nil then\n        c.pending = nil\n        return\n    end\n", 1)],
  "the management dialog's action result is swallowed"),
 # ── the readers ─────────────────────────────────────────────────────────────
 ("A39-action-reply-rendered-as-talk", UI,
  [("    local isDialogReply = reply.kind == R.KIND_DIALOG\n", "    local isDialogReply = true\n", 1)],
  "an accept reply (action type 1) paints as a Talk line (op 1)"),
 ("A41-pending-line-after-sync-reply", UI,
  [("    local view = self:personView()\n    if view ~= nil and view.pending then\n"
    "        self:setResponse(getModText(\"npc_dialog_pending\", \"Asking the neighbour...\"))\n    end\nend\n",
    "    self:setResponse(getModText(\"npc_dialog_pending\", \"Asking the neighbour...\"))\nend\n", 1)],
  "the listen host paints the pending line over the reply it already has"),
 ("A42-admin-remote-allowed", ADM,
  [("    if g_server == nil or g_localPlayer == nil then\n        if self.statusText then\n",
    "    if false then\n        if self.statusText then\n", 1)],
  "a remote client edits its local copy of a neighbour"),
 ("A43-goto-by-row", GUI,
  [("    local npc = g_NPCSystem.getNPCById and g_NPCSystem:getNPCById(index) or nil\n",
    "    local npc = g_NPCSystem.activeNPCs[index]\n", 1)],
  "npcGoto resolves a row position, not the durable number it displays"),
 ("A44-teleport-by-row", LST,
  [("    local npc = sys:getNPCById(d.personId)\n"
    "    if not npc or not npc.position or (sys.isPersonActionable ~= nil and not sys:isPersonActionable(npc)) then\n",
    "    local npc = sys.activeNPCs[rowNum]\n"
    "    if not npc or not npc.position or (sys.isPersonActionable ~= nil and not sys:isPersonActionable(npc)) then\n", 1)],
  "Go teleports to whoever occupies the row now"),
 ("A70-hud-never-watches", HUD,
  [("    if wantWatch and not self._watchingWork then\n        self._watchingWork = true\n        self.npcSystem:watchPersonalWork(true)\n",
    "    if wantWatch and not self._watchingWork then\n        self._watchingWork = true\n", 1)],
  "the HUD shows the list but never asks for the page"),
 # ── the money read and the gift ─────────────────────────────────────────────
 ("A49-gift-without-balance", SYS,
  [("            local farm = g_farmManager and g_farmManager:getFarmById(farmId)\n"
    "            local balance = farm and farm.money or 0\n            if balance < amount then\n                return false\n            end\n", "", 1)],
  "a gift the farm cannot afford is applied and charged"),
 ("A51-money-requirement-from-host-player", FAV,
  [("        if actingFarmId ~= nil then\n            local farm = NPCFarmIdentity.getLiveFarm(actingFarmId)\n"
    "            money = farm and farm.money or nil\n        elseif g_currentMission and g_currentMission.player then\n",
    "        if g_currentMission and g_currentMission.player then\n", 1)],
  "a money requirement reads the host player instead of the acting farm"),
 ("A54-revision-not-bumped-on-accept", FAV,
  [("            if self.bumpRecordRevision ~= nil then self:bumpRecordRevision(favor) end\n            if self.npcSystem.favorHUD then\n",
    "            if self.npcSystem.favorHUD then\n", 1)],
  "an accepted record keeps the revision the offer showed"),
]

def sha(b): return hashlib.sha256(b).hexdigest()

def run_suite():
    r = subprocess.run(["node", "run-tests.mjs"], cwd=p("tools/test"),
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
