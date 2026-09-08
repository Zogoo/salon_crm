# FRS §24 — import the existing client list and any outstanding gift cards.
#
# Outstanding gift cards matter most: importing them with the wrong balance, or
# not at all, means unrecorded liability (doc 07 risk register). Every import is
# idempotent on a natural key, so a re-run corrects rather than duplicates.
namespace :massagelab do
  namespace :import do
    desc "Import clients from CSV (first_name,last_name,phone,email,date_of_birth,notes)"
    task :clients, [ :path ] => :environment do |_t, args|
      require "csv"
      path = args[:path] or abort "usage: rake 'massagelab:import:clients[/path/to/clients.csv]'"
      created = updated = skipped = 0

      CSV.foreach(path, headers: true) do |row|
        phone = Client.to_e164(row["phone"])
        if phone.blank?
          skipped += 1
          warn "skipped (no phone): #{row.to_h.inspect}"
          next
        end

        # Phone is the natural key — it is the identity everywhere else in the
        # business and the front desk's search key.
        client = Client.find_or_initialize_by(phone:)
        was_new = client.new_record?
        client.assign_attributes(
          first_name: row["first_name"].presence || client.first_name || "Unknown",
          last_name: row["last_name"].presence || client.last_name || "",
          email: row["email"].presence || client.email,
          date_of_birth: row["date_of_birth"].presence || client.date_of_birth
        )
        client.save!
        was_new ? created += 1 : updated += 1
      end

      puts "clients: #{created} created, #{updated} updated, #{skipped} skipped"
    end

    desc "Import appointment history (phone,starts_at,location_code,service,therapist)"
    task :history, [ :path ] => :environment do |_t, args|
      require "csv"
      path = args[:path] or abort "usage: rake 'massagelab:import:history[/path/to/history.csv]'"
      imported = skipped = 0

      CSV.foreach(path, headers: true) do |row|
        client = Client.find_by(phone: Client.to_e164(row["phone"]))
        location = Location.find_by(code: row["location_code"])
        unless client && location
          skipped += 1
          next
        end

        # History is imported as a note on the client rather than as a synthetic
        # appointment: a fabricated appointment would occupy a room and a
        # therapist in the scheduling data and could collide with a real one.
        ClientNote.create!(
          client:,
          body: "Imported visit #{row['starts_at']} at #{location.name}" \
                "#{row['service'].present? ? " — #{row['service']}" : ''}" \
                "#{row['therapist'].present? ? " with #{row['therapist']}" : ''}"
        )
        imported += 1
      end

      puts "history notes: #{imported} imported, #{skipped} skipped (unknown client or location)"
    end

    desc "Import outstanding gift cards (code,balance,location_code,sold_at,buyer_name,buyer_phone)"
    task :gift_cards, [ :path ] => :environment do |_t, args|
      require "csv"
      path = args[:path] or abort "usage: rake 'massagelab:import:gift_cards[/path/to/cards.csv]'"
      created = updated = skipped = 0

      CSV.foreach(path, headers: true) do |row|
        code = row["code"].to_s.strip.upcase
        location = Location.find_by(code: row["location_code"])
        balance = (row["balance"].to_f * 100).round
        if code.blank? || location.nil?
          skipped += 1
          warn "skipped (bad code or location): #{row.to_h.inspect}"
          next
        end

        card = GiftCard.find_or_initialize_by(code:)
        if card.persisted?
          updated += 1
        else
          sold_at = row["sold_at"].present? ? Time.zone.parse(row["sold_at"]) : Time.current
          card.assign_attributes(
            origin: "physical",
            initial_value_cents: balance,
            current_balance_cents: 0,          # set by the ledger entry below
            purchase_payment_method: "other",  # unknown for a historical sale
            buyer_name: row["buyer_name"], buyer_phone: row["buyer_phone"],
            sold_at:, sold_at_location: location,
            expires_at: sold_at + location.gift_card_expiry_months.months,
            status: "active"
          )
          card.save!
          created += 1
        end

        # The ledger is the source of truth (BR-25), so an import writes an
        # opening entry rather than just setting the cached balance.
        ImmediateTransaction.call do
          card.gift_card_transactions.where(kind: "issue").destroy_all
          GiftCardTransaction.create!(
            gift_card: card, kind: "issue", amount_cents: balance,
            balance_after_cents: balance, location:,
            occurred_at: card.sold_at, note: "imported opening balance"
          )
          card.update!(current_balance_cents: balance)
        end
      end

      total = GiftCard.outstanding.sum(:current_balance_cents)
      puts "gift cards: #{created} created, #{updated} updated, #{skipped} skipped"
      puts "outstanding liability now: $#{'%.2f' % (total / 100.0)}"
    end
  end
end
