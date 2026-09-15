require "rails_helper"

# Regression specs for the conflicts found between the platform feedback
# features (docs/platform-feedback-conflicts.md, C1–C12) and the business
# decisions taken on deposits and Manager discounts.
RSpec.describe "Pre-release conflict fixes" do
  let(:world) { build_world(rooms: { single: 2 }, therapists: 2) }
  let(:owner) { create(:user, role: "owner") }
  let(:manager) { create(:user, role: "manager", location: world[:location]) }
  let(:therapist) { world[:staff].first }

  def complete(appt)
    %w[checked_in in_progress completed].each { |to| Scheduling::TransitionStatus.call(appointment: appt, to:) }
    appt.reload
  end

  def add_on_variant
    service = create(:service, kind: "add_on", name: "Scalp #{SecureRandom.hex(2)}")
    world[:staff].each { |sp| StaffQualification.create!(staff_profile: sp, service:) }
    create(:service_variant, service:, duration_minutes: 30, base_price_cents: 3_500)
  end

  describe "C1/C2 — an order opened early follows its appointment" do
    it "re-prices the order when an add-on is added after a calendar discount" do
      appt = book(world, staff_profile_ids: [ therapist.id ])
      order = Sales::OpenOrder.call(appointment: appt, actor: owner)
      Sales::ApplyDiscount.call(order:, amount_cents: 1_000, actor: owner, reason: "Loyalty")

      Scheduling::AddAppointmentItem.call(appointment: appt, variant_ids: [ add_on_variant.id ], actor: owner)

      order.reload
      expect(order.subtotal_cents).to eq(appt.reload.total_price_cents)
      expect(order.total_cents).to eq(appt.total_price_cents - 1_000)
    end

    it "moves the order and its discount with a reschedule instead of orphaning it" do
      appt = book(world, staff_profile_ids: [ therapist.id ])
      order = Sales::OpenOrder.call(appointment: appt, actor: owner)
      Sales::ApplyDiscount.call(order:, amount_cents: 1_000, actor: owner, reason: "Loyalty")

      moved = Scheduling::RescheduleAppointment.call(appointment: appt, start_at: world[:at] + 3.hours, actor: owner)

      expect(order.reload.appointment_id).to eq(moved.id)
      expect(order.status).to eq("open")
      expect(Sales::OpenOrder.call(appointment: moved).discount_cents).to eq(1_000)
      expect(Order.where(appointment_id: appt.id)).to be_empty
    end

    it "refuses to change the appointment once money has been taken against the order" do
      appt = book(world, staff_profile_ids: [ therapist.id ])
      order = Sales::OpenOrder.call(appointment: appt, actor: owner)
      Sales::RecordPayment.call(order:, method: "cash", amount_cents: 1_000, actor: owner)

      expect {
        Scheduling::AddAppointmentItem.call(appointment: appt, variant_ids: [ add_on_variant.id ], actor: owner)
      }.to raise_error(Sales::OrderLocked, "order_has_payments")
      expect(appt.reload.appointment_items.count).to eq(1)
    end

    it "voids an unpaid early order when the visit is cancelled" do
      appt = book(world, staff_profile_ids: [ therapist.id ])
      order = Sales::OpenOrder.call(appointment: appt, actor: owner)

      Scheduling::TransitionStatus.call(appointment: appt, to: "cancelled", actor: owner,
                                        now: appt.starts_at - 2.days)

      expect(order.reload.status).to eq("voided")
    end
  end

  describe "C3 — discounts are capped" do
    let(:order) { Sales::OpenOrder.call(appointment: complete(book(world)), actor: owner) }

    it "never takes an order below zero" do
      expect {
        Sales::ApplyDiscount.call(order:, amount_cents: order.subtotal_cents + 1, actor: owner, reason: "x")
      }.to raise_error(Sales::ApplyDiscount::Invalid, "discount_exceeds_remaining")
    end

    it "never discounts below what has already been paid" do
      Sales::RecordPayment.call(order:, method: "cash", amount_cents: 6_000, actor: owner)

      expect {
        Sales::ApplyDiscount.call(order:, amount_cents: 2_001, actor: owner, reason: "x")
      }.to raise_error(Sales::ApplyDiscount::Invalid, "discount_exceeds_remaining")
      Sales::ApplyDiscount.call(order:, amount_cents: 2_000, actor: owner, reason: "x")
      expect(order.reload.outstanding_cents).to eq(0)
    end

    it "requires a reason" do
      expect {
        Sales::ApplyDiscount.call(order:, amount_cents: 100, actor: owner, reason: " ")
      }.to raise_error(Sales::ApplyDiscount::Invalid, "reason_required")
    end
  end

  describe "Manager discount limit" do
    let(:order) { Sales::OpenOrder.call(appointment: complete(book(world)), actor: manager) }

    it "lets a Manager discount up to the location's limit, counted across the order" do
      world[:location].update!(manager_discount_limit_percent: 20)   # 20% of $80 = $16

      Sales::ApplyDiscount.call(order:, amount_cents: 1_000, actor: manager, reason: "Late start")
      Sales::ApplyDiscount.call(order:, amount_cents: 600, actor: manager, reason: "Late start")
      expect {
        Sales::ApplyDiscount.call(order:, amount_cents: 1, actor: manager, reason: "One more")
      }.to raise_error(Sales::ApplyDiscount::Invalid, "discount_above_manager_limit")
    end

    it "leaves the Owner unlimited, and refuses a therapist outright" do
      Sales::ApplyDiscount.call(order:, amount_cents: 7_000, actor: owner, reason: "Complaint")
      expect {
        Sales::ApplyDiscount.call(order:, amount_cents: 100, actor: therapist.user, reason: "x")
      }.to raise_error(Sales::ApplyDiscount::Invalid, "discount_not_permitted")
    end

    it "records who gave the discount and why" do
      Sales::ApplyDiscount.call(order:, amount_cents: 500, actor: manager, reason: "Room was cold")
      log = AuditLog.where(action: "order.discounted").last
      expect(log.actor_user).to eq(manager)
      expect(log.changes_json).to include("reason" => "Room was cold")
    end
  end

  describe "C3 — membership credit respects discounts already given" do
    it "caps the credit at what is left of the order" do
      appt = complete(book(world))
      order = Sales::OpenOrder.call(appointment: appt, actor: owner)
      Sales::ApplyDiscount.call(order:, amount_cents: 2_000, actor: owner, reason: "x")
      membership = Membership.create!(client: world[:client], location: world[:location], status: "active",
                                      price_cents: 8_000, credits_balance: 1,
                                      default_service_variant: world[:variant], enrolled_at: Time.current,
                                      current_period_start: Time.current, current_period_end: 1.month.from_now)

      Memberships::RedeemCredit.call(membership:, order:, actor: owner)

      expect(order.reload.total_cents).to eq(0)
    end
  end

  describe "C4 — daily revenue nets out discounts" do
    it "reports service revenue after manual discounts, with the discount on its own line" do
      appt = complete(book(world))
      order = Sales::OpenOrder.call(appointment: appt, actor: owner)
      Sales::ApplyDiscount.call(order:, amount_cents: 2_000, actor: owner, reason: "x")
      Sales::RecordPayment.call(order:, method: "card", amount_cents: 6_000, actor: owner)
      Sales::SettleOrder.call(order:, actor: owner)

      today = world[:location].today
      report = Reporting::DailyRevenue.call(location_ids: [ world[:location].id ], from: today, to: today)

      expect(report).to include(gross_service_revenue_cents: 8_000, discounts_cents: 2_000,
                                service_revenue_cents: 6_000, collected_cents: 6_000)
    end
  end

  describe "C5 — approval survives a move, and auto-approval survives bad records" do
    it "keeps a moved request pending, with one live request carrying the original clock" do
      appt = book(world, requested_staff_profile_id: therapist.id)
      asked_at = appt.approval_request.created_at

      moved = travel_to(10.minutes.from_now) do
        Scheduling::RescheduleAppointment.call(appointment: appt, start_at: world[:at] + 2.hours, actor: owner)
      end

      expect(moved.status).to eq("pending_approval")
      expect(ApprovalRequest.pending.pluck(:appointment_id)).to eq([ moved.id ])
      expect(moved.reload.approval_request.created_at).to be_within(1.second).of(asked_at)
      expect(appt.approval_request.reload.status).to eq("withdrawn")
    end

    it "keeps repeats of a pending request pending" do
      appt = book(world, requested_staff_profile_id: therapist.id)
      date = world[:date] + 7
      tz = world[:location].tz
      world[:staff].each do |sp|
        create(:shift, staff_profile: sp, location: world[:location], work_date: date,
                       starts_at: tz.local(date.year, date.month, date.day, 9), ends_at: tz.local(date.year, date.month, date.day, 22))
      end

      repeats = Scheduling::RepeatAppointment.call(appointment: appt, interval_weeks: 1, count: 1, actor: owner)
      expect(repeats.map(&:status)).to eq([ "pending_approval" ])
    end

    it "closes a stale request and still auto-approves the ones behind it" do
      stale = book(world, requested_staff_profile_id: therapist.id)
      stale.update_columns(status: "cancelled")
      live = book(world, requested_staff_profile_id: world[:staff].last.id, start_at: world[:at] + 3.hours)

      AutoApproveTherapistRequestsJob.new.perform(now: 1.hour.from_now)

      expect(stale.approval_request.reload.status).to eq("withdrawn")
      expect(live.reload.status).to eq("scheduled")
    end
  end

  describe "C6 — no completion or settlement before assignment" do
    it "refuses to complete a provisional booking, and pays nobody" do
      appt = book(world, provisional: true)
      %w[checked_in in_progress].each { |to| Scheduling::TransitionStatus.call(appointment: appt, to:) }

      expect { Scheduling::TransitionStatus.call(appointment: appt, to: "completed") }
        .to raise_error(Scheduling::TransitionStatus::Invalid, "therapist_assignment_required")
      expect(EarningLine.where(appointment: appt)).to be_empty
    end

    it "refuses to settle an order before the visit is completed" do
      appt = book(world)
      order = Sales::OpenOrder.call(appointment: appt, actor: owner)
      Sales::RecordPayment.call(order:, method: "cash", amount_cents: order.total_cents, actor: owner)

      expect { Sales::SettleOrder.call(order:, actor: owner) }
        .to raise_error(Sales::SettleOrder::Unsettled, "appointment_not_completed")
    end
  end

  describe "one-step checkout" do
    it "completes the visit and opens the order in one call" do
      appt = book(world)
      order = Scheduling::CompleteForCheckout.call(appointment: appt, actor: owner)

      expect(appt.reload.status).to eq("completed")
      expect(order.appointment_id).to eq(appt.id)
      expect(appt.appointment_status_events.pluck(:to_status)).to include("checked_in", "in_progress", "completed")
    end

    it "changes nothing when the therapist is not yet assigned" do
      appt = book(world, provisional: true)
      expect { Scheduling::CompleteForCheckout.call(appointment: appt, actor: owner) }
        .to raise_error(Scheduling::TransitionStatus::Invalid, "therapist_assignment_required")
      expect(appt.reload.status).to eq("scheduled")
    end
  end

  describe "C7/C8 — messages" do
    it "never names a provisional therapist, and skips reminders for a visit that is off" do
      appt = book(world, provisional: true)
      expect(Notifications::Confirm.details_for(appt)[:therapist]).to be_nil

      reminder = Notification.find_by!(appointment: appt, template_key: "appointment_reminder_2h", channel: "sms")
      Scheduling::TransitionStatus.call(appointment: appt, to: "cancelled", now: appt.starts_at - 2.days)
      Notifications::Deliver.call(notification: reminder)

      expect(reminder.reload.status).to eq("skipped")
    end

    it "does not text a rating link to a client who already rated at the desk" do
      appt = book(world)
      Crm::RecordRating.call(appointment: appt, score: 9, channel: "kiosk")
      complete(appt)

      expect(Notification.where(appointment: appt, template_key: "rating_request")).to be_empty
    end
  end

  describe "deposits" do
    def take_deposit(appt, cents = 2_000)
      Sales::RecordDeposit.call(appointment: appt, amount_cents: cents, method: "card", actor: manager)
    end

    it "is held until checkout, covers part of the bill, then becomes a payment" do
      appt = book(world)
      deposit = take_deposit(appt)
      complete(appt)
      order = Sales::OpenOrder.call(appointment: appt, actor: manager)
      expect(order.outstanding_cents).to eq(6_000)

      today = world[:location].today
      held = Reporting::DailyRevenue.call(location_ids: [ world[:location].id ], from: today, to: today)
      expect(held[:deposits_held_cents]).to eq(2_000)
      expect(held[:service_revenue_cents]).to eq(0)

      Sales::RecordPayment.call(order:, method: "cash", amount_cents: 6_000, actor: manager)
      Sales::SettleOrder.call(order:, actor: manager)

      expect(deposit.reload.status).to eq("applied")
      expect(order.reload.payments.captured.pluck(:method, :amount_cents)).to contain_exactly([ "card", 2_000 ], [ "cash", 6_000 ])
      after = Reporting::DailyRevenue.call(location_ids: [ world[:location].id ], from: today, to: today)
      expect(after).to include(deposits_held_cents: 0, service_revenue_cents: 8_000, collected_cents: 8_000)
    end

    it "is refunded in full on a cancellation in time" do
      appt = book(world)
      deposit = take_deposit(appt)
      Scheduling::TransitionStatus.call(appointment: appt, to: "cancelled", actor: manager, now: appt.starts_at - 2.days)

      expect(deposit.reload).to have_attributes(status: "refunded", refunded_cents: 2_000, fee_cents: 0)
    end

    it "pays the late-cancellation fee first and refunds the rest" do
      appt = book(world)
      deposit = take_deposit(appt)
      Scheduling::TransitionStatus.call(appointment: appt, to: "cancelled", actor: manager, now: appt.starts_at - 1.hour)

      fee_order = Order.find_by!(appointment_id: appt.id, kind: "fee")
      expect(deposit.reload).to have_attributes(status: "forfeited", fee_cents: 1_600, refunded_cents: 400)
      expect(fee_order.reload.status).to eq("paid")
    end

    it "travels with a reschedule and refuses a service change that would price below it" do
      appt = book(world)
      deposit = take_deposit(appt, 8_000)
      moved = Scheduling::RescheduleAppointment.call(appointment: appt, start_at: world[:at] + 3.hours, actor: owner)
      expect(deposit.reload.appointment_id).to eq(moved.id)

      cheaper = create(:service_variant, service: world[:service], duration_minutes: 30, base_price_cents: 4_000)
      expect {
        Scheduling::RescheduleAppointment.call(appointment: moved, start_at: moved.starts_at, actor: owner,
                                               room_id: moved.room_id, variant_ids: [ cheaper.id ])
      }.to raise_error(Scheduling::BookAppointment::Invalid, "price_below_deposit")
      expect(moved.reload.status).to eq("scheduled")
    end

    it "refuses a second deposit or one above the price" do
      appt = book(world)
      expect { take_deposit(appt, 8_001) }.to raise_error(Sales::RecordDeposit::Invalid, "deposit_exceeds_price")
      take_deposit(appt)
      expect { take_deposit(appt) }.to raise_error(Sales::RecordDeposit::Invalid, "deposit_already_recorded")
    end
  end
end
