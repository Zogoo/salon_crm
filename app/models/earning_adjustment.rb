class EarningAdjustment < ApplicationRecord
  belongs_to :earning_statement
  belongs_to :created_by_user, class_name: "User", optional: true
  validates :reason, presence: true
end
