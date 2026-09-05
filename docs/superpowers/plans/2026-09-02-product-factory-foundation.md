# Product Factory Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the deterministic Ruby runtime and a safe, resumable local setup/refresh flow that later GitHub and agent slices can extend without changing its contracts.

**Architecture:** A small Ruby CLI loads validated YAML, derives immutable operations, writes through an append-only JSONL journal, and synchronizes Product Factory files atomically. Planning is pure and mutation-free; apply consumes the saved plan after one confirmation, verifies each result, and resumes completed operations by stable ID.

**Tech Stack:** Ruby 4.0.6, Thor 1.5.0, Ruby standard library (`yaml`, `json`, `digest`, `fileutils`, `tempfile`, `open3`, `time`), RSpec, Rake

**Spec:** `docs/design/product-factory-v1.md`

## Global Constraints

- Use Ruby 4.0.6, the latest stable release when this plan was approved.
- Use Thor 1.5.x for the command interface; Rails already depends on Thor, so installed Rails projects gain no separate CLI stack.
- Use RSpec only; Minitest is forbidden.
- Load `spec_helper` once through `.rspec`; individual specs do not require it.
- Use `described_class` instead of repeating the class under test.
- Do not add FactoryBot in Slice 1 because the runtime has no domain model fixtures.
- Use no runtime gem dependency other than Thor and no Rails runtime coupling.
- Do not invoke an LLM or mutate GitHub in this slice.
- `plan` performs no filesystem mutation in the target repository.
- `apply` requires one explicit confirmation unless a previously confirmed run is being resumed.
- Setup never creates a branch, commit, push, or pull request.
- Managed writes are atomic; the journal is append-only JSON Lines.
- Preserve local-only changes; stop before apply when both local and upstream changed.
- Never store credentials or environment-variable values.
- Durable machine output and files are English.

---

## File map

```text
Gemfile                                      Development dependencies only
Rakefile                                     Default test task
.ruby-version                                Exact Ruby runtime
.rspec                                       RSpec output and load-path defaults
bin/product-factory                          Executable entry point
lib/product_factory.rb                       Version and requires
lib/product_factory/cli.rb                   Command parsing and user-facing exit codes
lib/product_factory/config.rb                Human config loading and validation
lib/product_factory/installation.rb          Machine state loading and atomic persistence
lib/product_factory/operation.rb             Immutable operation value object
lib/product_factory/plan.rb                  Immutable plan value object and JSON format
lib/product_factory/journal.rb                Append-only run event store
lib/product_factory/file_sync/                Three-way file planning and atomic writes
lib/product_factory/setup.rb                  Detect, plan, confirm, apply, verify orchestration
lib/product_factory/doctor.rb                 Environment checks
lib/product_factory/errors.rb                 Expected error classes
templates/config.yml                          Seed for initial human configuration
templates/project/bin/product-factory         Installed executable entry point
templates/project/.product-factory/spec/integration_spec.rb
                                               Installed RSpec runtime contract
templates/project/.product-factory/schemas/config-v1.yml
templates/project/.product-factory/schemas/installation-v1.yml
spec/spec_helper.rb                           Temporary repository helpers
spec/product_factory/*_spec.rb                Focused behavior specs
```

Public interfaces introduced here are intentionally concrete. Later slices add operation handlers to `Setup`; they do not introduce a generic plugin framework.

---

### Task 1: Executable Ruby skeleton

**Files:**
- Create: `Gemfile`
- Create: `Rakefile`
- Create: `.ruby-version`
- Create: `.rspec`
- Create: `bin/product-factory`
- Create: `lib/product_factory.rb`
- Create: `lib/product_factory/cli.rb`
- Create: `lib/product_factory/errors.rb`
- Create: `spec/spec_helper.rb`
- Test: `spec/product_factory/cli_spec.rb`

**Interfaces:**
- Produces: `ProductFactory::CLI.start(argv, input:, output:, error:, cwd:) -> Integer`
- Produces: `ProductFactory::VERSION -> String`

- [ ] **Step 1: Add the failing CLI contract test**

```ruby
# spec/product_factory/cli_spec.rb
RSpec.describe ProductFactory::CLI do
  describe ".start" do
    it "prints the version and succeeds" do
    output = StringIO.new

      status = described_class.start(["--version"], output: output)

      expect(status).to eq(0)
      expect(output.string).to eq("product-factory #{ProductFactory::VERSION}\n")
    end

    it "returns a usage error for an unknown command" do
      error = StringIO.new

      status = described_class.start(["unknown"], error: error)

      expect(status).to eq(64)
      expect(error.string).to include("Unknown command: unknown")
    end
  end
end
```

```ruby
# spec/spec_helper.rb
require "stringio"
require "tmpdir"
require_relative "../lib/product_factory"
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `bundle exec rspec spec/product_factory/cli_spec.rb`

Expected: FAIL because `ProductFactory::CLI` is undefined.

- [ ] **Step 3: Add the minimal executable and CLI**

```ruby
# lib/product_factory/errors.rb
module ProductFactory
  class Error < StandardError; end
  class UsageError < Error; end
  class ValidationError < Error; end
  class ConflictError < Error; end
