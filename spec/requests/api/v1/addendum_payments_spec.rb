require "rails_helper"

# FRS Addendum: split payments (§1), correcting and deleting a completed visit
# (§2), tips and transaction fees in total revenue (§3, §5), and the editable
# session quantity (§4) — each through the API the console uses.
RSpec.describe "FRS addendum — payments, corrections, revenue, earnings", type: :request do
  let(:world) { build_world(rooms: { single: 2 }, therapists: 2) }
  let(:owner) { create(:user, role: "owner") }
  let(:manager) { create(:user, role: "manager", location: world[:location]) }
  let(:first_therapist) { world[:staff].first }
  let(:second_therapist) { world[:staff].last }

  def json = JSON.parse(response.body)

  def visit_day(appt) = appt.starts_at.in_time_zone(world[:location].tz).to_date

  # Booked to the first therapist and taken to checkout: the order is open and
  # the visit completed, exactly where the desk is when the client pays.
  def at_checkout
    appt = book(world, staff_profile_ids: [ first_therapist.id ])
    order = Scheduling::CompleteForCheckout.call(appointment: appt, actor: manager)
    [ appt, order ]
  end

  def gift_card(cents)
    GiftCards::IssueCard.call(location: world[:location], amount_cents: cents, payment_method: "cash", actor: owner)
  end

  def revenue(appt)
    day = visit_day(appt)
    Reporting::DailyRevenue.call(location_ids: [ world[:location].id ], from: day, to: day)
  end

  describe "§1 split payment" do
    it "takes a gift card and Venmo that add up to the total, and closes the visit in one step" do
      appt, order = at_checkout
      card = gift_card(7_000)
      post "/api/v1/orders/#{order.id}/tips", params: { amount_cents: 1_500 }, headers: auth_headers(manager), as: :json
      post "/api/v1/orders/#{order.id}/transaction_fee", params: { amount_cents: 500 },
                                                          headers: auth_headers(manager), as: :json
      expect(json).to include("total_cents" => 10_000, "transaction_fee_cents" => 500)

      post "/api/v1/orders/#{order.id}/checkout",
           params: { payments: [ { method: "gift_card", code: card.code, amount_cents: 7_000 },
                                 { method: "venmo", amount_cents: 3_000 } ] },
           headers: auth_headers(manager), as: :json

      expect(response).to have_http_status(:ok)
      expect(json).to include("status" => "paid", "outstanding_cents" => 0)
      expect(card.reload.current_balance_cents).to eq(0)
      expect(appt.reload.status).to eq("completed")
      expect(EarningLine.where(appointment_id: appt.id).pluck(:source)).to contain_exactly("session", "tip")
    end

    it "refuses parts that do not add up to the total, and records none of them" do
      _appt, order = at_checkout
      card = gift_card(7_000)

      post "/api/v1/orders/#{order.id}/checkout",
           params: { payments: [ { method: "gift_card", code: card.code, amount_cents: 7_000 },
                                 { method: "cash", amount_cents: 500 } ] },
           headers: auth_headers(manager), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to include("code" => "split_total_mismatch", "details" => { "due_cents" => 8_000 })
      expect(order.reload).to have_attributes(status: "open")
      expect(order.payments).to be_empty
      expect(card.reload.current_balance_cents).to eq(7_000)
    end
  end

  describe "§3 and §5 revenue" do
    it "counts the tip and the transaction fee in total revenue, each on its own line" do
      appt, order = at_checkout
      Sales::AllocateTips.call(order:, amount_cents: 2_000, actor: manager)
      Sales::SetTransactionFee.call(order:, amount_cents: 300, actor: manager)
      Sales::TakePayments.call(order:, parts: [ { method: "card", amount_cents: 10_300 } ], actor: manager)

      expect(revenue(appt)).to include(service_revenue_cents: 8_000, tips_cents: 2_000,
                                       transaction_fees_cents: 300, total_revenue_cents: 10_300,
                                       collected_cents: 10_300)
    end

    it "gives each location its own totals in the system-wide view" do
      appt, order = at_checkout
      Sales::TakePayments.call(order:, parts: [ { method: "cash", amount_cents: 8_000 } ], actor: manager)
      other = create(:location, code: "other#{SecureRandom.hex(2)}", name: "Other")
      day = visit_day(appt)

      get "/api/v1/reports/daily_revenue",
          params: { location_ids: [ world[:location].id, other.id ], from: day, to: day },
          headers: auth_headers(owner)

      expect(json["total_revenue_cents"]).to eq(8_000)
      expect(json["by_location"].map { |r| [ r["location_id"], r["total_revenue_cents"] ] })
        .to contain_exactly([ world[:location].id, 8_000 ], [ other.id, 0 ])
    end
  end

  describe "§2 correcting a completed visit" do
    def settled_visit
      appt, order = at_checkout
      Sales::AllocateTips.call(order:, amount_cents: 1_000, actor: manager)
      Sales::TakePayments.call(order:, parts: [ { method: "card", amount_cents: 9_000 } ], actor: manager)
      appt
    end

    it "changes therapist, tip, fee and payments, and the reports and earnings follow" do
      appt = settled_visit

      post "/api/v1/appointments/#{appt.id}/correct_visit",
           params: { reason: "Wrong therapist and tip keyed", staff_profile_ids: [ second_therapist.id ],
                     tip_cents: 2_000, transaction_fee_cents: 400,
                     payments: [ { method: "cash", amount_cents: 6_000 }, { method: "zelle", amount_cents: 4_400 } ] },
           headers: auth_headers(manager), as: :json

      expect(response).to have_http_status(:ok)
      order = appt.order.reload
      expect(order).to have_attributes(status: "paid", total_cents: 10_400, tip_cents: 2_000,
                                       transaction_fee_cents: 400, outstanding_cents: 0)
      # The original card payment is voided, never edited (BR-23).
      expect(order.payments.pluck(:method, :status, :amount_cents))
        .to contain_exactly([ "card", "voided", 9_000 ], [ "cash", "captured", 6_000 ], [ "zelle", "captured", 4_400 ])
      expect(appt.reload.staff_profiles).to eq([ second_therapist ])

      report = revenue(appt)
      expect(report).to include(tips_cents: 2_000, transaction_fees_cents: 400, total_revenue_cents: 10_400)
      expect(report[:by_method]).to include("card" => 0, "cash" => 6_000, "zelle" => 4_400)

      # Pay moves to the therapist who actually did the visit.
      expect(EarningLine.where(appointment_id: appt.id, staff_profile: first_therapist)).to be_empty
      expect(EarningLine.where(appointment_id: appt.id, staff_profile: second_therapist).pluck(:source, :amount_cents))
        .to contain_exactly([ "session", 60 * 75 ], [ "tip", 2_000 ])
      expect(AuditLog.where(action: "appointment.visit_corrected").count).to eq(1)
    end

    it "refuses payments that do not cover the corrected total, and changes nothing" do
      appt = settled_visit

      post "/api/v1/appointments/#{appt.id}/correct_visit",
           params: { reason: "Tip was higher", tip_cents: 3_000, payments: [ { method: "card", amount_cents: 9_000 } ] },
           headers: auth_headers(manager), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]).to include("code" => "split_total_mismatch", "details" => { "due_cents" => 11_000 })
      expect(appt.order.reload).to have_attributes(tip_cents: 1_000, paid_cents: 9_000)
    end

    it "needs a reason, and refuses once the pay period is locked" do
      appt = settled_visit
      post "/api/v1/appointments/#{appt.id}/correct_visit",
           params: { payments: [ { method: "card", amount_cents: 9_000 } ] }, headers: auth_headers(manager), as: :json
      expect(json.dig("error", "code")).to eq("reason_required")

      starts_on, ends_on = EarningPeriod.semi_monthly_bounds(visit_day(appt))
      EarningPeriod.create!(starts_on:, ends_on:, kind: "semi_monthly", status: "locked")
      post "/api/v1/appointments/#{appt.id}/correct_visit",
           params: { reason: "late fix", payments: [ { method: "card", amount_cents: 9_000 } ] },
           headers: auth_headers(manager), as: :json
      expect(json.dig("error", "code")).to eq("period_locked")
    end
  end

  describe "§2 deleting a completed visit" do
    it "is the Owner's, voids the money, puts the gift card balance back and clears it from reports" do
      appt, order = at_checkout
      card = gift_card(3_000)
      Sales::TakePayments.call(order:, actor: manager,
                               parts: [ { method: "gift_card", code: card.code, amount_cents: 3_000 },
                                        { method: "cash", amount_cents: 5_000 } ])

      post "/api/v1/appointments/#{appt.id}/delete_visit", params: { reason: "Entered twice" },
                                                           headers: auth_headers(manager), as: :json
      expect(response).to have_http_status(:forbidden)

      post "/api/v1/appointments/#{appt.id}/delete_visit", params: { reason: "Entered twice" },
                                                           headers: auth_headers(owner), as: :json
      expect(response).to have_http_status(:no_content)

      expect(appt.reload.status).to eq("deleted")
      expect(order.reload.status).to eq("voided")
      expect(order.payments.captured).to be_empty
      expect(card.reload).to have_attributes(current_balance_cents: 3_000, status: "active")
      expect(card.drifted?).to be(false)
      expect(EarningLine.where(appointment_id: appt.id)).to be_empty
      expect(revenue(appt)).to include(total_revenue_cents: 0, collected_cents: 0)

      get "/api/v1/appointments/calendar", params: { location_id: world[:location].id, date: visit_day(appt) },
                                           headers: auth_headers(owner)
      expect(json["appointments"].pluck("id")).not_to include(appt.id)
    end
  end

  describe "§4 editable session quantity" do
    it "sets the number of sessions and the earnings follow, with the correction on record" do
      _appt, order = at_checkout
      Sales::TakePayments.call(order:, parts: [ { method: "card", amount_cents: 8_000 } ], actor: manager)
      from, to = EarningPeriod.semi_monthly_bounds(world[:date])

      put "/api/v1/reports/staff_earnings/quantity",
          params: { staff_profile_id: first_therapist.id, duration_minutes: 60, from:, to:, quantity: 3 },
          headers: auth_headers(owner), as: :json

      expect(response).to have_http_status(:ok)
      row = json["sessions"].find { |r| r["duration_minutes"] == 60 }
      expect(row).to include("quantity" => 3, "earnings_cents" => 3 * 60 * 75)
      manual = EarningLine.find_by!(source: "manual", staff_profile: first_therapist)
      expect(manual).to have_attributes(quantity: 2, amount_cents: 2 * 60 * 75, service_date: to)
      expect(manual.note).to include("corrected from 1 to 3")

      put "/api/v1/reports/staff_earnings/quantity",
          params: { staff_profile_id: first_therapist.id, duration_minutes: 60, from:, to:, quantity: -1 },
          headers: auth_headers(owner), as: :json
      expect(json.dig("error", "code")).to eq("quantity_invalid")

      put "/api/v1/reports/staff_earnings/quantity",
          params: { staff_profile_id: first_therapist.id, duration_minutes: 60, from:, to:, quantity: 2 },
          headers: auth_headers(manager), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end
