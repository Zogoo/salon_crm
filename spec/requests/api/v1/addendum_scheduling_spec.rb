require "rails_helper"

# FRS Addendum: approving a named therapist from the appointment itself (§6),
# a couples booking with only one client (§7), and staff working hours (§8).
RSpec.describe "FRS addendum — scheduling", type: :request do
  let(:world) { build_world(rooms: { single: 2, couple: 1 }, therapists: 2) }
  let(:owner) { create(:user, role: "owner") }
  let(:manager) { create(:user, role: "manager", location: world[:location]) }
  let(:therapist) { world[:staff].first }

  def json = JSON.parse(response.body)

  describe "§6 approval from the appointment" do
    it "carries the pending request on the appointment, so the panel can approve it there" do
      appt = book(world, requested_staff_profile_id: therapist.id)

      get "/api/v1/appointments/#{appt.id}", headers: auth_headers(manager)
      request_json = json["approval_request"]
      expect(request_json).to include("status" => "pending",
                                      "requested_therapist" => { "id" => therapist.id, "display_name" => therapist.display_name })

      post "/api/v1/approval_requests/#{request_json['id']}/approve", headers: auth_headers(manager)
      get "/api/v1/appointments/#{appt.id}", headers: auth_headers(manager)
      expect(json["status"]).to eq("scheduled")
      expect(json).not_to have_key("approval_request")
    end
  end

  describe "§7 couples booking" do
    it "books with only the first client; the second is optional" do
      service = create(:service, name: "Couples #{SecureRandom.hex(2)}")
      couple = create(:service_variant, service:, duration_minutes: 60, therapist_count: 2,
                                        required_client_capacity: 2)
      world[:staff].each { |sp| StaffQualification.create!(staff_profile: sp, service:) }

      post "/api/v1/appointments",
           params: { appointment: { location_id: world[:location].id, client_id: world[:client].id,
                                    service_variant_ids: [ couple.id ], start_at: world[:at].iso8601 } },
           headers: auth_headers(manager), as: :json

      expect(response).to have_http_status(:created)
      appt = Appointment.find(json["id"])
      expect(appt.room.client_capacity).to eq(2)
      expect(appt.appointment_participants.pluck(:client_id)).to eq([ world[:client].id ])
    end
  end

  describe "§8 working hours" do
    let(:weekday) { world[:date].wday }

    def set_hours(user, days)
      put "/api/v1/staff/#{therapist.id}/working_hours", params: { working_hours: days },
                                                           headers: auth_headers(user), as: :json
    end

    def open_times(staff_id)
      Scheduling::AvailabilitySearch.call(
        location: world[:location], variants: [ world[:variant] ], date_from: world[:date],
        requested_staff_profile_id: staff_id
      ).first[:slots].map { |s| s.start_at.in_time_zone(world[:location].tz).strftime("%H:%M") }
    end

    it "lets the location's Manager set a week, and the times offered follow it" do
      expect(open_times(therapist.id)).to include("09:00", "18:00")

      set_hours(manager, [ { weekday:, starts_at: "12:00", ends_at: "16:00" },
                           { weekday: (weekday + 1) % 7, off: true } ])
      expect(response).to have_http_status(:ok)
      expect(json["working_hours"]).to contain_exactly(
        { "weekday" => weekday, "off" => false, "starts_at" => "12:00", "ends_at" => "16:00" },
        { "weekday" => (weekday + 1) % 7, "off" => true, "starts_at" => nil, "ends_at" => nil }
      )

      times = open_times(therapist.id)
      # 60 minutes plus the 15-minute buffer must fit inside 12:00–16:00.
      expect(times.first).to eq("12:00")
      expect(times.last).to eq("14:45")
      expect(times).not_to include("09:00", "15:00")
    end

    it "offers nothing on a day marked off, and a booking outside the hours is refused" do
      set_hours(owner, [ { weekday:, off: true } ])
      expect(open_times(therapist.id)).to be_empty

      expect {
        Scheduling::BookAppointment.call(location: world[:location], client: world[:client],
                                         variant_ids: [ world[:variant].id ], start_at: world[:at],
                                         staff_profile_ids: [ therapist.id ])
      }.to raise_error(Scheduling::BookAppointment::Conflict, "therapist_outside_working_hours")
    end

    it "never moves or cancels an appointment already booked" do
      appt = book(world, staff_profile_ids: [ therapist.id ])
      set_hours(manager, [ { weekday:, off: true } ])

      expect(response).to have_http_status(:ok)
      expect(appt.reload).to have_attributes(status: "scheduled", starts_at: world[:at])
      expect(appt.staff_profiles).to eq([ therapist ])
    end

    it "explains a bad day in plain words, and a therapist cannot change their own" do
      set_hours(manager, [ { weekday:, starts_at: "17:00", ends_at: "09:00" } ])
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "message")).to include(Date::DAYNAMES[weekday])

      set_hours(therapist.user, [ { weekday:, off: true } ])
      expect(response).to have_http_status(:forbidden)
      get "/api/v1/staff/#{therapist.id}/working_hours", headers: auth_headers(therapist.user)
      expect(response).to have_http_status(:ok)
    end

    it "shows each therapist's hours beside their shift for the day" do
      set_hours(manager, [ { weekday:, starts_at: "10:00", ends_at: "18:00" } ])
      get "/api/v1/shifts/day", params: { location_id: world[:location].id, date: world[:date] },
                                headers: auth_headers(manager)
      row = json["working"].find { |w| w["staff_profile_id"] == therapist.id }
      expect(row["working_hours"]).to eq("off" => false, "starts_at" => "10:00", "ends_at" => "18:00")
    end
  end
end
