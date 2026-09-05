# GitHub and Wiki Provisioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `product-factory setup` idempotently provision the private GitHub Project, organization Issue Types, Project schema, views, and factory-owned Wiki pages required by later Product Factory phases.

**Architecture:** Extend the existing immutable `Plan -> confirmation -> Executor -> Journal` flow. Ruby planners compare a versioned provisioning manifest with read-only GitHub and Wiki snapshots; existing execution machinery applies ordinary operations through one `gh api` client and one Git-backed Wiki repository. No LLM participates in setup.

**Tech Stack:** Ruby 4.0.6, RSpec 3.13, Thor, Zeitwerk, Ruby stdlib (`Open3`, `JSON`, `YAML`, `Digest`, `Tempfile`), GitHub CLI, Git

**Spec:** `docs/superpowers/specs/2026-09-05-github-wiki-provisioning-design.md`

## Global Constraints

- Use Ruby 4.0.6 and the existing Zeitwerk loader.
- Add no runtime or test gem.
- Use RSpec only; specs are loaded through the existing `.rspec` file and do not require `spec_helper` themselves.
- Use `described_class` in specs.
- Reuse `ProductFactory::Service`, `Operation`, `Plan`, `Executor`, `Journal`, `Installation`, and `StreamShell`.
- `GitHub::Client` is the only production object allowed to execute `gh`.
- Pass command arguments as arrays; never interpolate user input into a shell command.
- Normal CI must perform zero live GitHub mutations.
- Setup must perform zero LLM calls and consume zero model tokens.
- The Product Factory Project and sandbox repository are private.
- Never modify `Bootcamper Product Delivery`, delete a GitHub resource, change repository visibility, rewrite Wiki history, or force-push.
- A missing Wiki `Home` page stops the entire plan before any mutation.
- Every external write is followed by a read and exact verification.
- Keep production classes within the existing RuboCop limits; do not add provider interfaces, factories, or speculative abstractions.

## File Structure

| File | Responsibility |
|---|---|
| `templates/project/.product-factory/schemas/provisioning-v1.yml` | Single desired-state manifest for Issue Types, Project fields, views, markers, and Wiki page names |
| `lib/product_factory/setup/schema.rb` | Safely load and validate that manifest |
| `lib/product_factory/external_failure.rb` | Carry structured external failure accountability |
| `lib/product_factory/github/client.rb` | Execute authenticated `gh` REST/GraphQL calls and parse/redact results |
| `lib/product_factory/github/state.rb` | Read and normalize current GitHub organization/repository/Project state |
| `lib/product_factory/github/planner.rb` | Produce GitHub operations and semantic conflicts without mutation |
| `lib/product_factory/github/writer.rb` | Apply one GitHub operation idempotently |
| `lib/product_factory/wiki/repository.rb` | Clone, inspect, commit, push, and verify the Wiki Git repository |
| `lib/product_factory/wiki/planner.rb` | Produce one Wiki synchronization operation and page conflicts |
| `lib/product_factory/setup/configuration.rb` | Build an in-memory first-run config from detected repository data and one product-name answer |
| Existing setup classes | Compose, preview, validate, persist, resume, and execute one plan |

---

### Task 1: Versioned Provisioning Schema and Installation State

**Files:**
- Create: `templates/project/.product-factory/schemas/provisioning-v1.yml`
- Create: `lib/product_factory/setup/schema.rb`
- Create: `spec/product_factory/setup/schema_spec.rb`
- Modify: `lib/product_factory/distribution.rb`
- Modify: `lib/product_factory/installation.rb`
- Modify: `templates/project/.product-factory/schemas/installation-v1.yml`
- Modify: `spec/product_factory/installation_spec.rb`

**Interfaces:**
- Produces: `ProductFactory::Setup::Schema.call(bytes:) -> frozen Hash`
- Produces: `Distribution#provisioning_schema_bytes -> String`
- Produces: installation keys `github_resource_ids`, `github_resource_hashes`, `wiki_page_hashes`, and `wiki_head`

- [ ] **Step 1: Write failing schema and installation specs**

```ruby
RSpec.describe ProductFactory::Setup::Schema do
  subject(:schema) do
    described_class.call(bytes: ProductFactory::Distribution.new(FileHelpers::FACTORY_ROOT).provisioning_schema_bytes)
  end

  it "loads the exact private v1 resource model" do
    expect(schema.dig("project", "public")).to be(false)
    expect(schema.fetch("issue_types").keys).to eq(%w[Idea Epic Ticket])
    expect(schema.dig("fields", "Priority", "options").map { |option| option.fetch("name") })
      .to eq((1..10).map { |number| "P#{number}" })
    expect(schema.dig("views").keys).to eq(%w[Ideas Epics Tickets])
    expect(schema.dig("wiki", "pages")).to eq(
      %w[_Sidebar Setup-Log Ideas Epics Tickets Research Factory-Runs]
    )
    expect(schema).to be_frozen
  end

  it "rejects an unsafe or incomplete manifest" do
    bytes = YAML.dump("schema_version" => 1, "project" => { "public" => true })

    expect { described_class.call(bytes:) }
      .to raise_error(ProductFactory::ValidationError, "invalid provisioning schema")
  end
end
```

Add an installation example asserting that all four remote-state keys round-trip without exposing internal mutation.

- [ ] **Step 2: Run the focused specs and verify RED**

Run:

```sh
mise exec -- bundle exec rspec spec/product_factory/setup/schema_spec.rb spec/product_factory/installation_spec.rb
```

Expected: failure because `Setup::Schema`, `provisioning_schema_bytes`, and the new defaults do not exist.

- [ ] **Step 3: Add the exact v1 manifest**

Use this shape and exact names in `provisioning-v1.yml`:

