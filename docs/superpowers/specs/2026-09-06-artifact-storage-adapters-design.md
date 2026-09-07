# Product Factory Artifact Storage Adapters

**Date:** 2026-09-06

**Status:** Approved for implementation planning

## Context

Product Factory currently treats a GitHub Wiki as the canonical product record. Private Wikis require a paid GitHub organization plan, so the private Product Factory sandbox cannot use that storage without upgrading the organization.

Canonical artifacts must remain readable, versioned, traceable, and independent from GitHub Issues and Projects. The storage location must also be replaceable without changing setup or future factory phases.

## Decision

Introduce one storage-neutral artifact planner and two working storage adapters:

- `repository`, the default, stores Markdown under `product/` in the application checkout;
- `wiki` preserves the existing Git-backed GitHub Wiki integration for repositories where Wiki is available.

Configuration selects the adapter:

```yaml
product:
  context_document: context
  inventory_document: inventory

artifacts:
  adapter: repository
  root: product
```

`root` applies only to the repository adapter. It must be a safe relative path inside the application checkout.
Product configuration uses logical document IDs rather than adapter-specific page names.

The repository adapter only reads and writes the current checkout. It never commits, pushes, creates a branch, or opens a pull request. The delivery workflow owns those Git operations after a successful factory phase.

## Architecture

```text
Setup and future factory phases
              |
       Artifacts::Planner
              |
        artifact_store
         /          \
 Repository          Wiki
  adapter            adapter
```

`Artifacts.build` selects an adapter with a small `case` statement. There is no registry, plugin system, abstract base class, or provider SDK.

The setup workflow depends on an `artifact_store`, not a Wiki repository. Both adapters support the setup behavior currently required:

- `snapshot`
- `apply`
- `matches?`
- `revision`
- `document_hashes`

Ruby duck typing is the adapter contract. Readable adapter specs verify equivalent behavior. Methods such as `read`, `write`, or `link` will be added only when a product phase requires them.

The existing `Wiki::Planner` becomes the storage-neutral `Artifacts::Planner`. The existing Git-backed Wiki repository becomes the Wiki adapter. Setup parameters, operation handlers, preview labels, validation, installation state, and accountability messages use artifact terminology.

## Logical Documents

The planner operates on stable document IDs. Adapters alone translate IDs into physical locations.

| Document ID | Repository adapter | Wiki adapter |
|---|---|---|
| `index` | `product/README.md` | `Product-Factory.md` |
| `setup-log` | `product/setup-log.md` | `Setup-Log.md` |
| `ideas/index` | `product/ideas/README.md` | `Ideas.md` |
| `epics/index` | `product/epics/README.md` | `Epics.md` |
| `tickets/index` | `product/tickets/README.md` | `Tickets.md` |
| `research/index` | `product/research/README.md` | `Research.md` |
| `factory-runs/index` | `product/factory-runs/README.md` | `Factory-Runs.md` |

The configured repository root replaces `product` in the repository paths above. Document IDs never contain adapter-specific paths or page names.

The old Wiki `_Sidebar` is not a canonical artifact. Refresh stops managing it but does not delete or modify it.

## Setup Flow

1. Load and validate configuration before mutation.
2. Select the configured artifact adapter.
3. Read the GitHub and artifact snapshots.
4. Build GitHub operations and one storage-neutral `sync_artifacts` operation.
5. Show the complete preview and any conflicts.
6. After explicit confirmation, apply operations through the existing executor and journal.
7. Before writing artifacts, verify the expected storage revision.
8. Write each changed document atomically and verify the desired content.
9. Persist the adapter name, generic artifact hashes, and revision in the installation state.
10. Leave commit, pull request, and push actions to the delivery workflow.

A repeated unchanged setup produces no operations and no synthetic log entry.

## Ownership and Versioning

Every factory-owned Markdown document contains this hidden marker:

```html
<!-- product-factory:v1:artifact:<document-id> -->
```

An existing document without the exact marker is human-owned. Setup reports a name collision and requires explicit adoption:

```text
product-factory setup --adopt artifact:<document-id>
```

Installed, current, and desired hashes retain the existing three-way comparison:

- desired changed while current equals installed: update;
- current changed while desired equals installed: preserve and report remote or local drift;
- current and desired both changed: report a concurrent-change conflict;
- no installed hash: create a missing document or require adoption for an existing unowned document.

