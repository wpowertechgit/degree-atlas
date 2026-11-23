# Security

## Reporting a vulnerability

Please report security problems privately through GitHub's **Report a vulnerability** button on the repository's Security tab, not in a public issue. Include what you found, how to reproduce it and the impact. Expect a first reply within a week.

## Things to know before you run it

**The in-app agent has full permissions.** The Agent panel starts a local `claude` process with `--permission-mode bypassPermissions` in the repository folder, so it can read and write files and run commands without asking. This is intentional (the app drives long writing jobs unattended), but it means:

- Run it only with an account and machine you are comfortable giving that access to.
- The agent reads web pages and your imported course files. Treat both as untrusted input: a page or a document can contain text that tries to steer the agent (prompt injection). Do not import files from sources you do not trust.
- Anything the agent can reach, a malicious page could try to make it do. Keep secrets out of the repository folder and out of folders you import.

**What the app itself does.**

- Its only network request is the one-time download of the Noto Sans font from Google Fonts (via the `google_fonts` package, cached afterwards). All other web access is done by the agent with its own tools.
- Importing a data export (`.json`) only writes inside `data/` and merges `progress.json`; paths outside `data/` or containing `..` are rejected.
- Importing course materials copies files into `profiles/<name>/materials/`, skipping hidden files and symlinks. The originals are never modified.
- Your progress, language, materials and agent session id are stored locally (`progress.json`, `settings.json`, `materials/`, `work/`) and are gitignored. Exports contain your data and progress, not your materials.

## Supported versions

Only the latest commit on `main` is supported.
