# A whole day on which the location does not open (C1). Distinct from having no
# business hours for that weekday: a closure is an exception to the usual week.
class LocationClosure < ApplicationRecord
  belongs_to :location
  belongs_to :created_by_user, class_name: "User", optional: true

  validates :date, presence: true, uniqueness: { scope: :location_id }
end
