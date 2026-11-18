# Target of the catch-all route for paths no other route matches
# (config/initializers/not_found_route.rb).
class ErrorsController < ApplicationController
  # Rendering the not found page changes nothing, so an unknown POST gets a
  # 404 instead of an authenticity token error.
  skip_forgery_protection

  def not_found
    render_not_found
  end
end
