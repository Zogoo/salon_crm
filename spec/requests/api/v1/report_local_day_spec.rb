require "rails_helper"

# A report's "today" is the salon's day. After 19:00 in Chicago UTC is already
# tomorrow, so a day bounded in UTC silently drops the evening's ratings.
RSpec.describe "Reports use the salon's own day", type: :request do
  let(:world) { build_world }
  let(:manager) { create(:user, role: "manager", location: world[:location]) }
  let(:owner) { create(:user, role: "owner") }

  def json = JSON.parse(response.body)

  it "keeps an evening rating in that evening's alerts and ratings report" do
    appt = book(world)
    %w[checked_in in_progress completed].each { |t| Scheduling::TransitionStatus.call(appointment: appt, to: t) }
    tz = world[:location].tz
    evening = tz.local(2026, 9, 30, 20, 30)

    travel_to(evening) do
      Crm::RecordRating.call(appointment: appt.reload, score: 3, channel: "kiosk", feedback: "Too cold")
      expect(Time.now.utc.to_date).to eq(Date.new(2026, 10, 1))

      get "/api/v1/reports/ratings/alerts", params: { location_id: world[:location].id }, headers: auth_headers(manager)
      expect(json["alerts"].map { |a| a["score"] }).to eq([ 3 ])

      get "/api/v1/reports/ratings", params: { location_id: world[:location].id }, headers: auth_headers(owner)
      expect(json["count"]).to eq(1)
    end
  end
end
