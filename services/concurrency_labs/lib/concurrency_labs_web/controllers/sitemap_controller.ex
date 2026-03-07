# lib/concurrency_labs_web/controllers/sitemap_controller.ex

defmodule ConcurrencyLabsWeb.SitemapController do
  use ConcurrencyLabsWeb, :controller

  alias ConcurrencyLabs.Blog

  @static_pages [
    {"/", "monthly", "1.0"},
    {"/elixir-concurrency", "monthly", "0.8"},
    {"/go-concurrency", "monthly", "0.8"},
    {"/hire", "monthly", "0.6"}
  ]

  def index(conn, _params) do
    base_url =
      ConcurrencyLabsWeb.Endpoint.url()
      |> String.trim_trailing("/")

    posts = Blog.all_posts()

    latest_post_date =
      posts
      |> Enum.map(& &1.date)
      |> Enum.max(fn -> Date.utc_today() end)
      |> Date.to_iso8601()

    static_entries =
      Enum.map_join(@static_pages, "\n", fn {path, changefreq, priority} ->
        """
        <url>
          <loc>#{base_url}#{path}</loc>
          <changefreq>#{changefreq}</changefreq>
          <priority>#{priority}</priority>
        </url>
        """
      end)

    blog_entry = """
    <url>
      <loc>#{base_url}/blog</loc>
      <lastmod>#{latest_post_date}</lastmod>
      <changefreq>weekly</changefreq>
      <priority>0.8</priority>
    </url>
    """

    post_entries =
      Enum.map_join(posts, "\n", fn post ->
        """
        <url>
          <loc>#{base_url}/blog/#{post.id}</loc>
          <lastmod>#{Date.to_iso8601(post.date)}</lastmod>
          <changefreq>never</changefreq>
          <priority>0.7</priority>
        </url>
        """
      end)

    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{static_entries}
    #{blog_entry}
    #{post_entries}
    </urlset>
    """

    conn
    |> put_resp_content_type("text/xml; charset=utf-8")
    |> send_resp(200, xml)
  end
end
