require "rails_helper"

RSpec.describe Earnings::UpdateManualLine do
  let(:world) { build_world }
  let(:owner) { create(:user, role: "owner") }

  it "updates a manual amount and audits the correction while the period is open" do
    line = Earnings::AddManualLine.call(
      staff_profile: world[:staff].first, service_date: world[:date],
      amount_cents: 10_000, note: "Off-system session", actor: owner
    )

    described_class.call(line:, amount_cents: 12_500, note: "Corrected", actor: owner)

    expect(line.reload).to have_attributes(amount_cents: 12_500, note: "Corrected")
    expect(AuditLog.where(auditable_type: "EarningLine", auditable_id: line.id,
                          action: "earning_line.updated")).to exist
  end

  it "refuses to edit generated appointment earnings" do
    appointment = book(world)
    %w[checked_in in_progress completed].each do |status|
      Scheduling::TransitionStatus.call(appointment:, to: status)
    end
    line = EarningLine.find_by!(appointment:)

    expect {
      described_class.call(line:, amount_cents: 1, actor: owner)
    }.to raise_error(described_class::Invalid, "only_manual_lines_are_editable")
  end
end
