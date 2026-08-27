defmodule AriesPaaS.Domain do
  @moduledoc """
  Ash control-plane domain for ARIES planning requests, observed solver runs,
  and provenance receipts.
  """

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AriesPaaS.PlanningRequest
    resource AriesPaaS.PlanRun
    resource AriesPaaS.PlanReceipt
  end
end

defmodule AriesPaaS.PlanningRequest do
  @moduledoc """
  An admitted planning intent projected as a public P-Plan `Plan`.

  PDDL/HDDL remains owned by ARIES; this resource stores identity, source paths,
  and explicit execution authority only.
  """

  use Ash.Resource,
    domain: AriesPaaS.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  r2rml do
    class_iri("http://purl.org/net/p-plan#Plan")
    subject_template("urn:aries:planning-request:{id}")
    table_name("aries_planning_requests")

    attribute_mappings([
      {:id, "http://purl.org/dc/terms/identifier"},
      {:domain_path, "http://purl.org/dc/terms/source"},
      {:problem_path, "http://purl.org/dc/terms/relation"},
      {:requested_at, "http://purl.org/dc/terms/created"}
    ])
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:domain_path, :problem_path, :authority]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :domain_path, :string, allow_nil?: false, public?: true
    attribute :problem_path, :string, allow_nil?: false, public?: true
    attribute :authority, :string, allow_nil?: false, public?: true
    create_timestamp :requested_at
  end
end

defmodule AriesPaaS.PlanRun do
  @moduledoc """
  One observed ARIES solver invocation, represented as a PROV-O `Activity`.
  """

  use Ash.Resource,
    domain: AriesPaaS.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  r2rml do
    class_iri("http://www.w3.org/ns/prov#Activity")
    subject_template("urn:aries:plan-run:{id}")
    table_name("aries_plan_runs")

    attribute_mappings([
      {:id, "http://purl.org/dc/terms/identifier"},
      {:started_at, "http://www.w3.org/ns/prov#startedAtTime"},
      {:ended_at, "http://www.w3.org/ns/prov#endedAtTime"}
    ])

    relationship_mappings([
      {:request, "http://www.w3.org/ns/prov#used"}
    ])
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:request_id, :started_at, :ended_at, :exit_code, :plan_text, :stdout]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :request_id, :uuid, allow_nil?: false, public?: true
    attribute :started_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :ended_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :exit_code, :integer, allow_nil?: false, public?: true
    attribute :plan_text, :string, allow_nil?: true, public?: true
    attribute :stdout, :string, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :request, AriesPaaS.PlanningRequest do
      source_attribute :request_id
      destination_attribute :id
      attribute_writable? true
    end
  end
end

defmodule AriesPaaS.PlanReceipt do
  @moduledoc """
  A receipted consequence of one solver invocation, represented as a PROV-O
  `Bundle`. Hashes and standing are operational evidence and intentionally do
  not invent new RDF vocabulary terms.
  """

  use Ash.Resource,
    domain: AriesPaaS.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  r2rml do
    class_iri("http://www.w3.org/ns/prov#Bundle")
    subject_template("urn:aries:plan-receipt:{id}")
    table_name("aries_plan_receipts")

    attribute_mappings([
      {:id, "http://purl.org/dc/terms/identifier"},
      {:generated_at, "http://www.w3.org/ns/prov#generatedAtTime"}
    ])

    relationship_mappings([
      {:run, "http://www.w3.org/ns/prov#wasGeneratedBy"}
    ])
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :run_id,
        :generated_at,
        :domain_sha256,
        :problem_sha256,
        :command_sha256,
        :plan_sha256,
        :stdout_sha256,
        :receipt_id,
        :standing
      ]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :run_id, :uuid, allow_nil?: false, public?: true
    attribute :generated_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :domain_sha256, :string, allow_nil?: false, public?: true
    attribute :problem_sha256, :string, allow_nil?: false, public?: true
    attribute :command_sha256, :string, allow_nil?: false, public?: true
    attribute :plan_sha256, :string, allow_nil?: true, public?: true
    attribute :stdout_sha256, :string, allow_nil?: false, public?: true
    attribute :receipt_id, :string, allow_nil?: false, public?: true
    attribute :standing, :string, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :run, AriesPaaS.PlanRun do
      source_attribute :run_id
      destination_attribute :id
      attribute_writable? true
    end
  end
end
