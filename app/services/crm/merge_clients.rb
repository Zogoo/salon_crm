module Crm
  # BR-42 and doc 07's risk register, which rates duplicate clients "very high"
  # likelihood: phone bookings plus an "Add New Client" button on the booking
  # screen guarantee them.
  #
  # Merging repoints history and marks the loser merged — it never deletes,
  # because appointments, orders and gift cards hang off it.
  class MergeClients < ApplicationService
    Invalid = Class.new(StandardError)

    def initialize(source:, target:, actor:)
      @source = source
      @target = target
      @actor = actor
    end

    def call
      raise Invalid, "same_client" if @source.id == @target.id
      raise Invalid, "already_merged" if @source.status == "merged"

      ImmediateTransaction.call do
        move_history!
        fill_gaps!
        @source.update!(status: "merged", merged_into_client: @target, discarded_at: Time.current)
        recount!
        AuditLog.record!(auditable: @target, action: "client.merged", actor: @actor,
                         changes: { merged_client_id: @source.id, phone: @source.phone })
        @target.reload
      end
    end

    private

    def move_history!
      Appointment.where(client_id: @source.id).update_all(client_id: @target.id)
      AppointmentParticipant.where(client_id: @source.id).update_all(client_id: @target.id)
      Order.where(client_id: @source.id).update_all(client_id: @target.id)
      ClientNote.where(client_id: @source.id).update_all(client_id: @target.id)
      GiftCard.where(buyer_client_id: @source.id).update_all(buyer_client_id: @target.id)
      GiftCard.where(recipient_client_id: @source.id).update_all(recipient_client_id: @target.id)
      GiftCardTransaction.where(redeemed_by_client_id: @source.id)
                         .update_all(redeemed_by_client_id: @target.id)
      # A client may hold only one membership, so the survivor keeps theirs and
      # the loser's moves only if the survivor has none.
      Membership.where(client_id: @source.id).update_all(client_id: @target.id) unless @target.membership
    end

    # Keep detail the survivor is missing rather than discarding it.
    def fill_gaps!
      @target.email ||= @source.email
      @target.date_of_birth ||= @source.date_of_birth
      @target.preferred_location_id ||= @source.preferred_location_id
      @target.save! if @target.changed?

      return if @target.client_preference || @source.client_preference.nil?

      @source.client_preference.update!(client_id: @target.id)
    end

    # The counters are denormalised, so recompute rather than add — the two
    # records may already have double-counted a shared visit.
    def recount!
      appointments = Appointment.where(client_id: @target.id)
      @target.update!(
        no_show_count: appointments.where(status: "no_show").count,
        late_cancel_count: appointments.where(status: "late_cancelled").count,
        cancel_count: appointments.where(status: "cancelled").count
      )
    end
  end
end
