# Artifact Storage Adapters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make private GitHub Free repositories store canonical Product Factory Markdown under `product/` while retaining GitHub Wiki as a configuration-selected adapter.

**Architecture:** Replace Wiki-specific setup planning with one logical-document planner and two duck-typed adapters. Repository storage writes only the current checkout through the existing safe file primitives; Wiki storage retains its existing Git transport. The existing immutable plan, explicit confirmation, executor, journal, and installation state remain the only mutation and recovery flow.

**Tech Stack:** Ruby 4.0.6, Zeitwerk, Thor, YAML/JSON/Digest/Open3/FileUtils/Tempfile from Ruby stdlib, RSpec, RuboCop, Git, GitHub CLI

**Spec:** `docs/superpowers/specs/2026-09-06-artifact-storage-adapters-design.md`

## Global Constraints

- New setup defaults to `artifacts.adapter: repository` with `artifacts.root: product`.
- Existing version 1 config without `artifacts` continues to select Wiki.
- Repository storage never commits, pushes, changes remotes, or mutates Git configuration.
- Wiki storage never force-pushes or rewrites history.
- Product entity versions are immutable; setup indexes and append-only logs may change in place.
- Every owned document has `<!-- product-factory:v1:artifact:<document-id> -->`.
- Unmarked collisions require exact `--adopt artifact:<document-id>` authorization.
- No new gem, registry, plugin framework, abstract adapter class, or second executor.
- All requires remain centralized in `lib/product_factory.rb`; Zeitwerk loads Product Factory constants.
- All behavior is covered by RSpec; no MiniTest.
- Full completion gate is `mise exec -- bundle exec rspec && mise exec -- bundle exec rubocop`.

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/product_factory/artifacts.rb` | Select the configured adapter with one explicit `case` |
| `lib/product_factory/artifacts/planner.rb` | Produce logical artifact documents, conflicts, and one sync operation |
| `lib/product_factory/artifacts/repository.rb` | Map logical IDs to safe paths and synchronize the current checkout |
| `lib/product_factory/artifacts/wiki.rb` | Map logical IDs to Wiki pages and synchronize through Git |
| `lib/product_factory/config_validator.rb` | Normalize legacy config and validate artifact settings |
| `lib/product_factory/installation.rb` | Normalize legacy Wiki state and expose generic artifact state |
| `lib/product_factory/setup/*` | Inject one artifact store into the existing setup plan/executor flow |
| `templates/project/.product-factory/schemas/provisioning-v1.yml` | Declare logical documents and the generic ownership marker |
| `spec/product_factory/artifacts/*_spec.rb` | Verify the planner and each concrete adapter directly |
| `spec/integration/artifact_storage_setup_spec.rb` | Verify repository and Wiki setup through the real CLI flow |
| `spec/live/github_repository_setup_spec.rb` | Verify default storage against the private sandbox |

Historical superseded implementation plans and specs remain unchanged.

---

### Task 1: Artifact Configuration and Installation Migration

**Files:**
- Modify: `lib/product_factory.rb`
- Modify: `lib/product_factory/config.rb`
- Modify: `lib/product_factory/config_validator.rb`
- Modify: `lib/product_factory/installation.rb`
- Modify: `lib/product_factory/setup/schema.rb`
- Modify: `templates/config.yml`
- Modify: `templates/project/.product-factory/schemas/provisioning-v1.yml`
- Modify: `spec/product_factory/config_spec.rb`
- Modify: `spec/product_factory/installation_spec.rb`
- Modify: `spec/product_factory/setup/schema_spec.rb`

**Interfaces:**
- Produces: `Config#artifacts -> Hash`
- Produces: normalized `product.context_document` and `product.inventory_document`
- Produces: `Installation#artifact_adapter -> String | nil`
- Produces: `Installation#artifact_document_hashes -> Hash<String, String>`
- Produces: generic installation keys `artifact_adapter`, `artifact_document_hashes`, `artifact_revision`
- Produces: provisioning keys `markers.artifact` and `artifacts.documents`

- [ ] **Step 1: Write failing configuration examples**

Replace new-config fixtures with repository storage and add one explicit legacy example:

```ruby
expect(config.artifacts).to eq("adapter" => "repository", "root" => "product")
expect(config.product).to include(
  "context_document" => "context",
  "inventory_document" => "inventory"
)

legacy = YAML.safe_load(YAML.dump(valid_config), aliases: false)
legacy.fetch("product")["context_page"] = legacy.fetch("product").delete("context_document")
legacy.fetch("product")["inventory_page"] = legacy.fetch("product").delete("inventory_document")
legacy.delete("artifacts")

expect(described_class.new(legacy).artifacts).to eq("adapter" => "wiki")
```

Add invalid examples for adapter `confluence`, root `/product`, root `../product`, and a non-mapping `artifacts` section.

- [ ] **Step 2: Write failing installation and manifest migration examples**

```ruby
legacy = described_class.new(
  "wiki_page_hashes" => {
    "Ideas.md" => "a" * 64,
    "_Sidebar.md" => "b" * 64
  },
  "wiki_head" => "WIKI-1"
)

expect(legacy.artifact_adapter).to eq("wiki")
expect(legacy.artifact_document_hashes).to eq("ideas/index" => "a" * 64)
expect(legacy.to_h).to include(
  "artifact_adapter" => "wiki",
  "artifact_revision" => "WIKI-1"
)
expect(legacy.to_h).not_to include("wiki_page_hashes", "wiki_head")
```

Update the schema expectation to require these exact IDs:

```ruby
expect(schema.dig("artifacts", "documents")).to eq(
  %w[index setup-log ideas/index epics/index tickets/index research/index factory-runs/index]
)
expect(schema.dig("markers", "artifact"))
  .to eq("<!-- product-factory:v1:artifact:%{document} -->")
```

- [ ] **Step 3: Run the focused specs and verify the red state**

Run:

```bash
mise exec -- bundle exec rspec \
  spec/product_factory/config_spec.rb \
  spec/product_factory/installation_spec.rb \
  spec/product_factory/setup/schema_spec.rb
```

Expected: failures mention missing `artifacts`, `context_document`, and generic installation keys.

- [ ] **Step 4: Implement config normalization and validation**

Centralize `pathname` with the other stdlib requires in `lib/product_factory.rb`. In `ConfigValidator`, normalize a copied string-keyed structure before existing validation:

```ruby
ADAPTERS = %w[repository wiki].freeze

def normalize_legacy!
  product = @data.fetch("product", {})
  artifacts = @data["artifacts"]
  if artifacts.nil?
    @data["artifacts"] = { "adapter" => "wiki" }
    product["context_document"] ||= product.delete("context_page")
    product["inventory_document"] ||= product.delete("inventory_page")
  elsif artifacts.is_a?(Hash) && artifacts["adapter"] == "repository"
    artifacts["root"] ||= "product"
  end
end

def validate_adapter!
  adapter = fetch("artifacts.adapter")
  raise ValidationError, "artifacts.adapter is unsupported" unless ADAPTERS.include?(adapter)

  root = fetch("artifacts.root")
  return if adapter == "wiki" && root.equal?(MISSING)

  parts = root.to_s.split(File::SEPARATOR, -1)
  safe = root.is_a?(String) && !root.include?("\0") && !Pathname.new(root).absolute? &&
         parts.none? { |part| part.empty? || part == "." || part == ".." }
  raise ValidationError, "artifacts.root must be a safe relative path" unless safe
end
```

Call `normalize_legacy!` before validation, add `artifacts` to mappings, replace page fields with document fields, expose `artifacts` from `Config`, and keep schema version `1`.

- [ ] **Step 5: Implement generic installation migration**

Use one physical-page mapping and remove legacy keys from normalized state:

```ruby
LEGACY_DOCUMENTS = {
  "Setup-Log.md" => "setup-log",
  "Ideas.md" => "ideas/index",
  "Epics.md" => "epics/index",
  "Tickets.md" => "tickets/index",
  "Research.md" => "research/index",
  "Factory-Runs.md" => "factory-runs/index"
}.freeze

def normalize(data)
  state = data.transform_keys(&:to_s)
  hashes = state.delete("wiki_page_hashes")
  head = state.delete("wiki_head")
  return state unless hashes || head

  unless hashes.nil? || hashes.is_a?(Hash)
    raise ValidationError, "wiki_page_hashes must be a mapping"
  end
  unless head.nil? || head.is_a?(String)
    raise ValidationError, "wiki_head must be a string or null"
  end

  state["artifact_adapter"] ||= "wiki"
  state["artifact_revision"] ||= head
  state["artifact_document_hashes"] ||= hashes.to_h.filter_map do |page, hash|
    document = LEGACY_DOCUMENTS[page]
    [document, hash] if document
  end.to_h
  state
end
```

Set generic defaults, add the three readers, and ensure `initialize` merges `DEFAULTS` with `normalize(data)`. Validate that adapter is nil, `repository`, or `wiki`; revision is nil or a string; and document hashes have string IDs and 64-character lowercase hexadecimal values. Add rejection examples for malformed legacy and generic state.

- [ ] **Step 6: Replace the template and provisioning vocabulary**

Use this template shape:

```yaml
product:
  name: Example Product
  context_document: context
  inventory_document: inventory
  max_active_ideas: 10

artifacts:
  adapter: repository
  root: product
```

Replace `markers.wiki` with `markers.artifact` and `wiki.pages` with:

```yaml
artifacts:
  documents: [index, setup-log, ideas/index, epics/index, tickets/index, research/index, factory-runs/index]
```

Make `Setup::Schema` require and validate the exact generic values.

- [ ] **Step 7: Run the focused specs**

Run the command from Step 3.

Expected: all focused examples pass.

- [ ] **Step 8: Commit**

```bash
git add lib/product_factory.rb lib/product_factory/config.rb \
  lib/product_factory/config_validator.rb lib/product_factory/installation.rb \
  lib/product_factory/setup/schema.rb templates/config.yml \
  templates/project/.product-factory/schemas/provisioning-v1.yml \
  spec/product_factory/config_spec.rb spec/product_factory/installation_spec.rb \
  spec/product_factory/setup/schema_spec.rb
git commit -m "Add artifact storage configuration"
```

---

### Task 2: Storage-Neutral Artifact Planner

**Files:**
- Create: `lib/product_factory/artifacts/planner.rb`
- Create: `spec/product_factory/artifacts/planner_spec.rb`
- Delete: `lib/product_factory/wiki/planner.rb`
- Delete: `spec/product_factory/wiki/planner_spec.rb`
- Modify: `lib/product_factory/operation.rb`

**Interfaces:**
- Consumes: snapshot `{ "revision" => String, "documents" => Hash, "legacy_owned_documents" => Array }`
- Consumes: installed hashes keyed by logical document ID
- Produces: `Artifacts::Planner.call(schema:, snapshot:, installed_hashes:, adoptions:, run_id:, recorded_at:, adapter:, operation_summaries:, failures:)`
- Produces: operation kind `Operation::SYNC_ARTIFACTS`
- Produces: operation target `artifacts:documents`

- [ ] **Step 1: Port the planner examples to logical documents**

Start from the existing Wiki planner examples, but assert the generic contract:

```ruby
expect(operation).to have_attributes(
  kind: ProductFactory::Operation::SYNC_ARTIFACTS,
  target: "artifacts:documents"
)
expect(operation.attributes.fetch("documents").keys).to contain_exactly(
  "index", "setup-log", "ideas/index", "epics/index", "tickets/index",
  "research/index", "factory-runs/index"
)
expect(operation.attributes.fetch("documents").values)
  .to all(include("<!-- product-factory:v1:artifact:"))
```

Cover exact adoption, local or remote drift, concurrent change, a generic legacy-owned ID, a structured failure row, adapter name in the setup log, and unchanged no-op.

- [ ] **Step 2: Run the planner spec and verify it fails**

Run:

```bash
mise exec -- bundle exec rspec spec/product_factory/artifacts/planner_spec.rb
```

Expected: Zeitwerk cannot load `ProductFactory::Artifacts::Planner`.

- [ ] **Step 3: Implement the logical planner**

Move the existing compare algorithm, replace page names with these constants, and remove `_Sidebar`:

```ruby
DOCUMENT_IDS = %w[
  index setup-log ideas/index epics/index tickets/index research/index factory-runs/index
].freeze

def desired_documents
  {
    "index" => page("index", "Product Factory", "Canonical product artifacts and factory run records."),
    "setup-log" => setup_log,
    "ideas/index" => page("ideas/index", "Ideas", "No Ideas have been published yet."),
    "epics/index" => page("epics/index", "Epics", "No Epics have been published yet."),
    "tickets/index" => page("tickets/index", "Tickets", "No Tickets have been published yet."),
    "research/index" => page("research/index", "Research", "No research records have been published yet."),
    "factory-runs/index" => page(
      "factory-runs/index", "Factory Runs", "No factory phase runs have been published yet."
    )
  }
end
```

Use logical ownership and conflicts:

```ruby
def owned?(document, content)
  content.include?(marker(document)) ||
    @snapshot.fetch("legacy_owned_documents", []).include?(document)
end

def collision(document)
  key = "artifact:#{document}"
  @conflicts << {
    "resource" => key,
    "reason" => "name collision",
    "adopt_with" => "product-factory setup --adopt #{key}"
  }
end
```

The operation captures all planned document hashes so partial repository writes can be distinguished from unrelated edits:

```ruby
Operation.new(
  kind: Operation::SYNC_ARTIFACTS,
  target: "artifacts:documents",
  attributes: {
    "adapter" => @adapter,
    "expected_revision" => @snapshot.fetch("revision"),
    "expected_hashes" => DOCUMENT_IDS.to_h do |document|
      content = @snapshot.fetch("documents")[document]
      [document, content && digest(content)]
    end,
    "documents" => @changes,
    "reason" => "synchronize Product Factory artifacts"
  }
)
```

Append `Storage: <adapter>` to each mutating setup-log row. Rename `SYNC_WIKI` to `SYNC_ARTIFACTS`.

- [ ] **Step 4: Run the planner spec**

Run the command from Step 2.

Expected: all planner examples pass.

- [ ] **Step 5: Commit**

```bash
git add lib/product_factory/operation.rb lib/product_factory/artifacts/planner.rb \
  spec/product_factory/artifacts/planner_spec.rb \
  lib/product_factory/wiki/planner.rb spec/product_factory/wiki/planner_spec.rb
git commit -m "Plan storage-neutral artifacts"
```

---

### Task 3: Repository Artifact Adapter

**Files:**
- Create: `lib/product_factory/artifacts/repository.rb`
- Create: `spec/product_factory/artifacts/repository_spec.rb`

**Interfaces:**
- Produces: `Artifacts::Repository.new(target_root:, root:)`
- Produces: `snapshot`, `apply`, `matches?`, `revision`, `document_hashes`
- Consumes: `Operation::SYNC_ARTIFACTS` from Task 2

- [ ] **Step 1: Write adapter behavior examples**

Assert exact mapping and generic snapshot shape:

```ruby
expect(adapter.apply(operation)).to be(true)
expect(File.read(File.join(target, "product/README.md"))).to eq(documents.fetch("index"))
expect(File.read(File.join(target, "product/ideas/README.md")))
  .to eq(documents.fetch("ideas/index"))
expect(adapter.snapshot.fetch("documents")).to include(documents)
expect(adapter.document_hashes.fetch("index"))
  .to eq(Digest::SHA256.hexdigest(documents.fetch("index")))
```

Also assert:

- reapply creates no content change;
- a changed expected document raises `ConflictError`;
- an already-written subset resumes and writes the remainder;
- absolute and traversal roots raise `ValidationError`;
- symlinked roots, ancestors, and targets raise `ValidationError` without touching the link target;
- Git `HEAD`, remotes, and config are byte-identical before and after apply.

- [ ] **Step 2: Run the adapter spec and verify it fails**

Run:

```bash
mise exec -- bundle exec rspec spec/product_factory/artifacts/repository_spec.rb
```

Expected: Zeitwerk cannot load `ProductFactory::Artifacts::Repository`.

- [ ] **Step 3: Implement mapping and snapshot**

Use only the seven current setup documents:

```ruby
PATHS = {
  "index" => "README.md",
  "setup-log" => "setup-log.md",
  "ideas/index" => "ideas/README.md",
  "epics/index" => "epics/README.md",
  "tickets/index" => "tickets/README.md",
  "research/index" => "research/README.md",
  "factory-runs/index" => "factory-runs/README.md"
}.freeze

def snapshot
  @snapshot ||= begin
    documents = PATHS.filter_map do |document, relative|
      content = read(relative)
      [document, content] if content
    end.to_h
    immutable(
      "revision" => Digest::SHA256.hexdigest(JSON.generate(documents)),
      "documents" => documents
    )
  end
end
```

Validate the configured root once with `FileSync::Path`. Build every physical target as `File.join(@root, PATHS.fetch(document))`.

Read with `File.open(path, File::RDONLY | File::NOFOLLOW)`, require a regular file, and translate `Errno::ELOOP` into `ValidationError`. Do not use `File.binread`, which can follow a last-component symlink during a race.

- [ ] **Step 4: Implement safe apply and resume**

Reuse `FileSync::Target` for atomic writes:

```ruby
def write(document, content)
  @files.apply(
    Operation.new(
      kind: Operation::WRITE_FILE,
      target: physical_path(document),
      attributes: { "content_base64" => [content].pack("m0"), "mode" => 0o644 }
    )
  )
end
```

Before writing, accept either the original expected hash or the desired hash for every known document. This permits exact partial-operation resume but rejects unrelated changes:

```ruby
def verify_revision!(operation, current)
  return if current.fetch("revision") == operation.attributes.fetch("expected_revision")

  expected = operation.attributes.fetch("expected_hashes")
  desired = operation.attributes.fetch("documents")
  safe = PATHS.keys.all? do |document|
    actual = digest(current.fetch("documents")[document])
    planned = expected[document]
    completed = desired.key?(document) && actual == digest(desired.fetch(document))
    actual == planned || completed
  end
  raise ConflictError, "Artifacts changed after planning" unless safe
end
```

Make `digest(nil)` return `nil`. Clear the cached snapshot after writes, verify `matches?`, and never invoke Git.

- [ ] **Step 5: Run the adapter spec**

Run the command from Step 2.

Expected: all repository examples pass.

- [ ] **Step 6: Commit**

```bash
git add lib/product_factory/artifacts/repository.rb \
  spec/product_factory/artifacts/repository_spec.rb
git commit -m "Add repository artifact adapter"
```

---

### Task 4: Wiki Artifact Adapter

**Files:**
- Create: `lib/product_factory/artifacts/wiki.rb`
- Create: `spec/product_factory/artifacts/wiki_spec.rb`
- Delete: `lib/product_factory/wiki/repository.rb`
- Delete: `spec/product_factory/wiki/repository_spec.rb`

**Interfaces:**
- Produces: `Artifacts::Wiki.new(organization:, repository:, shell:, remote: nil)`
- Produces the same five public operations as `Artifacts::Repository`
- Preserves human-owned `Home.md` and legacy `_Sidebar.md`

- [ ] **Step 1: Rewrite the existing Git-backed examples against logical IDs**

Keep the real temporary bare Git remote. Assert:

```ruby
expect(adapter.snapshot).to include(
  "revision" => a_string_matching(/\A[0-9a-f]{40,64}\z/),
  "documents" => { "ideas/index" => legacy_ideas }
)
expect(adapter.snapshot.fetch("legacy_owned_documents")).to include("ideas/index")
```

Apply a generic operation and verify `Ideas.md` receives the generic marker while `Home.md` and `_Sidebar.md` stay byte-identical. Retain tests for missing Home, stale revision, reapply no-op, and one normal Git commit.

- [ ] **Step 2: Run the Wiki adapter spec and verify it fails**

Run:

```bash
mise exec -- bundle exec rspec spec/product_factory/artifacts/wiki_spec.rb
```

Expected: Zeitwerk cannot load `ProductFactory::Artifacts::Wiki`.

- [ ] **Step 3: Move the Git transport behind the adapter mapping**

Use this mapping:

```ruby
PAGES = {
  "index" => "Product-Factory.md",
  "setup-log" => "Setup-Log.md",
  "ideas/index" => "Ideas.md",
  "epics/index" => "Epics.md",
  "tickets/index" => "Tickets.md",
  "research/index" => "Research.md",
  "factory-runs/index" => "Factory-Runs.md"
}.freeze
```

Translate checkout pages into logical documents in `snapshot`. Populate `legacy_owned_documents` only when a page contains its exact old marker, for example `<!-- product-factory:v1:wiki:Ideas -->`.

Translate logical operation documents back to pages before the existing atomic write, commit, and push. Rename `head` to `revision`, `page_hashes` to `document_hashes`, and all generic validation or conflict messages to `Artifacts`. Keep missing-Home and Git-command failures Wiki-specific.

- [ ] **Step 4: Run both adapter specs**

Run:

```bash
mise exec -- bundle exec rspec \
  spec/product_factory/artifacts/repository_spec.rb \
  spec/product_factory/artifacts/wiki_spec.rb
```

Expected: both adapters pass their explicit behavior suites.

- [ ] **Step 5: Commit**

```bash
git add lib/product_factory/artifacts/wiki.rb spec/product_factory/artifacts/wiki_spec.rb \
  lib/product_factory/wiki/repository.rb spec/product_factory/wiki/repository_spec.rb
git commit -m "Adapt GitHub Wiki artifact storage"
```

---

### Task 5: Wire Artifact Storage into Setup

**Files:**
- Create: `lib/product_factory/artifacts.rb`
- Create: `spec/product_factory/artifacts_spec.rb`
- Modify: `lib/product_factory/setup/workflow.rb`
- Modify: `lib/product_factory/setup/runner.rb`
- Modify: `lib/product_factory/setup/plan_builder.rb`
- Modify: `lib/product_factory/setup/operation_handlers.rb`
- Modify: `lib/product_factory/setup/options.rb`
- Modify: `lib/product_factory/setup/plan_validator.rb`
- Modify: `lib/product_factory/setup/preview.rb`
- Create: `spec/support/fake_artifact_store.rb`
- Delete: `spec/support/fake_wiki.rb`
- Modify: `spec/spec_helper.rb`
- Modify: `spec/product_factory/setup/runner_spec.rb`

**Interfaces:**
- Produces: `Artifacts.build(config:, target_root:, shell:)`
- Replaces every `wiki_repository` injection with `artifact_store`
- Persists actual adapter state only after successful artifact synchronization

- [ ] **Step 1: Write selector and runner examples**

Verify `Artifacts.build` returns `Artifacts::Repository` for repository config and `Artifacts::Wiki` for legacy Wiki config. Stub those constructors; do not touch disk or Git in the selector spec.

Change runner examples to inject one fake artifact store.

The fake exposes the approved contract:

```ruby
class FakeArtifactStore
  attr_reader :revision

  def initialize
    @revision = "ARTIFACTS-1"
    @documents = {}
  end

  def snapshot
    { "revision" => revision, "documents" => @documents }
  end

  def apply(operation)
    return true if matches?(operation)

    @documents.merge!(operation.attributes.fetch("documents"))
    @revision = "ARTIFACTS-#{revision.delete_prefix('ARTIFACTS-').to_i + 1}"
    true
  end

  def matches?(operation)
    operation.attributes.fetch("documents").all? do |document, content|
      @documents[document] == content
    end
  end

  def document_hashes
    @documents.transform_values { |content| Digest::SHA256.hexdigest(content) }
  end
end
```

Replace the Wiki preflight example with two examples: repository setup never asks for Wiki, while an explicitly selected failing Wiki adapter stops before every target mutation.

- [ ] **Step 2: Run the setup runner spec and verify it fails**

Run:

```bash
mise exec -- bundle exec rspec \
  spec/product_factory/artifacts_spec.rb \
  spec/product_factory/setup/runner_spec.rb
```

Expected: the runner does not accept `artifact_store` and still expects Wiki operations.

- [ ] **Step 3: Add the explicit adapter selector**

```ruby
module ProductFactory
  module Artifacts
    def self.build(config:, target_root:, shell:)
      case config.artifacts.fetch("adapter")
      when "repository"
        Repository.new(target_root:, root: config.artifacts.fetch("root"))
      when "wiki"
        Wiki.new(
          organization: config.github.fetch("organization"),
          repository: config.github.fetch("repository"),
          shell:
        )
      else
        raise ValidationError, "artifacts.adapter is unsupported"
      end
    end
  end
end
```

Do not add a base adapter, registry, or configuration callback.

- [ ] **Step 4: Rename setup dependencies and operation handling**

Use `artifact_store` and `artifact_snapshot` consistently in Runner, Workflow, PlanBuilder, and OperationHandlers. Workflow selects the store after configuration and snapshots only the selected adapter.

PlanBuilder invokes:

```ruby
artifacts = Artifacts::Planner.call(
  schema: @schema,
  snapshot: @artifact_snapshot,
  installed_hashes: installation.artifact_document_hashes,
  adoptions: @adoptions,
  run_id:,
  recorded_at: @clock.call.utc.iso8601,
  adapter: @configuration.fetch(:config).artifacts.fetch("adapter"),
  operation_summaries: operations.map(&:target),
  failures: setup_failures
)
```

The installation operation includes the configured `artifact_adapter`. OperationHandlers replaces its generic hashes and revision after successful apply:

```ruby
operation.attributes.merge(
  "github_resource_ids" => @github_state.resource_ids,
  "github_resource_hashes" => @github_state.resource_hashes,
  "artifact_document_hashes" => @artifact_store.document_hashes,
  "artifact_revision" => @artifact_store.revision
)
```

Treat an adapter-name change as an installation change even when destination content already matches.

- [ ] **Step 5: Validate generic plans and adoption keys**

Options accepts only IDs from `Artifacts::Planner::DOCUMENT_IDS`:

```ruby
artifact = Artifacts::Planner::DOCUMENT_IDS.include?(value&.delete_prefix("artifact:")) &&
           value.start_with?("artifact:")
value == "project" || issue || artifact
```

PlanValidator accepts exactly one `sync_artifacts` operation with target `artifacts:documents`. Require string `adapter` and `expected_revision`, an `expected_hashes` mapping whose keys equal the seven document IDs and whose values are nil or SHA-256 hashes, and a non-empty `documents` subset with string bodies. Order it after GitHub operations and before installation. Preview prints `SYNC` for this generic kind.

- [ ] **Step 6: Run setup and planner specs**

Run:

```bash
mise exec -- bundle exec rspec \
  spec/product_factory/artifacts \
  spec/product_factory/setup/runner_spec.rb \
  spec/product_factory/cli_setup_spec.rb
```

Expected: all selected examples pass.

- [ ] **Step 7: Commit**

```bash
git add lib/product_factory/artifacts.rb lib/product_factory/setup \
  spec/product_factory/artifacts_spec.rb \
  spec/support/fake_artifact_store.rb spec/support/fake_wiki.rb \
  spec/spec_helper.rb spec/product_factory/setup/runner_spec.rb \
  spec/product_factory/cli_setup_spec.rb
git commit -m "Use artifact adapters in setup"
```

---

### Task 6: End-to-End Repository, Wiki, and Migration Proof

**Files:**
- Create: `spec/integration/artifact_storage_setup_spec.rb`
- Delete: `spec/integration/github_wiki_setup_spec.rb`
- Create: `spec/live/github_repository_setup_spec.rb`
- Delete: `spec/live/github_wiki_setup_spec.rb`
- Modify: `spec/product_factory/cli_setup_spec.rb`
- Modify: `spec/product_factory/setup/configuration_spec.rb`

**Interfaces:**
- Verifies the installed CLI with each adapter through the real setup workflow
- Keeps the live gate environment contract `PRODUCT_FACTORY_LIVE_GITHUB=LIT-Bootcamp/product-factory-sandbox`

- [ ] **Step 1: Write a default repository integration example**

Initialize a real temporary Git repository with a GitHub-shaped origin, inject only fake GitHub state/writer, and run the CLI twice. Assert:

```ruby
expect(first_status).to eq(0), first_error.string
expect(second_status).to eq(0), second_error.string
expect(File.read(File.join(target, "product/README.md")))
  .to include("product-factory:v1:artifact:index")
expect(File.read(File.join(target, "product/ideas/README.md")))
  .to include("product-factory:v1:artifact:ideas/index")
expect(second_output.string).to include("Product Factory is up to date")
expect(git_head_after).to eq(git_head_before)
expect(git_remote_after).to eq(git_remote_before)
```

- [ ] **Step 2: Preserve one explicit Wiki integration example**

Write a version 1 legacy config without `artifacts`, create a real temporary bare Wiki remote with `Home.md`, inject `Artifacts::Wiki`, and run setup twice. Assert logical documents are written to their mapped pages, Home and `_Sidebar` are preserved, generic markers replace legacy markers through the previewed migration, installation state is generic, and the second run is a no-op.

- [ ] **Step 3: Prove an explicit adapter switch**

Start from the successful legacy Wiki setup, change only config to:

```yaml
artifacts:
  adapter: repository
  root: product
```

Run setup with the repository adapter. Assert all seven repository documents are created, Wiki `HEAD` and pages remain unchanged, installation records `repository`, and the next repository run is a no-op. Also pre-populate the repository with desired documents in one example and prove the adapter-only change still updates installation state.

- [ ] **Step 4: Run the integration spec and verify failures**

Run:

```bash
mise exec -- bundle exec rspec spec/integration/artifact_storage_setup_spec.rb
```

Expected: failures identify remaining Wiki-specific wiring or incorrect repository mappings.

- [ ] **Step 5: Fix only integration seams exposed by Step 4**

Keep fixes inside the classes introduced by Tasks 1-5. Do not add another coordinator, test-only production API, or Git mutation to the repository adapter.

- [ ] **Step 6: Replace the live Wiki gate with the private repository gate**

Clone `LIT-Bootcamp/product-factory-sandbox` into a temporary checkout, run default setup twice, and verify:

```ruby
expect(repository_visibility).to eq("PRIVATE")
expect(config.artifacts).to eq("adapter" => "repository", "root" => "product")
expect(ProductFactory::Installation.load(target).artifact_adapter).to eq("repository")
expect(Dir.glob(File.join(target, "product/**/*.md")).size).to eq(7)
expect(second_output.string).to include("Product Factory is up to date")
expect(head(target)).to eq(head_before_setup)
```

Retain the exact opt-in guard. Do not push from the spec.

- [ ] **Step 7: Run all non-live specs**

Run:

```bash
mise exec -- bundle exec rspec
```

Expected: all examples pass with the live example excluded.

- [ ] **Step 8: Run the opt-in sandbox gate**

Run:

```bash
PRODUCT_FACTORY_LIVE_GITHUB=LIT-Bootcamp/product-factory-sandbox \
  mise exec -- bundle exec rspec spec/live/github_repository_setup_spec.rb
