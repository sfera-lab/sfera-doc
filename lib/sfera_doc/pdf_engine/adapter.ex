defmodule SferaDoc.PdfEngine.Adapter do
  @moduledoc """
  Behaviour for PDF engines used by SferaDoc.

  PDF engine adapters are responsible for converting a rendered HTML string
  into a PDF binary.

  ## Implementing a Custom Adapter

  1. `@behaviour SferaDoc.PdfEngine.Adapter`
  2. Implement the `render/2` callback
  3. Configure the library to use your adapter:

         config :sfera_doc, :pdf_engine,
           adapter: MyApp.CustomPdfEngine
  """

  @type html :: String.t()
  @type reason :: any()

  @doc """
  Renders the given HTML string into a PDF binary.

  Returns `{:ok, pdf_binary}` on success or `{:error, reason}` on failure.
  """
  @callback render(html(), keyword()) :: {:ok, binary()} | {:error, reason()}
end
