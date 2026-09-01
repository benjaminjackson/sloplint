# frozen_string_literal: true

require "json"

# sloplint ships as a Claude Code plugin as well as a gem, so a few facts are
# now stated in two places. Same obligation rules_spec.rb carries for the
# README counts: a fact restated twice gets a test.
RSpec.describe "the Claude Code plugin" do
  ROOT = File.expand_path("..", __dir__)

  def read_json(relative)
    JSON.parse(File.read(File.join(ROOT, relative)))
  end

  it "declares the same version as the gem" do
    # `gem:release` bumps version.rb and knows nothing about plugin.json, and
    # `claude plugin tag` fails when the two disagree.
    expect(read_json(".claude-plugin/plugin.json")["version"]).to eq(Sloplint::VERSION)
  end

  it "names the plugin the same way in both manifests" do
    entries = read_json(".claude-plugin/marketplace.json")["plugins"]
    expect(entries.map { |e| e["name"] }).to eq([read_json(".claude-plugin/plugin.json")["name"]])
  end

  it "keeps the check skill where /sloplint:check resolves" do
    path = File.join(ROOT, "skills/check/SKILL.md")
    expect(File).to exist(path)
    expect(File.read(path)).to match(/^name: check$/)
  end

  it "has no top-level bin/ directory" do
    # claude.ai rejects a plugin that has one -- "Plugin contains a top-level
    # bin/ directory" -- on marketplace sync and on direct upload, which kills
    # organization distribution. The executable lives in exe/ instead.
    expect(Dir).not_to exist(File.join(ROOT, "bin"))
    expect(File).to exist(File.join(ROOT, "exe/sloplint"))
  end

  it "keeps the refusal gate in the skill" do
    # A reworded skill that drops this invites Claude to read the draft and
    # answer from its own judgment, in the format the skill asked for. The
    # reader then believes a linter cleared the writing. Nothing else notices.
    body = File.read(File.join(ROOT, "skills/check/SKILL.md"))
    expect(body).to include("report only what it returns")
    expect(body).to include("never present your own judgment as sloplint's findings")
  end
end
