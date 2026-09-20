# frozen_string_literal: true

module Sloplint
  module Judge
    # One normalised answer. probabilities: Float for a noul, Hash keyed by
    # option for a choice, Array low-to-high for a score. confidence: 0..1.
    # usage: whatever the backend counts, for the stderr trailer.
    Answer = Data.define(:type, :probabilities, :confidence, :usage) do
      def initialize(usage: {}, **rest) = super

      # Index of the most likely level of a score answer, which is the only
      # kind a rule flags on today, and nil when two levels share the top.
      # A tie has no most likely level: evenly split, the answer would go to
      # the lowest index, which is the level every rule flags on, so an
      # answer that says nothing would read as a finding.
      # See docs/JUDGE.md "Rule model".
      def top
        # A noul is a Float and a choice is a Hash keyed by option: neither
        # has a level, so neither has a most likely one. No rule flags on
        # either today, and asking for the top of one is a question with no
        # answer rather than a finding.
        return nil unless probabilities.is_a?(Array)

        best = probabilities.max
        probabilities.count(best) == 1 ? probabilities.index(best) : nil
      end
    end

    # Raised for anything that stops the backend answering: no key, network,
    # a non-200, a body that does not parse. The CLI turns it into exit 3.
    class BackendError < StandardError; end

    # The one interface the engine depends on. A backend answers `ask` with a
    # Hash of question name => Answer and `name` with a short stable string.
    # For the CLI's key commands it also declares KEY, the environment
    # variable and keychain account its key lives under, and answers
    # `configured!`, which checks its endpoint settings without building the
    # backend or reading the key and returns a short description of them, and
    # `model_name`, the string a built backend would answer `name` with, for
    # the run that asks no question and so builds nothing. A backend that
    # prices its own tokens answers `cost_usd` on the class as well as on the
    # instance, so that run can print a price too.
    # See docs/JUDGE.md "Backend adapter". The table is the guard that keeps
    # `--backend` from naming an arbitrary file.
    module Backend
      TABLE = { "jev" => "Jev" }.freeze

      module_function

      def load(name = nil) = klass(name).new

      # Which adapter a command runs: --backend, else the environment, else
      # jev. One place, because the commands that only print the name must
      # print the one `klass` would load.
      def default_name(chosen = nil) = chosen || ENV.fetch("SLOPLINT_JUDGE_BACKEND", "jev")

      # The class alone, for `status` and the key commands: they must not
      # construct a backend, because constructing one reads the key.
      def klass(name = nil)
        name = default_name(name)
        const = TABLE[name] or raise ArgumentError, "unknown backend: #{name} (known: #{TABLE.keys.join(", ")})"
        require_relative "backends/#{name}" unless Backends.const_defined?(const, false)
        Backends.const_get(const)
      end
    end

    module Backends; end
  end
end
