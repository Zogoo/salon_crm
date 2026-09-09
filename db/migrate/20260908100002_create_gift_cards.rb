class CreateGiftCards < ActiveRecord::Migration[8.1]
  def change
    create_table :gift_cards do |t|
      t.string  :code, null: false
      t.string  :origin, null: false, default: "physical"   # digital is Release 2
      t.integer :initial_value_cents, null: false
      # Cache of the ledger (BR-25); reconciled nightly.
      t.integer :current_balance_cents, null: false, default: 0
      t.string  :purchase_payment_method, null: false
      t.references :buyer_client, foreign_key: { to_table: :clients }
      t.string  :buyer_name
      t.string  :buyer_phone
      t.references :recipient_client, foreign_key: { to_table: :clients }
      t.string  :recipient_name
      t.string  :recipient_phone
      t.datetime :sold_at, null: false
      t.references :sold_by_user, foreign_key: { to_table: :users }
      # BR-27: liability stays with the selling location forever.
      t.references :sold_at_location, null: false, foreign_key: { to_table: :locations }
      t.datetime :expires_at, null: false
      t.string :status, null: false, default: "active"
      t.timestamps
    end
    add_index :gift_cards, :code, unique: true
    add_index :gift_cards, %i[sold_at_location_id sold_at]
    add_index :gift_cards, :status

    # BR-25: the source of truth. The balance column is a cache of this.
    create_table :gift_card_transactions do |t|
      t.references :gift_card, null: false, foreign_key: true
      t.string  :kind, null: false                          # issue | redeem | refund | adjust | expire
      t.integer :amount_cents, null: false                  # signed
      t.integer :balance_after_cents, null: false
      t.references :order, foreign_key: true
      t.references :appointment, foreign_key: true
      t.references :redeemed_by_client, foreign_key: { to_table: :clients }
      t.references :performed_by_user, foreign_key: { to_table: :users }
      t.references :location, foreign_key: true             # the REDEEMING location
      t.datetime :occurred_at, null: false
      t.text :note
      t.timestamps
    end
    add_index :gift_card_transactions, %i[gift_card_id occurred_at]
  end
end
