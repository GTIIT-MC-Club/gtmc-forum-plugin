# frozen_string_literal: true

RSpec.describe DiscourseGtmc::SeenPlayer do
  it "records each name once and keeps the first time and server" do
    freeze_time(Time.zone.parse("2026-11-24 10:00"))
    described_class.record(server_id: "survival", mc_names: %w[Steve Alex Steve])

    freeze_time(Time.zone.parse("2026-11-24 11:00"))
    described_class.record(server_id: "creative", mc_names: %w[Steve Herobrine])

    rows = described_class.order(:mc_name).pluck(:mc_name, :first_server_id, :first_seen_at)
    expect(rows.map { |name, server, _| [name, server] }).to eq(
      [%w[Alex survival], %w[Herobrine creative], %w[Steve survival]],
    )
    expect(rows.find { |name, _, _| name == "Steve" }.last).to eq_time(
      Time.zone.parse("2026-11-24 10:00"),
    )
  end

  it "does nothing for an empty list" do
    expect { described_class.record(server_id: "survival", mc_names: []) }.not_to change {
      described_class.count
    }
  end

  it "treats names that differ only in case as different players" do
    described_class.record(server_id: "survival", mc_names: %w[Steve])

    expect(described_class.any_seen?(%w[steve])).to eq(false)
    expect(described_class.any_seen?(%w[Notch Steve])).to eq(true)
    expect(described_class.any_seen?([])).to eq(false)
  end
end
