defmodule Pongex.Scene.Game do
  use Scenic.Scene
  require Logger
  alias Scenic.Graph
  alias Scenic.ViewPort

  import Scenic.Primitives,
    only: [{:rect, 3}, {:path, 3}, {:group, 3}, {:update_opts, 2}]

  @font Pongex.Font.font()

  @tile_size 8
  @ball_size @tile_size
  @vertical_padding @tile_size
  @horizontal_padding @tile_size * 8
  @paddle_width @tile_size
  @paddle_height @tile_size * 5

  @animate_ms trunc(1000 / 60)
  @animate_paddle_ms trunc(1000 / 120)
  @vel_factor 5
  @paddle_vel_factor 6

  @net_elements Enum.flat_map(0..100, fn x ->
                  if rem(x, 2) == 0 do
                    [{:move_to, 0, x * 10}, {:line_to, 0, (x + 1) * 10}]
                  else
                    []
                  end
                end)

  @initial_graph Graph.build()
                 |> rect({@ball_size, @ball_size}, fill: :white, id: :ball)
                 |> rect({@paddle_width, @paddle_height},
                   fill: :white,
                   id: :left_paddle
                 )
                 |> rect({@paddle_width, @paddle_height},
                   fill: :white,
                   id: :right_paddle
                 )
                 |> path(
                   [:begin] ++ @net_elements ++ [:close_path],
                   stroke: {1, :white},
                   id: :net
                 )

  def init(_, opts) do
    {:ok, %ViewPort.Status{size: {vp_width, vp_height}}} =
      ViewPort.info(opts[:viewport])

    vp_horizontal_center = vp_width / 2 - @ball_size / 2
    vp_vertical_center = vp_height / 2 - @ball_size / 2

    vp_center = {vp_horizontal_center, vp_vertical_center}

    graph =
      @initial_graph
      |> Graph.modify(:ball, &update_opts(&1, translate: vp_center))
      |> Graph.modify(
        :left_paddle,
        &update_opts(&1, translate: {@horizontal_padding, @vertical_padding})
      )
      |> Graph.modify(
        :right_paddle,
        &update_opts(&1,
          translate:
            {vp_width - @horizontal_padding - @tile_size,
             vp_height - @paddle_height - @vertical_padding}
        )
      )
      |> Graph.modify(
        :net,
        &update_opts(&1,
          translate: {vp_horizontal_center, 0}
        )
      )
      |> draw_scores(vp_width, {0, 0})

    {:ok, _} = :timer.send_interval(@animate_ms, :animate)
    {:ok, _} = :timer.send_interval(@animate_paddle_ms, :animate_paddle)

    state = %{
      vp_width: vp_width,
      vp_height: vp_height,
      vp_center: vp_center,
      graph: graph,
      game_state: :waiting,
      pressed_keys: %{},
      score: {0, 0},
      vel: {1, 1},
      vel_factor: @vel_factor
    }

    Process.send_after(self(), :new_ball, 1_000)

    {:ok, state, push: graph}
  end

  def handle_info(
        :animate,
        %{game_state: :playing, score: {left_score, right_score}} = state
      ) do
    {x, y} = Graph.get!(state.graph, :ball).transforms.translate
    {vel_x, vel_y} = state.vel

    {new_x, new_y} = {x + @vel_factor * vel_x, y + @vel_factor * vel_y}

    {new_score, new_state} =
      if new_x + @ball_size < 0 do
        {{left_score, right_score + 1}, :waiting}
      else
        if new_x > state.vp_width do
          {{left_score + 1, right_score}, :waiting}
        else
          {{left_score, right_score}, :playing}
        end
      end

    new_vel_y =
      if new_y < 0 || new_y + @ball_size > state.vp_height do
        -vel_y
      else
        vel_y
      end

    {new_vel_x, new_ball_coords} =
      case {is_colliding(state.graph, :left_paddle),
            is_colliding(state.graph, :right_paddle)} do
        {{true, paddle_x}, _} ->
          {-vel_x, {paddle_x + @paddle_width, new_y}}

        {_, {true, paddle_x}} ->
          {-vel_x, {paddle_x - @paddle_width, new_y}}

        _ ->
          {vel_x, {new_x, new_y}}
      end

    new_graph =
      state.graph
      |> Graph.modify(
        :ball,
        &update_opts(&1, translate: new_ball_coords)
      )

    with_scores =
      if new_state == :waiting do
        Process.send_after(self(), :new_ball, 1_000)
        draw_scores(new_graph, state.vp_width, new_score)
      else
        new_graph
      end

    {:noreply,
     %{
       state
       | graph: with_scores,
         vel: {new_vel_x, new_vel_y},
         score: new_score,
         game_state: new_state
     }, push: with_scores}
  end

  def handle_info(:animate, state) do
    {:noreply, state}
  end

  def handle_info(:animate_paddle, state) do
    new_graph = move_paddles(state)

    {:noreply, %{state | graph: new_graph, pressed_keys: %{}}, push: new_graph}
  end

  def handle_info(:new_ball, state) do
    new_graph =
      state.graph
      |> Graph.modify(
        :ball,
        &update_opts(&1, translate: state.vp_center)
      )

    {:noreply,
     %{
       state
       | graph: new_graph,
         game_state: :playing
     }, push: new_graph}
  end

  def handle_input({:key, {key, :press, _}}, _context, state)
      when key in ["W", "S", "I", "K"] do
    new_pressed_keys = Map.put(state.pressed_keys, key, true)
    {:noreply, %{state | pressed_keys: new_pressed_keys}}
  end

  def handle_input(_event, _context, state) do
    {:noreply, state}
  end

  def move_paddle_up(graph, paddle) do
    {x, y} = Graph.get!(graph, paddle).transforms.translate
    new_y = max(y - @vel_factor * @paddle_vel_factor, 0)

    graph
    |> Graph.modify(
      paddle,
      &update_opts(&1, translate: {x, new_y})
    )
  end

  def move_paddle_down(graph, vp_height, paddle) do
    {x, y} = Graph.get!(graph, paddle).transforms.translate

    new_y =
      min(y + @vel_factor * @paddle_vel_factor, vp_height - @paddle_height)

    graph
    |> Graph.modify(
      paddle,
      &update_opts(&1, translate: {x, new_y})
    )
  end

  def move_paddles(state) do
    [
      {"W", fn acc -> move_paddle_up(acc, :left_paddle) end},
      {"S", fn acc -> move_paddle_down(acc, state.vp_height, :left_paddle) end},
      {"I", fn acc -> move_paddle_up(acc, :right_paddle) end},
      {"K", fn acc -> move_paddle_down(acc, state.vp_height, :right_paddle) end}
    ]
    |> Enum.reduce(state.graph, fn {key, fun}, acc ->
      if Map.has_key?(state.pressed_keys, key) do
        fun.(acc)
      else
        acc
      end
    end)
  end

  def is_colliding(graph, paddle) do
    {ball_x, ball_y} = Graph.get!(graph, :ball).transforms.translate
    {paddle_x, paddle_y} = Graph.get!(graph, paddle).transforms.translate

    collision_detected =
      ball_x < paddle_x + @paddle_width &&
        ball_x + @ball_size > paddle_x &&
        ball_y < paddle_y + @paddle_height &&
        ball_y + @ball_size > paddle_y

    {collision_detected, paddle_x}
  end

  def draw_scores(graph, vp_width, {left_score, right_score}) do
    graph
    |> Graph.delete(:score)
    |> draw_score(left_score, @horizontal_padding + @paddle_width + @tile_size)
    |> draw_score(
      right_score,
      vp_width - @horizontal_padding - @paddle_width - @tile_size * 4
    )
  end

  def draw_score(graph, score, offset) do
    graph
    |> group(
      fn g ->
        Map.get(@font, rem(score, 10))
        |> Enum.with_index()
        |> Enum.reduce(g, fn {row, row_index}, row_acc ->
          row
          |> Enum.with_index()
          |> Enum.reduce(row_acc, fn {cell, col_index}, col_acc ->
            if cell == 1 do
              col_acc
              |> rect({@tile_size, @tile_size},
                fill: :white,
                translate: {col_index * @tile_size, row_index * @tile_size}
              )
            else
              col_acc
            end
          end)
        end)
      end,
      id: :score,
      translate: {offset, @vertical_padding}
    )
  end
end
