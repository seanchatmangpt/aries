defmodule AriesPaaS.Steps.Admit do
  @moduledoc false
  use Reactor.Step

  @impl Reactor.Step
  def run(%{request: request}, _context, _options) do
    with {:ok, domain_path} <- fetch_path(request, :domain_path),
         {:ok, problem_path} <- fetch_path(request, :problem_path),
         :ok <- regular_file(domain_path, :domain_path),
         :ok <- regular_file(problem_path, :problem_path) do
      {:ok,
       request
       |> Map.put(:domain_path, Path.expand(domain_path))
       |> Map.put(:problem_path, Path.expand(problem_path))}
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
  def run(%{request: request}, _context, _options) do
    case AriesPaaS.semantic_r2rml() do
      {:ok, turtle} when is_binary(turtle) ->
        {:ok,
         %{
           request: request,
           semantic_r2rml_sha256: AriesPaaS.Solver.sha256(turtle)
         }}

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
        %{authorized: %{request: request, semantic_r2rml_sha256: semantic_sha}},
        _context,
        _options
      ) do
    case AriesPaaS.Solver.solve(request) do
      {:ok, result} ->
        {:ok, attach_semantic_receipt(result, semantic_sha)}

      {:error, %{receipt: _receipt, result: result} = error} ->
        {:error,
         error
         |> Map.put(:result, attach_semantic_receipt(result, semantic_sha))
         |> Map.update!(:receipt, &Map.put(&1, :semantic_r2rml_sha256, semantic_sha))}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp attach_semantic_receipt(result, semantic_sha) do
    put_in(result, [:receipt, :semantic_r2rml_sha256], semantic_sha)
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
        {:error, receipt_refusal(:plan_hash_mismatch)}

      not is_binary(receipt.semantic_r2rml_sha256) ->
        {:error, receipt_refusal(:missing_semantic_mapping_identity)}

      receipt.exit_code != 0 ->
        {:error, receipt_refusal(:nonzero_exit_cannot_receive_alive_standing)}

      true ->
        {:ok, result}
    end
  end

  defp receipt_refusal(reason) do
    %AriesPaaS.Refusal{
      type: :receipt_verification_failed,
      message: "REFUSED: execution receipt did not verify",
      details: %{reason: reason}
    }
  end
end

defmodule AriesPaaS.SolveReactor do
  @moduledoc """
  BRCE-aligned planning reactor.

  `admit` and `semantic_admission` are SELECT/CONSTRUCT only. `authorize`
  manufactures explicit DO authority. `actuate` is the only solver execution
  edge, and `verify_receipt` refuses any unbound consequence.
  """

  use Reactor

  input(:request)

  step :admit, AriesPaaS.Steps.Admit do
    argument :request, input(:request)
  end

  step :semantic_admission, AriesPaaS.Steps.SemanticAdmission do
    argument :request, result(:admit)
  end

  step :authorize, AriesPaaS.Steps.Authorize do
    argument :semantic, result(:semantic_admission)
  end

  step :actuate, AriesPaaS.Steps.Actuate do
    argument :authorized, result(:authorize)
    max_retries 0
  end

  step :verify_receipt, AriesPaaS.Steps.VerifyReceipt do
    argument :result, result(:actuate)
  end

  return :verify_receipt
end
