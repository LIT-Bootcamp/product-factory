# Product Factory v1 Design

Status: Proposed for human review
Language of durable artifacts: English
Initial platform: Ruby on Rails applications, GitHub, and Codex

## 1. Purpose

Product Factory turns product discovery into traceable, versioned delivery artifacts:

```text
IDEA -> one or more EPICs -> one or more TICKETs
```

Each phase is independently invokable and safely repeatable. Business intent remains readable by humans, technical delivery remains traceable to exact scenarios, and every mutation has an accountable actor, reason, run, and source version.

Version 1 ends when technical tickets are ready for a future backlog process. Backlog management, implementation, pull-request delivery, and full ticket QA are intentionally outside this release.

## 2. Design Principles

1. Wiki artifacts are the canonical product record.
2. GitHub Issues and Project fields are synchronized projections of that record.
3. Every published artifact has an immutable semantic version.
4. Every phase can run without requiring another phase to remain active.
5. Selection, locking, validation, publication, and recovery are deterministic Ruby operations.
6. Agents are used only where judgment or authored content is required.
7. A partial external failure is resumed, not hidden, rolled back unsafely, or duplicated.
8. Material ambiguity asks for a human; normal progress does not.
9. Failures always name the responsible role and root cause.
10. The simplest native GitHub capability is preferred over a duplicate custom model.

## 3. Distribution and Installation

### 3.1 Repositories

There are two normal repositories:

1. `LIT-Bootcamp/product-factory` is the public, versioned distribution source.
2. The application repository contains the installed runtime, configuration, skills, and agent profiles.

The application Wiki is an attached Git repository managed by GitHub. It is not treated as a third product repository in the user interface.

Application business artifacts do not live in the application source tree.

### 3.2 Release model

Product Factory publishes stable semantic versions. A project installs a pinned setup skill, for example:

```shell
gh skill install LIT-Bootcamp/product-factory factory-setup@v1.0.0 --agent codex
```

The user then invokes:

```text
$factory-setup
```

The same invocation detects whether it is an initial installation or a refresh. Refresh targets the latest stable compatible release. There is no separate major-upgrade command in v1.

### 3.3 Installed project files

Setup manages the following files in the application repository:

```text
.product-factory/
  config.yml
  installation.yml
  runtime/
  schemas/
  templates/
  spec/
.agents/skills/
  factory-setup/
  product-inventory/
  ideation/
  idea-approve/
  idea-revise/
  analyze/
  tech-analyze/
.codex/agents/
  ideator.toml
  business-analyst.toml
  technical-lead.toml
  manual-qa.toml
bin/product-factory
```

Setup never creates a branch, commit, push, or pull request. It modifies local files and authorized GitHub resources. The user reviews and commits local changes through their normal Git workflow.

### 3.4 Runtime interface

The deterministic Ruby runtime exposes:

```text
bin/product-factory doctor
bin/product-factory setup
bin/product-factory plan
bin/product-factory apply
bin/product-factory validate
bin/product-factory test
```

Skills are thin orchestration instructions around these commands and the configured agents.

## 4. Setup and Refresh

### 4.1 Wizard

Version 1 provides one interactive wizard. Automated tests drive the same interface through standard input; there is no separate non-interactive setup API.

The wizard:

1. Detects repository, organization, default branch, Rails and Ruby versions, existing skills, documentation, GitHub resources, and current installation state.
2. Asks only for information that cannot be detected safely.
3. Produces a mutation-free plan listing local files, GitHub operations, conflicts, and required permissions.
4. Requests one explicit confirmation.
5. Applies the confirmed plan and journals each operation.
6. Reads resources back, validates the installation, and runs the factory tests.
7. Shows `git diff` guidance and offers the Product Inventory phase as the next action.

### 4.2 Required product context

Setup asks for:

- product name;
- mission;
- target users;
- primary user problem;
- desired outcome;
- markets and languages;
- optional competitor seeds;
- optional constraints and non-goals.

It publishes an immutable `Product-Context-vNNN` page and updates the `Product-Context` landing page.

### 4.3 GitHub authentication and permissions

