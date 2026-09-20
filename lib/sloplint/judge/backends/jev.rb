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
        # The environment variable, and the keychain account, this backend's
        # key lives under. Another backend declares its own, so two keys are
        # two items.
        KEY = "TYPESAFE_API_KEY"

        # key: nil means look it up (environment, then keychain; see Secret).
        def initialize(url: ENV.fetch("SYSTEMONE_URL", DEFAULT_URL),
                       model: ENV.fetch("SYSTEMONE_MODEL", DEFAULT_MODEL),
                       key: nil)
          key ||= Secret.fetch(KEY)&.first
          raise ArgumentError, Secret.missing(KEY) if key.nil? || key.empty?

          @url = self.class.https!(url)
          @model = model
          @key = key
        end

        # The endpoint settings, checked without building the backend or
        # reading the key; `status` prints what this returns.
        def self.configured!
          https!(ENV.fetch("SYSTEMONE_URL", DEFAULT_URL))
          "model #{ENV.fetch("SYSTEMONE_MODEL", DEFAULT_MODEL)}"
        end

        HOST = /\A(?:.+\.)?typesafe\.ai\z/

        # The key and the whole document go to this URL, so it is https and
        # a TypeSafe host or nothing. The host pin is what keeps an injected
        # `SYSTEMONE_URL=https://attacker.example sloplint check --judge` from
        # being a valid way to run the sanctioned command.
        def self.https!(url)
          uri = URI(url)
          raise ArgumentError, "SYSTEMONE_URL must be https, got #{uri.scheme.inspect}" unless uri.scheme == "https"
          raise ArgumentError, "SYSTEMONE_URL must be a typesafe.ai host, got #{uri.host.inspect}" unless uri.host.to_s.match?(HOST)
          raise ArgumentError, "SYSTEMONE_URL needs a path, for example #{DEFAULT_URL}" if uri.path.empty?

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
          req = Net::HTTP::Post.new(@url.request_uri, "Content-Type" => "application/json", "Authorization" => "Bearer #{@key}")
          req.body = JSON.generate({ "state" => state, "model" => @model, "questions" => questions })
          res = http.request(req)
          raise BackendError, "#{@url.host} returned #{res.code}: #{res.body.to_s[0, 200]}" unless res.code == "200"

          body = JSON.parse(res.body)
          usage = body["usage"].is_a?(Hash) ? body["usage"] : {}
          answers = body.fetch("answers")
          malformed!("answers is #{answers.class}, not a Hash keyed by question") unless answers.is_a?(Hash)
          questions.to_h do |qname, q|
            a = answers.fetch(qname) { raise KeyError, "no answer for #{qname}" }
            malformed!("the answer for #{qname} is #{a.class}, not a Hash") unless a.is_a?(Hash)
            type = q.fetch("type")
            probs = normalise(type, type == "noul" ? a.fetch("noul") : a.fetch("probabilities"), q)
            [qname, Answer.new(type: type, probabilities: probs, confidence: confidence_for(a, type, probs), usage: usage)]
          end
        # Transport errors, and a body missing a key Jev documents, are one
        # thing to the caller: the backend did not answer. Exit 3, not a
        # backtrace. A body of the wrong shape raises BackendError where it is
        # read, so this list stays off our own code: a bug in normalise is a
        # bug, and it gets to raise like one.
        rescue SocketError, IOError, SystemCallError, OpenSSL::SSL::SSLError, Net::ProtocolError, Net::OpenTimeout,
               Net::ReadTimeout, JSON::ParserError, KeyError => e
          raise BackendError, "#{e.class}: #{e.message}"
        end

        private

        # Jev returns score probabilities keyed by level index as strings, choice
        # probabilities keyed by option, and a noul as one float under "noul".
        # Anything else in those slots is a malformed body, said so here, which
        # is what lets `ask` rescue only the reads and not our own arithmetic.
        def normalise(type, probs, question)
          case type
          when "score" then scores(probs, question.fetch("criteria").size)
          when "choice"
            malformed!("choice probabilities are #{probs.class}, not a Hash keyed by option") unless probs.is_a?(Hash)

            probs.transform_values { |p| number(p) }
          else
            malformed!("noul is #{probs.class}, not a number") unless probs.is_a?(Numeric)

            probs.to_f
          end
        end

        # One probability per level, in level order. Jev may leave out a level
        # whose probability is zero, so the array is as long as the question's
        # criteria and the gaps are 0.0. Otherwise a short array would slide
        # every level down one and Answer#top would name the wrong criterion.
        def scores(probs, levels)
          malformed!("score probabilities are #{probs.class}, not a Hash keyed by level") unless probs.is_a?(Hash)

          out = Array.new(levels, 0.0)
          probs.each do |k, p|
            i = Integer(k.to_s, 10, exception: false)
            malformed!("score probability key #{k.inspect} is not one of the #{levels} levels") unless i&.between?(0, levels - 1)
            out[i] = number(p)
          end
          out
        end

        def number(p) = Float(p, exception: false) || malformed!("#{p.class} is not a probability")

        def malformed!(why) = raise(BackendError, "#{@url.host} returned a malformed body: #{why}")

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
