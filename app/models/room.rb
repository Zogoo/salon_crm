class Room < ApplicationRecord
  TYPES = %w[single couple three_table head_spa].freeze

  belongs_to :location
  has_many :appointments, dependent: :restrict_with_error

  validates :name, presence: true
  validates :room_type, inclusion: { in: TYPES }
  validates :client_capacity, numericality: { greater_than: 0 }

  scope :active, -> { where(status: "active") }

  # BR-09: capacity must be sufficient, and an exclusive room (head spa) accepts
  # only services that ask for its type. Capacity matching — not type equality —
  # is what lets Skokie's three-table room take a couple or a single.
  scope :suitable_for, ->(variant) {
    rel = active.where("client_capacity >= ?", variant.required_client_capacity)
    rel =
      if variant.requires_room_type.present?
        rel.where(room_type: variant.requires_room_type)
      else
        rel.where(exclusive: false)
      end
    rel
  }
end
