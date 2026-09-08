module Api
  module V1
    class ServicesController < ApplicationController
      # Returns the menu with the price already resolved for the location and
      # date, so no client ever implements price resolution (doc 05 §5).
      def index
        location = scoped_location!(params.require(:location_id))
        on = params[:date].present? ? Date.parse(params[:date]) : location.today

        priced = ServiceVariant.active
                               .joins(:location_prices)
                               .where(location_prices: { location_id: location.id })
                               .merge(LocationPrice.effective_on(on))
                               .includes(service: :service_category)
                               .distinct

        grouped = priced.group_by(&:service)
        render json: {
          location_id: location.id,
          services: grouped.map { |service, variants| service_json(service, variants, location, on) }
                           .sort_by { |s| [ s[:category_position], s[:name] ] }
        }
      end

      private

      def service_json(service, variants, location, on)
        {
          id: service.id, name: service.name, kind: service.kind,
          category: service.service_category.code,
          category_position: service.service_category.position,
          variants: variants.sort_by(&:duration_minutes).map { |v|
            {
              id: v.id, duration_minutes: v.duration_minutes,
              price_cents: Catalogue::ResolvePrice.call(variant: v, location:, on:),
              therapist_count: v.therapist_count,
              required_client_capacity: v.required_client_capacity,
              requires_room_type: v.requires_room_type
            }
          }
        }
      end
    end
  end
end
