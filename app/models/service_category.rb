class ServiceCategory < ApplicationRecord
  has_many :services, dependent: :destroy
  validates :name, :code, presence: true
  validates :code, uniqueness: true
end
