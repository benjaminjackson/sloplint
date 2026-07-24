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

  spec.metadata = {
    "source_code_uri" => "https://github.com/benjaminjackson/sloplint",
    "changelog_uri" => "https://github.com/benjaminjackson/sloplint/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/benjaminjackson/sloplint/issues",
    "rubygems_mfa_required" => "true"
  }

  # gem build resolves spec.files against the process's cwd at build time,
  # not against this file's location -- Dir[] alone made `gem build` from
  # anywhere but this directory silently produce a gem with zero files.
  # Changing cwd here (no block: RubyGems reads spec.files after this line
  # runs, in the same process, so the change needs to stick) makes the glob
  # -- and RubyGems' own file resolution after it -- independent of the
  # caller's cwd.
  Dir.chdir(__dir__)
  spec.files = Dir["lib/**/*.rb", "bin/*", "docs/SPEC.md", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.bindir      = "bin"
  spec.executables = ["sloplint"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
