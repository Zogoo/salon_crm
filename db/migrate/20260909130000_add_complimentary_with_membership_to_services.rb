# FRS §23: the included monthly massage comes with hot stone, hot herbal
# compression and aromatherapy at no extra charge. Essential oil ($10) is not
# included.
#
# A column rather than matching service names in code: a name is data the Owner
# can edit from the Services screen, and a rename would silently start charging
# members for something that is meant to be free.
class AddComplimentaryWithMembershipToServices < ActiveRecord::Migration[8.1]
  def up
    add_column :services, :complimentary_with_membership, :boolean, null: false, default: false

    # Backfill the three the FRS names.
    execute <<~SQL
      UPDATE services
         SET complimentary_with_membership = 1
       WHERE kind = 'enhancement'
         AND name IN ('Hot stone', 'Hot herbal compression', 'Aromatherapy')
    SQL
  end

  def down
    remove_column :services, :complimentary_with_membership
  end
end
