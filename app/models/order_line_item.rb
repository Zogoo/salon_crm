class OrderLineItem < ApplicationRecord
  # BR-48: what the reporting layer groups by. Never infer revenue from the
  # order total — a gift card sale and a fee both sit in the same order table.
  CATEGORIES = %w[service add_on enhancement gift_card_liability
                  membership_liability fee].freeze
  REVENUE    = %w[service add_on enhancement].freeze

  belongs_to :order
  belongs_to :purchasable, polymorphic: true, optional: true
  belongs_to :staff_profile, optional: true

  validates :description, presence: true
  validates :revenue_category, inclusion: { in: CATEGORIES }

  scope :revenue,   -> { where(revenue_category: REVENUE) }
  scope :liability, -> { where(revenue_category: %w[gift_card_liability membership_liability]) }
  scope :fees,      -> { where(revenue_category: "fee") }
end
