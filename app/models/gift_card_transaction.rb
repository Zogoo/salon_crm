class GiftCardTransaction < ApplicationRecord
  KINDS = %w[issue redeem refund adjust expire].freeze

  belongs_to :gift_card
  belongs_to :order, optional: true
  belongs_to :appointment, optional: true
  belongs_to :redeemed_by_client, class_name: "Client", optional: true
  belongs_to :performed_by_user, class_name: "User", optional: true
  # The REDEEMING location, which differs from the card's selling location
  # whenever a card crosses locations (BR-27).
  belongs_to :location, optional: true

  validates :kind, inclusion: { in: KINDS }
end
