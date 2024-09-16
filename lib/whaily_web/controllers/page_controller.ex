defmodule WhailyWeb.PageController do
  use WhailyWeb, :live_view

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
      socket
      |> assign(others: []) # breadcrumbs in case they become useful later
      |> assign_async(:trucks, fn -> fetch_truck() end)
      |> assign_async(:weather, fn -> fetch_weather() end)}
  end

  defp fetch_truck do
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
            <span>Min: <%= weather.min %></span>
            <span>Max: <%= weather.max %></span>
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

    <%= for item <- @others do %>
      <div>
        hello "<%= item %>"
      </div>
    <% end %>
    """
  end
end
