# Product Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend canonical artifact storage to safe versioned document IDs and publish the first immutable Product Context during setup.

**Architecture:** Keep the two existing artifact adapters and their existing compare-and-swap operation. Allow a caller to request additional validated logical documents, map them inside the selected adapter, and include them in the same preview, confirmation, journal, verification, and resume flow. A small Product Context domain service renders Markdown; a setup wizard only collects missing human input.

**Tech Stack:** Ruby 4.0.6, Zeitwerk, Thor, RSpec, existing Product Factory services and artifact adapters.

**Spec:** `docs/design/product-factory-v1.md` sections 4.2, 9, 10, 16-18; `docs/superpowers/specs/2026-09-06-artifact-storage-adapters-design.md`

## Global Constraints

- Durable artifacts are English; interactive prompts follow the user's input language only when localization exists.
- Product Context versions are immutable; only the configured landing document is mutable.
- Repository storage never commits, pushes, creates branches, or changes Git configuration.
- Wiki storage never force-pushes or rewrites history.
- Every write stays inside the existing immutable plan, one-confirmation executor, journal, and resume flow.
- Logical document IDs reject absolute paths, traversal, empty segments, NUL bytes, `.md` suffixes, and `--` inside a segment.
- No LLM or agent is involved in Product Context setup.
- Do not add a generic adapter registry, database, hosted service, or second execution pipeline.

---

### Task 1: Safe Versioned Artifact Documents

**Files:**
- Modify: `lib/product_factory/artifacts.rb`
- Modify: `lib/product_factory/artifacts/planner.rb`
- Modify: `lib/product_factory/artifacts/repository.rb`
- Modify: `lib/product_factory/artifacts/wiki.rb`
- Modify: `spec/product_factory/artifacts_spec.rb`
- Modify: `spec/product_factory/artifacts/planner_spec.rb`
- Modify: `spec/product_factory/artifacts/repository_spec.rb`
- Modify: `spec/product_factory/artifacts/wiki_spec.rb`

**Interfaces:**
- Produces: `Artifacts.valid_document_id?(document) -> true | false`
- Produces: `adapter.snapshot(document_ids: Artifacts::Planner::DOCUMENT_IDS) -> frozen Hash`
- Produces: `adapter.link(document) -> String`
- Preserves: `adapter.apply(operation)`, `matches?`, `revision`, and `document_hashes`
- Produces: `Artifacts::Planner.call(..., additional_documents: {})`

- [ ] **Step 1: Write failing document-contract examples**

Add table-driven examples proving these IDs are accepted:

```ruby
%w[context context/v1 ideas/IDEA-141/v2].each do |document|
  expect(ProductFactory::Artifacts.valid_document_id?(document)).to be(true)
end
```

Reject `nil`, empty IDs, absolute paths, `..`, `.`, empty segments, `.md` suffixes, NUL bytes, and segments containing `--`. Extend operation validation so `documents` must be non-empty, every desired key must exist in `expected_hashes`, and every expected hash key is a valid document ID.

- [ ] **Step 2: Run the contract specs and verify RED**

Run:

```shell
mise exec -- bundle exec rspec spec/product_factory/artifacts_spec.rb
```

Expected: failures because dynamic document validation does not exist.

- [ ] **Step 3: Implement the minimum logical-ID contract**

Keep validation in the existing `Artifacts` module. Use segment checks, not path expansion:

```ruby
def self.valid_document_id?(document)
  return false unless document.is_a?(String) && !document.empty? && !document.include?("\0")

  segments = document.split("/", -1)
  segments.all? { |segment| segment.match?(/\A[A-Za-z0-9][A-Za-z0-9._-]*\z/) &&
                            !segment.end_with?(".md") && !segment.include?("--") }
end
```

Update `valid_hashes?` and `valid_documents?` to validate keys dynamically. Do not weaken SHA-256 or operation target validation.

- [ ] **Step 4: Write failing adapter mapping examples**

