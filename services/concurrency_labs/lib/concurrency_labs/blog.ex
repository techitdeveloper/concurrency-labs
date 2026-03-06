# lib/concurrency_labs/blog.ex
#
# The Blog context. Single public API for everything blog-related.
# NimblePublisher does the heavy lifting at compile time:
#   - walks priv/posts/*.md
#   - parses YAML frontmatter via yaml_elixir
#   - converts Markdown body to HTML via earmark
#   - calls Post.build/3 for each file
#   - injects the result list as @posts module attribute
#
# Adding a new post = drop a .md file in priv/posts/ and redeploy.
# No DB. No migrations. No admin panel. No auth.

defmodule ConcurrencyLabs.Blog do
  use NimblePublisher,
    build: ConcurrencyLabs.Blog.Post,
    from: Application.app_dir(:concurrency_labs, "priv/posts/**/*.md"),
    as: :posts,
    earmark_options: %Earmark.Options{
      code_class_prefix: "language-",  # works with highlight.js
      smartypants: true
    }

  # NimblePublisher injects @posts here at compile time.
  # We sort once and store — zero runtime overhead.
  @sorted_posts Enum.sort_by(@posts, & &1.date, {:desc, Date})

  # All unique tags derived at compile time
  @all_tags @sorted_posts |> Enum.flat_map(& &1.tags) |> Enum.uniq() |> Enum.sort()

  # -------------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------------

  @doc "Returns all posts sorted newest-first."
  def all_posts, do: @sorted_posts

  @doc "Returns recent N posts (default 5). Useful for homepage previews."
  def recent_posts(n \\ 5), do: Enum.take(@sorted_posts, n)

  @doc "Returns a single post by id (slug), or raises NotFoundError."
  def get_post!(id) do
    Enum.find(@sorted_posts, &(&1.id == id)) ||
      raise ConcurrencyLabs.Blog.NotFoundError, "post not found: #{id}"
  end

  @doc "Returns all posts with a given tag."
  def posts_by_tag(tag) do
    Enum.filter(@sorted_posts, &(tag in &1.tags))
  end

  @doc "Returns all unique tags across all posts."
  def all_tags, do: @all_tags
end

# Simple not-found error — lets the router return a clean 404.
defmodule ConcurrencyLabs.Blog.NotFoundError do
  defexception [:message]
  @impl true
  def exception(msg), do: %__MODULE__{message: msg}
end
