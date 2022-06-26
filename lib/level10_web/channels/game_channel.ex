defmodule Level10Web.GameChannel do
  @moduledoc false
  use Level10Web, :channel
  alias Level10.Games
  alias Level10.Games.Card
  alias Level10.Games.Game
  alias Level10.Games.Settings
  require Logger

  def join("game:lobby", _params, socket) do
    {:ok, socket}
  end

  def join("game:" <> join_code, params, socket) do
    user_id = socket.assigns.user_id

    case Games.connect(join_code, user_id) do
      :ok ->
        send(self(), :after_join)
        {:ok, assign(socket, :join_code, join_code)}

      :game_not_found ->
        {:error, %{reason: "Game not found"}}

      :player_not_found ->
        user = %{id: user_id, name: Map.get(params, "displayName", "")}

        case Games.join_game(join_code, user) do
          :ok ->
            Logger.info(["Joined game ", join_code])
            send(self(), :after_join)
            {:ok, assign(socket, :join_code, join_code)}

          :already_started ->
            {:error, %{reason: "Game has already started"}}

          :full ->
            {:error, %{reason: "Game is full"}}

          :not_found ->
            {:error, "Game not found"}
        end
    end
  end

  # Handle incoming messages from the websocket

  def handle_in("add_to_table", params, socket) do
    %{join_code: join_code, user_id: user_id} = socket.assigns

    with %{"cards" => cards, "player_id" => table_id, "position" => position} <- params,
         cards <- Enum.map(cards, &Card.from_json/1),
         :ok <- Games.add_to_table(join_code, user_id, table_id, position, cards) do
      {:reply, :ok, socket}
    else
      :invalid_group -> {:reply, {:error, :invalid_group}, socket}
      :level_incomplete -> {:reply, {:error, :level_incomplete}, socket}
      :needs_to_draw -> {:reply, {:error, :needs_to_draw}, socket}
      :not_your_turn -> {:reply, {:error, :not_your_turn}, socket}
      _ -> {:reply, {:error, :bad_request}, socket}
    end
  end

  def handle_in("create_game", params, socket) do
    user = %{id: socket.assigns.user_id, name: Map.get(params, "displayName", "")}
    settings = %Settings{skip_next_player: Map.get(params, "skipNextPlayer", false)}

    case Games.create_game(user, settings) do
      {:ok, join_code} ->
        {:reply, {:ok, %{"joinCode" => join_code}}, socket}

      :error ->
        {:reply, {:error, "Failed to create game"}, socket}
    end
  end

  def handle_in("discard", params = %{"card" => card}, socket) do
    %{join_code: join_code, user_id: user_id} = socket.assigns

    with %Card{} = card <- Card.from_json(card),
         :ok <- discard(card, socket.assigns, params) do
      hand = Games.get_hand_for_player(join_code, user_id)
      {:reply, {:ok, %{hand: hand}}, socket}
    else
      nil ->
        {:reply, {:error, :no_card}, socket}

      {:already_skipped, _player} ->
        {:reply, {:error, :already_skipped}, socket}

      :not_your_turn ->
        {:reply, {:error, :not_your_turn}, socket}

      :need_to_draw ->
        {:reply, {:error, :need_to_draw}, socket}
    end
  end

  def handle_in("draw_card", %{"source" => source}, socket) do
    %{join_code: join_code, user_id: user_id} = socket.assigns
    source = atomic_source(source)

    case Games.draw_card(join_code, user_id, source) do
      %Card{} = new_card ->
        {:reply, {:ok, %{card: new_card}}, socket}

      error ->
        {:reply, {:error, error}, socket}
    end
  end

  def handle_in("leave_game", _params, socket) do
    %{join_code: join_code, user_id: user_id} = socket.assigns

    case Games.delete_player(join_code, user_id) do
      :ok ->
        Logger.info(["Left game ", join_code])
        {:stop, :normal, socket}

      :already_started ->
        {:reply, {:error, "Game has already started"}, socket}
    end
  end

  def handle_in("mark_ready", _params, socket) do
    %{join_code: join_code, user_id: user_id} = socket.assigns
    Games.mark_player_ready(join_code, user_id)
    {:noreply, socket}
  end

  def handle_in("start_game", _params, socket) do
    %{is_creator: is_creator, join_code: join_code} = socket.assigns

    if is_creator do
      Logger.info("Starting game #{join_code}")
      Games.start_game(join_code)
    else
      Logger.warn("Non-creator tried to start game #{join_code}")
    end

    {:noreply, socket}
  end

  def handle_in("table_cards", %{"table" => table}, socket) do
    %{join_code: join_code, user_id: user_id} = socket.assigns

    table =
      table
      |> Enum.with_index(fn group, index -> {index, Enum.map(group, &Card.from_json/1)} end)
      |> Enum.into(%{})

    case Games.table_cards(join_code, user_id, table) do
      :ok ->
        {:reply, :ok, socket}

      :invalid_level ->
        {:reply, {:error, :invalid_level}, socket}

      error ->
        Logger.error("Error tabling cards: #{error}")
        {:reply, {:error, :bad_request}, socket}
    end
  end

  # Handle incoming messages from PubSub and other things

  def handle_info(:after_join, socket) do
    %{join_code: join_code, user_id: user_id} = socket.assigns
    Games.subscribe(socket, user_id)
    game = Games.get(join_code)

    presence = Games.list_presence(join_code)
    push(socket, "presence_state", presence)

    is_creator = Games.creator(join_code).id == user_id

    skip_next_player = game.settings.skip_next_player || Game.remaining_player_count(game) < 3

    case game.current_stage do
      :lobby ->
        push(socket, "players_updated", %{players: game.players})

      :play ->
        current_player_id = game.current_player.id
        has_drawn = current_player_id == user_id && game.current_turn_drawn?

        state = %{
          current_player: current_player_id,
          discard_top: List.first(game.discard_pile),
          game_over: false,
          hand: game.hands[user_id],
          hand_counts: Game.hand_counts(game),
          has_drawn: has_drawn,
          levels: Games.format_levels(game.levels),
          players: game.players,
          round_number: game.current_round,
          scores: Games.format_scores(game.scoring),
          skip_next_player: skip_next_player,
          table: Games.format_table(game.table)
        }

        push(socket, "latest_state", state)

      :score ->
        {winner_id, _} = Enum.find(game.hands, fn {_, hand} -> hand == [] end)
        winner = Enum.find(game.players, &(&1.id == winner_id))

        state = %{
          current_player: game.current_player.id,
          discard_top: List.first(game.discard_pile),
          game_over: false,
          hand: game.hands[user_id],
          hand_counts: Game.hand_counts(game),
          has_drawn: false,
          levels: Games.format_levels(game.levels),
          players: game.players,
          players_ready: game.players_ready,
          round_number: game.current_round,
          round_winner: winner,
          scores: Games.format_scores(game.scoring),
          skip_next_player: skip_next_player,
          table: Games.format_table(game.table)
        }

        push(socket, "latest_state", state)

      :finish ->
        {winner_id, _} = Enum.find(game.hands, fn {_, hand} -> hand == [] end)
        winner = Enum.find(game.players, &(&1.id == winner_id))

        state = %{
          current_player: game.current_player.id,
          discard_top: List.first(game.discard_pile),
          game_over: true,
          hand: game.hands[user_id],
          hand_counts: Game.hand_counts(game),
          has_drawn: false,
          levels: Games.format_levels(game.levels),
          players: game.players,
          players_ready: game.players_ready,
          round_number: game.current_round,
          round_winner: winner,
          scores: Games.format_scores(game.scoring),
          skip_next_player: skip_next_player,
          table: Games.format_table(game.table)
        }

        push(socket, "latest_state", state)

      other ->
        Logger.warn("After-join hasn't been implemented for stage #{other}")
    end

    assigns = %{is_creator: is_creator, players: game.players, skip_next_player: skip_next_player}
    {:noreply, assign(socket, assigns)}
  end

  def handle_info({:game_finished, winner}, socket) do
    game = Games.get(socket.assigns.join_code)
    scores = Games.format_scores(game.scoring)
    push(socket, "game_finished", %{round_winner: winner, scores: scores})
    {:noreply, socket}
  end

  def handle_info({:game_started, _}, socket) do
    %{join_code: join_code, user_id: user_id} = socket.assigns
    game = Games.get(join_code)

    state = %{
      current_player: game.current_player.id,
      discard_top: List.first(game.discard_pile),
      hand: game.hands[user_id],
      levels: Games.format_levels(game.levels),
      players: game.players
    }

    push(socket, "game_started", state)
    {:noreply, socket}
  end

  def handle_info({:hand_counts_updated, hand_counts}, socket) do
    push(socket, "hand_counts_updated", %{hand_counts: hand_counts})
    {:noreply, socket}
  end

  def handle_info({:new_discard_top, card}, socket) do
    push(socket, "new_discard_top", %{discard_top: card})
    {:noreply, socket}
  end

  def handle_info({:new_turn, player}, socket) do
    push(socket, "new_turn", %{player: player.id})
    {:noreply, socket}
  end

  def handle_info({:players_ready, players_ready}, socket) do
    push(socket, "players_ready", %{players: players_ready})
    {:noreply, socket}
  end

  def handle_info({:players_updated, players}, socket) do
    push(socket, "players_updated", %{players: players})
    {:noreply, socket}
  end

  def handle_info({:round_finished, winner}, socket) do
    game = Games.get(socket.assigns.join_code)
    scores = Games.format_scores(game.scoring)
    push(socket, "round_finished", %{scores: scores, winner: winner})
    {:noreply, socket}
  end

  def handle_info({:round_started, _}, socket) do
    %{join_code: join_code, user_id: user_id} = socket.assigns
    game = Games.get(join_code)
    skip_next_player = game.settings.skip_next_player || MapSet.size(game.remaining_players) < 3

    state = %{
      current_player: game.current_player.id,
      discard_top: List.first(game.discard_pile),
      hand: game.hands[user_id],
      hand_counts: Game.hand_counts(game),
      levels: Games.format_levels(game.levels),
      round_number: game.current_round,
      skip_next_player: skip_next_player
    }

    push(socket, "round_started", state)

    assigns = %{skip_next_player: skip_next_player}
    {:noreply, assign(socket, assigns)}
  end

  def handle_info({:skipped_players_updated, skipped_players}, socket) do
    push(socket, "skipped_players_updated", %{skipped_players: skipped_players})
    {:noreply, socket}
  end

  def handle_info({:table_updated, table}, socket) do
    push(socket, "table_updated", %{table: Games.format_table(table)})
    {:noreply, socket}
  end

  def handle_info(message, socket) do
    Logger.warn("Game channel received unrecognized message: #{inspect(message)}")
    {:noreply, socket}
  end

  # Private

  @spec atomic_source(String.t()) :: :draw_pile | :discard_pile
  defp atomic_source("draw_pile"), do: :draw_pile
  defp atomic_source("discard_pile"), do: :discard_pile

  @spec discard(Card.t(), map(), map()) ::
          :ok
          | {:already_skipped, Player.t()}
          | :choose_skip_target
          | :not_your_turn
          | :needs_to_draw
  defp discard(%{value: :skip}, assigns, params) do
    %{join_code: join_code, skip_next_player: skip_next, user_id: user_id} = assigns

    cond do
      skip_next ->
        next_player = Games.get_next_player(join_code, user_id)
        Games.skip_player(join_code, user_id, next_player.id)

      params["player_id"] == nil ->
        :choose_skip_target

      params["player_id"] in Games.get_skipped_players(join_code) ->
        players = Games.get_players(join_code)
        player = Enum.find(players, &(&1.id == params["player_id"]))
        {:already_skipped, player}

      true ->
        Games.skip_player(join_code, user_id, params["player_id"])
    end
  end

  defp discard(card, assigns, _) do
    %{join_code: join_code, user_id: user_id} = assigns
    Games.discard_card(join_code, user_id, card)
  end
end