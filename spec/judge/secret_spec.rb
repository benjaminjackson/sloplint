# frozen_string_literal: true

require_relative "../../lib/sloplint/judge/secret"

# Nothing here touches a real keychain: the platform and the child process are
# stubbed, and the assertions are on the exact argv the tool would receive.
RSpec.describe Sloplint::Judge::Secret do
  let(:name) { "TYPESAFE_API_KEY" }

  around do |ex|
    saved = ENV.delete(name)
    ex.run
  ensure
    ENV[name] = saved
  end

  def darwin! = allow(described_class).to receive(:platform).and_return(:darwin)

  def linux!
    allow(described_class).to receive(:platform).and_return(:linux)
    allow(File).to receive(:executable?).and_call_original
    allow(File).to receive(:executable?).with("/usr/bin/secret-tool").and_return(true)
  end

  it "takes the environment first and says so" do
    ENV[name] = "from-env"
    expect(described_class).not_to receive(:run)
    expect(described_class.fetch(name)).to eq(["from-env", "environment"])
    expect(described_class.present?(name)).to eq("environment")
  end

  it "falls through to the macOS keychain with the exact argv, and strips the newline" do
    darwin!
    expect(described_class).to receive(:run)
      .with("/usr/bin/security", "find-generic-password", "-s", "sloplint-judge", "-a", name, "-w")
      .and_return("from-keychain\n")
    expect(described_class.fetch(name)).to eq(["from-keychain", "keychain"])
  end

  it "falls through to secret-tool on Linux, found at a fixed path and not on PATH" do
    linux!
    expect(described_class).to receive(:run)
      .with("/usr/bin/secret-tool", "lookup", "service", "sloplint-judge", "account", name)
      .and_return("from-libsecret")
    expect(described_class.fetch(name)).to eq(["from-libsecret", "keychain"])
    expect(described_class.store_command(name))
      .to eq(["/usr/bin/secret-tool", "store", "--label=sloplint-judge", "service", "sloplint-judge", "account", name])
  end

  it "answers present? without reading the value" do
    darwin!
    expect(described_class).to receive(:run)
      .with("/usr/bin/security", "find-generic-password", "-s", "sloplint-judge", "-a", name)
      .and_return("keychain: \"/Users/x/Library/Keychains/login.keychain-db\"\n")
    expect(described_class.present?(name)).to eq("keychain")
    expect(described_class).to receive(:run).and_return(nil)
    expect(described_class.present?(name)).to be_nil
  end

  it "is nil with no item, no tool, or no supported platform" do
    darwin!
    allow(described_class).to receive(:run).and_return(nil)
    expect(described_class.fetch(name)).to be_nil
    allow(described_class).to receive(:platform).and_return(nil)
    expect(described_class.fetch(name)).to be_nil
    expect(described_class.present?(name)).to be_nil
    expect(described_class.store_command(name)).to be_nil
  end

  it "stores through the tool's own prompt: -w last, no value anywhere in argv" do
    darwin!
    expect(described_class.store_command(name))
      .to eq(["/usr/bin/security", "add-generic-password", "-U", "-s", "sloplint-judge", "-a", name, "-w"])
    expect(described_class.delete_command(name))
      .to eq(["/usr/bin/security", "delete-generic-password", "-s", "sloplint-judge", "-a", name])
    linux!
    expect(described_class.delete_command(name))
      .to eq(["/usr/bin/secret-tool", "clear", "service", "sloplint-judge", "account", name])
  end

  it "stored? looks at the keychain even when the environment has a key" do
    darwin!
    ENV[name] = "from-env"
    expect(described_class).to receive(:run).and_return(nil)
    expect(described_class.stored?(name)).to be(false)
    expect(described_class.present?(name)).to eq("environment")
  end

  it "refuses a value with a control character, without printing the value" do
    ENV[name] = "abc\ndef"
    expect { described_class.fetch(name) }.to raise_error(ArgumentError) { |e|
      expect(e.message).to include("control character")
      expect(e.message).not_to include("abc")
    }
  end

  it "returns nil from run for a missing binary or a non-zero exit" do
    expect(described_class.run("/nonexistent/binary-for-this-spec")).to be_nil
    expect(described_class.run("/bin/sh", "-c", "exit 44")).to be_nil
    expect(described_class.run("/bin/sh", "-c", "echo hi")).to eq("hi\n")
  end

  it "kills a run that outlives the timeout and says a dialog may be waiting" do
    stub_const("Sloplint::Judge::Secret::TIMEOUT", 0.2)
    expect { described_class.run("/bin/sh", "-c", "sleep 5") }.to raise_error(ArgumentError, /dialog may be waiting/)
  end
end
