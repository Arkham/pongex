defmodule Pongex.Scene.Game do
  use Scenic.Scene
  require Logger
  alias Scenic.Graph
  alias Scenic.ViewPort
  import Scenic.Primitives, only: [{:rect, 3}, {:path, 3}, {:update_opts, 2}]

  @text_size 24
  @tile_size 8
  @ball_size @tile_size
  @padding @tile_size * 2
  @paddle_width @tile_size
  @paddle_height @tile_size * 5
  @animate_ms trunc(1000 / 60)
  @animate_paddle_ms trunc(1000 / 120)
  @vel_factor 5
  @paddle_vel_factor 5

  @net_elements Enum.flat_map(0..100, fn x ->
                  if rem(x, 2) == 0 do
                    [{:move_to, 0, x * 10}, {:line_to, 0, (x + 1) * 10}]
                  else
                    []
                  end
                end)

  @initial_graph Graph.build(font: :roboto, font_size: @text_size)
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
        &update_opts(&1, translate: {@padding * 4, @padding})
      )
      |> Graph.modify(
        :right_paddle,
        &update_opts(&1,
          translate: {vp_width - @padding * 4 - @tile_size, @padding}
        )
      )
      |> Graph.modify(
        :net,
        &update_opts(&1,
          translate: {vp_horizontal_center, 0}
        )
      )

    {:ok, _} = :timer.send_interval(@animate_ms, :animate)
    {:ok, _} = :timer.send_interval(@animate_paddle_ms, :animate_paddle)

    state = %{
      vp_width: vp_width,
      vp_height: vp_height,
      vp_center: vp_center,
      graph: graph,
      game_state: :playing,
      key_pressed: %{},
      score: {0, 0},
      vel: {1, 1},
      vel_factor: @vel_factor
    }

    {:ok, state, push: graph}
  end

  def handle_info(
        :animate,
        %{game_state: :playing, score: {p1_score, p2_score}} = state
      ) do
    {x, y} = Graph.get!(state.graph, :ball).transforms.translate
    {vel_x, vel_y} = state.vel

    {new_x, new_y} =
      {x + state.vel_factor * vel_x, y + state.vel_factor * vel_y}

    {new_score, new_state} =
      if new_x + @ball_size < 0 do
        {{p1_score, p2_score + 1}, :waiting}
      else
        if new_x > state.vp_width do
          {{p1_score + 1, p2_score}, :waiting}
        else
          {{p1_score, p2_score}, :playing}
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

    if new_state == :waiting do
      Process.send_after(self(), :new_ball, 1_000)
    end

    {:noreply,
     %{
       state
       | graph: new_graph,
         vel: {new_vel_x, new_vel_y},
         score: new_score,
         game_state: new_state
     }, push: new_graph}
  end

  def handle_info(:animate, state) do
    {:noreply, state}
  end

  def handle_info(:animate_paddle, state) do
    new_graph = move_paddles(state)

    {:noreply, %{state | graph: new_graph, key_pressed: %{}}, push: new_graph}
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

  def handle_input({:key, {"W", _, _}}, _context, state) do
    new_key_pressed = Map.put(state.key_pressed, "W", true)
    {:noreply, %{state | key_pressed: new_key_pressed}}
  end

  def handle_input({:key, {"S", _, _}}, _context, state) do
    new_key_pressed = Map.put(state.key_pressed, "S", true)
    {:noreply, %{state | key_pressed: new_key_pressed}}
  end

  def handle_input({:key, {"I", _, _}}, _context, state) do
    new_key_pressed = Map.put(state.key_pressed, "I", true)
    {:noreply, %{state | key_pressed: new_key_pressed}}
  end

  def handle_input({:key, {"K", _, _}}, _context, state) do
    new_key_pressed = Map.put(state.key_pressed, "K", true)
    {:noreply, %{state | key_pressed: new_key_pressed}}
  end

  def handle_input(event, _context, state) do
    Logger.info("Received event: #{inspect(event)}")
    {:noreply, state}
  end

  def move_paddle_up(graph, vel, paddle) do
    {x, y} = Graph.get!(graph, paddle).transforms.translate
    new_y = max(y - vel, 0)

    graph
    |> Graph.modify(
      paddle,
      &update_opts(&1, translate: {x, new_y})
    )
  end

  def move_paddle_down(graph, vel, vp_height, paddle) do
    {x, y} = Graph.get!(graph, paddle).transforms.translate
    new_y = min(y + vel, vp_height - @paddle_height)

    graph
    |> Graph.modify(
      paddle,
      &update_opts(&1, translate: {x, new_y})
    )
  end

  def move_paddles(state) do
    result = state.graph
    vel = state.vel_factor * @paddle_vel_factor

    result =
      if Map.has_key?(state.key_pressed, "W") do
        move_paddle_up(result, vel, :left_paddle)
      else
        result
      end

    result =
      if Map.has_key?(state.key_pressed, "S") do
        move_paddle_down(result, vel, state.vp_height, :left_paddle)
      else
        result
      end

    result =
      if Map.has_key?(state.key_pressed, "I") do
        move_paddle_up(result, vel, :right_paddle)
      else
        result
      end

    result =
      if Map.has_key?(state.key_pressed, "K") do
        move_paddle_down(result, vel, state.vp_height, :right_paddle)
      else
        result
      end

    result
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
end