```yaml
schema_version: 1
api_version: "2026-03-10"

markers:
  issue_type: "product-factory:v1:issue-type:%{name}"
  project: "product-factory:v1:project:%{organization}/%{repository}"
  wiki: "<!-- product-factory:v1:wiki:%{page} -->"

issue_types:
  Idea:
    description: "A high-level product opportunity with measurable user or business value. product-factory:v1:issue-type:Idea"
    color: purple
  Epic:
    description: "A coherent business capability and its observable scenarios. product-factory:v1:issue-type:Epic"
    color: blue
  Ticket:
    description: "An independently deliverable technical change. product-factory:v1:issue-type:Ticket"
    color: green

project:
  public: false

fields:
  Status:
    type: single_select
    options:
      - { name: Created, color: GRAY, description: "New Idea awaiting a human decision" }
      - { name: Human approved, color: GREEN, description: "Approved for business analysis" }
      - { name: Draft, color: GRAY, description: "Epic draft under Business Analyst ownership" }
      - { name: Analyzing, color: BLUE, description: "Business analysis is running" }
      - { name: Analyzed, color: GREEN, description: "Business scenarios are complete" }
      - { name: Tech analyzing, color: BLUE, description: "Technical analysis is running" }
      - { name: Tech analyzed, color: GREEN, description: "Technical decomposition is complete" }
      - { name: Ready for backlog, color: PURPLE, description: "Ticket is ready for backlog publication" }
      - { name: Done, color: GREEN, description: "Entity and all required children are complete" }
      - { name: Blocked, color: RED, description: "A declared dependency prevents progress" }
      - { name: Needs human, color: YELLOW, description: "A material human decision is required" }
      - { name: Superseded, color: GRAY, description: "A newer accepted entity replaces this one" }
  Priority:
    type: single_select
    options:
      - { name: P1, color: RED, description: "Highest priority" }
      - { name: P2, color: ORANGE, description: "Priority 2" }
      - { name: P3, color: ORANGE, description: "Priority 3" }
      - { name: P4, color: YELLOW, description: "Priority 4" }
      - { name: P5, color: YELLOW, description: "Priority 5" }
      - { name: P6, color: GREEN, description: "Priority 6" }
      - { name: P7, color: BLUE, description: "Priority 7" }
      - { name: P8, color: BLUE, description: "Priority 8" }
      - { name: P9, color: GRAY, description: "Priority 9" }
      - { name: P10, color: GRAY, description: "Lowest priority" }
  Created At: { type: date }
  Human Approved At: { type: date }
  Analysis Started At: { type: date }
  Analyzed At: { type: date }
  Tech Analysis Started At: { type: date }
  Tech Analyzed At: { type: date }
  Blocked At: { type: date }
  Needs Human At: { type: date }
  Superseded At: { type: date }
  Created By: { type: text }
  Approved By: { type: text }
  Analyzed By: { type: text }
  Tech Analyzed By: { type: text }
  Source: { type: text }
  Source Version: { type: number }
  Factory Run: { type: text }
  Active Run: { type: text }
  Claim Expires At: { type: date }
  Human Estimate Hours: { type: number }
  AI Estimate Hours: { type: number }
  Duration Minutes: { type: number }
  Tokens Used: { type: number }
  Run Count: { type: number }
  Failure Count: { type: number }
  Last Failure Owner: { type: text }
  Last Failure At: { type: date }
  User Value: { type: number }
  Business Value: { type: number }
  Progressiveness: { type: number }
  Strategic Fit: { type: number }
  Urgency: { type: number }
  Evidence Confidence: { type: number }
  Research Verified At: { type: date }

views:
  Ideas:
    issue_type: Idea
    visible_fields: [Title, Status, Priority, User Value, Business Value, Progressiveness, Strategic Fit, Urgency, Evidence Confidence, Created At]
  Epics:
    issue_type: Epic
    visible_fields: [Title, Status, Priority, Parent issue, Created At, Analyzed At, Tech Analyzed At]
  Tickets:
    issue_type: Ticket
    visible_fields: [Title, Status, Priority, Parent issue, Human Estimate Hours, AI Estimate Hours, Assignees, Linked pull requests]

wiki:
  pages: [_Sidebar, Setup-Log, Ideas, Epics, Tickets, Research, Factory-Runs]
```

- [ ] **Step 4: Implement safe loading and persistence**

```ruby
module ProductFactory
  module Setup
    class Schema < Service
      REQUIRED = %w[schema_version api_version markers issue_types project fields views wiki].freeze
      FIELD_TYPES = %w[date number single_select text].freeze

      def initialize(bytes:)
        super()
        @bytes = bytes
      end

      def call
        data = YAML.safe_load(@bytes, aliases: false)
        validate!(data)
        JSON.parse(JSON.generate(data), freeze: true)
      rescue Psych::Exception, JSON::GeneratorError
        raise ValidationError, "invalid provisioning schema"
      end

      private

      def validate!(data)
        valid = data.is_a?(Hash) && data.keys.sort == REQUIRED.sort &&
                data["schema_version"] == 1 && data.dig("project", "public") == false &&
                data.fetch("issue_types").keys == %w[Idea Epic Ticket] &&
                data.fetch("fields").values.all? { |field| FIELD_TYPES.include?(field["type"]) } &&
                data.fetch("views").keys == %w[Ideas Epics Tickets] &&
                data.dig("wiki", "pages") == %w[_Sidebar Setup-Log Ideas Epics Tickets Research Factory-Runs]
        raise ValidationError, "invalid provisioning schema" unless valid
      rescue KeyError, NoMethodError
        raise ValidationError, "invalid provisioning schema"
      end
    end
  end
end
```

Add the provisioning file to `Distribution::REQUIRED_FILES`, expose its bytes, and add these installation defaults:

```ruby
"github_resource_hashes" => {},
"wiki_page_hashes" => {},
"wiki_head" => nil,
```

Declare the same fields in `installation-v1.yml` as `mapping`, `mapping_of_strings`, and `string_or_null` respectively.

- [ ] **Step 5: Run focused specs and the full gate**

