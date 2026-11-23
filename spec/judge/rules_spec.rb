# frozen_string_literal: true

require_relative "../support/fake_backend"

RSpec.describe "Sloplint::Judge::RULES" do
  let(:rules) { Sloplint::Judge::RULES }

  it "has unique ids that do not collide with sloplint's ids or categories" do
    ids = rules.map(&:id) + [Sloplint::Judge::TRIAGE_ID]
    expect(ids).to eq(ids.uniq)
    taken = Sloplint::RULES.flat_map { |r| [r.id, r.category] }
    expect(ids & taken).to be_empty
    expect(rules.map(&:category).uniq & taken).to be_empty
  end

  # docs/JUDGE.md lists every rule and the README quotes the counts. Nothing
  # regenerates either, so both are asserted against the catalog.
  it "lists every rule in docs/JUDGE.md" do
    doc = File.read(File.expand_path("../../docs/JUDGE.md", __dir__), encoding: "UTF-8")
    rules.each { |r| expect(doc).to include("**#{r.id}**"), "#{r.id} missing from docs/JUDGE.md" }
  end

  it "names the low-confidence rules in docs/JUDGE.md" do
    doc = File.read(File.expand_path("../../docs/JUDGE.md", __dir__), encoding: "UTF-8")
    low = rules.select { |r| r.confidence == "low" }.map { |r| "`#{r.id}`" }
    expect(doc).to include("#{low[0..-2].join(", ")} and #{low[-1]} sit there.")
  end

  describe "the README rule counts" do
    readme = File.read(File.expand_path("../../README.md", __dir__), encoding: "UTF-8")

    it "quotes the catalog total" do
      words = %w[Zero One Two Three Four Five Six Seven Eight Nine Ten Eleven Twelve Thirteen Fourteen Fifteen Sixteen Seventeen Eighteen Nineteen Twenty Twenty-one]
      # fetch, not []: past the end of the list this must fail, not match " rules in two categories." against any count.
      expect(readme).to include("#{words.fetch(Sloplint::Judge::RULES.size)} rules in two categories.")
    end

    Sloplint::Judge::RULES.group_by(&:category).each do |category, rules|
      it "quotes the #{category} count" do
        expect(readme).to include("**#{category}** (#{rules.size})")
      end
    end
  end

  Sloplint::Judge::RULES.each do |rule|
    describe rule.id do
      it "is well formed" do
        expect(%i[paragraph sentence]).to include(rule.unit)
        expect(%w[error warning info]).to include(rule.severity)
        expect(%w[high medium low]).to include(rule.confidence)
        expect(rule.question["type"]).to eq("score")
        expect(rule.question["criteria"].size).to be >= 2
        expect(rule.question["criteria"]).to all(include("what", "examples"))
        expect(rule.flag[:level]).to be < rule.question["criteria"].size
        expect(rule.examples_bad).not_to be_empty
        expect(rule.examples_ok).not_to be_empty
        expect(rule.rationale).to be_a(String)
      end

      it "interpolates without error" do
        expect { format(rule.question["instructions"], register: "x") }.not_to raise_error
      end
    end
  end

  # The fixtures are pins against the live backend. Without a key, in the
  # environment or the keychain, this block skips itself and says so; it is
  # not a pass. See docs/JUDGE.md "Fixtures are live".
  # The backend's own constant, not a copy of the name: a rename there must
  # not turn the fixtures off silently.
  JEV_KEY = Sloplint::Judge::Backend.klass("jev")::KEY
  # present? refuses a key with a control character, and this runs at load
  # time: a bad key in the environment must skip the fixtures, not stop the
  # whole run before a single example.
  KEY_PRESENT = begin
    !Sloplint::Judge::Secret.present?(JEV_KEY).nil?
  rescue ArgumentError
    false
  end
  describe "live fixtures", if: KEY_PRESENT do
    let(:backend) { Sloplint::Judge::Backend.load("jev") }

    # The model's usual answer, not one draw of it. script/calibrate puts
    # agreement between two runs at 99 percent for low-confidence answers,
    # so a fixture the model holds at low confidence flips about one run in
    # a hundred, and sixty fixtures make that one suite run in several. Two
    # draws that agree settle it; a third breaks the tie. A fixture the
    # model has wrong still fails: this hides sampling noise, not a wrong
    # pin.
    def flags?(rule, ex, backend)
      draws = Array.new(2) { Sloplint::Judge::Engine.scan(ex, rules: [rule], backend: backend, strict: true).notes.any? { _1.rule == rule.id } }
      return draws.first if draws.uniq.size == 1

      Sloplint::Judge::Engine.scan(ex, rules: [rule], backend: backend, strict: true).notes.any? { _1.rule == rule.id }
    end

    Sloplint::Judge::RULES.each do |rule|
      rule.examples_bad.each do |ex|
        it "#{rule.id} flags: #{ex[0, 60].inspect}" do
          expect(flags?(rule, ex, backend)).to be(true)
        end
      end
      rule.examples_ok.each do |ex|
        it "#{rule.id} does not flag: #{ex[0, 60].inspect}" do
          expect(flags?(rule, ex, backend)).to be(false)
        end
      end
    end

    # A default run asks the sentence rules only about paragraphs a paragraph
    # rule or the triage question flagged. Each default sentence rule's bad
    # example, set between plain sentences, must reach the sentence rules, or
    # a default run cannot see it inside a long paragraph. The sentence
    # requests themselves are answered here without the backend: the question
    # is whether they are made, not what they find.
    describe "paragraph triage" do
      before_plain = "The export job moved to the new cluster on Tuesday. It now finishes in eleven minutes."
      after_plain = "The old cluster stays up until Friday."
      on = Sloplint::Judge::RULES.reject { _1.confidence == "low" }
      paragraph_rules = on.select { _1.unit == :paragraph }

      # Passes paragraph requests to the backend and records whether any
      # sentence request followed.
      let(:reached) do
        Class.new do
          attr_reader :sentence_asked

          def initialize(backend) = @backend = backend
          def name = @backend.name

          def ask(state, questions)
            return @backend.ask(state, questions) unless state.key?("target")

            @sentence_asked = true
            questions.to_h { |id, q| [id, Sloplint::Judge::Answer.new(type: q["type"], probabilities: [0.0] * (q["criteria"].size - 1) + [1.0], confidence: 1.0, usage: {})] }
          end
        end
      end

      # device-before-claim's own live fixtures miss these two, so the
      # triage question missing them too is the same gap. pending, not
      # skip: the day either one passes, the suite says so.
      known_misses = [
        "The cache holds the last hour of queries once it's warm.",
        "The incident review named five follow-up tasks."
      ]

      on.select { _1.unit == :sentence }.each do |rule|
        rule.examples_bad.each do |ex|
          it "reaches #{rule.id}: #{ex[0, 60].inspect}" do
            pending "device-before-claim misses this example in its own fixtures" if known_misses.any? { ex.start_with?(_1) }
            text = [before_plain, ex, after_plain].join(" ")
            draw = lambda do
              recorder = reached.new(backend)
              Sloplint::Judge::Engine.scan(text, rules: paragraph_rules + [rule], backend: recorder)
              recorder.sentence_asked == true
            end
            # Two draws that agree settle it; a third breaks the tie, as in flags?.
            draws = Array.new(2) { draw.call }
            draws << draw.call if draws.uniq.size > 1
            expect(draws.count(true)).to be > draws.size / 2, "no sentence request in #{draws.count(false)} of #{draws.size} draws"
          end
        end
      end
    end
  end

  it "says when the live fixtures were skipped" do
    skip "no #{JEV_KEY} in the environment or the keychain: the judge's fixtures were not run against the model" unless KEY_PRESENT
  end
end
