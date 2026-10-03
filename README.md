# reusable-configs

Workflows and configs shared by Webitel repositories. Each stack directory is synced to its repositories by
[file-sync](https://github.com/webitel/reusable-workflows/tree/main/actions/file-sync), which opens one pull request
per repository whenever something here changes.

| Directory | Repositories | Sync workflow |
|---|---|---|
| `golang/` | Go services and tools | `.github/workflows/sync-golang.yml` |
| `python/` | Python services | `.github/workflows/sync-python.yml` |
| `node/` | Front-end applications | `.github/workflows/sync-node.yml` |
| `clang/` | FreeSWITCH modules, PostgreSQL extensions | `.github/workflows/sync-clang.yml` |
| `common/` | Files shared by several stacks | — |

## `<stack>/sync.yml`

```yml
defaults:            # template variables of every repository
  version: v2

files:               # synced to every repository; .njk files are rendered with the repository's variables
  - source: golang/workflows/workflow.yml.njk
    dest: .github/workflows/workflow.yml
  - source: common/deploy/debian/postinst.sh
    dest: deploy/debian/postinst.sh
    when: service    # only repositories where `service` is true

repos:               # one entry per repository: its variables, deep-merged over defaults
  webitel/cases:
    name: webitel-cases
    build:
      binary-name: webitel-cases
```

Templates use `((( variable )))` for variables, so GitHub Actions expressions (`${{ }}`) pass through untouched.
The flags used by `when` are described at the top of each `sync.yml`.

### Adding a repository

1. Add an entry under `repos` in the stack's `sync.yml` with its variables (copy a similar repository).
2. Make sure the Delivery bot GitHub App is installed on it.

The sync workflow takes its token scope from `repos`, so nothing else needs to change. The first sync opens a pull
request with all files, a manifest (`.github/file-sync/<stack>-sync.yml`) and "DO NOT EDIT" headers.

## Running a sync

Syncs run on every push to `main` that touches the stack or `common/`, and daily. To preview without pushing anything,
run the stack's sync workflow manually with **dry-run**. The pinned **File sync status** issue shows the state of every
repository.