Setup uses the active `gh auth` identity. It audits required scopes and organization permissions before planning mutations. Tokens and credentials are never stored by Product Factory.

Organization ownership is required to create organization Issue Types. A missing permission is reported before apply.

### 4.4 Idempotency and resumption

Every operation has a stable operation ID and journal entry. If eight of ten external operations succeed, the next invocation verifies those eight and resumes from operation nine.

Existing resources are handled as follows:

- an exact factory marker is adopted;
- an unmarked resource with the same name is a collision and stops planning;
- adoption requires an explicit user choice;
- setup never automatically deletes or recreates an existing resource.

### 4.5 Managed-file refresh

Refresh compares the installed hash, local content, and upstream release:

- local unchanged and upstream changed: update;
- local changed and upstream unchanged: preserve;
- both changed: stop the plan and ask for `keep local`, `take upstream`, or `manual merge`;
- apply remains blocked until every conflict has a recorded resolution and reason.

New required settings are requested during refresh. Existing valid configuration is preserved.

## 5. Configuration

`.product-factory/config.yml` contains human-owned settings:

```yaml
schema_version: 1

product:
  name: Bootcamper
  context_page: Product-Context
  inventory_page: Product-Inventory
  max_active_ideas: 10

github:
  organization: LIT-Bootcamp
  repository: bootcamper
  project_title: Bootcamper Product Factory

research:
  freshness_days: 30

workflow:
  clarification_rounds: 3
  claim_lease_minutes: 60
  max_ticket_human_hours: 16

agents:
  ideator:
    model: configured-model
    reasoning: high
  business_analyst:
    model: configured-model
    reasoning: high
  technical_lead:
    model: configured-model
    reasoning: high
  manual_qa:
    model: configured-model
    reasoning: high

qa:
  local_url: http://127.0.0.1:3000
  start_command: bin/dev
  setup_command: bin/rails db:prepare
  staging_url:
  credential_env:
    student: FACTORY_STUDENT_CREDENTIALS
    mentor: FACTORY_MENTOR_CREDENTIALS
    admin: FACTORY_ADMIN_CREDENTIALS

knowledge:
  paths:
    - AGENTS.md
    - README.md
    - docs/architecture
    - Gemfile.lock
    - db/schema.rb
    - .github/workflows
```

Agent model and reasoning effort are configured exactly per role. Setup suggests currently available high-quality defaults but does not silently rewrite explicit choices.

Product Factory owns `.product-factory/installation.yml`. It records:

- installed factory version;
- installation time and actor;
- GitHub resource IDs;
- hashes of files installed by Product Factory;
- last successful setup run;
- pending resumable operations.

Manual edits to `config.yml` are allowed and validated. Manual edits to `installation.yml` are unsupported.

## 6. GitHub Domain Model

### 6.1 Project and views

Setup creates one organization-level GitHub Project titled `<Repository> Product Factory` by default. It contains three views:

- Ideas;
- Epics;
- Tickets.

The application repository uses organization-wide Issue Types:

- `Idea`;
- `Epic`;
- `Ticket`.

Every entity is a full GitHub Issue. Native parent/sub-issue relations define:

```text
IDEA parent -> EPIC children -> TICKET children
```

Native GitHub issue dependencies define `blocked by` and `blocking`. The factory does not create duplicate dependency text fields. Dependency cycles fail validation and block publication.

### 6.2 Stable identifiers

The GitHub Issue number is the stable numeric identity:

```text
Issue #141 with type Idea   -> IDEA-141
Issue #142 with type Epic   -> EPIC-142
Issue #143 with type Ticket -> TICKET-143
```

Numbers are shared across issue types, so gaps are expected and valid.

### 6.3 Canonical and projected state

Wiki content and logs are canonical. Issues and Project fields are projections.

Because GitHub Issue, Wiki Git, and Project mutations cannot be transactional, publication is recoverable:

1. The Issue is created to reserve its number and stable ID.
2. The immutable canonical Wiki version is committed.
3. The Issue body and Project fields are synchronized.
4. An incomplete run resumes missing projections without creating a second entity.

Issue bodies are useful mirrors, not link-only placeholders. They include:

- stable ID and version;
- summary and observable outcome;
- scenario or technical detail appropriate to the type;
- parent and dependencies;
- exact immutable Wiki link;
- hidden Product Factory identity marker.

Factory-managed Wiki pages and Project fields must not be edited manually. Detected drift is either restored from canonical state or escalated when restoration would overwrite an unrecognized change.

## 7. Project Fields

Common managed fields:

- Status
- Priority
- Created At
- Human Approved At
- Analysis Started At
- Analyzed At
- Tech Analysis Started At
- Tech Analyzed At
- Blocked At
- Needs Human At
- Superseded At
- Created By
- Approved By
- Analyzed By
- Tech Analyzed By
- Source
- Source Version
- Factory Run
- Active Run
- Claim Expires At
- Human Estimate Hours
- AI Estimate Hours
- Duration Minutes
- Tokens Used
- Run Count
- Failure Count
- Last Failure Owner
- Last Failure At

Idea scoring fields:

- User Value
- Business Value
- Progressiveness
- Strategic Fit
- Urgency
- Evidence Confidence
- Research Verified At

Issue Type, Parent, sub-issue progress, dependencies, assignees, and linked pull requests use native GitHub features.

Primary views hide audit and metric fields. Dedicated table and insights views may expose them.

Priority ranges from `P1` (highest) to `P10` (lowest). Equal-priority work is selected oldest first. Blocked work is never selected.

Timestamp fields describe the entity event without repeating its type: `Created At`, not `Idea Created At`. `Created At` and `Human Approved At` preserve their first occurrence. Analysis timestamps represent the latest current run; immutable logs retain the complete history.

Actor values use:

- agent: `<role>:<runtime-agent-id>`;
- human: authenticated GitHub login.

Exact metrics are recorded when available. Unknown token usage is stored as `unknown`; it is never estimated.

## 8. Status Model

The Project uses this fixed v1 status set:

- Created
- Human approved
- Draft
- Analyzing
- Analyzed
- Tech analyzing
- Tech analyzed
- Ready for backlog
- Done
- Blocked
- Needs human
- Superseded

Normal lifecycles:

```text
IDEA:   Created -> Human approved -> Analyzing -> Analyzed -> Done
EPIC:   Draft -> Analyzing -> Analyzed -> Tech analyzing -> Tech analyzed -> Done
TICKET: Ready for backlog
```

`Blocked`, `Needs human`, and `Superseded` are exceptional states.

An Epic becomes Done when all its Tickets are Done. An Idea becomes Done when all its Epics are Done. Ticket states after `Ready for backlog` belong to the later backlog and implementation design.

Active Ideas are in Created, Human approved, Analyzing, Analyzed, Blocked, or Needs human. Done and Superseded are inactive.

`max_active_ideas` defaults to 10. If eight Ideas are active, Ideation may create at most two. Updating an existing Created Idea does not consume another slot. At capacity, Ideation researches and updates eligible Created Ideas or returns a no-op. Blocked and Needs human Ideas still consume capacity.

## 9. Wiki Information Architecture

The factory manages these page families:

```text
Home
_Sidebar
Product-Context
Product-Context-v001
Product-Inventory
Product-Inventory-v001

Ideas
IDEA-141
IDEA-141-v001
IDEA-141-Log
IDEA-141-Analysis-RUN-...

Epics
EPIC-142
EPIC-142-v001
EPIC-142-Log
EPIC-142-Tech-Analysis-v001
EPIC-142-Tech-Communication-RUN-...

Tickets
TICKET-143
TICKET-143-v001
TICKET-143-Log

Research
RESEARCH-competitor-slug-date

Factory-Runs
RUN-...
Setup-Log
```

Landing pages are mutable projections of the current version. `vNNN` pages are immutable. Entity logs are append-only. A run page becomes immutable when the run finishes. Index pages and `_Sidebar` are generated deterministically.

Communication uses one page per analysis run, with numbered question-and-answer rounds, decisions, resolved and open items, assumptions, and outcome. It does not create a page per message.

Wiki Git history is useful audit evidence but does not replace explicit semantic version pages.