end
```

```ruby
# lib/product_factory/cli.rb
module ProductFactory
  class CLI
    COMMANDS = %w[doctor plan apply validate test].freeze

    def self.start(argv, input: $stdin, output: $stdout, error: $stderr, cwd: Dir.pwd)
      return output.puts("product-factory #{VERSION}") || 0 if argv == ["--version"]

      Application.start(argv, output:, error:, cwd:)
    rescue UsageError => exception
      error.puts(exception.message)
      64
    rescue Error => exception
      error.puts(exception.message)
      1
    end
  end
end
```

`Application` is a Thor command class. Register `--version` as an alias for a `version` command, keep `doctor`, `plan`, `apply`, `validate`, and `test` as named fail-closed commands until their owning tasks replace them, and override Thor's failure behavior so `CLI.start` returns `64` for usage errors instead of terminating the Ruby process. Inject output/error streams through a small Thor shell adapter; never replace global `$stdout` or `$stderr`.

```ruby
# lib/product_factory.rb
module ProductFactory
  VERSION = "0.1.0"
end

require_relative "product_factory/errors"
require_relative "product_factory/cli"
```

```ruby
#!/usr/bin/env ruby
# bin/product-factory
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "product_factory"
exit ProductFactory::CLI.start(ARGV)
```

```ruby
# Rakefile
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec
```

```ruby
# Gemfile
source "https://rubygems.org"

ruby "4.0.6"

gem "rake", "~> 13.2"
gem "rspec", "~> 3.13"
gem "thor", "~> 1.5.0"
```

```text
# .ruby-version
4.0.6
```

```text
# .rspec
--require spec_helper
--format documentation
--color
```

- [ ] **Step 4: Keep unfinished commands fail-closed**

Replace the final `raise` in `CLI.start` with dispatch that continues to fail closed until each concrete command is wired:

```ruby
handler = {
  "doctor" => -> { raise UsageError, "doctor is not installed" },
  "plan" => -> { raise UsageError, "plan is not installed" },
  "apply" => -> { raise UsageError, "apply is not installed" },
  "validate" => -> { raise UsageError, "validate is not installed" },
  "test" => -> { raise UsageError, "test is not installed" }
}.fetch(command)
handler.call
```

This ensures no command reports false success between commits.

- [ ] **Step 5: Run the test suite and executable**

Run: `bundle install && bundle exec rake && bin/product-factory --version`

Expected: tests PASS and output is `product-factory 0.1.0`.

- [ ] **Step 6: Commit**

```bash
git add .ruby-version .rspec Gemfile Rakefile bin lib spec
git commit -m "Add Product Factory Ruby CLI"
```

---

### Task 2: Validated human configuration

**Files:**
- Create: `lib/product_factory/config.rb`
- Create: `templates/config.yml`
- Create: `templates/project/.product-factory/schemas/config-v1.yml`
- Modify: `lib/product_factory.rb`
- Test: `spec/product_factory/config_spec.rb`

**Interfaces:**
- Produces: `ProductFactory::Config.load(root) -> Config`
- Produces readers: `schema_version`, `product`, `github`, `research`, `workflow`, `agents`, `qa`, `knowledge`
- Produces: `Config#to_h -> Hash`

- [ ] **Step 1: Write failing tests for valid, missing, and unsafe YAML**

```ruby
# spec/product_factory/config_spec.rb
RSpec.describe ProductFactory::Config do
  it "loads v1 config and applies fixed defaults" do
    in_tmp_repo do |root|
      write(root, ".product-factory/config.yml", <<~YAML)
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
        research: { freshness_days: 30 }
        workflow:
          clarification_rounds: 3
          claim_lease_minutes: 60
          max_ticket_human_hours: 16
        agents: {}
        qa: { credential_env: {} }
        knowledge: { paths: [AGENTS.md] }
      YAML

      config = described_class.load(root)

      expect(config.schema_version).to eq(1)
      expect(config.product.fetch("name")).to eq("Bootcamper")
      expect(config.workflow.fetch("max_ticket_human_hours")).to eq(16)
    end
  end

  it "rejects missing required values" do
    in_tmp_repo do |root|
      write(root, ".product-factory/config.yml", "schema_version: 1\n")

      expect { described_class.load(root) }
        .to raise_error(ProductFactory::ValidationError, /product\.name is required/)
    end
  end

  it "rejects Ruby objects through safe YAML loading" do
    in_tmp_repo do |root|
      write(root, ".product-factory/config.yml", "--- !ruby/object:Object {}\n")

      expect { described_class.load(root) }
        .to raise_error(ProductFactory::ValidationError)
    end
  end
end
```

Add helpers to `spec/spec_helper.rb`:

```ruby
require "fileutils"

def in_tmp_repo
  Dir.mktmpdir("product-factory-test") { |root| yield root }
end

def write(root, relative_path, content)
  path = File.join(root, relative_path)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, content)
end

RSpec.configure do |config|
  config.include SpecHelpers
end
```

