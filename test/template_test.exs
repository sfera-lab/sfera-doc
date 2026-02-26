defmodule SferaDoc.TemplateTest do
  use ExUnit.Case, async: true

  alias SferaDoc.Template

  describe "validate_variables/2" do
    test "passes when no schema set" do
      t = %Template{name: "t", body: "x"}
      assert :ok = Template.validate_variables(t, %{})
    end

    test "passes when all required vars present" do
      t = %Template{name: "t", body: "x", variables_schema: %{"required" => ["name", "age"]}}
      assert :ok = Template.validate_variables(t, %{"name" => "Alice", "age" => 30})
    end

    test "returns missing vars when required vars absent" do
      t = %Template{name: "t", body: "x", variables_schema: %{"required" => ["name", "amount"]}}

      assert {:error, {:missing_variables, missing}} =
               Template.validate_variables(t, %{"name" => "Alice"})

      assert missing == ["amount"]
    end

    test "returns all missing vars" do
      t = %Template{name: "t", body: "x", variables_schema: %{"required" => ["a", "b", "c"]}}
      assert {:error, {:missing_variables, missing}} = Template.validate_variables(t, %{})
      assert Enum.sort(missing) == ["a", "b", "c"]
    end

    test "optional vars do not affect validation" do
      t = %Template{
        name: "t",
        body: "x",
        variables_schema: %{"required" => ["name"], "optional" => ["footer"]}
      }

      assert :ok = Template.validate_variables(t, %{"name" => "Alice"})
    end

    test "passes when schema has no required key" do
      t = %Template{name: "t", body: "x", variables_schema: %{"optional" => ["footer"]}}
      assert :ok = Template.validate_variables(t, %{})
    end

    test "passes when schema is an empty map" do
      t = %Template{name: "t", body: "x", variables_schema: %{}}
      assert :ok = Template.validate_variables(t, %{})
    end

    test "returns error when assigns is not a map" do
      t = %Template{name: "t", body: "x", variables_schema: %{"required" => ["name"]}}
      assert {:error, :assigns_must_be_map} = Template.validate_variables(t, nil)
      assert {:error, :assigns_must_be_map} = Template.validate_variables(t, ["name"])
      assert {:error, :assigns_must_be_map} = Template.validate_variables(t, "name")
    end

    test "atom-keyed assigns do not satisfy string required keys" do
      t = %Template{name: "t", body: "x", variables_schema: %{"required" => ["name"]}}

      assert {:error, {:missing_variables, ["name"]}} =
               Template.validate_variables(t, %{name: "Alice"})
    end
  end
end
