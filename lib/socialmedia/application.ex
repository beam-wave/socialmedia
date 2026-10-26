defmodule Socialmedia.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Socialmedia.Workers.ProduceFailures.attach()

    children = [
      SocialmediaWeb.Telemetry,
      Socialmedia.Repo,
      {DNSCluster, query: Application.get_env(:socialmedia, :dns_cluster_query) || :ignore},
      Socialmedia.Vault,
      {Phoenix.PubSub, name: Socialmedia.PubSub},
      {Oban, Application.fetch_env!(:socialmedia, Oban)},
      # Start to serve requests, typically the last entry
      SocialmediaWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Socialmedia.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SocialmediaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
