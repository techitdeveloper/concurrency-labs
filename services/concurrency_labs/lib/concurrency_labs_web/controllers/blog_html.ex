# lib/concurrency_labs_web/controllers/blog_html.ex
#
# Phoenix 1.7+ uses the HTML module pattern.
# Templates live alongside this file in blog_html/

defmodule ConcurrencyLabsWeb.BlogHTML do
  use ConcurrencyLabsWeb, :html

  embed_templates "blog_html/*"

  # Shared helper used in both templates
  def format_date(%Date{} = d) do
    month = ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec) |> Enum.at(d.month - 1)
    "#{month} #{d.day}, #{d.year}"
  end
end
