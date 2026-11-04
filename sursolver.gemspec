# frozen_string_literal: true

require_relative "lib/sursolver/version"

Gem::Specification.new do |spec|
  spec.name = "sursolver"
  spec.version = SurSolver::VERSION
  spec.authors = ["SurSolver"]
  spec.summary = "Official Ruby client for the SurSolver captcha solver API."
  spec.description = "Solve reCAPTCHA v3, Cloudflare Turnstile, Cloudflare Challenge (cf_clearance), GeeTest, " \
                     "DataDome, AWS WAF, Akamai, Kasada and image captchas from Ruby with one call. " \
                     "Standard library only."
  spec.homepage = "https://sursolver.com"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata = {
    "homepage_uri" => "https://sursolver.com",
    "documentation_uri" => "https://sursolver.com/docs",
    "source_code_uri" => "https://github.com/sursolver/sursolver-ruby",
    "changelog_uri" => "https://github.com/sursolver/sursolver-ruby/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb"] + %w[README.md LICENSE CHANGELOG.md]
  spec.require_paths = ["lib"]
  spec.add_dependency "json", ">= 2.7"
end