Wrap both helper methods in `module SpecHelpers` before including the module.

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `bundle exec rspec spec/product_factory/config_spec.rb`

Expected: FAIL because `ProductFactory::Config` is undefined.

- [ ] **Step 3: Implement safe loading and exact v1 validation**

```ruby
# lib/product_factory/config.rb
require "yaml"

module ProductFactory
  class Config
    PATH = ".product-factory/config.yml"
    REQUIRED = %w[
      product.name product.context_page product.inventory_page
      github.organization github.repository github.project_title
      research.freshness_days workflow.clarification_rounds
      workflow.claim_lease_minutes workflow.max_ticket_human_hours
    ].freeze

    attr_reader :schema_version, :product, :github, :research, :workflow,
                :agents, :qa, :knowledge

    def self.load(root)
      path = File.join(root, PATH)
      data = YAML.safe_load_file(path, aliases: false) || {}
      new(data)
    rescue Errno::ENOENT
      raise ValidationError, "Missing #{PATH}"
    rescue Psych::Exception => exception
      raise ValidationError, "Invalid #{PATH}: #{exception.message}"
    end

    def initialize(data)
      @data = stringify(data)
      @schema_version = @data["schema_version"]
      raise ValidationError, "schema_version must equal 1" unless schema_version == 1

      REQUIRED.each do |path|
        raise ValidationError, "#{path} is required" if fetch_path(path).nil?
      end

      @product = @data.fetch("product")
      @github = @data.fetch("github")
      @research = @data.fetch("research")
      @workflow = @data.fetch("workflow")
      @agents = @data.fetch("agents", {})
      @qa = @data.fetch("qa", {})
      @knowledge = @data.fetch("knowledge", {})
    end

    def to_h = @data.dup

    private

    def fetch_path(path)
      path.split(".").reduce(@data) { |value, key| value.is_a?(Hash) ? value[key] : nil }
    end

    def stringify(value)
      case value
      when Hash then value.to_h { |key, item| [key.to_s, stringify(item)] }
      when Array then value.map { |item| stringify(item) }
      else value
      end
    end
  end
end
```

Require it from `lib/product_factory.rb`:

```ruby
require_relative "product_factory/config"
```

- [ ] **Step 4: Add the canonical template and schema description**

Copy the exact approved YAML shape from design section 5 into `templates/config.yml`, using neutral sample values `Example Product`, `example-org`, and `example-repo`. This is a human-owned seed, not a factory file: setup writes it only when target configuration is absent, and later human edits are validated but never hash-restored. Store a documentation-only field contract in `config-v1.yml` with each path, type, required flag, and fixed default. `Config` remains the executable validator; no schema gem is introduced.

- [ ] **Step 5: Run focused and full tests**

Run: `bundle exec rspec spec/product_factory/config_spec.rb && bundle exec rake`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib templates spec
git commit -m "Validate Product Factory configuration"
```

---

### Task 3: Atomic installation state

**Files:**
- Create: `lib/product_factory/installation.rb`
- Create: `templates/project/.product-factory/schemas/installation-v1.yml`
- Modify: `lib/product_factory.rb`
- Test: `spec/product_factory/installation_spec.rb`

**Interfaces:**
- Produces: `Installation.load(root) -> Installation`
- Produces: `Installation.empty -> Installation`
- Produces: `Installation#write(root) -> void`
- Produces: `Installation#factory_file_hashes -> Hash<String,String>`
- Produces: `Installation#with(attributes) -> Installation`

- [ ] **Step 1: Write the failing round-trip and atomicity tests**

```ruby
# spec/product_factory/installation_spec.rb
RSpec.describe ProductFactory::Installation do
  it "loads missing state as empty and round-trips atomically" do
    in_tmp_repo do |root|
      installation = described_class.load(root)
      installation = installation.with(
        "factory_version" => "0.1.0",
        "factory_file_hashes" => { ".product-factory/runtime/lib/product_factory.rb" => "abc" }
      )

      installation.write(root)
      loaded = described_class.load(root)

      expect(loaded.factory_version).to eq("0.1.0")
      expect(loaded.factory_file_hashes).to eq({ ".product-factory/runtime/lib/product_factory.rb" => "abc" })
      expect(File).not_to exist(File.join(root, ".product-factory/installation.yml.tmp"))
    end
  end
end
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `bundle exec rspec spec/product_factory/installation_spec.rb`

Expected: FAIL because `Installation` is undefined.

- [ ] **Step 3: Implement immutable state and same-directory atomic rename**

```ruby
# lib/product_factory/installation.rb
require "fileutils"
require "time"
require "yaml"

