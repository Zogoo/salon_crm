class ShiftBreak < ApplicationRecord
  belongs_to :shift
  validates :starts_at, :ends_at, presence: true
end
