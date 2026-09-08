require "rails_helper"

RSpec.describe Location do
  describe "#today" do
    # The bug this guards: Date.current follows Time.zone (UTC). The salon is
    # open until 22:00 Central, which is 03:00–04:00 UTC the next day, so any
    # controller defaulting to "today" with Date.current showed an empty board
    # for the last hours of every working day.
    it "is the salon's business date, not UTC's" do
      location = create(:location, timezone: "America/Chicago")

      travel_to Time.utc(2026, 9, 8, 4, 30) do   # 23:30 on the 7th in Chicago
        expect(Date.current).to eq(Date.new(2026, 9, 8))     # UTC has rolled over
        expect(location.today).to eq(Date.new(2026, 9, 7))   # the salon has not
      end
    end

    it "agrees with UTC during the salon's daytime" do
      location = create(:location, timezone: "America/Chicago")

      travel_to Time.utc(2026, 9, 8, 15, 0) do   # 10:00 in Chicago
        expect(location.today).to eq(Date.new(2026, 9, 8))
      end
    end
  end
end
