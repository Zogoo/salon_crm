class GiftCard < ApplicationRecord
  STATUSES = %w[active depleted expired void].freeze

  belongs_to :buyer_client, class_name: "Client", optional: true
  belongs_to :recipient_client, class_name: "Client", optional: true
  belongs_to :sold_by_user, class_name: "User", optional: true
  belongs_to :sold_at_location, class_name: "Location"
  has_many :gift_card_transactions, dependent: :destroy

  validates :code, presence: true, uniqueness: true
  validates :initial_value_cents, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :current_balance_cents, numericality: { greater_than_or_equal_to: 0 }

  normalizes :code, with: ->(c) { c.to_s.strip.upcase }

  scope :outstanding, -> { where("current_balance_cents > 0").where.not(status: "void") }

  # BR-30: expiry is a reporting flag. The balance stays spendable, so
  # redeemability asks the balance, never the status.
  def redeemable? = status != "void" && current_balance_cents.positive?
  def expired?    = status == "expired"

  def self.generate_code
    # Non-sequential and collision-resistant; this is printed on the card.
    loop do
      code = "GC-#{SecureRandom.alphanumeric(10).upcase}"
      break code unless exists?(code:)
    end
  end

  # BR-25: the cache must always equal the ledger. The nightly job asserts this.
  def ledger_balance_cents = gift_card_transactions.sum(:amount_cents)
  def drifted? = ledger_balance_cents != current_balance_cents
end
