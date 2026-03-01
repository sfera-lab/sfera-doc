---
title: Custom Adapters
description: Replace the Liquid engine or PDF renderer with your own implementation.
order: 6
---

SferaDoc's template engine and PDF engine are both pluggable via behaviour adapters.

---

## Custom Template Engine

The default template engine uses [`solid`](https://hex.pm/packages/solid) (Liquid). Replace it by implementing `SferaDoc.TemplateEngine.Adapter`.

### Behaviour

```elixir
defmodule SferaDoc.TemplateEngine.Adapter do
  @callback parse(body :: String.t()) ::
              {:ok, parsed :: term()} | {:error, term()}

  @callback render(parsed :: term(), assigns :: map()) ::
              {:ok, html :: String.t()} | {:error, term()}
end
```

### Example

```elixir
defmodule MyApp.EExEngine do
  @behaviour SferaDoc.TemplateEngine.Adapter

  @impl true
  def parse(body) do
    # EEx compiles at parse time
    {:ok, EEx.compile_string(body)}
  end

  @impl true
  def render(compiled, assigns) do
    html = EEx.eval_compiled(compiled, assigns: assigns)
    {:ok, html}
  rescue
    e -> {:error, e}
  end
end
```

Configure:

```elixir
config :sfera_doc, :template_engine,
  adapter: MyApp.EExEngine
```

---

## Custom PDF Engine

The default PDF engine uses [`chromic_pdf`](https://hex.pm/packages/chromic_pdf). Replace it by implementing `SferaDoc.PdfEngine.Adapter`.

### Behaviour

```elixir
defmodule SferaDoc.PdfEngine.Adapter do
  @callback render(html :: String.t(), opts :: keyword()) ::
              {:ok, binary()} | {:error, term()}
end
```

### Example

```elixir
defmodule MyApp.WkHtmlToPdf do
  @behaviour SferaDoc.PdfEngine.Adapter

  @impl true
  def render(html, _opts) do
    with {:ok, path} <- Temp.path(%{suffix: ".pdf"}),
         :ok <- write_html_and_convert(html, path),
         {:ok, binary} <- File.read(path) do
      {:ok, binary}
    end
  end

  defp write_html_and_convert(html, output_path) do
    input = Temp.path!(%{suffix: ".html"})
    File.write!(input, html)
    case System.cmd("wkhtmltopdf", [input, output_path]) do
      {_, 0} -> :ok
      {reason, _} -> {:error, reason}
    end
  end
end
```

Configure:

```elixir
config :sfera_doc, :pdf_engine,
  adapter: MyApp.WkHtmlToPdf
```

---

## Store Adapter

See [Store Adapters](/docs/store-adapters) for implementing a custom template store.

## Object Store Adapter

See [PDF Caching](/docs/pdf-caching) for implementing a custom object store.
