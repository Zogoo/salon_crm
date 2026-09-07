class ServiceVariant < ApplicationRecord
  # The pay ladder (FRS §4). A service/add_on duration must sit on a rung, or
  # the fallback branch of BR-33 would produce an unpayable earning line.
  LADDER = [ 30, 45, 60, 75, 90, 120 ].freeze

  belongs_to :service
  has_many :location_prices, dependent: :destroy
  has_many :appointment_items, dependent: :restrict_with_error

  delegate :kind, :name, :service_category, to: :service

  validates :duration_minutes, numericality: { greater_than_or_equal_to: 0 }
  validates :therapist_count, numericality: { in: 1..2 }
  validates :required_client_capacity, numericality: { in: 1..3 }
  validate  :duration_on_ladder

  scope :active, -> { where(active: true) }

  def enhancement? = kind == "enhancement"
  def payable? = %w[standard add_on].include?(kind)

  # Service.kind calls a bookable service "standard"; on an appointment line the
  # same thing is a "service" (doc 02 §3.5). Map once, here.
  def item_kind = kind == "standard" ? "service" : kind

  private

  def duration_on_ladder
    return if enhancement?    # enhancements add price, never time
    return if LADDER.include?(duration_minutes)

    errors.add(:duration_minutes, "must be one of #{LADDER.join(', ')} to be payable")
  end
end
