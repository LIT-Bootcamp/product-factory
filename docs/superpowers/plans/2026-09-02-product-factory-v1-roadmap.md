# Product Factory v1 Implementation Roadmap

**Spec:** `docs/design/product-factory-v1.md`

## Delivery rule

Implement the design as five sequential, independently testable slices. Do not start a later slice until the preceding slice passes its local and CI gates. Each slice receives its own detailed implementation plan immediately before execution so that exact interfaces reflect the code actually merged, rather than speculative scaffolding.

## Slice 1: Deterministic runtime and local setup

Detailed plan: `docs/superpowers/plans/2026-09-02-product-factory-foundation.md`

Delivers:

- Ruby 4.0.6 command-line runtime using Rails' existing Thor dependency;
- validated human configuration and machine installation state;
- deterministic plan, one-confirmation apply, operation journal, and resumption;
- three-way managed-file refresh conflicts;
- `doctor`, `plan`, `apply`, `validate`, and `test` commands;
- no GitHub mutations yet.

Exit proof: a temporary Rails repository can install managed local files, repeat as a no-op, refresh changed upstream files, preserve local-only edits, stop on a real three-way conflict, and resume an interrupted apply.

## Slice 2: GitHub and Wiki provisioning

Delivers:

- `gh auth` permission preflight;
- organization Issue Types;
- one organization Project with Ideas, Epics, and Tickets views and the fixed v1 fields;
- Wiki clone/bootstrap and immutable semantic pages;
- stable operation markers, resource adoption, collision handling, and read-after-write verification;
- recoverable Issue reservation -> Wiki commit -> Issue/Project projection;
- Project/Wiki drift detection.

Exit proof: a marked sandbox repository can be provisioned, re-planned as a no-op, interrupted after any external operation, resumed without duplicates, and inspected against the design's exact resource contract.

## Slice 3: Product context, inventory, and Ideation

Delivers:

- Product Context wizard publication;
- Product Inventory BA + Manual QA workflow and human approval gate;
- Idea schema/template/log/run pages;
- `$product-inventory`, `$ideation`, `$idea-approve`, and `$idea-revise`;
- active-Idea capacity, priority, evidence freshness, and Created-only automatic revision rules;
- compact deterministic agent context assembly.

Exit proof: a sandbox Rails application can publish an approved Inventory, generate capacity-safe evidence-backed Ideas, approve one without an LLM, and revise it as a new immutable version with an accepted human change reason.

## Slice 4: Business analysis

Delivers:

- leases, heartbeats, expiry attribution, and atomic queue claims;
- `$analyze` selection and recovery;
- bounded BA-to-Ideator clarification rounds;
- Epic and Gherkin templates;
- requirement/scenario coverage validation;
- semantic re-analysis without deleting existing Epics;
- material-ambiguity Needs human recovery.

Exit proof: two concurrent Analyze invocations claim different Ideas, publish complete immutable Epic versions with native hierarchy, and a killed run resumes without duplicate Issues or Wiki versions.

## Slice 5: Technical analysis and release qualification

Delivers:

- `$tech-analyze` selection and targeted Needs human recovery;
- current technical knowledge indexing;
- bounded TL-to-BA clarification;
- Technical Analysis and Ticket templates;
- exact scenario anchors, complete coverage, dependency DAG, and 16-hour Ticket limit validation;
- release-candidate real-agent loops and sandbox cleanup preview;
- one verified Bootcamper discovery-to-ticket cycle.

Exit proof: the highest-priority eligible Epic becomes Tech analyzed, every scenario maps to bounded acyclic Ready for backlog Tickets, all failures carry a responsible role and root cause, and the release suite passes in `LIT-Bootcamp/product-factory-sandbox` before Bootcamper verification.

## Cross-slice constraints

- Wiki artifacts remain canonical; Issues and Project fields remain projections.
- No hosted service, database, GitHub Pages, backlog delivery, implementation, or pull-request lifecycle is added in v1.
- No LLM performs selection, status transitions, claims, IDs, hashes, diffs, synchronization, validation, or log generation.
- Every external mutation is planned, marked, journaled, verified, and resumable.
- Durable artifacts are English; interactive dialogue follows the user's language.
- Production resources are never automatically deleted or force-pushed.

## Design coverage

| Design sections | Owning slice |
|---|---|
| 1-2 Purpose and principles | All slices as global constraints |
| 3-5 Distribution, setup, refresh, configuration | Slice 1 local mechanics; Slice 2 GitHub wizard and provisioning |
| 6-9 GitHub model, fields, states, Wiki | Slice 2 |
| 10 Artifact contracts | Slices 3-5 by entity type |
| 11 Product Inventory | Slice 3 |
| 12 Agents | Slices 3-5 by role |
| 13 Skill workflows | Slice 3 for product skills, Slice 4 Analyze, Slice 5 Tech Analyze |
| 14 Claims and recovery | Slice 1 operation recovery, Slice 4 entity claims, Slice 5 verification |
| 15 Accountability | Shared runtime from Slice 1, exercised by every later slice |
| 16 Token discipline | Shared deterministic-context contract, measured in Slices 3-5 |
| 17 Security and safety | Slice 1 local boundaries, Slice 2 external boundaries, regression-tested thereafter |
| 18 Testing and release gates | Per-slice CI plus final Slice 5 sandbox and Bootcamper qualification |
| 19 Version 1 boundaries | All slices; exclusions are release blockers if violated |
| 20 Design acceptance | Verified cumulatively at each exit proof |
