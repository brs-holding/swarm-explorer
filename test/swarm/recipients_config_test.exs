defmodule ZcashExplorer.RecipientsConfigTest do
  @moduledoc """
  The allocation file, in both of the shapes it exists in.

  `swarm-mainnet render` writes the node's allocation as
  `{"recipients":[{label,address,numerator}]}`; this explorer was written to
  read a bare `[{slot,label,address,percent}]`. On 2026-09-26 the mainnet was
  deployed with a second, hand-derived copy of the same three addresses to
  bridge that — two files saying the same thing, free to drift apart. Both
  shapes are now read, so one file can serve both.

  `async: false`: the allocation is application environment.
  """
  use ExUnit.Case, async: false

  alias ZcashExplorer.Swarm

  @key ZcashExplorer.Swarm

  # The live mainnet allocation, as the renderer writes it: labels, no slots,
  # `numerator` rather than `percent`.
  @rendered %{
    "recipients" => [
      %{
        "label" => "Core Development",
        "address" => "s3fLmEHc1xqs8KAe7QS7oupkhuGDjidV4eq",
        "numerator" => 8
      },
      %{
        "label" => "Grants & Ecosystem",
        "address" => "s3RiGvK5JzS8eh6ywN3K22f2LzDAhicgFuq",
        "numerator" => 4
      },
      %{
        "label" => "Community & Development Reserve",
        "address" => "s3g3pzQVhvVX17bzrrEN3vmcXZWSpj7KFVp",
        "numerator" => 8
      }
    ]
  }

  setup do
    original = Application.get_env(:zcash_explorer, @key, [])
    on_exit(fn -> Application.put_env(:zcash_explorer, @key, original) end)
    {:ok, original: original}
  end

  defp configure(%{original: original}, recipients) do
    Application.put_env(
      :zcash_explorer,
      @key,
      Keyword.put(original, :recipients, recipients)
    )
  end

  describe "unwrap/1" do
    test "takes the list out of either shape" do
      assert [%{"label" => "Core Development"} | _] = Swarm.unwrap(@rendered)
      assert Swarm.unwrap([%{"slot" => "ECC"}]) == [%{"slot" => "ECC"}]
      assert Swarm.unwrap(%{recipients: [:a]}) == [:a]
    end

    test "anything else is no allocation rather than a crash" do
      assert Swarm.unwrap(nil) == []
      assert Swarm.unwrap(%{"recipients" => "eight percent"}) == []
      assert Swarm.unwrap("[]") == []
    end
  end

  describe "the renderer's shape" do
    test "each entry lands in the slot its label names", ctx do
      configure(ctx, @rendered)

      assert [ecc, grants, reserve] = Swarm.recipients()
      assert ecc.slot == "ECC"
      assert grants.slot == "MajorGrants"
      assert reserve.slot == "ZcashFoundation"
    end

    test "numerator is read as the percentage", ctx do
      configure(ctx, @rendered)

      assert Swarm.recipient_for("ECC").percent == 8
      assert Swarm.recipient_for("Zcash Community Grants NU6").percent == 4
      assert Swarm.recipient_for("Zcash Foundation").percent == 8
    end

    test "the address page can still badge a destination", ctx do
      configure(ctx, @rendered)

      assert %{label: "Core Development", slot: "ECC"} =
               Swarm.recipient_for_address("s3fLmEHc1xqs8KAe7QS7oupkhuGDjidV4eq")
    end

    test "the two shapes describe the same allocation", ctx do
      slots = ["ECC", "MajorGrants", "ZcashFoundation"]

      bare =
        @rendered["recipients"]
        |> Enum.zip(slots)
        |> Enum.map(fn {r, slot} ->
          %{
            "slot" => slot,
            "label" => r["label"],
            "address" => r["address"],
            "percent" => r["numerator"]
          }
        end)

      configure(ctx, @rendered)
      from_wrapped = Swarm.recipients()

      configure(ctx, bare)
      assert Swarm.recipients() == from_wrapped
    end
  end

  describe "the bare array" do
    test "is read exactly as before", ctx do
      configure(ctx, [
        %{
          "slot" => "ECC",
          "label" => "Core Development",
          "address" => "s3fLmEHc1xqs8KAe7QS7oupkhuGDjidV4eq",
          "percent" => 8
        }
      ])

      assert [%{slot: "ECC", label: "Core Development", percent: 8, address: address}] =
               Swarm.recipients()

      assert address == "s3fLmEHc1xqs8KAe7QS7oupkhuGDjidV4eq"
    end

    test "upstream_slot is accepted as a slot name", ctx do
      configure(ctx, [%{"upstream_slot" => "MajorGrants", "label" => "Grants", "percent" => 4}])
      assert [%{slot: "MajorGrants", label: "Grants"}] = Swarm.recipients()
    end

    test "an empty allocation still renders the specification's defaults", ctx do
      configure(ctx, [])
      assert length(Swarm.recipients()) == 3
      assert Enum.all?(Swarm.recipients(), &is_nil(&1.address))
    end
  end
end
