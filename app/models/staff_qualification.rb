class StaffQualification < ApplicationRecord
  belongs_to :staff_profile
  belongs_to :service
  validates :service_id, uniqueness: { scope: :staff_profile_id }
end
