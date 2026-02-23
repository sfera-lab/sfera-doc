defmodule SferaDoc.Application do
  @moduledoc false
  use Application

  @impl Application
  def start(_type, _args) do
    SferaDoc.Supervisor.start_link([])
  end
end
