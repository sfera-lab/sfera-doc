defmodule SferaDoc.TestPdfEngine do
  @moduledoc false
  @behaviour SferaDoc.PdfEngine.Adapter

  alias SferaDoc.TestSupport

  @impl true
  def render(html, opts) do
    TestSupport.increment(:pdf_render)

    if Keyword.get(opts, :fail, false) || String.contains?(html, "PDF_ERROR") do
      {:error, :pdf_failed}
    else
      {:ok, "PDF_BINARY:#{html}"}
    end
  end
end
