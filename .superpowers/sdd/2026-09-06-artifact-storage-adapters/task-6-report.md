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

## Live-discovered field mutation regression

GitHub rejected the field update because `ProjectV2FieldConfiguration` is a union, so `id` cannot be selected directly. Schema introspection reported ProjectV2 Field, Iteration, MultiSelect, and SingleSelect union members. The mutation response is ignored, so selecting the union meta-field `__typename` avoids hard-coded fragments.

The existing Status-field writer example was strengthened before the mutation changed:

```text
mise exec -- bundle exec rspec spec/product_factory/github/writer_spec.rb

15 examples, 1 failure (seed 62315)
expected the query to include `projectV2Field { __typename }`;
received `projectV2Field { id }`
```

Changing only `UPDATE_FIELD` produced GREEN:

```text
mise exec -- bundle exec rspec spec/product_factory/github/writer_spec.rb

15 examples, 0 failures (seed 62516)
```

## Live gate

Exact command:

```text
PRODUCT_FACTORY_LIVE_GITHUB=LIT-Bootcamp/product-factory-sandbox \
  mise exec -- bundle exec rspec spec/live/github_repository_setup_spec.rb
```

The sandboxed attempt failed at clone DNS resolution, so the command was rerun with approved network access. Clone and the read-only default-config preflight succeeded; the sandbox has no checked-in config, so repository contents do not force the legacy Wiki adapter.

The missing Project scope was authorized and the exact command was rerun. It passed clone, configuration, Project snapshot, preview, and confirmation, then stopped on the first missing organization Issue Type before any GitHub mutation:

```text
1 example, 1 failure (seed 25180)

GitHub request failed (exit 1): gh: Not Found (HTTP 404)
This API operation needs the "admin:org" scope.
```

Only the temporary checkout received local setup files before the external request failed; the temporary directory was removed by the spec. No organization resource, application commit, or remote branch changed, and no push command exists in the spec. Successful live convergence/no-op remains unproved until `admin:org` is explicitly authorized and the same command is rerun.

The organization scope was then explicitly authorized. A later live run incrementally reconciled the sandbox until GitHub rejected the invalid field-update selection fixed above.

After the fix, the sandboxed exact command first failed at clone DNS resolution (`1 example, 1 failure`, seed `36116`). The same command was rerun with approved network access. It completed 101 operations, including the remaining Project fields and the Ideas view, then recorded:

```text
ProductFactory::ValidationError: verification failed for github:view:Epics
responsible_component: product_factory
recovery_action: rerun product-factory setup
```

Final live result:

```text
1 example, 1 failure (seed 34587)
Finished in 12 minutes 58 seconds
```

The local and remote application `HEAD` preservation assertions passed before the failed status assertion. The sandbox remains incrementally reconciled; no resources were deleted or reset. Per the live-failure stop rule, the Epics-view failure was recorded without attempting a second fix.

## Final local verification

```text
mise exec -- bundle exec rspec
208 examples, 0 failures (seed 41659)

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

- Live convergence/no-op remains unproved: the first setup now stops while verifying `github:view:Epics`. This is a separate failure and was intentionally not diagnosed or changed in this fix.
