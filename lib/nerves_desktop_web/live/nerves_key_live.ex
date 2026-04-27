defmodule NervesDesktopWeb.NervesKeyLive do
  use NervesDesktopWeb, :live_view
  require Logger

  alias NervesDesktop.SSHConnection
  alias NervesDesktop.NervesKey, as: KeyHelper

  @extraction_timeout 20_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(NervesDesktop.PubSub, "discovery")
      Phoenix.PubSub.subscribe(NervesDesktop.PubSub, "ssh_connection")
    end

    {:ok, pid} = SSHConnection.start_link([])

    {:ok,
     socket
     |> assign(devices: NervesDesktop.DeviceScanner.get_devices())     |> assign(ssh_pid: pid)
     |> assign(status: :disconnected)
     |> assign(selected_ip: nil)
     |> assign(selected_name: nil)
     |> assign(password: "")
     |> assign(key_info: nil)
     |> assign(extracting: false)
     |> assign(provisioning: false)
     |> assign(buffer: "")
     |> assign_workflow_form(%{
       "signer_cert" => "",
       "signer_key" => "",
       "device_serial" => "",
       "device_board_name" => "NervesKey"
     })}
  end

  @impl true
  def handle_params(params, _url, socket) do
    ip = params["ip"]
    name = params["name"]

    socket =
      if ip do
        socket
        |> assign(selected_ip: ip)
        |> assign(selected_name: name)
        |> then(fn s ->
          if connected?(s) do
            # Auto connect
            handle_event("connect", %{}, s) |> elem(1)
          else
            s
          end
        end)
      else
        socket
      end

    {:noreply, socket}
  end

  defp assign_workflow_form(socket, params) do
    assign(socket, :workflow_form, to_form(params, as: "workflow"))
  end

  @impl true
  def handle_info({:devices_updated, devices}, socket) do
    {:noreply, assign(socket, devices: devices)}
  end

  def handle_info({:ssh_output, device_ip, data}, socket) do
    if socket.assigns.selected_ip == device_ip do
      if socket.assigns.extracting or socket.assigns.provisioning do
        new_buffer = socket.assigns.buffer <> data
        parse_ssh_buffer(socket, new_buffer)
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({:ssh_closed, device_ip}, socket) do
    if socket.assigns.selected_ip == device_ip do
      {:noreply,
       socket
       |> assign(status: :disconnected, extracting: false, provisioning: false, buffer: "")
       |> put_flash(:error, "SSH connection closed unexpectedly.")}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:extract_info, socket) do
    ip = socket.assigns.selected_ip
    Logger.info("[NervesKey] Sending extraction command to #{ip}")

    cmd =
      "try do has_lib = Code.ensure_loaded?(NervesKey) and Code.ensure_loaded?(ATECC508A.Transport.I2C); if has_lib do case ATECC508A.Transport.I2C.init([]) do {:ok, i2c} -> info = %{provisioned: NervesKey.provisioned?(i2c), manufacturer_sn: NervesKey.manufacturer_sn(i2c), board_name: \"NervesKey\"}; IO.puts(\"NERVES_KEY_RESULT: \" <> Jason.encode!(info)); _ -> IO.puts(\"NERVES_KEY_RESULT: \" <> Jason.encode!(%{error: \"no_chip\"})) end else IO.puts(\"NERVES_KEY_RESULT: \" <> Jason.encode!(%{error: \"no_library\"})) end rescue _ -> IO.puts(\"NERVES_KEY_RESULT: \" <> Jason.encode!(%{error: \"unknown\"})) end"

    SSHConnection.send_data(socket.assigns.ssh_pid, "\r\n\r\n" <> cmd <> "\r\n")
    Process.send_after(self(), :extraction_timeout, @extraction_timeout)
    {:noreply, assign(socket, buffer: "")}
  end

  def handle_info(:extraction_timeout, socket) do
    if socket.assigns.extracting or socket.assigns.provisioning do
      ip = socket.assigns.selected_ip
      Logger.error("[NervesKey] Timeout waiting for device response from #{ip}")

      {:noreply,
       socket
       |> assign(extracting: false, provisioning: false, buffer: "")
       |> put_flash(:error, "Timeout: Device did not respond. Check password or Console page.")}
    else
      {:noreply, socket}
    end
  end

  defp parse_ssh_buffer(socket, buffer) do
    cond do
      Regex.match?(~r/NERVES_KEY_RESULT: (\{.*?\})/s, buffer) ->
        [_, json_str] = Regex.run(~r/NERVES_KEY_RESULT: (\{.*?\})/s, buffer)

        case Jason.decode(json_str) do
          {:ok, info} ->
            {:noreply, assign(socket, key_info: info, extracting: false, buffer: "")}

          _ ->
            {:noreply, assign(socket, buffer: buffer)}
        end

      Regex.match?(~r/PROVISION_RESULT: (\{.*?\})/s, buffer) ->
        [_, json_str] = Regex.run(~r/PROVISION_RESULT: (\{.*?\})/s, buffer)

        case Jason.decode(json_str) do
          {:ok, %{"status" => "ok"}} ->
            send(self(), :extract_info)

            {:noreply,
             socket
             |> assign(provisioning: false, buffer: "")
             |> put_flash(:info, "NervesKey provisioned successfully!")}

          {:ok, %{"error" => reason}} ->
            {:noreply,
             socket
             |> assign(provisioning: false, buffer: "")
             |> put_flash(:error, "Provisioning failed: #{reason}")}

          _ ->
            {:noreply, assign(socket, buffer: buffer)}
        end

      true ->
        {:noreply, assign(socket, buffer: buffer)}
    end
  end

  @impl true
  def handle_event(
        "validate_connection",
        %{"connection" => %{"ip" => ip, "password" => password}},
        socket
      ) do
    device = Enum.find(socket.assigns.devices, &(&1.ip == ip))

    {:noreply,
     socket
     |> assign(selected_ip: ip)
     |> assign(password: password)
     |> assign(selected_name: device && (device.name || device.hostname))}
  end

  def handle_event("connect", _params, socket) do
    ip = socket.assigns.selected_ip
    password = socket.assigns.password

    if ip in [nil, ""] do
      {:noreply, put_flash(socket, :error, "Please select a device first.")}
    else
      Logger.info("[NervesKey] Connecting to #{ip}...")

      SSHConnection.connect(
        socket.assigns.ssh_pid,
        ip,
        "root",
        if(password == "", do: nil, else: password)
      )

      Process.send_after(self(), :extract_info, 4000)
      {:noreply, assign(socket, status: :connected, extracting: true, key_info: nil, buffer: "")}
    end
  end

  def handle_event("disconnect", _params, socket) do
    Logger.info("[NervesKey] Disconnecting from #{socket.assigns.selected_ip}")
    SSHConnection.disconnect(socket.assigns.ssh_pid)

    {:noreply,
     socket
     |> assign(
       status: :disconnected,
       key_info: nil,
       extracting: false,
       provisioning: false,
       buffer: ""
     )
     |> push_event("print", %{data: "\r\n\x1B[1;31mSession disconnected.\x1B[0m\r\n"})}
  end

  def handle_event("generate_ca", _params, socket) do
    {:ok, {cert, key}} = KeyHelper.generate_ca()

    new_params =
      socket.assigns.workflow_form.params
      |> Map.put("signer_cert", cert)
      |> Map.put("signer_key", key)

    {:noreply, assign_workflow_form(socket, new_params)}
  end

  def handle_event("validate_provisioning", %{"workflow" => workflow_params}, socket) do
    {:noreply, assign_workflow_form(socket, workflow_params)}
  end

  def handle_event("commit_provisioning", _params, socket) do
    params = socket.assigns.workflow_form.params
    ip = socket.assigns.selected_ip

    Logger.info("[NervesKey] Committing provisioning to #{ip}")

    cert_escaped = String.replace(params["signer_cert"], "\"", "\\\"")
    key_escaped = String.replace(params["signer_key"], "\"", "\\\"")
    serial = params["device_serial"]
    board = params["device_board_name"]

    cmd = """
    (fn ->
      try do
        {:ok, i2c} = ATECC508A.Transport.I2C.init([])
        signer_cert = X509.Certificate.from_pem!("#{cert_escaped}")
        signer_key = X509.PrivateKey.from_pem!("#{key_escaped}")
        info = %NervesKey.ProvisioningInfo{manufacturer_sn: "#{serial}", board_name: "#{board}"}
        
        case NervesKey.provision(i2c, info, signer_cert, signer_key) do
          :ok -> IO.puts("PROVISION_RESULT: " <> Jason.encode!(%{status: "ok"}))
          {:error, reason} -> IO.puts("PROVISION_RESULT: " <> Jason.encode!(%{error: inspect(reason)}))
        end
      rescue
        e -> IO.puts("PROVISION_RESULT: " <> Jason.encode!(%{error: inspect(e)}))
      end
    end).()
    """

    SSHConnection.send_data(socket.assigns.ssh_pid, "\r\n\r\n" <> cmd <> "\r\n")
    Process.send_after(self(), :extraction_timeout, @extraction_timeout)

    {:noreply, assign(socket, provisioning: true, buffer: "")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={:nerves_key}>
      <div class="p-4 md:p-8 pb-12 md:pb-20 w-full flex flex-col">
        <UI.page_header
          icon="hero-key"
          title="Nerves Key"
          subtitle="Manage and provision NervesKey security chips"
        >
          <:actions>
            <div class="flex items-center gap-4 bg-white px-8 py-3 rounded-2xl shadow-sm border border-gray-100 w-full md:w-auto">
              <.form
                :let={f}
                for={to_form(%{"ip" => @selected_ip, "password" => @password}, as: :connection)}
                phx-change="validate_connection"
                phx-submit="connect"
                class="flex flex-wrap items-center gap-4"
              >
                <div class="w-fit min-w-[160px]">
                  <.input
                    field={f[:ip]}
                    type="select"
                    label="Target Device"
                    disabled={@status != :disconnected}
                    options={[
                      {"Select a device...", ""} | Enum.map(@devices, &{&1.name || &1.hostname, &1.ip})
                    ]}
                  />
                </div>

                <div class="h-10 w-px bg-gray-100 hidden sm:block"></div>

                <div class="w-32">
                  <.input
                    field={f[:password]}
                    type="password"
                    label="SSH Password"
                    disabled={@status != :disconnected}
                    placeholder="optional"
                  />
                </div>

                <div class="flex items-center mb-2 mt-6">
                  <%= if @status == :disconnected do %>
                    <button
                      type="submit"
                      class="btn btn-primary btn-md rounded-xl shadow-lg shadow-primary/20 flex items-center gap-2 px-8"
                    >
                      <.icon name="hero-bolt" class="w-4 h-4" /> Connect
                    </button>
                  <% else %>
                    <button
                      type="button"
                      phx-click="disconnect"
                      class="btn btn-error btn-outline btn-md rounded-xl flex items-center gap-2 px-8"
                    >
                      <.icon name="hero-x-mark" class="w-4 h-4" /> Disconnect
                    </button>
                  <% end %>
                </div>
              </.form>
            </div>
          </:actions>
        </UI.page_header>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-8 items-stretch">
          <!-- Left Column: Information -->
          <div class="space-y-8">
            <div class="bg-white rounded-[2.5rem] p-10 shadow-xl shadow-gray-200/50 border border-gray-100 relative overflow-hidden h-fit">
              <div
                :if={@extracting or @provisioning}
                class="absolute inset-0 bg-white/60 backdrop-blur-sm z-10 flex flex-col items-center justify-center space-y-4 text-center p-8"
              >
                <span class="loading loading-spinner loading-lg text-primary"></span>
                <p class="text-gray-900 font-black uppercase tracking-widest text-xs text-primary">
                  {if @extracting, do: "Communicating with IEx...", else: "Provisioning Hardware..."}
                </p>
              </div>

              <h3 class="text-2xl font-bold text-gray-900 mb-8 flex items-center gap-3">
                <div class="p-2 bg-primary/10 rounded-lg">
                  <.icon name="hero-information-circle" class="w-6 h-6 text-primary" />
                </div>
                Key Information
              </h3>

              <%= if @key_info do %>
                <div class="space-y-6 font-medium">
                  <%= if @key_info["error"] == "no_library" do %>
                    <div class="p-8 bg-amber-50 border-2 border-amber-200 rounded-[2rem] space-y-4">
                      <div class="flex items-center gap-3 text-amber-800 font-black uppercase text-xs tracking-widest">
                        <.icon name="hero-exclamation-triangle" class="w-6 h-6" /> Library Not Found
                      </div>
                      <p class="text-sm text-amber-700 leading-relaxed font-medium">
                        The <code>:nerves_key</code>
                        library is not installed in the device's firmware. Add it to your
                        <code>mix.exs</code>
                        and rebuild:
                      </p>
                      <div class="bg-white/50 p-4 rounded-2xl font-mono text-xs text-amber-900 border border-amber-200 shadow-inner">
                        {"{:nerves_key, \"~> 1.2\"}"}
                      </div>
                    </div>
                  <% end %>

                  <%= if @key_info["error"] == "no_chip" do %>
                    <div class="p-8 bg-red-50 border-2 border-red-200 rounded-[2rem] space-y-4">
                      <div class="flex items-center gap-3 text-red-800 font-black uppercase text-xs tracking-widest">
                        <.icon name="hero-cpu-chip" class="w-6 h-6" /> Hardware Not Detected
                      </div>
                      <p class="text-sm text-red-700 leading-relaxed font-medium">
                        The library is present, but no ATECC508A/608A chip was found on the I2C buses.
                      </p>
                      <ul class="text-sm text-red-600 space-y-2 list-disc list-inside px-2 font-medium">
                        <li>Check physical I2C wiring (SDA/SCL)</li>
                        <li>Ensure the chip has 3.3V power</li>
                        <li>Verify if a specific I2C bus is required</li>
                      </ul>
                    </div>
                  <% end %>

                  <%= if is_nil(@key_info["error"]) do %>
                    <div class="space-y-6">
                      <div class="grid grid-cols-2 gap-6">
                        <div class="p-6 bg-gray-50 rounded-3xl border border-gray-100 shadow-sm">
                          <div class="text-[10px] uppercase font-bold text-gray-400 mb-2 tracking-wider">
                            Provisioned Status
                          </div>
                          <div class="flex items-center gap-2">
                            <%= if @key_info["provisioned"] do %>
                              <span class="w-2.5 h-2.5 rounded-full bg-green-500 shadow-sm shadow-green-200">
                              </span>
                              <span class="font-black text-gray-900 uppercase text-sm tracking-tight">
                                Provisioned
                              </span>
                            <% else %>
                              <span class="w-2.5 h-2.5 rounded-full bg-red-500 shadow-sm shadow-red-200">
                              </span>
                              <span class="font-black text-gray-900 uppercase text-sm tracking-tight">
                                Not Provisioned
                              </span>
                            <% end %>
                          </div>
                        </div>
                        <div class="p-6 bg-gray-50 rounded-3xl border border-gray-100 shadow-sm">
                          <div class="text-[10px] uppercase font-bold text-gray-400 mb-2 tracking-wider">
                            Board Identity
                          </div>
                          <div class="font-black text-gray-900 text-sm tracking-tight">
                            {@key_info["board_name"] || "Unknown"}
                          </div>
                        </div>
                      </div>

                      <div class="p-6 bg-gray-50 rounded-3xl border border-gray-100 shadow-sm">
                        <div class="text-[10px] uppercase font-bold text-gray-400 mb-2 tracking-wider">
                          Manufacturer Serial Number
                        </div>
                        <div class="font-mono text-base font-black text-gray-900 break-all">
                          {@key_info["manufacturer_sn"] || "Not Available"}
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <div
                  :if={!@extracting}
                  class="flex flex-col items-center justify-center py-32 text-center space-y-6 text-gray-400 border-2 border-dashed border-gray-100 rounded-[2.5rem]"
                >
                  <div class="p-4 bg-gray-50 rounded-full">
                    <.icon name="hero-server-stack" class="w-12 h-12 opacity-30 text-primary" />
                  </div>
                  <p class="max-w-xs font-bold text-gray-500 leading-relaxed">
                    Connect to a device to read its NervesKey provisioning status.
                  </p>
                </div>
              <% end %>
            </div>

            <div class="bg-blue-50/50 p-8 rounded-[2.5rem] border border-blue-100/50 h-fit">
              <h4 class="font-black text-blue-900 text-xs uppercase tracking-widest mb-4 flex items-center gap-2">
                <.icon name="hero-question-mark-circle" class="w-4 h-4" /> About Nerves Key
              </h4>
              <p class="text-sm text-blue-800/70 leading-relaxed font-medium">
                The NervesKey is a specialized cryptographic chip used to securely identify devices. It protects private keys and enables seamless integration with NervesHub.
              </p>
              <div class="mt-4">
                <a
                  href="https://docs.nerves-hub.org/nerves-key/introduction"
                  target="_blank"
                  rel="noopener noreferrer"
                  phx-hook="TauriOpen"
                  id="docs-link"
                  class="text-xs text-blue-800 font-black hover:underline"
                >
                  Learn more in the documentation &rarr;
                </a>
              </div>
            </div>
          </div>
          
    <!-- Right Column: Signer & Provisioning Combined -->
          <div class="bg-gray-50 rounded-[2.5rem] p-10 shadow-xl shadow-gray-200/50 border border-gray-100 flex flex-col">
            <h3 class="text-2xl font-bold text-gray-900 mb-8 flex items-center gap-3">
              <div class="p-2 bg-primary/10 rounded-lg">
                <.icon name="hero-pencil-square" class="w-6 h-6 text-primary" />
              </div>
              Provisioning Workflow
            </h3>

            <.form
              :let={wf}
              for={@workflow_form}
              phx-change="validate_provisioning"
              phx-submit="commit_provisioning"
              class="space-y-8 flex-1"
            >
              <!-- Step 1: Device CA -->
              <section class="space-y-4">
                <div class="flex justify-between items-center px-1">
                  <h4 class="text-xs uppercase font-black text-gray-400 tracking-widest">
                    1. Device Certificate Authority
                  </h4>
                  <button
                    type="button"
                    phx-click="generate_ca"
                    class="text-[10px] text-primary font-black hover:underline uppercase tracking-wider"
                  >
                    Generate New Device CA
                  </button>
                </div>

                <div class="grid grid-cols-1 gap-4">
                  <.input
                    field={wf[:signer_cert]}
                    type="textarea"
                    label="Device CA Certificate (PEM)"
                    rows="4"
                    placeholder="Paste Device CA Cert..."
                  />
                  <.input
                    field={wf[:signer_key]}
                    type="textarea"
                    label="Device CA Private Key (PEM)"
                    rows="4"
                    placeholder="Paste Device CA Key..."
                  />
                </div>
              </section>
              
    <!-- Step 2: Device Provisioning -->
              <section class="space-y-6 pt-6 border-t border-gray-200">
                <h4 class="text-xs uppercase font-black text-gray-400 tracking-widest">
                  2. Device Target Data
                </h4>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <.input
                    field={wf[:device_serial]}
                    type="text"
                    label="Manufacturer Serial Number"
                    placeholder="e.g. SN12345678"
                  />
                  <.input
                    field={wf[:device_board_name]}
                    type="text"
                    label="Board Name"
                  />
                </div>
              </section>

              <div class="mt-12 space-y-4">
                <button
                  type="submit"
                  data-confirm="WARNING: Provisioning is PERMANENT and will lock the hardware security chip. Ensure all data is correct. Proceed?"
                  disabled={
                    @status == :disconnected or @workflow_form.params["signer_cert"] == "" or
                      @workflow_form.params["signer_key"] == "" or
                      @workflow_form.params["device_serial"] == "" or
                      (not is_nil(@key_info) and not is_nil(@key_info["error"]))
                  }
                  class="btn btn-primary w-full rounded-2xl h-14 shadow-xl shadow-primary/20 uppercase font-black tracking-widest text-base hover:scale-[1.01] active:scale-[0.99] transition-all"
                >
                  <.icon name="hero-check-badge" class="w-6 h-6 mr-2" /> Provision NervesKey
                </button>

                <div class="flex items-center gap-3 justify-center px-4">
                  <div class="h-px bg-gray-200 flex-1"></div>
                  <span class="text-[9px] text-gray-400 font-black uppercase tracking-tighter">
                    Danger Zone
                  </span>
                  <div class="h-px bg-gray-200 flex-1"></div>
                </div>

                <p class="text-[10px] text-red-500/70 text-center leading-relaxed font-bold px-8">
                  This will generate the private key on the device and sign it with your Device CA. This operation is permanent.
                </p>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
