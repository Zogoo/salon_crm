require "rails_helper"

# Doc 05 §4 and doc 02 §3.2 — hours, closures and room blocks all feed C1 and
# the room side of the availability search, so each is tested by its effect on
# what can actually be booked.
RSpec.describe "Location and room administration API", type: :request do
  let(:world)   { build_world(rooms: { single: 1 }, therapists: 1) }
  let(:owner)   { create(:user, email: "loc-owner@example.com", role: "owner") }
  let(:manager) { create(:user, email: "loc-mgr@example.com", role: "manager", location: world[:location]) }
  let(:location) { world[:location] }
  let(:room) { location.rooms.first }

  def auth(user) = { "Authorization" => "Bearer #{Auth::JwtService.encode(user)}" }
  def json = JSON.parse(response.body)

  def slots_on(date = world[:date])
    Scheduling::AvailabilitySearch.call(
      location:, variants: [ world[:variant] ], date_from: date
    ).first[:slots]
  end

  describe "closures (C1)" do
    it "empties the day and refuses the booking outright" do
      expect(slots_on).not_to be_empty

      post "/api/v1/locations/#{location.id}/closures",
           params: { date: world[:date].to_s, reason: "Thanksgiving" },
           headers: auth(owner), as: :json
      expect(response).to have_http_status(:created)

      expect(slots_on).to be_empty
      # The search hides it; the writer still has to say no to a direct POST.
      expect { book(world) }.to raise_error(Scheduling::BookAppointment::Conflict, "location_closed")
    end

    it "will not close a day that already has appointments" do
      appointment = book(world)

      post "/api/v1/locations/#{location.id}/closures",
           params: { date: world[:date].to_s }, headers: auth(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details", "appointment_ids")).to include(appointment.id)
      expect(location.closures).to be_empty
    end
  end

  describe "room blocks" do
    it "takes the room out of the search and out of booking" do
      slot = slots_on.first

      post "/api/v1/rooms/#{room.id}/blocks",
           params: { starts_at: slot.start_at.iso8601, ends_at: (slot.start_at + 3.hours).iso8601,
                     reason: "Deep clean" },
           headers: auth(manager), as: :json
      expect(response).to have_http_status(:created)

      expect(slots_on.map(&:start_at)).not_to include(slot.start_at)
      expect { book(world, start_at: slot.start_at) }
        .to raise_error(Scheduling::BookAppointment::Conflict)
    end

    it "will not block a room out from under a booking" do
      appointment = book(world)

      post "/api/v1/rooms/#{room.id}/blocks",
           params: { starts_at: appointment.starts_at.iso8601, ends_at: appointment.ends_at.iso8601 },
           headers: auth(manager), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("block_has_appointments")
    end
  end

  describe "business hours" do
    # Doc 02 §3.2 allows several rows per weekday, which is how split hours
    # (a midday close) are expressed.
    it "supports split hours and excludes the gap" do
      dow = world[:date].wday
      put "/api/v1/locations/#{location.id}/business_hours",
          params: { business_hours: [ { day_of_week: dow, opens_at: "09:00", closes_at: "12:00" },
                                      { day_of_week: dow, opens_at: "17:00", closes_at: "21:00" } ] },
          headers: auth(owner), as: :json
      expect(response).to have_http_status(:ok)

      hours = slots_on.map { |s| s.start_at.in_time_zone(location.tz).hour }.uniq
      expect(hours).to all(satisfy { |h| h < 12 || h >= 17 })
      expect(location.reload.open_minutes_on(world[:date])).to eq(180 + 240)
    end

    it "keeps hours editing to the Owner" do
      put "/api/v1/locations/#{location.id}/business_hours",
          params: { business_hours: [ { day_of_week: 1, opens_at: "09:00", closes_at: "10:00" } ] },
          headers: auth(manager), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "rooms" do
    it "lets the Owner add a room that the engine can then use" do
      post "/api/v1/rooms",
           params: { location_id: location.id,
                     room: { name: "Couple 9", room_type: "couple", client_capacity: 2, position: 9 } },
           headers: auth(owner), as: :json

      expect(response).to have_http_status(:created)
      expect(location.rooms.reload.map(&:name)).to include("Couple 9")
    end
  end
end
