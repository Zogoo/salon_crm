# Demo users, therapists, shifts and clients. Idempotent, development-shaped.
module Seeds
  module People
    module_function

    THERAPISTS = {
      "lawrence" => %w[Anna Bek Chen Dara Enkh],
      "skokie"   => %w[Fiona Gala Hana Iris],
      "luma"     => %w[Jae Khan Lena Mira Noor],
      "belmont"  => %w[Oyun Pema Rin Saru]
    }.freeze

    # A therapist's rate ladder, cents. All six rungs must exist or a booking
    # on an unfilled rung would be unpayable (doc 02 §3.4).
    LADDER = { 30 => 2500, 45 => 3500, 60 => 4500, 75 => 5500, 90 => 6500, 120 => 8500 }.freeze

    CLIENTS = [
      %w[Sarah Johnson +13125550101 sarah.johnson@example.com],
      %w[Michael Chen +13125550102 michael.chen@example.com],
      %w[Emily Rodriguez +13125550103 emily.rodriguez@example.com],
      %w[David Kim +13125550104 david.kim@example.com],
      %w[Jessica Brown +13125550105 jessica.brown@example.com],
      %w[Robert Wilson +13125550106 robert.wilson@example.com]
    ].freeze

    def seed!(locations)
      owner = seed_owner
      managers = seed_managers(locations)
      staff = seed_therapists(locations)
      seed_shifts(staff)
      clients = seed_clients(locations)
      { owner:, managers:, staff:, clients: }
    end

    def seed_owner
      User.find_or_create_by!(email: "owner@mongolianmassagelab.com") do |u|
        u.name = "Owner"
        u.role = "owner"
        u.password = "password123"
      end
    end

    def seed_managers(locations)
      locations.map do |code, location|
        User.find_or_create_by!(email: "manager.#{code}@mongolianmassagelab.com") do |u|
          u.name = "#{location.name} Manager"
          u.role = "manager"
          u.location = location
          u.password = "password123"
        end
      end
    end

    def seed_therapists(locations)
      # Every therapist is qualified for every service at their location, which
      # keeps the demo bookable; real onboarding sets these individually (BR-01).
      payable_services = Service.payable.to_a

      THERAPISTS.flat_map do |code, names|
        location = locations.fetch(code)
        names.each_with_index.map do |name, i|
          user = User.find_or_create_by!(email: "#{name.downcase}.#{code}@mongolianmassagelab.com") do |u|
            u.name = name
            u.role = "staff"
            u.password = "password123"
          end

          profile = StaffProfile.find_or_create_by!(user:) do |p|
            p.location = location
            p.employee_code = "#{code.upcase[0, 3]}-#{(i + 1).to_s.rjust(3, '0')}"
            p.display_name = name
            p.hire_date = Date.new(2026, 1, 1)
          end

          payable_services.each do |service|
            StaffQualification.find_or_create_by!(staff_profile: profile, service:)
          end

          LADDER.each do |duration, cents|
            StaffSessionRate.find_or_create_by!(staff_profile: profile,
                                                duration_minutes: duration,
                                                effective_from: Date.new(2026, 1, 1)) do |r|
              r.rate_cents = cents
            end
          end
          profile
        end
      end
    end

    # 09:00–22:00 shifts for the next 30 days, so the day board and the
    # availability search have something to work with immediately.
    def seed_shifts(staff, days: 30)
      today = Date.current
      staff.each do |profile|
        location = profile.location
        tz = location.tz
        (0...days).each do |offset|
          date = today + offset
          next if date.sunday?
          starts = tz.local(date.year, date.month, date.day, 9, 0)
          ends   = tz.local(date.year, date.month, date.day, 22, 0)
          Shift.find_or_create_by!(staff_profile: profile, location:, work_date: date) do |s|
            s.starts_at = starts
            s.ends_at = ends
            s.status = "published"
          end
        end
      end
    end

    def seed_clients(locations)
      CLIENTS.map do |first, last, phone, email|
        client = Client.find_or_create_by!(phone:) do |c|
          c.first_name = first
          c.last_name = last
          c.email = email
          c.preferred_location = locations.values.sample
        end
        ClientPreference.find_or_create_by!(client:) do |p|
          p.pressure = ClientPreference::PRESSURES.sample
          p.attention_areas = "Neck and shoulders"
          p.avoid_areas = "Lower back"
        end
        client
      end
    end
  end
end
