defmodule SocialmediaWeb.Plugs.AdminAuth do
  @moduledoc """
  HTTP basic auth for the admin panel when ADMIN_PASSWORD is set.
  Without a password (local dev) the panel is open; it only binds to 127.0.0.1 in dev.
  """
  def init(opts), do: opts

  def call(conn, _opts) do
    case Application.get_env(:socialmedia, :admin_password) do
      pw when is_binary(pw) and pw != "" ->
        Plug.BasicAuth.basic_auth(conn,
          username: Application.get_env(:socialmedia, :admin_user, "admin"),
          password: pw
        )

      _ ->
        conn
    end
  end
end