module ProductFactory
  class Installation
    PATH = ".product-factory/installation.yml"
    DEFAULTS = {
      "schema_version" => 1,
      "factory_version" => nil,
      "installed_at" => nil,
      "installed_by" => nil,
      "github_resource_ids" => {},
      "factory_file_hashes" => {},
      "last_successful_setup_run" => nil,
      "pending_operations" => []
    }.freeze

    def self.load(root)
      path = File.join(root, PATH)
      return empty unless File.exist?(path)

      new(YAML.safe_load_file(path, aliases: false) || {})
    rescue Psych::Exception => exception
      raise ValidationError, "Invalid #{PATH}: #{exception.message}"
    end

    def self.empty = new(DEFAULTS)

    def initialize(data)
      @data = DEFAULTS.merge(data.transform_keys(&:to_s)).freeze
      raise ValidationError, "installation schema_version must equal 1" unless @data["schema_version"] == 1
    end

    def factory_version = @data["factory_version"]
    def factory_file_hashes = @data["factory_file_hashes"].dup
    def pending_operations = @data["pending_operations"].dup
    def to_h = @data.dup
    def with(attributes) = self.class.new(@data.merge(attributes.transform_keys(&:to_s)))

    def write(root)
      path = File.join(root, PATH)
      temporary = "#{path}.tmp"
      FileUtils.mkdir_p(File.dirname(path))
      File.write(temporary, YAML.dump(@data))
      File.rename(temporary, path)
    ensure
      File.delete(temporary) if temporary && File.exist?(temporary)
    end
  end
end
```

- [ ] **Step 4: Add the installation schema description and require**

Record the exact keys from `DEFAULTS`, their types, and machine-managed ownership in `installation-v1.yml`. Add `require_relative "product_factory/installation"` to `lib/product_factory.rb`.

- [ ] **Step 5: Run tests and commit**

Run: `bundle exec rake`

Expected: PASS.

```bash
git add lib templates spec
git commit -m "Persist Product Factory installation state"
```

---

### Task 4: Immutable operations and serializable plans

**Files:**
- Create: `lib/product_factory/operation.rb`
- Create: `lib/product_factory/plan.rb`
- Modify: `lib/product_factory.rb`
- Test: `spec/product_factory/plan_spec.rb`

**Interfaces:**
- Produces: `Operation.new(kind:, target:, attributes:)`
- Produces: `Operation#id -> String`, SHA-256 of canonical operation data
- Produces: `Operation#to_h -> Hash`
- Produces: `Plan.new(run_id:, mode:, operations:, conflicts:)`
- Produces: `Plan#applicable?`, `Plan#write(path)`, `Plan.load(path)`

- [ ] **Step 1: Write failing determinism and round-trip tests**

```ruby
# spec/product_factory/plan_spec.rb
RSpec.describe ProductFactory::Plan do
  it "keeps operation IDs stable across hash order" do
    first = ProductFactory::Operation.new(kind: "write_file", target: "a", attributes: { "b" => 2, "a" => 1 })
    second = ProductFactory::Operation.new(kind: "write_file", target: "a", attributes: { "a" => 1, "b" => 2 })

    expect(first.id).to eq(second.id)
  end

  it "cannot apply a plan with conflicts" do
    plan = described_class.new(run_id: "RUN-1", mode: "refresh", operations: [], conflicts: [{ "path" => "a" }])

    expect(plan).not_to be_applicable
  end
end
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `bundle exec rspec spec/product_factory/plan_spec.rb`

Expected: FAIL because the value objects are undefined.

- [ ] **Step 3: Implement canonical JSON hashing and JSON plan persistence**

```ruby
# lib/product_factory/operation.rb
require "digest"
require "json"

module ProductFactory
  class Operation
    attr_reader :kind, :target, :attributes

    def initialize(kind:, target:, attributes: {})
      @kind = kind.to_s
      @target = target.to_s
      @attributes = canonical(attributes)
      freeze
    end

    def id = Digest::SHA256.hexdigest(JSON.generate(to_h))[0, 20]
    def to_h = { "kind" => kind, "target" => target, "attributes" => attributes }

    private

    def canonical(value)
      case value
      when Hash
        value.keys.sort_by(&:to_s).to_h { |key| [key.to_s, canonical(value.fetch(key))] }
      when Array then value.map { |item| canonical(item) }
      else value
      end
    end
  end
end
```

```ruby
# lib/product_factory/plan.rb
require "json"

module ProductFactory
  class Plan
    attr_reader :run_id, :mode, :operations, :conflicts

    def initialize(run_id:, mode:, operations:, conflicts: [])
      @run_id = run_id
      @mode = mode
      @operations = operations.freeze
      @conflicts = conflicts.freeze
    end

    def applicable? = conflicts.empty?

    def to_h
      { "run_id" => run_id, "mode" => mode, "operations" => operations.map(&:to_h), "conflicts" => conflicts }
    end

    def write(path) = File.write(path, JSON.pretty_generate(to_h) + "\n")

    def self.load(path)
      data = JSON.parse(File.read(path))
      operations = data.fetch("operations").map do |item|
        Operation.new(kind: item.fetch("kind"), target: item.fetch("target"), attributes: item.fetch("attributes"))
      end
      new(run_id: data.fetch("run_id"), mode: data.fetch("mode"), operations: operations, conflicts: data.fetch("conflicts"))
    end
  end
