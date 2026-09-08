# The nightly pass. Each step is safe to run twice.
class NightlyMaintenanceJob < ApplicationJob
  def perform(now: Time.current)
    {
      # BR-30: flags only. No ledger row, no balance change.
      gift_cards_expired: GiftCards::ExpireCards.call(now:),
      # BR-25: the cached balance must equal the ledger. Drift is a bug, and
      # this is how it surfaces as a report rather than as missing money.
      gift_card_drift: GiftCards::ReconcileBalances.call,
      membership_credit_drift: drifted_memberships,
      # Doc 03 §4.3: the denormalised interval on appointment_staff is what the
      # conflict check reads, so a row disagreeing with its parent is a silent
      # double-booking waiting to happen.
      appointment_staff_drift: drifted_appointment_staff
    }
  end

  private

  def drifted_memberships
    Membership.includes(:membership_credit_transactions).select(&:drifted?).map do |m|
      { id: m.id, cached: m.credits_balance, ledger: m.ledger_balance }
    end
  end

  def drifted_appointment_staff
    AppointmentStaff.joins(:appointment)
                    .where("appointment_staff.status != appointments.status
                            OR appointment_staff.starts_at != appointments.starts_at
                            OR appointment_staff.ends_at != appointments.ends_at")
                    .pluck(:appointment_id)
  end
end
