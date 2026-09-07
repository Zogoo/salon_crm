class CreateSales < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.string  :number, null: false
      t.references :client, foreign_key: true            # nil for an anonymous gift card sale
      t.references :location, null: false, foreign_key: true
      t.references :appointment, foreign_key: true       # nil for standalone sales
      t.integer :subtotal_cents, null: false, default: 0
      t.integer :discount_cents, null: false, default: 0
      t.integer :tax_cents,      null: false, default: 0  # always 0 — BR-47a
      t.integer :tip_cents,      null: false, default: 0
      t.integer :total_cents,    null: false, default: 0
      t.string  :status, null: false, default: "open"
      t.string  :kind,   null: false, default: "service"  # service | gift_card | membership | fee
      t.references :opened_by_user, foreign_key: { to_table: :users }
      t.references :closed_by_user, foreign_key: { to_table: :users }
      t.datetime :closed_at
      t.timestamps
    end
    add_index :orders, :number, unique: true
    add_index :orders, %i[location_id status closed_at]
    add_index :orders, %i[client_id status]

    create_table :order_line_items do |t|
      t.references :order, null: false, foreign_key: true
      t.string  :purchasable_type
      t.bigint  :purchasable_id
      t.string  :description, null: false
      t.integer :quantity, null: false, default: 1
      t.integer :unit_price_cents, null: false, default: 0
      t.integer :line_total_cents, null: false, default: 0
      # BR-48: revenue, liability and fees are three separate categories.
      t.string  :revenue_category, null: false
      t.references :staff_profile, foreign_key: true
      t.timestamps
    end
    add_index :order_line_items, %i[purchasable_type purchasable_id]
    add_index :order_line_items, :revenue_category

    create_table :payments do |t|
      t.references :order, null: false, foreign_key: true
      t.string  :method, null: false                     # card | cash | zelle | online | other
      t.string  :processing, null: false, default: "recorded"
      t.integer :amount_cents, null: false
      t.string  :reference
      t.datetime :received_at, null: false
      t.references :received_by_user, foreign_key: { to_table: :users }
      t.string  :status, null: false, default: "captured"
      t.references :voided_by_user, foreign_key: { to_table: :users }
      t.datetime :voided_at
      t.string  :void_reason
      t.timestamps
    end
    add_index :payments, %i[received_at method status]

    create_table :refunds do |t|
      t.references :order, null: false, foreign_key: true
      t.references :payment, foreign_key: true
      t.integer :amount_cents, null: false
      t.string  :reason, null: false
      t.references :issued_by_user, foreign_key: { to_table: :users }
      t.datetime :issued_at, null: false
      t.timestamps
    end

    create_table :order_discounts do |t|
      t.references :order, null: false, foreign_key: true
      t.string  :kind, null: false                        # manual | membership_upgrade_credit
      t.integer :amount_cents, null: false
      t.references :applied_by_user, foreign_key: { to_table: :users }
      t.string  :reason
      t.timestamps
    end

    # BR-24 / BR-24a: the tip is the therapist's, split evenly across two.
    create_table :tip_allocations do |t|
      t.references :order, null: false, foreign_key: true
      t.references :appointment, foreign_key: true
      t.references :staff_profile, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      t.string  :allocated_by, null: false, default: "system_even_split"
      t.timestamps
    end
    add_index :tip_allocations, %i[staff_profile_id created_at]
  end
end
