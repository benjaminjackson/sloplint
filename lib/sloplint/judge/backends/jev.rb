# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Sloplint
  module Judge
    module Backends
      # Jev, TypeSafe's System One model. The rule's question shape is Jev's,
      # so questions pass through verbatim.
      class Jev
        def initialize(url: ENV.fetch("SYSTEMONE_URL", "https://api.typesafe.ai/v1/systemone"),
                       model: ENV.fetch("SYSTEMONE_MODEL", "jev-latest"),
                       key: ENV["TYPESAFE_API_KEY"])
          @url = URI(url)
          @model = model
          @key = key
        end

        def name = @model

        def ask(state, questions)
          raise BackendError, "TYPESAFE_API_KEY is not set" if @key.nil? || @key.empty?

          http = Net::HTTP.new(@url.host, @url.port)
          http.use_ssl = @url.scheme == "https"
          http.read_timeout = 90
          req = Net::HTTP::Post.new(@url.path, "Content-Type" => "application/json", "Authorization" => "Bearer #{@key}")
          req.body = JSON.generate({ "state" => state, "model" => @model, "questions" => questions })
          res = http.request(req)
          raise BackendError, "#{@url.host} returned #{res.code}: #{res.body.to_s[0, 200]}" unless res.code == "200"

          body = JSON.parse(res.body)
          usage = body["usage"] || {}
          body.fetch("answers").to_h do |qname, a|
            type = questions.fetch(qname).fetch("type")
            probs = normalise(type, type == "noul" ? a.fetch("noul") : a.fetch("probabilities"))
            [qname, Answer.new(type: type, probabilities: probs, confidence: confidence_for(a, type, probs), usage: usage)]
          end
        rescue SocketError, IOError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, JSON::ParserError, KeyError => e
          raise BackendError, "#{e.class}: #{e.message}"
        end

        private

        # Jev returns score probabilities keyed by level index as strings, choice
        # probabilities keyed by option, and a noul as one float under "noul".
        def normalise(type, probs)
          case type
          when "score" then probs.sort_by { |k, _| k.to_i }.map { |_, p| p.to_f }
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
