require "rails_helper"

# The shared list contract (Listable): server-side search, filters, sorting and
# paging, with a capped page size — what makes 2,000 clients usable.
RSpec.describe "List API", type: :request do
  let(:world) { build_world(rooms: { single: 2 }, therapists: 3) }
  let(:owner) { create(:user, role: "owner") }
  let(:headers) { auth_headers(owner) }

  def json = JSON.parse(response.body)

  describe "clients" do
    before do
      world
      30.times { |i| create(:client, first_name: "Page#{format('%02d', i)}", last_name: "Zed") }
    end

    it "pages with a meta block that says where you are" do
      get "/api/v1/clients", params: { q: "zed", limit: 10, page: 2 }, headers: headers

      expect(json["clients"].size).to eq(10)
      expect(json["meta"]).to include("count" => 30, "page" => 2, "pages" => 3, "limit" => 10, "sort" => "name")
    end

    it "caps the page size and lands a page past the end on the last page" do
      get "/api/v1/clients", params: { limit: 5_000, page: 99 }, headers: headers

      expect(json["meta"]["limit"]).to eq(100)
      expect(json["meta"]["page"]).to eq(json["meta"]["pages"])
    end

    it "sorts only by whitelisted keys, in either direction" do
      get "/api/v1/clients", params: { q: "zed", sort: "name", dir: "desc", limit: 3 }, headers: headers
      expect(json["clients"].first["first_name"]).to eq("Page29")

      get "/api/v1/clients", params: { q: "zed", sort: "phone; DROP TABLE clients", limit: 3 }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(json["meta"]["sort"]).to eq("name")
    end

    it "filters by no-shows, membership and visit history, and reports the last visit" do
      flaky = Client.find_by!(first_name: "Page01")
      flaky.update!(no_show_count: 2)
      member = Client.find_by!(first_name: "Page02")
      Membership.create!(client: member, location: world[:location], status: "active", price_cents: 8_000,
                         enrolled_at: Time.current, current_period_start: Time.current,
                         current_period_end: 1.month.from_now)
      visited = Client.find_by!(first_name: "Page03")
      appt = Scheduling::BookAppointment.call(location: world[:location], client: visited,
                                              variant_ids: [ world[:variant].id ], start_at: world[:at])
      appt.update_columns(status: "completed", starts_at: 10.days.ago, service_ends_at: 10.days.ago + 1.hour,
                          ends_at: 10.days.ago + 75.minutes)

      get "/api/v1/clients", params: { q: "zed", no_shows: "true" }, headers: headers
      expect(json["clients"].pluck("id")).to eq([ flaky.id ])

      get "/api/v1/clients", params: { q: "zed", membership: "member" }, headers: headers
      expect(json["clients"].pluck("id")).to eq([ member.id ])
      expect(json["clients"].first["member"]).to be(true)

      get "/api/v1/clients", params: { q: "zed", visited: "recent" }, headers: headers
      row = json["clients"].sole
      expect(row).to include("id" => visited.id, "visits_count" => 1)
      expect(row["last_visit_at"]).to be_present

      get "/api/v1/clients", params: { q: "zed", visited: "never" }, headers: headers
      expect(json["meta"]["count"]).to eq(29)
    end

    it "sorts by last visit with never-visited clients last in both directions" do
      recent, older = %w[Page05 Page06].map { |name| Client.find_by!(first_name: name) }
      { recent => 2.days.ago, older => 20.days.ago }.each_with_index do |(client, at), i|
        appt = Scheduling::BookAppointment.call(location: world[:location], client:,
                                                variant_ids: [ world[:variant].id ],
                                                start_at: world[:at] + (i * 2).hours)
        appt.update_columns(status: "completed", starts_at: at, service_ends_at: at + 1.hour,
                            ends_at: at + 75.minutes)
      end

      get "/api/v1/clients", params: { q: "zed", sort: "last_visit", dir: "desc", limit: 100 }, headers: headers
      expect(json["clients"].first(2).pluck("id")).to eq([ recent.id, older.id ])
      expect(json["clients"].last["last_visit_at"]).to be_nil

      get "/api/v1/clients", params: { q: "zed", sort: "last_visit", dir: "asc", limit: 100 }, headers: headers
      expect(json["clients"].first(2).pluck("id")).to eq([ older.id, recent.id ])
      expect(json["clients"].last["last_visit_at"]).to be_nil
    end
  end

  # Sorting is built from Arel nodes only. A whitelist entry that is SQL text
  # is refused outright, so no later change can reintroduce string splicing.
  describe "sort whitelist entries" do
    let(:lister) { Class.new { include Listable }.new }

    it "accepts column symbols and Arel nodes, and refuses SQL strings" do
      table = Client.arel_table
      expect(lister.send(:sort_expression, table, :last_name)).to eq(table[:last_name])
      expect(lister.send(:sort_expression, table, ClientsQuery.last_visit)).to be_a(Arel::Nodes::Grouping)
      expect { lister.send(:sort_expression, table, "clients.last_name") }.to raise_error(ArgumentError)
      expect { lister.send(:sort_expression, table, Arel.sql("clients.last_name")) }.to raise_error(ArgumentError)
    end
  end

  describe "staff" do
    it "searches by name or code, filters by role, and pages" do
      manager_user = create(:user, role: "manager", location: world[:location], email: "lead@example.com")
      create(:staff_profile, user: manager_user, location: world[:location], display_name: "Lead Person",
                             employee_code: "LEAD-1", engagement_type: "manager_flat")

      get "/api/v1/staff", params: { location_id: world[:location].id, q: "lead-1" }, headers: headers
      expect(json["staff"].pluck("display_name")).to eq([ "Lead Person" ])

      get "/api/v1/staff", params: { location_id: world[:location].id, role: "staff", limit: 2 }, headers: headers
      expect(json["staff"].size).to eq(2)
      expect(json["meta"]).to include("count" => 3, "pages" => 2)
    end
  end

  describe "gift cards" do
    it "finds expired cards that still hold money, newest first by default" do
      location = world[:location]
      fresh = GiftCards::IssueCard.call(location:, amount_cents: 5_000, payment_method: "cash", actor: owner,
                                        buyer_name: "Fresh Buyer")
      old = GiftCards::IssueCard.call(location:, amount_cents: 5_000, payment_method: "cash", actor: owner,
                                      buyer_name: "Old Buyer")
      old.update_columns(expires_at: 1.day.ago, sold_at: 2.years.ago)

      get "/api/v1/gift_cards", params: { status: "expired" }, headers: headers
      expect(json["gift_cards"].pluck("code")).to eq([ old.code ])

      get "/api/v1/gift_cards", params: { q: "fresh buyer" }, headers: headers
      expect(json["gift_cards"].pluck("code")).to eq([ fresh.code ])

      get "/api/v1/gift_cards", headers: headers
      expect(json["gift_cards"].first["code"]).to eq(fresh.code)
      expect(json["meta"]).to include("sort" => "sold", "dir" => "desc")
    end
  end

  describe "memberships" do
    it "searches members by client name and filters those at the credit cap" do
      capped = create(:client, first_name: "Capped", last_name: "Member")
      other = create(:client, first_name: "Other", last_name: "Member")
      [ [ capped, Membership::CREDIT_CAP ], [ other, 0 ] ].each do |client, credits|
        Membership.create!(client:, location: world[:location], status: "active", price_cents: 8_000,
                           credits_balance: credits, enrolled_at: Time.current,
                           current_period_start: Time.current, current_period_end: 1.month.from_now)
      end

      get "/api/v1/memberships", params: { at_cap: "true" }, headers: headers
      expect(json["memberships"].map { |m| m.dig("client", "id") }).to eq([ capped.id ])

      get "/api/v1/memberships", params: { q: "other member" }, headers: headers
      expect(json["memberships"].map { |m| m.dig("client", "id") }).to eq([ other.id ])
      expect(json["meta"]["count"]).to eq(1)

      # Sorting by the joined client's name, without any SQL text in the whitelist.
      capped.update!(last_name: "Aardvark")
      get "/api/v1/memberships", params: { sort: "client", dir: "asc" }, headers: headers
      expect(json["memberships"].first.dig("client", "id")).to eq(capped.id)
      get "/api/v1/memberships", params: { sort: "client", dir: "desc" }, headers: headers
      expect(json["memberships"].last.dig("client", "id")).to eq(capped.id)
    end
  end

  it "pages a client's visit history" do
    client = world[:client]
    3.times do |i|
      book(world, start_at: world[:at] + (i * 2).hours)
    end

    get "/api/v1/clients/#{client.id}/appointments", params: { limit: 2 }, headers: headers
    expect(json["appointments"].size).to eq(2)
    expect(json["meta"]).to include("count" => 3, "pages" => 2)
  end
end
