# Product Factory

Product Factory installs a local, traceable foundation for incrementally turning product ideas into delivery work. Setup provisions factory files, organization Issue Types, one private GitHub Project, and factory-owned Wiki pages without using an LLM.

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

The repository Wiki must already have a manually created `Home` page. Product Factory never edits `Home`.

Same-name unowned resources require exact adoption after reviewing the collision:

```sh
bin/product-factory setup --adopt project
bin/product-factory setup --adopt issue-type:Idea
bin/product-factory setup --adopt wiki:_Sidebar
```

Low-level `plan` and `apply PLAN_PATH` remain available for local-file diagnosis.

## Live release gate

An organization owner must create the private `LIT-Bootcamp/product-factory-sandbox` repository and its first Wiki `Home` page once. The live test is excluded from normal CI and runs only with the exact confirmation:

```sh
PRODUCT_FACTORY_LIVE_GITHUB=LIT-Bootcamp/product-factory-sandbox \
  mise exec -- bundle exec rspec spec/live/github_wiki_setup_spec.rb
```
