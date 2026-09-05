# Product Factory GitHub and Wiki Provisioning Design

**Status:** Approved in conversation

**Date:** 2026-09-05

**Scope:** Product Factory roadmap Slice 2

## Purpose

Extend the existing local Product Factory setup so one command safely provisions the GitHub and Wiki infrastructure required by later product phases.

The result is an idempotent setup flow that:

- creates or refreshes the factory's organization Issue Types;
- creates or refreshes one private organization Project and its three views;
- links the Project to the application repository;
- creates or refreshes factory-owned Wiki navigation and index pages;
- previews every mutation and asks for one confirmation;
- resumes interrupted runs without duplicating resources;
- produces machine-readable recovery state and concise human-readable output;
- uses no language model and therefore no model tokens.

## Scope Boundaries

This slice provisions infrastructure only. It does not:

- create the application repository;
- initialize an empty GitHub Wiki;
- publish Product Context, Product Inventory, Ideas, Epics, or Tickets;
- run Ideator, Business Analyst, Technical Lead, or other agents;
- implement backlog or delivery lifecycle states after `Ready for backlog`;
- delete GitHub resources, rename foreign resources, change repository visibility, or make a Project public;
- modify the existing `LIT-Bootcamp` Project named `Bootcamper Product Delivery`.

The application repository must already exist. GitHub requires a Wiki's first page to be created through the web interface before its Git repository can be cloned. When the Wiki is empty, setup stops before all mutations and prints one exact instruction: create `Home`, then rerun setup.

## User Interface

The normal entry point is:

```sh
product-factory setup
```

The same command handles first installation and later refreshes. A separate `setup refresh` command is unnecessary: current state plus the versioned desired schema determines the semantic diff.

Setup detects the repository, organization, default branch, active GitHub identity, current installation, and existing resources. It asks only for required values that cannot be detected safely. If configuration does not exist, the answers are held in memory and included in the plan; setup writes nothing before confirmation.

The existing low-level `plan` and `apply` commands remain available for diagnosis and recovery. Normal users do not need to call them.

Adoption is explicit and resource-specific:

```sh
product-factory setup --adopt project
product-factory setup --adopt issue-type:Idea
product-factory setup --adopt wiki:_Sidebar
```

`--adopt` may be repeated. It applies only to the exact named resource shown in the preceding collision report. It is not a global force option.

## Execution Flow

```text
setup
  -> preflight
  -> local + GitHub + Wiki planners
  -> one immutable Plan
  -> human-readable preview
  -> one confirmation
  -> existing Executor and Journal
  -> read-after-write verification
  -> installation checkpoint and run summary
```

### Preflight

Preflight performs no mutations. It:

1. validates the target repository and existing local Product Factory state;
2. resolves the configured organization and repository against the current checkout;
3. checks `gh auth` and the permissions required for organization Issue Types and Projects;
4. reads existing Issue Types, Projects, fields, options, views, and repository links;
5. verifies that the Wiki can be cloned and already contains `Home`;
6. detects collisions, drift, and requested adoptions;
7. builds and validates the complete plan.

Any preflight failure stops before local, GitHub, Project, or Wiki mutation.

### Preview and confirmation

The preview groups operations by destination and uses concrete verbs:

```text
Local files
  CREATE .product-factory/config.yml

GitHub organization
  CREATE issue type Idea

GitHub Project
  CREATE Bootcamper Product Factory (private)
  CREATE field Priority

Wiki
  CREATE _Sidebar
```

It also shows adoptions, conflicts, and the reason for every update. One `yes` confirms the exact serialized plan. A changed resource invalidates that plan instead of silently applying stale intent.

### Apply order

Operations run in this order:

1. organization Issue Types;
2. private organization Project and application-repository link;
3. Project fields and select options;
4. Project views;
5. factory-owned Wiki pages and `_Sidebar`;
6. local installation state and final run event.

Every external write is immediately read back and compared with the desired state. A verification failure stops later operations.

## Architecture

The new behavior extends the existing `Plan -> confirmation -> Executor -> Journal` flow.

```text
Setup::Runner
  |-- FileSync::Planner
  |-- GitHub::Planner -- GitHub::Client -- gh api
  `-- Wiki::Planner   -- Wiki::Repository -- git
             |
             v
       one Plan
             |
             v
   existing Executor + Journal
