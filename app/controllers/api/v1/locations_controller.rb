module Api
  module V1
    class LocationsController < ApplicationController
      def index
        locations = Location.active.where(id: current_user.accessible_location_ids).order(:name)
        render json: { locations: locations.map { |l| location_json(l) } }
      end

      def show
        render json: location_json(scoped_location!(params[:id]), rooms: true)
      end

      private

      def location_json(location, rooms: false)
        json = {
          id: location.id, name: location.name, code: location.code,
          timezone: location.timezone,
          opens_at: location.opens_at.strftime("%H:%M"),
          closes_at: location.closes_at.strftime("%H:%M"),
          buffer_minutes: location.buffer_minutes,
          slot_granularity_minutes: location.slot_granularity_minutes,
          room_count: location.rooms.active.count
        }
        if rooms
          json[:rooms] = location.rooms.active.order(:position).map do |r|
            { id: r.id, name: r.name, room_type: r.room_type,
              client_capacity: r.client_capacity, exclusive: r.exclusive }
          end
        end
        json
      end
    end
  end
end
