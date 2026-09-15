module Api
  module V1
    class AppointmentsController < ApplicationController
      # BR-14: only Owner and Manager create appointments. Staff never.
      before_action :require_booking!, only: %i[create transition]

      CALENDAR_STATUSES = (Appointment::ACTIVE_STATUSES + %w[no_show]).freeze

      def index
        location = scoped_location!(params.require(:location_id))
        date = params[:date].present? ? Date.parse(params[:date]) : location.today
        scope = Appointment.on_date(location, date)
                           .includes(:room, :client, :appointment_items, staff_profiles: [])
        scope = visible_to_current_user(scope)
        render json: { date:, appointments: scope.order(:starts_at).map { |a| appointment_json(a) } }
      end

      def show
        render json: appointment_json(find_appointment, detail: true)
      end

      # The day board: rooms down the side, appointments placed in them.
      def calendar
        location = scoped_location!(params.require(:location_id))
        date = params[:date].present? ? Date.parse(params[:date]) : location.today
        # Cancelled and late-cancelled visits leave the board (feedback 1.1). A
        # no-show stays, drawn faded, so the desk can see who did not come — it
        # holds no room or therapist, so it never blocks a new booking.
        appts = visible_to_current_user(
          Appointment.where(status: CALENDAR_STATUSES).on_date(location, date)
                     .includes(:client, :room, staff_profiles: [])
        ).order(:starts_at)

        render json: {
          date:,
          opens_at: location.opens_at.strftime("%H:%M"),
          closes_at: location.closes_at.strftime("%H:%M"),
          rooms: location.rooms.active.order(:position).map { |r|
            { id: r.id, name: r.name, room_type: r.room_type, client_capacity: r.client_capacity }
          },
          appointments: appts.map { |a| appointment_json(a) }
        }
      end

      def create
        location = scoped_location!(create_params.require(:location_id))
        client = Client.kept.find(create_params.require(:client_id))

        appt = Scheduling::BookAppointment.call(
          location:, client:, actor: current_user,
          variant_ids: create_params.require(:service_variant_ids),
          start_at: Time.zone.parse(create_params.require(:start_at)),
          staff_profile_ids: create_params[:staff_profile_ids],
          room_id: create_params[:room_id],
          requested_staff_profile_id: create_params[:requested_staff_profile_id],
          participant_client_ids: create_params[:participant_client_ids] || [],
          booking_channel: create_params[:booking_channel] || "manager",
          client_note: create_params[:client_note],
          appointment_note: create_params[:appointment_note]
        )
        render json: appointment_json(appt, detail: true), status: :created
      rescue Scheduling::BookAppointment::Conflict => e
        render json: { error: { code: e.message, message: conflict_message(e.message),
                                details: suggestions(e.message) } }, status: :conflict
      rescue Scheduling::BookAppointment::Invalid, ArgumentError => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      # Doc 03 §4.6 — a new booking plus a release, never a mutation.
      def reschedule
        appt = find_appointment
        fresh = Scheduling::RescheduleAppointment.call(
          appointment: appt, start_at: Time.zone.parse(params.require(:start_at)),
          actor: current_user,
          staff_profile_ids: params[:staff_profile_ids],
          room_id: params[:room_id]
        )
        render json: appointment_json(fresh, detail: true), status: :created
      rescue Scheduling::BookAppointment::Conflict => e
        render json: { error: { code: e.message, message: conflict_message(e.message) } },
               status: :conflict
      rescue Scheduling::BookAppointment::Invalid => e
        render json: { error: { code: e.message } }, status: :unprocessable_content
      end

      def transition
        appt = find_appointment
        Scheduling::TransitionStatus.call(
          appointment: appt, to: params.require(:to),
          actor: current_user, reason: params[:reason]
        )
        render json: appointment_json(appt.reload, detail: true)
      rescue Scheduling::TransitionStatus::Invalid => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      def assign_staff
        require_booking!
        appt = find_appointment
        Scheduling::AssignAppointmentStaff.call(
          appointment: appt, staff_profile_ids: params.require(:staff_profile_ids), actor: current_user
        )
        render json: appointment_json(appt.reload, detail: true)
      rescue Scheduling::AssignAppointmentStaff::Invalid => e
        render_invalid(e.message)
      rescue Scheduling::AssignAppointmentStaff::Conflict => e
        render json: { error: { code: e.message } }, status: :conflict
      end

      def repeat
        require_booking!
        appt = find_appointment
        repeats = Scheduling::RepeatAppointment.call(
          appointment: appt, interval_weeks: params.require(:interval_weeks),
          count: params.require(:count), actor: current_user
        )
        render json: { appointments: repeats.map { |repeat| appointment_json(repeat, detail: true) } },
               status: :created
      rescue Scheduling::RepeatAppointment::Unavailable => e
        render json: { error: { code: e.message, message: repeat_message(e.dates),
                                details: { dates: e.dates } } }, status: :conflict
      rescue Scheduling::RepeatAppointment::Invalid => e
        render_invalid(e.message)
      rescue Scheduling::BookAppointment::Conflict => e
        render json: { error: { code: e.message, message: conflict_message(e.message) } },
               status: :conflict
      rescue Scheduling::BookAppointment::Invalid => e
        render_invalid(e.message)
      end

      def replace_service
        require_booking!
        appt = find_appointment
        fresh = Scheduling::RescheduleAppointment.call(
          appointment: appt, start_at: appt.starts_at, actor: current_user,
          staff_profile_ids: appt.staff_assignment_confirmed? ? appt.staff_profiles.map(&:id) : nil,
          room_id: appt.room_id,
          variant_ids: params.require(:service_variant_ids)
        )
        render json: appointment_json(fresh, detail: true), status: :created
      rescue Scheduling::BookAppointment::Conflict => e
        render json: { error: { code: e.message, message: conflict_message(e.message) } },
               status: :conflict
      rescue Scheduling::BookAppointment::Invalid, ArgumentError => e
        render_invalid(e.message)
      end

      # Doc 05: notes and internal fields only. Times move through reschedule,
      # which releases the old slot properly; status moves through transition.
      def update
        require_booking!
        appt = find_appointment
        appt.update!(appointment_update_params)
        render json: appointment_json(appt.reload, detail: true)
      rescue ActiveRecord::RecordInvalid => e
        render_invalid(e.record.errors.full_messages.join(", "))
      end

      # BR-18/BR-19: the 4-hour window decides cancelled vs late_cancelled and
      # the fee, so cancelling is a transition rather than a separate path.
      def cancel
        require_booking!
        appt = find_appointment
        Scheduling::TransitionStatus.call(appointment: appt, to: "cancelled",
                                          actor: current_user, reason: params[:reason])
        render json: appointment_json(appt.reload, detail: true)
      rescue Scheduling::TransitionStatus::Invalid => e
        render_invalid(e.message)
      end

      # Feedback 3.3: one Checkout button. Moves the visit to completed in one
      # transaction and opens its order.
      def complete_for_checkout
        require_booking!
        appt = find_appointment
        order = Scheduling::CompleteForCheckout.call(appointment: appt, actor: current_user)
        render json: { appointment: appointment_json(appt.reload, detail: true), order_id: order.id }
      rescue Scheduling::TransitionStatus::Invalid => e
        render_invalid(e.message, code: e.message)
      end

      # Feedback 3.2: a deposit taken before the visit, held until checkout.
      def deposit
        require_booking!
        appt = find_appointment
        Sales::RecordDeposit.call(
          appointment: appt, amount_cents: params.require(:amount_cents),
          method: params.require(:method), actor: current_user,
          reference: params[:reference], note: params[:note]
        )
        render json: appointment_json(appt.reload, detail: true), status: :created
      rescue Sales::RecordDeposit::Invalid => e
        render_invalid(e.message, code: e.message)
      end

      # Hands a held deposit back while the visit still stands — the client
      # asked for it back, or it was keyed against the wrong booking.
      def refund_deposit
        require_booking!
        appt = find_appointment
        deposit = Deposit.held.find_by(appointment_id: appt.id)
        return render_invalid("no_held_deposit", code: "no_held_deposit") unless deposit

        Sales::ReleaseDeposit.call(appointment: appt, actor: current_user,
                                   reason: params[:reason].presence || "refunded at the desk")
        render json: appointment_json(appt.reload, detail: true)
      end

      def add_items
        require_booking!
        appt = find_appointment
        Scheduling::AddAppointmentItem.call(
          appointment: appt, variant_ids: params[:service_variant_ids], actor: current_user
        )
        render json: appointment_json(appt.reload, detail: true), status: :created
      rescue Scheduling::AddAppointmentItem::Invalid => e
        render_invalid(e.message)
      rescue Scheduling::AddAppointmentItem::Conflict => e
        render json: { error: { code: e.message } }, status: :conflict
      end

      def remove_item
        require_booking!
        appt = find_appointment
        Scheduling::RemoveAppointmentItem.call(
          appointment: appt, item_id: params[:item_id], actor: current_user
        )
        render json: appointment_json(appt.reload, detail: true)
      rescue Scheduling::RemoveAppointmentItem::Invalid => e
        render_invalid(e.message)
      end

      private

      def appointment_update_params
        params.require(:appointment).permit(:appointment_note, :client_note)
      end

      def create_params
        params.require(:appointment).permit(
          :location_id, :client_id, :start_at, :room_id, :requested_staff_profile_id,
          :booking_channel, :client_note, :appointment_note,
          service_variant_ids: [], staff_profile_ids: [], participant_client_ids: []
        )
      end

      def find_appointment
        appt = Appointment.includes(:client, :room, :location, :appointment_items, :staff_profiles)
                          .find(params[:id])
        raise ActiveRecord::RecordNotFound unless current_user.can_access_location?(appt.location_id)
        raise ActiveRecord::RecordNotFound unless visible?(appt)
        appt
      end

      # Staff see only appointments they are on — including as the second
      # therapist on a couples booking, which is why this joins the join table.
      #
      # A therapist only provisionally holding a no-preference booking does not
      # see it: they may never be the one who does it.
      def visible_to_current_user(scope)
        return scope unless current_user.staff?
        scope.joins(:appointment_staff)
             .where(appointment_staff: { staff_profile_id: current_user.staff_profile&.id })
             .where(staff_assignment_confirmed: true)
      end

      def visible?(appt)
        return true unless current_user.staff?
        appt.staff_assignment_confirmed? &&
          appt.appointment_staff.exists?(staff_profile_id: current_user.staff_profile&.id)
      end

      def repeat_message(dates)
        list = dates.map { |d| "#{d[:starts_at].to_s[0, 10]} (#{conflict_message(d[:code])})" }
        "No repeats were booked. These dates are unavailable: #{list.join('; ')}."
      end

      def conflict_message(code)
        {
          "slot_taken" => "That time was just booked by someone else.",
          "insufficient_therapists" => "This service needs two therapists and only one is free.",
          "no_suitable_room" => "No room of the required type or capacity is free.",
          "therapist_not_on_shift" => "That therapist is not on shift for the whole appointment.",
          "therapist_on_break" => "That therapist is on a break at that time.",
          "requested_therapist_unavailable" => "That therapist is not free at that time.",
          "outside_business_hours" => "That time is outside opening hours.",
          "location_closed" => "The location is closed that day."
        }.fetch(code, code)
      end

      # BR-16: if a named therapist was unavailable, offer that therapist's own
      # next times rather than a different person.
      def suggestions(code)
        return {} unless params.dig(:appointment, :requested_staff_profile_id).present?
        return {} unless %w[slot_taken therapist_not_on_shift therapist_on_break].include?(code)

        location = Location.find(create_params[:location_id])
        variants = ServiceVariant.where(id: create_params[:service_variant_ids]).includes(:service)
        slots = Scheduling::NextAvailableForTherapist.call(
          location:, variants:,
          staff_profile_id: create_params[:requested_staff_profile_id],
          after: Time.zone.parse(create_params[:start_at])
        )
        { suggested_slots: slots.map { |s| s.start_at.iso8601 } }
      rescue StandardError
        {}
      end

      def appointment_json(appt, detail: false)
        loc = appt.location
        json = {
          id: appt.id, reference: appt.reference, status: appt.status,
          starts_at: local_iso(appt.starts_at, loc),
          service_ends_at: local_iso(appt.service_ends_at, loc),
          ends_at: local_iso(appt.ends_at, loc),
          duration_minutes: appt.duration_minutes,
          room: { id: appt.room_id, name: appt.room.name },
          client: { id: appt.client_id, full_name: appt.client.full_name, phone: appt.client.phone },
          therapists: visible_therapists(appt),
          assignment_pending: !appt.staff_assignment_confirmed?,
          therapists_required: appt.appointment_items.includes(:service_variant)
                                     .map { |item| item.service_variant.therapist_count }.max || 1,
          total_price_cents: appt.total_price_cents,
          client_note: appt.client_note
        }
        if detail
          json[:location] = { id: appt.location_id, name: appt.location.name }
          json[:appointment_note] = appt.appointment_note
          json[:fee_charged_cents] = appt.fee_charged_cents
          json[:deposit] = appt.deposit&.then { |d|
            { id: d.id, amount_cents: d.amount_cents, method: d.method, status: d.status,
              reference: d.reference, fee_cents: d.fee_cents, refunded_cents: d.refunded_cents,
              received_at: local_iso(d.received_at, loc) }
          }
          json[:items] = appt.appointment_items.order(:position).map { |i|
            { id: i.id, service_variant_id: i.service_variant_id,
              name: i.service_variant.name, kind: i.kind,
              duration_minutes: i.duration_minutes, price_cents: i.price_cents }
          }
          json[:preference] = appt.client.client_preference&.then { |p|
            { attention_areas: p.attention_areas, avoid_areas: p.avoid_areas,
              pressure: p.pressure, other_requests: p.other_requests }
          }
        end
        json
      end

      def visible_therapists(appt)
        return [] unless appt.staff_assignment_confirmed? || current_user.staff?

        appt.staff_profiles.map { |sp| { id: sp.id, display_name: sp.display_name } }
      end
    end
  end
end
