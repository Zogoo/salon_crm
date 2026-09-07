class SpaController < ActionController::Base
  def index
    spa_index = Rails.root.join("public", "index.html")
    if spa_index.exist?
      render file: spa_index, layout: false, content_type: "text/html"
    else
      render plain: "Frontend not built. Run: cd frontend && npm run build", status: :service_unavailable
    end
  end
end
