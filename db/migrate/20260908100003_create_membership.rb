class CreateMembership < ActiveRecord::Migration[8.1]
  def change
    create_table :memberships do |t|
      t.references :client, null: false, foreign_key: true
      # BR-39a: tied to the joining location; using it elsewhere needs an override.
      t.references :location, null: false, foreign_key: true
      t.string  :status, null: false, default: "active"
      t.integer :price_cents, null: false, default: 8000
      t.string  :stripe_subscription_id                   # Release 2; null while billed by hand
      t.references :default_service_variant, foreign_key: { to_table: :service_variants }
      t.datetime :enrolled_at, null: false
      t.datetime :current_period_start, null: false
      t.datetime :current_period_end, null: false
      # Cache of the credit ledger, capped at 3 (BR-38).
      t.integer :credits_balance, null: false, default: 0
      t.datetime :cancellation_requested_at
      t.datetime :cancellation_effective_at
      t.timestamps
    end
    add_index :memberships, %i[client_id status]
    add_index :memberships, :current_period_end

    create_table :membership_cycles do |t|
      t.references :membership, null: false, foreign_key: true
      t.datetime :period_start, null: false
      t.datetime :period_end, null: false
      t.datetime :charged_at
      t.integer :amount_cents, null: false
      t.references :order, foreign_key: true
      t.string  :stripe_invoice_id
      t.boolean :credit_granted, null: false, default: false
      t.boolean :forfeited_to_cap, null: false, default: false
      t.string  :status, null: false, default: "open"
      t.timestamps
    end
    add_index :membership_cycles, %i[membership_id period_start], unique: true

    create_table :membership_credit_transactions do |t|
      t.references :membership, null: false, foreign_key: true
      t.string  :kind, null: false                        # grant | redeem | expire | adjust
      t.integer :amount, null: false                      # signed, in credits
      t.integer :balance_after, null: false
      t.references :appointment, foreign_key: true
      t.references :membership_cycle, foreign_key: true
      t.references :performed_by_user, foreign_key: { to_table: :users }
      # BR-39a: who authorised use away from the home location, kept on the row.
      t.references :cross_location_approved_by_user, foreign_key: { to_table: :users }
      t.datetime :occurred_at, null: false
      t.text    :note
      t.timestamps
    end
  end
end
