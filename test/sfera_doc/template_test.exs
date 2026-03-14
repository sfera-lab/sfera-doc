defmodule SferaDoc.TemplateTest do
  use ExUnit.Case, async: true

  alias SferaDoc.Template

  describe "validate_variables/2" do
    test "returns :ok when no variables_schema is set" do
      template = %Template{name: "test", body: "body", variables_schema: nil}
      assert Template.validate_variables(template, %{}) == :ok
      assert Template.validate_variables(template, %{"any" => "value"}) == :ok
    end

    test "returns :ok when no required variables" do
      template = %Template{name: "test", body: "body", variables_schema: %{}}
      assert Template.validate_variables(template, %{}) == :ok
    end

    test "returns :ok when all required variables are present" do
      template = %Template{
        name: "test",
        body: "body",
        variables_schema: %{"required" => ["name", "email"]}
      }

      assigns = %{"name" => "Alice", "email" => "alice@example.com", "extra" => "ok"}
      assert Template.validate_variables(template, assigns) == :ok
    end

    test "returns error when required variables are missing" do
      template = %Template{
        name: "test",
        body: "body",
        variables_schema: %{"required" => ["name", "email"]}
      }

      assert {:error, {:missing_variables, missing}} =
               Template.validate_variables(template, %{})

      assert Enum.sort(missing) == ["email", "name"]
    end

    test "returns error when some required variables are missing" do
      template = %Template{
        name: "test",
        body: "body",
        variables_schema: %{"required" => ["name", "email", "age"]}
      }

      assigns = %{"name" => "Alice"}

      assert {:error, {:missing_variables, missing}} =
               Template.validate_variables(template, assigns)

      assert Enum.sort(missing) == ["age", "email"]
    end

    test "returns error when assigns is not a map" do
      template = %Template{name: "test", body: "body"}

      assert {:error, :assigns_must_be_map} = Template.validate_variables(template, "not a map")
      assert {:error, :assigns_must_be_map} = Template.validate_variables(template, [:list])
      assert {:error, :assigns_must_be_map} = Template.validate_variables(template, 123)
      assert {:error, :assigns_must_be_map} = Template.validate_variables(template, nil)
    end

    test "handles invalid required field in schema gracefully" do
      # When "required" is not a list, should treat as empty
      template = %Template{
        name: "test",
        body: "body",
        variables_schema: %{"required" => "not a list"}
      }

      assert Template.validate_variables(template, %{}) == :ok
    end

    test "handles schema with optional variables" do
      template = %Template{
        name: "test",
        body: "body",
        variables_schema: %{
          "required" => ["name"],
          "optional" => ["footer", "header"]
        }
      }

      # Only required variables are validated
      assert Template.validate_variables(template, %{"name" => "Alice"}) == :ok
      assert {:error, {:missing_variables, ["name"]}} = Template.validate_variables(template, %{})
    end
  end

  describe "struct creation" do
    test "requires name and body" do
      assert %Template{name: "test", body: "content"}
    end

    test "allows optional fields" do
      template = %Template{
        id: "123",
        name: "test",
        body: "content",
        version: 1,
        is_active: true,
        variables_schema: %{"required" => ["name"]},
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }

      assert template.id == "123"
      assert template.version == 1
      assert template.is_active == true
    end
  end
end
