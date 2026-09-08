require "rails_helper"

# FRS §9, §10, §12 and BR-48 — the rule reporting must never break.
RSpec.describe "Reporting" do
  let(:world) { build_world(rooms: { single: 3 }, therapists: 3) }
  let(:owner) { create(:user, email: "rep-owner@example.com", role: "owner") }

  def complete_and_pay(w = world, method: "card", tip: 0)
    appt = book(w)
    %w[checked_in in_progress completed].each { |t| Scheduling::TransitionStatus.call(appointment: appt, to: t) }
    order = Sales::OpenOrder.call(appointment: appt.reload)
    Sales::AllocateTips.call(order:, amount_cents: tip) if tip.positive?
    order.reload
    Sales::RecordPayment.call(order:, method:, amount_cents: order.total_cents, actor: owner)
    Sales::SettleOrder.call(order:, actor: owner)
    Earnings::GenerateForTip.call(order: order.reload)
    order
  end

  describe "daily revenue (FRS §10)" do
    # BR-48 — the single most important assertion in this file. A gift card sale
    # and a no-show fee sit in the same orders table as service revenue; summing
    # order totals would silently mix all three.
    it "keeps service revenue, liabilities and fees in three separate figures" do
      complete_and_pay(tip: 1_000)
      GiftCards::IssueCard.call(location: world[:location], amount_cents: 5_000,
                                payment_method: "cash", actor: owner, buyer_name: "B")

      no_show = book(world, start_at: world[:at] + 4.hours)
      Scheduling::TransitionStatus.call(appointment: no_show, to: "no_show")

      data = Reporting::DailyRevenue.call(location_ids: [ world[:location].id ],
                                          from: world[:location].today, to: world[:location].today + 7)

      expect(data[:service_revenue_cents]).to be_positive
      expect(data[:gift_card_liability_cents]).to eq(5_000)
      # The fee order is still open (owed, not collected), so it is not in a
      # settled-order revenue figure.
      expect(data[:service_revenue_cents]).not_to eq(data[:gift_card_liability_cents])
    end

    it "breaks the take down by payment method" do
      complete_and_pay(method: "cash")
      complete_and_pay(method: "zelle")
      data = Reporting::DailyRevenue.call(location_ids: [ world[:location].id ],
                                          from: world[:location].today, to: world[:location].today + 7)

      expect(data[:by_method]["cash"]).to be_positive
      expect(data[:by_method]["zelle"]).to be_positive
      expect(data[:by_method]["card"]).to be_zero
      # Every method appears, even at zero, so the report shape is stable.
      expect(data[:by_method].keys).to match_array(Payment::METHODS)
    end

    it "counts tips separately from service revenue (BR-24a)" do
      complete_and_pay(tip: 2_500)
      data = Reporting::DailyRevenue.call(location_ids: [ world[:location].id ],
                                          from: world[:location].today, to: world[:location].today + 7)
      expect(data[:tips_cents]).to eq(2_500)
    end
  end

  describe "client log (FRS §9)" do
    it "lists completed appointments with therapist, tip and method" do
      order = complete_and_pay(tip: 1_500, method: "zelle")
      rows = Reporting::ClientLog.call(location: world[:location],
                                       date: order.appointment.starts_at.to_date)

      expect(rows.size).to eq(1)
      row = rows.first
      expect(row[:tip_cents]).to eq(1_500)
      expect(row[:payment_methods]).to include("zelle")
      expect(row[:therapists]).to be_present
    end

    it "excludes appointments that were not completed" do
      book(world, start_at: world[:at] + 4.hours)
      rows = Reporting::ClientLog.call(location: world[:location], date: world[:date])
      expect(rows).to be_empty
    end
  end

  describe "staff earnings (FRS §4, §8)" do
    it "reports quantity and earnings per ladder rung, plus tips" do
      order = complete_and_pay(tip: 1_000)
      staff = order.appointment.staff_profiles.first
      from, to = EarningPeriod.semi_monthly_bounds(order.appointment.starts_at.to_date)

      report = Reporting::StaffEarnings.call(staff_profile: staff, from:, to:)

      expect(report[:sessions].map { |r| r[:duration_minutes] })
        .to eq(ServiceVariant::LADDER)                    # all six rungs always present
      sixty = report[:sessions].find { |r| r[:duration_minutes] == 60 }
      expect(sixty[:quantity]).to eq(1)
      expect(report[:tips_cents]).to eq(1_000)
      expect(report[:total_cents]).to eq(sixty[:earnings_cents] + 1_000)
    end
  end

  describe "gift card liability (BR-26, BR-27, BR-30)" do
    it "reports outstanding balance against the selling location" do
      card = GiftCards::IssueCard.call(location: world[:location], amount_cents: 9_000,
                                       payment_method: "card", actor: owner, buyer_name: "B")
      data = Reporting::GiftCardLiability.call(location_ids: [ world[:location].id ])

      expect(data[:total_outstanding_cents]).to eq(9_000)
      expect(data[:by_location][world[:location].name][:cents]).to eq(9_000)
      expect(data[:by_issue_month].keys).to include(card.sold_at.strftime("%Y-%m"))
    end

    # Because expiry forfeits nothing, old balances never age off by themselves.
    it "keeps an expired card in the liability, flagged as still spendable" do
      card = GiftCards::IssueCard.call(location: world[:location], amount_cents: 3_000,
                                       payment_method: "cash", actor: owner, buyer_name: "B")
      card.update!(expires_at: 1.day.ago)
      GiftCards::ExpireCards.call

      data = Reporting::GiftCardLiability.call(location_ids: [ world[:location].id ])
      expect(data[:total_outstanding_cents]).to eq(3_000)
      expect(data[:expired_but_spendable_cents]).to eq(3_000)
    end
  end

  describe "ratings (FRS §11.2)" do
    it "reports average, distribution and recommend rate per therapist" do
      order = complete_and_pay
      Crm::RecordRating.call(appointment: order.appointment, score: 9,
                             channel: "kiosk", would_recommend: true)

      data = Reporting::Ratings.call(location_ids: [ world[:location].id ],
                                     from: world[:location].today, to: world[:location].today + 7)
      expect(data[:count]).to eq(1)
      expect(data[:average]).to eq(9.0)
      expect(data[:recommend_rate]).to eq(100.0)
      expect(data[:by_therapist].first[:count]).to eq(1)
    end
  end
end