Storage revision compare-and-swap prevents changes between preview and apply. A mismatch stops the operation and requires a fresh semantic plan.

Product entity versions created by later phases are immutable, for example `ideas/IDEA-001/v1.md` and `v2.md`. Every new version records a human-readable `Change reason`. Mutable indexes and append-only logs may be updated in place.

`setup-log` records the run ID, adapter, timestamp, and concise reason for a successful mutating setup. The JSONL journal remains the machine-readable execution and recovery record.

## Repository Adapter Safety

The repository adapter:

- rejects absolute roots, traversal, NUL bytes, and paths outside the checkout;
- rejects a symlinked root, ancestor, target, or unexpected non-file target;
- reads only regular Markdown files in the configured artifact root;
- writes through a temporary file in the destination directory followed by atomic rename;
- never deletes artifacts, rewrites Git history, or mutates Git configuration;
- never claims multi-file filesystem writes are transactional.

If a multi-file operation fails, completed writes remain verifiable. The existing executor and journal resume only the unfinished work.

## Wiki Adapter

The Wiki adapter retains ordinary Git clone, compare, commit, and push behavior. It never force-pushes or rewrites Wiki history. A Wiki must still be initialized manually with `Home` because GitHub does not expose a safe API for creating its first page.

Wiki-specific failures name `wiki` as the responsible adapter and give the exact recovery action. Wiki availability is not a precondition when the repository adapter is selected.

## Migration and Adapter Switching

New configurations default to the repository adapter and `product/` root. They use `context_document` and `inventory_document` instead of Wiki-specific page settings.

For backward compatibility, a version 1 config without `artifacts` selects Wiki. Setup does not silently move an existing installation to repository storage.

On the first refresh, legacy `context_page` and `inventory_page` values are treated as Wiki document IDs. Legacy `wiki_page_hashes` and `wiki_head` are normalized into `artifact_adapter`, `artifact_document_hashes`, and `artifact_revision`. Known legacy page names map to logical document IDs. Legacy Product Factory Wiki markers are accepted as owned during this migration and replaced with generic artifact markers through the normal preview.

Changing `artifacts.adapter` explicitly synchronizes desired documents into the newly selected storage. Old storage remains untouched. The preview shows every write, and the successful run replaces the installation adapter, hashes, and revision with the new adapter state. An adapter change updates installation state even when the destination already contains the desired documents.

## Failure Handling

The workflow stops before mutation when:

- the configured adapter is unsupported;
- the repository root is unsafe;
- the selected Wiki is unavailable or uninitialized;
- an artifact collides with human-owned content;
- stored installation state is malformed;
- the artifact revision changes after planning;
- the plan contains an invalid document ID, body, or operation target.

Every external failure records the failed rule, responsible component, root cause, impact, and concrete recovery action. Secrets and credentials remain redacted.

## Verification

RSpec provides:

1. planner examples for desired documents, ownership, adoption, drift, logging, and no-op behavior;
2. explicit repository adapter examples for mapping, revision, atomic writes, and path and symlink safety;
3. explicit Wiki adapter examples using a real temporary bare Git remote;
4. setup integration examples proving each adapter follows the same plan, apply, resume, and no-op flow;
5. migration examples for legacy config, installation state, and markers;
6. CLI integration proving repository setup never changes Git history or remotes;
7. an opt-in live gate against `LIT-Bootcamp/product-factory-sandbox` proving GitHub provisioning, local repository artifacts, and a second no-op run.

After the live gate, the normal delivery flow commits `product/**` to the sandbox so the artifacts are visible on GitHub. The full RSpec and RuboCop gates must pass.

## Acceptance Criteria

1. A private GitHub Free repository completes setup without a Wiki.
2. New setup defaults to `repository` and creates the approved `product/` layout.
3. `wiki` remains a working configuration choice.
4. Setup and its planner contain no Wiki-specific dependency.
5. Switching adapters requires only configuration and an approved synchronization plan.
6. Existing Wiki installations refresh without losing or deleting content.
7. Unchanged repeated setup reports zero operations.
8. Repository setup does not commit, push, or change Git configuration.
9. Artifact changes remain versioned, attributable, and recoverable.

## Excluded

- Confluence, GitHub Pages, object storage, and other adapters;
- a dynamic plugin or adapter registry;
- automatic commit, branch, push, or pull-request creation;
- product-phase document APIs not yet required;
- deletion or cleanup of legacy Wiki pages.
