require "rails_helper"

# FRS §11.2, doc 01 §3.10, and BR-44, BR-45, BR-45a.
RSpec.describe "Ratings and care notes" do
  let(:world) { build_world(rooms: { single: 2 }, therapists: 2) }
  let!(:owner) { create(:user, email: "r-owner@example.com", role: "owner") }
  let!(:manager) do
    create(:user, email: "r-mgr@example.com", role: "manager", location: world[:location])
  end

  def complete(appt)
    %w[checked_in in_progress completed].each { |t| Scheduling::TransitionStatus.call(appointment: appt, to: t) }
    appt.reload
  end

  let(:appointment) { complete(book(world)) }

  describe "ratings" do
    it "records a 1-10 score against the appointment and the therapist" do
      rating = Crm::RecordRating.call(appointment:, score: 9, channel: "kiosk",
                                      feedback: "Great pressure", would_recommend: true)
      expect(rating.score).to eq(9)
      expect(rating.staff_profile_id).to eq(appointment.staff_profiles.first.id)
    end

    it "rejects a second rating for the same appointment (BR-45)" do
      Crm::RecordRating.call(appointment:, score: 8, channel: "kiosk")
      expect { Crm::RecordRating.call(appointment:, score: 3, channel: "kiosk") }
        .to raise_error(Crm::RecordRating::Invalid, "already_rated")
    end

    it "rejects a score outside 1-10" do
      expect { Crm::RecordRating.call(appointment:, score: 11, channel: "kiosk") }
        .to raise_error(Crm::RecordRating::Invalid, /1-10/)
    end

    # BR-45a: **below** the threshold. The default is 6, so 5 alerts and 6 does not.
    it "alerts Owner and the location Manager on a score below the threshold" do
      Crm::RecordRating.call(appointment:, score: 5, channel: "kiosk")
      alerts = Notification.where(template_key: "low_rating_alert")

      expect(alerts).to be_present
      recipients = alerts.map { |n| n.recipient_id }.uniq
      expect(recipients).to include(owner.id, manager.id)
    end

    it "does not alert on the threshold itself" do
      Crm::RecordRating.call(appointment:, score: 6, channel: "kiosk")
      expect(Notification.where(template_key: "low_rating_alert")).to be_empty
    end

    it "does not alert a Manager at another location" do
      other = create(:location, code: "elsewhere#{SecureRandom.hex(2)}")
      stranger = create(:user, email: "stranger@example.com", role: "manager", location: other)
      Crm::RecordRating.call(appointment:, score: 2, channel: "kiosk")

      ids = Notification.where(template_key: "low_rating_alert").map(&:recipient_id)
      expect(ids).not_to include(stranger.id)
    end
  end

  describe "care notes" do
    let(:therapist) { appointment.staff_profiles.first }

    it "records an encrypted note readable through the model" do
      note = Crm::RecordCareNote.call(appointment:, staff_profile: therapist,
                                      body: "Avoid left knee — recent surgery")
      raw = CareNote.connection.select_value("SELECT body FROM care_notes WHERE id=#{note.id}")

      expect(note.reload.body).to eq("Avoid left knee — recent surgery")
      expect(raw).not_to include("knee")     # ciphertext at rest
    end

    # BR-44
    it "is append-only — a correction supersedes rather than edits" do
      note = Crm::RecordCareNote.call(appointment:, staff_profile: therapist, body: "First")
      expect(note.update(body: "Changed")).to be(false)

      correction = Crm::RecordCareNote.call(appointment:, staff_profile: therapist,
                                            body: "Corrected", supersedes: note)
      expect(correction.supersedes_note_id).to eq(note.id)
      expect(appointment.care_notes.count).to eq(2)
    end

    it "refuses a therapist who is not on the appointment" do
      stranger = world[:staff].last
      stranger = create(:staff_profile, location: world[:location]) if stranger == therapist

      expect { Crm::RecordCareNote.call(appointment:, staff_profile: stranger, body: "x") }
        .to raise_error(Crm::RecordCareNote::Forbidden)
    end
  end

  describe "notifications (FRS §22)" do
    it "queues an email and an SMS confirmation, plus both reminders" do
      appt = book(world)   # booking transitions to scheduled, which confirms
      keys = Notification.where(appointment_id: appt.id).pluck(:template_key).uniq

      expect(keys).to include("booking_confirmation")
      expect(keys).to include("appointment_reminder_24h", "appointment_reminder_2h")
      confirmations = Notification.where(appointment_id: appt.id,
                                         template_key: "booking_confirmation")
      expect(confirmations.pluck(:channel)).to contain_exactly("email", "sms")
    end

    it "schedules the reminders at 24 h and 2 h before the start" do
      appt = book(world)
      r24 = Notification.find_by(appointment_id: appt.id, template_key: "appointment_reminder_24h", channel: "sms")
      r2  = Notification.find_by(appointment_id: appt.id, template_key: "appointment_reminder_2h", channel: "sms")

      expect(r24.scheduled_for).to be_within(1.minute).of(appt.starts_at - 24.hours)
      expect(r2.scheduled_for).to be_within(1.minute).of(appt.starts_at - 2.hours)
    end

    it "sends the rating request by SMS only — FRS §11.2 specifies a text link" do
      appt = complete(book(world))
      requests = Notification.where(appointment_id: appt.id, template_key: "rating_request")

      expect(requests.pluck(:channel)).to eq([ "sms" ])
      expect(appt.reload.rating_token).to be_present
    end

    # FRS §22 rules both of these out, so their absence is a decision.
    it "never queues a membership renewal or cancellation-window reminder" do
      book(world)
      expect(Notification.where("template_key LIKE '%renewal%'")).to be_empty
      expect(Notification.where("template_key LIKE '%cancellation_window%'")).to be_empty
    end

    it "queues a fee notice when a no-show fee is recorded" do
      appt = book(world)
      Scheduling::TransitionStatus.call(appointment: appt, to: "no_show")
      expect(Notification.where(appointment_id: appt.id, template_key: "fee_charged")).to be_present
    end
  end
end