end
```

- [ ] **Step 4: Require both files and run tests**

Add the two requires after `errors` in `lib/product_factory.rb`.

Run: `bundle exec rake`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib spec
git commit -m "Add deterministic setup plans"
```

---

### Task 5: Three-way factory-file planning

**Files:**
- Create: `lib/product_factory/file_sync.rb`
- Modify: `lib/product_factory.rb`
- Test: `spec/product_factory/file_sync/planner_spec.rb`

**Interfaces:**
- Produces: `FileSync::Planner.call(sources:, target_root:, installed_hashes:, resolutions: {}) -> Hash`
- Result keys: `operations`, `conflicts`, `next_hashes`
- Produces: `FileSync::Target#apply(operation) -> void`

- [ ] **Step 1: Write a four-case truth-table test**

```ruby
# spec/product_factory/file_sync/planner_spec.rb
RSpec.describe ProductFactory::FileSync::Planner do
  it "implements the three-way refresh truth table" do
    in_tmp_repo do |source|
      in_tmp_repo do |target|
        write(source, "managed/a.txt", "upstream-v1\n")
        sources = { "a.txt" => File.join(source, "managed/a.txt") }
        files = described_class.new(sources: sources)
        initial = files.plan(target_root: target, installed_hashes: {})
        files.apply(initial.fetch(:operations).first, target_root: target)
        old_hashes = initial.fetch(:next_hashes)

        expect(files.plan(target_root: target, installed_hashes: old_hashes).fetch(:operations)).to be_empty

        write(target, "a.txt", "local-only\n")
        expect(files.plan(target_root: target, installed_hashes: old_hashes).fetch(:operations)).to be_empty

        write(source, "managed/a.txt", "upstream-v2\n")
        conflict = files.plan(target_root: target, installed_hashes: old_hashes)
        expect(conflict.fetch(:conflicts).map { |item| item.fetch("path") }).to eq(["a.txt"])

        resolved = files.plan(target_root: target, installed_hashes: old_hashes, resolutions: { "a.txt" => "take_upstream" })
        expect(resolved.fetch(:operations).length).to eq(1)
      end
    end
  end
end
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `bundle exec rspec spec/product_factory/file_sync/planner_spec.rb`

Expected: FAIL because `FileSync::Planner` is undefined.

- [ ] **Step 3: Implement hashing and the exact decision table**

`FileSync::Planner` must enumerate the target-relative keys of `sources` in sorted order and compare:

```ruby
installed = installed_hashes[path]
local = hash_if_file(File.join(target_root, path))
upstream = hash_if_file(sources.fetch(path))

decision = if installed.nil?
  local.nil? ? :write_upstream : (local == upstream ? :adopt : :conflict)
elsif local == installed && upstream != installed
  :write_upstream
elsif local != installed && upstream == installed
  :preserve_local
elsif local == upstream
  :adopt
elsif local != installed && upstream != installed
  :conflict
else
  :noop
end
```

For a conflict, accept only `keep_local`, `take_upstream`, or `manual_merge`. `manual_merge` remains a conflict until the local file hash equals the explicitly recorded merged hash. Every conflict object contains `path`, `installed_hash`, `local_hash`, `upstream_hash`, and `resolution`.

Write operations contain base64-encoded bytes and mode, so apply does not depend on changing source files. Use `Tempfile.create` in the destination directory, `flush`, `fsync`, `chmod`, and `rename` for atomic replacement. Reject symlinks in both source and target.

- [ ] **Step 4: Add deletion behavior only for previously installed factory files**

Add tests and implementation for an upstream removal:

- unchanged previously managed local file -> `delete_file` operation;
- locally changed factory file -> conflict;
- never-managed local file -> untouched.

Deletion is limited to the exact relative file path recorded in `installed_hashes`; directories are removed only when empty.

- [ ] **Step 5: Run focused and full tests**

Run: `bundle exec rspec spec/product_factory/file_sync/planner_spec.rb && bundle exec rake`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib spec
git commit -m "Plan safe factory-file refreshes"
```

---

### Task 6: Append-only journal and resumable executor

**Files:**
- Create: `lib/product_factory/journal.rb`
- Create: `lib/product_factory/executor.rb`
- Modify: `lib/product_factory.rb`
- Test: `spec/product_factory/executor_spec.rb`

**Interfaces:**
- Produces: `Journal.new(path:, clock:)`
- Produces: `Journal#append(event)`, `Journal#events`, `Journal#completed_operation_ids(run_id)`
- Produces: `Executor.new(journal:, handlers:)`
- Produces: `Executor#apply(plan) -> :success`
- Handler contract: `call(operation) -> void`

- [ ] **Step 1: Write the interrupted-resume test**

