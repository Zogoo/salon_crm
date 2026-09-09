require "rails_helper"

# Doc 05 §"Shifts" and BR-07 / doc 03 §4.7.
RSpec.describe "Roster management API", type: :request do
  let(:world)   { build_world(rooms: { single: 2 }, therapists: 2) }
  let(:owner)   { create(:user, email: "ro-owner@example.com", role: "owner") }
  let(:manager) { create(:user, email: "ro-mgr@example.com", role: "manager", location: world[:location]) }

  def auth(user) = { "Authorization" => "Bearer #{Auth::JwtService.encode(user)}" }
  def json = JSON.parse(response.body)

  let(:appointment) { book(world) }
  let(:shift) { Shift.published.find_by!(staff_profile_id: appointment.staff_profiles.first.id) }
  let(:tz) { world[:location].tz }

  describe "the BR-07 guard is the same guard everywhere" do
    it "refuses to shorten a shift out from under a booking" do
      patch "/api/v1/shifts/#{shift.id}",
            params: { shift: { starts_at: appointment.ends_at.in_time_zone(tz).strftime("%H:%M") } },
            headers: auth(manager), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("would_orphan_appointments")
      expect(json.dig("error", "details", "appointment_ids")).to include(appointment.id)
      expect(shift.reload.starts_at).to be < appointment.starts_at
    end

    it "refuses to delete a shift that still has one" do
      delete "/api/v1/shifts/#{shift.id}", headers: auth(manager)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("shift_has_appointments")
      expect(Shift.exists?(shift.id)).to be(true)
    end

    it "refuses to drop a break on top of one" do
      post "/api/v1/shifts/#{shift.id}/breaks",
           params: { starts_at: appointment.starts_at.in_time_zone(tz).strftime("%H:%M"),
                     ends_at: appointment.service_ends_at.in_time_zone(tz).strftime("%H:%M") },
           headers: auth(manager), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("break_has_appointments")
      expect(shift.shift_breaks).to be_empty
    end

    it "allows a change that still covers everything booked" do
      patch "/api/v1/shifts/#{shift.id}",
            params: { shift: { ends_at: "22:00" } }, headers: auth(manager), as: :json

      expect(response).to have_http_status(:ok)
      expect(shift.reload.ends_at.in_time_zone(tz).strftime("%H:%M")).to eq("22:00")
    end
  end

  describe "publishing a drafted roster" do
    let(:therapist) { world[:staff].last }
    let(:draft) do
      Shift.create!(staff_profile: therapist, location: world[:location], status: "draft",
                    work_date: world[:at].to_date + 7, starts_at: world[:at] + 7.days,
                    ends_at: world[:at] + 7.days + 8.hours)
    end

    it "publishes in bulk" do
      post "/api/v1/shifts/publish", params: { shift_ids: [ draft.id ] },
           headers: auth(manager), as: :json

      expect(response).to have_http_status(:ok)
      expect(draft.reload.status).to eq("published")
    end

    # A half-published week is a week where some therapists are silently
    # unbookable, so one clash rolls the whole batch back.
    it "publishes all or nothing when one shift clashes" do
      clashing = Shift.create!(staff_profile: therapist, location: world[:location], status: "draft",
                               work_date: draft.work_date, starts_at: draft.starts_at + 1.hour,
                               ends_at: draft.ends_at + 1.hour)

      post "/api/v1/shifts/publish", params: { shift_ids: [ draft.id, clashing.id ] },
           headers: auth(manager), as: :json

      expect(response).to have_http_status(:conflict)
      expect([ draft.reload.status, clashing.reload.status ]).to eq(%w[draft draft])
    end
  end

  describe "roster reads" do
    it "returns the range for index and the who-is-off view for day" do
      get "/api/v1/shifts", params: { location_id: world[:location].id },
          headers: auth(owner)
      expect(json).to have_key("shifts")

      get "/api/v1/shifts/day",
          params: { location_id: world[:location].id, date: world[:at].to_date.to_s },
          headers: auth(owner)
      expect(json).to have_key("working").and have_key("not_working")
    end

    # The roster cannot tell a draft from a live shift without this, and would
    # offer to publish what is already published.
    it "says whether each shift is published" do
      get "/api/v1/shifts",
          params: { location_id: world[:location].id,
                    from: world[:date].to_s, to: world[:date].to_s },
          headers: auth(owner)

      statuses = json["shifts"].map { |s| s["status"] }
      expect(statuses).to all(be_present)
      expect(statuses).to include("published")
    end

    it "lists the breaks on a shift" do
      post "/api/v1/shifts/#{shift.id}/breaks",
           params: { starts_at: "21:00", ends_at: "21:30", reason: "dinner" },
           headers: auth(manager), as: :json
      expect(response).to have_http_status(:created)

      get "/api/v1/shifts/#{shift.id}/breaks", headers: auth(manager)
      expect(json["breaks"].first["reason"]).to eq("dinner")
    end
  end
end
