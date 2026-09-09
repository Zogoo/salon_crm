class CreateEarnings < ActiveRecord::Migration[8.1]
  def change
    # FRS §8: the two standing periods are 1st–15th and 16th–end of month.
    create_table :earning_periods do |t|
      t.date    :starts_on, null: false
      t.date    :ends_on, null: false
      t.string  :kind, null: false, default: "semi_monthly"
      t.string  :status, null: false, default: "open"
      t.datetime :locked_at
      t.references :locked_by_user, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :earning_periods, %i[starts_on ends_on], unique: true

    # One row per payable session, or per tip, or per manual correction.
    create_table :earning_lines do |t|
      t.references :staff_profile, null: false, foreign_key: true
      t.references :location, null: false, foreign_key: true
      t.date    :service_date, null: false
      t.string  :source, null: false                      # session | tip | manual
      t.references :appointment, foreign_key: true
      t.references :tip_allocation, foreign_key: true
      # BR-33: which items this line absorbed, so a combined session is explainable.
      t.text    :covers_item_ids, null: false, default: "[]"
      t.integer :duration_minutes                         # the ladder rung; null for tips
      t.integer :quantity, null: false, default: 1
      t.integer :rate_cents                               # snapshot — BR-35
      t.integer :amount_cents, null: false
      t.references :created_by_user, foreign_key: { to_table: :users }
      t.text :note
      t.timestamps
    end
    add_index :earning_lines, %i[staff_profile_id service_date]
    add_index :earning_lines, %i[location_id service_date duration_minutes]

    create_table :earning_statements do |t|
      t.references :earning_period, null: false, foreign_key: true
      t.references :staff_profile, null: false, foreign_key: true
      t.integer :total_sessions, null: false, default: 0
      t.integer :service_earnings_cents, null: false, default: 0
      t.integer :tips_cents, null: false, default: 0
      t.integer :adjustments_cents, null: false, default: 0
      t.integer :gross_amount_cents, null: false, default: 0
      t.datetime :generated_at, null: false
      t.references :approved_by_user, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :earning_statements, %i[earning_period_id staff_profile_id], unique: true

    create_table :earning_adjustments do |t|
      t.references :earning_statement, null: false, foreign_key: true
      t.date    :service_date, null: false
      t.integer :amount_cents, null: false                # signed
      t.string  :reason, null: false
      t.references :created_by_user, foreign_key: { to_table: :users }
      t.timestamps
    end

    # BR-36: managers are flat-monthly and never produce session earnings.
    create_table :manager_payouts do |t|
      t.references :staff_profile, null: false, foreign_key: true
      t.date    :month, null: false
      t.integer :amount_cents, null: false
      t.string  :status, null: false, default: "pending"
      t.datetime :paid_at
      t.timestamps
    end
    add_index :manager_payouts, %i[staff_profile_id month], unique: true

    create_table :staff_monthly_rates do |t|
      t.references :staff_profile, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      t.date    :effective_from, null: false
      t.date    :effective_to
      t.references :created_by_user, foreign_key: { to_table: :users }
      t.text :note
      t.timestamps
    end
    add_index :staff_monthly_rates, %i[staff_profile_id effective_from], unique: true
  end
end