```ruby
# spec/product_factory/executor_spec.rb
RSpec.describe ProductFactory::Executor do
  it "skips verified completed operations when resuming" do
    in_tmp_repo do |root|
      journal = ProductFactory::Journal.new(path: File.join(root, "journal.jsonl"), clock: -> { Time.utc(2026, 9, 2) })
      calls = []
      applied = []
      operations = %w[a b c].map { |name| ProductFactory::Operation.new(kind: "record", target: name) }
      plan = ProductFactory::Plan.new(run_id: "RUN-1", mode: "setup", operations: operations)
      fail_once = true
      apply = lambda do |operation|
        calls << operation.target
        if operation.target == "b" && fail_once
          fail_once = false
          raise ProductFactory::Error, "interrupted"
        end
        applied << operation.target
      end
      verify = ->(operation) { applied.include?(operation.target) }
      handler = { apply: apply, verify: verify }
      executor = described_class.new(journal: journal, handlers: { "record" => handler })

      expect { executor.apply(plan) }.to raise_error(ProductFactory::Error, "interrupted")
      expect(executor.apply(plan)).to eq(:success)
      expect(calls).to eq(%w[a b b c])
    end
  end
end
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `bundle exec rspec spec/product_factory/executor_spec.rb`

Expected: FAIL because `Journal` and `Executor` are undefined.

- [ ] **Step 3: Implement durable JSONL events**

Each append opens with `File::WRONLY | File::CREAT | File::APPEND`, writes one compact JSON object plus newline, flushes, and calls `fsync`. Every event receives `recorded_at`. Parsing an invalid or truncated line raises `ValidationError` with its line number; it is never silently discarded.

Event forms:

```json
{"event":"run_confirmed","run_id":"RUN-1","recorded_at":"2026-09-02T00:00:00Z"}
{"event":"operation_started","run_id":"RUN-1","operation_id":"abc","recorded_at":"..."}
{"event":"operation_completed","run_id":"RUN-1","operation_id":"abc","recorded_at":"..."}
{"event":"operation_failed","run_id":"RUN-1","operation_id":"abc","error_class":"ProductFactory::Error","message":"interrupted","recorded_at":"..."}
{"event":"run_completed","run_id":"RUN-1","status":"success","recorded_at":"..."}
```

- [ ] **Step 4: Implement executor resumption**

Before skipping a completed operation, call its handler's optional verifier:

```ruby
Handlers are hashes containing callable `apply` and `verify` values.
```

`verify.call(operation)` returns true only when target state matches. A missing verifier is a configuration error. If verification fails, execute the operation again. Append started/completed/failed events around each call and a final run-completed event only after every operation verifies.

- [ ] **Step 5: Run tests and commit**

Run: `bundle exec rake`

Expected: PASS.

```bash
git add lib spec
git commit -m "Resume journaled factory operations"
```

---

### Task 7: Local setup orchestration

**Files:**
- Create: `lib/product_factory/setup.rb`
- Create: `lib/product_factory/run_id.rb`
- Modify: `lib/product_factory/cli.rb`
- Modify: `lib/product_factory.rb`
- Test: `spec/product_factory/setup_spec.rb`
- Test: `spec/product_factory/cli_setup_spec.rb`

**Interfaces:**
- Produces: `RunId.generate(clock:, random:) -> String`
- Produces: `Setup.new(distribution_root:, target_root:, input:, output:, clock:)`
- Produces: `Setup#plan(resolutions: {}) -> Plan`
- Produces: `Setup#apply(plan) -> :success | :declined`
- CLI: `product-factory plan [--resolve PATH=keep_local|take_upstream|manual_merge]`
- CLI: `product-factory apply PLAN_PATH`

- [ ] **Step 1: Write a failing setup/no-op integration test**

```ruby
# spec/product_factory/setup_spec.rb
RSpec.describe ProductFactory::Setup do
  it "applies an initial setup and plans the next refresh as a no-op" do
    in_tmp_repo do |target|
      setup = described_class.new(
        distribution_root: File.expand_path("../..", __dir__),
        target_root: target,
        input: StringIO.new("yes\n"),
        output: StringIO.new,
        clock: -> { Time.utc(2026, 9, 2) }
      )

      first = setup.plan
      expect(first.mode).to eq("setup")
      expect(first).to be_applicable
      expect(setup.apply(first)).to eq(:success)

      second = setup.plan
      expect(second.mode).to eq("refresh")
      expect(second.operations).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `bundle exec rspec spec/product_factory/setup_spec.rb`

Expected: FAIL because `Setup` is undefined.

- [ ] **Step 3: Implement setup detection and plan persistence**

Mode is `setup` when `.product-factory/installation.yml` is absent and `refresh` otherwise. Build the factory source map deterministically:

```ruby
sources = {}
Dir.glob(File.join(distribution_root, "lib/**/*.rb")).sort.each do |source|
  relative = source.delete_prefix("#{distribution_root}/")
  sources[File.join(".product-factory/runtime", relative)] = source
end
Dir.glob(File.join(distribution_root, "templates/project/**/*"), File::FNM_DOTMATCH).sort.each do |source|
  next unless File.file?(source)

  relative = source.delete_prefix("#{distribution_root}/templates/project/")
  sources[relative] = source
