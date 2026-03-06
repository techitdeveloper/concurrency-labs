# lib/concurrency_labs/blog/post.ex
#
# Defines the shape of a single blog post.
# NimblePublisher calls build/3 at compile time for every .md file it finds.
# Any missing required field raises at compile time — no silent failures at runtime.

defmodule ConcurrencyLabs.Blog.Post do
  @enforce_keys [:id, :title, :date, :description, :tags, :body, :reading_time_min]
  defstruct [
    # derived from filename: "2024-01-15-beam-memory" → slug used in URL
    :id,
    # frontmatter: title
    :title,
    # frontmatter: date (parsed to Date)
    :date,
    # frontmatter: description (used in meta tags + card preview)
    :description,
    # frontmatter: tags (list of strings)
    :tags,
    # rendered HTML (earmark does the conversion)
    :body,
    # computed from word count
    :reading_time_min
  ]

  # NimblePublisher calls build/3 at compile time for each .md file.
  # `filename` is the FULL absolute path — we derive the slug from the basename.
  # `attrs`    is a map with ATOM keys (not string keys).
  # `body`     is the rendered HTML string.
  def build(filename, attrs, body) do
    # "/full/path/priv/posts/2024-01-20-beam-memory.md" → "2024-01-20-beam-memory"
    id = filename |> Path.basename(".md")

    date = parse_date!(attrs[:date], id)

    struct!(
      __MODULE__,
      id: id,
      title: fetch_required!(attrs, :title, id),
      date: date,
      description: fetch_required!(attrs, :description, id),
      tags: attrs[:tags] || [],
      body: body,
      reading_time_min: estimate_reading_time(body)
    )
  end

  # ---------------------------------------------------------------------------

  defp fetch_required!(attrs, key, id) do
    case Map.fetch(attrs, key) do
      {:ok, val} when val not in [nil, ""] -> val
      _ -> raise "Post #{id} is missing required frontmatter field: #{key}"
    end
  end

  defp parse_date!(nil, id),
    do: raise("Post #{id} is missing required frontmatter field: date")

  defp parse_date!(value, id) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _} -> raise "Post #{id} has invalid date: #{value} — expected YYYY-MM-DD"
    end
  end

  defp estimate_reading_time(html) do
    word_count =
      html
      |> String.replace(~r/<[^>]+>/, " ")
      |> String.split(~r/\s+/, trim: true)
      |> length()

    max(1, div(word_count, 200))
  end
end
