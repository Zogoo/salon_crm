module Scheduling
  # Feedback 3.3: one Checkout button instead of Check in → Start → Complete.
  #
  # The steps still happen — each writes its status event, and completion
  # generates earnings — but in one transaction, so a dropped connection can
  # never leave the visit stranded half-way through. Ends with the order open.
  class CompleteForCheckout < ApplicationService
    NEXT = { "scheduled" => "checked_in", "checked_in" => "in_progress",
             "in_progress" => "completed" }.freeze

    def initialize(appointment:, actor: nil)
      @appt = appointment
      @actor = actor
    end

    def call
      unless @appt.staff_assignment_confirmed?
        raise TransitionStatus::Invalid, "therapist_assignment_required"
      end

      ImmediateTransaction.call do
        while (target = NEXT[@appt.status])
          TransitionStatus.call(appointment: @appt, to: target, actor: @actor, reason: "checkout")
        end
        raise TransitionStatus::Invalid, "cannot_checkout_#{@appt.status}" unless @appt.status == "completed"

        Sales::OpenOrder.call(appointment: @appt, actor: @actor)
      end
    end
  end
end
