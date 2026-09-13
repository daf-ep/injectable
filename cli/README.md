`injectable`, the command-line tool that installs and keeps up to date the injectable engineering rules corpus.

## Commands

`login` links this machine to an injectable account through GitHub or GitLab: pick a
host, or pass `--provider github|gitlab` to skip the menu, and injectable runs that
host's OAuth Device Authorization Grant, opening the browser on its own. injectable's
backend is asked who the resulting access token belongs to exactly once, and
the session it hands back is stored at `$HOME/.local/share/injectable/credentials`
unless `INJECTABLE_CREDENTIALS_PATH` says otherwise, restricted to this account's own
read and write wherever `chmod` applies. `logout` forgets it again, and is a
no-op when there was nothing to forget.

Every other command refuses to run at all without a session stored, `injectable
login` first is how it says so, except `bridge`: that one is invoked by Claude
Code itself rather than by whoever is or isn't logged in, and its own
contract is to never fail regardless of the reason.

`init` syncs `global/`, at the `rules/` checkout next to this package, into a
single store every project on the machine shares, at
`$HOME/.local/share/injectable/rules/` unless `INJECTABLE_RULES_DIR` says otherwise. A
later run replaces that store's content wholesale, so it always matches the
installed corpus exactly. `project/` is the one part of the corpus that is
not shared: `init` ensures each of its files exists under this project's
`.claude/injectable/`, without ever overwriting one the project already wrote.
`init` also declares `injectable`'s MCP server in `.mcp.json`, adding or replacing
only its own entry and leaving every other server a project declared for
itself alone. It declares `injectable`'s hooks in `.claude/settings.local.json` the
same way, never in `.claude/settings.json`, which a project routinely commits, and
adds `.claude/context` to `.gitignore` for whatever local file a future capture
mechanism writes there. When a session is stored, it also declares
`ANTHROPIC_BASE_URL` under `env` in that same `.claude/settings.local.json`, pointed
at injectable's BYOK gateway for this project and the logged-in account; with no
session stored, it skips this and says so instead of writing an url with no
account to attribute captures to.

`injectable` only works inside a git repository whose `origin` remote points at
GitHub or GitLab: the project's id is `host/owner/repo`, taken from that
remote rather than stored anywhere, so two clones of the same repository
share the same id.

`mcp` runs the MCP server Claude Code talks to over stdio, exposing
`get_rule` and `list_rules` to read the shared corpus and `record_decision`
to capture a decision. It is not meant to be run by hand: `init` wires it
into `.mcp.json`, and Claude Code starts and stops the process itself, once
per session. Every decision is recorded in a single database shared across
every project, at `$HOME/.local/share/injectable/decisions.sqlite3` unless
`INJECTABLE_DECISIONS_DATABASE` says otherwise, tagged with the project's git-derived
id.

`bridge` is wired into `SessionStart`, `UserPromptSubmit` and `Stop` in
`.claude/settings.local.json` by `init`, as `--start`, `--input` and `--end`
respectively, and is not meant to be run by hand. `--input` and `--end` seal
the exchange's text and queue it locally; `--start` does nothing yet. See
"Capturing session context" below for where that stands.

## Logging in

`injectable login` needs an OAuth client id per host, `INJECTABLE_GITHUB_CLIENT_ID` and
`INJECTABLE_GITLAB_CLIENT_ID`: public identifiers for injectable's own OAuth apps, safe to
ship inside the CLI, never a secret the way a client secret would be. A
self-managed GitLab instance is named through `INJECTABLE_GITLAB_BASE_URL`,
`https://gitlab.com` otherwise. `INJECTABLE_BACKEND_URL` says where injectable's backend
API lives, `http://localhost:8080` otherwise. `INJECTABLE_GATEWAY_URL` says where
injectable's BYOK gateway lives, `INJECTABLE_BACKEND_URL`'s value otherwise: the
gateway and the backend API are the same deployed service unless a project's
setup says otherwise.

## Checking for updates

Every command checks the public corpus, `daf-ep/injectable` on GitHub, for
updates once it finishes its own work, at most once a day unless
`INJECTABLE_UPDATE_CHECK_INTERVAL_SECONDS` says otherwise. A check that finds the
corpus changed replaces the shared store wholesale, the same way `init`
does, and adds any new `project/` file to the current project's
`.claude/injectable/`, never overwriting one already there. A check that cannot
reach GitHub, or that runs before the interval has passed, is silent: injectable
tries again next time, and no command ever fails because of it.

## Capturing session context

Session capture used to work by encrypting `.claude/context`, a project-local
sqlite database, under a symmetric key shared by hand between teammates
(`INJECTABLE_CONTEXT_KEY`), then pushing it to `injectable-context`, an orphan branch on
`origin` with no history shared with any other branch. That key let anyone
holding it, including the person captured, decrypt their own capture, which
does not fit an account model where a session's owner should not need to be
trusted with the ability to read it back.

The replacement seals each event under a public key only `injectable`'s
backend can decrypt, `INJECTABLE_CAPTURE_PUBLIC_KEY` (base64) names it and
capture stays a no-op until it is set, and queues the sealed bytes in a local
database, `$HOME/.local/share/injectable/captures.sqlite3` unless
`INJECTABLE_CAPTURES_DATABASE` says otherwise. Nothing reads that queue yet:
syncing it to `injectable`'s backend over an authenticated connection, rather
than through this project's own git history, is still to build.

## Running it from source

```
dart run bin/injectable.dart init
```

## Testing it

```
dart test
```
