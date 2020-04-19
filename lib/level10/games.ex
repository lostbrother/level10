defmodule Level10.Games do
  @moduledoc """
  This context module handles all of the work around running games. Most of the
  functions will take in a game struct and manipulate that struct and return
  it.
  """
  alias Level10.Games.{Game, GameRegistry, GameSupervisor, Player}

  @typep event_type :: atom()
  @typep game_name :: Agent.name()

  @max_attempts 10
  @max_players 6

  @spec create_game(String.t()) :: {:ok, Game.join_code(), Player.id()} | :error
  def create_game(player_name) do
    player = Player.new(player_name)
    do_create_game(player, @max_attempts)
  end

  @spec do_create_game(Player.t(), non_neg_integer()) ::
          {:ok, Game.join_code(), Player.id()} | :error
  defp do_create_game(player, attempts_remaining)

  defp do_create_game(_player, 0) do
    :error
  end

  defp do_create_game(player, attempts_remaining) do
    join_code = Game.generate_join_code()

    game = %{
      id: join_code,
      start: {Agent, :start_link, [Game, :new, [join_code, player], [name: via(join_code)]]},
      restart: :temporary
    }

    case DynamicSupervisor.start_child(GameSupervisor, game) do
      {:ok, _pid} ->
        {:ok, join_code, player.id}

      {:error, {:already_started, _pid}} ->
        do_create_game(player, attempts_remaining - 1)
    end
  end

  @spec exists?(Game.join_code()) :: boolean()
  def exists?(join_code) do
    case Registry.lookup(GameRegistry, join_code) do
      [] -> false
      _ -> true
    end
  end

  @spec via(Game.join_code()) :: game_name()
  defp via(join_code) do
    {:via, Registry, {GameRegistry, join_code}}
  end

  @doc """
  Get the hand of the specified player.

  ## Examples

      iex> get_hand_for_player("ABCD", "557489d0-1ef2-4763-9b0b-d2ea3c80fd99")
      [%Card{color: :green, value: :twelve}, %Card{color: :blue, value: :nine}, ...]
  """
  @spec get_hand_for_player(Game.join_code(), Player.id()) :: list(Card.t())
  def get_hand_for_player(join_code, player_id) do
    Agent.get(via(join_code), & &1.hands[player_id])
  end

  @doc """
  Get the scores for all players in a game.

  ## Examples

      iex> get_scores("ABCD")
      %{
        "e486056e-4a01-4239-9f00-6f7f57ca8d54" => {3, 55},
        "38379e46-4d29-4a22-a245-aa7013ec3c33" => {2, 120}
      }
  """
  @spec get_scores(Game.join_code()) :: Game.scores()
  def get_scores(join_code) do
    Agent.get(via(join_code), & &1.scoring)
  end

  @spec get_players(Game.join_code()) :: list(Player.t())
  def get_players(join_code) do
    Agent.get(via(join_code), & &1.players)
  end

  @doc """
  Get the top card from the discard pile.

  ## Examples

      iex> get_top_discarded_card("ABCD")
      %Card{color: :green, value: :twelve}
  """
  @spec get_top_discarded_card(Game.join_code()) :: Card.t() | nil
  def get_top_discarded_card(join_code) do
    Agent.get(via(join_code), fn game ->
      case game.discard_pile do
        [] -> nil
        [top_card | _] -> top_card
      end
    end)
  end

  @doc """
  Attempts to join a game. Will return an ok tuple with the player ID for the
  new player if joining is successful, or an atom with a reason if not.

  ## Examples

      iex> join_game("ABCD", "Player One")
      {:ok, "9bbfeacb-a006-4646-8776-83cca0ad03eb"}

      iex> join_game("ABCD", "Player One")
      :already_started

      iex> join_game("ABCD", "Player One")
      :full

      iex> join_game("ABCD", "Player One")
      :not_found
  """
  @spec join_game(Game.join_code(), String.t()) ::
          {:ok, Player.id()} | :already_started | :full | :not_found
  def join_game(join_code, player_name) do
    player = Player.new(player_name)

    if exists?(join_code) do
      Agent.get_and_update(via(join_code), fn game ->
        with {:ok, updated_game} <- Game.put_player(game, player),
             true <- length(updated_game.players) <= @max_players do
          broadcast(game.join_code, :players_updated, updated_game.players)
          {{:ok, player.id}, updated_game}
        else
          :already_started ->
            {:already_started, game}

          _ ->
            {:full, game}
        end
      end)
    else
      :not_found
    end
  end

  @spec leave_game(Game.join_code(), Player.id()) :: :ok | :already_started
  def leave_game(join_code, player_id) do
    Agent.get_and_update(via(join_code), fn game ->
      case Game.delete_player(game, player_id) do
        {:ok, game} ->
          broadcast(game.join_code, :players_updated, game.players)
          {:ok, game}

        :already_started ->
          {:already_started, game}
      end
    end)
  end

  @spec player_exists?(Game.join_code(), Player.id()) :: boolean()
  def player_exists?(join_code, player_id) do
    Agent.get(via(join_code), fn game ->
      Enum.any?(game.players, fn player -> player.id == player_id end)
    end)
  end

  @spec start_round(Game.join_code()) :: :ok | :game_over
  def start_round(join_code) do
    Agent.get_and_update(via(join_code), fn game ->
      case Game.start_round(game) do
        {:ok, game} ->
          {:ok, game}

        :game_over ->
          {:game_over, game}
      end
    end)
  end

  @spec start_game(Game.join_code()) :: :ok | :single_player
  def start_game(join_code) do
    Agent.get_and_update(via(join_code), fn game ->
      case Game.start_game(game) do
        {:ok, game} ->
          broadcast(game.join_code, :game_started, nil)
          {:ok, game}

        :single_player ->
          {:single_player, game}
      end
    end)
  end

  @doc """
  Check whether or not a game has started.

  ## Examples

      iex> started?("ABCD")
      true

      iex> started?("EFGH")
      false
  """
  @spec started?(Game.join_code()) :: boolean()
  def started?(join_code) do
    Agent.get(via(join_code), fn game ->
      game.current_stage != :lobby
    end)
  end

  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(game_code) do
    Phoenix.PubSub.subscribe(Level10.PubSub, "game:" <> game_code)
  end

  @spec unsubscribe(String.t()) :: :ok | {:error, term()}
  def unsubscribe(game_code) do
    Phoenix.PubSub.unsubscribe(Level10.PubSub, "game:" <> game_code)
  end

  @spec broadcast(Game.join_code(), event_type(), term()) :: :ok | {:error, term()}
  defp broadcast(join_code, event_type, event) do
    Phoenix.PubSub.broadcast(Level10.PubSub, "game:" <> join_code, {event_type, event})
  end
end
