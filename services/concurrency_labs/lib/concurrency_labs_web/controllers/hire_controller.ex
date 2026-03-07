# lib/concurrency_labs_web/controllers/hire_controller.ex

defmodule ConcurrencyLabsWeb.HireController do
  use ConcurrencyLabsWeb, :controller

  alias ConcurrencyLabs.HomeContent

  def index(conn, _params) do
    h = HomeContent.hire()

    conn
    |> assign(:page_title, "Hire Me")
    |> assign(:page_description, h.positioning)
    |> render(:index,
      hire: h,
      work: HomeContent.work(),
      labs: HomeContent.labs()
    )
  end
end
