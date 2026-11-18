# Be sure to restart your server when you modify this file.

# Content Security Policy: scripts, styles and fonts only from this app.
# Images may also come from any https host, because equipment photos are
# hotlinked (D17). See the Securing Rails Applications Guide:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self
    policy.img_src     :self, :https
    policy.object_src  :none
    policy.script_src  :self
    policy.style_src   :self
    policy.base_uri    :self
    policy.form_action :self
    policy.frame_ancestors :none
  end

  # Nonces for the importmap script and Turbo's progress bar style. A fresh
  # random nonce per response: the session id is still empty on a visitor's
  # first request, and Turbo ignores nonces when comparing tracked elements.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end
