# Any path no other route matches gets the app's "Page not found" page instead
# of the framework's routing error, in every environment.
#
# Appended here instead of written at the end of config/routes.rb: engine routes
# (Turbo, Active Storage, Action Mailbox) are drawn after the app's own routes,
# so a catch-all there would hide them. Appended blocks run after all route
# files, the same way Rails adds its development welcome page.
Rails.application.routes.append do
  match "*path", to: "errors#not_found", via: :all
end
