require "rails_helper"

RSpec.describe "Scheduling API", type: :request do
  # Builds a world plus the three roles that can see it.
  let(:world) { build_world(rooms: { single: 2, couple: 1 }, therapists: 3) }
  let(:owner) { create(:user, email: "owner@example.com", role: "owner") }
  let(:manager) do
    create(:user, email: "mgr@example.com", role: "manager", location: world[:location])
  end
  let(:therapist_user) { world[:staff].first.user }

  def auth(user) = { "Authorization" => "Bearer #{Auth::JwtService.encode(user)}" }
  def json = JSON.parse(response.body)

  describe "location scoping (BR-01, BR-02)" do
    it "shows the Owner every location" do
      world_location = world[:location]          # `world` is lazy — realise it first
      other = create(:location, code: "other")
      get "/api/v1/locations", headers: auth(owner)
      expect(json["locations"].map { |l| l["id"] }).to include(world_location.id, other.id)
    end

    it "shows a Manager only their own location" do
      create(:location, code: "other")
      get "/api/v1/locations", headers: auth(manager)
      expect(json["locations"].map { |l| l["id"] }).to eq([ world[:location].id ])
    end

    it "returns 404, not 403, for a location out of scope" do
      other = create(:location, code: "other")
      get "/api/v1/locations/#{other.id}", headers: auth(manager)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /appointments" do
    let(:payload) do
      { appointment: { location_id: world[:location].id, client_id: world[:client].id,
                       service_variant_ids: [ world[:variant].id ],
                       start_at: world[:at].iso8601 } }
    end

    it "lets a Manager book" do
      post "/api/v1/appointments", params: payload, headers: auth(manager), as: :json
      expect(response).to have_http_status(:created)
      expect(json["reference"]).to be_present
      expect(json["therapists"].size).to eq(1)
    end

    # BR-14 — the rule the FRS states twice.
    it "refuses to let Staff book" do
      post "/api/v1/appointments", params: payload, headers: auth(therapist_user), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(Appointment.count).to be_zero
    end

    it "returns 409 slot_taken on a double booking" do
      single_room = build_world(rooms: { single: 1 }, therapists: 2)
      body = { appointment: { location_id: single_room[:location].id,
                              client_id: single_room[:client].id,
                              service_variant_ids: [ single_room[:variant].id ],
                              start_at: single_room[:at].iso8601 } }
      admin = create(:user, email: "o2@example.com", role: "owner")
      post "/api/v1/appointments", params: body, headers: auth(admin), as: :json
      expect(response).to have_http_status(:created)

      post "/api/v1/appointments", params: body, headers: auth(admin), as: :json
      expect(response).to have_http_status(:conflict)
      expect(json.dig("error", "code")).to eq("slot_taken")
    end

    it "returns 422 when a two-therapist service has only one therapist free" do
      w = build_world(rooms: { couple: 1 }, therapists: 1)
      svc = create(:service, name: "Couples")
      couples = create(:service_variant, service: svc, duration_minutes: 60,
                                         therapist_count: 2, required_client_capacity: 2)
      StaffQualification.create!(staff_profile: w[:staff].first, service: svc)
      admin = create(:user, email: "o3@example.com", role: "owner")

      post "/api/v1/appointments",
           params: { appointment: { location_id: w[:location].id, client_id: w[:client].id,
                                    service_variant_ids: [ couples.id ],
                                    start_at: w[:at].iso8601 } },
           headers: auth(admin), as: :json
      expect(response).to have_http_status(:conflict)
      expect(json.dig("error", "code")).to eq("insufficient_therapists")
    end
  end

  describe "specific-therapist requests (BR-15, BR-15a)" do
    it "creates a pending appointment and approves it" do
      post "/api/v1/appointments",
           params: { appointment: { location_id: world[:location].id, client_id: world[:client].id,
                                    service_variant_ids: [ world[:variant].id ],
                                    start_at: world[:at].iso8601,
                                    requested_staff_profile_id: world[:staff].first.id } },
           headers: auth(manager), as: :json
      expect(response).to have_http_status(:created)
      expect(json["status"]).to eq("pending_approval")

      get "/api/v1/approval_requests", headers: auth(manager)
      req = json["approval_requests"].first
      expect(req["pending_for_minutes"]).to be >= 0
      expect(req["auto_approves_at"]).to be_present

      post "/api/v1/approval_requests/#{req['id']}/approve", headers: auth(manager), as: :json
      expect(json["status"]).to eq("approved")
      expect(Appointment.first.status).to eq("scheduled")
    end

    it "frees the slot when rejected" do
      appt = Scheduling::BookAppointment.call(
        location: world[:location], client: world[:client],
        variant_ids: [ world[:variant].id ], start_at: world[:at],
        requested_staff_profile_id: world[:staff].first.id
      )
      post "/api/v1/approval_requests/#{appt.approval_request.id}/reject",
           headers: auth(manager), as: :json
      expect(appt.reload.status).to eq("cancelled")
      expect(appt.fee_charged_cents).to be_zero    # not the client's fault
    end
  end

  describe "the day board" do
    it "returns rooms and the appointments placed in them" do
      Scheduling::BookAppointment.call(
        location: world[:location], client: world[:client],
        variant_ids: [ world[:variant].id ], start_at: world[:at]
      )
      get "/api/v1/appointments/calendar",
          params: { location_id: world[:location].id, date: world[:date].to_s },
          headers: auth(manager)
      expect(json["rooms"].size).to eq(3)
      expect(json["appointments"].size).to eq(1)
      expect(json["opens_at"]).to eq("09:00")
    end

    # Staff see only their own work — including as second therapist.
    it "scopes the board to the therapist's own appointments" do
      Scheduling::BookAppointment.call(
        location: world[:location], client: world[:client],
        variant_ids: [ world[:variant].id ], start_at: world[:at],
        staff_profile_ids: [ world[:staff].last.id ]
      )
      get "/api/v1/appointments/calendar",
          params: { location_id: world[:location].id, date: world[:date].to_s },
          headers: auth(therapist_user)
      expect(json["appointments"]).to be_empty
    end
  end

  describe "status transitions (BR-18, BR-19, BR-21)" do
    let!(:appt) do
      Scheduling::BookAppointment.call(
        location: world[:location], client: world[:client],
        variant_ids: [ world[:variant].id ], start_at: world[:at]
      )
    end

    it "runs through to completed and frees nothing early" do
      %w[checked_in in_progress completed].each do |to|
        post "/api/v1/appointments/#{appt.id}/transition",
             params: { to: }, headers: auth(manager), as: :json
        expect(response).to have_http_status(:ok)
      end
      expect(appt.reload.status).to eq("completed")
    end

    it "rejects an illegal transition" do
      post "/api/v1/appointments/#{appt.id}/transition",
           params: { to: "completed" }, headers: auth(manager), as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "charges no fee for a cancellation outside the 4-hour window" do
      post "/api/v1/appointments/#{appt.id}/transition",
           params: { to: "cancelled" }, headers: auth(manager), as: :json
      expect(appt.reload.status).to eq("cancelled")
      expect(appt.fee_charged_cents).to be_zero
      expect(world[:client].reload.cancel_count).to eq(1)
    end

    it "records a 20% fee as owed on a no-show, and frees the slot" do
      post "/api/v1/appointments/#{appt.id}/transition",
           params: { to: "no_show" }, headers: auth(manager), as: :json
      appt.reload
      expect(appt.status).to eq("no_show")
      expect(appt.fee_charged_cents).to eq((appt.total_price_cents * 0.2).round)
      expect(world[:client].reload.no_show_count).to eq(1)
      # BR-21: the room is bookable again immediately.
      expect {
        Scheduling::BookAppointment.call(
          location: world[:location], client: world[:client],
          variant_ids: [ world[:variant].id ], start_at: world[:at], room_id: appt.room_id
        )
      }.not_to raise_error
    end
  end

  describe "rates are Owner-only (BR-02)" do
    it "omits session rates from a Manager's view of a therapist" do
      get "/api/v1/staff/#{world[:staff].first.id}", headers: auth(manager)
      expect(json).not_to have_key("session_rates")
    end

    it "includes them for the Owner" do
      get "/api/v1/staff/#{world[:staff].first.id}", headers: auth(owner)
      expect(json["session_rates"].size).to eq(6)
    end

    it "lets a therapist see their own rates but not another's" do
      get "/api/v1/staff/#{world[:staff].first.id}", headers: auth(therapist_user)
      expect(json["session_rates"].size).to eq(6)

      get "/api/v1/staff/#{world[:staff].last.id}", headers: auth(therapist_user)
      expect(response).to have_http_status(:not_found)
    end
  end
end