end
```

When target `.product-factory/config.yml` is missing, add one `seed_config` operation containing the rendered `templates/config.yml`; do not include it in `factory_file_hashes`. When it exists, load and preserve it. Plans are saved outside the target repository at `Dir.tmpdir/product-factory-<run-id>.json`, so planning does not mutate the target.

Create the installed executable:

```ruby
#!/usr/bin/env ruby
# templates/project/bin/product-factory
$LOAD_PATH.unshift(File.expand_path("../.product-factory/runtime/lib", __dir__))
require "product_factory"
exit ProductFactory::CLI.start(ARGV)
```

Create the installed RSpec runtime contract:

```ruby
# templates/project/.product-factory/spec/integration_spec.rb
runtime_lib = File.expand_path("../runtime/lib", __dir__)
$LOAD_PATH.unshift(runtime_lib)
require "product_factory"

RSpec.describe "installed Product Factory runtime" do
  it "loads and validates its installation" do
    root = File.expand_path("../..", __dir__)

    expect(ProductFactory::Config.load(root)).to be_a(ProductFactory::Config)
    expect(ProductFactory::Installation.load(root)).to be_a(ProductFactory::Installation)
    expect(ProductFactory::Validator.call(root: root)).to eq(true)
  end
end
```

Generate run IDs as:

```ruby
"RUN-#{clock.call.utc.strftime('%Y%m%dT%H%M%SZ')}-#{random.hex(4)}"
```

The plan output lists mode, target, every operation ID/kind/path, every conflict and available resolution, and the plan path.

- [ ] **Step 4: Implement one confirmation and apply**

`Setup#apply`:

1. rejects a plan with conflicts;
2. checks `run_confirmed`; if absent, prints the exact operation count and asks `Apply this plan? [yes/no]`;
3. accepts only the literal `yes`;
4. records confirmation before the first mutation;
5. applies and verifies file operations through `Executor`;
6. writes installation state as the final operation, including new hashes, version, actor from `ENV.fetch("USER", "unknown")`, run ID, and no pending operations;
7. re-loads state and verifies every managed hash.

A resumed confirmed plan does not ask again.

- [ ] **Step 5: Wire `plan` and `apply` CLI commands**

Replace the two fail-closed handlers with:

```ruby
"plan" => -> { Setup::Runner.from_cli(cwd:, input:, output:).plan_and_print(argv) },
"apply" => -> { Setup::Runner.from_cli(cwd:, input:, output:).load_and_apply(argv.fetch(0)) }
```

Add tests that assert:

- `plan` leaves target `git status --porcelain` unchanged;
- `apply` with `no` returns status 0 and changes nothing;
- `apply` with `yes` installs files;
- a conflict makes `plan` return status 2 and `apply` refuse;
- no command calls `git commit`, `git push`, or `gh`.

- [ ] **Step 6: Run focused and full tests**

Run: `bundle exec rspec spec/product_factory/setup_spec.rb spec/product_factory/cli_setup_spec.rb && bundle exec rake`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib spec templates
git commit -m "Add local setup and refresh flow"
```

---

### Task 8: Doctor, validate, and test commands

**Files:**
- Create: `lib/product_factory/doctor.rb`
- Create: `lib/product_factory/validator.rb`
- Modify: `lib/product_factory/cli.rb`
- Modify: `lib/product_factory.rb`
- Test: `spec/product_factory/doctor_spec.rb`
- Test: `spec/product_factory/validator_spec.rb`

**Interfaces:**
- Produces: `Doctor::Runner.call(root:, command_runner:) -> Array<Check>`
- `Check = Data.define(:name, :status, :message)` where status is `:pass`, `:warn`, or `:fail`
- Produces: `Validator.call(root:) -> true`, raises `ValidationError` on failure
- CLI commands: `doctor`, `validate`, `test`

- [ ] **Step 1: Write failing environment and installation validation tests**

```ruby
# spec/product_factory/doctor_spec.rb
RSpec.describe ProductFactory::Doctor::Runner do
  it "reports missing gh without running setup" do
    runner = ->(*command) { command == ["ruby", "--version"] ? [true, "ruby 3.3.0"] : [false, "missing"] }
    checks = described_class.new(root: Dir.pwd, command_runner: runner).call

    expect(checks.find { |check| check.name == "ruby" }.status).to eq(:pass)
    expect(checks.find { |check| check.name == "gh" }.status).to eq(:fail)
  end
end
```

```ruby
# spec/product_factory/validator_spec.rb
RSpec.describe ProductFactory::Validator do
  it "rejects a modified factory file" do
    in_tmp_repo do |root|
      config_template = File.expand_path("../../templates/config.yml", __dir__)
      write(root, ".product-factory/config.yml", File.read(config_template))
      write(root, ".product-factory/runtime/lib/product_factory.rb", "changed\n")
      ProductFactory::Installation.empty.with(
        "factory_file_hashes" => { ".product-factory/runtime/lib/product_factory.rb" => "not-the-current-hash" }
      ).write(root)

      expect { described_class.new(root: root).call }
        .to raise_error(ProductFactory::ValidationError, /\.product-factory\/runtime\/lib\/product_factory\.rb/)
    end
  end
