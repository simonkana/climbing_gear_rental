class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Unknown or mistyped public_ids get a friendly page in the app layout
  # instead of the framework error page.
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  private
    def render_not_found
      respond_to do |format|
        format.html { render "errors/not_found", status: :not_found }
        format.any { head :not_found }
      end
    end
end
