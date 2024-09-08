defmodule WhailyWeb.PageController do
  use WhailyWeb, :live_view

  def render(assigns) do
    ~H"""
    <%= for item <- @list do %>
      <div>
        hello "<%= item %>"
      </div>
    <% end %>
    """
  end

  def mount(_params, _session, socket) do
    list = ["babbys first vra", 64, "third var"]
    {:ok, assign(socket, :list, list)}
  end
end
