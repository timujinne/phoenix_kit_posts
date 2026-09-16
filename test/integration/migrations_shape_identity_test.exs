defmodule PhoenixKitPosts.Integration.MigrationsShapeIdentityTest do
  @moduledoc """
  The claim V1 rests on, checked against a real database instead of a
  description of one: running this chain into an EMPTY schema produces, for
  all 13 tables, exactly the shape core's own V135→current chain produces.

  `migrations_test.exs` compares the emitted SQL to core's `ExpectedSchema`
  manifest. That is core describing itself — a manifest that drifted from
  core's own migrations would take this chain's DDL with it, and both would
  still agree. Here both chains actually run, into two schemas in the same
  database, and Postgres' own catalogue is the arbiter: every column (type,
  width, nullability, default), every index definition, and every constraint
  definition must match.

  It is also the only place the Phase 2 path is exercised at all. Today core
  creates these tables on every install, so V1's `CREATE TABLE` statements
  are no-ops everywhere and a mistake in one is invisible. Once core's
  baseline squash stops creating them, those statements become the only
  thing that ever builds the tables — this test is what says they can.

  `async: false` — it creates and drops schemas, which is not row-scoped.
  """
  use PhoenixKitPosts.DataCase, async: false

  alias Ecto.Migration.Runner

  @core_schema "pkpo_shape_core"
  @module_schema "pkpo_shape_module"

  @tables ~w(
    phoenix_kit_posts phoenix_kit_post_comments phoenix_kit_post_likes
    phoenix_kit_post_dislikes phoenix_kit_post_tags
    phoenix_kit_post_tag_assignments phoenix_kit_post_groups
    phoenix_kit_post_group_assignments phoenix_kit_post_media
    phoenix_kit_post_mentions phoenix_kit_post_views
    phoenix_kit_comment_likes phoenix_kit_comment_dislikes
  )

  defmodule CoreChain do
    @moduledoc false
    use Ecto.Migration

    def up, do: PhoenixKit.Migration.up(prefix: "pkpo_shape_core", create_schema: true)
    def down, do: :ok
  end

  defmodule ModuleChain do
    @moduledoc false
    use Ecto.Migration

    def up, do: PhoenixKitPosts.Migrations.up(prefix: "pkpo_shape_module")
    def down, do: :ok
  end

  @tag timeout: 600_000
  test "V1 built from scratch is shape-identical to core's chain, table for table" do
    run(CoreChain)

    # Phase 2, as it will actually arrive: the two tables this chain points
    # at from outside itself exist, and nothing else does.
    Repo.query!("CREATE SCHEMA #{@module_schema}")
    Repo.query!(~s|CREATE TABLE #{@module_schema}.phoenix_kit_users ("uuid" uuid PRIMARY KEY)|)
    Repo.query!(~s|CREATE TABLE #{@module_schema}.phoenix_kit_files ("uuid" uuid PRIMARY KEY)|)
    run(ModuleChain)

    core = catalogue(@core_schema)
    module = catalogue(@module_schema)

    for table <- @tables, aspect <- [:columns, :indexes, :constraints] do
      assert drift(core, module, {aspect, table}) == [],
             "#{aspect} drift on #{table}: " <>
               inspect(drift(core, module, {aspect, table}), pretty: true, limit: :infinity)
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────

  # Both chains run in THIS process, through Ecto's own migration runner, for
  # the reason `migrations_data_safety_test.exs` documents: `Ecto.Migrator`
  # runs a migration in a `Task`, which never gets the sandbox connection
  # this test owns. Everything below therefore rolls back with the test.
  defp run(module) do
    Runner.run(Repo, [], :os.system_time(:microsecond), module, :forward, :up, :up,
      log: false,
      log_migrations_sql: false
    )
  end

  defp drift(core, module, key) do
    left = Map.fetch!(core, key)
    right = Map.fetch!(module, key)

    Enum.map(Enum.reject(left, &(&1 in right)), &{:core_only, &1}) ++
      Enum.map(Enum.reject(right, &(&1 in left)), &{:module_only, &1})
  end

  # The schema name is the one legitimate difference between the two builds
  # (it appears in qualified defaults like `<schema>.uuid_generate_v7()` and
  # in every `REFERENCES`), so it is normalised away rather than compared.
  defp catalogue(schema) do
    normalise = fn
      value when is_binary(value) -> String.replace(value, schema, "SCHEMA")
      value -> value
    end

    columns =
      query(
        """
        SELECT table_name, column_name, data_type, character_maximum_length,
               is_nullable, column_default
        FROM information_schema.columns
        WHERE table_schema = $1
        ORDER BY table_name, column_name
        """,
        schema
      )

    indexes =
      query(
        "SELECT tablename, indexname, indexdef FROM pg_indexes WHERE schemaname = $1",
        schema
      )

    constraints =
      query(
        """
        SELECT t.relname, c.conname, pg_get_constraintdef(c.oid)
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = $1
        """,
        schema
      )

    for table <- @tables,
        {aspect, rows} <- [columns: columns, indexes: indexes, constraints: constraints],
        into: %{} do
      values =
        rows
        |> Enum.filter(&(hd(&1) == table))
        |> Enum.map(fn [_table | rest] -> Enum.map(rest, normalise) end)
        |> Enum.sort()

      {{aspect, table}, values}
    end
  end

  defp query(sql, schema), do: Repo.query!(sql, [schema]).rows
end
