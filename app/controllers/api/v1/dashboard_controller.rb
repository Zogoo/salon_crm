module Api
  module V1
    class DashboardController < ApplicationController
      # FRS §15 — today at the selected location. Money fields are Owner-only;
      # they are omitted at the serialiser, not hidden in the UI (doc 05 §13).
      def show
        location = scoped_location!(params.require(:location_id))
        date = params[:date].present? ? Date.parse(params[:date]) : Date.current

        appts = Appointment.on_date(location, date)
        working = Shift.published.where(location_id: location.id, work_date: date)
        busy_rooms = appts.active.where("starts_at <= ? AND ends_at > ?", Time.current, Time.current)
                          .distinct.count(:room_id)

        json = {
          date:,
          location: { id: location.id, name: location.name },
          appointments_today: appts.active.count,
          completed_today: appts.where(status: "completed").count,
          cancelled_today: appts.where(status: %w[cancelled late_cancelled]).count,
          no_shows_today: appts.where(status: "no_show").count,
          staff_working: working.count,
          staff_not_working: StaffProfile.active.where(location_id: location.id).count - working.count,
          rooms_total: location.rooms.active.count,
          rooms_free_now: location.rooms.active.count - busy_rooms,
          pending_approvals: ApprovalRequest.pending.joins(:appointment)
                                            .where(appointments: { location_id: location.id }).count
        }

        if current_user.can_view_money?
          json[:revenue_booked_cents] = appts.where(status: "completed").sum(:total_price_cents)
        end

        render json: json
      end
    end
  end
end
