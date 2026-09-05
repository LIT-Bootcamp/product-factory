# Product Factory

Product Factory installs a local, traceable foundation for incrementally turning product ideas into delivery work.

Slice 1 provides only safe local setup, refresh, health checks, validation, and RSpec execution. See the [v1 design](docs/design/product-factory-v1.md) for the planned product workflow.

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

## Local setup

Planning does not modify the target project. Apply the generated plan only after reviewing its printed operations:

```sh
bin/product-factory plan
bin/product-factory apply /tmp/product-factory-RUN-....json
bin/product-factory doctor
bin/product-factory validate
bin/product-factory test
```

GitHub Project provisioning, Wiki publishing, and Ideator/BA/TL/PM/Engineer/QA agent phases are intentionally deferred to later roadmap slices.
