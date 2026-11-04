# frozen_string_literal: true

require "net/http"
require "openssl"
require "uri"

module SurSolver
  # One HTTP request handed to a transport. timeout is in seconds.
  Request = Struct.new(:method, :url, :headers, :body, :timeout, keyword_init: true)

  # What a transport returns for any HTTP status.
  Response = Struct.new(:status, :body, keyword_init: true)

  # The default transport: Net::HTTP, which never follows redirects, so a request body carrying the
  # API key is not replayed to another location.
  #
  # A transport is any object with #call(request) returning a Response for every HTTP status. Raise
  # Timeout::Error when request.timeout passes, and an IOError, SystemCallError or SocketError when
  # no response arrived.
  class NetHttpTransport
    # proxy: optional URI of an HTTP proxy for the connection to the API.
    def initialize(proxy: nil)
      @proxy = proxy && URI(proxy)
    end

    def call(request)
      uri = URI(request.url)
      http = Net::HTTP.new(uri.host, uri.port, @proxy&.host, @proxy&.port, @proxy&.user, @proxy&.password)
      http.use_ssl = uri.scheme == "https"
      # Net::HTTP bounds each phase (connect, write, every read) by the request timeout.
      http.open_timeout = http.read_timeout = http.write_timeout = http.ssl_timeout = request.timeout
      http.max_retries = 0
      message = (request.method == "POST" ? Net::HTTP::Post : Net::HTTP::Get).new(uri.request_uri, request.headers)
      message.body = request.body if request.body
      response = http.start { |connection| connection.request(message) }
      Response.new(status: response.code.to_i, body: response.body || "")
    end
  end

  # The real clock: monotonic seconds and Kernel#sleep.
  class SystemClock
    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def sleep(seconds)
      Kernel.sleep(seconds)
    end
  end
end
