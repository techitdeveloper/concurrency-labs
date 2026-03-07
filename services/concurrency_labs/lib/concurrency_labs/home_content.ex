# lib/concurrency_labs/home_content.ex
# Loads priv/content/content.exs at compile time.
# @external_resource tells Mix to recompile when the file changes.

defmodule ConcurrencyLabs.HomeContent do
  @content_path Application.app_dir(:concurrency_labs, "priv/content/content.exs")
  @external_resource @content_path
  @content @content_path |> File.read!() |> Code.eval_string() |> elem(0)

  def hero, do: @content.hero
  def hero_stats, do: @content.hero_stats
  def what_this_is, do: @content.what_this_is
  def labs, do: @content.labs
  def work, do: @content.work
  def about, do: @content.about
  def hire, do: @content.hire
end
