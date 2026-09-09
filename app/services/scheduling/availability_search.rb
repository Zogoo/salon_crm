module Scheduling
  # Doc 03 §2. Returns every start time at which the requested appointment can
  # be booked at a location, on the location's 15-minute grid.
  #
  # Everything after the initial load happens in memory over a small, bounded
  # dataset — a 7-day window at peak volume is ~2,000 rows (doc 03 §2.2).
  # Availability itself is never cached (ADR-03).
  class AvailabilitySearch < ApplicationService
    Slot = Struct.new(:start_at, :service_end_at, :end_at, :staff, :room_ids, keyword_init: true)

    def initialize(location:, variants:, date_from:, date_to: nil,
                   requested_staff_profile_id: nil, channel: "manager", now: Time.current)
      @location = location
      @shape = AppointmentShape.call(variants:)
      @date_from = date_from.to_date
      @date_to = (date_to || date_from).to_date
      @requested_staff_id = requested_staff_profile_id
      @channel = channel.to_s
      @now = now
    end

    def call
      @date_from.upto(@date_to).map { |date| { date:, slots: slots_for(date) } }
    end

    private

    def total_minutes = @shape.duration_minutes + @location.buffer_minutes

    # --- candidates -------------------------------------------------------

    # C2/C3/C4 — qualified, at this location, on a published shift.
    def shifts_for(date)
      rel = Shift.published
                 .where(location_id: @location.id, work_date: date)
                 .includes(:shift_breaks, staff_profile: :staff_qualifications)
      rel = rel.where(staff_profile_id: @requested_staff_id) if @requested_staff_id
      rel.select { |s| s.staff_profile.status == "active" && s.staff_profile.qualified_for?(@shape.service_ids) }
    end

    # C7/C11 — capacity sufficient, exclusive rooms respected.
    def rooms
      @rooms ||= Room.suitable_for(@shape.room_requirement).where(location_id: @location.id).to_a
    end

    # C5 — therapist conflicts are company-wide, so this query is NOT scoped to
    # the location. A therapist booked at Luma is unavailable at Belmont.
    def staff_busy(staff_ids, from, to)
      AppointmentStaff.active.overlapping(from, to)
                      .where(staff_profile_id: staff_ids)
                      .pluck(:staff_profile_id, :starts_at, :ends_at)
                      .group_by(&:first)
    end

    # --- the scan ---------------------------------------------------------

    def slots_for(date)
      shifts = shifts_for(date)
      return [] if shifts.empty? || rooms.empty?

      # C1 — closed, or no hours for this weekday. Split hours give several
      # windows, so the scan runs once per window.
      windows = @location.business_windows(date)
      return [] if windows.empty?

      day_from = windows.first.first
      day_to = windows.last.last
      staff_ids = shifts.map(&:staff_profile_id).uniq
      busy_staff = staff_busy(staff_ids, day_from, day_to)
      busy_rooms = room_busy(rooms.map(&:id), day_from, day_to)
      breaks = shifts.flat_map { |s| s.shift_breaks.map { |b| [ s.staff_profile_id, b.starts_at, b.ends_at ] } }
                     .group_by(&:first)

      windows.flat_map { |w| scan(w, shifts, busy_staff, busy_rooms, breaks) }
    end

    # Doc 03 §2.4: blocks participate exactly like appointments, so they are
    # merged into the room's busy list rather than checked separately.
    def room_busy(room_ids, from, to)
      appointments = Appointment.active.overlapping(from, to)
                                .where(room_id: room_ids)
                                .pluck(:room_id, :starts_at, :ends_at)
      blocks = RoomBlock.overlapping(from, to).where(room_id: room_ids)
                        .pluck(:room_id, :starts_at, :ends_at)
      (appointments + blocks).group_by(&:first)
    end

    def scan(window, shifts, busy_staff, busy_rooms, breaks)
      day_from = window.first
      day_to = window.last
      step = @location.slot_granularity_minutes.minutes
      slots = []
      t = day_from

      while t + total_minutes.minutes <= day_to
        finish = t + total_minutes.minutes
        if bookable_time?(t)
          free = shifts.select { |s| staff_free?(s, t, finish, busy_staff, breaks) }
                       .map(&:staff_profile).uniq
          # C12 — cardinality, not existence. A couples massage needs two.
          if free.size >= @shape.therapist_count
            open_rooms = rooms.reject { |r| clash?(busy_rooms[r.id], t, finish) }
            unless open_rooms.empty?
              slots << Slot.new(
                start_at: t,
                service_end_at: t + @shape.duration_minutes.minutes,
                end_at: finish,
                staff: free.map { |sp| { id: sp.id, display_name: sp.display_name } },
                room_ids: open_rooms.map(&:id)
              )
            end
          end
        end
        t += step
      end
      slots
    end

    def staff_free?(shift, from, to, busy_staff, breaks)
      return false unless shift.covers?(from, to)                       # C4
      return false if clash?(busy_staff[shift.staff_profile_id], from, to)  # C5
      return false if clash?(breaks[shift.staff_profile_id], from, to)      # C6
      true
    end

    def clash?(rows, from, to)
      return false if rows.blank?
      rows.any? { |(_, s, e)| s < to && e > from }
    end

    # C10 — cut-off and horizon constrain the client channel only. Owner and
    # Manager must be able to book someone standing at the desk (Release 2
    # note: no client channel exists yet, but the rule is implemented).
    def bookable_time?(t)
      return true unless @channel == "client"
      t >= @now + @location.booking_cutoff_minutes.minutes &&
        t <= @now + @location.booking_horizon_days.days
    end
  end
end
