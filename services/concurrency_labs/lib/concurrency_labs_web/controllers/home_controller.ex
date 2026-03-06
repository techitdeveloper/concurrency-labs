# lib/concurrency_labs_web/controllers/home_controller.ex

defmodule ConcurrencyLabsWeb.HomeController do
  use ConcurrencyLabsWeb, :controller

  alias ConcurrencyLabs.Blog
  alias ConcurrencyLabs.HomeContent

  def index(conn, _params) do
    conn
    |> assign(:page_title, "concurrency-labs")
    |> assign(
      :page_description,
      "Live Elixir/OTP and Go concurrency experiments. Real processes, real goroutines, real metrics."
    )
    |> render(:index,
      recent_posts: Blog.recent_posts(3),
      hero: HomeContent.hero(),
      hero_stats: HomeContent.hero_stats(),
      what_this_is: HomeContent.what_this_is(),
      labs: HomeContent.labs(),
      work: HomeContent.work(),
      about: HomeContent.about()
    )
  end
end