Repository expectations:

```ruby
snapshot = adapter.snapshot(document_ids: %w[context context/v1 ideas/IDEA-141/v2])
expect(adapter.link("context/v1")).to eq("context/v1.md")
```

Applying an operation writes:

```text
<configured-root>/context.md
<configured-root>/context/v1.md
<configured-root>/ideas/IDEA-141/v2.md
```

`index` and `*/index` retain their existing `README.md` mappings.

Wiki expectations:

```ruby
expect(adapter.link("context/v1")).to eq("context--v1")
```

The Wiki Git filename is `context--v1.md`; the seven existing setup pages retain their friendly names. Both adapters must reject unsafe IDs before filesystem or Git mutation.

- [ ] **Step 5: Run adapter specs and verify RED**

Run:

```shell
mise exec -- bundle exec rspec \
  spec/product_factory/artifacts/repository_spec.rb \
  spec/product_factory/artifacts/wiki_spec.rb
```

Expected: failures because adapters currently accept only the seven setup mappings and `snapshot` has no argument.

- [ ] **Step 6: Generalize the existing mappings**

In each adapter, preserve the fixed setup mapping and add one private fallback:

```ruby
# repository
def mapped_path(document)
  PATHS.fetch(document) do
    document.end_with?("/index") ? "#{document.delete_suffix('/index')}/README.md" : "#{document}.md"
  end
end

# wiki
def mapped_page(document)
  PAGES.fetch(document) { "#{document.gsub('/', '--')}.md" }
end
```

Make `snapshot(document_ids:)` read the requested IDs. `apply` and `matches?` must refresh exactly the keys captured by `expected_hashes`; completed-write recovery and unrelated-document drift checks remain unchanged. `link` returns the mapped repository-relative path or Wiki page name without `.md`.

- [ ] **Step 7: Extend the artifact planner**

Add `additional_documents: {}` to the planner. Merge those documents into the existing seven setup documents and build `expected_hashes` for the union of snapshot keys and desired keys. Existing setup with no additional documents must remain byte-identical and plan as a no-op.

- [ ] **Step 8: Run all artifact checks and verify GREEN**

Run:

```shell
mise exec -- bundle exec rspec \
  spec/product_factory/artifacts_spec.rb \
  spec/product_factory/artifacts/planner_spec.rb \
  spec/product_factory/artifacts/repository_spec.rb \
  spec/product_factory/artifacts/wiki_spec.rb
```

Expected: all examples pass.

- [ ] **Step 9: Commit**

```shell
git add lib/product_factory/artifacts.rb lib/product_factory/artifacts \
  spec/product_factory/artifacts_spec.rb spec/product_factory/artifacts
git commit -m "Support versioned artifact documents"
```

---

### Task 2: Product Context Documents

**Files:**
- Create: `lib/product_factory/product_context.rb`
- Create: `spec/product_factory/product_context_spec.rb`

**Interfaces:**
- Produces: `ProductContext.document_ids(config) -> [landing_id, version_id]`
- Produces: `ProductContext.call(config:, snapshot:, answers:, actor:, run_id:, recorded_at:, version_link:) -> Hash<String, String>`
- Consumes: validated `Config`, artifact snapshot, optional initial answers, GitHub actor, run metadata, and adapter link

- [ ] **Step 1: Write failing document examples**

Assert `document_ids` returns `context` and `context/v1` for the default config. For an empty snapshot and complete answers, assert two Markdown documents are returned.

The immutable `context/v1` document must contain:

```markdown
<!-- product-factory:v1:artifact:context/v1 -->
# Product Context — Example Product

| Field | Value |
|---|---|
| Version | 1 |
| Created at | 2026-09-07T10:00:00Z |
| Created by | human:factory-test |
| Factory run | RUN-1 |
| Change reason | Initial Product Context |

## Mission
...

## Target Users
...

## Primary User Problem
...

## Desired Outcome
...

## Markets and Languages
...

## Competitor Seeds
...

## Constraints
...

## Non-goals
...
```

