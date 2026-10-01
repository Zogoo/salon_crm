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
  #
  # A redemption taken back when a settled visit is corrected is answered by a
  # "refund" row on the same card and order, so what counts is the net.
  def redeemed_cents = live_redemptions.sum { |_card, cents| cents }

  # [[gift_card, net cents]] still drawn against this order, per card.
  def live_redemptions
    rows = gift_card_transactions.where(kind: %w[redeem refund]).includes(:gift_card).to_a
    rows.group_by(&:gift_card).filter_map do |card, txns|
      net = txns.sum { |t| t.kind == "redeem" ? t.amount_cents.abs : -t.amount_cents.abs }
      [ card, net ] if net.positive?
    end
  end

  # A membership credit is a *discount*: it lowers what is owed rather than
  # covering it, so it is already inside total_cents and must not be counted
  # again here. The service revenue on the line items is untouched — the
  # session was delivered, funded by the membership liability.
  def credited_cents
    order_discounts.where(kind: "membership_upgrade_credit").sum(:amount_cents)
  end

  def paid_cents = payments.where(status: "captured").sum(:amount_cents)
  def covered_cents = paid_cents + redeemed_cents + deposit_cents
  def outstanding_cents = total_cents - covered_cents
  def refunded_cents = refunds.sum(:amount_cents)

  # A deposit still held against this order's appointment. It covers part of
  # the bill already, but stays the client's money until settlement turns it
  # into a payment (Sales::SettleOrder).
  def held_deposit
    return nil unless kind == "service" && appointment_id

    Deposit.held.find_by(appointment_id:)
  end

  def deposit_cents = held_deposit&.amount_cents.to_i

  # Once money has been taken against an order, the lines it was taken against
  # must stop moving: changing them would silently re-price a bill someone has
  # already paid part of (BR-22, BR-23).
  def money_taken?
    status != "open" || payments.captured.exists? ||
      redeemed_cents.positive? ||
      order_discounts.where(kind: "membership_upgrade_credit").exists?
  end

  def recalculate!
    # Callers create and destroy these through the class, not the association,
    # so a cached (and possibly stale-empty) target must not be trusted.
    %i[order_line_items order_discounts tip_allocations payments
       gift_card_transactions].each { |a| association(a).reset }

    self.subtotal_cents = order_line_items.sum(:line_total_cents)
    self.discount_cents = order_discounts.sum(:amount_cents)
    self.tip_cents = tip_allocations.sum(:amount_cents)
    # Addendum §5: the transaction fee is part of what the client pays, beside
    # the services and the tip, never inside either.
    self.total_cents = subtotal_cents - discount_cents + tax_cents + tip_cents + transaction_fee_cents
    save!
    self
  end
end
