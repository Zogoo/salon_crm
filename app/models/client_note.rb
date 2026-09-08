# Non-clinical front-desk notes, separately permissioned from care notes.
class ClientNote < ApplicationRecord
  belongs_to :client
  belongs_to :created_by_user, class_name: "User", optional: true
  validates :body, presence: true
end
