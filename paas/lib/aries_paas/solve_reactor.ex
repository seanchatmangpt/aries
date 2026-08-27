defmodule AriesPaaS.Steps.Admit do
  @moduledoc false
  use Reactor.Step

  @impl Reactor.Step
  def run(%{request: request}, _context, _options) do
    with {:ok, domain_path} <- fetch_path(request, :domain_path),
         {:ok, problem_path} <- fetch_path(request, :problem_path),
         :ok <- regular_file(domain_path, :domain_path),
         :ok <- regular_file(problem_path, :problem_path) do
      normalized =
        request
        |> Map.put(:domain_path, Path.expand(domain_path))
        |> Map.put(:problem_path, Path.expand(problem_path))

      attrs = %{
        domain_path: normalized.domain_path,
        problem_path: normalized.problem_path,
        authority: authority_for_storage(Map.get(normalized, :authority))
      }

      case Ash.create(Ash.Changeset.for_create(AriesPaaS.PlanningRequest, :create, attrs)) do
        {:ok, planning_request} ->
          {:ok, %{request: normalized, planning_request: planning_request}}

        {:error, reason} ->
          {:error, refusal(:ash_request_admission_failed, %{reason: inspect(reason)})}
      end
    end
  end

  defp fetch_path(request, key) do
    case Map.fetch(request, key) do
      {:ok, value} when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, refusal(:missing_required_input, %{field: key})}
    end
  end

  defp regular_file(path, field) do
    if File.regular?(path) do
      :ok
    else
      {:error, refusal(:input_not_regular_file, %{field: field, path: path})}
    end
  end

  defp authority_for_storage(value) when is_atom(value), do: Atom.to_string(value)
  defp authority_for_storage(value) when is_binary(value), do: value
  defp authority_for_storage(nil), do: nil
  defp authority_for_storage(value), do: inspect(value)

  defp refusal(type, details) do
    %AriesPaaS.Refusal{
      type: type,
      message: "REFUSED before ARIES actuation",
      details: details
    }
  end
end

defmodule AriesPaaS.Steps.SemanticAdmission do
  @moduledoc false
  use Reactor.Step

  @impl Reactor.Step
  def run(%{admitted: admitted}, _context, _options) do
    case AriesPaaS.semantic_r2rml() do
      {:ok, turtle} when is_binary(turtle) ->
        {:ok, Map.put(admitted, :semantic_r2rml_sha256, AriesPaaS.Solver.sha256(turtle))}

      {:error, reason} ->
        {:error,
         %AriesPaaS.Refusal{
           type: :semantic_alignment_failed,
           message: "REFUSED: AshR2RML semantic admission failed",
           details: %{reason: inspect(reason)}
         }}
    end
  end
end

defmodule AriesPaaS.Steps.Authorize do
  @moduledoc false
  use Reactor.Step

  @impl Reactor.Step
  def run(%{semantic: %{request: request} = semantic}, _context, _options) do
    case Map.get(request, :authority) do
      authority when authority in [:execute, "execute"] ->
        {:ok, semantic}

      observed ->
        {:error,
         %AriesPaaS.Refusal{
           type: :missing_execute_authority,
           message: "REFUSED: explicit execute authority is required",
           details: %{observed: observed}
         }}
    end
  end
end

defmodule AriesPaaS.Steps.Actuate do
  @moduledoc false
  use Reactor.Step

  @impl Reactor.Step
  def run(
        %{
          authorized: %{
            request: request,
            planning_request: planning_request,
            semantic_r2rml_sha256: semantic_sha
          }
        },
        _context,
        _options
      ) do
    case AriesPaaS.Solver.solve(request) do
      {:ok, result} ->
        {:ok, attach_context(result, planning_request, semantic_sha)}

      {:error, %{receipt: _receipt, result: result} = error} ->
        {:ok,
         result
         |> attach_context(planning_request, semantic_sha)
         |> Map.put(:solver_error, Map.drop(error, [:result, :receipt]))}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp attach_context(result, planning_request, semantic_sha) do
    result
    |> put_in([:receipt, :semantic_r2rml_sha256], semantic_sha)
    |> Map.put(:planning_request, planning_request)
  end
end

