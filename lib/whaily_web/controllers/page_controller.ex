defmodule WhailyWeb.PageController do
  use WhailyWeb, :live_view

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    Logger.info "mount"
    if connected?(socket) do Logger.info "mount connected!!!!" end
    {:ok,
      socket
      |> assign(others: ["babbys first vra", 64, "third var"])
      |> assign_async(:truck_name, fn -> fetch_truck() end)
      |> assign_async(:temperature, fn -> {:ok, %{temperature: fetch_temp()}} end)}
  end

  def fetch_truck do
    Logger.info "fetch_truck let's go"
    case Finch.build(:get, "https://google.com") |> Finch.request(Whaily.Finch) do
      {:ok, %Finch.Response{status: 200, body: _body}} ->
        {:ok, "Tacos and Beer"}

      {:ok, %Finch.Response{status: status}} ->
        {:error, "Failed with status #{status}"}

      {:error, reason} ->
        {:error, "Error: #{inspect(reason)}"}
    end
  end

  def fetch_temp do
    10
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container" :if={@temperature.loading}>loading temp...</div>
    <div class="container" :if={temp = @temperature.ok? && @temperature.result}>Forecast: <%= temp %></div>
    <div class="container">
      <.async_result :let={truck} assign={@truck_name}>
        <:loading>loading truck...</:loading>
        <:failed :let={failure}>error: <%= inspect failure %></:failed>
        <%= truck %>
      </.async_result>
    </div>
    <%= for item <- @others do %>
      <div class="container">
        hello "<%= item %>"
      </div>
    <% end %>
    """
  end
end
