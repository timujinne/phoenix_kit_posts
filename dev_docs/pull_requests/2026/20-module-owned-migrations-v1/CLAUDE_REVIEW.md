# PR #20 — Add module-owned migration chain V1 for the 13 posts tables

**Reviewed:** 2026-09-15 · **Author:** Timujeen · **Verdict:** PASS — ship,
no findings.

## What actually landed

`lib/phoenix_kit_posts/migrations.ex` (new), implementing
`PhoenixKitPosts.Migrations` — the same decentralized-migrations dual-reader
protocol already merged for `phoenix_kit_dashboards` (PR #11) and
`phoenix_kit_warehouse` (PR #30), scaled to this module's 13 tables / 24 FKs.
V1 is a pure adoption: it recognizes and idempotently re-asserts the exact
shape core's own chain already created (`V135` baseline, `V167` — makes
`phoenix_kit_posts_slug_index` UNIQUE, `V168` — adds the `(user_uuid, slug)`
unique index on `phoenix_kit_post_groups`, `V185` — adds
`phoenix_kit_posts.time_zone`), then stamps a `pkpo_schema:1` marker via
`COMMENT ON TABLE` on `phoenix_kit_posts` (the module's own hub table,
deliberately chosen over the FK-free `phoenix_kit_post_tags`, with the
moduledoc explaining why). `migration_module/0` wired on
`PhoenixKitPosts`; `column_widths/0` added to the six schemas with varchar
columns; three new test files; `AGENTS.md`/`README.md`/`CHANGELOG.md`
updated (no version bump).

An earlier draft's moduledoc/`AGENTS.md` omitted V167 from the ownership
narrative (DDL was already correct — only the prose credited V135/V168/V185
and skipped V167). Fixed in commit `3098593`; confirmed present and correct
in both files.

## Verification

Independently re-derived, not taken from the PR body's self-report:

- **DDL shape-identity**: `CREATE TABLE` bodies for all 13 tables diffed
  character-by-character against `/app/lib/phoenix_kit/migrations/postgres/v135.ex`
  (lines 461-591, 1355-1383) — exact match on every column/type/default/NOT
  NULL. All PK guards, FK guards, and indexes grep-verified by exact name
  against `v135.ex`/`v167.ex`/`v168.ex`/`v185.ex` — no drift.
- **FK tally** (24 total: 9→`phoenix_kit_users` CASCADE, 1 self-referential
  on `post_comments`, 1→`post_groups`, 1→`post_tags`, 2→`files` [1 CASCADE +
  the one non-CASCADE `SET NULL`], 8→`posts`, 2→`post_comments` non-self) —
  confirmed against the DDL, matches the PR body exactly.
- **No-PK tables**: confirmed neither core nor V1 give `post_tag_assignments`
  / `post_group_assignments` a primary key (UNIQUE indexes only).
- **6 real unique indexes** adopted as-is; **5 known-gap unique
  constraints** (`post_likes`/`post_dislikes`/`post_mentions` on
  `(post_uuid, user_uuid)`, `comment_likes`/`comment_dislikes` on
  `(comment_uuid, user_uuid)`) confirmed absent from V1's DDL and documented
  as a deliberate V2+ gap in both the moduledoc and PR body.
- **`down/1` safety**: emits only `COMMENT ON TABLE` for any target,
  verified by source reading and by `migrations_data_safety_test.exs`,
  which seeds real rows (`Post`/`PostLike`/`PostTag`+`PostTagAssignment`)
  via a real `Ecto.Migration.Runner`, proves byte-for-byte survival through
  `down(version: 0)` and a map-shaped `down(%{version: 1})`, and includes a
  `DestructiveRollback` negative control proving the survival assertions
  actually fail against a real mutant — not a tautological test.
- **Docs**: `AGENTS.md` "Database & migrations" fully rewritten with a
  Phase 0/1/2 ownership narrative; `README.md`'s new "Removing this module"
  section gives a manually-verified FK-safe DROP order; `CHANGELOG.md` has
  a matching `## Unreleased` entry; `mix.exs` `@version` untouched.
- **Commit hygiene**: both commits (`0930b42`, `3098593`) authored by
  `Timujeen <timujeen@gmail.com>`, no AI attribution, working tree clean.
  PR is draft, base `main`, targets `BeamLabEU/phoenix_kit_posts`.

```
$ mix precommit
415 mods/funs, found no issues.
Starting Dialyzer
Total errors: 0, Skipped: 0, Unnecessary Skips: 0
done (passed successfully)

$ MIX_ENV=test PGDATABASE=phoenix_kit_posts_test PGHOST=localhost mix test
Running ExUnit with seed: 785707, max_cases: 8
....................................................................................................
Finished in 4.4 seconds (3.0s async, 1.3s sync)
98 tests, 0 failures
```

(`PGHOST=postgres`, as literally specified in the task brief, does not
authenticate in this container — confirmed independently twice; the test DB
this container actually reaches is on `localhost` with `postgres`/`postgres`.)

## Findings

None. No `BUG`, no `IMPROVEMENT`, no `NITPICK`. Both spec-compliance and
code-quality stages PASS.
