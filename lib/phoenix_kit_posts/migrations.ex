defmodule PhoenixKitPosts.Migrations do
  @moduledoc """
  Module-owned versioned migrations for `phoenix_kit_posts` — the
  decentralized-migrations protocol that core's `mix phoenix_kit.update`
  discovers via `migration_module/0`. This follows the canonical shape
  documented in `phoenix_kit_hello_world`'s README ("Versioned migrations",
  "Adopting a table core already creates") and its
  `mix phoenix_kit_hello_world.audit_migrations` task: **two readers**
  (`migrated_version/1` for migration context, `migrated_version_runtime/1`
  for Mix-task context), `up/1` re-reading the version before it changes
  anything, and a namespaced `COMMENT ON TABLE` marker on one anchor table
  for a chain that spans 13. `phoenix_kit_warehouse` (`v1_statements/2`,
  8 adopted tables in one version) and `phoenix_kit_billing` (ten adopted
  tables in one version) are the closest sibling examples of this exact
  adoption situation, scaled up further here.

  ## Ownership situation — read before touching

  All 13 `phoenix_kit_post*`/`phoenix_kit_comment_*` tables are core's
  baseline: `V135` created all 13 in their pre-`time_zone` shape (with a
  plain, non-unique `phoenix_kit_posts_slug_index`), `V167` made that index
  UNIQUE (repairing any existing duplicate slugs first), `V168` added the
  `(user_uuid, slug)` unique index on `phoenix_kit_post_groups`, and `V185`
  added `phoenix_kit_posts.time_zone`. On every existing install
  all 13 already have their full current shape before this chain ever
  executes — this is an ADOPTION, not a create. Varchar widths are never
  restated as a second number: each owning schema's own `column_widths/0`
  (`Post`, `PostComment`, `PostGroup`, `PostMention`, `PostTag`, `PostView`
  — the other seven tables have no varchar column) is the single shape
  authority this chain's DDL interpolates.

  Rather than stamp all 13 tables, the chain anchors its version marker on a
  single table — `phoenix_kit_posts` itself, this module's own central,
  load-bearing table. This deliberately departs from the sibling chains'
  convention of anchoring on the table with no outgoing FK of its own
  (`phoenix_kit_post_tags` has that property here — zero outgoing FKs, the
  only one of the 13 — but is not otherwise central to the module and is not
  the table every other adoption in this chain ultimately points back to).
  `phoenix_kit_posts` is never at risk of being dropped independently of the
  rest of the chain, which is what the anchor choice is actually protecting.

  Every table with a `user_uuid` column carries a real FK to
  `phoenix_kit_users(uuid) ON DELETE CASCADE` — 9 of the 13 tables
  (`phoenix_kit_post_tags`, `phoenix_kit_post_tag_assignments`, and
  `phoenix_kit_post_group_assignments` have no `user_uuid` column and thus
  no such FK). In total this chain adopts 24 FKs: 9 to `phoenix_kit_users`,
  1 self-referential on `phoenix_kit_post_comments` (`parent_uuid`), 1 to
  `phoenix_kit_post_groups`, 1 to `phoenix_kit_post_tags`, 2 to
  `phoenix_kit_files` (`phoenix_kit_post_media.file_uuid`, `ON DELETE
  CASCADE`, and `phoenix_kit_post_groups.cover_image_uuid`, `ON DELETE SET
  NULL` — the lone non-CASCADE FK in the whole set), 8 to `phoenix_kit_posts`
  itself, and 2 to `phoenix_kit_post_comments`
  (`phoenix_kit_comment_likes`/`_dislikes`).

  ### A discrepancy between core's migration source and its `ExpectedSchema` manifest

  The manifest's human-readable `create:` string for a bare (no-DEFAULT)
  not-null column across all 13 tables omits `NOT NULL` — e.g.
  `phoenix_kit_posts.title`. Core's actual migration source (`v135.ex`) and
  the manifest's own structured `revisions.not_null` field both agree the
  column IS `NOT NULL`. This chain's DDL follows the source and
  `revisions` — the `create:` string is the buggy representation, and the
  ownership test below diffs against `revisions`, never against `create:`.

  ### Phase 0 — this V1 adopts, and changes NOTHING

  `CREATE TABLE IF NOT EXISTS` shape-identical to core's `V135`/`V167`/`V168`/`V185`
  baseline, under core's exact object names (every pkey, index, and FK),
  then a **namespaced** marker stamp on the anchor table (`pkpo_schema:1` —
  an adopted table may already carry a foreign comment, so the reader must
  treat prose as version 0, never crash on it, never assume it means V1).
  Because the shape is unchanged, core's `ExpectedSchema` manifest stays
  accurate: **no core release is required and there is no release-ordering
  hazard.** This package releases alone.

  Five unique constraints this module's own schemas assert via
  `Ecto.Changeset.unique_constraint/3` have no backing index in core's
  baseline — `phoenix_kit_post_likes`/`_dislikes`/`_mentions` on
  `(post_uuid, user_uuid)` and `phoenix_kit_comment_likes`/`_dislikes` on
  `(comment_uuid, user_uuid)`. V1 does NOT create these: it is a pure
  adoption of core's shape exactly as it stands, and adding a constraint
  core never had would be a shape CHANGE, not an adoption. They are a
  documented gap for a future V2.

  ### Phase 1 — the first real shape change (V2+) is when core must move too

  Before shipping a version that changes any of the 13 tables' shape —
  including closing the five gaps above:

    1. add the objects that version alters to core's manifest generator's
       `@excluded_exact` (`dev_docs/squash/generate_baseline.exs`) and
       regenerate `ExpectedSchema`;
    2. raise this package's `:phoenix_kit` floor to the release that ships
       that regenerated manifest.

  Skipping step 1 means `mix phoenix_kit.repair` restores the old shape
  after every run, silently undoing the new version.

  A related, separate proposal (not a code change in this PR): core's
  `@table_owner_prefixes`/`@table_owner_substrings` baseline-squash heuristic
  (`generate_baseline.exs`) currently tags `phoenix_kit_post_comments`,
  `phoenix_kit_post_likes`, `phoenix_kit_post_dislikes`,
  `phoenix_kit_comment_likes` and `phoenix_kit_comment_dislikes` as
  `owner: :comments` — a coincidental substring match on
  "comment"/"like"/"dislike" (that file's own moduledoc calls this "a
  best-effort hint, not a rigorous taxonomy") since the real
  `phoenix_kit_comments` module owns entirely different tables
  (`phoenix_kit_comments`, `phoenix_kit_comments_likes`,
  `phoenix_kit_comments_dislikes` — plural `comments_`). A `{"post_", :posts}`
  prefix rule ahead of the substring fallback, plus explicit entries for the
  two `phoenix_kit_comment_*` tables, would tag all 5 as `:posts` instead.

  ### Phase 2 — creation leaves core's baseline at the next squash cycle

  When core cuts its next baseline, module-owned tables are simply not
  included: fresh installs from then on get all 13 `phoenix_kit_post*`/
  `phoenix_kit_comment_*` tables from THIS chain's V1 — which is why V1's
  `up/1` ensures the `uuid_generate_v7()` function (and its `pgcrypto`
  extension) exist rather than assuming core's chain already provided them,
  and why every `CREATE TABLE` must already be the full, correct definition
  on its own, not merely a shape-matching no-op for an already-existing
  table. Existing installs are untouched — a baseline squash only affects
  fresh installs and below-floor bridging.

  ## What must NEVER happen

  No conditional core migration of the form "module absent → drop the
  tables" — that is nondeterministic (depends on which packages are
  compiled in) and destroys data on a host that merely removed the
  package. Removing this module's data is a human, manual step — see
  README.md "Removing this module" for the operator SQL. There is
  deliberately no automated uninstall path, and `down/1` NEVER drops any of
  the 13 tables for ANY target version, including `0` — it only unstamps
  (or re-stamps) the marker on the anchor table. The rows are every user's
  posts, likes, tags, groups, media, mentions, views and legacy comments,
  and on most installs every table is core-created; rolling back this
  module's chain must not destroy any of them.

  The migrated version is tracked as a `pkpo_schema:<N>` COMMENT on
  `phoenix_kit_posts`. A marker-less table, or one carrying a foreign
  (non-`pkpo_schema:`) comment, reads as version 0 — the core-baseline shape
  before this chain existed.
  """

  use Ecto.Migration

  alias PhoenixKit.Migrations.Postgres.Helpers
  alias PhoenixKitPosts.Post
  alias PhoenixKitPosts.PostComment
  alias PhoenixKitPosts.PostGroup
  alias PhoenixKitPosts.PostMention
  alias PhoenixKitPosts.PostTag
  alias PhoenixKitPosts.PostView

  @initial_version 1
  @current_version 1
  @default_prefix "public"
  @marker_prefix "pkpo_schema:"

  @posts "phoenix_kit_posts"
  @post_comments "phoenix_kit_post_comments"
  @post_likes "phoenix_kit_post_likes"
  @post_dislikes "phoenix_kit_post_dislikes"
  @post_tags "phoenix_kit_post_tags"
  @post_tag_assignments "phoenix_kit_post_tag_assignments"
  @post_groups "phoenix_kit_post_groups"
  @post_group_assignments "phoenix_kit_post_group_assignments"
  @post_media "phoenix_kit_post_media"
  @post_mentions "phoenix_kit_post_mentions"
  @post_views "phoenix_kit_post_views"
  @comment_likes "phoenix_kit_comment_likes"
  @comment_dislikes "phoenix_kit_comment_dislikes"

  # The single table this chain's marker lives on — this module's own hub
  # table, not `post_tags` (see the moduledoc for why the usual "FK-free
  # table" convention is set aside here). Every other table adopted below
  # shares this chain's version; none of them carry a marker of their own.
  @version_table @posts

  @doc "The version this code expects the schema to be at."
  @spec current_version() :: pos_integer()
  def current_version, do: @current_version

  @doc """
  The version a bare, freshly-created set of tables is at (Phase 2 — a
  future install whose core baseline no longer creates these tables).
  """
  @spec initial_version() :: pos_integer()
  def initial_version, do: @initial_version

  @doc """
  The table carrying the `pkpo_schema:<N>` marker for the whole 13-table chain.

  Not part of the protocol `mix phoenix_kit.update` calls. Exported so an
  auditor (`mix phoenix_kit_hello_world.audit_migrations`) can verify the
  marker is really a number without hard-coding this table's name.
  """
  @spec version_table() :: String.t()
  def version_table, do: @version_table

  @doc """
  Applies every chain version up to `opts[:version]` (default
  `current_version/0`). Migration-context only — re-reads the installed
  version via `migrated_version/1` before making any change, so a database
  already at (or ahead of) the target does nothing.
  """
  @spec up(keyword() | map()) :: :ok
  def up(opts \\ []) do
    opts = with_defaults(opts, @current_version)

    if migrated_version(opts) < opts.version do
      # Don't assume core's chain ran first (Phase 2): `uuid_generate_v7()`
      # is built on pgcrypto's `gen_random_bytes`, and
      # `ensure_uuid_v7_function/1` does not install extensions — without
      # the first call the function is created and then fails on the first
      # insert.
      Helpers.ensure_extension!("pgcrypto")
      Helpers.ensure_uuid_v7_function(opts.prefix)

      opts.prefix
      |> up_statements(opts.version)
      |> Enum.each(&execute/1)
    end

    :ok
  end

  @doc """
  Rolls back to `opts[:version]` (default `0`). Migration-context only.
  Never drops a table or a row in any of the 13, for any target — see the
  moduledoc.
  """
  @spec down(keyword() | map()) :: :ok
  def down(opts \\ []) do
    opts = with_defaults(opts, 0)

    if migrated_version(opts) > opts.version do
      opts.prefix
      |> down_statements(opts.version)
      |> Enum.each(&execute/1)
    end

    :ok
  end

  @doc """
  The version currently installed, read INSIDE a migration — through
  `Ecto.Migration`'s own `repo()`. No rescue: inside a migration a version
  that cannot be read must abort the transaction, never be guessed at.
  `up/1` and `down/1` call this — never `migrated_version_runtime/1` —
  before making any change.
  """
  @spec migrated_version(keyword() | map()) :: non_neg_integer()
  def migrated_version(opts \\ []) do
    opts = with_defaults(opts, @initial_version)
    read_version(repo(), opts.prefix)
  end

  @doc """
  Runtime-safe reader — the one `mix phoenix_kit.update` calls, from a Mix
  task with no migrator running, through PhoenixKit's configured repo
  instead of `Ecto.Migration`'s.

  An invalid prefix is re-raised, matching core's own reader: `0` means
  "not installed here", so reporting it for a bad prefix would tell the
  operator something false and send the updater off to install a schema
  over live data. Genuine unreachability still yields `0`, which is safe
  only because `up/1` re-reads the version in migration context before
  touching anything — a wrong `0` costs a redundant migration file, never
  wrong DDL.
  """
  @spec migrated_version_runtime(keyword() | map()) :: non_neg_integer()
  def migrated_version_runtime(opts \\ []) do
    opts = with_defaults(opts, @initial_version)
    read_version(PhoenixKit.RepoHelper.repo(), opts.prefix)
  rescue
    e in ArgumentError -> reraise e, __STACKTRACE__
    _ -> 0
  end

  @doc """
  The SQL `up/1` executes, as data — the testable single source. The
  ownership test suite parses these statements to prove that the object
  names are core's `V135`/`V167`/`V168`/`V185` names, that every `CREATE TABLE`
  stays shape-identical to core's `ExpectedSchema` manifest, that every
  varchar width is its owning schema's `column_widths/0`, and that nothing
  here can drop a table.

  `target` selects how much of the chain to emit (default
  `current_version/0`): `0` applies nothing (not an operation — clearing
  the marker is `down/1`'s job); `1` is the pure `V135`/`V167`/`V168`/`V185`-adoption
  step across all 13 tables.
  """
  @spec up_statements(String.t(), non_neg_integer()) :: [String.t()]
  def up_statements(prefix \\ @default_prefix, target \\ @current_version)

  def up_statements(prefix, target) when is_integer(target) and target >= 0 do
    validate_target!(target)
    prefix = validated_prefix(prefix)

    if target == 0 do
      []
    else
      v1_statements(prefix, target)
    end
  end

  @doc """
  The SQL `down/1` executes, as data (marker bookkeeping only, on the
  anchor table). V1 changes no shape of its own — it is pure adoption — so
  there is nothing to drop beyond the marker; all 13 tables and every row in
  them are left untouched, for any target including `0`.
  """
  @spec down_statements(String.t(), non_neg_integer()) :: [String.t()]
  def down_statements(prefix \\ @default_prefix, target \\ 0)

  def down_statements(prefix, target) when is_integer(target) and target >= 0 do
    validate_target!(target)
    prefix = validated_prefix(prefix)
    qualified = Helpers.qualify_table(@version_table, prefix)

    if target > 0 do
      ["COMMENT ON TABLE #{qualified} IS '#{@marker_prefix}#{target}'"]
    else
      ["COMMENT ON TABLE #{qualified} IS NULL"]
    end
  end

  # ── V1 statement builder ────────────────────────────────────────────────

  defp v1_statements(prefix, target) do
    users = Helpers.qualify_table("phoenix_kit_users", prefix)
    files = Helpers.qualify_table("phoenix_kit_files", prefix)
    uuid_default = Helpers.uuid_v7_call(prefix)

    q_posts = Helpers.qualify_table(@posts, prefix)
    q_post_comments = Helpers.qualify_table(@post_comments, prefix)
    q_post_likes = Helpers.qualify_table(@post_likes, prefix)
    q_post_dislikes = Helpers.qualify_table(@post_dislikes, prefix)
    q_post_tags = Helpers.qualify_table(@post_tags, prefix)
    q_post_tag_assignments = Helpers.qualify_table(@post_tag_assignments, prefix)
    q_post_groups = Helpers.qualify_table(@post_groups, prefix)
    q_post_group_assignments = Helpers.qualify_table(@post_group_assignments, prefix)
    q_post_media = Helpers.qualify_table(@post_media, prefix)
    q_post_mentions = Helpers.qualify_table(@post_mentions, prefix)
    q_post_views = Helpers.qualify_table(@post_views, prefix)
    q_comment_likes = Helpers.qualify_table(@comment_likes, prefix)
    q_comment_dislikes = Helpers.qualify_table(@comment_dislikes, prefix)

    pw = Post.column_widths()
    cw = PostComment.column_widths()
    gw = PostGroup.column_widths()
    mw = PostMention.column_widths()
    tw = PostTag.column_widths()
    vw = PostView.column_widths()

    tables = [
      """
      CREATE TABLE IF NOT EXISTS #{q_posts} (
        "uuid" uuid DEFAULT #{uuid_default} NOT NULL,
        "title" character varying(#{pw.title}) NOT NULL,
        "sub_title" character varying(#{pw.sub_title}),
        "content" text NOT NULL,
        "type" character varying(#{pw.type}) DEFAULT 'post'::character varying NOT NULL,
        "status" character varying(#{pw.status}) DEFAULT 'draft'::character varying NOT NULL,
        "scheduled_at" timestamp with time zone,
        "published_at" timestamp with time zone,
        "repost_url" character varying(#{pw.repost_url}),
        "slug" character varying(#{pw.slug}) NOT NULL,
        "like_count" integer DEFAULT 0 NOT NULL,
        "comment_count" integer DEFAULT 0 NOT NULL,
        "view_count" integer DEFAULT 0 NOT NULL,
        "metadata" jsonb DEFAULT '{}'::jsonb,
        "inserted_at" timestamp with time zone NOT NULL,
        "updated_at" timestamp with time zone NOT NULL,
        "dislike_count" integer DEFAULT 0 NOT NULL,
        "user_uuid" uuid NOT NULL
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS #{q_post_comments} (
        "uuid" uuid DEFAULT #{uuid_default} NOT NULL,
        "post_uuid" uuid NOT NULL,
        "parent_uuid" uuid,
        "content" text NOT NULL,
        "status" character varying(#{cw.status}) DEFAULT 'published'::character varying NOT NULL,
        "depth" integer DEFAULT 0 NOT NULL,
        "like_count" integer DEFAULT 0 NOT NULL,
        "inserted_at" timestamp with time zone NOT NULL,
        "updated_at" timestamp with time zone NOT NULL,
        "dislike_count" integer DEFAULT 0 NOT NULL,
        "user_uuid" uuid NOT NULL
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS #{q_post_likes} (
        "uuid" uuid DEFAULT #{uuid_default} NOT NULL,
        "post_uuid" uuid NOT NULL,
        "inserted_at" timestamp with time zone NOT NULL,
        "updated_at" timestamp with time zone NOT NULL,
        "user_uuid" uuid NOT NULL
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS #{q_post_dislikes} (
        "uuid" uuid DEFAULT #{uuid_default} NOT NULL,
        "post_uuid" uuid NOT NULL,
        "inserted_at" timestamp with time zone NOT NULL,
        "updated_at" timestamp with time zone NOT NULL,
        "user_uuid" uuid NOT NULL
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS #{q_post_tags} (
        "uuid" uuid DEFAULT #{uuid_default} NOT NULL,
        "name" character varying(#{tw.name}) NOT NULL,
        "slug" character varying(#{tw.slug}) NOT NULL,
        "usage_count" integer DEFAULT 0 NOT NULL,
        "inserted_at" timestamp with time zone NOT NULL,
        "updated_at" timestamp with time zone NOT NULL
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS #{q_post_tag_assignments} (
        "post_uuid" uuid NOT NULL,
        "tag_uuid" uuid NOT NULL,
        "inserted_at" timestamp with time zone NOT NULL,
        "updated_at" timestamp with time zone NOT NULL
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS #{q_post_groups} (
        "uuid" uuid DEFAULT #{uuid_default} NOT NULL,
        "name" character varying(#{gw.name}) NOT NULL,
        "slug" character varying(#{gw.slug}) NOT NULL,
        "description" text,
        "cover_image_uuid" uuid,
        "post_count" integer DEFAULT 0 NOT NULL,
        "is_public" boolean DEFAULT false NOT NULL,
        "position" integer DEFAULT 0 NOT NULL,
        "inserted_at" timestamp with time zone NOT NULL,
        "updated_at" timestamp with time zone NOT NULL,
        "user_uuid" uuid NOT NULL
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS #{q_post_group_assignments} (
        "post_uuid" uuid NOT NULL,
        "group_uuid" uuid NOT NULL,
        "position" integer DEFAULT 0 NOT NULL,
        "inserted_at" timestamp with time zone NOT NULL,
        "updated_at" timestamp with time zone NOT NULL
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS #{q_post_media} (
        "uuid" uuid DEFAULT #{uuid_default} NOT NULL,
        "post_uuid" uuid NOT NULL,
        "file_uuid" uuid NOT NULL,
        "position" integer NOT NULL,
        "caption" text,
        "inserted_at" timestamp with time zone NOT NULL,
        "updated_at" timestamp with time zone NOT NULL
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS #{q_post_mentions} (
        "uuid" uuid DEFAULT #{uuid_default} NOT NULL,
        "post_uuid" uuid NOT NULL,
        "mention_type" character varying(#{mw.mention_type}) DEFAULT 'mention'::character varying NOT NULL,
        "inserted_at" timestamp with time zone NOT NULL,
        "updated_at" timestamp with time zone NOT NULL,
        "user_uuid" uuid NOT NULL
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS #{q_post_views} (
        "uuid" uuid DEFAULT #{uuid_default} NOT NULL,
        "post_uuid" uuid NOT NULL,
        "ip_address" character varying(#{vw.ip_address}),
        "user_agent_hash" character varying(#{vw.user_agent_hash}),
        "session_id" character varying(#{vw.session_id}),
        "viewed_at" timestamp with time zone NOT NULL,
        "inserted_at" timestamp with time zone NOT NULL,
        "updated_at" timestamp with time zone NOT NULL,
        "user_uuid" uuid
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS #{q_comment_likes} (
        "uuid" uuid DEFAULT #{uuid_default} NOT NULL,
        "comment_uuid" uuid NOT NULL,
        "inserted_at" timestamp with time zone NOT NULL,
        "updated_at" timestamp with time zone NOT NULL,
        "user_uuid" uuid NOT NULL
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS #{q_comment_dislikes} (
        "uuid" uuid DEFAULT #{uuid_default} NOT NULL,
        "comment_uuid" uuid NOT NULL,
        "inserted_at" timestamp with time zone NOT NULL,
        "updated_at" timestamp with time zone NOT NULL,
        "user_uuid" uuid NOT NULL
      )
      """
    ]

    # Safety net for a host that ran core's V135/V167/V168 but never V185 (table
    # exists, `time_zone` does not) — `CREATE TABLE IF NOT EXISTS` above
    # no-ops against the existing table and does not retroactively add the
    # column.
    safety_net = [
      "ALTER TABLE #{q_posts} ADD COLUMN IF NOT EXISTS \"time_zone\" character varying(#{pw.time_zone})"
    ]

    pkeys =
      for {table, qualified} <- [
            {@posts, q_posts},
            {@post_comments, q_post_comments},
            {@post_likes, q_post_likes},
            {@post_dislikes, q_post_dislikes},
            {@post_tags, q_post_tags},
            {@post_groups, q_post_groups},
            {@post_media, q_post_media},
            {@post_mentions, q_post_mentions},
            {@post_views, q_post_views},
            {@comment_likes, q_comment_likes},
            {@comment_dislikes, q_comment_dislikes}
          ] do
        pkey_guard(table, qualified, prefix)
      end

    indexes =
      [
        {"", "phoenix_kit_posts_published_at_index", q_posts, "btree", "published_at"},
        {"", "phoenix_kit_posts_scheduled_at_index", q_posts, "btree", "scheduled_at"},
        {"UNIQUE", "phoenix_kit_posts_slug_index", q_posts, "btree", "slug"},
        {"", "phoenix_kit_posts_status_index", q_posts, "btree", "status"},
        {"", "phoenix_kit_posts_status_published_at_index", q_posts, "btree",
         "status, published_at"},
        {"", "phoenix_kit_posts_type_index", q_posts, "btree", "type"},
        {"", "phoenix_kit_posts_type_status_index", q_posts, "btree", "type, status"},
        {"", "phoenix_kit_posts_user_uuid_idx", q_posts, "btree", "user_uuid"},
        {"", "phoenix_kit_post_comments_depth_index", q_post_comments, "btree", "depth"},
        {"", "phoenix_kit_post_comments_parent_id_index", q_post_comments, "btree",
         "parent_uuid"},
        {"", "phoenix_kit_post_comments_post_id_index", q_post_comments, "btree", "post_uuid"},
        {"", "phoenix_kit_post_comments_post_id_parent_id_depth_index", q_post_comments, "btree",
         "post_uuid, parent_uuid, depth"},
        {"", "phoenix_kit_post_comments_status_index", q_post_comments, "btree", "status"},
        {"", "phoenix_kit_post_comments_user_uuid_idx", q_post_comments, "btree", "user_uuid"},
        {"", "phoenix_kit_post_likes_post_id_index", q_post_likes, "btree", "post_uuid"},
        {"", "phoenix_kit_post_likes_user_uuid_idx", q_post_likes, "btree", "user_uuid"},
        {"", "phoenix_kit_post_dislikes_post_id_index", q_post_dislikes, "btree", "post_uuid"},
        {"", "phoenix_kit_post_dislikes_user_uuid_idx", q_post_dislikes, "btree", "user_uuid"},
        {"UNIQUE", "phoenix_kit_post_tags_slug_index", q_post_tags, "btree", "slug"},
        {"", "phoenix_kit_post_tags_usage_count_index", q_post_tags, "btree", "usage_count"},
        {"", "phoenix_kit_post_tag_assignments_post_id_index", q_post_tag_assignments, "btree",
         "post_uuid"},
        {"", "phoenix_kit_post_tag_assignments_tag_id_index", q_post_tag_assignments, "btree",
         "tag_uuid"},
        {"UNIQUE", "phoenix_kit_post_tag_assignments_post_uuid_tag_uuid_index",
         q_post_tag_assignments, "btree", "post_uuid, tag_uuid"},
        {"", "phoenix_kit_post_groups_is_public_index", q_post_groups, "btree", "is_public"},
        {"", "phoenix_kit_post_groups_position_index", q_post_groups, "btree", "position"},
        {"", "phoenix_kit_post_groups_user_uuid_idx", q_post_groups, "btree", "user_uuid"},
        {"UNIQUE", "phoenix_kit_post_groups_user_uuid_slug_index", q_post_groups, "btree",
         "user_uuid, slug"},
        {"", "phoenix_kit_post_group_assignments_group_id_index", q_post_group_assignments,
         "btree", "group_uuid"},
        {"", "phoenix_kit_post_group_assignments_group_id_position_index",
         q_post_group_assignments, "btree", "group_uuid, \"position\""},
        {"", "phoenix_kit_post_group_assignments_position_index", q_post_group_assignments,
         "btree", "\"position\""},
        {"", "phoenix_kit_post_group_assignments_post_id_index", q_post_group_assignments,
         "btree", "post_uuid"},
        {"UNIQUE", "phoenix_kit_post_group_assignments_post_uuid_group_uuid_index",
         q_post_group_assignments, "btree", "post_uuid, group_uuid"},
        {"", "phoenix_kit_post_media_file_id_index", q_post_media, "btree", "file_uuid"},
        {"", "phoenix_kit_post_media_position_index", q_post_media, "btree", "\"position\""},
        {"", "phoenix_kit_post_media_post_id_index", q_post_media, "btree", "post_uuid"},
        {"UNIQUE", "phoenix_kit_post_media_post_uuid_position_index", q_post_media, "btree",
         "post_uuid, \"position\""},
        {"", "phoenix_kit_post_mentions_mention_type_index", q_post_mentions, "btree",
         "mention_type"},
        {"", "phoenix_kit_post_mentions_post_id_index", q_post_mentions, "btree", "post_uuid"},
        {"", "phoenix_kit_post_mentions_user_uuid_idx", q_post_mentions, "btree", "user_uuid"},
        {"", "phoenix_kit_post_views_post_id_index", q_post_views, "btree", "post_uuid"},
        {"", "phoenix_kit_post_views_post_id_viewed_at_index", q_post_views, "btree",
         "post_uuid, viewed_at"},
        {"", "phoenix_kit_post_views_session_id_index", q_post_views, "btree", "session_id"},
        {"", "phoenix_kit_post_views_viewed_at_index", q_post_views, "btree", "viewed_at"},
        {"", "phoenix_kit_post_views_user_uuid_idx", q_post_views, "btree", "user_uuid"},
        {"", "phoenix_kit_comment_likes_comment_id_index", q_comment_likes, "btree",
         "comment_uuid"},
        {"", "phoenix_kit_comment_likes_user_uuid_idx", q_comment_likes, "btree", "user_uuid"},
        {"", "phoenix_kit_comment_dislikes_comment_id_index", q_comment_dislikes, "btree",
         "comment_uuid"},
        {"", "phoenix_kit_comment_dislikes_user_uuid_idx", q_comment_dislikes, "btree",
         "user_uuid"}
      ]
      |> Enum.map(fn {unique, name, table, method, columns} ->
        "CREATE #{unique_prefix(unique)}INDEX IF NOT EXISTS #{name} ON #{table} USING #{method} (#{columns})"
      end)

    fks = [
      fk_guard(@posts, q_posts, "fk_posts_user_uuid", "user_uuid", users, "CASCADE", prefix),
      fk_guard(
        @post_comments,
        q_post_comments,
        "phoenix_kit_post_comments_parent_id_fkey",
        "parent_uuid",
        q_post_comments,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @post_comments,
        q_post_comments,
        "phoenix_kit_post_comments_post_id_fkey",
        "post_uuid",
        q_posts,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @post_comments,
        q_post_comments,
        "fk_post_comments_user_uuid",
        "user_uuid",
        users,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @post_likes,
        q_post_likes,
        "phoenix_kit_post_likes_post_id_fkey",
        "post_uuid",
        q_posts,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @post_likes,
        q_post_likes,
        "fk_post_likes_user_uuid",
        "user_uuid",
        users,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @post_dislikes,
        q_post_dislikes,
        "phoenix_kit_post_dislikes_post_id_fkey",
        "post_uuid",
        q_posts,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @post_dislikes,
        q_post_dislikes,
        "fk_post_dislikes_user_uuid",
        "user_uuid",
        users,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @post_tag_assignments,
        q_post_tag_assignments,
        "phoenix_kit_post_tag_assignments_post_id_fkey",
        "post_uuid",
        q_posts,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @post_tag_assignments,
        q_post_tag_assignments,
        "phoenix_kit_post_tag_assignments_tag_id_fkey",
        "tag_uuid",
        q_post_tags,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @post_groups,
        q_post_groups,
        "phoenix_kit_post_groups_cover_image_id_fkey",
        "cover_image_uuid",
        files,
        "SET NULL",
        prefix
      ),
      fk_guard(
        @post_groups,
        q_post_groups,
        "fk_post_groups_user_uuid",
        "user_uuid",
        users,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @post_group_assignments,
        q_post_group_assignments,
        "phoenix_kit_post_group_assignments_group_id_fkey",
        "group_uuid",
        q_post_groups,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @post_group_assignments,
        q_post_group_assignments,
        "phoenix_kit_post_group_assignments_post_id_fkey",
        "post_uuid",
        q_posts,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @post_media,
        q_post_media,
        "phoenix_kit_post_media_file_id_fkey",
        "file_uuid",
        files,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @post_media,
        q_post_media,
        "phoenix_kit_post_media_post_id_fkey",
        "post_uuid",
        q_posts,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @post_mentions,
        q_post_mentions,
        "phoenix_kit_post_mentions_post_id_fkey",
        "post_uuid",
        q_posts,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @post_mentions,
        q_post_mentions,
        "fk_post_mentions_user_uuid",
        "user_uuid",
        users,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @post_views,
        q_post_views,
        "phoenix_kit_post_views_post_id_fkey",
        "post_uuid",
        q_posts,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @post_views,
        q_post_views,
        "fk_post_views_user_uuid",
        "user_uuid",
        users,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @comment_likes,
        q_comment_likes,
        "phoenix_kit_comment_likes_comment_id_fkey",
        "comment_uuid",
        q_post_comments,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @comment_likes,
        q_comment_likes,
        "fk_comment_likes_user_uuid",
        "user_uuid",
        users,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @comment_dislikes,
        q_comment_dislikes,
        "phoenix_kit_comment_dislikes_comment_id_fkey",
        "comment_uuid",
        q_post_comments,
        "CASCADE",
        prefix
      ),
      fk_guard(
        @comment_dislikes,
        q_comment_dislikes,
        "fk_comment_dislikes_user_uuid",
        "user_uuid",
        users,
        "CASCADE",
        prefix
      )
    ]

    marker = ["COMMENT ON TABLE #{q_posts} IS '#{@marker_prefix}#{target}'"]

    tables ++ safety_net ++ pkeys ++ indexes ++ fks ++ marker
  end

  defp unique_prefix("UNIQUE"), do: "UNIQUE "
  defp unique_prefix(""), do: ""

  defp pkey_guard(table, qualified, prefix) do
    """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE c.conname = '#{table}_pkey'
          AND t.relname = '#{table}'
          AND n.nspname = '#{prefix}'
      ) THEN
        ALTER TABLE #{qualified} ADD CONSTRAINT #{table}_pkey PRIMARY KEY (uuid);
      END IF;
    END
    $$
    """
  end

  defp fk_guard(table, qualified, constraint_name, column, references, on_delete, prefix) do
    """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE c.conname = '#{constraint_name}'
          AND t.relname = '#{table}'
          AND n.nspname = '#{prefix}'
      ) THEN
        ALTER TABLE #{qualified} ADD CONSTRAINT #{constraint_name} FOREIGN KEY (#{column}) REFERENCES #{references}(uuid) ON DELETE #{on_delete};
      END IF;
    END
    $$
    """
  end

  # ── internals ──────────────────────────────────────────────────────────

  defp with_defaults(opts, version) do
    opts = Enum.into(opts, %{})
    prefix = validated_prefix(Map.get(opts, :prefix) || @default_prefix)

    opts
    |> Map.put(:prefix, prefix)
    |> Map.put_new(:version, version)
  end

  defp read_version(repo, prefix) do
    if table_exists?(repo, prefix) do
      repo |> table_comment(prefix) |> parse_version()
    else
      0
    end
  end

  defp table_exists?(repo, prefix) do
    query = """
    SELECT EXISTS (
      SELECT FROM information_schema.tables
      WHERE table_name = $1 AND table_schema = $2
    )
    """

    case repo.query(query, [@version_table, prefix], log: false) do
      {:ok, %{rows: [[exists?]]}} -> exists?
      {:error, error} -> raise error
    end
  end

  defp table_comment(repo, prefix) do
    query = """
    SELECT pg_catalog.obj_description(c.oid, 'pg_class')
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = $1 AND n.nspname = $2
    """

    case repo.query(query, [@version_table, prefix], log: false) do
      {:ok, %{rows: [[comment]]}} -> comment
      {:ok, %{rows: []}} -> nil
      {:error, error} -> raise error
    end
  end

  defp parse_version(@marker_prefix <> n) do
    case Integer.parse(n) do
      {version, ""} when version >= 0 -> version
      _ -> 0
    end
  end

  defp parse_version(_), do: 0

  defp validate_target!(target) when target > @current_version do
    raise ArgumentError,
          "PhoenixKitPosts.Migrations has no version #{target} " <>
            "(current_version/0 is #{@current_version}); stamping it would make every " <>
            "later version look already applied"
  end

  defp validate_target!(_target), do: :ok

  defp validated_prefix(prefix) do
    if Code.ensure_loaded?(Helpers) and function_exported?(Helpers, :validate_prefix!, 1) do
      Helpers.validate_prefix!(prefix)
    else
      unless is_binary(prefix) and prefix =~ ~r/^[a-z_][a-z0-9_]*$/ and byte_size(prefix) <= 20 do
        raise ArgumentError, "invalid schema prefix: #{inspect(prefix)}"
      end
    end

    prefix
  end
end
