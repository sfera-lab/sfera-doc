defmodule SferaDoc.PdfEngine.Adapter do
  @moduledoc """
  Behaviour for PDF engines used by SferaDoc.
  """

  @type reason :: any()

  @callback render(binary(), keyword()) :: {:ok, binary()} | {:error, reason()}
end
