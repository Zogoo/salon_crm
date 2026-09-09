module Catalogue
  # Invariant 5: a price is per location and effective-dated. BR-11 snapshots
  # the price onto the appointment at booking, so changing a price must never
  # reach back into an order already taken — hence a new row, never an update.
  class SetPrice < ApplicationService
    Invalid = Class.new(StandardError)

    def initialize(variant:, location:, price_cents:, effective_from:, actor: nil)
      @variant = variant
      @location = location
      @price_cents = price_cents.to_i
      @effective_from = effective_from.to_date
      @actor = actor
    end

    def call
      raise Invalid, "negative_price" if @price_cents.negative?

      ImmediateTransaction.call do
        scope = LocationPrice.where(location: @location, service_variant: @variant)
        EffectiveDating.close_open_periods!(scope, @effective_from)
        price = scope.create!(price_cents: @price_cents, effective_from: @effective_from)
        AuditLog.record!(auditable: @variant, action: "price.set", actor: @actor,
                         changes: { location_id: @location.id, price_cents: @price_cents,
                                    effective_from: @effective_from })
        price
      end
    rescue ActiveRecord::RecordInvalid => e
      raise Invalid, e.record.errors.full_messages.join(", ")
    end
  end
end