The mutable landing document contains its own marker, product name, `Current version: [v1](...)`, and a short mission summary. Markdown table values escape pipes and all content ends with one newline.

- [ ] **Step 2: Run the Product Context spec and verify RED**

Run:

```shell
mise exec -- bundle exec rspec spec/product_factory/product_context_spec.rb
```

Expected: Zeitwerk cannot load `ProductFactory::ProductContext`.

- [ ] **Step 3: Implement one cohesive renderer**

Use one `ProductContext < Service`; do not add builders, serializers, repositories, or a template gem. Validate required answers (`mission`, `target_users`, `primary_user_problem`, `desired_outcome`, `markets_and_languages`) as non-empty strings. Optional values render as `Not provided`.

When `context/v1` already exists, return only the deterministic landing document. Never regenerate or overwrite the immutable version. When the landing already matches, the artifact planner naturally produces no change.

- [ ] **Step 4: Verify GREEN and commit**

Run:

```shell
mise exec -- bundle exec rspec spec/product_factory/product_context_spec.rb
```

Then:

```shell
git add lib/product_factory/product_context.rb spec/product_factory/product_context_spec.rb
git commit -m "Render immutable product context"
```

---

### Task 3: Product Context Wizard and Setup Integration

**Files:**
- Create: `lib/product_factory/setup/product_context_wizard.rb`
- Create: `spec/product_factory/setup/product_context_wizard_spec.rb`
- Modify: `lib/product_factory/setup/workflow.rb`
- Modify: `lib/product_factory/setup/plan_builder.rb`
- Modify: `spec/product_factory/setup/runner_spec.rb`
- Modify: `spec/support/fake_artifact_store.rb`

**Interfaces:**
- Produces: `Setup::ProductContextWizard.call(input:, output:, snapshot:, document_ids:) -> Hash | nil`
- Extends: `Setup::PlanBuilder.call(..., product_context: nil)`
- Consumes: `artifact_store.snapshot(document_ids:)` and `artifact_store.link(document)`

- [ ] **Step 1: Write failing wizard examples**

For a snapshot without `context/v1`, provide one input line for each field and assert the wizard returns:

```ruby
{
  "mission" => "Help people learn with mentors",
  "target_users" => "Students and mentors",
  "primary_user_problem" => "Learning lacks feedback",
  "desired_outcome" => "Students complete guided courses",
  "markets_and_languages" => "Ukraine; Ukrainian and English",
  "competitor_seeds" => "Coursera, Udemy",
  "constraints" => "Small team",
  "non_goals" => "Marketplace"
}
```

Required prompts repeat after blank input and raise `UsageError` on end-of-input instead of looping. Optional prompts accept blank input. If `context/v1` exists, assert no input is read, no output is written, and the result is `nil`.

- [ ] **Step 2: Run the wizard spec and verify RED**

Run:

```shell
mise exec -- bundle exec rspec spec/product_factory/setup/product_context_wizard_spec.rb
```

- [ ] **Step 3: Implement the prompt-only wizard**

Use one ordered field table and two private methods, `required_answer` and `optional_answer`. The wizard does not render Markdown, create IDs, access GitHub, or mutate files.

- [ ] **Step 4: Write failing setup examples**

Cover both paths through the real setup runner:

1. A first repository setup asks for product name and eight context values, previews one artifact sync, confirms once, and writes `product/context.md` plus `product/context/v1.md`.
2. A project installed by the previous release but missing Product Context asks only the context questions and publishes v1 during refresh.
3. A second run reads v1, asks no context questions, and is a no-op.
4. Declining the plan writes neither context document.
5. A Wiki setup writes the landing and immutable version through its dynamic page mapping.

- [ ] **Step 5: Run setup specs and verify RED**

Run:

```shell
mise exec -- bundle exec rspec \
  spec/product_factory/setup/runner_spec.rb \
  spec/integration/artifact_storage_setup_spec.rb
```

