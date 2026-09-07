# BR-44: append-only. A correction is a new note superseding the original.
#
# Not a clinical record (doc 04 §5) — no intake, no consent, no SOAP structure.
# Still body-related information about an identifiable person, so the body is
# encrypted and access is scoped to Owner, Manager, and the therapist on that
# appointment.
class CareNote < ApplicationRecord
  self.record_timestamps = false

  belongs_to :appointment
  belongs_to :staff_profile
  belongs_to :supersedes_note, class_name: "CareNote", optional: true

  encrypts :body

  validates :body, presence: true
  validate  :never_modified, on: :update

  before_validation(on: :create) { self.created_at ||= Time.current }

  private

  def never_modified
    errors.add(:base, "care notes are append-only (BR-44) — supersede it instead")
  end
end
