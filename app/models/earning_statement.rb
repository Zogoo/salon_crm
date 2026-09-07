class EarningStatement < ApplicationRecord
  belongs_to :earning_period
  belongs_to :staff_profile
  belongs_to :approved_by_user, class_name: "User", optional: true
  has_many :earning_adjustments, dependent: :destroy
end
