defmodule SferaDoc.TestSupportTest do
  use ExUnit.Case, async: false

  alias SferaDoc.TestSupport

  describe "reset_counters/0" do
    test "creates table if it doesn't exist" do
      # Ensure table doesn't exist
      table = :sfera_doc_test_counters

      if :ets.whereis(table) != :undefined do
        :ets.delete(table)
      end

      # Reset should create the table
      assert :ok = TestSupport.reset_counters()
      assert :ets.whereis(table) != :undefined
    end

    test "clears existing counters" do
      TestSupport.reset_counters()
      TestSupport.increment(:test_counter)
      assert TestSupport.get_counter(:test_counter) == 1

      # Reset should clear counters
      TestSupport.reset_counters()
      assert TestSupport.get_counter(:test_counter) == 0
    end
  end

  describe "increment/1" do
    setup do
      TestSupport.reset_counters()
      :ok
    end

    test "increments counter from 0" do
      assert :ok = TestSupport.increment(:my_counter)
      assert TestSupport.get_counter(:my_counter) == 1
    end

    test "increments counter multiple times" do
      TestSupport.increment(:my_counter)
      TestSupport.increment(:my_counter)
      TestSupport.increment(:my_counter)
      assert TestSupport.get_counter(:my_counter) == 3
    end

    test "maintains separate counters" do
      TestSupport.increment(:counter_a)
      TestSupport.increment(:counter_a)
      TestSupport.increment(:counter_b)

      assert TestSupport.get_counter(:counter_a) == 2
      assert TestSupport.get_counter(:counter_b) == 1
    end

    test "creates table if it doesn't exist" do
      table = :sfera_doc_test_counters
      :ets.delete(table)

      # Increment should create table if needed
      assert :ok = TestSupport.increment(:test)
      assert TestSupport.get_counter(:test) == 1
    end
  end

  describe "get_counter/1" do
    setup do
      TestSupport.reset_counters()
      :ok
    end

    test "returns 0 for non-existent counter" do
      assert TestSupport.get_counter(:nonexistent) == 0
    end

    test "returns correct value for existing counter" do
      TestSupport.increment(:existing)
      TestSupport.increment(:existing)
      assert TestSupport.get_counter(:existing) == 2
    end

    test "creates table if it doesn't exist" do
      table = :sfera_doc_test_counters
      :ets.delete(table)

      # get_counter should create table if needed
      assert TestSupport.get_counter(:test) == 0
      assert :ets.whereis(table) != :undefined
    end
  end
end