Every Gherkin scenario has its own Markdown heading and fenced Gherkin block, allowing a Ticket to link to an exact anchor in an immutable Epic version. Scenario identity is unique within an Epic, for example `EPIC-142/SCENARIO-002`.

## 10. Artifact Contracts

### 10.1 Idea

An Idea version contains:

1. Metadata: ID, version, status, creator, time, run, and change reason.
2. Summary.
3. User Problem.
4. Proposed Experience: high-level end-to-end behavior without technical design.
5. User Value.
6. Business Value.
7. Why Now.
8. Existing Product Fit.
9. Competitor Research: competitor, capability, evidence URL, verification time.
10. Differentiated Proposal.
11. Evidence and Expected Reach: measured reach and horizon, with assumptions labeled.
12. Priority `P1` to `P10`, rationale, and dependencies.
13. Six score values.
14. Success Signals.
15. Dependencies.
16. Assumptions.
17. Risks and Open Questions.
18. Non-goals.

Ideas contain no architecture, database, API, or library decisions.

External claims require a source URL and verification time. Research is fresh for 30 days by default. Stable official product mission statements are exempt from freshness expiry.

### 10.2 Epic and Gherkin

An Epic version contains:

1. Metadata and parent Idea.
2. Business Goal.
3. Scope.
4. Actors.
5. Preconditions.
6. Numbered Business Rules such as `REQ-001`.
7. Gherkin scenarios.
8. Requirement Coverage table.
9. Dependencies.
10. Assumptions.
11. Clarification Decisions with transcript links.
12. Non-goals.

Each scenario uses:

````markdown
### SCENARIO-001 — Descriptive outcome

Requirements: REQ-001
Tags: @student @happy_path

```gherkin
Scenario: Descriptive outcome
  Given ...
  When ...
  Then ...
```
````

Every requirement maps to at least one scenario, and every scenario maps to an in-scope requirement.

### 10.3 Technical analysis

The Technical Analysis contains:

1. Metadata and exact source Epic version.
2. Technical Problem.
3. Current Architecture.
4. Proposed Approach.
5. Key Decisions and Trade-offs.
6. Security and Privacy.
7. Data and Concurrency.
8. Delivery and Operations.
9. Risks and Challenges.
10. Estimate ranges: human ideal days and AI wall-clock hours, with assumptions.
11. Ticket Decomposition table with outcome, scenarios, dependencies, human days, and AI hours.
12. Complete scenario Coverage.
13. Acyclic Delivery Order.
14. Open Questions.

Security, privacy, data, concurrency, operations, and accessibility are considered explicitly; `Not applicable` is valid when justified.

### 10.4 Ticket

A Ticket version contains:

1. Metadata, parent Epic, priority, and run.
2. Business Context.
3. Observable Outcome.
4. Scenario Traceability table with exact clickable immutable Wiki anchors.
5. Current Behavior.
6. Required Behavior, including success, failure, and boundary behavior.
7. Acceptance Criteria.
8. Technical Details.
9. Change Surface.
10. Data, Security, and Concurrency.
11. UI and Accessibility, or a justified `Not applicable`.
12. Testing Requirements.
13. Definition of Done.
14. Native Dependencies.
15. Human and AI estimate ranges in hours.
16. Risks.
17. External Actions.
18. Assumptions and Open Questions.
19. Out of Scope.

Definition of Done requires evidence for each criterion, automated tests, repository quality gates, browser verification for visible UI, independent review with no unresolved blockers, and linked Ticket and pull request where applicable.

A Ticket human estimate may not exceed 16 hours. Larger work must be split. Epic summaries use human ideal days.

## 11. Product Inventory Gate

Ideation cannot run until a human-approved Product Inventory exists.

`$product-inventory` performs:

1. The Business Analyst reads Product Context and existing product documentation.
2. Manual QA starts the configured application and verifies observable flows in a browser for student, mentor, and admin roles.
3. The Business Analyst combines documentary and observed evidence.
4. A human reviews the inventory.
5. The runtime publishes `Product-Inventory-vNNN` and updates the landing page.

Each capability records:

