module Api
  module V1
    # The menu's top-level grouping and its display order (FRS §19).
    class ServiceCategoriesController < ApplicationController
      def index
        render json: {
          service_categories: ServiceCategory.order(:position).map { |c|
            { id: c.id, code: c.code, name: c.name, position: c.position }
          }
        }
      end
    end
  end
end
