require "json"

class Location < ApplicationRecord
  ROOM_ORDER = %w[single couple three_table head_spa].freeze

  # SQLite has no array type; the Postgres design used integer[].
  serialize :reminder_offsets_minutes, coder: JSON, type: Array

  has_many :rooms, dependent: :destroy
  has_many :business_hours, class_name: "LocationBusinessHour", dependent: :destroy
  has_many :closures, class_name: "LocationClosure", dependent: :destroy
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
  validates :manager_discount_limit_percent, :no_show_fee_percent, :late_cancel_fee_percent,
            numericality: { only_integer: true, in: 0..100 }

  scope :active, -> { where(status: "active") }

  def tz = ActiveSupport::TimeZone[timezone]

  # The salon's current business date. `Date.current` follows Time.zone (UTC),
  # which after 19:00 Central is already tomorrow — so a controller defaulting
  # to "today" that way shows an empty board for the last hours of every day.
  def today = tz.today

  # C1: a closure is an exception to the usual week — the location keeps its
  # hours, it simply does not open that day.
  def closed_on?(date) = closures.exists?(date:)

  # Local wall-clock trading windows for a date (doc 03 §5). Several, because
  # doc 02 §3.2 allows split hours; empty when the location is shut.
  #
  # Falls back to the location's single opens_at/closes_at when no per-weekday
  # rows exist, so a location works before anyone edits its hours.
  def business_windows(date)
    return [] if closed_on?(date)

    rows = business_hours.for_day(date.wday)
    return [ window_between(date, opens_at, closes_at) ] if rows.empty?

    rows.map { |r| window_between(date, r.opens_at, r.closes_at) }
  end

  # The outer bounds of the trading day — what the day board draws.
  def open_window(date)
    windows = business_windows(date)
    return nil if windows.empty?

    windows.first.first..windows.last.last
  end

  # Minutes the location is actually open, which is the only honest
  # denominator for utilisation (BR-28).
  def open_minutes_on(date)
    business_windows(date).sum { |w| ((w.last - w.first) / 60).round }
  end

  private

  def window_between(date, from, to)
    tz.local(date.year, date.month, date.day, from.hour, from.min)..
      tz.local(date.year, date.month, date.day, to.hour, to.min)
  end
end
