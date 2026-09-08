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

RSpec.describe Client do
  describe ".to_e164" do
    # Doc 02 §5. The importer's whole job is not to duplicate people, so
    # "(312) 555-0101" and "+13125550101" must land on one client.
    it "normalises US formats to a single key" do
      %w[(312)555-0101 312-555-0101 3125550101 +13125550101 13125550101].each do |input|
        expect(described_class.to_e164(input)).to eq("+13125550101")
      end
    end

    it "leaves an already-international number alone" do
      expect(described_class.to_e164("+976 11 123456")).to eq("+97611123456")
    end

    it "does not invent a country code for something it cannot parse" do
      expect(described_class.to_e164("12345")).to eq("12345")
      expect(described_class.to_e164("")).to eq("")
    end

    it "finds the same client whichever format is entered" do
      client = create(:client, phone: "(312) 555-4242")
      expect(client.reload.phone).to eq("+13125554242")
      expect(Client.find_by(phone: Client.to_e164("312-555-4242"))).to eq(client)
    end
  end
end
