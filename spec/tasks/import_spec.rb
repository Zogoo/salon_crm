require "rails_helper"
require "rake"

# FRS §24. The gift card import is the one that matters: a wrong balance, or a
# card silently not imported, is unrecorded liability.
RSpec.describe "massagelab:import" do
  before(:all) do
    Rake::Task.clear
    Rails.application.load_tasks
  end

  before do
    Rake::Task["massagelab:import:clients"].reenable
    Rake::Task["massagelab:import:gift_cards"].reenable
  end

  def write(name, content)
    path = Rails.root.join("tmp", name)
    File.write(path, content)
    path.to_s
  end

  describe "clients" do
    it "creates, dedupes on phone, and skips a row with no phone" do
      existing = create(:client, phone: "+13125551234", first_name: "Old", last_name: "Name")
      path = write("clients_spec.csv", <<~CSV)
        first_name,last_name,phone,email,date_of_birth
        New,Person,(312) 555-9999,new@example.com,1990-01-01
        Updated,Name,+13125551234,updated@example.com,
        No,Phone,,nophone@example.com,
      CSV

      expect { Rake::Task["massagelab:import:clients"].invoke(path) }
        .to change(Client, :count).by(1)

      expect(Client.find_by(phone: "+13125559999").first_name).to eq("New")
      # Phone is the natural key, so the same person is corrected, not duplicated.
      expect(existing.reload.first_name).to eq("Updated")
      expect(Client.where(email: "nophone@example.com")).to be_empty
    end
  end

  describe "gift cards" do
    let!(:location) { create(:location, code: "belmont") }

    it "imports an outstanding balance as a ledger entry, not just a column" do
      path = write("cards_spec.csv", <<~CSV)
        code,balance,location_code,sold_at,buyer_name,buyer_phone
        LEG-1,75.00,belmont,2026-03-14,Buyer,+13125559001
      CSV

      Rake::Task["massagelab:import:gift_cards"].invoke(path)
      card = GiftCard.find_by(code: "LEG-1")

      expect(card.current_balance_cents).to eq(7_500)
      expect(card.ledger_balance_cents).to eq(7_500)
      expect(card).not_to be_drifted
      expect(card.sold_at_location_id).to eq(location.id)
    end

    it "skips a card whose location is unknown rather than guessing" do
      path = write("cards_bad.csv", <<~CSV)
        code,balance,location_code,sold_at,buyer_name,buyer_phone
        LEG-BAD,40.00,nowhere,2026-06-01,Buyer,
      CSV

      expect { Rake::Task["massagelab:import:gift_cards"].invoke(path) }
        .not_to change(GiftCard, :count)
    end

    it "is idempotent — re-running corrects rather than doubling the liability" do
      path = write("cards_twice.csv", <<~CSV)
        code,balance,location_code,sold_at,buyer_name,buyer_phone
        LEG-2,50.00,belmont,2026-03-14,Buyer,
      CSV

      Rake::Task["massagelab:import:gift_cards"].invoke(path)
      Rake::Task["massagelab:import:gift_cards"].reenable
      Rake::Task["massagelab:import:gift_cards"].invoke(path)

      expect(GiftCard.where(code: "LEG-2").count).to eq(1)
      card = GiftCard.find_by(code: "LEG-2")
      expect(card.current_balance_cents).to eq(5_000)
      expect(card.ledger_balance_cents).to eq(5_000)   # not 10_000
    end
  end
end
