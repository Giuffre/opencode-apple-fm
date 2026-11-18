# Contributing

## Commit format

This repository follows [Conventional Commits](https://www.conventionalcommits.org/). Every commit message must match:

```text
<type>(<optional scope>): <short description>
```

Examples:

```text
feat(provider): add support for FM_PORT
fix(plugin): keep properties named "pattern" in glob/grep
docs: document npm trusted publishing
ci: pin semantic-release plugins
chore(release): 1.4.0 [skip ci]
```

Allowed types: `feat`, `fix`, `perf`, `docs`, `style`, `refactor`, `test`, `build`, `ci`, `chore`, `revert`.

A `BREAKING CHANGE:` footer triggers a major release:

```text
feat(api)!: rename provider to applefm

BREAKING CHANGE: the old `fm` provider ID is no longer installed.
```

## Release rules

Releases are automated by [semantic-release](https://semantic-release.gitbook.io/) on every push/merge to `main`.

| Commit | Version bump |
| --- | --- |
| `fix:` or `perf:` | patch (1.0.0 → 1.0.1) |
| `feat:` | minor (1.0.0 → 1.1.0) |
| `BREAKING CHANGE:` | major (1.0.0 → 2.0.0) |
| `docs:`, `chore:`, `ci:`, `test:`, etc. | no release |

The release job:

1. analyzes commits since the last release;
2. updates `plugins/applefm-compat/package.json`;
3. publishes `opencode-applefm-compat` to npm;
4. creates a GitHub release with generated notes and the `.tgz` asset;
5. commits the version back to `main` with `chore(release): X.Y.Z [skip ci]`.

Only commits that change behavior produce a new version. Infrastructure-only merges still run the workflow, but no release is created.

## Local validation

```bash
npm ci
npx commitlint --from=HEAD~1 --to=HEAD
```

The same check runs on pull requests and on pushes to `main`.

## Publishing credentials (maintainers)

The release workflow supports two authentication modes.

### 1. npm token (needed for the first release)

npm does not let you configure Trusted Publishing until the package exists in the registry, so bootstrap the first release with a granular access token:

1. Create a granular token at <https://www.npmjs.com/settings/giuffre/tokens/granular-access-tokens/new>.
2. Grant **Publish** access to `opencode-applefm-compat` and enable bypass 2FA.
3. Store it as a GitHub secret:

   ```bash
   gh secret set NPM_TOKEN --repo Giuffre/opencode-apple-fm
   ```

### 2. Trusted Publishing (recommended afterwards)

Once the package exists:

1. Open <https://www.npmjs.com/package/opencode-applefm-compat> → **Settings** → **Trusted publisher**.
2. Add a GitHub Actions publisher:
   - Owner: `Giuffre`
   - Repository: `opencode-apple-fm`
   - Workflow filename: `release.yml`
3. The workflow already requests `id-token: write` and upgrades npm to 11.5.1+, so no token is required. You can then remove the `NPM_TOKEN` secret.

Enabling branch protection on `main` with a required review is recommended.
