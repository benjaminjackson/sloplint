# frozen_string_literal: true

require_relative "../support/fake_backend"

RSpec.describe "Sloplint::Judge::RULES" do
  let(:rules) { Sloplint::Judge::RULES }

  it "has unique ids that do not collide with sloplint's ids or categories" do
    ids = rules.map(&:id)
    expect(ids).to eq(ids.uniq)
    taken = Sloplint::RULES.flat_map { |r| [r.id, r.category] }
    expect(ids & taken).to be_empty
    expect(rules.map(&:category).uniq & taken).to be_empty
  end

  it "ships the eight rules docs/JUDGE.md lists, in its two categories" do
    doc = File.read(File.expand_path("../../docs/JUDGE.md", __dir__), encoding: "UTF-8")
    rules.each { |r| expect(doc).to include("**#{r.id}**"), "#{r.id} missing from docs/JUDGE.md" }
    expect(rules.group_by(&:category).transform_values(&:size)).to eq("paragraph" => 3, "sentence" => 5)
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
  KEY_PRESENT = !Sloplint::Judge::Secret.present?("TYPESAFE_API_KEY").nil?
  describe "live fixtures", if: KEY_PRESENT do
    let(:backend) { Sloplint::Judge::Backend.load("jev") }

    Sloplint::Judge::RULES.each do |rule|
      rule.examples_bad.each do |ex|
        it "#{rule.id} flags: #{ex[0, 60].inspect}" do
          notes = Sloplint::Judge::Engine.scan(ex, rules: [rule], backend: backend, strict: true).notes
          expect(notes.map(&:rule)).to include(rule.id)
        end
      end
      rule.examples_ok.each do |ex|
        it "#{rule.id} does not flag: #{ex[0, 60].inspect}" do
          notes = Sloplint::Judge::Engine.scan(ex, rules: [rule], backend: backend, strict: true).notes
          expect(notes.map(&:rule)).not_to include(rule.id)
        end
      end
    end
  end

  it "says when the live fixtures were skipped" do
    skip "no TYPESAFE_API_KEY in the environment or the keychain: the judge's fixtures were not run against the model" unless KEY_PRESENT
  end
end