```

Expected: one live example passes, the second setup reports no operations, and the remote repository commit remains unchanged.

- [ ] **Step 9: Commit**

```bash
git add spec/integration/artifact_storage_setup_spec.rb \
  spec/integration/github_wiki_setup_spec.rb \
  spec/live/github_repository_setup_spec.rb spec/live/github_wiki_setup_spec.rb \
  spec/product_factory/cli_setup_spec.rb \
  spec/product_factory/setup/configuration_spec.rb
git commit -m "Verify artifact storage end to end"
```

---

### Task 7: Current Documentation and Completion Gate

**Files:**
- Modify: `README.md`
- Modify: `docs/design/product-factory-v1.md`
- Modify: `docs/superpowers/plans/2026-09-02-product-factory-v1-roadmap.md`

**Interfaces:**
- Documents repository as the default canonical storage and Wiki as optional
- Documents the exact configuration switch and ownership command

- [ ] **Step 1: Update operator documentation**

README must show:

```yaml
artifacts:
  adapter: repository
  root: product
```

Replace the Wiki prerequisite with the generated `product/` tree, replace adoption with `--adopt artifact:ideas/index`, and update the live command to `spec/live/github_repository_setup_spec.rb`. State explicitly that setup leaves `product/**` uncommitted for the normal delivery flow.

- [ ] **Step 2: Update the authoritative product design and roadmap**

In `docs/design/product-factory-v1.md`, replace Wiki as the canonical store with the configured artifact store, use logical document IDs, describe repository-default publication and delivery-owned Git, and retain Wiki Git compare-and-swap only in the Wiki adapter section. Replace exact Wiki links with exact immutable artifact links as a future phase requirement.

In the roadmap, rename Slice 2 to `GitHub and artifact storage provisioning`, make the private sandbox repository-based, and replace remaining active Wiki-only exit proofs with adapter-neutral artifact proofs. Do not edit historical completed plans or superseded specs.

- [ ] **Step 3: Scan active code and docs for accidental Wiki coupling**

Run:

```bash
rg -n "SYNC_WIKI|wiki_repository|Wiki::Planner|Wiki::Repository|context_page|inventory_page|wiki_page_hashes|wiki_head" \
  lib spec templates README.md docs/design docs/superpowers/plans/2026-09-02-product-factory-v1-roadmap.md
```

Expected: no matches outside explicit legacy-migration fixtures and Wiki adapter behavior.

- [ ] **Step 4: Run formatting and the complete gate**

Run:

```bash
git diff --check
mise exec -- bundle exec rspec
mise exec -- bundle exec rubocop
```

Expected: no whitespace errors, all RSpec examples pass, and RuboCop reports no offenses.

- [ ] **Step 5: Verify the final diff and repository status**

Run:

```bash
git status --short
git diff --stat origin/main...HEAD
git diff --name-status origin/main...HEAD
```

Expected: only the approved adapter refactor, its tests, and current documentation are present. `Gemfile.lock` is not added.

- [ ] **Step 6: Commit**

```bash
git add README.md docs/design/product-factory-v1.md \
  docs/superpowers/plans/2026-09-02-product-factory-v1-roadmap.md
git commit -m "Document artifact storage adapters"
```

- [ ] **Step 7: Run the post-commit completion gate**

Run:

```bash
mise exec -- bundle exec rspec && mise exec -- bundle exec rubocop
git status --short --branch
```

Expected: all checks pass and the working tree is clean.
