# PR #20 — Add module-owned migration chain V1 for the 13 posts tables

**Reviewed:** 2026-09-16 · **Author:** Tymofii Shapovalov (`timujinne`) ·
**Reviewer:** Claude Opus 5 · **Verdict:** APPROVE the chain as written; three
pre-existing `varchar` overflow bugs found alongside it and fixed here.

A second, independent review — `CLAUDE_REVIEW.md` in this directory is another
agent's and is not edited by this one. Its verdict on the migration chain is
confirmed below by a different method (a live database, not a source diff), and
this review adds findings it did not cover.

## Scope actually reviewed

`git fetch origin pull/20/head`, merged into `main` locally and reviewed
**against core `2.23.3`** (the version `main`'s `mix.lock` resolves), not
against the `2.16.0` the PR branch's own lock still carries. The merge takes
`main`'s lock, so 2.23.3 is what ships. This matters: the PR's shape claims
were derived against a core checkout whose version the PR does not state.

## Verification of the chain (independent method)

The PR's own `migrations_test.exs` proves V1's SQL matches core's
`ExpectedSchema` manifest. That is core describing itself — a manifest that
drifted from core's migrations would take this chain's DDL with it and both
would still agree. So the central claim was re-checked against Postgres
instead:

- Core's full chain (**V135→V190**) run into schema `A`, this module's V1 run
  from scratch into an empty schema `B` holding nothing but stub
  `phoenix_kit_users` / `phoenix_kit_files` tables — i.e. the Phase 2 world.
- Every column (type, width, nullability, default), every `pg_indexes.indexdef`
  and every `pg_get_constraintdef` for all 13 tables compared between the two.
- **Result: zero drift.** The adoption is exact, and the Phase 2 `CREATE TABLE`
  path — which is a no-op everywhere today and therefore untested by
  construction — genuinely builds the right tables.

This check is now a permanent test:
`test/integration/migrations_shape_identity_test.exs`. It was mutation-checked
(removing one index and widening one column both fail it).

Also confirmed independently:

- **No core migration after V185 touches any of the 13 tables** (checked V186–V190
  in core `2.23.3`), so V1's adopted shape is current, not stale.
- **Every core API the chain calls is below the `~> 2.16` floor.**
  `Helpers.qualify_table/2`, `uuid_v7_call/1`, `ensure_extension!/1`,
  `ensure_uuid_v7_function/1` and `validate_prefix!/1` all landed in core
  `v1.7.189`; the `migration_module/0` callback in `1.7.63`. No floor bump is
  needed — the failure mode this repo has hit before (a module calling a core
  API newer than its own floor) is not present.
- **`up/1` works on a non-superuser role.** `Helpers.ensure_extension!("pgcrypto")`
  runs under the unprivileged `beamlab_test` role in the check above without
  raising, so the Phase 2 preparation is not a superuser-only path.
- **The protocol matches what core actually calls.**
  `PhoenixKit.Migrations.Modules.describe/2` calls
  `migrated_version_runtime(prefix: prefix)` and `current_version/0`; the
  generated migration calls `Mod.up(prefix:, version:)` /
  `Mod.down(prefix:, version:)`. All four exist with the right shapes, and the
  generated filename really is `posts_update_v00_to_v01.exs`
  (slug derived from `module_name/0`).
- **README's uninstall SQL is FK-safe.** Every child precedes its parent;
  `phoenix_kit_posts` last, which also removes the marker comment.
- Full suite green on a real database (`PGDATABASE=beamlab_test`), 104 tests
  after this review's additions.

## Findings

### BUG - MEDIUM — `Post.changeset/2` allowed a `sub_title` the column cannot hold

`validate_length(:sub_title, max: 500)` against a `character varying(255)`
column. The changeset reports `valid?`, and Postgres then raises
`22001 string_data_right_truncation` on insert — an unhandled `Postgrex.Error`,
i.e. a 500 in the admin editor rather than a form error. The editor's own
character counter and `maxlength` came from `posts_max_subtitle_length`, whose
default is **500**, so the page actively invited the input that breaks it.

Pre-existing, but this PR is what makes it a live contradiction: `column_widths/0`
now declares `sub_title: 255` as "the single shape authority", and the PR's own
comment on that map acknowledged the 500-vs-255 mismatch without resolving it.

**Fixed.** `changeset/2`'s `validate_length/3` calls are now driven from
`@column_widths`, and `Web.Edit` clamps `max_title_length` /
`max_subtitle_length` to the real widths so an operator setting above the
column is absorbed rather than advertised.

### BUG - MEDIUM — `repost_url` had no length bound at all

`character varying(255)`, cast from user input, never validated. A repost URL
with a long query string is entirely ordinary and produces the same `22001`.
**Fixed** — bounded by `@column_widths.repost_url`.

### BUG - MEDIUM — a colliding maximum-length title generated a slug wider than its column

`slugify/1` passed no `:max_length`, and `unique_slug/2` called
`Slug.ensure_unique/2` without one. A 255-character title slugifies to 255
characters; the second post with that title gets `-2` appended, producing 257,
and the insert raises `22001`. Core's own `Slug` documents exactly this hazard
("against a `varchar(n)` column Postgres raises rather than truncating") and
provides `:max_length` on both functions for it — available since core `v2.4.0`,
well below this package's floor. **Fixed** — both calls now carry
`max_length: @column_widths.slug`, so the base is trimmed to make room for the
suffix.

### BUG - LOW — `PostGroup` / `PostTag` accepted an over-wide explicit slug

Both cast `:slug` from user input with a format check but no length check, both
columns being `varchar(255)`. Generated slugs are safe (they derive from a
`name` capped at 100), so this is only reachable by typing one — but the group
edit form does let you. **Fixed** — `validate_length(:slug, max: @column_widths.slug)`
on each.

### NITPICK — `up/1` prepares the database before validating the target

`up(version: 99)` runs `ensure_extension!/1` and `ensure_uuid_v7_function/1`,
then raises out of `up_statements/2`'s `validate_target!/1`. The side effects
are harmless and idempotent and the call is operator error, so **not changed** —
reordering would buy nothing and diverge from the sibling chains.

### NITPICK — `up/1` overwrites a foreign `COMMENT` on the anchor table

The marker is stamped unconditionally, so a comment an operator put on
`phoenix_kit_posts` is lost on first `up`. The reader already treats a foreign
comment as version 0, which is the important half. `down/1` cannot hit this
(it only runs when the marker parses above the target). **Not changed** —
matches `phoenix_kit_dashboards` / `phoenix_kit_warehouse`; changing it here
alone would make the family inconsistent for a case nobody has hit.

### Not a finding, recorded

- **The 5 known-gap unique constraints** (`post_likes`/`post_dislikes`/
  `post_mentions` on `(post_uuid, user_uuid)`, `comment_likes`/`comment_dislikes`
  on `(comment_uuid, user_uuid)`) are correctly left alone: the schemas assert
  them via `unique_constraint/3` with no backing index, so those messages never
  fire and duplicates are possible today. Closing them is a shape change and
  belongs to V2 with the core-side manifest work, exactly as the PR says.
- **No chain-level advisory lock.** Core's `Postgres.up/1` takes one; this
  chain does not. In practice `mix ecto.migrate` already serialises through
  Ecto's own migration lock, and the sibling chains do the same thing. Worth
  revisiting family-wide, not here.

## Changes made under this review

| File | Change |
|---|---|
| `lib/phoenix_kit_posts/schemas/post.ex` | `validate_length/3` driven from `@column_widths`; `repost_url` and explicit `slug` bounded; `slugify/1` and `unique_slug/2` carry `max_length` |
| `lib/phoenix_kit_posts/schemas/post_group.ex`, `post_tag.ex` | explicit `slug` bounded by the column width |
| `lib/phoenix_kit_posts/web/edit.ex` | title/subtitle counters and `maxlength` clamped to the real column widths |
| `test/integration/column_width_test.exs` | new — 6 tests, all six fail without the fixes |
| `test/integration/migrations_shape_identity_test.exs` | new — live two-schema shape diff, mutation-checked |

## Gate

`mix precommit` (compile `--warnings-as-errors` + format + credo `--strict` +
dialyzer) clean, and `PGDATABASE=beamlab_test mix test` green. A default
`mix test` here exercises none of the DB paths and still exits 0 — the
integration tier is skipped silently when `phoenix_kit_posts_test` is absent,
which is why every number above is from the `beamlab_test` run.
