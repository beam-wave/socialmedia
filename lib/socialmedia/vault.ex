defmodule Socialmedia.Vault do
  @moduledoc "Encrypts secrets at rest (Instagram access tokens)."
  use Cloak.Vault, otp_app: :socialmedia

  @impl GenServer
  def init(config) do
    key = Application.fetch_env!(:socialmedia, :cloak_key) |> Base.decode64!()

    config =
      Keyword.put(config, :ciphers,
        default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: key, iv_length: 12}
      )

    {:ok, config}
  end
end

defmodule Socialmedia.Encrypted.Binary do
  @moduledoc false
  use Cloak.Ecto.Binary, vault: Socialmedia.Vault
end
