# lib/concurrency_labs_web/controllers/blog_html.ex
#
# Phoenix 1.7+ uses the HTML module pattern.
# Templates live alongside this file in blog_html/

defmodule ConcurrencyLabsWeb.BlogHTML do
  use ConcurrencyLabsWeb, :html

  import ConcurrencyLabsWeb.Helpers.Utils
  import ConcurrencyLabsWeb.Helpers.SEO

  embed_templates "blog_html/*"
end
