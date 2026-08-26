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
    readme = File.read(File.expand_path("../README.md", __dir__), encoding: "UTF-8")

    it "quotes the catalog total" do
      expect(readme).to match(/^#{Sloplint::RULES.size} rules across/)
    end

    Sloplint::RULES.group_by(&:category).each do |category, rules|
      it "quotes the #{category} count" do
        expect(readme).to include("**#{category}** (#{rules.size})")
      end
    end
  end

  # docs/SPEC.md lists the catalog too, and had drifted ten rules behind the
  # code before anyone noticed. Nothing regenerates it either, so pin it the
  # same way as the README: every id must be named somewhere in the doc.
  describe "the SPEC rule catalog" do
    spec_doc = File.read(File.expand_path("../docs/SPEC.md", __dir__), encoding: "UTF-8")

    Sloplint::RULES.each do |rule|
      it "lists #{rule.id}" do
        expect(spec_doc).to include("`#{rule.id}`")
      end
    end
  end

  # worth-naming and worth-saying-plainly are one construction with and
  # without a manner adverb, and both used to fire on the adverb-bearing
  # form. worth-naming now yields. The cross-rule check above only scans
  # examples_ok, so it would never have caught the overlap.
  describe "the worth-* pair" do
    it "reports the adverb-bearing form once, at warning" do
      notes = Sloplint::Engine.scan("It's worth naming plainly what went wrong.")
      expect(notes.map(&:rule)).to eq(%w[worth-saying-plainly])
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
    # em-dash flags every dash by design, so em-dash-overuse's ok-fixtures (one
    # or two dashes -- clean for *overuse*) legitimately trip it. Only this pair.
    overlaps = { "em-dash-overuse" => %w[em-dash] }

    Sloplint::RULES.each do |owner|
      owner.examples_ok.each do |example|
        it "#{owner.id}'s ok-fixture #{example.inspect} trips no other rule" do
          notes = Sloplint::Engine.scan(example)
          expect(notes.map(&:rule) - overlaps.fetch(owner.id, [])).to eq([])
        end
      end
    end
  end
end
