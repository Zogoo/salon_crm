class Order < ApplicationRecord
  STATUSES = %w[open paid voided refunded partially_refunded].freeze
  KINDS    = %w[service gift_card membership fee].freeze

  belongs_to :client, optional: true
  belongs_to :location
  belongs_to :appointment, optional: true
  belongs_to :opened_by_user, class_name: "User", optional: true
  belongs_to :closed_by_user, class_name: "User", optional: true

  has_many :order_line_items, dependent: :destroy
  has_many :payments, dependent: :destroy
  has_many :refunds, dependent: :destroy
  has_many :order_discounts, dependent: :destroy
  has_many :tip_allocations, dependent: :destroy
  has_many :gift_card_transactions, dependent: :nullify

  validates :number, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :kind, inclusion: { in: KINDS }

  scope :settled, -> { where(status: %w[paid partially_refunded]) }
  scope :outstanding_fees, -> { where(kind: "fee", status: "open") }

  def self.generate_number
    "ORD-#{Time.current.year}-#{SecureRandom.random_number(1_000_000).to_s.rjust(6, '0')}"
  end

  # A gift card redemption is not a payment — it has its own ledger — but it
  # does settle an order (BR-22).
  def redeemed_cents
    gift_card_transactions.where(kind: "redeem").sum(:amount_cents).abs
  end

  # A membership credit is a *discount*: it lowers what is owed rather than
  # covering it, so it is already inside total_cents and must not be counted
  # again here. The service revenue on the line items is untouched — the
  # session was delivered, funded by the membership liability.
  def credited_cents
    order_discounts.where(kind: "membership_upgrade_credit").sum(:amount_cents)
  end

  def paid_cents = payments.where(status: "captured").sum(:amount_cents)
  def covered_cents = paid_cents + redeemed_cents
  def outstanding_cents = total_cents - covered_cents
  def refunded_cents = refunds.sum(:amount_cents)

  def recalculate!
    # Callers create and destroy these through the class, not the association,
    # so a cached (and possibly stale-empty) target must not be trusted.
    %i[order_line_items order_discounts tip_allocations payments
       gift_card_transactions].each { |a| association(a).reset }

    self.subtotal_cents = order_line_items.sum(:line_total_cents)
    self.discount_cents = order_discounts.sum(:amount_cents)
    self.tip_cents = tip_allocations.sum(:amount_cents)
    self.total_cents = subtotal_cents - discount_cents + tax_cents + tip_cents
    save!
    self
  end
end