- status: Implemented, Partial, or Absent;
- actors;
- business behavior;
- entry point;
- evidence;
- gaps;
- last verification time.

Manual QA reports rendered behavior. The inventory avoids treating controllers or models as proof of user capability. Partial behavior is described exactly. Secrets are never copied into artifacts. Inventory refresh is manually invoked in v1.

## 12. Agents

### 12.1 Ideator

The Ideator is business-only. It knows the Product Context, approved Product Inventory, high-level active and completed Ideas and Epics, competitor evidence, and dependencies. It researches user and business value, priority, urgency, differentiation, and expected reach. Unverified conclusions are labeled assumptions. It never inspects implementation code or proposes technical architecture.

### 12.2 Business Analyst

The Business Analyst owns Epic scope and Gherkin. It decomposes each Idea into one or more coherent Epics, explores happy paths, failure paths, boundaries, permissions, lifecycle states, and cross-feature effects, and maintains complete requirement coverage. It asks the Ideator consolidated, precise questions when business intent is ambiguous. Only the Business Analyst may revise BA-owned artifacts in response to Technical Lead trade-offs.

### 12.3 Technical Lead

The Technical Lead reads an exact Epic version, configured knowledge files, and the current application architecture. It identifies ambiguity, reuse opportunities, delivery trade-offs, security risks, operational concerns, estimates, an acyclic delivery order, and bounded Tickets with complete scenario coverage. It applies KISS, SOLID, YAGNI, and DRY without inventing speculative infrastructure.

### 12.4 Manual QA

Manual QA is used for Product Inventory in v1. It configures and exercises the real application, verifies role-based behavior in a browser, records repeatable evidence, and distinguishes observed behavior from assumptions. Full Ticket QA belongs to the later delivery release.

Agent profiles are generic and factory-managed. Project-specific context is assembled for each invocation. Each role has an independently configurable exact model and reasoning effort.

## 13. Skill Workflows

### 13.1 `$ideation`

1. Acquire the singleton global Ideation lease.
2. Read Product Context, approved Inventory, active Idea summaries, capacity, dependencies, and fresh research.
3. Calculate remaining Idea slots.
4. Invoke one Ideator with the bounded context.
5. Research competitors and user needs, compare candidates with existing Created Ideas, and rank them.
6. Validate all proposed artifacts.
7. Create Issues to reserve stable IDs, publish Wiki versions, and synchronize the Project.
8. Release the lease and finish with Success, No-op, Needs human, or Failed.

Ideation asks no human questions. It may automatically modify only Created Ideas. For Human approved, Analyzing, or Analyzed Ideas it may log a proposed research change, but scope or priority changes require `$idea-revise`. Reaching capacity is a valid no-op.

### 13.2 `$idea-approve IDEA-ID`

1. Require the Idea to be Created and complete.
2. Resolve the current human from `gh auth`.
3. Show the exact version being approved.
4. Request explicit confirmation.
5. Publish the approval version and update status, actor, and timestamp.

This workflow is deterministic and does not spawn an agent. It does not automatically run Analyze.

### 13.3 `$idea-revise IDEA-ID`

1. Load the current immutable version and human feedback.
2. Start an interactive, delta-focused Ideator discussion.
3. Record the transcript and proposed changes.
4. Publish nothing until the human explicitly accepts the revision.
5. Validate and publish a new version with a required change reason.

Status after revision:

- Created remains Created;
- Human approved remains Human approved;
- an active Analyze run consumes the newest accepted version;
- Analyzed returns to Human approved;
- Needs human returns to Human approved after resolution;
- Done and Superseded cannot be revised.

Existing Epics are never deleted. A later Analyze performs a semantic diff and creates or revises only affected artifacts.

### 13.4 `$analyze`

1. Recover expired claims.
2. Select the highest-priority, oldest, unblocked Human approved Idea.
3. Atomically claim it and set Analyzing, Analyzed By, Analysis Started At, Active Run, and Claim Expires At.
4. Bind the run to the newest accepted Idea version.
5. Invoke the Business Analyst and Ideator with bounded context.
6. The Business Analyst assesses completeness and, when needed, sends one consolidated numbered question set per round.
7. After no more than three rounds, produce one or more Epic drafts, detailed Gherkin, and coverage.
8. Create Epic Issues, publish canonical versions, set native parent and dependencies, and synchronize projections.
9. Set each Epic to Analyzed and the Idea to Analyzed.

