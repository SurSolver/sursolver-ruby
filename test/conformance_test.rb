# frozen_string_literal: true

# Runs the vendored language-neutral conformance scenarios (conformance/README.md) with a
# scripted fake transport, a virtual clock and a fixed random source.

require_relative "test_helper"

class ConformanceTest < Minitest::Test
  ROOT = File.expand_path("../conformance", __dir__)

  # Records sleeps in milliseconds and advances virtual time.
  class VirtualClock
    attr_reader :sleeps

    def initialize
      @now = 0.0
      @sleeps = []
    end

    attr_reader :now

    def sleep(seconds)
      @sleeps << (seconds * 1000).round
      @now += seconds
    end
  end

  # Replays the scenario script and records mismatches instead of raising them into the client.
  class ScriptedTransport
    attr_reader :requests, :failures

    def initialize(script)
      @script = script
      @requests = []
      @failures = []
    end

    def call(request)
      @requests << request
      step = @requests.length
      entry = @script[step - 1] or return mismatch(step, "unexpected #{request.method} #{request.url}")
      expected = entry["expect"]
      uri = URI(request.url)
      unless expected["method"] == request.method && expected["path"] == uri.path
        return mismatch(step, "expected #{expected["method"]} #{expected["path"]}, got #{request.method} #{uri.path}")
      end
      return mismatch(step, "unexpected query") if expected["noQuery"] && uri.query
      if expected.key?("json")
        body = JSON.parse(request.body.to_s)
        return mismatch(step, "body #{request.body} != #{JSON.generate(expected["json"])}") unless body == expected["json"]
      end
      headers = request.headers.transform_keys(&:downcase)
      (expected["headers"] || {}).each do |name, want|
        actual = headers[name]
        matches = !actual.nil? && (want.is_a?(Hash) ? Regexp.new(want["matches"]).match?(actual) : actual == want)
        return mismatch(step, "header #{name} mismatch: #{actual.inspect}") unless matches
      end
      case entry["fail"]
      when nil then nil
      when "request_timeout" then raise Net::ReadTimeout
      when "connection_reset" then raise Errno::ECONNRESET
      else raise EOFError, "end of file reached"
      end
      respond(entry["respond"])
    end

    private

    def mismatch(step, message)
      @failures << "request #{step}: #{message}"
      raise IOError, "harness mismatch"
    end

    def respond(respond)
      status = respond.fetch("status", 200)
      if respond["respondFrom"]
        fixture = JSON.parse(File.read(File.join(ROOT, "recorded", respond["respondFrom"])))["response"]
        status = fixture["status"] unless respond.key?("status")
        body = fixture["body_is_json"] ? JSON.generate(fixture["body"]) : fixture["body"]
        return SurSolver::Response.new(status: status, body: body)
      end
      return SurSolver::Response.new(status: status, body: JSON.generate(respond["json"])) if respond.key?("json")

      SurSolver::Response.new(status: status, body: respond.fetch("text", ""))
    end
  end

  def self.scenario_files
    Dir[File.join(ROOT, "scenarios", "*.json")].sort
  end

  # The README key rule: lowercase without underscores, except inside a solution.
  def normalize(value, inside_solution = false)
    case value
    when Array then value.map { |v| normalize(v, inside_solution) }
    when Hash
      return value if inside_solution

      value.to_h { |k, v| [k.to_s.delete("_").downcase, normalize(v, k.to_s == "solution")] }
    else value
    end
  end

  def json_equal?(a, b)
    case a
    when Numeric then b.is_a?(Numeric) && a.to_f == b.to_f
    when Array then b.is_a?(Array) && a.length == b.length && a.zip(b).all? { |x, y| json_equal?(x, y) }
    when Hash then b.is_a?(Hash) && a.length == b.length && a.all? { |k, v| b.key?(k) && json_equal?(v, b[k]) }
    else a == b
    end
  end

  # The result in wire spelling (struct members are snake_case; solutions untouched).
  def to_wire(value)
    case value
    when SurSolver::TaskResult
      value.solution.nil? ? { "status" => value.status } : { "status" => value.status, "solution" => value.solution }
    when Struct then value.to_h.to_h { |k, v| [k.to_s, to_wire(v)] }
    when Array then value.map { |v| to_wire(v) }
    else value
    end
  end

  def pointer_get(root, pointer)
    pointer.split("/").drop(1).reduce(root) do |current, raw|
      segment = raw.gsub("~1", "/").gsub("~0", "~")
      current.is_a?(Array) ? current[segment.to_i] : current[segment]
    end
  end

  def error_view(error)
    fields = {}
    return ["unexpected #{error.class}: #{error.message}", fields] unless error.is_a?(SurSolver::Error)

    fields["operation"] = error.operation if error.operation
    case error
    when SurSolver::SolveTimeoutError
      fields["taskId"] = error.task_id
      fields["lastErrorType"] = error.last_error && error_view(error.last_error).first
    when SurSolver::TransportError
      fields["mayHaveCreatedTask"] = error.may_have_created_task?
      fields["status"] = error.status if error.status
      fields["serverCode"] = error.server_code if error.server_code
      fields["retryAfterSeconds"] = error.retry_after_seconds if error.retry_after_seconds
    when SurSolver::ApiError
      fields.merge!("code" => error.code, "description" => error.description, "retryable" => error.retryable?,
                    "taskId" => error.task_id, "supportedUserAgents" => error.supported_user_agents)
    end
    [error.class.name.split("::").last, fields]
  end

  def run_scenario(sc)
    call = sc["call"]
    args = call["args"] || {}
    expect = sc["expect"]
    script = sc["script"] || []
    clock = VirtualClock.new
    transport = ScriptedTransport.new(script)
    random = sc.fetch("random", 0)
    options = { transport: transport, clock: clock, random: -> { random } }
    api_key = TEST_API_KEY
    (sc["client"] || {}).each do |name, value|
      case name
      when "apiKey" then api_key = value
      when "baseUrl" then options[:base_url] = value
      when "requestTimeoutMs" then options[:request_timeout] = value / 1000.0
      when "pollIntervalMs" then options[:poll_interval] = value / 1000.0
      when "solveTimeoutMs" then options[:solve_timeout] = value / 1000.0
      when "maxSubmitRetries" then options[:max_submit_retries] = value
      when "appId" then options[:app_id] = value
      when "userAgentSuffix" then options[:user_agent_suffix] = value
      else flunk "unknown client option #{name}"
      end
    end

    created = []
    result = nil
    error = nil
    begin
      client = SurSolver::Client.new(api_key, **options)
      case call["method"]
      when "construct" then nil
      when "createTask" then result = client.create_task(args["task"])
      when "getTaskResult" then result = client.get_task_result(args["taskId"])
      when "getBalance" then result = client.get_balance
      when "listTaskTypes" then result = client.list_task_types
      when "listServices" then result = client.list_services
      when "solve"
        solve_options = { on_task_created: ->(id) { created << id } }
        solve_options[:poll_interval] = args["pollIntervalMs"] / 1000.0 if args.key?("pollIntervalMs")
        solve_options[:solve_timeout] = args["solveTimeoutMs"] / 1000.0 if args.key?("solveTimeoutMs")
        result = client.solve(args["task"], **solve_options)
      else flunk "unknown call #{call["method"]}"
      end
    rescue SurSolver::Error => e
      error = e
    end

    assert_empty transport.failures, "harness"
    assert_equal script.length, transport.requests.length, "scripted requests consumed"
    assert_equal expect["sleeps"], clock.sleeps, "sleeps" if expect.key?("sleeps")
    assert_equal expect["lastTaskId"], created.last, "onTaskCreated" if expect.key?("lastTaskId")

    outcome = expect["outcome"] || {}
    if (want = outcome["error"])
      refute_nil error, "expected #{want["type"]}, got #{result.inspect}"
      type, fields = error_view(error)
      assert_equal want["type"], type, error.inspect
      want.each do |name, value|
        next if %w[type messageIncludes messageExcludes].include?(name)

        assert fields.key?(name) && json_equal?(value, fields[name]), "#{name} = #{fields[name].inspect}, want #{value.inspect}"
      end
      rendered = "#{error.message}\n#{error.full_message(highlight: false)}\n#{error.inspect}"
      (want["messageIncludes"] || []).each { |text| assert_includes rendered, text }
      (want["messageExcludes"] || []).each { |text| refute_includes rendered, text }
    else
      assert_nil error, "unexpected error: #{error&.message}"
      wire = to_wire(result)
      if outcome.key?("ok")
        assert json_equal?(normalize(outcome["ok"]), normalize(wire)), "result #{wire.inspect}, want #{outcome["ok"].inspect}"
      end
      (expect["outcomeSubset"] || []).each do |check|
        value = pointer_get(wire, check["pointer"])
        assert_equal check["length"], value.length, check["pointer"] if check.key?("length")
        if check.key?("equals")
          assert json_equal?(normalize(check["equals"]), normalize(value)), "#{check["pointer"]} = #{value.inspect}"
        end
      end
    end

    return unless expect["redaction"]

    transport.requests.each do |request|
      refute_includes request.url, api_key
      refute(request.headers.values.any? { |v| v.include?(api_key) }, "key in a header")
      assert_equal 1, request.body.scan(api_key).length, "key exactly once in the body"
      assert_equal api_key, JSON.parse(request.body)["clientKey"]
    end
    refute_includes "#{error&.full_message} #{error.inspect}", api_key if error
  end

  scenario_files.each do |file|
    sc = JSON.parse(File.read(file))
    # This client is synchronous and has no cancellation primitive, so the two cancellation
    # scenarios do not apply (like the Python sync client).
    next if sc.dig("call", "cancelAfterSleeps")

    define_method("test_#{sc["name"].tr("-", "_")}") { run_scenario(sc) }
  end

  def test_scenarios_are_vendored
    assert_operator self.class.scenario_files.length, :>=, 90
  end
end