end
```

- [ ] **Step 2: Run focused tests and confirm RED**

Run: `bundle exec rspec spec/product_factory/doctor_spec.rb spec/product_factory/validator_spec.rb`

Expected: FAIL because both classes are undefined.

- [ ] **Step 3: Implement deterministic checks**

Doctor checks, without mutation:

- Ruby version is exactly 4.0.6;
- `git --version` succeeds;
- `gh --version` succeeds;
- target is inside a Git work tree;
- config and installation files are readable when present;
- configured knowledge paths exist when an installation exists.

Use `Open3.capture3(*command)` through an injected runner. Never construct a shell string.

Validator checks:

- configuration validity;
- installation schema validity;
- every installed factory file exists and matches its recorded SHA-256; human-owned `.product-factory/config.yml` is validated semantically and is not hash-compared;
- pending operations are empty after a successful run;
- the journal parses completely;
- no credential environment-variable value appears in config or installation state.

- [ ] **Step 4: Wire commands and exact exit behavior**

- `doctor`: print one line per check and return 1 if any check fails;
- `validate`: print `Product Factory installation is valid` and return 0, otherwise the validation error and 1;
- `test`: execute RSpec using argument arrays and return its status. In the distribution repository this is `bundle exec rspec`; in an installed project it is `bundle exec rspec .product-factory/spec/integration_spec.rb`.

Installation fails validation if the installed test runner is absent; it never claims success without executing the check.

- [ ] **Step 5: Run all gates**

Run:

```bash
bundle exec rake
bin/product-factory doctor
bin/product-factory validate
git diff --check
```

Expected: test suite PASS; Doctor reports the real local environment; Validate reports the distribution repository is not an installed target with a clear non-zero result; diff check is clean.

- [ ] **Step 6: Commit**

```bash
git add lib spec
git commit -m "Validate Product Factory installations"
```

---

### Task 9: End-to-end local setup release gate

**Files:**
- Create: `spec/integration/local_setup_spec.rb`
- Create: `.github/workflows/ci.yml`
- Create: `README.md`
- Modify: `templates/config.yml`

**Interfaces:**
- Consumes all Slice 1 interfaces.
- Produces one documented local workflow and a CI gate for Ruby 4.0.6.

- [ ] **Step 1: Write the end-to-end failure matrix**

Create one RSpec file with independent temporary-target examples for:

1. initial setup plan is mutation-free;
2. declined apply changes nothing;
3. accepted apply installs and validates;
4. immediate refresh is No-op;
5. upstream-only change updates;
6. local-only change is preserved;
7. both-changed conflict blocks all apply operations;
8. accepted `take_upstream` resolves and logs its reason;
9. interruption after operation two resumes at operation three after verifying one and two;
10. a corrupted journal fails closed with its line number;
11. a symlinked source or destination fails closed;
12. target Git history and remotes remain unchanged.

Use a fake distribution directory copied from `templates/project`; never edit the real templates inside a test.

- [ ] **Step 2: Run the E2E file and observe any missing behavior**

Run: `bundle exec rspec spec/integration/local_setup_spec.rb`

Expected before corrections: at least one assertion exposes any integration gap between Tasks 1-8. Record the exact failure in the commit body if the correction changes a public interface.

- [ ] **Step 3: Make only the corrections required by the matrix**

Do not add GitHub clients, Wiki code, agents, skills, Rails fixtures, or future phase abstractions. Corrections stay inside the concrete Slice 1 files named by the failing assertion.

- [ ] **Step 4: Add CI**

```yaml
# .github/workflows/ci.yml
name: CI

on:
  pull_request:

permissions:
  contents: read

jobs:
  test:
    strategy:
      matrix:
        ruby: ["4.0.6"]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: ${{ matrix.ruby }}
          bundler-cache: true
      - run: bundle exec rake
      - run: git diff --check
```

- [ ] **Step 5: Document only the working interface**

`README.md` contains:

- Product Factory's one-sentence purpose;
- v1 scope link to the design;
- Ruby requirement;
- `bundle install`, `bundle exec rake`, and `bin/product-factory --version`;
- Slice 1 local `plan` and `apply` example;
- an explicit note that GitHub provisioning and agent phases are not present until later roadmap slices.

- [ ] **Step 6: Run the final Slice 1 gate**

Run:

```bash
bundle exec rake
git diff --check
git status --short
```

Expected: all tests PASS, no whitespace errors, and only Task 9 files are uncommitted.

- [ ] **Step 7: Commit**

```bash
git add .github README.md templates test lib
git commit -m "Verify local Product Factory setup end to end"
```

## Slice 1 completion proof

Before planning Slice 2, capture:

```text
Ruby versions tested:
Test command and example count:
Initial setup operation count:
Immediate refresh operation count (must be 0):
Conflict fixture and blocked operation count (must be all):
Interrupted run completed operation IDs before and after resume:
Git status before plan and after plan (must match):
Git HEAD and remotes before and after apply (must match):
```

Do not mark Slice 1 complete unless each value is produced by the test run rather than inferred.