```sh
mise exec -- bundle exec rspec spec/product_factory/setup/schema_spec.rb spec/product_factory/installation_spec.rb
mise exec -- bundle exec rake
```

Expected: all examples pass and RuboCop reports no offenses.

- [ ] **Step 6: Commit**

```sh
git add lib/product_factory/setup/schema.rb lib/product_factory/distribution.rb lib/product_factory/installation.rb templates/project/.product-factory/schemas/provisioning-v1.yml templates/project/.product-factory/schemas/installation-v1.yml spec/product_factory/setup/schema_spec.rb spec/product_factory/installation_spec.rb
git commit -m "Add provisioning schema"
```

---

### Task 2: Authenticated GitHub Command Boundary and Structured Failures

**Files:**
- Create: `lib/product_factory/external_failure.rb`
- Create: `lib/product_factory/github/client.rb`
- Create: `spec/product_factory/github/client_spec.rb`
- Modify: `lib/product_factory/stream_shell.rb`
- Modify: `lib/product_factory/journal.rb`
- Modify: `lib/product_factory/executor.rb`
- Create: `spec/product_factory/journal_spec.rb`
- Modify: `spec/product_factory/executor_spec.rb`

**Interfaces:**
- Produces: `StreamShell#capture3(*command, chdir: nil, stdin_data: nil)`
- Produces: `GitHub::Client#get(endpoint)`, `#post(endpoint, body)`, `#put(endpoint, body)`, `#graphql(query, variables = {})`, and `#auth_status`
- Produces: `ExternalFailure` readers `failed_rule`, `responsible_component`, `root_cause`, `impact`, and `recovery_action`

- [ ] **Step 1: Write failing client, redaction, and failure-journal specs**

```ruby
RSpec.describe ProductFactory::GitHub::Client do
  subject(:client) { described_class.new(shell:) }

  let(:shell) { instance_double(ProductFactory::StreamShell) }
  let(:status) { instance_double(Process::Status, success?: true, exitstatus: 0) }

  it "sends JSON through stdin with the pinned REST version" do
    allow(shell).to receive(:capture3).and_return(["{\"id\":410}", "", status])

    result = client.post("orgs/acme/issue-types", "name" => "Idea", "is_enabled" => true)

    expect(result).to eq("id" => 410)
    expect(shell).to have_received(:capture3).with(
      "gh", "api", "orgs/acme/issue-types", "--method", "POST",
      "--header", "Accept: application/vnd.github+json",
      "--header", "X-GitHub-Api-Version: 2026-03-10",
      "--input", "-",
      chdir: nil,
      stdin_data: "{\"name\":\"Idea\",\"is_enabled\":true}"
    )
  end

  it "redacts credentials from failures" do
    failed = instance_double(Process::Status, success?: false, exitstatus: 1)
    allow(shell).to receive(:capture3).and_return(["", "token ghp_SECRET", failed])

    expect { client.get("user") }
      .to raise_error(ProductFactory::ExternalFailure, /\[REDACTED\]/)
  end
end
```

Extend executor coverage to expect all structured failure fields in `operation_failed`, and journal coverage to accept only those fields with string values.

- [ ] **Step 2: Run focused specs and verify RED**

```sh
mise exec -- bundle exec rspec spec/product_factory/github/client_spec.rb spec/product_factory/journal_spec.rb spec/product_factory/executor_spec.rb
```

Expected: missing constants and missing structured journal fields.

- [ ] **Step 3: Add the command method and failure type**

```ruby
def capture3(*command, chdir: nil, stdin_data: nil)
  options = {}
  options[:chdir] = chdir if chdir
  options[:stdin_data] = stdin_data if stdin_data
  Open3.capture3(*command, **options)
end
```

```ruby
module ProductFactory
  class ExternalFailure < Error
    FIELDS = %i[failed_rule responsible_component root_cause impact recovery_action].freeze

    attr_reader(*FIELDS)

    def initialize(**details)
      FIELDS.each { |field| instance_variable_set("@#{field}", details.fetch(field)) }
      super(root_cause)
    end

    def to_h = FIELDS.to_h { |field| [field, public_send(field)] }
  end
end
```

- [ ] **Step 4: Implement the minimal `gh api` client**

Use one private request method. `get` sends no body; `post`, `put`, and `graphql` serialize a hash through stdin. `auth_status` runs `gh auth status --active` and returns true or raises a structured failure. Reject non-object/non-array JSON.

```ruby
def request(endpoint, method:, body: nil)
  command = ["gh", "api", endpoint, "--method", method, *HEADERS]
  command += ["--input", "-"] if body
  output, error, status = @shell.capture3(
    *command,
    chdir: nil,
    stdin_data: body && JSON.generate(body)
  )
  return JSON.parse(output) if status.success?

  raise failure(error, status.exitstatus)
rescue JSON::ParserError => error
  raise failure("invalid GitHub JSON: #{error.message}", 1)
end
```

Use these redactions before building the failure: GitHub tokens matching `gh[a-z]_[A-Za-z0-9_]+` and `Authorization:` header values must become `[REDACTED]`. Product credentials are never passed to this client.

- [ ] **Step 5: Journal structured accountability**

For `operation_failed`, append the exception's `to_h` when it is an `ExternalFailure`. For other errors use:

```ruby
{
  failed_rule: "operation_execution",
  responsible_component: "product_factory",
  root_cause: error.message,
  impact: "#{operation.target} was not verified",
  recovery_action: "rerun product-factory setup"
}
```

Allow `run_completed` statuses `success` and `no-op`. Do not add agent fields to setup failures.

- [ ] **Step 6: Run focused specs and full gate**

```sh
mise exec -- bundle exec rspec spec/product_factory/github/client_spec.rb spec/product_factory/journal_spec.rb spec/product_factory/executor_spec.rb
mise exec -- bundle exec rake
```

- [ ] **Step 7: Commit**

