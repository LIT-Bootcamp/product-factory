# Product Factory

Product Factory installs a local, traceable foundation for incrementally turning product ideas into delivery work. Setup provisions factory files, organization Issue Types, one private GitHub Project, and canonical Markdown artifacts without using an LLM.

## Requirements

- Ruby 4.0.6
- Bundler
- Git
- GitHub CLI (`gh`)

## Development

```sh
bundle install
bundle exec rake
bin/product-factory --version
```

The default Rake task runs the complete RSpec suite and RuboCop.

## Setup

Run this from an existing application repository with a GitHub `origin`:

```sh
bin/product-factory setup
bin/product-factory doctor
bin/product-factory validate
bin/product-factory test
```

Setup performs a mutation-free preflight, prints one complete plan, and asks for one `yes`. An interrupted confirmed run resumes automatically. A repeated converged run reports `Product Factory is up to date`.

New installations store canonical artifacts in the application repository by default:

```yaml
artifacts:
  adapter: repository
  root: product
```

Setup creates this local tree:

```text
product/
  README.md
  setup-log.md
  ideas/README.md
  epics/README.md
  tickets/README.md
  research/README.md
  factory-runs/README.md
```

Setup leaves `product/**` uncommitted. The normal delivery flow owns its review, commit, and push.

GitHub Wiki remains available as an optional adapter:

```yaml
artifacts:
  adapter: wiki
```

The Wiki adapter requires a manually created `Home` page and never edits it.

Same-name unowned resources require exact adoption after reviewing the collision:

```sh
bin/product-factory setup --adopt project
bin/product-factory setup --adopt issue-type:Idea
bin/product-factory setup --adopt artifact:ideas/index
```

Low-level `plan` and `apply PLAN_PATH` remain available for local-file diagnosis.

## Live release gate

An organization owner must create the private `LIT-Bootcamp/product-factory-sandbox` repository once. The live test is excluded from normal CI and runs only with the exact confirmation:

```sh
PRODUCT_FACTORY_LIVE_GITHUB=LIT-Bootcamp/product-factory-sandbox \
  mise exec -- bundle exec rspec spec/live/github_repository_setup_spec.rb
```
