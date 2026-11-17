defmodule NervesDesktop.MCP do
  @moduledoc """
  Runs an MCP server per device and remembers where each one lives.

  Every device gets its own port, counted up from 13000. The port a device was
  given is written to disk along with whether its server is switched on, so
  quitting and reopening the app brings the same servers back on the same
  ports and an MCP client configured once keeps working.

  Everything a device prints while its server runs, including what an agent
  causes, is appended to a file in the system's temporary directory. It stays
  there until the system clears it out, so a session can be read back later or
  followed with `tail -f` while an agent is at work.
  """

  use GenServer

  require Logger

  alias NervesDesktop.Firmware.Catalog

  @topic "mcp"
  @ports 13_000..13_099
  @log_limit 5_000_000

  @type server :: %{
          id: binary(),
          port: :inet.port_number(),
          url: binary(),
          connection: keyword(),
          log: binary() | nil
        }

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  The PubSub topic that receives `{:mcp_changed, servers}`.
  """
  def topic, do: @topic

  @doc """
  Starts the MCP server for a device, on the port it had before if there was one.
  """
  @spec start_server(GenServer.server(), map()) :: {:ok, server()} | {:error, term()}
  def start_server(mcp \\ __MODULE__, device), do: GenServer.call(mcp, {:start, device}, 15_000)

  @doc """
  Stops a device's MCP server. Its port stays reserved for next time.
  """
  @spec stop_server(GenServer.server(), binary()) :: :ok
  def stop_server(mcp \\ __MODULE__, target), do: GenServer.call(mcp, {:stop, target})

  @doc """
  The running servers, keyed by device target.
  """
  @spec servers(GenServer.server()) :: %{binary() => server()}
  def servers(mcp \\ __MODULE__), do: GenServer.call(mcp, :servers)

  @doc """
  The name a device's server goes by in an MCP client: its hostname, or the
  serial port's name, reduced to what client CLIs accept.
  """
  @spec client_name(map()) :: binary()
  def client_name(device) do
    (device[:hostname] || device[:target] || "nerves")
    |> Path.basename()
    |> String.replace_suffix(".local", "")
    |> String.replace(~r/[^A-Za-z0-9_-]+/, "-")
    |> String.trim("-")
  end

  @doc """
  The shell command that adds a server to an agent.
  """
  @spec add_command(:claude_code | :codex, binary(), binary()) :: binary()
  def add_command(:claude_code, name, url), do: "claude mcp add --transport http #{name} #{url}"
  def add_command(:codex, name, url), do: "codex mcp add #{name} --url #{url}"

  @doc """
  The PubSub topic that receives `{:mcp_log, target}` each time something was
  added to a device's log.
  """
  def log_topic(target), do: "mcp_log:#{target}"

  @doc false
  def record(target, log, data) do
    File.write!(log, data, [:append])
    Phoenix.PubSub.broadcast(NervesDesktop.PubSub, log_topic(target), {:mcp_log, target})
  end

  @doc """
  The file holding what a device's server has seen, if there is one yet.
  """
  @spec log_path(binary(), binary() | nil) :: binary() | nil
  def log_path(target, dir \\ log_dir()) do
    path = log_file(target, dir)
    if path && File.exists?(path), do: path
  end

  defp log_dir do
    Application.get_env(:nerves_desktop, __MODULE__, [])
    |> Keyword.get(:log_dir, default_log_dir())
  end

  defp default_log_dir, do: Path.join([System.tmp_dir!(), "nerves_desktop", "mcp"])

  defp log_file(_target, nil), do: nil
  defp log_file(target, dir), do: Path.join(dir, client_name(%{target: target}) <> ".log")

  @doc """
  Where the port assignments are kept unless configured otherwise.
  """
  def default_path do
    Path.join(:filename.basedir(:user_data, ~c"NervesDesktop"), "mcp.json")
  end

  @impl true
  def init(opts) do
    path = Keyword.get(opts, :path, default_path())
    saved = load(path)

    state = %{
      path: path,
      range: Keyword.get(opts, :ports, @ports),
      log_dir: Keyword.get(opts, :log_dir, default_log_dir()),
      ports: saved.ports,
      enabled: saved.enabled
    }

    {:ok, state, {:continue, :restore}}
  end

  @impl true
  def handle_continue(:restore, state) do
    restored =
      Enum.reduce(Map.values(state.enabled), state, fn entry, state ->
        case launch(entry, state) do
          {:ok, server} ->
            put_in(state.ports[entry.target], server.port)

          {:error, reason} ->
            Logger.warning("Could not restore MCP server for #{entry.target}: #{inspect(reason)}")
            state
        end
      end)

    if restored.ports != state.ports, do: save(restored)
    {:noreply, restored}
  end

  @impl true
  def handle_call({:start, device}, _from, state) do
    entry = entry(device)

    case launch(entry, state) do
      {:ok, server} ->
        state = %{
          state
          | ports: Map.put(state.ports, entry.target, server.port),
            enabled: Map.put(state.enabled, entry.target, entry)
        }

        save(state)
        broadcast(state)
        {:reply, {:ok, server}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:stop, target}, _from, state) do
    NervesMCP.stop_server(target)
    state = %{state | enabled: Map.delete(state.enabled, target)}

    save(state)
    broadcast(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:servers, _from, state), do: {:reply, running(state), state}

  defp running(state) do
    for target <- Map.keys(state.enabled), server = NervesMCP.server(target), into: %{} do
      {target, with_log(server, state)}
    end
  end

  defp launch(entry, state) do
    log = log_file(entry.target, state.log_dir)

    opts =
      [connection: connection(entry), port: candidates(entry.target, state), ip: :loopback] ++
        if(log, do: [on_output: &record(entry.target, log, &1)], else: [])

    if NervesMCP.server(entry.target) == nil, do: prepare(log)

    case NervesMCP.start_server(entry.target, opts) do
      {:ok, server} -> {:ok, with_log(server, state)}
      {:error, :already_started} -> {:ok, with_log(NervesMCP.server(entry.target), state)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp with_log(server, state), do: Map.put(server, :log, log_file(server.id, state.log_dir))

  defp prepare(nil), do: :ok

  defp prepare(log) do
    with {:ok, %{size: size}} when size > @log_limit <- File.stat(log), do: File.rm(log)

    with :ok <- File.mkdir_p(Path.dirname(log)), :ok <- File.write(log, "", [:append]) do
      :ok
    else
      {:error, reason} -> Logger.warning("Could not prepare MCP log #{log}: #{inspect(reason)}")
    end
  end

  # A device's own port comes first. Ports promised to other devices come last,
  # so a device that is switched off still finds its port free when it returns.
  defp candidates(target, state) do
    promised = state.ports |> Map.delete(target) |> Map.values()
    {taken, free} = Enum.split_with(state.range, &(&1 in promised))

    List.wrap(state.ports[target]) ++ free ++ taken
  end

  defp entry(device) do
    %{
      target: device[:target],
      type: if(device[:type] == :uart, do: :uart, else: :network),
      product: device[:product]
    }
  end

  defp connection(%{type: :uart, target: target}), do: [type: :uart, port: target]

  defp connection(%{target: target} = entry) do
    [type: :ssh, host: target, user: "root"] ++ password(entry)
  end

  # nerves_mcp hands passwords to sshpass, so without it only key logins work.
  defp password(entry) do
    case Catalog.password_for(entry) do
      password when is_binary(password) ->
        if System.find_executable("sshpass"), do: [pass: password], else: []

      nil ->
        []
    end
  end

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(NervesDesktop.PubSub, @topic, {:mcp_changed, running(state)})
  end

  defp load(nil), do: %{ports: %{}, enabled: %{}}

  defp load(path) do
    with {:ok, json} <- File.read(path),
         {:ok, %{"ports" => ports, "enabled" => enabled}} <- Jason.decode(json) do
      %{ports: ports, enabled: Map.new(enabled, &{&1["target"], decode_entry(&1)})}
    else
      _ -> load(nil)
    end
  end

  defp decode_entry(entry) do
    %{
      target: entry["target"],
      type: if(entry["type"] == "uart", do: :uart, else: :network),
      product: entry["product"]
    }
  end

  defp save(%{path: nil}), do: :ok

  defp save(state) do
    json = Jason.encode!(%{ports: state.ports, enabled: Map.values(state.enabled)}, pretty: true)
    tmp = state.path <> ".tmp"

    with :ok <- File.mkdir_p(Path.dirname(state.path)),
         :ok <- File.write(tmp, json),
         :ok <- File.rename(tmp, state.path) do
      :ok
    else
      {:error, reason} ->
        Logger.warning("Could not save MCP ports to #{state.path}: #{inspect(reason)}")
    end
  end
end
