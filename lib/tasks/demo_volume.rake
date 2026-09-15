# Review-scale demo data, so list screens are designed and tested against the
# volumes the business will actually have — not against six seeded clients.
#
#   bin/rails massagelab:demo_volume
#
# Adds 2,000 clients (most with visit history), 1,000 staff across the four
# locations, 500 gift cards and 500 memberships. Idempotent: a second run adds
# nothing. Uses bulk inserts, so it takes seconds rather than minutes.
module DemoVolume
  module_function

  FIRST = %w[Ava Ben Chloe Daniel Ella Finn Grace Henry Isla Jack Kai Luna Mason Nora Owen Piper
             Quinn Ruby Sam Tara Uma Victor Willow Xavier Yara Zane Amira Bilal Carmen Dmitri
             Elena Farah Gabriel Hana Ivan Jia Kenji Leila Mateo Nadia Omar Priya Rafael Sofia
             Tomas Ursula Vera Wei Yusuf Zoe Aditi Bruno Celine Diego Esme Felix Gia Hugo Ines].freeze
  LAST = %w[Anderson Bennett Carter Diaz Evans Foster Garcia Hughes Ito Jensen Khan Lopez Morgan
            Nguyen Ortiz Patel Quinn Rivera Singh Torres Usman Vargas Walker Xu Young Zhang Ahmed
            Brooks Chen Dubois Ellis Fischer Gupta Hansen Ibrahim Johnson Kowalski Larsen Murphy
            Novak Okafor Petrov Reyes Silva Tanaka Ueda Volkov Wright Yilmaz Zimmerman].freeze

  CLIENT_PHONE_PREFIX = "+1773555".freeze

  def load!
    if Client.where("phone LIKE ?", "#{CLIENT_PHONE_PREFIX}%").exists?
      puts "Demo volume already loaded — nothing to do."
      return
    end

    @now = Time.current
    @rng = Random.new(20_260_916)
    @locations = Location.order(:id).to_a
    raise "Run db:seed first — no locations." if @locations.empty?

    ActiveRecord::Base.transaction do
      client_ids = clients!(2_000)
      visits!(client_ids)
      staff!(1_000)
      gift_cards!(500, client_ids)
      memberships!(500, client_ids)
    end

    puts <<~SUMMARY
      Demo volume loaded:
        clients      #{Client.count}
        appointments #{Appointment.count}
        staff        #{StaffProfile.count}
        gift cards   #{GiftCard.count}
        memberships  #{Membership.count}
      Volume staff sign in as volume.staff1@example.test … / password123
    SUMMARY
  end

  def name(i) = [ FIRST[i % FIRST.size], LAST[(i / FIRST.size + i * 7) % LAST.size] ]

  def clients!(count)
    rows = Array.new(count) do |i|
      first, last = name(i)
      email = "#{first}.#{last}.#{i}@example.test".downcase
      {
        first_name: first, last_name: last,
        phone: "#{CLIENT_PHONE_PREFIX}#{format('%04d', i)}", email:,
        search_name: "#{first} #{last} #{email}".downcase,
        status: "active",
        no_show_count: (@rng.rand < 0.1 ? @rng.rand(1..3) : 0),
        late_cancel_count: (@rng.rand < 0.08 ? @rng.rand(1..2) : 0),
        preferred_location_id: @locations.sample(random: @rng).id,
        created_at: @now - @rng.rand(1..900).days, updated_at: @now
      }
    end
    rows.each_slice(1_000) { |slice| Client.insert_all(slice) }
    Client.where("phone LIKE ?", "#{CLIENT_PHONE_PREFIX}%").order(:id).pluck(:id)
  end

  # Past completed visits, so "last visit", "lapsed" and visit counts are real.
  def visits!(client_ids)
    rooms = @locations.to_h { |l| [ l.id, l.rooms.order(:position).first&.id ] }
    seq = 0
    rows = client_ids.flat_map do |client_id|
      next [] if @rng.rand < 0.25 # a quarter have never visited

      Array.new(@rng.rand(1..6)) do
        location = @locations.sample(random: @rng)
        day = (@now - @rng.rand(1..540).days).in_time_zone(location.tz)
        starts = location.tz.local(day.year, day.month, day.day, @rng.rand(9..19), 0)
        seq += 1
        {
          reference: "VOL-#{format('%06d', seq)}", client_id:, location_id: location.id,
          room_id: rooms.fetch(location.id), starts_at: starts,
          service_ends_at: starts + 60.minutes, ends_at: starts + 75.minutes,
          status: "completed", total_price_cents: [ 8_000, 11_500, 15_000 ].sample(random: @rng),
          booking_channel: "manager", staff_assignment_confirmed: true,
          fee_charged_cents: 0, created_at: starts, updated_at: starts
        }
      end
    end
    rows.each_slice(1_000) { |slice| Appointment.insert_all(slice) }
  end

  def staff!(count)
    digest = BCrypt::Password.create("password123", cost: BCrypt::Engine::MIN_COST)
    user_rows = Array.new(count) do |i|
      first, last = name(i + 31)
      {
        email: "volume.staff#{i + 1}@example.test", name: "#{first} #{last}",
        role: (i % 50).zero? ? "manager" : "staff", status: "active",
        location_id: (i % 50).zero? ? @locations[i % @locations.size].id : nil,
        password_digest: digest, created_at: @now, updated_at: @now
      }
    end
    user_rows.each_slice(500) { |slice| User.insert_all(slice) }
    users = User.where("email LIKE ?", "volume.staff%@example.test").order(:id).to_a

    profile_rows = users.each_with_index.map do |user, i|
      offboarded = @rng.rand < 0.05
      {
        user_id: user.id, location_id: @locations[i % @locations.size].id,
        display_name: user.name, employee_code: "VOL-#{format('%04d', i + 1)}",
        engagement_type: user.role == "manager" ? "manager_flat" : "contractor_1099",
        hire_date: (@now - @rng.rand(30..2_000).days).to_date,
        status: offboarded ? "offboarded" : "active",
        termination_date: offboarded ? (@now - @rng.rand(1..200).days).to_date : nil,
        created_at: @now, updated_at: @now
      }
    end
    profile_rows.each_slice(500) { |slice| StaffProfile.insert_all(slice) }

    profiles = StaffProfile.where("employee_code LIKE 'VOL-%'").to_a
    service_ids = Service.payable.pluck(:id)
    qualifications = profiles.flat_map do |p|
      service_ids.map { |sid| { staff_profile_id: p.id, service_id: sid, created_at: @now, updated_at: @now } }
    end
    qualifications.each_slice(2_000) { |slice| StaffQualification.insert_all(slice) }

    ladder = { 30 => 2_500, 45 => 3_500, 60 => 4_500, 75 => 5_500, 90 => 6_500, 120 => 8_500 }
    rates = profiles.select { |p| p.engagement_type == "contractor_1099" }.flat_map do |p|
      ladder.map do |minutes, cents|
        { staff_profile_id: p.id, duration_minutes: minutes, rate_cents: cents,
          effective_from: p.hire_date, created_at: @now, updated_at: @now }
      end
    end
    rates.each_slice(2_000) { |slice| StaffSessionRate.insert_all(slice) }
  end

  def gift_cards!(count, client_ids)
    clients = Client.where(id: client_ids.sample(count, random: @rng)).to_a
    rows = Array.new(count) do |i|
      buyer = @rng.rand < 0.7 ? clients[i % clients.size] : nil
      value = [ 5_000, 10_000, 15_000, 20_000 ].sample(random: @rng)
      balance = [ value, value, value / 2, 0 ].sample(random: @rng)
      sold = @now - @rng.rand(1..500).days
      {
        code: "VOL-GC-#{format('%05d', i + 1)}", origin: "physical",
        initial_value_cents: value, current_balance_cents: balance,
        status: balance.zero? ? "depleted" : "active", purchase_payment_method: "card",
        buyer_client_id: buyer&.id, buyer_name: buyer&.full_name || "#{name(i + 7).join(' ')}",
        buyer_phone: buyer&.phone, sold_at: sold, sold_at_location_id: @locations.sample(random: @rng).id,
        expires_at: sold + 12.months, created_at: sold, updated_at: sold
      }
    end
    GiftCard.insert_all(rows)

    ledger = GiftCard.where("code LIKE 'VOL-GC-%'").flat_map do |card|
      issue = { gift_card_id: card.id, kind: "issue", amount_cents: card.initial_value_cents,
                balance_after_cents: card.initial_value_cents, location_id: card.sold_at_location_id,
                occurred_at: card.sold_at, created_at: card.sold_at, updated_at: card.sold_at }
      spent = card.initial_value_cents - card.current_balance_cents
      next [ issue ] unless spent.positive?

      at = card.sold_at + 20.days
      [ issue, issue.merge(kind: "redeem", amount_cents: -spent, balance_after_cents: card.current_balance_cents,
                           occurred_at: at, created_at: at, updated_at: at) ]
    end
    GiftCardTransaction.insert_all(ledger)
  end

  def memberships!(count, client_ids)
    already = Membership.pluck(:client_id)
    chosen = (client_ids - already).sample(count, random: @rng)
    variant = ServiceVariant.joins(:service).where(duration_minutes: 60, therapist_count: 1)
                            .where("services.name LIKE 'Deep Tissue%'").first
    rows = chosen.map do |client_id|
      enrolled = @now - @rng.rand(10..700).days
      period_start = enrolled + ((@now - enrolled) / 1.month).floor.months
      status = [ "active" ] * 17 + [ "pending_cancellation" ] * 2 + [ "cancelled" ]
      state = status.sample(random: @rng)
      {
        client_id:, location_id: @locations.sample(random: @rng).id, status: state,
        price_cents: 8_000, credits_balance: @rng.rand(0..3),
        default_service_variant_id: variant&.id, enrolled_at: enrolled,
        current_period_start: period_start, current_period_end: period_start + 1.month,
        cancellation_requested_at: state == "active" ? nil : @now - 5.days,
        cancellation_effective_at: state == "active" ? nil : period_start + 1.month,
        created_at: enrolled, updated_at: @now
      }
    end
    Membership.insert_all(rows)
  end
end

namespace :massagelab do
  desc "Load review-scale demo data (2,000 clients, 1,000 staff, 500 gift cards, 500 memberships)"
  task demo_volume: :environment do
    if Rails.env.production? && ENV["ALLOW_DEMO_VOLUME"] != "1"
      abort "Refusing to load demo data in production. Set ALLOW_DEMO_VOLUME=1 only on a review copy."
    end

    DemoVolume.load!
  end
end
