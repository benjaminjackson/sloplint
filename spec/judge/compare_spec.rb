# frozen_string_literal: true

require_relative "../support/fake_backend"

RSpec.describe Sloplint::Judge::Compare do
  def backend(p_a:, p_b:, keep_conf: 0.9, drift: 0.1, drift_conf: 0.9)
    FakeBackend.new { |_s, name, _q| name == "keep" ? [{ "A" => p_a, "B" => p_b }, keep_conf] : [drift, drift_conf] }
  end

  it "maps the slot back when the passages were swapped" do
    v = described_class.run("orig", "new", place: "here", backend: backend(p_a: 0.9, p_b: 0.1), swap: true)
    expect(v.keep).to eq("B")
    expect(v.p_keep_b).to eq(0.9)
    v = described_class.run("orig", "new", place: "here", backend: backend(p_a: 0.9, p_b: 0.1), swap: false)
    expect(v.keep).to eq("A")
  end

  it "carries both confidences and the drift, and applies no acceptance rule" do
    v = described_class.run("a", "b", place: "x", backend: backend(p_a: 0.2, p_b: 0.8, drift: 0.7, drift_conf: 0.4), drift: true, swap: false)
    expect(v.to_h.except(:usage)).to eq(keep: "B", p_keep_b: 0.8, keep_confidence: 0.9, drift: 0.7, drift_confidence: 0.4)
  end
end
