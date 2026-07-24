# frozen_string_literal: true

RSpec.describe "Sloplint::RULES" do
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

  # The README quotes the catalog size and a per-category breakdown. Nothing
  # regenerates those, so they go stale the moment a rule is added.
  describe "the README rule counts" do
    readme = File.read(File.expand_path("../README.md", __dir__))

    it "quotes the catalog total" do
      expect(readme).to match(/^#{Sloplint::RULES.size} rules across/)
    end

    Sloplint::RULES.group_by(&:category).each do |category, rules|
      it "quotes the #{category} count" do
        expect(readme).to include("**#{category}** (#{rules.size})")
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

  # Each rule's examples_ok is only ever checked against that one rule
  # (see the "ignores:" tests above). A fixture proven clean against its own
  # rule can still trip a DIFFERENT rule in the catalog -- this runs every
  # examples_ok against the full default catalog to catch that.
  describe "cross-rule false positives" do
    Sloplint::RULES.each do |owner|
      owner.examples_ok.each do |example|
        it "#{owner.id}'s ok-fixture #{example.inspect} trips no other rule" do
          notes = Sloplint::Engine.scan(example)
          expect(notes.map(&:rule)).to eq([])
        end
      end
    end
  end
end
