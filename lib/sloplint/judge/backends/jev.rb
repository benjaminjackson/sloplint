# frozen_string_literal: true

require "net/http"
require "openssl"
require "uri"
require "json"
require_relative "../secret"

module Sloplint
  module Judge
    module Backends
      # Jev, TypeSafe's System One model. The rule's question shape is Jev's,
      # so questions pass through verbatim.
      class Jev
        DEFAULT_URL = "https://api.typesafe.ai/v1/systemone"
        DEFAULT_MODEL = "jev-latest"

        # key: nil means look it up (environment, then keychain; see Secret).
        def initialize(url: ENV.fetch("SYSTEMONE_URL", DEFAULT_URL),
                       model: ENV.fetch("SYSTEMONE_MODEL", DEFAULT_MODEL),
                       key: nil)
          key ||= Secret.fetch("TYPESAFE_API_KEY")&.first
          raise ArgumentError, Secret::MISSING if key.nil? || key.empty?

          @url = self.class.https!(url)
          @model = model
          @key = key
        end

        HOST = /\A(?:.+\.)?typesafe\.ai\z/

        # The key and the whole document go to this URL, so it is https and
        # a TypeSafe host or nothing. The host pin is what keeps an injected
        # `SYSTEMONE_URL=https://attacker.example sloplint check --judge` from
        # being a valid way to run the sanctioned command. `status` asks the
        # same question without building a backend.
        def self.https!(url)
          uri = URI(url)
          raise ArgumentError, "SYSTEMONE_URL must be https, got #{uri.scheme.inspect}" unless uri.scheme == "https"
          raise ArgumentError, "SYSTEMONE_URL must be a typesafe.ai host, got #{uri.host.inspect}" unless uri.host.to_s.match?(HOST)

          uri
        end

        # Jev's response carries token counts and no price. TypeSafe's public
        # price is $42 per billion input tokens; output tokens are free. So
        # the cost is the input tokens times this, exactly, not an estimate.
        # ponytail: one constant, not a config; move to an env var when the
        # price moves.
        USD_PER_INPUT_TOKEN = 42.0 / 1_000_000_000

        def name = @model

        # Dollars for a summed usage Hash. Output tokens cost nothing.
        def cost_usd(usage) = usage.fetch("input_tokens", 0) * USD_PER_INPUT_TOKEN

        def ask(state, questions)
          http = Net::HTTP.new(@url.host, @url.port)
          http.use_ssl = true
          http.read_timeout = 90
          req = Net::HTTP::Post.new(@url.path, "Content-Type" => "application/json", "Authorization" => "Bearer #{@key}")
          req.body = JSON.generate({ "state" => state, "model" => @model, "questions" => questions })
          res = http.request(req)
          raise BackendError, "#{@url.host} returned #{res.code}: #{res.body.to_s[0, 200]}" unless res.code == "200"

          body = JSON.parse(res.body)
          usage = body["usage"] || {}
          answers = body.fetch("answers")
          questions.to_h do |qname, q|
            a = answers.fetch(qname) { raise KeyError, "no answer for #{qname}" }
            type = q.fetch("type")
            probs = normalise(type, type == "noul" ? a.fetch("noul") : a.fetch("probabilities"))
            [qname, Answer.new(type: type, probabilities: probs, confidence: confidence_for(a, type, probs), usage: usage)]
          end
        # Transport errors, and a body that is not the shape Jev documents
        # (TypeError, NoMethodError on a nil answer), are one thing to the
        # caller: the backend did not answer. Exit 3, not a backtrace.
        rescue SocketError, IOError, SystemCallError, OpenSSL::SSL::SSLError, Net::ProtocolError, Net::OpenTimeout,
               Net::ReadTimeout, JSON::ParserError, KeyError, TypeError, NoMethodError => e
          raise BackendError, "#{e.class}: #{e.message}"
        end

        private

        # Jev returns score probabilities keyed by level index as strings, choice
        # probabilities keyed by option, and a noul as one float under "noul".
        def normalise(type, probs)
          case type
          when "score"
            raise BackendError, "score probabilities are #{probs.class}, not a Hash keyed by level" unless probs.is_a?(Hash)

            probs.sort_by { |k, _| k.to_i }.map { |_, p| p.to_f }
          when "choice" then probs.transform_values(&:to_f)
          else probs.to_f
          end
        end

        # Score and choice answers carry a confidence. A noul does not, so it
        # gets the one thing its answer can defend: distance from the fence,
        # scaled so 0.5 is 0 and 0 or 1 is 1.
        def confidence_for(answer, type, probs)
          return answer["confidence"].to_f if answer["confidence"]
          return (probs - 0.5).abs * 2 if type == "noul"

          sorted = (probs.is_a?(Hash) ? probs.values : probs).sort.reverse
          (sorted[0] - (sorted[1] || 0)).clamp(0.0, 1.0)
        end
      end
    end
  end
end
