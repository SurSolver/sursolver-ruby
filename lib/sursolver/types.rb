# frozen_string_literal: true

module SurSolver
  # One getTaskResult answer: status is "processing" or "ready" (with solution). Solution keys
  # differ per type ("token", "gRecaptchaResponse", "cf_clearance", "cookies", ...) and are passed
  # through untouched. Tokens are single-use.
  TaskResult = Struct.new(:status, :solution, keyword_init: true) do
    def ready?
      status == "ready"
    end

    def processing?
      status == "processing"
    end
  end

  # What solve returns.
  SolveResult = Struct.new(:task_id, :solution, keyword_init: true)

  # One entry of GET /v1/task-types. proxy is "none", "optional" or "required"; required lists
  # groups of accepted spellings (one name per group); any_of lists alternatives.
  TaskTypeInfo = Struct.new(
    :page_slug, :display_name, :task_type, :task_type_proxyless, :aliases, :proxy, :required,
    :any_of, :optional, :solution_keys, keyword_init: true
  )

  # The public task-type catalog.
  TaskTypeCatalog = Struct.new(:task_types, :error_codes, keyword_init: true)

  # One entry of GET /v1/services. price_per_request is the USD price per task as a decimal string.
  ServiceInfo = Struct.new(:id, :slug, :display_name, :price_per_request, :status, :avg_latency_ms, keyword_init: true)
end
