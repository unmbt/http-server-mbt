# BRIEFING — 2026-09-18T13:12:00Z

## Mission
Design and implement the dual min/full C ABI dynamic and static library export pipeline in MoonBit project http-server-mbt, with clean hs_* symbol isolation, .mbtx build driver script, and standalone C consumer smoke tests.

## 🔒 My Identity
- Archetype: Project Orchestrator
- Roles: orchestrator, user_liaison, human_reporter, successor
- Working directory: E:/project/moonbit/unmbt/http-server-mbt/.agents/orchestrator_cabi_1
- Original parent: parent
- Original parent conversation ID: 8daa1763-599b-4bc0-850f-fea87e5cc5c8

## 🔒 My Workflow
- **Pattern**: Project
- **Scope document**: E:/project/moonbit/unmbt/http-server-mbt/.agents/orchestrator_cabi_1/PROJECT.md
1. **Decompose**: Survey full scope with 3 Explorers / Spec Miners, merge into Feature Inventory, split into verifiable milestones.
2. **Dispatch & Execute**:
   - **Direct (iteration loop)**: Explorer (3) → Worker (1) → Reviewer (2) + Challenger (2) + Auditor (1) → Gate evaluation.
3. **On failure** (in this order):
   - Retry: nudge stuck agent or re-send task
   - Replace: spawn fresh agent with partial progress
   - Skip: proceed without (only if non-critical)
   - Redistribute: split stuck agent's remaining work
   - Redesign: re-partition decomposition
   - Escalate: report to parent (sub-orchestrators only, last resort)
4. **Succession**: Spawn successor at 16 spawns after active subagents complete.
- **Work items**:
  1. Survey and Technical Investigation [in-progress]
  2. C ABI Interface & Bridge Package (min & full) [pending]
  3. Build Driver Script (scripts/build_cabi.mbtx) [pending]
  4. C Consumer Smoke Tests & Symbol Isolation Audit [pending]
  5. Full Regression & Git Commit Gate [pending]
- **Current phase**: 1 (Implementation)
- **Current focus**: Milestone 1 (C ABI Specification & Bridge Packages) and Milestone 2 (Build Driver Script)

## 🔒 Key Constraints
- NEVER write, modify, or create source code files directly.
- NEVER run build/test commands yourself — require workers to do so.
- NEVER investigate or explore the problem at the code level — dispatch Explorers for technical investigation.
- Use file-editing tools ONLY for metadata/state files (.md) in .agents/ folder.
- Never reuse a subagent after it has delivered its handoff — always spawn fresh.
- Binary veto on Forensic Auditor INTEGRITY VIOLATION.
- Local git commits only; strictly NO git push.
- 0 warnings, 0 errors, 100% pass on all existing 228 tests.

## Current Parent
- Conversation ID: 8daa1763-599b-4bc0-850f-fea87e5cc5c8
- Updated: 2026-09-18T13:27:00Z

## Key Decisions Made
- Dispatched survey phase to 3 explorers (including spec miner) to analyze docs/design.md, docs/tasks.md, docs/cli-min-full-and-cabi-handover.md, MoonBit native toolchain/clang/link.exe capabilities, and object file layout.
- Adopted package layout: c_abi/include/http_server.h, c_abi/min/, c_abi/full/.
- Confirmed Windows .def file export isolation strategy to restrict DLL exports strictly to the 5 hs_* APIs.
- Confirmed /Dmain=moonbit_unused_main preprocessor remapping to avoid main symbol collision in consumer programs linking static libraries.

## Team Roster
| Agent | Type | Work Item | Status | Conv ID |
|-------|------|-----------|--------|---------|
| spec_miner_survey_1 | teamwork_preview_spec_miner | Survey C ABI & symbol specs | completed | 8e8f7b7f-1386-4348-b677-817309c58063 |
| explorer_codebase_1 | teamwork_preview_explorer | Survey codebase & lifecycle bridging | completed | c24f30a2-4839-4abc-8757-7e473540a3ca |
| explorer_toolchain_1 | teamwork_preview_explorer | Survey toolchain, linking & build scripts | completed | 8cfe2877-c059-486e-8b0f-5818257f8514 |
| worker_impl_1 | teamwork_preview_worker | Implement C ABI packages, build driver & C consumer tests | completed | c40334ce-128c-4a33-8b8c-d5bde0630722 |
| reviewer_1 | teamwork_preview_reviewer | C ABI spec conformance & build pipeline review | in-progress | bcefad24-54e0-45e4-b215-66c804453c56 |
| reviewer_2 | teamwork_preview_reviewer | Memory safety, thread lifecycle & header review | in-progress | 0aa28851-f9d4-4861-8929-96c6515c42f6 |
| challenger_1 | teamwork_preview_challenger | Adversarial lifecycle & error stress testing | in-progress | 642e9619-0763-4750-95d4-828259bd02f4 |
| challenger_2 | teamwork_preview_challenger | Adversarial symbol purity & static link testing | in-progress | 9f9b1757-99db-4128-9d8d-a43f6aec58a9 |
| auditor_1 | teamwork_preview_auditor | Forensic integrity & zero-cheating verification | in-progress | f01d93d7-3aa5-4593-8860-b144ff0253f5 |

## Succession Status
- Succession required: no
- Spawn count: 9 / 16
- Pending subagents: [bcefad24-54e0-45e4-b215-66c804453c56, 0aa28851-f9d4-4861-8929-96c6515c42f6, 642e9619-0763-4750-95d4-828259bd02f4, 9f9b1757-99db-4128-9d8d-a43f6aec58a9, f01d93d7-3aa5-4593-8860-b144ff0253f5]
- Predecessor: none
- Successor: not yet spawned

## Active Timers
- Heartbeat cron: task-8
- Safety timer: none
- On succession: kill all timers before spawning successor
- On context truncation: run `manage_task(Action="list")` — re-create if missing

## Artifact Index
- E:/project/moonbit/unmbt/http-server-mbt/.agents/orchestrator_cabi_1/BRIEFING.md — Persistent working memory
- E:/project/moonbit/unmbt/http-server-mbt/.agents/orchestrator_cabi_1/PROJECT.md — Global architecture, feature inventory, milestones
- E:/project/moonbit/unmbt/http-server-mbt/.agents/orchestrator_cabi_1/progress.md — Liveness heartbeat and milestone tracking
- E:/project/moonbit/unmbt/http-server-mbt/.agents/orchestrator_cabi_1/DISPATCH.md — Task assignment log
