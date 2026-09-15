# Seed data transcribed from FRS §19 (menu) and §20 (rooms). Idempotent.
module Seeds
  module Catalogue
    module_function

    # FRS §20 — 28 rooms across four locations.
    ROOMS = {
      "skokie"   => { single: 3, couple: 3, three_table: 1, head_spa: 0 },
      "lawrence" => { single: 4, couple: 4, three_table: 0, head_spa: 0 },
      "luma"     => { single: 3, couple: 3, three_table: 0, head_spa: 2 },
      "belmont"  => { single: 2, couple: 4, three_table: 0, head_spa: 0 }
    }.freeze

    CAPACITY = { single: 1, couple: 2, three_table: 3, head_spa: 2 }.freeze

    LOCATIONS = [
      { code: "lawrence", name: "Lawrence" },
      { code: "skokie",   name: "Skokie" },
      { code: "luma",     name: "Luma" },
      { code: "belmont",  name: "Belmont" }
    ].freeze

    CATEGORIES = [
      { code: "massage",     name: "Massage",     position: 1 },
      { code: "facial",      name: "Facial",      position: 2 },
      { code: "head_spa",    name: "Head Spa",    position: 3 },
      { code: "bioelectric", name: "Bioelectric", position: 4 },
      { code: "add_on",      name: "Add-Ons",     position: 5 },
      { code: "enhancement", name: "Enhancements", position: 6 }
    ].freeze

    # Prices are cents. `nil` means the length is not offered.
    # Standard tier: Lawrence, Skokie, Luma (FRS §19.2, §19.4).
    # Premium tier: Belmont (FRS §19.7).
    MASSAGE = [
      { name: "Deep Tissue / Sport / Swedish massage", therapists: 1, capacity: 1,
        std: { 60 => 8000,  90 => 11500, 120 => 15000 },
        bel: { 60 => 9000,  90 => 13000, 120 => 17000 } },
      { name: "Lymphatic massage", therapists: 1, capacity: 1,
        std: { 60 => 9000,  90 => 12500, 120 => 16000 },
        bel: { 60 => 10000, 90 => 14000, 120 => 18000 } },
      { name: "Pregnancy massage", therapists: 1, capacity: 1,
        std: { 60 => 9000,  90 => 12500 },
        bel: { 60 => 10000, 90 => 14000 } },
      { name: "Couples massage", therapists: 2, capacity: 2,
        std: { 60 => 16000, 90 => 23000, 120 => 30000 },
        bel: { 60 => 18000, 90 => 26000, 120 => 34000 } },
      { name: "Four hands massage", therapists: 2, capacity: 1,
        std: { 60 => 15000, 90 => 22000, 120 => 29000 },
        bel: { 60 => 17000, 90 => 25000, 120 => 33000 } }
    ].freeze

    # FRS §19.3 / §19.8 — facial menu at Lawrence, Skokie and Belmont.
    FACIAL_COMMON = [
      { name: "Facial massage",              std: { 60 => 9000 },  bel: { 60 => 9500 } },
      { name: "Facial and body combination", std: { 90 => 12500, 120 => 16000 },
                                             bel: { 90 => 14000, 120 => 18000 } }
    ].freeze

    # FRS §19.5 — Luma's own facial menu, distinct from the others.
    FACIAL_LUMA = [
      { name: "Anti-aging facial massage",   prices: { 75 => 9000 } },
      { name: "Volumizing facial massage",   prices: { 60 => 13000 } },
      { name: "Timeless lift facial",        prices: { 90 => 14000 } },
      { name: "Radiance Revival Facial",     prices: { 90 => 17500 } },
      { name: "Facial and body combination", prices: { 90 => 12500, 120 => 16000 } }
    ].freeze

    # FRS §19.6 — Luma only. Head spa needs an exclusive head-spa room.
    LUMA_SPECIAL = [
      { name: "Single head spa", category: "head_spa", prices: { 60 => 9000 },
        therapists: 1, capacity: 1, room_type: "head_spa" },
      { name: "Couple head spa", category: "head_spa", prices: { 60 => 18000 },
        therapists: 2, capacity: 2, room_type: "head_spa" },
      { name: "Body Bioelectric Meridian Therapy", category: "bioelectric",
        prices: { 60 => 12000 }, therapists: 1, capacity: 1 },
      { name: "Facial Bioelectric Meridian Therapy", category: "bioelectric",
        prices: { 60 => 12000 }, therapists: 1, capacity: 1 }
    ].freeze

    # FRS §19.9 / §19.10 — 30-minute add-ons. $35 standard, $40 Belmont.
    ADD_ONS = [
      "Neck, shoulder & back massage", "Feet reflexology", "Abdominal massage",
      "Sinus relief", "TMJ relief", "Scalp massage"
    ].freeze

    # FRS §19.11 plus the OQ-07 decision: essential oil $10; hot stone, hot
    # herbal compression and aromatherapy $15 each. None adds time.
    ENHANCEMENTS = [
      { name: "Essential oil", cents: 1000 },
      # FRS §23: these three come free with the included monthly massage.
      { name: "Hot stone", cents: 1500, complimentary: true },
      { name: "Hot herbal compression", cents: 1500, complimentary: true },
      { name: "Aromatherapy", cents: 1500, complimentary: true }
    ].freeze

    def seed!
      locations = seed_locations
      seed_rooms(locations)
      seed_categories
      seed_massage(locations)
      seed_facials(locations)
      seed_luma_specials(locations)
      seed_add_ons(locations)
      seed_enhancements(locations)
      locations
    end

    def seed_locations
      LOCATIONS.each_with_object({}) do |attrs, acc|
        acc[attrs[:code]] = Location.find_or_create_by!(code: attrs[:code]) do |l|
          l.name = attrs[:name]
          l.opens_at = "09:00"
          l.closes_at = "22:00"
        end
      end
    end

    def seed_rooms(locations)
      ROOMS.each do |code, counts|
        location = locations.fetch(code)
        position = 0
        counts.each do |type, n|
          n.times do |i|
            position += 1
            name = "#{type.to_s.tr('_', ' ').split.map(&:capitalize).join(' ')} #{i + 1}"
            Room.find_or_create_by!(location:, name:) do |r|
              r.room_type = type.to_s
              r.client_capacity = CAPACITY.fetch(type)
              r.exclusive = (type == :head_spa)   # head spa is specialised kit
              r.position = position
            end
          end
        end
      end
    end

    def seed_categories
      CATEGORIES.each do |c|
        ServiceCategory.find_or_create_by!(code: c[:code]) do |sc|
          sc.name = c[:name]
          sc.position = c[:position]
        end
      end
    end

    def category(code) = ServiceCategory.find_by!(code: code)

    # Matched on a code derived from the seeded name, never on the name itself:
    # the Owner can rename a service (feedback 6.1), and a re-run must find the
    # renamed row rather than create a second copy.
    def upsert_service(name, category_code, kind: "standard")
      code = name.parameterize(separator: "_")
      Service.find_or_create_by!(code:) do |s|
        s.name = name
        s.service_category = category(category_code)
        s.kind = kind
      end
    end

    def upsert_variant(service, duration, therapists: 1, capacity: 1, room_type: nil, base: 0)
      ServiceVariant.find_or_create_by!(service:, duration_minutes: duration) do |v|
        v.therapist_count = therapists
        v.required_client_capacity = capacity
        v.requires_room_type = room_type
        v.base_price_cents = base
      end
    end

    def price!(location, variant, cents)
      LocationPrice.find_or_create_by!(location:, service_variant: variant,
                                       effective_from: Date.new(2026, 1, 1)) do |p|
        p.price_cents = cents
      end
    end

    def seed_massage(locations)
      MASSAGE.each do |m|
        service = upsert_service(m[:name], "massage")
        (m[:std].keys | m[:bel].keys).each do |duration|
          variant = upsert_variant(service, duration, therapists: m[:therapists],
                                   capacity: m[:capacity], base: m[:std][duration] || 0)
          %w[lawrence skokie luma].each do |code|
            price!(locations[code], variant, m[:std][duration]) if m[:std][duration]
          end
          price!(locations["belmont"], variant, m[:bel][duration]) if m[:bel][duration]
        end
      end
    end

    def seed_facials(locations)
      FACIAL_COMMON.each do |f|
        service = upsert_service(f[:name], "facial")
        (f[:std].keys | f[:bel].keys).each do |duration|
          variant = upsert_variant(service, duration, base: f[:std][duration] || 0)
          %w[lawrence skokie].each do |code|
            price!(locations[code], variant, f[:std][duration]) if f[:std][duration]
          end
          price!(locations["belmont"], variant, f[:bel][duration]) if f[:bel][duration]
        end
      end

      FACIAL_LUMA.each do |f|
        service = upsert_service(f[:name], "facial")
        f[:prices].each do |duration, cents|
          variant = upsert_variant(service, duration, base: cents)
          price!(locations["luma"], variant, cents)
        end
      end
    end

    def seed_luma_specials(locations)
      LUMA_SPECIAL.each do |s|
        service = upsert_service(s[:name], s[:category])
        s[:prices].each do |duration, cents|
          variant = upsert_variant(service, duration, therapists: s[:therapists],
                                   capacity: s[:capacity], room_type: s[:room_type], base: cents)
          price!(locations["luma"], variant, cents)
        end
      end
    end

    def seed_add_ons(locations)
      ADD_ONS.each do |name|
        service = upsert_service(name, "add_on", kind: "add_on")
        variant = upsert_variant(service, 30, base: 3500)
        %w[lawrence skokie luma].each { |c| price!(locations[c], variant, 3500) }
        price!(locations["belmont"], variant, 4000)
      end
    end

    def seed_enhancements(locations)
      ENHANCEMENTS.each do |e|
        service = upsert_service(e[:name], "enhancement", kind: "enhancement")
        service.update!(complimentary_with_membership: e.fetch(:complimentary, false))
        variant = upsert_variant(service, 0, base: e[:cents])
        locations.each_value { |l| price!(l, variant, e[:cents]) }
      end
    end
  end
end
