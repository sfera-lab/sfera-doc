defmodule SferaDoc.PdfEngine.ChromicPDF do
  @moduledoc """
  Default PDF engine adapter backed by `ChromicPDF`.
  """

  @behaviour SferaDoc.PdfEngine.Adapter

  @impl true
  def render(html, opts) do
    case ChromicPDF.print_to_pdf({:html, html}, opts) do
      {:ok, pdf} -> {:ok, pdf}
      other -> {:error, {:chromic_pdf_error, other}}
    end
  end
end
