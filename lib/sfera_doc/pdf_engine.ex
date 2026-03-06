defmodule SferaDoc.PdfEngine do
  @moduledoc false

  alias SferaDoc.Config

  @spec render(binary(), keyword()) :: {:ok, binary()} | {:error, any()}
  def render(html, opts), do: Config.pdf_engine_adapter().render(html, opts)
end
