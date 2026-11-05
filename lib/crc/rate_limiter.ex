defmodule CRC.RateLimiter do
  @moduledoc """
  Fixed-window attempt counter for abuse-prone actions such as login.

  Counts live in a local ETS table, so each Fly machine counts on its own and
  a machine that restarts or autostops starts over from zero.
  """

  use GenServer

  @table __MODULE__
  @cleanup_interval :timer.minutes(10)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc """
  Checks and records in one atomic step: `:ok` if allowed, `:error` if over the
  limit. Simultaneous callers can't slip past the limit.
  """
  @spec hit(term(), pos_integer(), pos_integer()) :: :ok | :error
  def hit(key, limit, window_ms) do
    window = window_id(window_ms)

    count =
      :ets.update_counter(
        @table,
        {key, window},
        1,
        {{key, window}, 0, expires_at(window, window_ms)}
      )

    if count <= limit, do: :ok, else: :error
  end

  @doc """
  Gives back one attempt taken with `hit/3`, for when it turns out not to count.
  The count never drops below zero, even if the window changed in between.
  """
  @spec release(term(), pos_integer()) :: :ok
  def release(key, window_ms) do
    window = window_id(window_ms)

    :ets.update_counter(
      @table,
      {key, window},
      {2, -1, 0, 0},
      {{key, window}, 0, expires_at(window, window_ms)}
    )

    :ok
  end

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    schedule_cleanup()
    {:ok, nil}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = System.system_time(:millisecond)
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    schedule_cleanup()
    {:noreply, state}
  end

  defp window_id(window_ms), do: div(System.system_time(:millisecond), window_ms)
  defp expires_at(window, window_ms), do: (window + 1) * window_ms
  defp schedule_cleanup, do: Process.send_after(self(), :cleanup, @cleanup_interval)
end
