# frozen_string_literal: true

# Live smoke test against the real API; costs nothing. Run: rake smoke
# Reads the public catalog and calls get_balance with a fake key (expects AuthenticationError).
# Set SURSOLVER_API_KEY to also read your real balance; SURSOLVER_BASE_URL overrides the origin.

require "sursolver"

base_url = ENV.fetch("SURSOLVER_BASE_URL", SurSolver::Client::DEFAULT_BASE_URL)
client = SurSolver::Client.new("sur_00000000000000000000000000000000", base_url: base_url)

catalog = client.list_task_types
puts "list_task_types: #{catalog.task_types.length} types, #{catalog.error_codes.length} error codes"
puts "list_services: #{client.list_services.length} active services"
begin
  client.get_balance
  abort "get_balance accepted a fake key"
rescue SurSolver::AuthenticationError => e
  puts "get_balance (fake key): #{e.message}"
end

api_key = ENV.fetch("SURSOLVER_API_KEY", "")
unless api_key.empty?
  puts "get_balance (your key): #{SurSolver::Client.new(api_key, base_url: base_url).get_balance} USD"
end
puts "smoke OK"