```sh
git add lib/product_factory/external_failure.rb lib/product_factory/github/client.rb lib/product_factory/stream_shell.rb lib/product_factory/journal.rb lib/product_factory/executor.rb spec/product_factory/github/client_spec.rb spec/product_factory/journal_spec.rb spec/product_factory/executor_spec.rb
git commit -m "Add authenticated GitHub boundary"
```

---

### Task 3: Read-Only GitHub State and Semantic Planning

**Files:**
- Create: `lib/product_factory/github/state.rb`
- Create: `lib/product_factory/github/planner.rb`
- Create: `spec/product_factory/github/state_spec.rb`
- Create: `spec/product_factory/github/planner_spec.rb`
- Modify: `lib/product_factory/operation.rb`

**Interfaces:**
- Produces: `GitHub::State#snapshot -> Hash`, `#matches?(operation) -> Boolean`, `#resource_ids -> Hash`, `#resource_hashes -> Hash`
- Produces: `GitHub::Planner.call(config:, schema:, state:, installed_hashes:, adoptions:) -> { operations: Array<Operation>, conflicts: Array<Hash> }`
- Produces operation kinds: `ensure_issue_type`, `ensure_project`, `ensure_project_field`, `ensure_project_view`

- [ ] **Step 1: Write failing state-normalization specs**

Use a client double and return one organization/repository/project graph plus REST Issue Type and Project-field responses. Assert the normalized snapshot has only semantic values:

```ruby
expect(state.snapshot).to include(
  "actor" => "denys",
  "organization" => { "id" => "O_1", "login" => "LIT-Bootcamp", "role" => "admin" },
  "repository" => { "id" => "R_1", "name" => "bootcamper" }
)
expect(state.snapshot.dig("projects", 0)).to include(
  "id" => "P_2",
  "number" => 2,
  "title" => "Bootcamper Product Factory",
  "public" => false
)
```

Assert fingerprints are stable across response-key order and exclude timestamps such as `updatedAt`.

- [ ] **Step 2: Write failing planner specs for all decision branches**

Cover these exact cases:

1. Empty organization state emits three Issue Types, one Project, every manifest field, and three views in that order.
2. An exact marker plus exact shape emits no operation.
3. A same-name unmarked Issue Type or Project emits a collision with the exact rerun command.
4. `adoptions: ["project"]` turns only the Project collision into an operation.
5. A mismatched field type is always a conflict; adoption cannot change a field's type.
6. Remote equals installed while desired changed emits an update.
7. Remote changed while desired equals installed emits drift and no overwrite.
8. Remote and desired both changed emits a conflict.
9. The unrelated `Bootcamper Product Delivery` Project is absent from all operations.

The new-resource expectation should be explicit:

```ruby
expect(result.fetch(:operations).map { |operation| [operation.kind, operation.target] }).to start_with(
  [ProductFactory::Operation::ENSURE_ISSUE_TYPE, "github:issue-type:Idea"],
  [ProductFactory::Operation::ENSURE_ISSUE_TYPE, "github:issue-type:Epic"],
  [ProductFactory::Operation::ENSURE_ISSUE_TYPE, "github:issue-type:Ticket"],
  [ProductFactory::Operation::ENSURE_PROJECT, "github:project"]
)
```

- [ ] **Step 3: Run focused specs and verify RED**

```sh
mise exec -- bundle exec rspec spec/product_factory/github/state_spec.rb spec/product_factory/github/planner_spec.rb
```

- [ ] **Step 4: Implement state reads and normalized fingerprints**

Use REST for:

- `GET user/memberships/orgs/{org}`;
- `GET orgs/{org}/issue-types`;
- `GET orgs/{org}/projectsV2/{number}/fields?per_page=100`.

Use one GraphQL query for viewer, organization membership, repository, Projects, Project fields/options, views/filter/visible fields, linked repositories, and Project item count. Paginate Projects when `pageInfo.hasNextPage` is true; never assume the desired Project is in the first page.

Normalize option values to `{ "id", "name", "color", "description" }`, using the REST response's `.raw` values. Fingerprint with SHA-256 over canonical JSON containing only managed semantic values.

Preflight raises `ExternalFailure` before planning when:

- `gh auth status --active` fails;
- repository owner/name differs from config;
- organization membership is not active admin for Issue Type creation;
- Wiki preflight supplied by Task 5 fails.

- [ ] **Step 5: Implement the planner with one generic comparison method**

Each operation carries:

```ruby
{
  "desired" => desired_resource,
  "expected_fingerprint" => current_fingerprint,
  "reason" => "missing"
}
```

Use semantic resource keys `issue-type:Idea`, `project`, `field:Priority`, and `view:Ideas`. Do not include API IDs in desired state. A handler resolves current IDs during apply.

The shared comparison follows this exact decision table:

| Current | Marker/adoption | Installed hash | Result |
|---|---|---|---|
| Missing | Not applicable | Any | Ensure operation |
| Desired | Owned | Any | No-op |
| Present | Foreign, not adopted | Any | Collision |
| Present | Wrong immutable type | Any | Conflict |
| Changed | Owned/adopted | Equals current | Update operation |
| Changed | Owned/adopted | Equals desired | Preserve drift and conflict |
| Changed | Owned/adopted | Differs from both | Concurrent-change conflict |

For a brand-new Project, plan all fields and views even though their parent ID does not exist yet. Writer resolution by semantic key makes the plan immutable.

- [ ] **Step 6: Run focused specs and full gate**

```sh
mise exec -- bundle exec rspec spec/product_factory/github/state_spec.rb spec/product_factory/github/planner_spec.rb
mise exec -- bundle exec rake
```

- [ ] **Step 7: Commit**

```sh
git add lib/product_factory/operation.rb lib/product_factory/github/state.rb lib/product_factory/github/planner.rb spec/product_factory/github/state_spec.rb spec/product_factory/github/planner_spec.rb
git commit -m "Plan GitHub infrastructure changes"
```

---

### Task 4: Idempotent GitHub Mutation and Verification

