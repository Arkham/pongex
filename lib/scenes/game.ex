defmodule Pongex.Scene.Game do
  use Scenic.Scene
  require Logger
  alias Scenic.Graph
  alias Scenic.ViewPort
  import Scenic.Primitives, only: [{:rect, 3}, {:update_opts, 2}]

  @text_size 24
  @tile_size 8
  @ball_size @tile_size
  @padding @tile_size * 2
  @animate_ms trunc(1000 / 60)
  @initial_graph Graph.build(font: :roboto, font_size: @text_size)
                 |> rect({@ball_size, @ball_size}, fill: :white, id: :ball)
                 |> rect({@tile_size, @tile_size * 5},
                   fill: :white,
                   id: :left_paddle
                 )
                 |> rect({@tile_size, @tile_size * 5},
                   fill: :white,
                   id: :right_paddle
                 )

  def init(_, opts) do
    {:ok, %ViewPort.Status{size: {vp_width, vp_height}}} =
      ViewPort.info(opts[:viewport])

    vp_center = {
      vp_width / 2 - @ball_size / 2,
      vp_height / 2 - @ball_size / 2
    }

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

    {:ok, timer} = :timer.send_interval(@animate_ms, :animate)

    state = %{
      vp_width: vp_width,
      vp_height: vp_height,
      timer: timer,
      graph: graph,
      vel: {1, 0},
      vel_factor: 4
    }

    {:ok, state, push: graph}
  end

  def handle_info(:animate, state) do
    {x, y} = Graph.get!(state.graph, :ball).transforms.translate
    {vel_x, vel_y} = state.vel

    {new_x, new_y} =
      {x + state.vel_factor * vel_x, y + state.vel_factor * vel_y}

    new_vel_x =
      if new_x < 0 || new_x + @ball_size > state.vp_width do
        -vel_x
      else
        vel_x
      end

    new_vel_y =
      if new_y < 0 || new_y + @ball_size > state.vp_height do
        -vel_y
      else
        vel_y
      end

    new_graph =
      state.graph
      |> Graph.modify(
        :ball,
        &update_opts(&1, translate: {new_x, new_y})
      )

    {:noreply, %{state | graph: new_graph, vel: {new_vel_x, new_vel_y}},
     push: new_graph}
  end

  def handle_input(event, _context, state) do
    Logger.info("Received event: #{inspect(event)}")
    {:noreply, state}
  end
end
