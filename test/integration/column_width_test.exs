defmodule PhoenixKitPosts.Integration.ColumnWidthTest do
  @moduledoc """
  Every `character varying(n)` column a caller can write must be bounded by
  `column_widths/0` — the same map `PhoenixKitPosts.Migrations` builds its DDL
  from.

  This needs the database because the failure it guards against is invisible
  without one: the changeset says `valid?`, and Postgres raises `22001` on the
  insert. The admin editor turned that into a 500 with no form error, for a
  subtitle the page's own character counter invited the user to type.
  """
  use PhoenixKitPosts.DataCase, async: true

  alias PhoenixKitPosts.Post
  alias PhoenixKitPosts.PostGroup
  alias PhoenixKitPosts.PostTag

  setup do
    %{user: user_fixture()}
  end

  defp over(field), do: String.duplicate("a", Post.column_widths()[field] + 1)

  test "a subtitle wider than the column is a form error, not a 22001", %{user: user} do
    changeset =
      Post.changeset(%Post{}, %{
        title: "Overflow",
        content: "Body",
        sub_title: over(:sub_title),
        user_uuid: user.uuid
      })

    refute changeset.valid?
    assert Keyword.has_key?(changeset.errors, :sub_title)
  end

  test "a repost_url wider than the column is a form error, not a 22001", %{user: user} do
    changeset =
      Post.changeset(%Post{}, %{
        title: "Repost",
        content: "Body",
        type: "repost",
        repost_url: "https://example.com/?q=" <> over(:repost_url),
        user_uuid: user.uuid
      })

    refute changeset.valid?
    assert Keyword.has_key?(changeset.errors, :repost_url)
  end

  test "an explicitly supplied slug wider than the column is a form error", %{user: user} do
    changeset =
      Post.changeset(%Post{}, %{
        title: "Explicit",
        content: "Body",
        slug: String.downcase(over(:slug)),
        user_uuid: user.uuid
      })

    refute changeset.valid?
    assert Keyword.has_key?(changeset.errors, :slug)
  end

  # The generated path cannot produce a form error — nobody typed the slug — so
  # it has to fit instead. A title at the column's own width slugifies to a slug
  # at the column's own width, and the collision suffix then has nowhere to go
  # unless `ensure_unique/3` is told the ceiling.
  test "a colliding maximum-length title still yields a slug that fits", %{user: user} do
    title = String.duplicate("a", Post.column_widths().title)
    width = Post.column_widths().slug

    {:ok, first} = PhoenixKitPosts.create_post(user.uuid, %{"title" => title, "content" => "B"})
    {:ok, second} = PhoenixKitPosts.create_post(user.uuid, %{"title" => title, "content" => "B"})

    assert String.length(first.slug) <= width
    assert String.length(second.slug) <= width
    assert second.slug != first.slug
    assert String.ends_with?(second.slug, "-2")
  end

  test "a group slug wider than the column is a form error", %{user: user} do
    changeset =
      PostGroup.changeset(%PostGroup{}, %{
        name: "Group",
        slug: String.duplicate("a", PostGroup.column_widths().slug + 1),
        user_uuid: user.uuid
      })

    refute changeset.valid?
    assert Keyword.has_key?(changeset.errors, :slug)
  end

  test "a tag slug wider than the column is a form error" do
    changeset =
      PostTag.changeset(%PostTag{}, %{
        name: "Tag",
        slug: String.duplicate("a", PostTag.column_widths().slug + 1)
      })

    refute changeset.valid?
    assert Keyword.has_key?(changeset.errors, :slug)
  end
end
