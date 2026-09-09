module Api
  module V1
    # A variant is a duration of a service; its price is per location and
    # effective-dated, so it lives on its own sub-resource.
    class ServiceVariantsController < ApplicationController
      before_action :require_menu_editor!, except: :prices

      def create
        service = Service.find(params.require(:service_id))
        variant = service.service_variants.create!(variant_params)
        render json: variant_json(variant), status: :created
      rescue ActiveRecord::RecordInvalid => e
        render_invalid(e.record.errors.full_messages.join(", "))
      end

      def update
        variant = ServiceVariant.find(params[:id])
        variant.update!(variant_params)
        render json: variant_json(variant.reload)
      rescue ActiveRecord::RecordInvalid => e
        render_invalid(e.record.errors.full_messages.join(", "))
      end

      def prices
        require_owner!
        variant = ServiceVariant.find(params[:id])
        scope = variant.location_prices.includes(:location)
        scope = scope.where(location_id: scoped_location!(params[:location_id]).id) if params[:location_id].present?

        render json: { service_variant_id: variant.id,
                       prices: scope.order(:location_id, :effective_from).map { |p| price_json(p) } }
      end

      # BR-11: the booking snapshots the price, so a new price never reaches
      # back into an order already taken.
      def set_price
        require_owner!
        variant = ServiceVariant.find(params[:id])
        price = Catalogue::SetPrice.call(
          variant:, location: scoped_location!(params.require(:location_id)),
          price_cents: params.require(:price_cents),
          effective_from: params.require(:effective_from), actor: current_user
        )
        render json: price_json(price.reload), status: :created
      rescue Catalogue::SetPrice::Invalid => e
        render_invalid(e.message)
      end

      private

      def variant_params
        params.require(:service_variant).permit(:duration_minutes, :therapist_count,
                                                :required_client_capacity, :requires_room_type, :active)
      end

      def variant_json(variant)
        { id: variant.id, service_id: variant.service_id,
          duration_minutes: variant.duration_minutes, therapist_count: variant.therapist_count,
          required_client_capacity: variant.required_client_capacity,
          requires_room_type: variant.requires_room_type, active: variant.active }
      end

      def price_json(price)
        { id: price.id, location_id: price.location_id, location: price.location.name,
          price_cents: price.price_cents, effective_from: price.effective_from,
          effective_to: price.effective_to }
      end
    end
  end
end
