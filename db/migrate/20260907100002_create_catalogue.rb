class CreateCatalogue < ActiveRecord::Migration[8.1]
  def change
    create_table :service_categories do |t|
      t.string  :name, null: false
      t.string  :code, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :service_categories, :code, unique: true

    create_table :services do |t|
      t.references :service_category, null: false, foreign_key: true
      t.string  :name, null: false
      t.text    :description
      t.string  :kind, null: false, default: "standard"   # standard | add_on | enhancement
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :services, %i[kind active]

    create_table :service_variants do |t|
      t.references :service, null: false, foreign_key: true
      t.integer :duration_minutes, null: false
      t.integer :therapist_count, null: false, default: 1
      t.integer :required_client_capacity, null: false, default: 1
      t.string  :requires_room_type                       # nil, or head_spa
      t.integer :base_price_cents, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :service_variants, %i[service_id duration_minutes], unique: true

    create_table :location_prices do |t|
      t.references :location, null: false, foreign_key: true
      t.references :service_variant, null: false, foreign_key: true
      t.integer :price_cents, null: false
      t.date    :effective_from, null: false
      t.date    :effective_to
      t.timestamps
    end
    add_index :location_prices, %i[location_id service_variant_id effective_from],
              unique: true, name: "idx_location_prices_lookup"
  end
end
