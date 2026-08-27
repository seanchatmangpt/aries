defmodule AriesPaaSE2ETest do
  use ExUnit.Case, async: false

  @repo_root Path.expand("../..", __DIR__)
  @domain_path Path.join(@repo_root, "planning/problems/pddl/tests/gripper.dom.pddl")
  @problem_path Path.join(@repo_root, "planning/problems/pddl/tests/gripper.pb.pddl")
  @aries_binary Path.join(@repo_root, "target/debug/aries-plan")

  test "Ash resource executes and public semantic closure compiles through AshR2RML/Reactor" do
    changeset =
      Ash.Changeset.for_create(AriesPaaS.PlanningRequest, :create, %{
        domain_path: @domain_path,
        problem_path: @problem_path,
        authority: "execute"
      })

    assert {:ok, request} = Ash.create(changeset)
    assert request.domain_path == @domain_path

    assert {:ok, turtle} = AriesPaaS.semantic_r2rml()
    assert turtle =~ "http://purl.org/net/p-plan#Plan"
    assert turtle =~ "http://www.w3.org/ns/prov#Activity"
    assert turtle =~ "http://www.w3.org/ns/prov#Bundle"
  end

  test "ggen manufactures the capability catalog from the public ontology graph" do
    capabilities = AriesPaaS.Generated.CapabilityCatalog.all()

    assert Enum.map(capabilities, & &1.id) == [
             "authorize",
             "semantic_admission",
             "solve",
             "verify_receipt"
           ]

    assert AriesPaaS.Generated.CapabilityCatalog.fetch("solve").phase == "DO"
    assert AriesPaaS.Generated.CapabilityCatalog.fetch("authorize").phase == "SELECT"
  end

  test "exact admitted Gripper subject reaches ARIES and persists a verified Ash receipt chain" do
    assert File.regular?(@aries_binary)

    assert {:ok, result} =
             AriesPaaS.solve(%{
               domain_path: @domain_path,
               problem_path: @problem_path,
               authority: :execute,
               binary: @aries_binary
             })

    assert result.exit_code == 0
    assert is_binary(result.plan)
    assert byte_size(result.plan) > 0
    assert result.receipt.standing == "ALIVE"
    assert result.receipt.plan_sha256 == AriesPaaS.Solver.sha256(result.plan)
    assert is_binary(result.receipt.semantic_r2rml_sha256)

    assert result.planning_request.authority == "execute"
    assert result.plan_run.request_id == result.planning_request.id
    assert result.plan_receipt.run_id == result.plan_run.id
    assert result.plan_receipt.receipt_id == result.receipt.receipt_id

    assert result.plan_receipt.semantic_r2rml_sha256 ==
             result.receipt.semantic_r2rml_sha256

    File.mkdir_p!("tmp")

    File.write!(
      "tmp/aries_paas_receipt.json",
      Jason.encode!(result.receipt, pretty: true)
    )
  end

  test "DO path is refused without explicit execute authority" do
    assert {:error, _reason} =
             AriesPaaS.solve(%{
               domain_path: @domain_path,
               problem_path: @problem_path,
               authority: :observe,
               binary: @aries_binary
             })
  end
end
