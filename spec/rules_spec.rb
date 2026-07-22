# frozen_string_literal: true

RSpec.describe Sloplint::RULES do
  it "has unique rule ids" do
    ids = Sloplint::RULES.map(&:id)
    expect(ids).to eq(ids.uniq)
  end

  it "uses only known categories and severities" do
    categories = %w[rhetorical-tic puffery structure hedging]
    severities = %w[error warning info]
    Sloplint::RULES.each do |rule|
      expect(categories).to include(rule.category), "#{rule.id} category"
      expect(severities).to include(rule.severity), "#{rule.id} severity"
    end
  end

  Sloplint::RULES.each do |rule|
    describe rule.id do
      it "ships at least one bad and one ok fixture" do
        expect(rule.examples_bad).not_to be_empty
        expect(rule.examples_ok).not_to be_empty
      end

      rule.examples_bad.each do |example|
        it "flags: #{example.inspect}" do
          notes = Sloplint::Engine.scan(example, rules: [rule])
          expect(notes).not_to be_empty
        end
      end

      rule.examples_ok.each do |example|
        it "ignores: #{example.inspect}" do
          notes = Sloplint::Engine.scan(example, rules: [rule])
          expect(notes).to be_empty
        end
      end
    end
  end

  describe "count_group rules" do
    it "counts items in a no-x-no-y chain" do
      note = Sloplint::Engine.scan("No fluff, no filler, no jargon.").find { |n| n.rule == "no-x-no-y" }
      expect(note.count).to eq(3)
      expect(note.message).to include("3 items")
    end
  end
end
