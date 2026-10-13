defmodule RxGeneratorWeb.PageController do
  use RxGeneratorWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
