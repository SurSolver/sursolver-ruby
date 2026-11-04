# frozen_string_literal: true

require_relative "sursolver/version"
require_relative "sursolver/task_types"
require_relative "sursolver/errors"
require_relative "sursolver/types"
require_relative "sursolver/transport"
require_relative "sursolver/client"

# Official Ruby client for the SurSolver captcha-solving API (https://sursolver.com).
#
#   client = SurSolver::Client.new("YOUR_API_KEY")
#   result = client.solve(
#     "type" => SurSolver::TaskTypes::TURNSTILE_TOKEN_PROXY_LESS,
#     "websiteURL" => "https://example.com/login",
#     "websiteKey" => "0x4AAAAAAA...",
#     "userAgent" => USER_AGENT
#   )
#   result.solution["token"]
#
# The API key travels only in request bodies and never appears in errors or #inspect.
module SurSolver
end