defmodule AriesPaaS.Steps.PersistEvidence do
  @moduledoc false
  use Reactor.Step

  @impl Reactor.Step
  def run(%{result: result}, _context, _options) do
    receipt = result.receipt

    run_attrs = %{
      request_id: result.planning_request.id,
      started_at: result.started_at,
      ended_at: result.ended_at,
      exit_code: result.exit_code,
      plan_text: result.plan,
      stdout: result.stdout
    }

    with {:ok, plan_run} <-
           Ash.create(Ash.Changeset.for_create(AriesPaaS.PlanRun, :create, run_attrs)),
         {:ok, plan_receipt} <- create_receipt(plan_run, result, receipt) do
      {:ok,
       result
       |> Map.put(:plan_run, plan_run)
       |> Map.put(:plan_receipt, plan_receipt)}
    else
      {:error, reason} ->
        {:error,
         %AriesPaaS.Refusal{
           type: :ash_evidence_persistence_failed,
           message: "REFUSED: observed ARIES consequence could not be persisted through Ash",
           details: %{reason: inspect(reason), receipt_id: receipt.receipt_id}
         }}
    end
  end

  defp create_receipt(plan_run, result, receipt) do
    attrs = %{
      run_id: plan_run.id,
      generated_at: result.ended_at,
      domain_sha256: receipt.domain_sha256,
      problem_sha256: receipt.problem_sha256,
      command_sha256: receipt.command_sha256,
      plan_sha256: receipt.plan_sha256,
      stdout_sha256: receipt.stdout_sha256,
      semantic_r2rml_sha256: receipt.semantic_r2rml_sha256,
      receipt_id: receipt.receipt_id,
      standing: receipt.standing
    }

    Ash.create(Ash.Changeset.for_create(AriesPaaS.PlanReceipt, :create, attrs))
  end
end

defmodule AriesPaaS.Steps.VerifyReceipt do
  @moduledoc false
  use Reactor.Step

  @impl Reactor.Step
  def run(%{result: %{plan: plan, receipt: receipt} = result}, _context, _options) do
    expected_plan_sha = if is_binary(plan), do: AriesPaaS.Solver.sha256(plan), else: nil

    cond do
      receipt.plan_sha256 != expected_plan_sha ->
        {:error, receipt_refusal(:plan_hash_mismatch, receipt)}

      not is_binary(receipt.semantic_r2rml_sha256) ->
        {:error, receipt_refusal(:missing_semantic_mapping_identity, receipt)}

      result.plan_receipt.receipt_id != receipt.receipt_id ->
        {:error, receipt_refusal(:ash_receipt_identity_mismatch, receipt)}

      result.plan_receipt.run_id != result.plan_run.id ->
        {:error, receipt_refusal(:ash_receipt_run_mismatch, receipt)}

      result.plan_run.request_id != result.planning_request.id ->
        {:error, receipt_refusal(:ash_run_request_mismatch, receipt)}

      receipt.exit_code != 0 ->
        {:error, receipt_refusal(:aries_nonzero_exit, receipt)}

      true ->
        {:ok, result}
    end
  end

  defp receipt_refusal(reason, receipt) do
    %AriesPaaS.Refusal{
      type: :receipt_verification_failed,
      message: "REFUSED: execution receipt did not verify as an ALIVE consequence",
      details: %{
        reason: reason,
        receipt_id: receipt.receipt_id,
        observed_standing: receipt.standing
      }
    }
  end
end

defmodule AriesPaaS.SolveReactor do
  @moduledoc """
  BRCE-aligned planning reactor.

  `admit` persists the intent through Ash. `semantic_admission` compiles and
  verifies the AshR2RML semantic closure. `authorize` manufactures explicit DO
  authority. `actuate` is the only solver execution edge. `persist_evidence`
  records the observed run and receipt through Ash before `verify_receipt`
  decides standing.
  """

  use Reactor

  input(:request)

  step :admit, AriesPaaS.Steps.Admit do
    argument :request, input(:request)
  end

  step :semantic_admission, AriesPaaS.Steps.SemanticAdmission do
    argument :admitted, result(:admit)
  end

  step :authorize, AriesPaaS.Steps.Authorize do
    argument :semantic, result(:semantic_admission)
  end

  step :actuate, AriesPaaS.Steps.Actuate do
    argument :authorized, result(:authorize)
    max_retries 0
  end

  step :persist_evidence, AriesPaaS.Steps.PersistEvidence do
    argument :result, result(:actuate)
  end

  step :verify_receipt, AriesPaaS.Steps.VerifyReceipt do
    argument :result, result(:persist_evidence)
  end

  return :verify_receipt
end
