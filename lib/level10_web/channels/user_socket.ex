defmodule Level10Web.UserSocket do
  use Phoenix.Socket
  require Logger

  ## Channels
  channel "game:*", Level10Web.GameChannel

  # Socket params are passed from the client and can
  # be used to verify and authenticate a user. After
  # verification, you can put default assigns into
  # the socket that will be set for all channels, ie
  #
  #     {:ok, assign(socket, :user_id, verified_user_id)}
  #
  # To deny connection, return `:error`.
  #
  # See `Phoenix.Token` documentation for examples in
  # performing token verification on connect.
  @impl true
  def connect(params = %{"token" => token}, socket, _connect_info) do
    with {:ok, player_id} <- validate_token(socket, token) do
      Logger.debug(fn -> ["Socket connected for player_id ", player_id] end)
      socket = assign(socket, :player_id, player_id)
      socket = assign(socket, :device_token, params["device"])
      socket = assign(socket, :app_version, params["app_version"])
      socket = assign(socket, :build_number, params["build_number"])
      {:ok, socket}
    end
  end

  # Socket id's are topics that allow you to identify all sockets for a given user:
  #
  #     def id(socket), do: "user_socket:#{socket.assigns.user_id}"
  #
  # Would allow you to broadcast a "disconnect" event and terminate
  # all active sockets and channels for a given user:
  #
  #     Level10Web.Endpoint.broadcast("user_socket:#{user.id}", "disconnect", %{})
  #
  # Returning `nil` makes this socket anonymous.
  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.player_id}"

  # Private

  @spec validate_token(Phoenix.Socket.t(), String.t()) ::
          {:ok, String.t()} | {:error, :invalid_token | :token_required}
  defp validate_token(_socket, nil), do: {:error, :token_required}

  defp validate_token(socket, token) do
    with {:error, _error} <- Phoenix.Token.verify(socket, "user auth", token) do
      {:error, :invalid_token}
    end
  end
end
