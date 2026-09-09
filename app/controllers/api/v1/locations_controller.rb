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

      def update
        require_owner!
        location = scoped_location!(params[:id])
        location.update!(location_params)
        render json: location_json(location.reload, rooms: true)
      rescue ActiveRecord::RecordInvalid => e
        render_invalid(e.record.errors.full_messages.join(", "))
      end

      # Doc 02 §3.2: several rows per weekday express split hours.
      def business_hours
        location = scoped_location!(params[:id])
        render json: { location_id: location.id, business_hours: hours_json(location) }
      end

      # Sent as the complete week, because a partial update cannot express
      # "this day now has one window instead of two".
      def set_business_hours
        require_owner!
        location = scoped_location!(params[:id])
        rows = params.require(:business_hours)

        ImmediateTransaction.call do
          location.business_hours.destroy_all
          rows.each do |row|
            location.business_hours.create!(
              day_of_week: row[:day_of_week], opens_at: row[:opens_at], closes_at: row[:closes_at]
            )
          end
        end
        render json: { location_id: location.id, business_hours: hours_json(location.reload) }
      rescue ActiveRecord::RecordInvalid => e
        render_invalid(e.record.errors.full_messages.join(", "))
      end

      # --- closures (C1) ---

      def closures
        location = scoped_location!(params[:id])
        scope = location.closures.order(:date)
        scope = scope.where("date >= ?", location.today) unless params[:include_past] == "true"
        render json: { location_id: location.id,
                       closures: scope.map { |c| { id: c.id, date: c.date, reason: c.reason } } }
      end

      def create_closure
        location = scoped_location!(params[:id])
        date = Date.parse(params.require(:date))

        # A closure removes a whole trading day, so it must not strand
        # appointments already booked into it (BR-07 in spirit).
        booked = appointments_on(location, date)
        if booked.any?
          return render json: { error: { code: "closure_has_appointments",
                                         details: { appointment_ids: booked.map(&:id) } } },
                        status: :unprocessable_content
        end

        closure = location.closures.create!(date:, reason: params[:reason], created_by_user: current_user)
        render json: { id: closure.id, date: closure.date, reason: closure.reason }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render_invalid(e.record.errors.full_messages.join(", "))
      end

      def destroy_closure
        location = scoped_location!(params[:id])
        location.closures.find(params[:closure_id]).destroy!
        head :no_content
      end

      private

      def appointments_on(location, date)
        windows = location.business_windows(date)
        return [] if windows.empty?

        location.appointments.active
                .where(starts_at: windows.first.first..windows.last.last).to_a
      end

      def location_params
        params.require(:location).permit(:name, :code, :timezone, :opens_at, :closes_at,
                                         :buffer_minutes, :slot_granularity_minutes,
                                         :cancellation_window_hours, :no_show_fee_percent,
                                         :late_cancel_fee_percent, :status)
      end

      def hours_json(location)
        location.business_hours.order(:day_of_week, :opens_at).map do |h|
          { id: h.id, day_of_week: h.day_of_week,
            opens_at: h.opens_at.strftime("%H:%M"), closes_at: h.closes_at.strftime("%H:%M") }
        end
      end

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
