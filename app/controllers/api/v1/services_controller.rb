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

      # The catalogue itself, unpriced — what the menu editor works against.
      def show
        service = Service.includes(:service_category, :service_variants).find(params[:id])
        render json: catalogue_json(service)
      end

      def variants
        service = Service.find(params[:id])
        render json: { service_id: service.id,
                       variants: service.service_variants.order(:duration_minutes).map { |v| variant_json(v) } }
      end

      def create
        require_menu_editor!
        service = Service.create!(service_params)
        render json: catalogue_json(service), status: :created
      rescue ActiveRecord::RecordInvalid => e
        render_invalid(e.record.errors.full_messages.join(", "))
      end

      def update
        require_menu_editor!
        service = Service.find(params[:id])
        service.update!(service_params)
        render json: catalogue_json(service.reload)
      rescue ActiveRecord::RecordInvalid => e
        render_invalid(e.record.errors.full_messages.join(", "))
      end

      # FRS §19.1: deactivate rather than delete. A service that has ever been
      # booked is referenced by appointment history and priced rows; removing it
      # would rewrite what a client was actually sold.
      def destroy
        require_menu_editor!
        service = Service.find(params[:id])
        if service.service_variants.joins(:appointment_items).exists?
          return render_invalid("Service has appointment history; deactivate it instead",
                                code: "service_in_use")
        end

        service.destroy!
        head :no_content
      end

      def activate   = set_active(true)
      def deactivate = set_active(false)

      private

      def set_active(flag)
        require_menu_editor!
        service = Service.find(params[:id])
        service.update!(active: flag)
        render json: catalogue_json(service)
      end

      def service_params
        params.require(:service).permit(:name, :kind, :service_category_id, :active, :description)
      end

      def catalogue_json(service)
        { id: service.id, name: service.name, kind: service.kind, active: service.active,
          service_category_id: service.service_category_id,
          variants: service.service_variants.order(:duration_minutes).map { |v| variant_json(v) } }
      end

      def variant_json(variant)
        { id: variant.id, duration_minutes: variant.duration_minutes,
          therapist_count: variant.therapist_count,
          required_client_capacity: variant.required_client_capacity,
          requires_room_type: variant.requires_room_type, active: variant.active }
      end

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
