module Api
  module V1
    class ShiftsController < ApplicationController
      before_action :require_booking!, only: %i[create destroy]

      def index
        location = scoped_location!(params.require(:location_id))
        date = params[:date].present? ? Date.parse(params[:date]) : Date.current
        scope = Shift.published.where(location_id: location.id, work_date: date)
                     .includes(:staff_profile)
        scope = scope.where(staff_profile_id: current_user.staff_profile&.id) if current_user.staff?

        working = scope.order(:starts_at)
        # FRS §3/§15: the Owner needs to see who is *not* working, too.
        off = if current_user.staff?
                StaffProfile.none
              else
                StaffProfile.active.where(location_id: location.id)
                            .where.not(id: working.map(&:staff_profile_id))
              end

        render json: {
          date:,
          working: working.map { |s| shift_json(s) },
          not_working: off.order(:display_name).map { |p|
            { staff_profile_id: p.id, display_name: p.display_name }
          }
        }
      end

      def create
        location = scoped_location!(shift_params.require(:location_id))
        profile = StaffProfile.active.find(shift_params.require(:staff_profile_id))
        date = Date.parse(shift_params.require(:work_date))
        tz = location.tz

        shift = Shift.new(
          staff_profile: profile, location:, work_date: date,
          starts_at: tz.parse("#{date} #{shift_params.require(:starts_at)}"),
          ends_at: tz.parse("#{date} #{shift_params.require(:ends_at)}"),
          notes: shift_params[:notes]
        )
        if shift.save
          render json: shift_json(shift), status: :created
        else
          render json: { error: shift.errors.full_messages }, status: :conflict
        end
      end

      # BR-07: removing availability is blocked when appointments sit inside it.
      def destroy
        shift = Shift.find(params[:id])
        raise ActiveRecord::RecordNotFound unless current_user.can_access_location?(shift.location_id)

        clashes = AppointmentStaff.active
                                  .overlapping(shift.starts_at, shift.ends_at)
                                  .where(staff_profile_id: shift.staff_profile_id)
        if clashes.exists?
          return render json: {
            error: "shift_has_appointments",
            details: { appointment_ids: clashes.pluck(:appointment_id) }
          }, status: :unprocessable_content
        end

        shift.destroy!
        head :no_content
      end

      private

      def shift_params
        params.require(:shift).permit(:location_id, :staff_profile_id, :work_date,
                                      :starts_at, :ends_at, :notes)
      end

      def shift_json(shift)
        {
          id: shift.id, work_date: shift.work_date,
          staff_profile_id: shift.staff_profile_id,
          display_name: shift.staff_profile.display_name,
          starts_at: shift.starts_at.iso8601, ends_at: shift.ends_at.iso8601,
          notes: shift.notes
        }
      end
    end
  end
end
