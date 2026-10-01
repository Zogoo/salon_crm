# Addendum §5: a card-processing (or similar) fee the desk adds to the client's
# bill. Kept as its own column, not a line item, so it never counts as service
# revenue, never raises the discount ceiling, and is never tipped on.
class AddTransactionFeeToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :transaction_fee_cents, :integer, null: false, default: 0
  end
end