The Business Analyst owns all output; the Ideator only answers product questions. Multiple invocations may analyze different Ideas in parallel. If no eligible Idea exists, the result is No-op.

After the final clarification round, explicit assumptions are used where safe. Material ambiguity publishes recoverable drafts and moves the Idea to Needs human. `$idea-revise` resolves it; the next Analyze reuses those drafts instead of starting over.

### 13.5 `$tech-analyze`

1. Recover expired claims.
2. Select the highest-priority, oldest, unblocked Analyzed Epic.
3. Atomically claim it and set Tech analyzing, Tech Analyzed By, Tech Analysis Started At, Active Run, and Claim Expires At.
4. Bind the run to the exact current Epic version.
5. Invoke the Technical Lead with that Epic, current configured knowledge, a relevant architecture and code index, and prior decisions.
6. The Technical Lead may send the Business Analyst one consolidated numbered question set per round, for at most three rounds.
7. The Business Analyst alone revises business scenarios when an accepted trade-off requires it.
8. The Technical Lead writes the Technical Analysis and bounded Tickets.
9. Create Ticket Issues, insert exact immutable scenario links, validate complete coverage, estimate limits, and the dependency DAG.
10. Publish and set Tickets to Ready for backlog and the Epic to Tech analyzed.

Normal `$tech-analyze` takes no ID and claims the next eligible Epic. `$tech-analyze EPIC-ID` exists only to recover a Needs human Epic after the required decision. Multiple invocations may process different Epics in parallel.

Material unresolved ambiguity preserves drafts and moves the Epic to Needs human. A new Epic version is the only business-source event that requires Technical Analysis to rerun. The Technical Lead always reads current technical knowledge at run time; v1 does not maintain knowledge fingerprints.

## 14. Claims, Concurrency, and Recovery

One invocation claims one item. Parallel sessions claim different items.

A claim records:

- run ID;
- agent ID;
- claimed time;
- heartbeat time;
- expiry time.

Claims are renewable and expire after 60 minutes by default. Wiki publication uses Git compare-and-swap against the expected head. A competing update causes a semantic retry; it never force-pushes.

An expired run is marked Failed with attribution before a later invocation recovers its work. Recovery reuses reserved Issues, published immutable pages, and completed operations.

Run lifecycle:

```text
Planned -> Running -> Success | No-op | Needs human | Failed
```

Each immutable run page records:

- phase;
- source entity and version;
- agent, model, and reasoning effort;
- start and finish times;
- claim details;
- compact input summary;
- outputs;
- planned and completed operations;
- exact metrics;
- clarification rounds;
- final status;
- failure root-cause record when applicable.

Transient network failures use bounded retries and respect GitHub `Retry-After`. Validation failures publish nothing and return the artifact to the same responsible agent for correction within the run. Source changes before claim consume the newest accepted version. Success and No-op release their claims.

## 15. Accountability

Every failure record must include:

- `failed_rule`;
- `responsible_role`;
- `responsible_agent_id`;
- `root_cause`;
- `impact`;
- `recovery_action`;
- `process_change_required`.

The Project stores the latest failure owner and time. The immutable run page stores the full record. Descriptions such as “mistakenly remained ready” without a responsible role and root cause are invalid.

Configuration, permission, runtime, agent, validation, external service, and human-decision failures are attributed to the component or actor that violated the documented rule, not automatically to the agent visible at the end of the workflow.

## 16. Token and Cost Discipline

Architecture:

```text
Skill -> Ruby builds compact context -> agent authors/judges -> Ruby validates and publishes
```

No language model is used for:

- setup and refresh mechanics;
- status transitions;
- queue selection;
- claims and heartbeats;
- stable IDs;
- hashes and diffs;
- logs and generated indexes;
- GitHub synchronization;
- schema, coverage, estimate, or DAG validation.

