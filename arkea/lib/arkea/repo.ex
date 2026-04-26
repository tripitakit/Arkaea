defmodule Arkea.Repo do
  use Ecto.Repo,
    otp_app: :arkea,
    adapter: Ecto.Adapters.Postgres
end
