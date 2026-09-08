require "rails_helper"

# The Phase 1 workflows that had models and rules but no code path.
RSpec.describe "Workforce and client administration" do
  let(:world) { build_world(rooms: { single: 2 }, therapists: 2) }
  let(:owner) { create(:user, email: "wa-owner@example.com", role: "owner") }
  let(:manager) { create(:user, email: "wa-mgr@example.com", role: "manager", location: world[:location]) }

  describe "staff requests (BR-05, BR-06)" do
    let(:profile) { world[:staff].first }
    let(:shift) { Shift.find_by(staff_profile_id: profile.id) }

    def shift_change
      StaffRequest.create!(staff_profile: profile, kind: "shift_change", shift:,
                           requested_payload: { "starts_at" => "11:00", "ends_at" => "18:00" })
    end

    def location_change(destination)
      StaffRequest.create!(staff_profile: profile, kind: "location_change",
                           requested_payload: { "location_id" => destination.id })
    end

    it "lets a Manager approve a shift change at their own location" do
      request = shift_change
      Workforce::ApproveStaffRequest.call(request:, actor: manager)

      expect(request.reload.status).to eq("approved")
      expect(shift.reload.starts_at.in_time_zone(world[:location].tz).strftime("%H:%M")).to eq("11:00")
    end

    # BR-06 — the one approval the Owner withheld from Managers.
    it "refuses to let a Manager approve a location change" do
      other = create(:location, code: "dest#{SecureRandom.hex(2)}")
      request = location_change(other)

      expect { Workforce::ApproveStaffRequest.call(request:, actor: manager) }
        .to raise_error(Workforce::ApproveStaffRequest::Forbidden, "owner_approval_required")
      expect(request.reload.status).to eq("submitted")
    end

    it "lets the Owner approve a location change, which moves the therapist" do
      other = create(:location, code: "dest#{SecureRandom.hex(2)}")
      request = location_change(other)

      Workforce::ApproveStaffRequest.call(request:, actor: owner)

      expect(request.reload.status).to eq("approved")
      # BR-03a: moved, not added to.
      expect(profile.reload.location_id).to eq(other.id)
      expect(Shift.where(staff_profile_id: profile.id).where("starts_at >= ?", Time.current)).to be_empty
    end

    it "refuses a location change while the therapist has future bookings" do
      other = create(:location, code: "dest#{SecureRandom.hex(2)}")
      book(world, staff_profile_ids: [ profile.id ])
      request = location_change(other)

      expect { Workforce::ApproveStaffRequest.call(request:, actor: owner) }
        .to raise_error(Workforce::ApproveStaffRequest::Invalid, "has_future_appointments")
      expect(profile.reload.location_id).to eq(world[:location].id)
    end

    # BR-07
    it "refuses a shift change that would orphan a booked appointment" do
      appt = book(world, staff_profile_ids: [ profile.id ])
      request = StaffRequest.create!(staff_profile: profile, kind: "shift_change", shift:,
                                     requested_payload: { "starts_at" => "18:00", "ends_at" => "20:00" })

      expect { Workforce::ApproveStaffRequest.call(request:, actor: owner) }
        .to raise_error(Workforce::ApproveStaffRequest::Invalid, /would_orphan_appointments:#{appt.id}/)
    end

    it "cannot be reviewed twice" do
      request = shift_change
      Workforce::ApproveStaffRequest.call(request:, actor: owner)

      expect { Workforce::ApproveStaffRequest.call(request: request.reload, actor: owner) }
        .to raise_error(Workforce::ApproveStaffRequest::Invalid, "already_reviewed")
    end
  end

  describe "offboarding (BR-02)" do
    let(:profile) { world[:staff].first }

    it "is blocked while future appointments exist, and names them" do
      appt = book(world, staff_profile_ids: [ profile.id ])

      expect { Workforce::OffboardStaff.call(staff_profile: profile, actor: owner) }
        .to raise_error(Workforce::OffboardStaff::Blocked, /#{appt.id}/)
      expect(profile.reload.status).to eq("active")
    end

    it "is soft — history survives and nothing is deleted" do
      # Completed work is history, not a reason to block: it cannot be
      # reassigned or cancelled.
      appt = book(world, staff_profile_ids: [ profile.id ])
      %w[checked_in in_progress completed].each { |t| Scheduling::TransitionStatus.call(appointment: appt, to: t) }
      Earnings::GenerateForAppointment.call(appointment: appt.reload)

      Workforce::OffboardStaff.call(staff_profile: profile, actor: owner)

      expect(profile.reload.status).to eq("terminated")
      expect(profile.user.reload.status).to eq("disabled")
      expect(EarningLine.where(staff_profile_id: profile.id)).to be_present
      expect(StaffProfile.find(profile.id)).to be_present
    end
  end

  describe "client merge (BR-42)" do
    it "repoints history, keeps the loser, and recounts the counters" do
      # The survivor deliberately lacks an email, so the merge has something
      # to carry across.
      keep = create(:client, first_name: "Sarah", last_name: "Johnson",
                             phone: "+13125550101", email: nil)
      dupe = create(:client, first_name: "sarah", last_name: "johnson", phone: "+13125550102",
                             email: "sarah@example.com")

      appt = book(world.merge(client: dupe))
      Scheduling::TransitionStatus.call(appointment: appt, to: "no_show")

      Crm::MergeClients.call(source: dupe, target: keep, actor: owner)

      expect(appt.reload.client_id).to eq(keep.id)
      expect(dupe.reload.status).to eq("merged")
      expect(dupe.merged_into_client_id).to eq(keep.id)
      # Detail the survivor lacked is kept rather than thrown away.
      expect(keep.reload.email).to eq("sarah@example.com")
      # Counters are recomputed, not added, so a shared visit is not doubled.
      expect(keep.no_show_count).to eq(1)
    end

    it "refuses to merge a client into itself" do
      client = create(:client)
      expect { Crm::MergeClients.call(source: client, target: client, actor: owner) }
        .to raise_error(Crm::MergeClients::Invalid, "same_client")
    end

    it "moves a gift card the duplicate had bought" do
      keep = create(:client)
      dupe = create(:client)
      card = GiftCards::IssueCard.call(location: world[:location], amount_cents: 5_000,
                                       payment_method: "cash", actor: owner, buyer_client: dupe)

      Crm::MergeClients.call(source: dupe, target: keep, actor: owner)
      expect(card.reload.buyer_client_id).to eq(keep.id)
    end
  end
end

RSpec.describe "Disabled accounts (BR-02)" do
  let(:world) { build_world(rooms: { single: 1 }) }
  let(:owner) { create(:user, email: "da-owner@example.com", role: "owner") }
  let(:profile) { world[:staff].first }

  it "refuses a sign-in once the account is disabled" do
    user = profile.user
    expect(Auth::AuthenticateUser.call(email: user.email, password: "password123")).to eq(user)

    Workforce::OffboardStaff.call(staff_profile: profile, actor: owner)

    expect(Auth::AuthenticateUser.call(email: user.email, password: "password123")).to be_nil
  end
end

RSpec.describe "Disabled accounts reject an existing token", type: :request do
  let(:world) { build_world(rooms: { single: 1 }) }
  let(:owner) { create(:user, email: "da2-owner@example.com", role: "owner") }

  # A JWT stays valid until it expires, so the check cannot live only at
  # sign-in — an offboarded therapist would keep working access until then.
  it "rejects a token issued before the account was disabled" do
    profile = world[:staff].first
    token = Auth::JwtService.encode(profile.user)
    headers = { "Authorization" => "Bearer #{token}" }

    get "/api/v1/locations", headers: headers
    expect(response).to have_http_status(:ok)

    Workforce::OffboardStaff.call(staff_profile: profile, actor: owner)

    get "/api/v1/locations", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end
end
