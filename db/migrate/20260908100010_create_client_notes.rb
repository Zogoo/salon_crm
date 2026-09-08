class CreateClientNotes < ActiveRecord::Migration[8.1]
  # Doc 02 §3.6. Non-clinical front-desk notes, separately permissioned from
  # care notes — no encryption, because this is "prefers the corner room", not
  # "avoid the left knee".
  def change
    create_table :client_notes do |t|
      t.references :client, null: false, foreign_key: true
      t.text :body, null: false
      t.references :created_by_user, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :client_notes, %i[client_id created_at]
  end
end
