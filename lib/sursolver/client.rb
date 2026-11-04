# frozen_string_literal: true

require "json"
require "socket"
require "timeout"
require "uri"

module SurSolver
  # Client of the SurSolver captcha-solving API. Durations are in seconds.
  #
  # The API key travels only in request bodies and never appears in errors or #inspect.
  class Client
    DEFAULT_BASE_URL = "https://api.sursolver.com"
    DEFAULT_REQUEST_TIMEOUT = 30
    DEFAULT_POLL_INTERVAL = 3
    DEFAULT_SOLVE_TIMEOUT = 210
    DEFAULT_MAX_SUBMIT_RETRIES = 1
    # Upper bound of the random delay added to a submit retry, in seconds.
    SUBMIT_RETRY_JITTER = 1

    LOOPBACK_HOSTS = %w[localhost 127.0.0.1 ::1].freeze
    NO_RESPONSE_ERRORS = [IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError, Net::ProtocolError].freeze
    private_constant :LOOPBACK_HOSTS, :NO_RESPONSE_ERRORS

    # Builds a client; raises ConfigurationError for an unusable option (nothing is sent).
    #
    # transport: object with #call(Request) -> Response (default NetHttpTransport).
    # clock: object with #now and #sleep(seconds) (tests). random: callable returning [0, 1).
    def initialize(api_key, base_url: DEFAULT_BASE_URL, request_timeout: DEFAULT_REQUEST_TIMEOUT,
                   poll_interval: DEFAULT_POLL_INTERVAL, solve_timeout: DEFAULT_SOLVE_TIMEOUT,
                   max_submit_retries: DEFAULT_MAX_SUBMIT_RETRIES, app_id: nil, user_agent_suffix: nil,
                   transport: nil, clock: nil, random: nil)
      raise ConfigurationError, "api_key must be a non-empty string" if !api_key.is_a?(String) || api_key.strip.empty?
      raise ConfigurationError, "api_key has leading or trailing whitespace" if api_key.strip != api_key

      @base_url = normalize_base_url(base_url)
      { request_timeout: request_timeout, poll_interval: poll_interval, solve_timeout: solve_timeout }.each do |name, value|
        require_positive(name, value)
      end
      unless max_submit_retries.is_a?(Integer) && max_submit_retries >= 0
        raise ConfigurationError, "max_submit_retries must be a non-negative integer"
      end

      @user_agent = "sursolver-ruby/#{VERSION}"
      unless user_agent_suffix.nil?
        unless user_agent_suffix.is_a?(String) && user_agent_suffix.match?(/\A[\x20-\x7e]+\z/)
          raise ConfigurationError, "user_agent_suffix must be non-empty printable ASCII"
        end

        @user_agent += " #{user_agent_suffix}"
      end
      @api_key = api_key
      @request_timeout = request_timeout
      @poll_interval = poll_interval
      @solve_timeout = solve_timeout
      @max_submit_retries = max_submit_retries
      @app_id = app_id&.strip
      @app_id = nil if @app_id&.empty?
      @transport = transport || NetHttpTransport.new
      @clock = clock || SystemClock.new
      @random = random || -> { Random.rand }
    end

    # Never reveals the API key.
    def inspect
      "#<SurSolver::Client base_url=#{@base_url}>"
    end
    alias to_s inspect

    # Submits a task and returns its id. The task is charged from this point. It is never retried:
    # after a TransportError the task may exist (check get_balance before submitting again).
    #
    # task: Hash with "type" plus that type's fields, sent verbatim. Browser types require "userAgent".
    def create_task(task)
      payload = { "clientKey" => @api_key, "task" => task }
      payload["appId"] = @app_id if @app_id
      body = solver_call("createTask", "/createTask", payload)
      task_id = body["taskId"]
      raise ProtocolError.new("createTask", "errorId 0 without a taskId") unless task_id.is_a?(String) && !task_id.empty?

      task_id
    end

    # Reads a task's state once. A terminal failure raises TaskFailedError.
    def get_task_result(task_id)
      body = solver_call("getTaskResult", "/getTaskResult", { "clientKey" => @api_key, "taskId" => task_id }, task_id)
      case body["status"]
      when "processing" then TaskResult.new(status: "processing", solution: nil)
      when "ready"
        solution = body["solution"]
        raise ProtocolError.new("getTaskResult", "status ready without a solution object") unless solution.is_a?(Hash)

        TaskResult.new(status: "ready", solution: solution)
      else
        raise ProtocolError.new("getTaskResult", "unknown status #{JSON.generate(body["status"])}")
      end
    end

    # The cash balance in USD as the JSON number the API sends. Display it; do not do money
    # arithmetic on it (the dashboard's GET /v1/balance has the exact decimal).
    def get_balance # rubocop:disable Naming/AccessorMethodName
      balance = solver_call("getBalance", "/getBalance", { "clientKey" => @api_key })["balance"]
      raise ProtocolError.new("getBalance", "errorId 0 without a numeric balance") unless balance.is_a?(Numeric) && balance.finite?

      balance.to_f
    end

    # Creates a task and polls it until it is ready, failed, or the deadline passes.
    #
    # createTask is resubmitted only after ERROR_NO_SLOT_AVAILABLE (nothing was created), at most
    # max_submit_retries times; any other submit failure is raised at once. Polls that fail with a
    # TransportError or ERROR_INTERNAL_ERROR are retried until the deadline; any other error ends the
    # call and carries the task id. On the deadline SolveTimeoutError is raised; the task may still
    # finish. on_task_created is called once with the task id as soon as the task is accepted.
    def solve(task, poll_interval: nil, solve_timeout: nil, on_task_created: nil)
      interval = poll_interval || @poll_interval
      timeout = solve_timeout || @solve_timeout
      require_positive(:poll_interval, interval)
      require_positive(:solve_timeout, timeout)
      deadline = @clock.now + timeout

      retries = 0
      begin
        task_id = create_task(task)
      rescue NoSlotAvailableError
        raise if retries >= @max_submit_retries

        retries += 1
        jitter_ms = (@random.call * SUBMIT_RETRY_JITTER * 1000).floor
        @clock.sleep(interval + (jitter_ms / 1000.0))
        retry
      end
      on_task_created&.call(task_id)

      loop do
        last_error = nil
        begin
          result = get_task_result(task_id)
          return SolveResult.new(task_id: task_id, solution: result.solution) if result.ready?
        rescue TransportError => e
          last_error = e
        rescue ApiError => e
          raise unless e.code == ErrorCodes::ERROR_INTERNAL_ERROR

          last_error = e
        end
        @clock.sleep(interval)
        raise SolveTimeoutError.new(task_id, timeout, last_error) if @clock.now >= deadline
      end
    end

    # The public task-type catalog: accepted names, fields, proxy modes and result keys.
    def list_task_types
      data = catalog_call("listTaskTypes", "/v1/task-types")
      task_types = data["task_types"]
      error_codes = data["error_codes"]
      unless task_types.is_a?(Array) && error_codes.is_a?(Array)
        raise ProtocolError.new("listTaskTypes", "data without task_types and error_codes arrays")
      end

      read = EntryReader.new("listTaskTypes")
      TaskTypeCatalog.new(
        task_types: task_types.map do |raw|
          entry = read.object(raw)
          TaskTypeInfo.new(
            page_slug: read.optional_text(entry, "page_slug"),
            display_name: read.text(entry, "display_name"),
            task_type: read.text(entry, "task_type"),
            task_type_proxyless: read.optional_text(entry, "task_type_proxyless"),
            aliases: read.texts(entry["aliases"], "aliases"),
            proxy: read.text(entry, "proxy"),
            required: read.groups(entry, "required"),
            any_of: read.groups(entry, "any_of"),
            optional: read.texts(entry["optional"], "optional"),
            solution_keys: read.texts(entry["solution_keys"], "solution_keys")
          )
        end,
        error_codes: read.texts(error_codes, "error_codes")
      )
    end

    # Active services with their current USD price per task (decimal strings).
    def list_services
      services = catalog_call("listServices", "/v1/services")["services"]
      raise ProtocolError.new("listServices", "data without a services array") unless services.is_a?(Array)

      read = EntryReader.new("listServices")
      services.map do |raw|
        entry = read.object(raw)
        ServiceInfo.new(
          id: read.integer(entry, "id"),
          slug: read.text(entry, "slug"),
          display_name: read.text(entry, "display_name"),
          price_per_request: read.text(entry, "price_per_request"),
          status: read.text(entry, "status"),
          avg_latency_ms: entry.key?("avg_latency_ms") && entry["avg_latency_ms"].nil? ? nil : read.integer(entry, "avg_latency_ms")
        )
      end
    end

    private

    def require_positive(name, value)
      raise ConfigurationError, "#{name} must be a positive number of seconds" unless value.is_a?(Numeric) && value.positive?
    end

    def normalize_base_url(raw)
      uri = begin
        URI.parse(raw.to_s)
      rescue URI::InvalidURIError
        nil
      end
      raise ConfigurationError, "base_url is not a valid absolute URL" if uri.nil? || uri.host.nil? || uri.host.empty?

      host = uri.host.downcase.delete_prefix("[").delete_suffix("]")
      loopback_http = uri.scheme == "http" && LOOPBACK_HOSTS.include?(host)
      unless uri.scheme == "https" || loopback_http
        raise ConfigurationError, "base_url must use https:// (plain http:// only for localhost)"
      end
      if uri.userinfo || uri.query || uri.fragment || raw.include?("?") || raw.include?("#")
        raise ConfigurationError, "base_url must not carry credentials, a query or a fragment"
      end

      port = uri.port == uri.default_port ? "" : ":#{uri.port}"
      "#{uri.scheme}://#{uri.host.downcase}#{port}#{uri.path.sub(%r{/+\z}, "")}"
    end

    def request(method, path, body)
      headers = { "Accept" => "application/json", "User-Agent" => @user_agent }
      headers["Content-Type"] = "application/json" if body
      Request.new(method: method, url: @base_url + path, headers: headers, body: body, timeout: @request_timeout)
    end

    def send_request(operation, request)
      response = begin
        @transport.call(request)
      rescue Timeout::Error
        raise TransportError.new(operation, "request timed out after #{(request.timeout * 1000).round} ms")
      rescue *NO_RESPONSE_ERRORS
        raise TransportError.new(operation, "connection failed")
      end
      return response if response.status == 200

      detail = parse(response.body)
      detail = detail.is_a?(Hash) ? detail["error"] : nil
      server_code = detail.is_a?(Hash) && detail["code"].is_a?(String) ? detail["code"] : nil
      retry_after = detail.is_a?(Hash) && detail["retry_after_seconds"].is_a?(Numeric) ? detail["retry_after_seconds"].to_i : nil
      reason = server_code ? "HTTP #{response.status} (#{server_code})" : "HTTP #{response.status}"
      raise TransportError.new(operation, reason, status: response.status, server_code: server_code,
                                                  retry_after_seconds: retry_after)
    end

    NOT_JSON = Object.new.freeze
    private_constant :NOT_JSON

    def parse(body)
      JSON.parse(body.to_s)
    rescue JSON::ParserError
      NOT_JSON
    end

    # POSTs to a solver endpoint; returns the errorId 0 body or raises the classified error.
    def solver_call(operation, path, payload, task_id = nil)
      response = send_request(operation, request("POST", path, JSON.generate(payload)))
      body = parse(response.body)
      error_id = body.is_a?(Hash) ? body["errorId"] : nil
      unless error_id.is_a?(Integer) || (error_id.is_a?(Float) && error_id.finite? && error_id == error_id.floor)
        what = body.equal?(NOT_JSON) ? "not JSON" : "not the solver envelope"
        raise TransportError.new(operation, "HTTP 200 body is #{what}", status: 200)
      end
      return body if error_id.zero?
      raise ProtocolError.new(operation, "errorId #{error_id}") unless error_id == 1

      code = body["errorCode"]
      raise ProtocolError.new(operation, "errorId 1 without a string errorCode") unless code.is_a?(String)

      description = body["errorDescription"].is_a?(String) ? body["errorDescription"] : ""
      supported = body["supportedUserAgents"].is_a?(Array) ? body["supportedUserAgents"].grep(String) : []
      raise ApiError.for(operation, code, description, task_id, supported)
    end

    # GETs a public catalog endpoint and returns its data object.
    def catalog_call(operation, path)
      envelope = parse(send_request(operation, request("GET", path, nil)).body)
      return envelope["data"] if envelope.is_a?(Hash) && envelope["success"] == true && envelope["data"].is_a?(Hash)

      raise TransportError.new(operation, "HTTP 200 body is not the API envelope", status: 200)
    end

    # Typed reads of catalog entries; a missing or mistyped field is a ProtocolError.
    class EntryReader
      def initialize(operation)
        @operation = operation
      end

      def object(raw)
        raise ProtocolError.new(@operation, "a catalog entry is not an object") unless raw.is_a?(Hash)

        raw
      end

      def text(entry, key)
        value = entry[key]
        raise fail(key, "a string") unless value.is_a?(String)

        value
      end

      def optional_text(entry, key)
        value = entry[key]
        raise fail(key, "a string or null") unless value.nil? || value.is_a?(String)

        value
      end

      def integer(entry, key)
        value = entry[key]
        raise fail(key, "an integer") unless value.is_a?(Integer)

        value
      end

      def texts(raw, key)
        raise fail(key, "a list of strings") unless raw.is_a?(Array) && raw.all?(String)

        raw
      end

      def groups(entry, key)
        value = entry[key]
        raise fail(key, "a list of string lists") unless value.is_a?(Array) && value.all? { |g| g.is_a?(Array) && g.all?(String) }

        value
      end

      private

      def fail(key, expected)
        ProtocolError.new(@operation, "catalog field #{key} is not #{expected}")
      end
    end
    private_constant :EntryReader
  end
end
