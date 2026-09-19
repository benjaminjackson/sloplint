# frozen_string_literal: true

require_relative "lib/sloplint/judge/version"

Gem::Specification.new do |spec|
  spec.name        = "sloplint-judge"
  spec.version     = Sloplint::Judge::VERSION
  spec.authors     = ["Benjamin Jackson"]
  spec.email       = ["ben@benjaminjackson.co"]

  spec.summary     = "sloplint rules that ask a System One model what a regex cannot."
  spec.description = "A second catalog for sloplint whose rules are questions put to a System One model " \
                     "(Jev by default) rather than regexes: does this paragraph end by restating itself, does " \
                     "this sentence name anything a reader could check. Emits sloplint's own notes. Adds " \
                     "`sloplint check --judge` and a `sloplint-judge` executable."
  spec.homepage    = "https://github.com/benjaminjackson/sloplint"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata = {
    "source_code_uri" => "https://github.com/benjaminjackson/sloplint",
    "changelog_uri" => "https://github.com/benjaminjackson/sloplint/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/benjaminjackson/sloplint/issues",
    "rubygems_mfa_required" => "true"
  }

  # Same cwd note as sloplint.gemspec: gem build resolves files against the
  # process cwd, so pin it here.
  Dir.chdir(__dir__)
  spec.files = Dir["lib/sloplint/judge.rb", "lib/sloplint/judge/**/*.rb", "exe/sloplint-judge", "docs/JUDGE.md", "LICENSE"]
  spec.bindir      = "exe"
  spec.executables = ["sloplint-judge"]
  spec.require_paths = ["lib"]

  spec.add_dependency "sloplint", "~> 0.8"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
