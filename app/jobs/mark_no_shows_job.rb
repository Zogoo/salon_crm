# Proposes no-shows for appointments well past their start.
#
# It never commits one. Marking a no-show records a 20% fee against the client,
# and doing that because nobody pressed "check in" is exactly the kind of
# automation that produces disputes — so this only flags them for a human.
class MarkNoShowsJob < ApplicationJob
  GRACE = 30.minutes

  def perform(now: Time.current)
    Appointment.where(status: "scheduled")
               .where(starts_at: ..(now - GRACE))
               .pluck(:id, :reference, :location_id)
               .map { |id, reference, location_id| { id:, reference:, location_id: } }
  end
end