**Files:**
- Create: `lib/product_factory/github/writer.rb`
- Create: `spec/product_factory/github/writer_spec.rb`
- Modify: `lib/product_factory/github/state.rb`

**Interfaces:**
- Produces: `GitHub::Writer#apply(operation) -> true`
- Consumes: `GitHub::State#matches?(operation)` for post-write and resume verification

- [ ] **Step 1: Write failing writer specs**

Cover:

- Issue Type creation includes `is_enabled: true`, configured color, description marker, and read-after-write.
- Existing adopted Issue Type uses `PUT orgs/{org}/issue-types/{id}`.
- Project creation uses a temporary marked title, then `updateProjectV2` sets final title, `public: false`, and marked `shortDescription`.
- A Project created in the crash window is found by its temporary marker and finalized rather than duplicated.
- Existing unlinked adopted Project uses `linkProjectV2ToRepository`.
- New text/date/number/single-select fields use the Project fields REST endpoint.
- Existing single-select updates preserve option IDs with matching names.
- Fresh Project default `Status` options may be replaced because its item count is zero.
- A non-empty Project with extra Status/Priority options fails before removing an option.
- The default fresh `View 1` is renamed/configured as `Ideas`; `Epics` and `Tickets` are created.
- Every operation is read back after mutation.
- A changed expected fingerprint raises `ConflictError` before mutation.

- [ ] **Step 2: Run the focused spec and verify RED**

```sh
mise exec -- bundle exec rspec spec/product_factory/github/writer_spec.rb
```

- [ ] **Step 3: Implement one operation dispatcher**

```ruby
def apply(operation)
  verify_precondition!(operation)
  send("apply_#{operation.kind}", operation)
  raise ValidationError, "verification failed for #{operation.target}" unless @state.matches?(operation)

  true
end
```

Keep the dispatcher private-safe by first checking `Operation::GITHUB_KINDS.include?(operation.kind)`; never dispatch arbitrary plan strings.

- [ ] **Step 4: Implement exact GitHub mutations**

Use these APIs:

| Resource | Create | Update/complete |
|---|---|---|
| Issue Type | `POST orgs/{org}/issue-types` | `PUT orgs/{org}/issue-types/{id}` |
| Project | GraphQL `createProjectV2(ownerId:, repositoryId:, title:, clientMutationId:)` | GraphQL `updateProjectV2(projectId:, title:, public: false, shortDescription:)` and `linkProjectV2ToRepository` when absent |
| Field | `POST orgs/{org}/projectsV2/{number}/fields` | GraphQL `updateProjectV2Field`; include existing option IDs by matching name |
| View | `POST orgs/{org}/projectsV2/{number}/views` | GraphQL `updateProjectV2View(viewId:, name:, layout: TABLE, filter:, configuration:)` |

Create a Project first with this temporary title:

```ruby
temporary_title = "#{desired.fetch('title')} [#{desired.fetch('marker')}]"
```

Then immediately set the final title, private visibility, and marker. A rerun searches both the final title/short description and the temporary title marker.

Translate view filters from the manifest to GitHub query text only in the writer/state pair:

```ruby
"type:\"#{desired.fetch('issue_type')}\""
```

Resolve manifest `visible_fields` names to the current Project field numeric IDs for REST creation and node IDs for GraphQL updates. Missing required field IDs are a validation failure; never create a partially configured view.

- [ ] **Step 5: Add precondition and safe option rules**

Before mutation, re-read the target resource. Proceed only when its fingerprint equals `expected_fingerprint`, it is already desired, or it is a recoverable temporary Project marker from the same operation. If it is already desired, return true without issuing a write.

Never remove a select option from a Project containing items. For a zero-item Project, replace the fresh default Status options with the manifest options. For an existing option name, preserve its ID during GraphQL update so item values survive color or description changes.

- [ ] **Step 6: Run focused specs and full gate**

```sh
mise exec -- bundle exec rspec spec/product_factory/github/writer_spec.rb spec/product_factory/github/state_spec.rb
mise exec -- bundle exec rake
```

- [ ] **Step 7: Commit**

```sh
git add lib/product_factory/github/writer.rb lib/product_factory/github/state.rb spec/product_factory/github/writer_spec.rb spec/product_factory/github/state_spec.rb
git commit -m "Apply GitHub infrastructure changes"
```

---

### Task 5: Git-Backed Wiki Planning, Synchronization, and Human Log

**Files:**
- Create: `lib/product_factory/wiki/repository.rb`
- Create: `lib/product_factory/wiki/planner.rb`
- Create: `spec/product_factory/wiki/repository_spec.rb`
- Create: `spec/product_factory/wiki/planner_spec.rb`
- Modify: `lib/product_factory/operation.rb`

**Interfaces:**
- Produces: `Wiki::Repository.new(organization:, repository:, shell:, remote: nil)` with a local-remote test seam
- Produces: `Wiki::Repository#snapshot -> { "head" => String, "pages" => Hash }`, `#apply(operation)`, `#matches?(operation)`, `#head`, and `#page_hashes`
- Produces: `Wiki::Planner.call(schema:, snapshot:, installed_hashes:, adoptions:, run_id:, recorded_at:, operation_summaries:, failures:) -> { operations:, conflicts: }`
- Produces operation kind: `sync_wiki`

- [ ] **Step 1: Write failing repository specs with local bare Git repositories**

Create a normal source repository and a bare `application.wiki.git` remote inside `Dir.mktmpdir`; do not mock Git. Assert:

1. Snapshot reads the current head and Markdown files.
2. Missing `Home.md` raises an `ExternalFailure` whose recovery action is `Create the Home page in GitHub Wiki, then rerun product-factory setup`.
3. Apply changes only the listed factory-owned pages, commits once, and preserves `Home.md` byte-for-byte.
4. Apply refuses an unexpected head and never force-pushes.
5. Reapplying desired pages is a no-op.

- [ ] **Step 2: Write failing planner specs**

