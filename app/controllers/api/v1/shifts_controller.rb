module Api
  module V1
    class ShiftsController < ApplicationController
      before_action :require_booking!, only: %i[create destroy]

      # The roster over a range — what a Manager edits (doc 05 §"Shifts").
      def index
        scope = Shift.includes(:staff_profile, :location)
                     .where(location_id: scoped_location_ids)
                     .where(work_date: range)
        scope = scope.where(staff_profile_id: params[:staff_id]) if params[:staff_id].present?
        scope = scope.where(status: params[:status]) if params[:status].present?
        # Staff see their own roster and nobody else's.
        scope = scope.where(staff_profile_id: current_user.staff_profile&.id) if current_user.staff?

        render json: { shifts: scope.order(:work_date, :starts_at).map { |sh| shift_json(sh) } }
      end

      # FRS §3/§15: one day, and crucially who is *not* working that day.
      def day
        location = scoped_location!(params.require(:location_id))
        date = params[:date].present? ? Date.parse(params[:date]) : location.today
        working = Shift.published.where(location_id: location.id, work_date: date)
                       .includes(:staff_profile).order(:starts_at)
        working = working.where(staff_profile_id: current_user.staff_profile&.id) if current_user.staff?

        off =
          if current_user.staff?
            StaffProfile.none
          else
            StaffProfile.active.where(location_id: location.id)
                        .where.not(id: working.map(&:staff_profile_id))
          end

        render json: {
          date:,
          working: working.map { |sh| shift_json(sh) },
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
      # BR-07: the whole span disappears, so anything inside it is orphaned.
      def destroy
        shift = find_shift!
        orphans = Scheduling::ShiftCoverage.inside(shift.staff_profile_id, shift.starts_at, shift.ends_at)
        return render_orphans("shift_has_appointments", orphans) if orphans.any?

        shift.destroy!
        head :no_content
      end

      # BR-07: a shortened shift must still cover everything already booked in it.
      def update
        shift = find_shift!
        proposed = proposed_span(shift)
        orphans = Scheduling::ShiftCoverage.orphaned_by_change(
          shift, starts_at: proposed[:starts_at], ends_at: proposed[:ends_at]
        )
        return render_orphans("would_orphan_appointments", orphans) if orphans.any?

        shift.update!(shift_params.to_h.symbolize_keys.slice(:notes).merge(proposed))
        render json: shift_json(shift.reload)
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: { code: "shift_conflict", message: e.record.errors.full_messages.join(", ") } },
               status: :conflict
      end

      # A roster is drafted, then published in one go — a half-published week is
      # a week where some therapists are bookable and some silently are not.
      def publish
        shifts = Shift.where(id: Array(params[:shift_ids]))
                      .where(location_id: current_user.accessible_location_ids)
        return render_invalid("No shifts given", code: "no_shifts") if shifts.empty?

        published = []
        conflicts = []
        ImmediateTransaction.call do
          shifts.each do |shift|
            # BR-04 lives on the model; a clash makes that one shift fail, and
            # the whole publish is rolled back rather than half-applied.
            if shift.update(status: "published")
              published << shift
            else
              conflicts << { shift_id: shift.id, errors: shift.errors.full_messages }
            end
          end
          raise ActiveRecord::Rollback if conflicts.any?
        end

        if conflicts.any?
          return render json: { error: { code: "shift_conflict", details: { conflicts: } } },
                        status: :conflict
        end
        render json: { published: published.map { |s| shift_json(s.reload) } }
      end

      def breaks
        shift = find_shift!
        render json: { shift_id: shift.id, breaks: shift.shift_breaks.order(:starts_at).map { |b| break_json(b, shift) } }
      end

      # The availability engine already subtracts breaks (doc 03 §2.3); there
      # was no way to record one.
      def create_break
        shift = Shift.find(params[:id])
        raise ActiveRecord::RecordNotFound unless current_user.can_access_location?(shift.location_id)

        tz = shift.location.tz
        brk = ShiftBreak.new(
          shift:,
          starts_at: tz.parse("#{shift.work_date} #{params.require(:starts_at)}"),
          ends_at: tz.parse("#{shift.work_date} #{params.require(:ends_at)}"),
          reason: params[:reason]
        )
        # BR-07: a break punches a hole in availability, so it must not land
        # on top of a booking.
        orphans = Scheduling::ShiftCoverage.inside(shift.staff_profile_id, brk.starts_at, brk.ends_at)
        return render_orphans("break_has_appointments", orphans) if orphans.any?

        brk.save!
        render json: break_json(brk, shift), status: :created
      end

      def destroy_break
        brk = ShiftBreak.joins(:shift).find(params[:break_id])
        raise ActiveRecord::RecordNotFound unless current_user.can_access_location?(brk.shift.location_id)
        brk.destroy!
        head :no_content
      end

      private

      def scoped_location_ids
        return [ scoped_location!(params[:location_id]).id ] if params[:location_id].present?
        current_user.accessible_location_ids
      end

      # Defaults to the salon's current week, not the server's.
      def range
        default = Location.find_by(id: scoped_location_ids.first)&.today || Date.current
        from = params[:from].present? ? Date.parse(params[:from]) : default.beginning_of_week
        to   = params[:to].present?   ? Date.parse(params[:to])   : from + 6.days
        from..to
      end

      def find_shift!
        shift = Shift.find(params[:id])
        raise ActiveRecord::RecordNotFound unless current_user.can_access_location?(shift.location_id)
        shift
      end

      def render_orphans(code, rows)
        render json: { error: { code:,
                                details: { appointment_ids: Scheduling::ShiftCoverage.appointment_ids(rows) } } },
               status: :unprocessable_content
      end

      # Times arrive as wall clock; the salon's day is not the server's.
      def proposed_span(shift)
        tz = shift.location.tz
        date = shift_params[:work_date].presence&.to_date || shift.work_date
        { work_date: date,
          starts_at: shift_params[:starts_at].present? ? tz.parse("#{date} #{shift_params[:starts_at]}") : shift.starts_at,
          ends_at: shift_params[:ends_at].present? ? tz.parse("#{date} #{shift_params[:ends_at]}") : shift.ends_at }
      end

      def break_json(brk, shift)
        { id: brk.id, starts_at: local_iso(brk.starts_at, shift.location),
          ends_at: local_iso(brk.ends_at, shift.location), reason: brk.reason }
      end

      def shift_params
        params.require(:shift).permit(:location_id, :staff_profile_id, :work_date,
                                      :starts_at, :ends_at, :notes)
      end

      def shift_json(shift)
        {
          id: shift.id, work_date: shift.work_date,
          staff_profile_id: shift.staff_profile_id,
          display_name: shift.staff_profile.display_name,
          location_id: shift.location_id,
          # Without this the roster cannot tell a draft from a published
          # shift, and offers to publish what is already live.
          status: shift.status,
          starts_at: local_iso(shift.starts_at, shift.location),
          ends_at: local_iso(shift.ends_at, shift.location),
          notes: shift.notes
        }
      end
    end
  end
end
