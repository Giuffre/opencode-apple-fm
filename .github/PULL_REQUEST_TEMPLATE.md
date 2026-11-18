## Summary

<!-- Describe the change and why it is needed. Link any related issue. -->

## Type of change

- [ ] `feat` — new feature (minor release)
- [ ] `fix` / `perf` — bug fix or performance improvement (patch release)
- [ ] `docs` / `ci` / `chore` — no release

The PR title must follow [Conventional Commits](https://www.conventionalcommits.org/), because it becomes the squash commit message.

## Checklist

- [ ] PR title is a valid conventional commit
- [ ] `npm ci && npx commitlint --from=HEAD~1 --to=HEAD` passes locally
- [ ] Smoke tests pass if runtime behavior changed
- [ ] Documentation updated if needed
