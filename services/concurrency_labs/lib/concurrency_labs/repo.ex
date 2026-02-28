defmodule ConcurrencyLabs.Repo do
  use Ecto.Repo,
    otp_app: :concurrency_labs,
    adapter: Ecto.Adapters.Postgres
end
