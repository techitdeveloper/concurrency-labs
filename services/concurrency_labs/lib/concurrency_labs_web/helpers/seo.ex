defmodule ConcurrencyLabsWeb.Helpers.SEO do

  @author "Concurrency Labs"

  def blog_post_json_ld(post) do
    base = ConcurrencyLabsWeb.Endpoint.url() |> String.trim_trailing("/")

    %{
      "@context" => "https://schema.org",
      "@type" => "BlogPosting",
      "headline" => post.title,
      "description" => post.description,
      "datePublished" => Date.to_iso8601(post.date),
      "dateModified" => Date.to_iso8601(post.date),
      "author" => %{
        "@type" => "Person",
        "name" => @author
      },
      "mainEntityOfPage" => %{
        "@type" => "WebPage",
        "@id" => "#{base}/blog/#{post.id}"
      },
      "url" => "#{base}/blog/#{post.id}",
      "keywords" => Enum.join(post.tags, ", ")
    }
    |> Jason.encode!()
  end
end
