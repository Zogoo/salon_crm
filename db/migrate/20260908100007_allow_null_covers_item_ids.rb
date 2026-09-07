class AllowNullCoversItemIds < ActiveRecord::Migration[8.1]
  # Rails' `serialize ..., type: Array` treats an empty array as equivalent to
  # nil and writes NULL, so a NOT NULL column can never hold "no items" — which
  # is exactly what a tip line is. The reader coerces NULL back to [].
  def change
    change_column_null :earning_lines, :covers_item_ids, true
    change_column_default :earning_lines, :covers_item_ids, from: "[]", to: nil
  end
end
