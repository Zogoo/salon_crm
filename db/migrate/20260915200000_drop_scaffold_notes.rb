# The `notes` table was the example resource shipped with the project scaffold
# ("replace them with your own domain"). It was never part of the salon's
# workflow — care notes and client notes are — so it goes, with its screen.
class DropScaffoldNotes < ActiveRecord::Migration[8.1]
  def up
    drop_table :notes
  end

  def down
    create_table :notes do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :body
      t.timestamps
    end
  end
end