- [ ] **Step 6: Connect Product Context to the existing setup plan**

In `Workflow`:

1. Prepare and snapshot GitHub as today.
2. Ask the adapter for the seven setup IDs plus `ProductContext.document_ids(config)`.
3. Run `ProductContextWizard` only when v1 is absent.
4. Pass answers, actor, and `artifact_store.link(version_id)` to `PlanBuilder`.

In `PlanBuilder`, generate the run ID once, call `ProductContext` with that same ID and timestamp, and pass returned documents as `additional_documents` to `Artifacts::Planner`. Keep Product Context in the existing `SYNC_ARTIFACTS` operation; do not add another executor or confirmation.

Update `FakeArtifactStore` to accept requested IDs and return deterministic links. Do not add test-only branches to production code.

- [ ] **Step 7: Verify setup integration and commit**

Run:

```shell
mise exec -- bundle exec rspec \
  spec/product_factory/setup/product_context_wizard_spec.rb \
  spec/product_factory/setup/runner_spec.rb \
  spec/integration/artifact_storage_setup_spec.rb
```

Then:

```shell
git add lib/product_factory/setup lib/product_factory/product_context.rb \
  spec/product_factory/setup spec/support/fake_artifact_store.rb \
  spec/integration/artifact_storage_setup_spec.rb
git commit -m "Publish Product Context during setup"
```

---

### Task 4: Installed Runtime, Documentation, and End-to-End Proof

**Files:**
- Modify: `README.md`
- Modify: `docs/design/product-factory-v1.md`
- Modify: `docs/superpowers/plans/2026-09-02-product-factory-v1-roadmap.md`
- Modify: `spec/integration/local_setup_spec.rb`
- Modify: `templates/project/.product-factory/spec/integration_spec.rb`

**Interfaces:**
- Preserves: `bin/product-factory setup` as the single user entry point
- Proves: installed runtime publishes and validates Product Context without changing Git history

- [ ] **Step 1: Extend the installed integration contract**

After setup, assert:

```ruby
expect(File.read(File.join(target, "product/context/v1.md"))).to include(
  "# Product Context", "| Version | 1 |", "## Mission"
)
expect(git_head(target)).to eq(head_before_setup)
```

Run the installed runtime a second time with empty input and assert no operations and no prompts.

- [ ] **Step 2: Run integration specs and verify RED**

Run:

```shell
mise exec -- bundle exec rspec \
  spec/integration/local_setup_spec.rb \
  spec/integration/artifact_storage_setup_spec.rb
```

- [ ] **Step 3: Update durable guidance**

Document the eight Product Context prompts, the `context.md` landing document, the immutable `context/v1.md` version, one confirmation, and the rule that users commit repository-adapter output through normal Git workflow.

Mark only the Product Context portion of Slice 3 complete. Product Inventory, Ideation, approval, and revision remain explicit next work; do not imply Slice 3 is finished.

- [ ] **Step 4: Run the complete local gate**

Run:

```shell
mise exec -- bundle exec rspec
mise exec -- bundle exec rubocop
git diff --check
```

Expected: all RSpec examples pass, RuboCop reports zero offenses, and `git diff --check` exits zero.

- [ ] **Step 5: Commit**

```shell
git add README.md docs spec/integration templates/project/.product-factory/spec/integration_spec.rb
git commit -m "Document Product Context setup"
```

---

## Final Review

- [ ] Confirm Product Context v1 is immutable and a repeat run is a no-op.
- [ ] Confirm both adapters map every accepted document ID without collisions.
- [ ] Confirm one setup plan, one confirmation, one journal, and one artifact operation remain authoritative.
- [ ] Confirm configuration changes after planning and artifact revision drift still fail before mutation.
- [ ] Confirm no agent, LLM, Git commit, branch, push, database, or hosted service was introduced.
- [ ] Confirm Product Inventory and Ideation remain outside this PR.
