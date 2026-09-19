# frozen_string_literal: true

module Sloplint
  module Judge
    # One normalised answer. probabilities: Float for a noul, Hash keyed by
    # option for a choice, Array low-to-high for a score. confidence: 0..1.
    # usage: whatever the backend counts, for the stderr trailer.
    Answer = Data.define(:type, :probabilities, :confidence, :usage) do
      def initialize(usage: {}, **rest) = super

      # Index of the most likely level (score) or the most likely option (choice).
      def top
        case type
        when "score" then probabilities.each_with_index.max_by { |p, _| p }.last
        when "choice" then probabilities.max_by { |_, p| p }.first
        else probabilities >= 0.5
        end
      end
    end

    # Raised for anything that stops the backend answering: no key, network,
    # a non-200, a body that does not parse. The CLI turns it into exit 3.
    class BackendError < StandardError; end

    # The one interface the engine depends on. A backend answers `ask` with a
    # Hash of question name => Answer and `name` with a short stable string.
    # See docs/JUDGE.md "Backend adapter".
    module Backend
      TABLE = { "jev" => "Jev" }.freeze

      module_function

      def load(name = ENV.fetch("SLOPLINT_JUDGE_BACKEND", "jev"))
        klass = TABLE[name] or raise BackendError, "unknown backend: #{name} (known: #{TABLE.keys.join(", ")})"
        require_relative "backends/#{name}"
        Backends.const_get(klass).new
      end
    end

    module Backends; end
  end
end
