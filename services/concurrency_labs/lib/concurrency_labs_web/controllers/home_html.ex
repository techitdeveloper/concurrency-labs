# lib/concurrency_labs_web/controllers/home_html.ex

defmodule ConcurrencyLabsWeb.HomeHTML do
  use ConcurrencyLabsWeb, :html

  import ConcurrencyLabsWeb.Helpers.Utils

  embed_templates "home_html/*"
end
