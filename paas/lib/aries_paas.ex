defmodule AriesPaaS.Refusal do
  @moduledoc "Typed fail-closed refusal emitted before ARIES actuation."
  defexception [:type, :message, details: %{}]
end

defmodule AriesPaaS do
  @moduledoc """
  Semantic PaaS facade around the ARIES Rust planner.

  The Rust solver remains the planning kernel. Ash supplies the control-plane
  resource model, AshR2RML compiles that model to public R2RML/PROV/P-Plan
  semantics, Reactor sequences admission/authority/actuation/verification, and
  ggen manufactures static capability projections at construction time.
  """

  @semantic_resources [
    AriesPaaS.PlanningRequest,
    AriesPaaS.PlanRun,
    AriesPaaS.PlanReceipt
  ]

  @spec resources() :: [module()]
  def resources, do: @semantic_resources

  @spec semantic_r2rml() :: {:ok, String.t()} | {:error, term()}
  def semantic_r2rml do
    Reactor.run(AshR2RML.Reactor.Pipeline, %{
      resources: @semantic_resources,
      actor: nil,
      observations: [],
      metadata: %{system: :aries_paas}
    })
  end

  @spec solve(map()) :: {:ok, map()} | {:error, term()}
  def solve(request) when is_map(request) do
    Reactor.run(AriesPaaS.SolveReactor, %{request: request})
  end
end
