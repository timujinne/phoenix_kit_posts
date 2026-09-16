# PR #20 Follow-up — Module-owned migration chain V1

After-action for `CLAUDE_REVIEW.md` (the author-side agent review) and
`CLAUDE_OPUS5_REVIEW.md` (the independent review). Verified against current
code on `main`.

## Merged as-is

The migration chain itself needed no change. `CLAUDE_REVIEW.md`'s PASS was
re-derived by a different method — core's full V135→V190 chain and this
module's V1 both built into real schemas and diffed out of Postgres'
catalogue — with zero drift on every column, index and constraint of all 13
tables. The `~> 2.16` floor was separately confirmed to cover every core API
the chain calls (`Helpers.*` land in `v1.7.189`, `migration_module/0` in
`1.7.63`), and no core migration after V185 touches these tables in core
`2.23.3`.

That live check is now permanent:
`test/integration/migrations_shape_identity_test.exs`. Previously nothing ran
the chain against a database — `migrations_test.exs` compares its SQL to
core's `ExpectedSchema` manifest, which is core describing itself — and
nothing exercised V1's `CREATE TABLE` statements at all, since they are
no-ops on every install until core's Phase 2 squash.

## Fixed (post-review)

Three `varchar` overflow bugs, all pre-existing, all surfaced by the PR
making `column_widths/0` the declared shape authority while the changesets
went on using independent numbers. Each produced a `valid?` changeset and a
raw `22001 string_data_right_truncation` at insert — a 500 in the admin
editor, not a form error.

- ~~**`sub_title` validated at 500 against a `varchar(255)` column.**~~ Fixed:
  `Post.changeset/2`'s `validate_length/3` calls now read `@column_widths`,
  and `Web.Edit` clamps the `posts_max_title_length` /
  `posts_max_subtitle_length` counters and `maxlength` attributes to the real
  widths. The editor's own counter had been inviting up to 500 characters.
- ~~**`repost_url` had no length bound at all.**~~ Fixed — bounded by
  `@column_widths.repost_url`.
- ~~**A colliding 255-character title generated a 257-character slug.**~~
  Fixed — `slugify/1` and `unique_slug/2` pass `max_length:` to core's `Slug`,
  which trims the base to make room for the `-2` suffix. Core documents this
  exact hazard and has had the option since `v2.4.0`.
- ~~**`PostGroup` / `PostTag` accepted an over-wide explicit slug.**~~ Fixed —
  `validate_length(:slug, max: @column_widths.slug)` on each.

`test/integration/column_width_test.exs` locks all of it in; all six tests
fail without the fixes.

## Skipped (with rationale)

- **`up/1` prepares the database before validating the target.**
  `up(version: 99)` creates the extension and the UUIDv7 function before
  raising. Idempotent, harmless, operator error — reordering buys nothing and
  would diverge from the sibling chains.
- **`up/1` overwrites a foreign `COMMENT` on `phoenix_kit_posts`.** The reader
  already treats a foreign comment as version 0, which is the half that
  matters. Matches `phoenix_kit_dashboards` / `phoenix_kit_warehouse`;
  changing it here alone would split the family.
- **No chain-level advisory lock.** Core's `Postgres.up/1` takes one; no
  module chain does. `mix ecto.migrate` already serialises through Ecto's
  migration lock. Worth revisiting family-wide, not in this package.

## Open

- **The 5 known-gap unique constraints** the schemas assert via
  `unique_constraint/3` with no backing index
  (`post_likes`/`post_dislikes`/`post_mentions` on `(post_uuid, user_uuid)`,
  `comment_likes`/`comment_dislikes` on `(comment_uuid, user_uuid)`).
  Duplicates are possible today and those error messages never fire. Correctly
  out of scope for a pure adoption — closing them is a shape change and needs
  the core-side `@excluded_exact` / `ExpectedSchema` work first, per the PR's
  own Phase 1.
- **`posts_max_subtitle_length`'s default is still 500** while the column is
  255. `Web.Edit` now clamps it, so nothing breaks, but the setting advertises
  a ceiling the database does not have. Widening the column is a V2 shape
  change; lowering the default is a settings migration. Left for whichever
  lands first.
