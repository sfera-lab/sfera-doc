defmodule SferaDoc.PdfEngine.ChromicPDF do
  @moduledoc """
  Default PDF engine adapter backed by `ChromicPDF`.
  """

  require Logger

  @behaviour SferaDoc.PdfEngine.Adapter

  @impl true
  def render(html, opts) do
    case ChromicPDF.print_to_pdf({:html, html}, opts) do
      {:ok, base64_data} ->
        pdf_binary = Base.decode64!(base64_data)
        Logger.debug("ChromicPDF rendered PDF of size: #{byte_size(pdf_binary)} bytes")
        {:ok, pdf_binary}

      other ->
        {:error, {:chromic_pdf_error, other}}
    end
  end
end
