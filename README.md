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