Assert exact first-run page names and content markers. Cover same-name foreign pages, exact `--adopt wiki:_Sidebar`, three-way drift, unpublished failures, and a pure no-op that emits no operation and no setup-log row.

```ruby
expect(result.fetch(:operations).sole).to have_attributes(
  kind: ProductFactory::Operation::SYNC_WIKI,
  target: "wiki:factory-pages"
)
expect(result.fetch(:operations).sole.attributes.dig("pages", "Home.md")).to be_nil
```

- [ ] **Step 3: Run focused specs and verify RED**

```sh
mise exec -- bundle exec rspec spec/product_factory/wiki/repository_spec.rb spec/product_factory/wiki/planner_spec.rb
```

- [ ] **Step 4: Implement snapshot and Git synchronization**

Use a temporary checkout for every snapshot/apply. The default remote is:

```ruby
"https://github.com/#{organization}/#{repository}.wiki.git"
```

An explicitly injected `remote:` is accepted only for integration specs against a local bare Git repository; normal setup never supplies it.

Use the active GitHub CLI credential helper without storing a token:

```ruby
["git", "-c", "credential.https://github.com.helper=!gh auth git-credential", "clone", "--quiet", remote, checkout]
```

Run Git commands through `StreamShell#capture3`. For apply:

1. clone;
2. compare `git rev-parse HEAD` with `expected_head`;
3. validate every page name against the fixed manifest list;
4. write with `Tempfile` plus rename;
5. `git add --` only the exact changed paths;
6. commit with fixed local `user.name=Product Factory` and `user.email=product-factory@users.noreply.github.com`;
7. `git push origin HEAD` without force;
8. clone/read again and verify.

- [ ] **Step 5: Implement concise generated pages**

Generate these exact purposes:

| Page | Initial body after marker and heading |
|---|---|
| `_Sidebar` | Links to `Home`, `Ideas`, `Epics`, `Tickets`, `Research`, `Factory-Runs`, and `Setup-Log` |
| `Ideas` | `No Ideas have been published yet.` |
| `Epics` | `No Epics have been published yet.` |
| `Tickets` | `No Tickets have been published yet.` |
| `Research` | `No research records have been published yet.` |
| `Factory-Runs` | `No factory phase runs have been published yet.` |
| `Setup-Log` | Markdown table with `Run`, `Recorded at`, and `Changes` |

Append a setup-log row only when the plan has mutations or the local journal contains an operation failure not already identified in the page. Build the change cell with `"Applied: #{operation_summaries.join(', ')}"`; do not claim final success before the local installation checkpoint. Failure rows include operation ID, responsible component, root cause, and recovery action.

- [ ] **Step 6: Implement Wiki comparison**

Fingerprint each owned page's complete bytes. Foreign unmarked content is a collision. The exact page adoption flag permits replacing that page after preview. Apply the same installed/current/desired decision table as GitHub planning. One operation contains all changed owned pages and the expected Wiki head, producing one Wiki commit.

- [ ] **Step 7: Run focused specs and full gate**

```sh
mise exec -- bundle exec rspec spec/product_factory/wiki/repository_spec.rb spec/product_factory/wiki/planner_spec.rb
mise exec -- bundle exec rake
```

- [ ] **Step 8: Commit**

```sh
git add lib/product_factory/operation.rb lib/product_factory/wiki/repository.rb lib/product_factory/wiki/planner.rb spec/product_factory/wiki/repository_spec.rb spec/product_factory/wiki/planner_spec.rb
git commit -m "Synchronize factory Wiki pages"
```

---

### Task 6: One Resumable Setup Command

**Files:**
- Create: `lib/product_factory/setup/configuration.rb`
- Create: `spec/product_factory/setup/configuration_spec.rb`
- Modify: `lib/product_factory/cli.rb`
- Modify: `lib/product_factory/setup/runner.rb`
- Modify: `lib/product_factory/setup/plan_builder.rb`
- Modify: `lib/product_factory/setup/operation_handlers.rb`
- Modify: `lib/product_factory/setup/plan_validator.rb`
- Modify: `lib/product_factory/plan.rb`
- Modify: `lib/product_factory/installation.rb`
- Modify: `lib/product_factory/journal.rb`
- Modify: `spec/product_factory/cli_setup_spec.rb`
- Modify: `spec/product_factory/setup/runner_spec.rb`
- Create: `spec/product_factory/setup/plan_builder_spec.rb`
- Create: `spec/support/fake_github.rb`
- Create: `spec/support/fake_wiki.rb`
- Modify: `spec/support/file_helpers.rb`
- Modify: `spec/spec_helper.rb`
- Modify: `spec/integration/local_setup_spec.rb`

**Interfaces:**
- Produces: `Setup::Configuration.call(distribution:, target_root:, input:, output:, github_client:, shell:) -> { config:, bytes:, repository: }`
- Produces: `Setup::Runner#run(arguments) -> :success | :declined`
- Produces: `Setup::Runner.new(distribution_root:, target_root:, input:, output:, clock:, shell: nil, github_state: nil, github_writer: nil, wiki_repository: nil)` dependency seam
- Produces: `CLI.start(argv, input:, output:, error:, cwd:, setup_runner: nil)` dependency seam for integration tests
- Produces: durable confirmed plans at `.product-factory/runs/<RUN-ID>.json`
- Consumes: GitHub and Wiki planner results, writer handlers, remote fingerprints, and remote IDs

- [ ] **Step 1: Write failing first-run configuration specs**

Assert an existing config is loaded without prompts. For a missing config, stub detected repository `LIT-Bootcamp/bootcamper`, answer `Bootcamper`, and expect generated bytes whose only changed template values are:

```yaml
product:
  name: Bootcamper
github:
  organization: LIT-Bootcamp
  repository: bootcamper
  project_title: Bootcamper Product Factory
```

Blank product-name input uses a titleized repository name. The config remains in memory; the target directory stays unchanged.

- [ ] **Step 2: Write failing setup orchestration specs**

Cover:

