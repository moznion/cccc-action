# cccc-action

A GitHub composite action that installs the
[`cccc`](https://github.com/moznion/cccc) complexity analyzer from a GitHub
release (matching the runner's OS/arch, verified by SHA-256) and adds it to
`PATH`. If you pass `path`, it also runs cccc as a Cognitive/Cyclomatic
complexity gate.

`cccc` is a single binary that measures **Cognitive Complexity** (SonarSource)
and **Cyclomatic Complexity** (McCabe) across multiple languages:
TypeScript/JavaScript (`es`), Rust (`rust`/`rs`), Go (`go`), and PHP (`php`).

## Analysis is configured via `cccc.toml`

Analysis behavior — languages, excludes, extensions, complexity thresholds,
`.gitignore` handling, parallelism, table output — is configured in cccc's own
config file (`cccc.toml` / `.cccc.toml`), **not** through action inputs. This
keeps a single source of truth and avoids the action drifting out of sync as
cccc's options evolve. cccc auto-discovers the file by walking up from the
working directory.

```toml
# cccc.toml
languages         = ["es", "go"]     # restrict to these languages
exclude-languages = ["php"]          # or exclude specific ones
exclude           = ["dist/**", "**/*.test.ts"]
table             = false
max-cognitive     = 15               # gate: fail if any function exceeds this
max-cyclomatic    = 20
min               = 1
no-ignore         = false
jobs              = 8

[ext]
es = ["ts", "tsx"]                   # narrow / route extensions per language
go = ["go", "tmpl"]
```

The action only exposes the knobs cccc offers **on the command line only**
(`top-cognitive`, `top-cyclomatic`), plus config-file selection and an `args`
escape hatch. See [the cccc docs](https://github.com/moznion/cccc) for the full
config reference.

## Usage

### Run it as a CI gate

Put your thresholds in `cccc.toml` (committed to the repo), then:

```yaml
- uses: moznion/cccc-action@v1
  with:
    path: src/           # analyze this; thresholds come from cccc.toml
```

### One-off overrides without a config file

Use `args` to pass any cccc option verbatim:

```yaml
- uses: moznion/cccc-action@v1
  with:
    path: src/
    args: --max-cognitive 15 --lang es --exclude 'dist/**'
```

### Reuse results across runs (`cache = true` in `cccc.toml`)

Caching follows the same rule as everything else: it is configured in
`cccc.toml`, not through action inputs.

```toml
# cccc.toml
cache = true
```

That's it — no workflow changes. The action asks cccc where its
[results cache](https://github.com/moznion/cccc#results-cache) resolves to
(`cccc --print-cache-file`) and, when enabled, persists that file between
workflow runs through `actions/cache`: no key design, paths, or save/restore
wiring on your side. Unchanged files are validated against git's index
instead of being re-parsed; only files that changed since the previous run
are re-analyzed (measured ~1.6–9.6× faster than a cold run on large trees).
The same `cache = true` also speeds up everyone's local runs — one setting,
one behavior. Add the cache file (`.cccc.cache` by default) to `.gitignore`.

Details the action takes care of:

- **The cache is saved even when the complexity gate fails.** The run step
  records cccc's exit code, the save step runs, and a final gate step
  re-raises the code — so a red gate still warms the next run.
- **Stale caches are safe by design.** cccc validates every entry against the
  file's actual content, so the laziest possible key strategy (`restore-keys`
  prefix match on the newest previous cache) is also a correct one; there is
  nothing to clean up.
- **Jobs don't thrash each other's cache.** The key includes a discriminator
  derived from what is analyzed and how (`path`/`config`/`args`), so jobs
  caching different analyses of the same repository keep separate entries.

One-off control still works through the usual escape hatch: `args: --cache`
enables caching without a config file, `args: --no-cache` disables it for one
workflow — the action honors either, since it asks cccc rather than parsing
the config itself.

Worth enabling on medium-to-large trees; on small ones (a cold run of a few
hundred files takes tens of milliseconds) the cache download/upload costs
more than it saves.

### Install only, then use the binary yourself

```yaml
- uses: moznion/cccc-action@v1
  with:
    version: v1.0.0        # or "latest" (default)
- run: cccc --top-cognitive 10 src/
```

## Inputs

| Input | Default | Description |
|-------|---------|-------------|
| `version` | `latest` | Release tag to install (e.g. `v1.0.0`), or `latest` |
| `repository` | `moznion/cccc` | Repo to fetch the cccc release from |
| `github-token` | `${{ github.token }}` | Token for API calls / asset downloads |
| `path` | _(empty)_ | Files/dirs to analyze. **Empty = install only** |
| `config` | | Explicit path to a `cccc.toml` config file |
| `no-config` | `false` | Skip config-file discovery and loading |
| `top-cognitive` | | Show the N most cognitively-complex functions |
| `top-cyclomatic` | | Show the N most cyclomatically-complex functions |
| `args` | | Extra raw arguments appended to the invocation |
| `output-file` | | Also write output to this file (gate exit code preserved) |

There is deliberately no `cache` input: enable it with `cache = true` in
`cccc.toml` (see above), and the action wires up the persistence.

> Analysis options such as `max-cognitive`, `lang`, `exclude`, `ext`, `jobs`,
> etc. are **not** action inputs — set them in `cccc.toml`, or pass them via
> `args` for one-off runs.

## Outputs

| Output | Description |
|--------|-------------|
| `version` | The release tag that was installed |
| `bin` | Absolute path to the installed `cccc` binary |

## Supported runners

`ubuntu-latest`, `macos-latest`, and `windows-latest` (the targets published by
the [cccc release workflow](https://github.com/moznion/cccc/blob/main/.github/workflows/release.yml)):

| OS | Arch | Target |
|----|------|--------|
| Linux | x64 | `x86_64-unknown-linux-musl` |
| Linux | arm64 | `aarch64-unknown-linux-musl` |
| macOS | x64 | `x86_64-apple-darwin` |
| macOS | arm64 | `aarch64-apple-darwin` |
| Windows | x64 | `x86_64-pc-windows-msvc` |

## License

[MIT](./LICENSE)
