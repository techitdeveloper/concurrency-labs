# lib/concurrency_labs_web/controllers/home_html.ex

defmodule ConcurrencyLabsWeb.HomeHTML do
  use ConcurrencyLabsWeb, :html

  embed_templates "home_html/*"

  def format_date(%Date{} = d) do
    month = ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec) |> Enum.at(d.month - 1)
    "#{month} #{d.day}, #{d.year}"
  end
end
