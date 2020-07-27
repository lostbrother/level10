defmodule Level10.Games do
  @moduledoc """
  This context module handles all of the work around running games. Most of the
  functions will take in a game struct and manipulate that struct and return
  it.
  """

  alias Level10.Games.{Card, Game, GameRegistry, GameServer, GameSupervisor, Levels, Player}
  alias Level10.Presence
  require Logger

  @typep event_type :: atom()
  @typep game_name :: {:via, module, term}

  @max_attempts 10

  @doc """
  Add one or more cards to a group that is already on the table
  """
  @spec add_to_table(Game.join_code(), Player.id(), Player.id(), non_neg_integer(), Game.cards()) ::
          :ok | :invalid_group | :level_incomplete | :needs_to_draw | :not_your_turn
  defdelegate add_to_table(join_code, player_id, table_id, position, cards_to_add), to: GameServer

  @doc """
  Get the current count of active games in play.
  """
  @spec count() :: non_neg_integer()
  def count() do
    %{active: count} = Supervisor.count_children(GameSupervisor)
    count
  end

  @doc """
  Create a new game with the player named as its creator.
  """
  @spec create_game(String.t()) :: {:ok, Game.join_code(), Player.id()} | :error
  def create_game(player_name) do
    player = Player.new(player_name)
    do_create_game(player, @max_attempts)
  end

  @doc """
  Returns a Player struct representing the player who created the game.
  """
  @spec creator(Game.join_code()) :: Player.t()
  defdelegate creator(join_code), to: GameServer

  @doc """
  Check to see if the current player has drawn a card yet.

  ## Examples

      iex> current_player_has_drawn?("ABCD")
      true
  """
  @spec current_player_has_drawn?(Game.join_code()) :: boolean()
  defdelegate current_player_has_drawn?(join_code), to: GameServer

  @doc """
  Delete a game.

  ## Examples

      iex> delete_game("ABCD")
      :ok
  """
  @spec delete_game(Game.join_code()) :: :ok
  defdelegate delete_game(join_code), to: GameServer

  @doc """
  Discard a card from the player's hand

  ## Examples

      iex> discard_card("ABCD", "9c34b9fe-3104-44b3-b21b-28140e2e3624", %Card{color: :green, value: :twelve})
      :ok
  """
  @spec discard_card(Game.join_code(), Player.id(), Card.t()) ::
          :ok | :needs_to_draw | :not_your_turn
  defdelegate discard_card(join_code, player_id, card), to: GameServer

  @doc """
  Take the top card from either the draw pile or discard pile and add it to the
  player's hand

  ## Examples

      iex> draw_card("ABCD", "9c34b9fe-3104-44b3-b21b-28140e2e3624", :draw_pile)
      %Card{color: :green, value: :twelve}

      iex> draw_card("ABCD", "9c34b9fe-3104-44b3-b21b-28140e2e3624", :discard_pile)
      %Card{color: :green, value: :twelve}
  """
  @spec draw_card(Game.join_code(), Player.id(), :discard_pile | :draw_pile) ::
          Card.t() | :already_drawn | :empty_discard_pile | :not_your_turn | :skip
  defdelegate draw_card(join_code, player_id, source), to: GameServer

  @doc """
  Returns whether or not a game with the specified join code exists.

  ## Examples

      iex> exists?("ABCD")
      true

      iex> exists?("ASDF")
      false
  """
  @spec exists?(Game.join_code()) :: boolean()
  defdelegate exists?(join_code), to: GameServer

  @spec via(Game.join_code()) :: game_name()
  defp via(join_code) do
    {:via, Horde.Registry, {GameRegistry, join_code}}
  end

  @spec finished?(Game.join_code()) :: boolean()
  defdelegate finished?(join_code), to: GameServer

  @doc """
  Returns the game with the specified join code.

  ## Examples

      iex> get("ABCD")
      %Game{}
  """
  @spec get(Game.join_code()) :: Game.t()
  defdelegate get(join_code), to: GameServer

  @doc """
  Get the player whose turn it currently is.

  ## Examples

      iex> get_current_turn("ABCD")
      %Player{id: "ffe6629a-faff-4053-b7b8-83c3a307400f", name: "Player 1"}
  """
  @spec get_current_turn(Game.join_code()) :: Player.t()
  defdelegate get_current_turn(join_code), to: GameServer

  @doc """
  Get the count of cards in each player's hand.

  ## Examples

      iex> get_hand_counts("ABCD")
      %{"179539f0-661e-4b56-ac67-fec916214223" => 10, "000cc69a-bb7d-4d3e-ae9f-e42e3dcac23e" => 3}
  """
  @spec get_hand_counts(Game.join_code()) :: %{optional(Player.id()) => non_neg_integer()}
  defdelegate get_hand_counts(join_code), to: GameServer

  @doc """
  Get the hand of the specified player.

  ## Examples

      iex> get_hand_for_player("ABCD", "557489d0-1ef2-4763-9b0b-d2ea3c80fd99")
      [%Card{color: :green, value: :twelve}, %Card{color: :blue, value: :nine}, ...]
  """
  @spec get_hand_for_player(Game.join_code(), Player.id()) :: list(Card.t())
  defdelegate get_hand_for_player(join_code, player_id), to: GameServer

  @doc """
  Get the level information for each player in the game.

  ## Examples

      iex> get_levels("ABCD")
      %{
        "04ba446e-0b2a-49f2-8dbf-7d9742548842" => [set: 4, run: 4],
        "86800484-8e73-4408-bd15-98a57871694f" => [run: 7],
      }
  """
  @spec get_levels(Game.join_code()) :: %{optional(Player.t()) => Levels.level()}
  defdelegate get_levels(join_code), to: GameServer

  @doc """
  Get the list of players in a game.

  ## Examples

      iex> get_players("ABCD")
      [
        %Player{id: "601a07a1-b229-47e5-ad13-dbe0599c90e9", name: "Player 1"},
        %Player{id: "a0d2ef3e-e44c-4a58-b90d-a56d88224700", name: "Player 2"}
      ]
  """
  @spec get_players(Game.join_code()) :: list(Player.t())
  defdelegate get_players(join_code), to: GameServer

  @doc """
  Gets the set of IDs of players who are ready for the next round to begin.
  """
  @spec get_players_ready(Game.join_code()) :: MapSet.t(Player.id())
  defdelegate get_players_ready(join_code), to: GameServer

  @spec get_round_number(Game.join_code()) :: non_neg_integer()
  defdelegate get_round_number(join_code), to: GameServer

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
  defdelegate get_scores(join_code), to: GameServer

  @doc """
  Get the table: the cards that have been played to complete levels by each
  player.

  ## Examples

      iex> get_table("ABCD")
      %{
        "12a29ba6-fe6f-4f81-8c89-46ef8aff4b82" => %{
          0 => [
            %Level10.Games.Card{color: :black, value: :wild},
            %Level10.Games.Card{color: :blue, value: :twelve},
            %Level10.Games.Card{color: :red, value: :twelve}
          ],
          1 => [
            %Level10.Games.Card{color: :black, value: :wild},
            %Level10.Games.Card{color: :green, value: :ten},
            %Level10.Games.Card{color: :blue, value: :ten}
          ]
        }
      }
  """
  @spec get_table(Game.join_code()) :: Game.table()
  defdelegate get_table(join_code), to: GameServer

  @doc """
  Get the top card from the discard pile.

  ## Examples

      iex> get_top_discarded_card("ABCD")
      %Card{color: :green, value: :twelve}

      iex> get_top_discarded_card("ABCD")
      nil
  """
  @spec get_top_discarded_card(Game.join_code()) :: Card.t() | nil
  defdelegate get_top_discarded_card(join_code), to: GameServer

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
  defdelegate join_game(join_code, player_name), to: GameServer

  @doc """
  Removes the specified player from the game. This is only allowed if the game
  is still in the lobby stage.

  If the player is currently alone in the game, the game will be deleted as
  well.
  """
  @spec leave_game(Game.join_code(), Player.id()) :: :ok | :already_started | :deleted
  defdelegate leave_game(join_code, player_id), to: GameServer

  @doc """
  Stores in the game state that the specified player is ready to move on to the
  next stage of the game.
  """
  @spec mark_player_ready(Game.join_code(), Player.id()) :: :ok
  defdelegate mark_player_ready(join_code, player_id), to: GameServer

  @doc """
  Returns whether or not the specified player exists within the specified game.
  """
  @spec player_exists?(Game.t() | Game.join_code(), Player.id()) :: boolean()
  defdelegate player_exists?(join_code, player_id), to: GameServer

  @doc """
  Check whether or not the current round has started.

  ## Examples

      iex> round_started?("ABCD")
      true

      iex> round_started?("EFGH")
      false
  """
  @spec round_started?(Game.join_code()) :: boolean()
  defdelegate round_started?(join_code), to: GameServer

  @doc """
  Returns the player struct representing the player who won the current round.
  """
  @spec round_winner(Game.join_code()) :: Player.t() | nil
  defdelegate round_winner(join_code), to: GameServer

  @doc """
  Start the next round.
  """
  @spec start_round(Game.join_code()) :: :ok | :game_over
  defdelegate start_round(join_code), to: GameServer

  @spec start_game(Game.join_code()) :: :ok | :single_player
  def start_game(join_code) do
    GameServer.get_and_update(via(join_code), fn game ->
      case Game.start_game(game) do
        {:ok, game} ->
          Logger.info("Started game #{join_code}")
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
    GameServer.get(via(join_code), fn game ->
      game.current_stage != :lobby
    end)
  end

  @doc """
  Set the given player's table to the given cards.
  """
  @spec table_cards(Game.join_code(), Player.id(), Game.player_table()) ::
          :ok | :already_set | :needs_to_draw | :not_your_turn
  def table_cards(join_code, player_id, player_table) do
    GameServer.get_and_update(via(join_code), fn game ->
      with {:ok, game} <- Game.set_player_table(game, player_id, player_table) do
        broadcast(join_code, :hand_counts_updated, Game.hand_counts(game))
        broadcast(join_code, :table_updated, game.table)

        {:ok, maybe_complete_round(game, player_id)}
      end
    end)
  end

  @spec subscribe(String.t(), Player.id()) :: :ok | {:error, term()}
  def subscribe(game_code, player_id) do
    topic = "game:" <> game_code

    with :ok <- Phoenix.PubSub.subscribe(Level10.PubSub, topic),
         {:ok, _} <- Presence.track_player(game_code, player_id) do
      Presence.track_user(player_id, game_code)
      :ok
    end
  end

  @spec unsubscribe(String.t(), Player.id()) :: :ok | {:error, term()}
  def unsubscribe(game_code, player_id) do
    topic = "game:" <> game_code

    with :ok <- Phoenix.PubSub.unsubscribe(Level10.PubSub, topic) do
      Presence.untrack(self(), topic, player_id)
    end
  end

  @spec update(Game.join_code(), (Game.t() -> Game.t())) :: :ok
  def update(join_code, fun) do
    GameServer.update(via(join_code), fun)
  end

  @spec broadcast(Game.join_code(), event_type(), term()) :: :ok | {:error, term()}
  def broadcast(join_code, event_type, event) do
    Phoenix.PubSub.broadcast(Level10.PubSub, "game:" <> join_code, {event_type, event})
  end

  @spec list_presence(Game.join_code()) :: %{optional(Player.id()) => map()}
  def list_presence(join_code) do
    Presence.list("game:" <> join_code)
  end

  # Private

  @spec broadcast_game_complete(Game.t(), Player.id()) :: :ok | {:error, term()}
  defp broadcast_game_complete(game, player_id) do
    player = Enum.find(game.players, &(&1.id == player_id))
    broadcast(game.join_code, :game_finished, player)
  end

  @spec broadcast_round_complete(Game.t(), Player.id()) :: Game.t()
  defp broadcast_round_complete(game, player_id) do
    player = Enum.find(game.players, &(&1.id == player_id))
    broadcast(game.join_code, :round_finished, player)
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
      start: {GameServer, :start_link, [{join_code, player}, [name: via(join_code)]]},
      restart: :temporary
    }

    case Horde.DynamicSupervisor.start_child(GameSupervisor, game) do
      {:ok, _pid} ->
        Logger.info(["Created game ", join_code])
        {:ok, join_code, player.id}

      {:error, {:already_started, _pid}} ->
        do_create_game(player, attempts_remaining - 1)
    end
  end

  @spec maybe_complete_round(Game.t(), Player.id()) :: Game.t()
  defp maybe_complete_round(game, player_id) do
    with true <- Game.round_finished?(game, player_id),
         %{current_stage: :finish} = game <- Game.complete_round(game) do
      broadcast_game_complete(game, player_id)
      game
    else
      false ->
        game

      game ->
        broadcast_round_complete(game, player_id)
        game
    end
  end
end
