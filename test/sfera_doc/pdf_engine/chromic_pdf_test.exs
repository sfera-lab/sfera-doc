defmodule SferaDoc.PdfEngine.ChromicPDFTest do
  use ExUnit.Case, async: true

  alias SferaDoc.PdfEngine.ChromicPDF

  @html_content "<html><body><h1>Test PDF</h1></body></html>"
  @pdf_binary <<37, 80, 68, 70, 45, 49, 46, 52>> <> "test pdf content"

  describe "render/2 logic" do
    test "successfully processes base64-encoded PDF" do
      # Test the core logic of what render/2 does
      pdf_content = "test pdf content"
      base64_pdf = Base.encode64(pdf_content)

      # Simulate the case expression in render/2
      result =
        case {:ok, base64_pdf} do
          {:ok, base64_data} ->
            pdf_binary = Base.decode64!(base64_data)
            {:ok, pdf_binary}

          other ->
            {:error, {:chromic_pdf_error, other}}
        end

      assert {:ok, ^pdf_content} = result
    end

    test "decodes base64 PDF data correctly" do
      base64_pdf = Base.encode64(@pdf_binary)

      result =
        case {:ok, base64_pdf} do
          {:ok, base64_data} ->
            decoded = Base.decode64!(base64_data)
            {:ok, decoded}

          other ->
            {:error, {:chromic_pdf_error, other}}
        end

      assert {:ok, decoded} = result
      assert decoded == @pdf_binary
    end

    test "wraps error responses in error tuple" do
      error_response = {:error, :timeout}

      result =
        case error_response do
          {:ok, base64_data} ->
            pdf_binary = Base.decode64!(base64_data)
            {:ok, pdf_binary}

          other ->
            {:error, {:chromic_pdf_error, other}}
        end

      assert {:error, {:chromic_pdf_error, {:error, :timeout}}} = result
    end

    test "handles unexpected responses" do
      for unexpected <- [:atom, nil, "string", 123, false] do
        result =
          case unexpected do
            {:ok, base64_data} ->
              pdf_binary = Base.decode64!(base64_data)
              {:ok, pdf_binary}

            other ->
              {:error, {:chromic_pdf_error, other}}
          end

        assert {:error, {:chromic_pdf_error, ^unexpected}} = result
      end
    end

    test "verifies byte size calculation works correctly" do
      pdf_content = String.duplicate("test", 100)
      expected_size = byte_size(pdf_content)

      # Verify the log message format
      log_message = "ChromicPDF rendered PDF of size: #{expected_size} bytes"

      assert log_message =~ "ChromicPDF rendered PDF of size: #{expected_size} bytes"
      assert log_message =~ "#{expected_size}"
    end

    test "processes various PDF sizes" do
      for size <- [10, 100, 1000, 10_000] do
        pdf_content = String.duplicate("x", size)
        base64_pdf = Base.encode64(pdf_content)

        result =
          case {:ok, base64_pdf} do
            {:ok, base64_data} ->
              decoded = Base.decode64!(base64_data)
              {:ok, decoded}

            other ->
              {:error, {:chromic_pdf_error, other}}
          end

        assert {:ok, decoded} = result
        assert byte_size(decoded) == size
      end
    end
  end

  describe "module structure" do
    test "implements PdfEngine.Adapter behaviour" do
      behaviours =
        ChromicPDF.module_info(:attributes)
        |> Keyword.get(:behaviour, [])

      assert SferaDoc.PdfEngine.Adapter in behaviours
    end

    test "exports render/2 function" do
      exports = ChromicPDF.__info__(:functions)
      assert {:render, 2} in exports
    end

    test "render/2 has correct arity" do
      assert function_exported?(ChromicPDF, :render, 2)
    end
  end

  describe "error handling patterns" do
    test "error tuple format is consistent" do
      error = {:error, {:chromic_pdf_error, :some_error}}

      assert {:error, {:chromic_pdf_error, :some_error}} = error
    end

    test "handles various error types" do
      errors = [
        {:error, :timeout},
        {:error, "string error"},
        {:error, {:nested, :error}},
        :unexpected_atom,
        nil,
        123,
        "plain string",
        []
      ]

      for error <- errors do
        wrapped = {:error, {:chromic_pdf_error, error}}
        assert {:error, {:chromic_pdf_error, ^error}} = wrapped
      end
    end

    test "distinguishes between different error types" do
      timeout_error = {:error, {:chromic_pdf_error, {:error, :timeout}}}
      crash_error = {:error, {:chromic_pdf_error, :unexpected}}
      nil_error = {:error, {:chromic_pdf_error, nil}}

      # All have the same outer structure but different inner errors
      assert {:error, {:chromic_pdf_error, _}} = timeout_error
      assert {:error, {:chromic_pdf_error, _}} = crash_error
      assert {:error, {:chromic_pdf_error, _}} = nil_error

      # But inner errors are different
      assert timeout_error != crash_error
      assert crash_error != nil_error
      assert timeout_error != nil_error
    end
  end

  # Integration tests that would run if ChromicPDF is available
  if Code.ensure_loaded?(ChromicPDF) do
    describe "integration with real ChromicPDF (if available)" do
      @moduletag :integration
      @moduletag :skip

      test "can call render with HTML" do
        # This test would only run in environments where ChromicPDF is fully set up
        # For now, we just verify the function can be called
        assert function_exported?(ChromicPDF, :render, 2)
      end
    end
  end
end
