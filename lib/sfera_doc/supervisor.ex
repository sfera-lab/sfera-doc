defmodule SferaDoc.Supervisor do
  @moduledoc false
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Supervisor
  def init(_opts) do
    children =
      [
        SferaDoc.Cache.ParsedTemplate.worker_spec(),
        store_worker_spec(),
        SferaDoc.Pdf.HotCache.worker_spec(),
        SferaDoc.Pdf.ObjectStore.worker_spec(),
        chromic_pdf_spec()
      ]
      |> Enum.reject(&is_nil/1)

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp store_worker_spec do
    try do
      SferaDoc.Config.store_adapter().worker_spec()
    rescue
      UndefinedFunctionError ->
        raise """
        SferaDoc: the configured store adapter module is not available.
        Make sure the adapter module exists and its dependencies are included:

            config :sfera_doc, :store, adapter: SferaDoc.Store.ETS   # or Ecto / Redis
        """
    end
  end

  defp chromic_pdf_spec do
    cond do
      SferaDoc.Config.pdf_engine_adapter() != SferaDoc.PdfEngine.ChromicPDF ->
        nil

      Keyword.get(SferaDoc.Config.chromic_pdf_opts(), :disabled, false) ->
        nil

      true ->
        opts = SferaDoc.Config.chromic_pdf_opts()
        {ChromicPDF, Keyword.delete(opts, :disabled)}
    end
  end
end
