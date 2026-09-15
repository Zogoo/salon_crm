# Pre-release decisions from the platform feedback review:
#
# * deposits taken in the salon before a visit are held for the client (a
#   liability) until checkout, where they settle part of the bill;
# * Managers may discount up to a per-location percentage; above it is the
#   Owner's call;
# * seeded services are matched on a stable code, so renaming one from the
#   Services screen and re-running the seeds no longer duplicates it.
class AddDepositsDiscountLimitsAndServiceCodes < ActiveRecord::Migration[8.1]
  def up
    add_column :locations, :manager_discount_limit_percent, :integer, default: 20, null: false

    create_table :deposits do |t|
      t.references :appointment, null: false, foreign_key: true, index: { unique: true }
      t.references :client, null: false, foreign_key: true
      t.references :location, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      t.string :method, null: false
      t.string :reference
      t.string :status, null: false, default: "held"
      t.datetime :received_at, null: false
      t.references :received_by_user, foreign_key: { to_table: :users }
      t.references :applied_order, foreign_key: { to_table: :orders }
      t.integer :fee_cents, null: false, default: 0
      t.integer :refunded_cents, null: false, default: 0
      t.datetime :resolved_at
      t.references :resolved_by_user, foreign_key: { to_table: :users }
      t.string :note
      t.timestamps
    end
    add_index :deposits, %i[location_id status]

    add_column :services, :code, :string
    add_index :services, :code, unique: true

    # Backfill from the current name, so a database seeded before this column
    # existed is matched on the next seed run instead of duplicated.
    taken = {}
    select_rows("SELECT id, name FROM services ORDER BY id").each do |id, name|
      base = name.to_s.parameterize(separator: "_").presence || "service"
      code = taken.key?(base) ? "#{base}_#{id}" : base
      taken[code] = true
      execute "UPDATE services SET code = #{connection.quote(code)} WHERE id = #{id.to_i}"
    end
  end

  def down
    remove_index :services, :code
    remove_column :services, :code
    drop_table :deposits
    remove_column :locations, :manager_discount_limit_percent
  end
end