1. `setup` dispatches plan, preview, one confirmation, and apply.
2. Empty Wiki or failed GitHub preflight leaves the target byte-for-byte unchanged.
3. Local and external operations appear in this order: config, factory files, Issue Types, Project, fields, views, Wiki, installation.
4. A conflict anywhere blocks every operation.
5. `--adopt` is repeatable and exact; an unknown key is a usage error.
6. Empty operations print `Product Factory is up to date`, append a local `no-op` run event, and do not ask for confirmation.
7. After `yes`, the exact plan is written atomically under `.product-factory/runs` before `run_confirmed` is journaled.
8. A later `setup` detects a confirmed unfinished run, validates and resumes the stored plan without another confirmation.
9. Completed desired operations and started-but-uncompleted desired operations are verified/reused rather than duplicated.
10. Final installation state contains actual GitHub IDs/hashes and Wiki hashes/head read after all external operations.

- [ ] **Step 3: Run focused specs and verify RED**

```sh
mise exec -- bundle exec rspec spec/product_factory/setup/configuration_spec.rb spec/product_factory/setup/runner_spec.rb spec/product_factory/setup/plan_builder_spec.rb spec/product_factory/cli_setup_spec.rb
```

- [ ] **Step 4: Implement in-memory configuration**

Always read `git remote get-url origin` through `StreamShell`, support GitHub HTTPS and SSH URLs, and validate the derived `owner/repository` with `GitHub::Client#get("repos/{owner}/{repository}")`. When config exists, require its owner/repository to equal that detected remote and return `Config.load` plus its exact bytes. Otherwise prompt exactly:

```text
Product name [Bootcamper]:
```

Parse `templates/config.yml`, replace product name and the three GitHub values, validate with `Config.new`, then return the object, `YAML.dump(data)`, and the validated repository response. Derive the default Project title from the repository name, not the product-name answer, using `repository.tr("-_", "  ").split.map(&:capitalize).join(" ")`. Do not write the file in this service.

- [ ] **Step 5: Compose all planners into one immutable plan**

Extend `PlanBuilder.call` to receive `configuration`, `schema`, `github_planner`, `wiki_planner`, `installation`, `adoptions`, and journal events. Merge the returned operations/conflicts in the documented order. Keep the existing local file three-way logic unchanged.

The final installation operation carries desired factory hashes plus empty remote result slots. At apply time, `OperationHandlers` fills those slots from fresh verified state:

```ruby
state = operation.attributes.merge(
  "github_resource_ids" => @github_state.resource_ids,
  "github_resource_hashes" => @github_state.resource_hashes,
  "wiki_page_hashes" => @wiki_repository.page_hashes,
  "wiki_head" => @wiki_repository.head
)
Installation.new(state).write(@root)
```

Verification derives the same state again and compares it with `Installation.load(@root).to_h`.

- [ ] **Step 6: Wire handlers and validate order**

Keep local handlers in `Setup::OperationHandlers`. Add GitHub handlers by iterating `Operation::GITHUB_KINDS`, all using `GitHub::Writer#apply` and `GitHub::State#matches?`. Add the Wiki handler using `Wiki::Repository#apply` and `#matches?`.

Update `PlanValidator` so unsupported kinds fail before confirmation and the only valid order is:

```ruby
config_operations + file_operations + issue_type_operations +
  project_operations + field_operations + view_operations +
  wiki_operations + installation_operations
```

Require exactly one final installation operation for a mutating plan.

- [ ] **Step 7: Add durable confirmed-plan resume**

`Runner#run(arguments)` first checks the journal for a `run_confirmed` event without a matching `run_completed`. If found, load `.product-factory/runs/<run_id>.json`, validate it against the current target/distribution, print `Resuming <run_id>`, and apply it without prompting.

For a new run:

1. build and print the mutation-free plan;
2. return after journaling `no-op` when it has no operations;
3. ask `Apply this plan? [yes/no]` once;
4. on `yes`, atomically persist the plan under `.product-factory/runs`;
5. append `run_confirmed`;
6. execute.

Use `Tempfile` plus rename for the plan. Reject symlinked run directories/files. An orphan plan without `run_confirmed` is safe and ignored.

- [ ] **Step 8: Add CLI setup and human-readable preview**

Add `setup` to `CLI::COMMANDS` and dispatch it to `Setup::Runner#run`. Keep `plan` and `apply` operational.

Allow tests to pass one already-built runner through `CLI.start(argv, input:, output:, error:, cwd:, setup_runner:)`; the default remains `Setup::Runner.from_cli`. Allow `Setup::Runner` to receive optional `github_state`, `github_writer`, and `wiki_repository` dependencies, constructing real objects when omitted. This is the only integration seam; do not add environment-driven fake modes to production.

Preview every operation with one of `CREATE`, `ADOPT`, `UPDATE`, or `SYNC`, its human resource name, and its `reason`. Print conflicts with the exact adoption command where applicable. Do not expose raw GraphQL, tokens, or full API payloads.

Add small stateful `FakeGitHub` and `FakeWiki` support objects implementing only those injected public methods. Update existing setup helpers and `local_setup_spec.rb` to inject them, preserving the existing local setup assertions without network access. Require these support files from `spec_helper.rb` alongside the existing support configuration.

- [ ] **Step 9: Run focused specs and full gate**

```sh
mise exec -- bundle exec rspec spec/product_factory/setup spec/product_factory/cli_setup_spec.rb
mise exec -- bundle exec rake
```

- [ ] **Step 10: Commit**

```sh
git add lib/product_factory/cli.rb lib/product_factory/setup/configuration.rb lib/product_factory/setup/runner.rb lib/product_factory/setup/plan_builder.rb lib/product_factory/setup/operation_handlers.rb lib/product_factory/setup/plan_validator.rb lib/product_factory/plan.rb lib/product_factory/installation.rb lib/product_factory/journal.rb spec/product_factory/setup/configuration_spec.rb spec/product_factory/setup/runner_spec.rb spec/product_factory/setup/plan_builder_spec.rb spec/product_factory/cli_setup_spec.rb spec/support/fake_github.rb spec/support/fake_wiki.rb spec/support/file_helpers.rb spec/spec_helper.rb spec/integration/local_setup_spec.rb
git commit -m "Add resumable setup command"
```

