require "json"

class EarningLine < ApplicationRecord
  SOURCES = %w[session tip manual].freeze

  belongs_to :staff_profile
  belongs_to :location
  belongs_to :appointment, optional: true
  belongs_to :tip_allocation, optional: true
  belongs_to :created_by_user, class_name: "User", optional: true

  # Stored as text: the SQLite schema dumper cannot round-trip a json column.
  # Rails writes NULL for an empty array here (it treats [] as the type's
  # default), so the column is nullable and reads coerce back to [].
  serialize :covers_item_ids, coder: JSON, type: Array

  validates :source, inclusion: { in: SOURCES }
  validates :amount_cents, numericality: true

  scope :sessions, -> { where(source: %w[session manual]).where.not(duration_minutes: nil) }
  scope :tips,     -> { where(source: "tip") }
  scope :in_period, ->(from, to) { where(service_date: from..to) }
end