Agent contexts are bounded:

- Ideator: Product Context, approved Inventory, active summaries, and fresh research;
- Business Analyst: one Idea, relevant existing Epic summaries, and new deltas;
- Technical Lead: one exact Epic, Gherkin, configured knowledge index, and relevant code;
- Manual QA: configured flows and environment.

Unchanged content is eliminated by hashes before agent invocation. Clarification stays in one thread and sends deltas. External research is cached until its freshness window expires. Metadata, links, fields, logs, and indexes are generated by Ruby.

The runtime records context size, model, duration, and exact token usage when available. Version 1 measures real use before introducing hard token budgets.

## 17. Security and Safety

The runtime:

- allowlists configured organization and repository IDs;
- verifies factory markers and operation IDs before mutation;
- never force-pushes or rewrites Wiki history;
- never automatically deletes production resources;
- supports deletion only for marked sandbox resources after an exact preview and separate confirmation;
- passes command arguments without shell interpolation;
- writes local files atomically;
- performs permission preflight and read-after-write verification;
- redacts secrets and credentials from logs and agent contexts;
- stores credential environment-variable names, never values;
- resolves human identity from authenticated GitHub state.

## 18. Testing and Release Gates

Every Product Factory pull request runs:

- Ruby runtime unit tests;
- schema and template contract tests;
- state-machine tests;
- claim and concurrency tests;
- Wiki semantic merge tests;
- GitHub operation-plan tests;
- setup and refresh migration tests;
- interrupted-operation resume tests;
- factory-file conflict tests;
- a simulated zero-LLM end-to-end flow.

Skills use RED/GREEN pressure tests that first demonstrate a contract failure and then verify the corrected instruction.

Release candidates run against the dedicated private repository `LIT-Bootcamp/product-factory-sandbox`. An organization owner creates the repository and its first Wiki `Home` page once:

1. empty Rails project setup;
2. setup no-op;
3. refresh from an older release;
4. factory-file conflict;
5. interrupted apply and resume;
6. Product Inventory;
7. Ideation;
8. Idea approval;
9. two parallel Analyze invocations;
10. Tech Analyze;
11. drift detection and restoration;
12. cleanup preview.

Every sandbox resource carries a `sandbox:run` marker. Successful run resources may be removed only after a separate exact cleanup preview and confirmation. Failed-run resources are preserved for diagnosis.

Real agent loops run only for release candidates and record cost and regression evidence. After sandbox success, one full cycle is verified in Bootcamper before release promotion.

## 19. Version 1 Boundaries

Version 1 includes:

- setup and refresh;
- Product Context and Inventory;
- Ideation, approval, and revision;
- business analysis into Epics and Gherkin;
- technical analysis into bounded Tickets;
- Wiki, Issue, and Project synchronization;
- audit, claims, recovery, validation, and release testing.

Version 1 deliberately excludes:

- Project Manager backlog reconciliation;
- Engineer implementation;
- pull-request lifecycle and merging;
- Ticket execution status design after Ready for backlog;
- complete per-Ticket Manual QA;
- integrations other than GitHub, Codex, and Rails;
- a hosted Product Factory service or database;
- GitHub Pages publication;
- automatic Product Inventory refresh;
- knowledge fingerprints and speculative invalidation logic.

These are separate designs added only when the v1 discovery-to-ticket loop is proven in real use.

## 20. Acceptance of the Design

The design is ready for implementation planning when a reviewer can answer yes to all of the following:

- Can every Idea, Epic, Ticket, version, scenario, dependency, actor, and run be traced without reading application source?
- Can every phase be invoked independently and return a correct Success, No-op, Needs human, or Failed result?
- Can an interrupted cross-system publication resume without duplicates or data loss?
- Can two sessions safely process different eligible entities?
- Does every failure name the violated rule, owner, root cause, impact, and recovery?
- Are agent inputs bounded and deterministic work kept outside the model?
- Can setup and refresh be previewed, confirmed once, repeated safely, and audited?
- Does Technical Analysis prove complete scenario coverage and bounded acyclic Tickets?
- Are all v1 exclusions explicit enough to prevent accidental implementation?
