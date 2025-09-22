defmodule WhailyWeb.PageController do
  use WhailyWeb, :live_view

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
      socket
      |> assign_async(:trucks, fn -> fetch_truck() end)
      |> assign_async(:weather, fn -> fetch_weather() end)
      |> assign_async(:beers, fn -> fetch_beers() end)
      |> assign_async(:economy, fn -> fetch_econ() end)
      |> fetch_buses_async()}
  end

  # TODO: rewrite with `with`? Or guard clauses?
  defp seek_value data, date, obs_index do
    case Enum.at(data, obs_index) do
      nil -> {%{date: date, rate: nil}, obs_index}
      obs -> case Date.compare(obs.date, date) do
        :lt -> seek_value(data, date, obs_index + 1)
        :gt -> {%{date: date, rate: nil}, obs_index}
        :eq -> {%{date: date, rate: obs.rate}, obs_index + 1}
      end
    end
  end


  defp unpack_and_interpolate(fred_response, past_days) do
    parse_float = fn value ->
      case Float.parse(value) do
        {val, _} -> val
        :error -> nil
      end
    end

    data = fred_response["observations"]
           |> Enum.map(&(
             %{date: Date.from_iso8601!(&1["date"]),
               rate: parse_float.(&1["value"])}
           ))
           |> Enum.reverse

    # Create the date range we *want* and populate values where we *can*
    latest_date = Enum.at(data, -1).date
    Date.range(Date.add(latest_date, -past_days), latest_date)
             |> Enum.map_reduce(0, &seek_value(data, &1, &2))
             |> elem(0)
  end

  defp fetch_econ do
    key = System.get_env("FRED_KEY")
    history_days = 2 * 365

    # 10y Treasury Bond Yield Rates
    bond_url = ~s(https://api.stlouisfed.org/fred/series/observations?series_id=DGS10&api_key=#{key}&file_type=json&sort_order=desc&limit=#{history_days})
    # 30y Fixed-rate Jumbo Mortgage Index
    mortgage_url = ~s(https://api.stlouisfed.org/fred/series/observations?series_id=OBMMIJUMBO30YF&api_key=#{key}&file_type=json&sort_order=desc&limit=#{history_days})

    # TODO: confirm whether Elixir/BEAM make these async on our behalf
    with {:ok, bond_result} <- get(bond_url, &unpack_and_interpolate(&1, history_days)),
         {:ok, mortgage_result} <- get(mortgage_url, &unpack_and_interpolate(&1, history_days)) do
      {:ok, %{economy: %{bond_rates: bond_result, mortgage_rates: mortgage_result}}}
    end
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

  defp beer_reducer(beers) do
    # TODO: Chuck's seems to prefix '-' or '_' for unavailable beers - probably just-tapped rather than on-deck
    fresh_hop_filter = %{title: "Fresh Hops", filter: fn tap -> String.contains?(String.downcase(tap.name), "fresh hop") end}
    dark_filter = %{title: "Dark Beers", filter: fn tap -> tap.color != nil && String.downcase(tap.color) == "orange" end}
    hazy_filter = %{title: "Hazies", filter: fn tap -> String.contains?(String.downcase(tap.name), "hazy") end}
    #default_filter = %{title: "Beers", filter: fn tap -> tap end}

    ordered_filters = [fresh_hop_filter, dark_filter, hazy_filter]

    {:ok, Enum.reduce_while(ordered_filters, beers, fn (fltr, all_beers) ->
      filtered_results = Enum.filter(all_beers, &(fltr.filter.(&1)))
      if !Enum.empty?(filtered_results) do
        {:halt, %{title: fltr.title, taps: filtered_results}}
      else
        {:cont, all_beers}
      end
    end)}
  end

  defp fetch_beers do
    url = ~s(https://taplists.web.app/data?menu=GW)

    get_response = get(url, fn response ->
      response
      |> Enum.map(fn tap -> %{
        name: tap["beer"],
        origin: tap["origin"],
        serving: tap["serving"],
        color: tap["color"],
        style: tap["type"]}
      end)
    end)

    with {:ok, result} <- get_response,
         {:ok, beer_result} <- beer_reducer(result)
    do
      {:ok, %{beers: beer_result}}
    end
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
    url = ~s(https://api.open-meteo.com/v1/forecast?latitude=#{lat}&longitude=#{long}&current=temperature_2m&hourly=temperature_2m,precipitation_probability&past_days=1&forecast_days=2&temperature_unit=fahrenheit&timezone=America%2FLos_Angeles)

    get_response = get(url, fn response ->
      # get the past two hours and next 14 (16h total window)
      # per original inspection, one point per hour, from midnight to midnight
      # current time sometimes has minutes, so just match to the hour - e.g. "2025-09-08T19:15"
      current_time_prefix = String.slice(response["current"]["time"], 0..-3//1)
      idx_now = response["hourly"]["time"] |> Enum.find_index(&(String.starts_with?(&1, current_time_prefix)))
      idx_start = idx_now - 2
      temp_data = response["hourly"]["temperature_2m"] |> Enum.slice(idx_start, 2 + 1 + 14)
      precip_data = response["hourly"]["precipitation_probability"] |> Enum.slice(idx_start, 2 + 1 + 14)
      # give the frontend just the 24h value
      short_times = response["hourly"]["time"]
                    |> Enum.slice(idx_start, 2 + 1 + 14)
                    |> Enum.map(&(String.slice(&1, 11..12)))
                    |> Enum.map(&String.to_integer/1)

      current_time_tokens = response["current"]["time"]
                            |> String.slice(-5..-1)
                            |> String.split(":")
      current_time_decimal = String.to_integer(hd(current_time_tokens)) + (String.to_integer(hd(tl(current_time_tokens))) / 60.0)

      %{temp: temp_data,
        precip: precip_data,
        short_times: short_times,
        current_time: current_time_decimal,
        current_temp: response["current"]["temperature_2m"]}
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

    <div class="section">
      <h2>Weather</h2>
      <div class="card bg-sky-100">
        <.async_result :let={weather} assign={@weather}>
          <:loading>checking weather...</:loading>
          <:failed :let={failure}>error: <%= inspect failure %></:failed>

          <canvas id="weather_chart" phx-hook=".WeatherChart" data-weather={weather && Jason.encode!(weather)}></canvas>
          <script :type={Phoenix.LiveView.ColocatedHook} name=".WeatherChart">
            export default {
              mounted() {
                const data = JSON.parse(this.el.dataset.weather);

                // kludge to stop messing with time/labels/annotation
                var count = 0;
                const labels = data.short_times.map(t => {
                  if (t === 0) count++;
                  return count ? t + 24 : t;
                });
                const annotationValue = data.current_time < labels[0] ? data.current_time + 24 : data.current_time;

                new Chart(this.el, {
                  type: 'line',
                  data: {
                    labels: labels,
                    datasets: [{
                        data: data.temp,
                        yAxisID: 'y_temp',
                        tension: 0.4,
                        borderColor: '#ff6384'
                      }, {
                        data: data.precip,
                        yAxisID: 'y_precip',
                        tension: 0.4,
                        borderColor: '#36a2eb'
                      }]
                  },
                  options: {
                    elements: {
                      point: { pointStyle: false }
                    },
                    plugins: {
                      legend: { display: false },
                      annotation: {
                        annotations: {
                          x: {
                            type: 'line',
                            scaleID: 'x',
                            label: {
                              content: data.current_temp,
                              display: true,
                              backgroundColor: 'rgba(0,0,0,.5)'
                            },
                            value: annotationValue,
                            endValue: annotationValue,
                            borderColor: 'rgba(0,0,0,.4)',
                            borderWidth: 2
                          }
                        }
                      }
                    },
                    scales: {
                      x: {
                        type: 'linear',
                        min: labels[0],
                        max: labels.at(-1),
                        ticks: {
                          callback: function(value) { return value % 24; }
                        }
                      },
                      y_temp: {
                        type: 'linear',
                        position: 'left',
                        ticks: {
                          color: '#ff6384',
                          callback: function(value) { return value + '°'; }
                        },
                        min: Math.floor(Math.min(...data.temp) - 5),
                        max: Math.ceil(Math.max(...data.temp) + 5),
                      },
                      y_precip: {
                        type: 'linear',
                        position: 'right',
                        ticks: {
                          color: '#36a2eb',
                          callback: function(value) { return value + '%'; }
                        },
                        grid: { drawOnChartArea: false },
                        min: 0,
                        max: 100,
                      }
                    }
                  }
                });
              }
            }
          </script>

        </.async_result>
      </div>
    </div>

    <div class="section">
      <h2>Chuck's Food</h2>
      <.async_result :let={trucks} assign={@trucks}>
        <:loading>
          <div class="card bg-orange-100">
            parking trucks...
          </div>
        </:loading>
        <:failed :let={failure}>
          <div class="card bg-orange-100">
            error: <%= inspect failure %>
          </div>
        </:failed>
        <%= for truck <- trucks do %>
          <div class="card bg-orange-100">
            <a href="https://www.chuckshopshop.com/greenwood">
              <div><%= truck.start %> - <%= truck.end %></div>
              <div><%= truck.name %></div>
            </a>
          </div>
        <% end %>
      </.async_result>
    </div>

    <div class="section">
      <h2>Buses</h2>
      <div id="buses" phx-update="stream" class="contents">
        <div
          class="card bg-red-100"
          :for={{dom_id, stop} <- @streams.buses}
          id={dom_id}
        >
          <%= if stop.data do %>
            <div>
              <%= stop.data.intersection %> (<%= stop.data.direction %>)
            </div>
            <div class="flex flex-row space-x-4">
              <%= for bus <- Enum.sort_by(stop.data.buses, fn bus -> bus.eta end) do %>
                <div class="font-bold">
                  <span class="bg-red-200"><%= bus.short_name %>: </span><span class="bg-gray-100"><%= bus.eta %></span>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>

    <div class="section">
      <.async_result :let={beers} assign={@beers}>
        <:loading>
          <h2>Chuck's Beers</h2>
          <div class="card bg-green-100">
            pouring taps...
          </div>
        </:loading>
        <:failed :let={failure}>
          <h2>Chuck's Beers</h2>
          <div class="card bg-green-100">
            error: <%= inspect failure %>
          </div>
        </:failed>
        <h2>Chuck's <%= beers.title %></h2>
        <div class="grid grid-flow-row grid-cols-2">
          <%= for tap <- beers.taps do %>
            <div class="card bg-green-100 max-w-64">
              <a href="https://taplists.web.app/?store=GW">
                <div><%= tap.name %> - <%= tap.origin %></div>
              </a>
            </div>
          <% end %>
        </div>
      </.async_result>
    </div>

    <!-- [date, rate] -->
    <div class="section">
      <h2><span style="color: #36a2eb">10y Treasury Bonds</span> and <span style="color: #ff6384">30y Jumbo Mortgages</span></h2>
      <div class="card bg-yellow-100">
      <.async_result :let={economy} assign={@economy}>
        <:loading>calculating rates...</:loading>
        <:failed :let={failure}>error: <%= inspect failure %></:failed>

        <div class="w-[80vw]">
          <canvas id="economic_chart"
            phx-hook=".EconomicChart"
            data-econ={economy && Jason.encode!(economy)}>
          </canvas>
        </div>

        <script :type={Phoenix.LiveView.ColocatedHook} name=".EconomicChart">
          export default {
            mounted() {
              const data = JSON.parse(this.el.dataset.econ);

              new Chart(this.el, {
                type: 'line',
                data: {
                  datasets: [{
                    data: data.bond_rates,
                    cubicInterpolationMode: 'monotone',
                    spanGaps: true,
                    yAxisID: 'y_bond'
                  }, {
                    data: data.mortgage_rates,
                    cubicInterpolationMode: 'monotone',
                    spanGaps: true,
                    yAxisID: 'y_mortgage'
                  }]
                },
                options: {
                  responsive: true,
                  maintainAspectRatio: false,
                  parsing: {
                    xAxisKey: 'date',
                    yAxisKey: 'rate'
                  },
                  plugins: {
                    legend: { display: false }
                  },
                  elements: {
                    point: { pointStyle: false }
                  },
                  scales: {
                    x: {
                      ticks: {
                        callback: function(value, index) { return data.bond_rates[index].date.substring(5); }
                      }
                    },
                    y_bond: {
                      type: 'linear',
                      position: 'left',
                      ticks: { color: '#36a2eb' },
                      grid: { drawOnChartArea: false }
                    },
                    y_mortgage: {
                      type: 'linear',
                      position: 'right',
                      ticks: { color: '#ff6384' }
                    }
                  }
                }
              });
            },

            // Something about LiveView update/render prevents ChartJS from doing
            // the right thing on initial mount
            updated() {
              const chart = Chart.getChart('economic_chart');
              chart.resize();
            }
          }
        </script>

      </.async_result>
      </div>
    </div>

    """
  end
end
