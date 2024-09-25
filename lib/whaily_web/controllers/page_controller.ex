defmodule WhailyWeb.PageController do
  use WhailyWeb, :live_view

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
      socket
      |> assign_async(:trucks, fn -> fetch_truck() end)
      |> assign_async(:weather, fn -> fetch_weather() end)
      |> fetch_buses_async()}
  end

  defp fetch_buses_async(socket) do
    stop_ids = System.get_env("OBA_STOPS")
               |> String.split(",")

    placeholders = Enum.map(stop_ids, fn stop -> %{id: stop, data: nil} end)
    socket = stream(socket, :buses, placeholders)

    Enum.reduce(stop_ids, socket, fn (stop, socket) ->
      start_async(socket, {:bus_handler, stop}, fn -> fetch_stop(stop) end)
    end)
  end

  defp fetch_truck do
    today = DateTime.now!("America/Los_Angeles")
    today_iso = DateTime.to_iso8601(today)
    tomorrow_iso =
      today
      |> DateTime.add(1, :day, Tz.TimeZoneDatabase)
      |> DateTime.to_iso8601

    url = ~s(https://clients6.google.com/calendar/v3/calendars/tihhbg3gp215ruuo0nsp3qafgs@group.calendar.google.com/events?calendarId=tihhbg3gp215ruuo0nsp3qafgs%40group.calendar.google.com&singleEvents=true&eventTypes=default&eventTypes=focusTime&eventTypes=outOfOffice&timeZone=America%2FLos_Angeles&maxAttendees=1&maxResults=250&sanitizeHtml=true&timeMin=#{today_iso}&timeMax=#{tomorrow_iso}&key=AIzaSyBNlYH01_9Hc5S1J9vuFmu2nUqBZJNAXxs&%24unique=gc237)

    get_response = get(url, fn response ->
      Enum.map(response["items"], fn i -> %{
        start: ~s(#{String.slice(i["start"]["dateTime"], 5, 5)} #{String.slice(i["start"]["dateTime"], 11, 5)}),
        end: String.slice(i["end"]["dateTime"], 11, 5),
        name: i["summary"]}
      end)
    end)

    case get_response do
      {:ok, result} -> {:ok, %{trucks: Enum.sort_by(result, fn t -> t.start end)}}
      {:error, error} -> {:error, error}
    end
  end

  defp fetch_weather do
    lat = System.get_env("WEATHER_LAT")
    long = System.get_env("WEATHER_LONG")
    url = ~s(https://api.open-meteo.com/v1/forecast?latitude=#{lat}&longitude=#{long}&current=temperature_2m&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max&temperature_unit=fahrenheit&timezone=America%2FLos_Angeles&forecast_days=1)

    get_response = get(url, fn response ->
      %{max: hd(response["daily"]["temperature_2m_max"]),
        min: hd(response["daily"]["temperature_2m_min"]),
        current: response["current"]["temperature_2m"],
        precip: hd(response["daily"]["precipitation_probability_max"])}
    end)

    case get_response do
      {:ok, result} -> {:ok, %{weather: result}}
      {:error, error} -> {:error, error}
    end
  end

  @impl true
  def handle_async({:bus_handler, _}, {:ok, fetched_stop}, socket) do
    {:noreply, stream_insert(socket, :buses, %{id: fetched_stop.stop_id, data: fetched_stop})}
  end

  @impl true
  def handle_async({:bus_handler, _}, {:exit, reason}, socket) do
    Logger.error reason
    {:noreply, socket}
  end

  defp fetch_stop(stop) do
    key = System.get_env("OBA_KEY")
    url = ~s(https://api.pugetsound.onebusaway.org/api/where/arrivals-and-departures-for-stop/#{stop}.json?key=#{key})

    get_response = get(url, fn response ->
      stop_response = response["data"]["references"]["stops"]
                      |> Enum.find(fn s -> s["id"] == stop end)
      buses_response = response["data"]["entry"]["arrivalsAndDepartures"]
      now = DateTime.utc_now()

      bus_parser = fn b ->
        eta = case b["predictedArrivalTime"] do
          0 -> b["scheduledArrivalTime"]
          _ -> b["predictedArrivalTime"]
        end
        |> DateTime.from_unix!(:millisecond)
        |> DateTime.diff(now)
        |> div(60)

        %{short_name: b["routeShortName"], eta: eta}
      end

      %{stop_id: stop,
        intersection: stop_response["name"],
        direction: stop_response["direction"],
        buses: Enum.map(buses_response, bus_parser)}
    end)

    case get_response do
      {:ok, result} -> result
      {:error, error} -> {:error, error}
    end
  end

  defp get(url, json_fn) do
    Logger.info url
    case Finch.build(:get, url) |> Finch.request(Whaily.Finch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, response} ->
            {:ok, json_fn.(response)}

          {:error, error} ->
            {:error, "Jason error: #{inspect(error)}"}
        end

      {:ok, %Finch.Response{status: status}} ->
        {:error, "Request failed with status #{status}"}
      {:error, reason} ->
        {:error, "Request error: #{inspect(reason)}"}
    end
 end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-8 shadow-md bg-sky-100">
      <.async_result :let={weather} assign={@weather}>
          <:loading>loading weather...</:loading>
          <:failed :let={failure}>error: <%= inspect failure %></:failed>
          <div>
            <span>Low: <%= weather.min %></span>
            <span>High: <%= weather.max %></span>
            <span>Precip: <%= weather.precip %>%</span>
          </div>
          <div>
            <span>Current: <%= weather.current %></span>
          </div>
        </.async_result>
    </div>

    <.async_result :let={trucks} assign={@trucks}>
      <:loading>
        <div class="p-8 shadow-md bg-green-100">
          loading trucks...
        </div>
      </:loading>
      <:failed :let={failure}>
        <div class="p-8 shadow-md bg-green-100">
          error: <%= inspect failure %>
        </div>
      </:failed>
      <%= for truck <- trucks do %>
        <div class="p-8 shadow-md bg-green-100">
          <a href="https://www.chuckshopshop.com/greenwood">
            <div><%= truck.start %> - <%= truck.end %></div>
            <div><%= truck.name %></div>
          </a>
        </div>
      <% end %>
    </.async_result>

    <!-- TODO: fresh hops -->

    <div id="buses" phx-update="stream" class="contents">
      <div
        class="p-8 shadow-md bg-red-100"
        :for={{dom_id, stop} <- @streams.buses}
        id={dom_id}
      >
        <%= if stop.data do %>
          <div>
            <%= stop.data.intersection %> (<%= stop.data.direction %>)
          </div>
          <div>
            <%= for bus <- Enum.sort_by(stop.data.buses, fn bus -> bus.eta end) do %>
              <span class="bg-red-200 mx-[4px]">
                <%= bus.short_name %>: <%= bus.eta %>
              </span>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
