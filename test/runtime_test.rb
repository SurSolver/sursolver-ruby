# frozen_string_literal: true

# Behaviour the language-neutral scenarios cannot cover: the real Net::HTTP transport against a
# local server and #inspect redaction.

require_relative "test_helper"
require "socket"

class RuntimeTest < Minitest::Test
  TASK_ID = "tsk_4f7a9c1e2b8d3a6f5c0e9d21"
  TASK = {
    "type" => SurSolver::TaskTypes::TURNSTILE_TOKEN_PROXY_LESS,
    "websiteURL" => "https://example.com/",
    "websiteKey" => "k",
    "userAgent" => "ua"
  }.freeze

  Recorded = Struct.new(:line, :headers, :body)

  # A minimal HTTP/1.1 server on 127.0.0.1; the block returns a raw response, or nil to never answer.
  def serve(&handler)
    server = TCPServer.new("127.0.0.1", 0)
    @requests = Queue.new
    @release = Queue.new
    @server_thread = Thread.new do
      loop do
        socket = server.accept
        line = socket.gets.to_s.split[0, 2].join(" ")
        headers = {}
        while (header = socket.gets) && header != "\r\n"
          name, value = header.split(":", 2)
          headers[name.strip.downcase] = value.strip
        end
        body = socket.read(headers["content-length"].to_i)
        request = Recorded.new(line, headers, body)
        @requests << request
        response = handler.call(request)
        if response
          socket.write(response)
        else
          @release.pop
        end
        socket.close
      end
    rescue IOError
      nil
    end
    @server = server
    "http://127.0.0.1:#{server.addr[1]}"
  end

  def teardown
    @release&.push(:go)
    @server&.close
    @server_thread&.join(1)
  end

  def json(body)
    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
  end

  def test_key_travels_only_in_the_body_with_the_sdk_user_agent
    base = serve { json(%({"errorId":0,"taskId":"#{TASK_ID}"})) }
    client = SurSolver::Client.new(TEST_API_KEY, base_url: base)

    assert_equal TASK_ID, client.create_task(TASK)

    request = @requests.pop
    assert_equal "POST /createTask", request.line
    assert request.headers["user-agent"].start_with?("sursolver-ruby/#{SurSolver::VERSION}")
    assert_equal "application/json", request.headers["content-type"]
    refute(request.headers.values.any? { |v| v.include?(TEST_API_KEY) })
    assert_equal TEST_API_KEY, JSON.parse(request.body)["clientKey"]
  end

  def test_request_timeout_is_a_transport_error
    base = serve { nil }
    # A real 100 ms wait: the behaviour under test is Net::HTTP's own deadline handling.
    client = SurSolver::Client.new(TEST_API_KEY, base_url: base, request_timeout: 0.1)

    error = assert_raises(SurSolver::TransportError) { client.get_balance }

    assert_includes error.message, "timed out after 100 ms"
    refute error.may_have_created_task?
    assert_nil error.status
  end

  def test_redirect_is_not_followed
    base = serve { "HTTP/1.1 307 Temporary Redirect\r\nLocation: /elsewhere\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" }
    client = SurSolver::Client.new(TEST_API_KEY, base_url: base)

    error = assert_raises(SurSolver::TransportError) { client.create_task(TASK) }

    assert_equal 307, error.status
    assert error.may_have_created_task?
    assert_includes error.message, "charged"
    assert_equal 1, @requests.size
  end

  def test_api_errors_and_inspect_never_show_the_key
    base = serve do
      json('{"errorId":1,"errorCode":"ERROR_KEY_DOES_NOT_EXIST","errorDescription":"The clientKey does not match any active API key."}')
    end
    client = SurSolver::Client.new(TEST_API_KEY, base_url: base)

    error = assert_raises(SurSolver::AuthenticationError) { client.get_balance }

    refute_includes "#{error.full_message} #{error.inspect}", TEST_API_KEY
    refute_includes client.inspect, TEST_API_KEY
    refute_includes client.to_s, TEST_API_KEY
    assert_includes client.inspect, base
  end
end
