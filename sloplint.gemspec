# frozen_string_literal: true

require_relative "lib/sloplint/version"

Gem::Specification.new do |spec|
  spec.name        = "sloplint"
  spec.version     = Sloplint::VERSION
  spec.authors     = ["Benjamin Jackson"]
  spec.email       = ["ben@benjaminjackson.co"]

  spec.summary     = "Flag the rhetorical tics and puffery that mark AI-generated prose."
  spec.description = "A dependency-free CLI that scans prose for the specific fingerprints of " \
                     "LLM writing — cadence tics, puffery, vague attribution — and reports them " \
                     "as machine-readable linting notes. Agent-first: JSON output, stable schema, " \
                     "and an `explain` command."
  spec.homepage    = "https://github.com/benjaminjackson/sloplint"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.files = Dir["lib/**/*.rb", "bin/*", "docs/SPEC.md", "*.gemspec", ".rspec", "Rakefile"]
  spec.bindir      = "bin"
  spec.executables = ["sloplint"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
