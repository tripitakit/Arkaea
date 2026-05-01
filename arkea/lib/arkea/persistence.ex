defmodule Arkea.Persistence do
  @moduledoc false

  @spec enabled?() :: boolean()
  def enabled? do
    Application.get_env(:arkea, :persistence_enabled, true)
  end
end
