defmodule PhoenixKitPosts.MigrationsDataSafetyTest do
  use PhoenixKitPosts.DataCase, async: false

  alias Ecto.Migration.Runner
  alias PhoenixKitPosts.Migrations
  alias PhoenixKitPosts.Post
  alias PhoenixKitPosts.PostLike
  alias PhoenixKitPosts.PostTag
  alias PhoenixKitPosts.PostTagAssignment

  @moduledoc """
  The acceptance a table full of real user posts actually needs, and that no
  static test can give: REAL rows, a REAL `down/1` run as a migration, and
  the rows still there afterwards, byte-for-byte.

  `migrations_test.exs` proves what the chain BUILDS (no
  DROP/TRUNCATE/DELETE token anywhere, `down/1` emits marker bookkeeping
  only). That is a proof about text. This file proves what the chain DOES
  to a database that holds a real post, a real like, and a real tag
  assignment — on `phoenix_kit_posts`, the anchor table, and two of its
  dependents.

  The last test is the mutation check: it runs the same survival harness
  against a deliberately destructive rollback and requires it to FAIL.
  Without that, a survival assertion that silently stopped asserting (wrong
  table name, empty row set) would stay green forever and prove nothing.

  `async: false` — the migrator wants the shared sandbox connection.
  """

  defmodule RollbackToZero do
    @moduledoc false
    use Ecto.Migration

    def up, do: Migrations.down(prefix: "public", version: 0)
    def down, do: :ok
  end

  defmodule RollbackToOneFromMap do
    @moduledoc false
    use Ecto.Migration

    # Deliberately the MAP shape: it is accepted, so it must carry
    # `:version` like the keyword list does.
    def up, do: Migrations.down(%{prefix: "public", version: 1})
    def down, do: :ok
  end

  defmodule DestructiveRollback do
    @moduledoc false
    use Ecto.Migration

    # NOT what the package ships — the mutant the survival check must catch.
    def up do
      execute("DELETE FROM public.phoenix_kit_post_tag_assignments")
      execute("DELETE FROM public.phoenix_kit_post_likes")
      execute("DELETE FROM public.phoenix_kit_posts")
    end

    def down, do: :ok
  end

  setup do
    user = user_fixture()
    post = post_fixture(user, title: "Data safety post", status: "public")

    {:ok, like} =
      %PostLike{}
      |> PostLike.changeset(%{post_uuid: post.uuid, user_uuid: user.uuid})
      |> Repo.insert()

    {:ok, tag} =
      %PostTag{}
      |> PostTag.changeset(%{
        name: "Elixir",
        slug: "elixir-#{System.unique_integer([:positive])}"
      })
      |> Repo.insert()

    {:ok, assignment} =
      %PostTagAssignment{}
      |> PostTagAssignment.changeset(%{post_uuid: post.uuid, tag_uuid: tag.uuid})
      |> Repo.insert()

    {:ok, post: post, like: like, tag: tag, assignment: assignment}
  end

  test "a real down(version: 0) leaves the seeded post, like and tag assignment alive",
       %{post: post, like: like, tag: tag} do
    post_count = count("phoenix_kit_posts")
    like_count = count("phoenix_kit_post_likes")
    assignment_count = count("phoenix_kit_post_tag_assignments")

    run_migration(RollbackToZero)

    assert count("phoenix_kit_posts") == post_count,
           "rolling this chain back changed the row count in phoenix_kit_posts"

    assert count("phoenix_kit_post_likes") == like_count,
           "rolling this chain back changed the row count in phoenix_kit_post_likes"

    assert count("phoenix_kit_post_tag_assignments") == assignment_count,
           "rolling this chain back changed the row count in phoenix_kit_post_tag_assignments"

    reloaded_post = Repo.get!(Post, post.uuid)
    assert reloaded_post.title == post.title
    assert reloaded_post.slug == post.slug
    assert reloaded_post.status == post.status

    reloaded_like = Repo.get!(PostLike, like.uuid)
    assert reloaded_like.post_uuid == like.post_uuid
    assert reloaded_like.user_uuid == like.user_uuid

    assert Repo.get!(PostTag, tag.uuid).name == tag.name
  end

  test "the rollback still does its one real job: the marker is cleared" do
    Repo.query!("COMMENT ON TABLE phoenix_kit_posts IS 'pkpo_schema:1'")
    assert Migrations.migrated_version_runtime(prefix: "public") == 1

    run_migration(RollbackToZero)

    assert Migrations.migrated_version_runtime(prefix: "public") == 0
  end

  test "a rollback to version 1 passed as a map stops at 1, not at 0" do
    Repo.query!("COMMENT ON TABLE phoenix_kit_posts IS 'pkpo_schema:1'")

    run_migration(RollbackToOneFromMap)

    assert Migrations.migrated_version_runtime(prefix: "public") == 1,
           "the map shape lost :version and rolled the chain further back than asked"
  end

  test "the survival check has teeth: a destructive rollback fails it", %{post: post} do
    post_count = count("phoenix_kit_posts")

    run_migration(DestructiveRollback)

    # The same assertions the real test makes. Both must fail here, or the
    # real test above is decoration.
    assert_raise ExUnit.AssertionError, fn ->
      assert count("phoenix_kit_posts") == post_count
    end

    assert_raise Ecto.NoResultsError, fn ->
      Repo.get!(Post, post.uuid)
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────

  # Runs the migration IN THIS PROCESS, through Ecto's own migration runner,
  # rather than `Ecto.Migrator.up/4`. The Migrator runs the migration inside a
  # `Task`, which then has to check out the sandbox connection this test
  # already owns — it never gets it, and every assertion below dies in the
  # checkout queue instead of testing the rollback. The runner is what the
  # Migrator itself calls once it has dealt with locking and version
  # bookkeeping; going straight to it keeps the real migration context (so
  # `execute/1` inside `down/1` is the real `execute/1`) and drops only the
  # parts this file is not about.
  defp run_migration(module) do
    Runner.run(
      Repo,
      [],
      :os.system_time(:microsecond),
      module,
      :forward,
      :up,
      :up,
      log: false,
      log_migrations_sql: false
    )
  end

  defp count(table) do
    %{rows: [[count]]} = Repo.query!("SELECT count(*) FROM #{table}")
    count
  end
end
