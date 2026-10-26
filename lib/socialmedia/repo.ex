defmodule Socialmedia.Repo do
  use Ecto.Repo,
    otp_app: :socialmedia,
    adapter: Ecto.Adapters.Postgres
end