---

### Task 7: Integration, Live Release Gate, and Operator Documentation

**Files:**
- Create: `spec/integration/github_wiki_setup_spec.rb`
- Create: `spec/live/github_wiki_setup_spec.rb`
- Create: `spec/support/live_github.rb`
- Modify: `spec/spec_helper.rb`
- Modify: `README.md`
- Modify: `docs/design/product-factory-v1.md`
- Modify: `docs/superpowers/plans/2026-09-02-product-factory-v1-roadmap.md`

**Interfaces:**
- Produces: deterministic in-memory GitHub boundary for integration specs
- Produces: opt-in live RSpec gate controlled by exact repository confirmation
- Produces: documented setup, adoption, recovery, and live verification commands

- [ ] **Step 1: Write the full local integration spec**

Drive the real `ProductFactory::CLI` with real local files, real bare Wiki Git repositories, and the stateful `FakeGitHub` created in Task 6 through `CLI.start(argv, input:, output:, error:, cwd:, setup_runner:)`. Do not fake `Plan`, `Executor`, `Journal`, or `Installation`.

The example must prove this complete loop:

```ruby
first_status = ProductFactory::CLI.start(["setup"], input: StringIO.new("Bootcamper\nyes\n"), **io)
second_status = ProductFactory::CLI.start(["setup"], input: StringIO.new, **io)

expect(first_status).to eq(0)
expect(second_status).to eq(0)
expect(fake_github.issue_type_names).to eq(%w[Idea Epic Ticket])
expect(fake_github.project.fetch("public")).to be(false)
expect(fake_github.view_names).to eq(%w[Ideas Epics Tickets])
expect(wiki_page("Home.md")).to eq(original_home)
expect(second_output.string).to include("Product Factory is up to date")
```

Add a second example that raises after a remote Project creation, invokes `setup` again, and proves one Project exists, the same run resumes without a second prompt, and the journal names the failed component/root cause/recovery action.

- [ ] **Step 2: Run the integration spec and verify RED, then GREEN**

```sh
mise exec -- bundle exec rspec spec/integration/github_wiki_setup_spec.rb
```

Fix only integration defects in the responsible production layer. Do not add integration-only production branches.

- [ ] **Step 3: Add the opt-in live RSpec gate**

Exclude `live_github: true` unless this environment value exactly matches the sandbox:

```ruby
LIVE_REPOSITORY = "LIT-Bootcamp/product-factory-sandbox"
enabled = ENV["PRODUCT_FACTORY_LIVE_GITHUB"] == LIVE_REPOSITORY
config.filter_run_excluding(live_github: true) unless enabled
```

The live spec must abort before cloning or mutation when the value does not match. When enabled, clone the private sandbox into `Dir.mktmpdir`, record `Home.md`, run setup with one `yes`, rerun setup, and assert:

- repository name is the exact sandbox;
- Project marker targets the sandbox, Project `public` is false, and repository link is exact;
- Issue Types are `Idea`, `Epic`, and `Ticket` with markers;
- every manifest field and select option exists;
- views are exactly `Ideas`, `Epics`, and `Tickets` with correct filters;
- all seven owned Wiki pages have markers;
- `Home.md` is byte-identical;
- the second plan has zero operations.

The live example must not delete or reset any GitHub resource.

- [ ] **Step 4: Update operator documentation and remove stale public wording**

Replace the README's Slice 1-only section with:

```sh
bin/product-factory setup
bin/product-factory doctor
bin/product-factory validate
bin/product-factory test
```

Document collision recovery with exact `--adopt <resource>` examples and interrupted-run automatic resume. Document the live gate:

```sh
PRODUCT_FACTORY_LIVE_GITHUB=LIT-Bootcamp/product-factory-sandbox \
  mise exec -- bundle exec rspec spec/live/github_wiki_setup_spec.rb
```

Change both v1 design and roadmap references from a public sandbox to a private sandbox. State the one-time prerequisites: an organization owner creates the private sandbox repository and manually creates its `Home` Wiki page.

- [ ] **Step 5: Run all release checks**

```sh
mise exec -- bundle exec rake
git diff --check
```

Expected: all RSpec examples pass, RuboCop reports no offenses, and diff check is empty. The live example remains excluded.

- [ ] **Step 6: Run the explicit live gate**

Precondition: `LIT-Bootcamp/product-factory-sandbox` exists, is private, and has a manually created `Home` page.

```sh
PRODUCT_FACTORY_LIVE_GITHUB=LIT-Bootcamp/product-factory-sandbox \
  mise exec -- bundle exec rspec spec/live/github_wiki_setup_spec.rb
```

Expected: first setup converges all resources; second setup reports zero operations; no existing unrelated Project changes.

- [ ] **Step 7: Commit**

```sh
git add spec/support/live_github.rb spec/integration/github_wiki_setup_spec.rb spec/live/github_wiki_setup_spec.rb spec/spec_helper.rb README.md docs/design/product-factory-v1.md docs/superpowers/plans/2026-09-02-product-factory-v1-roadmap.md
git commit -m "Verify GitHub and Wiki provisioning"
```

---

## Final Verification

- [ ] Run `mise exec -- bundle exec rake` and retain the exact example/offense counts.
- [ ] Run `git diff --check`.
- [ ] Run `git status --short` and confirm only intended files are present.
- [ ] Verify `git log --oneline origin/main..HEAD` contains the design, plan, and seven focused implementation commits.
- [ ] Inspect the live sandbox Project and Wiki URLs and record them in the pull request verification section.
- [ ] Confirm `Bootcamper Product Delivery` has the same Project ID, title, visibility, field count, and item count observed before this slice.
- [ ] Request independent code review before merge.
