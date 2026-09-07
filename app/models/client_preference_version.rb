# BR-43: updating the preferences form never destroys the previous answers.
class ClientPreferenceVersion < ApplicationRecord
  belongs_to :client
  belongs_to :updated_by_user, class_name: "User", optional: true
end
