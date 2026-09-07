require "rails_helper"

# BR-33 — a *pay* rule that looks like a pricing rule, and the one the Owner
# changed late, so it is the most likely to be got wrong.
RSpec.describe Earnings::GenerateForAppointment do
  RATES = { 30 => 2500, 45 => 3500, 60 => 4500, 75 => 5500, 90 => 6500, 120 => 8500 }.freeze

  # build_world seeds a rate ladder of its own; overwrite it so the expected
  # amounts below are the ones under test.
  def rate_up(staff)
    RATES.each do |duration, cents|
      row = StaffSessionRate.find_or_initialize_by(
        staff_profile: staff, duration_minutes: duration, effective_from: Date.new(2026, 1, 1)
      )
      row.update!(rate_cents: cents)
    end
  end

  def add_service(world, name:, duration:, kind: "add_on", price: 3500)
    service = create(:service, name:, kind:)
    variant = create(:service_variant, service:, duration_minutes: duration, base_price_cents: price)
    world[:staff].each { |sp| StaffQualification.create!(staff_profile: sp, service:) }
    variant
  end

  def complete(appt)
    %w[checked_in in_progress completed].each do |to|
      Scheduling::TransitionStatus.call(appointment: appt, to:)
    end
    appt.reload
  end

  let(:world) do
    w = build_world(rooms: { single: 2 }, therapists: 2)
    w[:staff].each { |sp| rate_up(sp) }
    w
  end

  it "pays a plain 60-minute session at the 60 rate" do
    lines = described_class.call(appointment: complete(book(world)))
    expect(lines.size).to eq(1)
    expect(lines.first.duration_minutes).to eq(60)
    expect(lines.first.amount_cents).to eq(RATES[60])
  end

  it "combines a 60-minute service and a 30-minute add-on into one 90-minute line" do
    add_on = add_service(world, name: "Scalp", duration: 30)
    appt = complete(book(world, variant_ids: [ world[:variant].id, add_on.id ]))

    lines = described_class.call(appointment: appt)
    expect(lines.size).to eq(1)
    expect(lines.first.duration_minutes).to eq(90)
    expect(lines.first.amount_cents).to eq(RATES[90])
    # Combining pays *less* than the two parts would separately — intended.
    expect(lines.first.amount_cents).to be < (RATES[60] + RATES[30])
    expect(lines.first.covers_item_ids.size).to eq(2)
  end

  it "splits a 120-minute service and a 30-minute add-on into a 120 and a 30" do
    long = create(:service_variant, service: world[:service], duration_minutes: 120)
    add_on = add_service(world, name: "Feet", duration: 30)
    appt = complete(book(world, variant_ids: [ long.id, add_on.id ]))

    lines = described_class.call(appointment: appt).sort_by(&:duration_minutes)
    expect(lines.map(&:duration_minutes)).to eq([ 30, 120 ])
    expect(lines.sum(&:amount_cents)).to eq(RATES[30] + RATES[120])
    expect(lines.map { |l| l.covers_item_ids.size }).to all(eq(1))
  end

  it "gives an enhancement no earning line — price without time or pay" do
    enh = add_service(world, name: "Hot stone", duration: 0, kind: "enhancement", price: 1500)
    appt = complete(book(world, variant_ids: [ world[:variant].id, enh.id ]))

    lines = described_class.call(appointment: appt)
    expect(lines.size).to eq(1)
    expect(lines.first.duration_minutes).to eq(60)
  end

  it "pays each therapist of a two-therapist service a full session rate (BR-34)" do
    couples_service = create(:service, name: "Couples")
    couples = create(:service_variant, service: couples_service, duration_minutes: 90,
                                       therapist_count: 2, required_client_capacity: 2)
    w = build_world(rooms: { couple: 1 }, therapists: 2)
    w[:staff].each do |sp|
      rate_up(sp)
      StaffQualification.create!(staff_profile: sp, service: couples_service)
    end

    lines = described_class.call(appointment: complete(book(w, variant_ids: [ couples.id ])))
    expect(lines.size).to eq(2)
    expect(lines.map(&:amount_cents)).to all(eq(RATES[90]))
    expect(lines.map(&:staff_profile_id).uniq.size).to eq(2)
  end

  it "snapshots the rate in force on the service date (BR-35)" do
    staff = world[:staff].first
    StaffSessionRate.where(staff_profile: staff, duration_minutes: 60)
                    .update_all(effective_to: Date.current - 1)
    StaffSessionRate.create!(staff_profile: staff, duration_minutes: 60,
                             rate_cents: 9_999, effective_from: Date.current)

    line = described_class.call(appointment: complete(book(world, staff_profile_ids: [ staff.id ]))).first
    expect(line.rate_cents).to eq(9_999)
  end

  it "does not pay an appointment that is not completed (BR-17)" do
    expect(described_class.call(appointment: book(world))).to be_empty
  end

  it "is idempotent — settling twice does not pay twice" do
    appt = complete(book(world))
    described_class.call(appointment: appt)
    expect { described_class.call(appointment: appt) }.not_to change(EarningLine, :count)
  end
end
