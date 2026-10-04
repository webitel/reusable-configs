# reusable-configs

Workflows and configs shared by Webitel repositories. Each stack directory is synced to its repositories by
[file-sync](https://github.com/webitel/reusable-workflows/tree/main/actions/file-sync)
(`.github/workflows/sync.yml`), which opens one pull request per repository whenever something here changes.

| Directory | Repositories |
|---|---|
| `golang/` | Go services and tools |
| `python/` | Python services |
| `node/` | Front-end applications |
| `clang/` | FreeSWITCH modules, PostgreSQL extensions |
| `common/` | Files shared by several stacks |

A new stack is a new directory with a `sync.yml`; the sync workflow picks it up without changes.

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

The **Sync** workflow runs on every push to `main` for the stacks it changed (all of them when `common/` changes), and
daily for every stack. Run it manually to sync one stack (or all, when left empty), with **dry-run** to preview without
pushing anything. The pinned **File sync status** issue shows the state of every repository.
