require "rails_helper"

RSpec.describe "Analytics reports" do
  let(:world) { build_world(rooms: { single: 2 }, therapists: 2) }
  let(:owner) { create(:user, email: "an-owner@example.com", role: "owner") }

  def complete(appt)
    %w[checked_in in_progress completed].each { |t| Scheduling::TransitionStatus.call(appointment: appt, to: t) }
    appt.reload
  end

  describe "no-shows (FRS §21)" do
    it "reports rates and separates fees owed from fees collected" do
      complete(book(world))
      no_show = book(world, start_at: world[:at] + 3.hours)
      Scheduling::TransitionStatus.call(appointment: no_show, to: "no_show")

      data = Reporting::NoShows.call(location_ids: [ world[:location].id ],
                                     from: world[:date], to: world[:date])

      expect(data[:appointments]).to eq(2)
      expect(data[:no_shows]).to eq(1)
      expect(data[:no_show_rate]).to eq(50.0)
      # Release 1 records the fee as owed; nothing is collected.
      expect(data[:fees_owed_cents]).to be_positive
      expect(data[:fees_collected_cents]).to be_zero
      expect(data[:by_therapist].values.sum).to be >= 1
    end
  end

  describe "utilisation (BR-28)" do
    it "measures against published shift minutes and open room minutes" do
      complete(book(world))   # a 60-minute service

      data = Reporting::Utilization.call(location: world[:location],
                                         from: world[:date], to: world[:date])

      # 09:00–22:00 is 13 hours of room time.
      expect(data[:open_minutes_per_room]).to eq(780)

      room = data[:rooms].find { |r| r[:booked_minutes].positive? }
      # The buffer is reserved, not sold — counting it would flatter this by 20%.
      expect(room[:booked_minutes]).to eq(60)
      expect(room[:utilization_percent]).to eq((60.0 / 780 * 100).round(1))

      therapist = data[:therapists].find { |t| t[:booked_minutes].positive? }
      expect(therapist[:available_minutes]).to eq(780)   # the published shift
    end

    it "reports zero rather than dividing by zero when nobody is scheduled" do
      Shift.delete_all
      data = Reporting::Utilization.call(location: world[:location],
                                         from: world[:date], to: world[:date])
      expect(data[:therapists].map { |t| t[:utilization_percent] }).to all(eq(0.0))
    end
  end

  describe "client retention" do
    it "separates new from returning, and lists lapsed clients" do
      complete(book(world))

      lapsed_client = create(:client)
      old = book(world.merge(client: lapsed_client), start_at: world[:at] + 3.hours)
      complete(old)
      old.update_column(:starts_at, 200.days.ago)

      data = Reporting::ClientRetention.call(location_ids: [ world[:location].id ],
                                             from: world[:date], to: world[:date])

      expect(data[:clients_seen]).to eq(1)
      expect(data[:new_clients]).to eq(1)
      expect(data[:returning_clients]).to be_zero
      expect(data[:lapsed][:client_ids]).to include(lapsed_client.id)
      expect(data[:top_clients].first[:spend_cents]).to be_positive
    end
  end
end
