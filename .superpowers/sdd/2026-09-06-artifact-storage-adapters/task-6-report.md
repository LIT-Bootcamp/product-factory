# Task 6 — End-to-End Artifact Storage Proof

## Scope

- Replaced the Wiki-only integration spec with real CLI/workflow coverage for default repository storage, legacy Wiki migration, Wiki-to-repository switching, and an already-converged destination switch.
- Replaced the live Wiki gate with the exact private repository gate for `LIT-Bootcamp/product-factory-sandbox`.
- Fixed one integration seam: by normalizing legacy `context_page` and `inventory_page` keys even after an explicit `artifacts` section is added.
- Left `spec/product_factory/cli_setup_spec.rb` and `spec/product_factory/setup/configuration_spec.rb` unchanged because the real integration path provided the required regression proof.

## RED

The replacement integration examples were written before the production fix.

```text
mise exec -- bundle exec rspec spec/integration/artifact_storage_setup_spec.rb

4 examples, 2 failures (seed 1216)
```

Both explicit Wiki-to-repository examples failed with:

```text
product.context_document is required
```

The legacy config normalized `context_page` and `inventory_page` only while `artifacts` was absent. Adding only the explicit repository adapter made the same legacy product keys invalid.

## GREEN

Moved the two legacy product-key normalizations ahead of adapter normalization in `ConfigValidator`. No coordinator, adapter API, dependency, or Git behavior was added.

```text
mise exec -- bundle exec rspec spec/integration/artifact_storage_setup_spec.rb

4 examples, 0 failures (seed 21377)
```

The integration examples prove:

- default repository setup creates exactly seven marked Markdown documents through two real CLI/workflow runs while preserving application `HEAD` and `origin`;
- a legacy v1 config, legacy installation keys, and seven legacy Wiki markers migrate to logical generic documents and generic installation state through a real bare Wiki remote;
- human `Home.md` and `_Sidebar.md` bytes are preserved and the second Wiki run is a no-op;
- an explicit repository switch creates all seven repository documents without changing Wiki bytes or `HEAD`, persists `repository`, and then no-ops;
- an adapter-only installation change persists when all seven destination documents already match and no artifact sync is planned.

## Live gate

Exact command:

```text
PRODUCT_FACTORY_LIVE_GITHUB=LIT-Bootcamp/product-factory-sandbox \
  mise exec -- bundle exec rspec spec/live/github_repository_setup_spec.rb
```

The sandboxed attempt failed at clone DNS resolution, so the command was rerun with approved network access. Clone and the read-only default-config preflight succeeded; the sandbox has no checked-in config, so repository contents do not force the legacy Wiki adapter.

The live gate remains externally blocked:

```text
1 example, 1 failure (seed 59697)

Your token has not been granted the required scopes to execute this query.
The 'id' field requires one of the following scopes: ['read:project'],
but your token has only been granted: ['gist', 'read:org', 'repo', 'workflow'].
```

Both setup calls stopped during the GitHub Project snapshot, before preview, confirmation, or apply. The live spec checks local and remote application `HEAD` before checking setup status; both assertions passed across the failed calls. No commit or push command exists in the spec or was run. Visibility, generated config/artifacts, installation state, and the successful second no-op remain unproved until the token has `read:project` and the same command is rerun.

## Final local verification

```text
mise exec -- bundle exec rspec
208 examples, 0 failures (seed 17118)

mise exec -- bundle exec rubocop
90 files inspected, no offenses detected

git diff --check
exit 0
```

Bundler's generated untracked `Gemfile.lock` was removed and is not part of the change.

## Self-review

- Repository paths and logical marker IDs are asserted from literal mappings rather than adapter constants.
- Legacy state begins on disk with `wiki_page_hashes` and `wiki_head`; persisted state contains only generic artifact fields.
- Wiki preservation compares the complete remote tree and revision across the adapter switch.
- The pre-populated destination example asserts that no `sync_artifacts` operation is planned, so the adapter-only installation branch is exercised directly.
- The live guard accepts only the exact opt-in repository and stops before setup if a checked-in config selects anything other than `repository` under `product/`.
- The live test contains no application commit, push, branch, or remote mutation path.

## Concerns

- External only: the current GitHub token lacks `read:project`, so the required successful live convergence/no-op proof cannot run to completion.