```

### Components

`GitHub::Client` is the only production object that invokes `gh`. It passes argument arrays without user-controlled shell interpolation, parses JSON into Ruby hashes, redacts errors, and normalizes API failures.

`GitHub::Planner` reads remote state through the client and emits ordinary Product Factory operations for missing or outdated resources. It does not mutate GitHub.

One versioned YAML manifest holds Issue Type definitions, Project visibility, field types and options, view definitions, and factory markers. Ruby code does not scatter resource names or workflow options across classes.

`Wiki::Repository` handles clone, fetch, compare, commit, and push with ordinary Git. It never force-pushes or rewrites history.

`Wiki::Planner` compares the desired factory-owned pages with the current Wiki checkout and emits ordinary operations. It does not perform Git mutations.

The existing setup plan builder merges local, GitHub, and Wiki operations. The existing operation, plan, executor, journal, installation, service, and shell abstractions are reused. There is no provider framework, Octokit dependency, second executor, or second recovery system.

`gh api` is the transport because the required resources span current REST and GraphQL APIs and the active `gh auth` identity already supplies authentication. Octokit would still require generic REST and GraphQL calls while adding another dependency and credential path.

## Resource Model

### Visibility

- The application repository remains at its existing visibility.
- The Product Factory Project is always private.
- The dedicated `LIT-Bootcamp/product-factory-sandbox` integration repository is private.
- Setup never changes a repository's visibility and never makes a Project public.

### Organization Issue Types

Product Factory requires these organization-wide Issue Types:

- `Idea` — a high-level product opportunity with measurable user or business value;
- `Epic` — a coherent business capability and its observable scenarios;
- `Ticket` — an independently deliverable technical change.

Missing types are created once. Exact factory-owned types are reused. A same-name unmarked type is a collision until explicitly adopted. Setup never renames or deletes an Issue Type.

### Project and views

Setup creates or adopts one private organization Project named `<Repository> Product Factory` by default. It links that Project to the application repository and creates three table views:

| View | Semantic filter |
|---|---|
| Ideas | Issue Type is `Idea` |
| Epics | Issue Type is `Epic` |
| Tickets | Issue Type is `Ticket` |

These are views of one Project, not three Projects.

The primary views expose only useful working columns. Audit and metrics fields remain available but hidden from the primary views.

### Native GitHub data

The factory uses native GitHub features for:

- Issue Type;
- assignees;
- parent and sub-issues;
- sub-issue progress;
- blocked-by and blocking relationships;
- linked pull requests.

No custom fields duplicate those values.

### Managed fields

The versioned manifest defines the following Project fields.

| Group | Fields | Type |
|---|---|---|
| Workflow | `Status`, `Priority` | Single select |
| Lifecycle | `Created At`, `Human Approved At`, `Analysis Started At`, `Analyzed At`, `Tech Analysis Started At`, `Tech Analyzed At`, `Blocked At`, `Needs Human At`, `Superseded At` | Date |
| Actors | `Created By`, `Approved By`, `Analyzed By`, `Tech Analyzed By` | Text |
| Traceability | `Source`, `Factory Run`, `Active Run` | Text |
| Traceability | `Source Version` | Number |
| Claim | `Claim Expires At` | Date |
| Estimates and metrics | `Human Estimate Hours`, `AI Estimate Hours`, `Duration Minutes`, `Tokens Used`, `Run Count`, `Failure Count` | Number |
| Failure | `Last Failure Owner` | Text |
| Failure | `Last Failure At` | Date |
| Idea scoring | `User Value`, `Business Value`, `Progressiveness`, `Strategic Fit`, `Urgency`, `Evidence Confidence` | Number |
| Research | `Research Verified At` | Date |

An unavailable numeric metric remains blank in the Project and is recorded as `unknown` in the immutable run record.

`Priority` contains `P1` through `P10`; `P1` is highest. Equal-priority queue selection is oldest first, and blocked items are ineligible.

`Status` contains:

- `Created`
- `Human approved`
- `Draft`
- `Analyzing`
- `Analyzed`
- `Tech analyzing`
- `Tech analyzed`
- `Ready for backlog`
- `Done`
- `Blocked`
- `Needs human`
- `Superseded`

Timestamp names describe the event without repeating the entity type: `Created At`, not `Idea Created At`.

## Wiki Ownership

The manually initialized `Home` page is human-owned and is never rewritten by setup.

Setup owns only these pages:

- `_Sidebar`
- `Setup-Log`
- `Ideas`
- `Epics`
- `Tickets`
- `Research`
- `Factory-Runs`

Every owned page contains a hidden Product Factory marker. `_Sidebar` links the owned indexes while leaving `Home` as the Wiki landing page.

A pure no-op setup does not create a Wiki commit merely to record that nothing changed. The local journal records the no-op and the CLI reports it. `Setup-Log` records successful mutating setup runs and failures that occur after the Wiki is available.

Product Context and Product Inventory pages belong to later roadmap slices.

## Identity, Adoption, and Drift

Top-level resources use stable Product Factory markers where GitHub supports descriptions or page content. Nested Project resources are identified by the marked Project ID, their semantic key, and the IDs stored in installation state.

The rules are:

- a resource with the expected marker and compatible shape is reused automatically;
- an unmarked same-name resource is a collision;
- a collision is adopted only through its exact `--adopt` key and the confirmed preview;
- an adopted resource receives a marker when the platform supports one;
- a resource with an incompatible type, options, visibility, or ownership is a conflict with a semantic diff;
- setup never resolves a conflict by deleting or recreating the resource.

Refresh uses the same three-way rule as local factory files:

- remote equals installed and desired changed: update;
- remote changed and desired equals installed: preserve the external change and report drift;
- remote and desired both changed: conflict requiring an explicit resolution;
- current state already equals desired: no operation.

## Recovery and Concurrency

Each operation has a stable ID derived from its action, semantic resource key, and desired-state digest. Each operation also has an expected remote fingerprint captured during planning.

The executor records the start of an operation, applies it, reads the resource back, and then records completion. If the process dies after the remote write but before completion is journaled, the next run discovers the marker or exact nested resource, verifies it, and continues without creating a duplicate.

If remote state changes between plan and apply, the expected fingerprint fails and setup stops with a conflict. It does not overwrite concurrent work.

External operations are not rolled back. Automatic rollback could destroy a valid resource created or modified concurrently. A later `setup` resumes from verified state.

The final installation file is written atomically after all external resources verify successfully. It records the factory version, GitHub resource IDs, desired and installed fingerprints, and the last successful setup run.

## Errors and Accountability

Every failure record contains:

- operation ID when one exists;
- failed rule;
- responsible component or actor;
- root cause;
- impact;
- exact recovery action.

Setup does not invent an agent identity when no agent participated. Examples include the Product Factory release for an invalid manifest, the authenticated operator for missing permissions, the Wiki prerequisite for an uninitialized Wiki, or GitHub for a failed external request. Secrets, tokens, and credential values are redacted.

Failures are written to the local JSONL journal and CLI output immediately. Failure handling does not attempt another external mutation. The next successful mutating setup publishes any unpublished failure summaries to `Setup-Log`. JSONL is the durable recovery state; Markdown is the human-readable summary.

## Security

The runtime:

- allowlists the configured organization and repository before mutation;
- uses the active `gh auth` identity and never stores its token;
- invokes commands with argument arrays rather than interpolated user input;
- verifies markers, parent IDs, operation IDs, and expected fingerprints;
- verifies that the resulting Project is private;
- never changes repository visibility;
- never deletes production resources;
- never force-pushes or rewrites Wiki history;
- redacts credentials and tokens from plans, journals, and errors;
- writes local state atomically.

## Testing and Release Gate

All automated tests use RSpec.

The normal test suite contains:

1. unit specs for GitHub planning, schema comparison, markers, collisions, adoption, ordering, and error redaction;
2. unit specs for Wiki planning, ownership, three-way comparison, and Git conflict handling;
3. an integration spec that drives the real CLI against a fake GitHub command boundary;
4. recovery specs that interrupt runs after external writes and prove idempotent resume;
5. regression coverage for the existing local setup and refresh behavior.

Normal CI performs no live GitHub mutations.

A manual RSpec gate targets the private `LIT-Bootcamp/product-factory-sandbox` repository. An organization owner creates that repository and its initial human-owned `Home` Wiki page once; Product Factory does not create either. The operator must explicitly enable the live example and confirm its mutation preview. The gate:

- creates missing factory resources on its first run;
- verifies all resources are private and linked correctly;
- verifies the exact Issue Types, fields, options, views, Wiki pages, and markers;
- reruns setup and proves zero planned operations;
- confirms the sandbox repository's human-owned `Home` page is unchanged.

Interrupted-run and collision cases remain deterministic local integration specs; the live gate does not manufacture destructive organization drift.

## Acceptance Criteria

1. `product-factory setup` is the only command required for initial setup and refresh.
2. Setup performs no mutation before displaying the complete plan and receiving one `yes`.
3. An uninitialized Wiki stops setup before all mutations with an exact one-time instruction.
4. Missing Issue Types, one private Project, fields, options, views, repository link, and owned Wiki pages are created in the documented order.
5. The existing `Bootcamper Product Delivery` Project is never modified.
6. A second unchanged setup produces no operations and no Wiki commit.
7. Same-name foreign resources require exact explicit adoption.
8. Interrupted setup resumes without duplicate resources.
9. Concurrent drift invalidates a stale plan rather than overwriting it.
10. Every external write is read back and verified.
11. Errors identify the responsible component or actor, root cause, impact, and recovery action without exposing secrets.
12. Normal CI passes without GitHub credentials or network mutations.
13. The manual live RSpec gate passes against the private sandbox.
14. Setup invokes no LLM and uses zero model tokens.

## References

- [GitHub REST API: Organization issue types](https://docs.github.com/en/rest/orgs/issue-types)
- [GitHub: Managing issue types in an organization](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/managing-issue-types-in-an-organization)
- [GitHub REST API: Project views](https://docs.github.com/en/rest/projects/views)
- [GitHub GraphQL API: Projects](https://docs.github.com/en/graphql/reference/projects)
- [GitHub: Adding or editing Wiki pages](https://docs.github.com/en/communities/documenting-your-project-with-wikis/adding-or-editing-wiki-pages)
