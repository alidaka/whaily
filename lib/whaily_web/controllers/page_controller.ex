defmodule WhailyWeb.PageController do
  use WhailyWeb, :live_view

  def render(assigns) do
    ~H"""
    <div>
      hallo "<%= @myvar %>"
    </div>
    """
  end

  def mount(_params, _session, socket) do
    myvar = "babbys first vra"
    {:ok, assign(socket, :myvar, myvar)}
  end
end
