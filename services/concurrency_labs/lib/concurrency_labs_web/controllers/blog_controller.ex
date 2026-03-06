# lib/concurrency_labs_web/controllers/blog_controller.ex

defmodule ConcurrencyLabsWeb.BlogController do
  use ConcurrencyLabsWeb, :controller

  alias ConcurrencyLabs.Blog
  alias ConcurrencyLabs.Blog.NotFoundError

  def index(conn, params) do
    {posts, active_tag} =
      case params do
        %{"tag" => tag} -> {Blog.posts_by_tag(tag), tag}
        _ -> {Blog.all_posts(), nil}
      end

    conn
    |> assign(:page_title, "Writing")
    |> assign(
      :page_description,
      "Technical writing on Elixir/OTP, Go runtime behaviour, and backend system design."
    )
    |> render(:index, posts: posts, all_tags: Blog.all_tags(), active_tag: active_tag)
  end

  def show(conn, %{"id" => id}) do
    post = Blog.get_post!(id)

    conn
    |> assign(:page_title, post.title)
    |> assign(:page_description, post.description)
    |> render(:show, post: post)
  rescue
    NotFoundError ->
      conn
      |> put_status(:not_found)
      |> render(:not_found, [])
  end
end
