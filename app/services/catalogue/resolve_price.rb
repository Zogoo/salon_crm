module Catalogue
  # BR-11: resolves the price for a variant at a location on a date.
  # Order: effective location price → variant base price (doc 02 §3.3).
  class ResolvePrice < ApplicationService
    def initialize(variant:, location:, on: Date.current)
      @variant = variant
      @location = location
      @on = on
    end

    def call
      @variant.location_prices
              .where(location_id: @location.id)
              .effective_on(@on)
              .order(effective_from: :desc)
              .first&.price_cents || @variant.base_price_cents
    end
  end
end
