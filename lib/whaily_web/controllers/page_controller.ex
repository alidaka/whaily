defmodule WhailyWeb.PageController do
  use WhailyWeb, :live_view

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    Logger.info "mount"
    if connected?(socket) do Logger.info "mount connected!!!!" end
    {:ok,
      socket
      |> assign(others: []) # breadcrumbs in case they become useful later
      |> assign_async(:truck_name, fn -> fetch_truck() end)
      |> assign_async(:weather, fn -> fetch_weather() end)}
  end

  defp fetch_truck do
    Logger.info "fetch_truck let's go"
    #url = "https://clients6.google.com/calendar/v3/calendars/tihhbg3gp215ruuo0nsp3qafgs@group.calendar.google.com/events?calendarId=tihhbg3gp215ruuo0nsp3qafgs%40group.calendar.google.com&singleEvents=true&eventTypes=default&eventTypes=focusTime&eventTypes=outOfOffice&timeZone=America%2FLos_Angeles&maxAttendees=1&maxResults=250&sanitizeHtml=true&timeMin=2024-09-08T00%3A00%3A00-07%3A00&timeMax=2024-10-15T00%3A00%3A00-07%3A00&key=AIzaSyBNlYH01_9Hc5S1J9vuFmu2nUqBZJNAXxs&%24unique=gc237"
    today = DateTime.now!("America/Los_Angeles")
    today_iso = DateTime.to_iso8601(today)
    tomorrow_iso =
      today
      |> DateTime.add(1, :day, Tz.TimeZoneDatabase)
      |> DateTime.to_iso8601

    url = ~s(https://clients6.google.com/calendar/v3/calendars/tihhbg3gp215ruuo0nsp3qafgs@group.calendar.google.com/events?calendarId=tihhbg3gp215ruuo0nsp3qafgs%40group.calendar.google.com&singleEvents=true&eventTypes=default&eventTypes=focusTime&eventTypes=outOfOffice&timeZone=America%2FLos_Angeles&maxAttendees=1&maxResults=250&sanitizeHtml=true&timeMin=#{today_iso}&timeMax=#{tomorrow_iso}&key=AIzaSyBNlYH01_9Hc5S1J9vuFmu2nUqBZJNAXxs&%24unique=gc237)

    get_response = get(url, fn
      response ->
        response["items"]
        |> Enum.map(fn i -> i["summary"] end)
        |> Enum.join("; ")
    end)

    case get_response do
      {:ok, result} -> {:ok, %{truck_name: result}}
      {:error, error} -> {:error, error}
    end
  end

  defp fetch_weather do
    lat = System.get_env("WEATHER_LAT")
    long = System.get_env("WEATHER_LONG")
    url = ~s(https://api.open-meteo.com/v1/forecast?latitude=#{lat}&longitude=#{long}&current=temperature_2m&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max&temperature_unit=fahrenheit&timezone=America%2FLos_Angeles&forecast_days=1)

    get_response = get(url, fn
      response ->
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

  defp get(url, json_fn) do
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
    <div class="p-8 shadow-md">
      <.async_result :let={weather} assign={@weather}>
          <:loading>loading weather...</:loading>
          <:failed :let={failure}>error: <%= inspect failure %></:failed>
          <span>Min: <%= weather.min %></span>
          <span>Max: <%= weather.max %></span>
          <span>Current: <%= weather.current %></span>
          <span>Precip: <%= weather.precip %>%</span>
        </.async_result>
    </div>

    <div class="p-8 shadow-md">
      <a href="https://www.chuckshopshop.com/greenwood">
        <.async_result :let={truck} assign={@truck_name}>
          <:loading>loading truck...</:loading>
          <:failed :let={failure}>error: <%= inspect failure %></:failed>
          <%= truck %>
        </.async_result>
      </a>
    </div>
    <%= for item <- @others do %>
      <div>
        hello "<%= item %>"
      </div>
    <% end %>
    """
  end
end
