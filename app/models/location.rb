require "json"

class Location < ApplicationRecord
  ROOM_ORDER = %w[single couple three_table head_spa].freeze

  # SQLite has no array type; the Postgres design used integer[].
  serialize :reminder_offsets_minutes, coder: JSON, type: Array

  has_many :rooms, dependent: :destroy
  has_many :staff_profiles, dependent: :restrict_with_error
  has_many :shifts, dependent: :destroy
  has_many :appointments, dependent: :restrict_with_error
  has_many :location_prices, dependent: :destroy
  has_many :orders, dependent: :restrict_with_error
  has_many :sold_gift_cards, class_name: "GiftCard", foreign_key: :sold_at_location_id,
                             dependent: :restrict_with_error, inverse_of: :sold_at_location
  has_many :memberships, dependent: :restrict_with_error

  validates :name, :code, presence: true
  validates :code, uniqueness: true
  validates :buffer_minutes, :slot_granularity_minutes,
            numericality: { greater_than: 0 }

  scope :active, -> { where(status: "active") }

  def tz = ActiveSupport::TimeZone[timezone]

  # Local wall-clock opening/closing instants for a given date (doc 03 §5).
  def open_window(date)
    tz.local(date.year, date.month, date.day, opens_at.hour, opens_at.min)..
      tz.local(date.year, date.month, date.day, closes_at.hour, closes_at.min)
  end
end
